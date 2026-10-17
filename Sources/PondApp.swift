import AppKit
import CoreGraphics
import SpriteKit
import UniformTypeIdentifiers
import ServiceManagement
import QuartzCore

final class PondDesktopWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// macOS-only native app. Finder remains the owner of the desktop and its icons.
/// This app never modifies Finder, the wallpaper preference, or the Dock.
final class PondApp: NSObject, NSApplicationDelegate {
    private var window: PondDesktopWindow?
    private var view: SKView?
    private var scene: PondScene?
    private var status: NSStatusItem?
    private var interactionMenu: NSMenuItem?
    private var pauseMenu: NSMenuItem?
    private var rainMenu: NSMenuItem?
    private var soundMenu: NSMenuItem?
    private var volumeMenu: NSMenuItem?
    private var volumePresetItems: [NSMenuItem] = []
    private var feedingOverlay: NSVisualEffectView?
    private var overlayAnimationToken = 0
    private var loginMenu: NSMenuItem?
    private var lowPowerMenu: NSMenuItem?
    private var escapeMonitor: Any?
    private let sound = PondSoundController()
    private var interactive = false
    private var paused = false
    private var sleeping = false
    private var rain = (UserDefaults.standard.object(forKey:"pondRainEnabled") as? Bool) ?? true
    private var soundEnabled = UserDefaults.standard.bool(forKey:"pondSoundEnabled")
    private var lowPower = UserDefaults.standard.bool(forKey:"nativePondLowPower")
    private var stabilityMenu: NSMenuItem?
    private var stabilityTimer: Timer?
    private var stabilitySamplesWritten = 0
    private var stabilityActive = false
    private var stabilityLogURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/LivingPond/stability-v1.1.2.log")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        createWindow()
        if !sound.setEnabled(soundEnabled) {
            soundEnabled=false
            UserDefaults.standard.set(false,forKey:"pondSoundEnabled")
            soundMenu?.state = .off
        }
        escapeMonitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
            guard let self=self else { return event }
            if event.keyCode == 53 && self.interactive {
                self.setInteractive(false)
                return nil
            }
            return event
        }
        let nc=NSWorkspace.shared.notificationCenter
        nc.addObserver(self,selector:#selector(willSleep),name:NSWorkspace.willSleepNotification,object:nil)
        nc.addObserver(self,selector:#selector(didWake),name:NSWorkspace.didWakeNotification,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(screensChanged),name:NSApplication.didChangeScreenParametersNotification,object:nil)
        nc.addObserver(self,selector:#selector(spaceChanged),name:NSWorkspace.activeSpaceDidChangeNotification,object:nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        stabilityTimer?.invalidate()
        stabilityTimer = nil
        if stabilityActive {
            flushPendingSlowEvents()
            appendStabilityLog("[结束] 应用退出，采样提前结束")
        }
        if let monitor=escapeMonitor { NSEvent.removeMonitor(monitor) }
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        sound.stop()
        view?.isPaused=true
        window?.orderOut(nil)
        window?.close()
    }

    private func addItem(_ menu:NSMenu, _ label:String, _ selector:Selector?, checked:Bool=false) -> NSMenuItem {
        let item=NSMenuItem(title:label,action:selector,keyEquivalent:"")
        item.target=self
        item.state=checked ? .on : .off
        menu.addItem(item)
        return item
    }

    private func installMenu() {
        status=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        if let button=status?.button {
            if let image=NSImage(systemSymbolName:"fish.fill",accessibilityDescription:"一池清宁") {
                image.isTemplate=true
                button.image=image
            } else { button.title="池" }
            button.toolTip="一池清宁 · 喂鱼、听雨"
        }
        let menu=NSMenu(title:"一池清宁")
        menu.delegate = self
        let heading=addItem(menu,"一池清宁",nil)
        heading.isEnabled=false
        menu.addItem(.separator())

        // The four actions people actually use belong at the top level.
        interactionMenu=addItem(menu,"喂鱼…",#selector(toggleInteractive))
        pauseMenu=addItem(menu,"暂停鱼塘",#selector(togglePause))
        menu.addItem(.separator())
        rainMenu=addItem(menu,"细雨涟漪",#selector(toggleRain),checked:rain)
        soundMenu=addItem(menu,"细雨声",#selector(toggleSound),checked:soundEnabled)
        menu.addItem(.separator())

        // Advanced operations remain available, but do not dominate the menu.
        let more=NSMenu(title:"更多设置")
        let audio=NSMenu(title:"声音选项")
        let levels=NSMenu(title:"音量")
        for pct in [15,30,50,70,100] {
            let item=addItem(levels,"\(pct)%",#selector(changeVolume))
            item.tag=pct
            volumePresetItems.append(item)
        }
        let volumeParent=NSMenuItem(title:"音量",action:nil,keyEquivalent:"")
        audio.addItem(volumeParent)
        audio.setSubmenu(levels,for:volumeParent)
        volumeMenu=volumeParent
        refreshVolumeMenu()
        audio.addItem(.separator())
        _=addItem(audio,"导入自己的雨声…",#selector(importSound))
        _=addItem(audio,"恢复内置雨声",#selector(useBundledSound))
        _=addItem(audio,"检查声音播放状态…",#selector(showAudioStatus))
        let audioParent=NSMenuItem(title:"声音选项",action:nil,keyEquivalent:"")
        more.addItem(audioParent)
        more.setSubmenu(audio,for:audioParent)

        loginMenu=addItem(more,"登录时启动",#selector(toggleLaunchAtLogin),checked:SMAppService.mainApp.status == .enabled)
        lowPowerMenu=addItem(more,"省电模式 · 30 FPS",#selector(toggleLowPower),checked:lowPower)
        more.addItem(.separator())
        let diagnostics=NSMenu(title:"诊断与日志")
        _=addItem(diagnostics,"画面性能…",#selector(showPerformance))
        _=addItem(diagnostics,"重新开始性能采样",#selector(resetPerformance))
        diagnostics.addItem(.separator())
        stabilityMenu=addItem(diagnostics,"开始 30 分钟稳定性记录…",#selector(toggleStabilityMonitoring))
        _=addItem(diagnostics,"查看稳定性日志…",#selector(openStabilityLog))
        let diagnosticsParent=NSMenuItem(title:"诊断与日志",action:nil,keyEquivalent:"")
        more.addItem(diagnosticsParent)
        more.setSubmenu(diagnostics,for:diagnosticsParent)
        more.addItem(.separator())
        _=addItem(more,"关于一池清宁…",#selector(showAbout))
        let moreParent=NSMenuItem(title:"更多设置",action:nil,keyEquivalent:"")
        menu.addItem(moreParent)
        menu.setSubmenu(more,for:moreParent)
        menu.addItem(.separator())
        _=addItem(menu,"退出一池清宁",#selector(quitApp))
        status?.menu=menu
    }

    private func refreshVolumeMenu() {
        let current=Int((sound.volume*100).rounded())
        volumeMenu?.title="音量 · \(current)%"
        for item in volumePresetItems {
            item.state = abs(Int(item.tag)-current) < 1 ? .on : .off
        }
    }

    private func desktopLevel()->NSWindow.Level {
        NSWindow.Level(rawValue:Int(CGWindowLevelForKey(.desktopIconWindow))-1)
    }

    private func createWindow() {
        guard let screen=NSScreen.main ?? NSScreen.screens.first else { return }
        let window=PondDesktopWindow(contentRect:screen.frame,styleMask:[.borderless],backing:.buffered,defer:false,screen:screen)
        window.backgroundColor=NSColor(red:0.04,green:0.18,blue:0.17,alpha:1)
        window.isOpaque=true
        window.hasShadow=false
        window.collectionBehavior=[.canJoinAllSpaces,.stationary,.ignoresCycle,.fullScreenNone]
        window.level=desktopLevel()
        window.ignoresMouseEvents=true
        window.title="一池清宁"

        let container=NSView(frame:NSRect(origin:.zero,size:screen.frame.size))
        container.autoresizingMask=[.width,.height]
        let sk=SKView(frame:container.bounds)
        sk.autoresizingMask=[.width,.height]
        sk.ignoresSiblingOrder=true
        sk.preferredFramesPerSecond=lowPower ? 30 : 60
        sk.showsFPS=false
        sk.showsNodeCount=false
        let pond=PondScene(size:screen.frame.size)
        pond.scaleMode = .resizeFill
        pond.setRainEnabled(rain)
        pond.setLowPower(lowPower)
        pond.onFeeding = { [weak self] in self?.sound.playFeedingRipple() }
        sk.presentScene(pond)
        container.addSubview(sk)

        // One cohesive, native macOS HUD. Unlike the former detached label and
        // button, this view uses a single layout and never touches the Dock.
        let overlay=makeFeedingOverlay()
        overlay.translatesAutoresizingMaskIntoConstraints=false
        overlay.isHidden=true
        overlay.alphaValue=0
        container.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo:container.topAnchor,constant:30),
            overlay.trailingAnchor.constraint(equalTo:container.trailingAnchor,constant:-32),
            overlay.widthAnchor.constraint(equalToConstant:276),
            overlay.heightAnchor.constraint(equalToConstant:54)
        ])
        window.contentView=container
        window.orderFrontRegardless()
        self.window=window
        self.view=sk
        self.scene=pond
        self.feedingOverlay=overlay
    }

    /// Minimal status overlay for the few seconds spent feeding. No debug copy,
    /// no extra windows, and no controls placed near the bottom Dock.
    private func makeFeedingOverlay() -> NSVisualEffectView {
        let effect=NSVisualEffectView(frame:.zero)
        effect.material = .hudWindow
        effect.blendingMode = .withinWindow
        effect.state = .active
        effect.appearance = NSAppearance(named:.darkAqua)
        effect.wantsLayer=true
        effect.layer?.cornerRadius=17
        effect.layer?.masksToBounds=true

        let symbol=NSImageView(frame:.zero)
        symbol.translatesAutoresizingMaskIntoConstraints=false
        symbol.image=NSImage(systemSymbolName:"hand.tap.fill",accessibilityDescription:"投食")
        symbol.contentTintColor=NSColor(calibratedRed:0.86,green:0.88,blue:0.70,alpha:1)
        symbol.imageScaling = .scaleProportionallyDown
        symbol.setContentHuggingPriority(.required,for:.horizontal)

        let title=NSTextField(labelWithString:"喂鱼中")
        title.font=NSFont.systemFont(ofSize:12,weight:.semibold)
        title.textColor=NSColor.white.withAlphaComponent(0.94)
        let hint=NSTextField(labelWithString:"轻点水面，投一把鱼食")
        hint.font=NSFont.systemFont(ofSize:10,weight:.regular)
        hint.textColor=NSColor.white.withAlphaComponent(0.68)
        let texts=NSStackView(views:[title,hint])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing=3
        texts.translatesAutoresizingMaskIntoConstraints=false

        let finish=NSButton(title:"完成",target:self,action:#selector(endInteractiveMode))
        finish.translatesAutoresizingMaskIntoConstraints=false
        finish.isBordered=false
        finish.wantsLayer=true
        finish.layer?.cornerRadius=9
        finish.layer?.backgroundColor=NSColor.white.withAlphaComponent(0.13).cgColor
        finish.attributedTitle=NSAttributedString(string:"完成",attributes:[
            .foregroundColor:NSColor.white.withAlphaComponent(0.92),
            .font:NSFont.systemFont(ofSize:12,weight:.medium)
        ])
        finish.keyEquivalent=""  // Esc is handled separately.
        finish.toolTip="结束喂鱼（Esc）"
        finish.setAccessibilityLabel("完成喂鱼")
        finish.setContentHuggingPriority(.required,for:.horizontal)

        effect.addSubview(symbol)
        effect.addSubview(texts)
        effect.addSubview(finish)
        NSLayoutConstraint.activate([
            symbol.leadingAnchor.constraint(equalTo:effect.leadingAnchor,constant:15),
            symbol.centerYAnchor.constraint(equalTo:effect.centerYAnchor),
            symbol.widthAnchor.constraint(equalToConstant:17),
            symbol.heightAnchor.constraint(equalToConstant:17),
            texts.leadingAnchor.constraint(equalTo:symbol.trailingAnchor,constant:11),
            texts.centerYAnchor.constraint(equalTo:effect.centerYAnchor),
            texts.trailingAnchor.constraint(lessThanOrEqualTo:finish.leadingAnchor,constant:-10),
            finish.trailingAnchor.constraint(equalTo:effect.trailingAnchor,constant:-10),
            finish.centerYAnchor.constraint(equalTo:effect.centerYAnchor),
            finish.widthAnchor.constraint(equalToConstant:55),
            finish.heightAnchor.constraint(equalToConstant:28)
        ])
        return effect
    }

    private func showFeedingOverlay(_ shown:Bool, completion: (() -> Void)? = nil) {
        guard let overlay=feedingOverlay else { return }
        overlayAnimationToken += 1
        let token=overlayAnimationToken
        if shown {
            overlay.alphaValue=0
            overlay.isHidden=false
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name:.easeInEaseOut)
            overlay.animator().alphaValue=shown ? 1 : 0
        }, completionHandler: { [weak self, weak overlay] in
            guard let self=self, token == self.overlayAnimationToken else { return }
            if !shown { overlay?.isHidden=true }
            completion?()
        })
    }

    private func setInteractive(_ value:Bool) {
        guard interactive != value,let window=window else { return }
        // Feeding while paused should be an intentional resume, not a dead click.
        if value && paused { togglePause() }
        interactive=value
        if value {
            // Deliberately temporary, above Finder only while feeding fish.
            window.level = .floating
            window.ignoresMouseEvents=false
            NSApp.activate(ignoringOtherApps:true)
            window.makeKeyAndOrderFront(nil)
            if let view=view { window.makeFirstResponder(view) }
        } else {
            // Let the exit HUD fade before sinking back beneath Finder icons.
            // Mouse input is immediately returned to Finder during the fade.
            window.ignoresMouseEvents=true
        }
        if value {
            showFeedingOverlay(true)
        } else {
            showFeedingOverlay(false) { [weak self, weak window] in
                guard let self=self, let window=window, !self.interactive else { return }
                window.level=self.desktopLevel()
                window.orderFrontRegardless()
            }
        }
        interactionMenu?.title=value ? "结束喂鱼（Esc）" : "喂鱼…"
        // Discard only the transition's wall-clock gap; keep lifetime metrics.
        scene?.setDiagnosticWindowMode(value ? "互动浮层" : "Finder 桌面")
        scene?.resetFrameClock()
        if stabilityActive { appendStabilityLog("[窗口状态] \(value ? "互动浮层" : "Finder 桌面")") }
    }

    @objc private func toggleInteractive() { setInteractive(!interactive) }
    @objc private func endInteractiveMode() { setInteractive(false) }
    @objc private func togglePause() {
        paused.toggle()
        pauseMenu?.title=paused ? "继续鱼塘" : "暂停鱼塘"
        scene?.setUserPaused(paused)
        view?.isPaused=paused || sleeping
        _ = sound.setSuspended(paused || sleeping)
        if stabilityActive { appendStabilityLog("[用户操作] \(paused ? "暂停" : "恢复")") }
        if stabilityActive { flushPendingSlowEvents() }
        scene?.frameMeter.reset()
    }
    @objc private func toggleRain() {
        rain.toggle()
        rainMenu?.state=rain ? .on : .off
        UserDefaults.standard.set(rain,forKey:"pondRainEnabled")
        scene?.setRainEnabled(rain)
        if stabilityActive { appendStabilityLog("[设置切换] 细雨画面=\(rain ? "开" : "关")") }
    }
    @objc private func toggleSound() {
        soundEnabled.toggle()
        if !sound.setEnabled(soundEnabled) {
            soundEnabled=false
            presentAlert(title:"雨声未启动",message:sound.lastError ?? "请检查音源与输出设备。")
        }
        UserDefaults.standard.set(soundEnabled,forKey:"pondSoundEnabled")
        soundMenu?.state=soundEnabled ? .on : .off
    }
    @objc private func toggleLaunchAtLogin() {
        let service=SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else if service.status != .requiresApproval {
                try service.register()
            }
        } catch {
            presentAlert(title:"登录启动设置未完成",message:"macOS 未接受这次更改：\n\(error.localizedDescription)\n\n可在系统设置 → 通用 → 登录项与扩展中检查。")
        }
        loginMenu?.state = service.status == .enabled ? .on : .off
        if service.status == .requiresApproval {
            presentAlert(title:"需要系统批准",message:"请在系统设置 → 通用 → 登录项与扩展中允许「一池清宁」。")
        }
    }

    @objc private func toggleLowPower() {
        lowPower.toggle()
        lowPowerMenu?.state=lowPower ? .on : .off
        UserDefaults.standard.set(lowPower,forKey:"nativePondLowPower")
        view?.preferredFramesPerSecond=lowPower ? 30 : 60
        scene?.setLowPower(lowPower)
        if stabilityActive { flushPendingSlowEvents() }
        scene?.frameMeter.reset()
        if stabilityActive { appendStabilityLog("[帧率设置] \(lowPower ? "30" : "60") FPS") }
    }
    @objc private func changeVolume(_ sender:NSMenuItem) {
        sound.volume=Float(sender.tag)/100
        refreshVolumeMenu()
    }
    @objc private func useBundledSound() {
        if sound.useBundledRain() { presentAlert(title:"音源已切换",message:"已启用随 App 打包的离线雨声。") }
        else { presentAlert(title:"音源不可用",message:sound.lastError ?? "未知错误") }
    }
    @objc private func importSound() {
        let panel=NSOpenPanel()
        panel.title="选择雨声音频"
        panel.allowedContentTypes=["mp3","m4a","wav","aif","aiff","caf"].compactMap { UTType(filenameExtension:$0) }
        panel.allowsMultipleSelection=false
        NSApp.activate(ignoringOtherApps:true)
        guard panel.runModal() == .OK, let url=panel.url else { return }
        if let name=sound.importRain(url) {
            presentAlert(title:"雨声导入成功",message:"音源：\(name)\n\(soundEnabled ? "正在使用新音源。" : "当前声音开关为关闭，开启后即可播放。")")
        } else { presentAlert(title:"导入失败",message:sound.lastError ?? "无法读取音频文件") }
    }
    @objc private func showAudioStatus() { presentAlert(title:"雨声播放状态",message:sound.diagnostic()) }
    @objc private func showPerformance() {
        guard let scene=scene else { return }
        let report=scene.diagnostic(mode: interactive ? "互动浮层" : "Finder 桌面（图标下方）",preferredFPS:view?.preferredFramesPerSecond ?? 60)
        let alert=NSAlert()
        alert.messageText="原生鱼塘性能 · V1.1.2"
        alert.informativeText=report
        alert.addButton(withTitle:"复制报告")
        alert.addButton(withTitle:"关闭")
        NSApp.activate(ignoringOtherApps:true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(report,forType:.string)
        }
        if stabilityActive { flushPendingSlowEvents() }
        scene.frameMeter.reset()
    }
    @objc private func resetPerformance() {
        if stabilityActive { flushPendingSlowEvents() }
        scene?.frameMeter.reset()
    }

    /// Explicitly opt-in. Writes once per minute, never once per frame.
    /// 30 entries give a meaningful long-running picture, not a 15-second sample.
    @objc private func toggleStabilityMonitoring() {
        if stabilityActive {
            stopStabilityMonitoring(completed:false)
            presentAlert(title:"采样已停止",message:"日志已保存到：\n\(stabilityLogURL.path)")
            return
        }
        do {
            try FileManager.default.createDirectory(at:stabilityLogURL.deletingLastPathComponent(),
                                                     withIntermediateDirectories:true)
            guard FileManager.default.createFile(atPath:stabilityLogURL.path,contents:Data()) else {
                presentAlert(title:"无法开始采样",message:"无法新建稳定性日志。请检查 Library/Logs 目录权限。")
                return
            }
            stabilityActive = true
            stabilitySamplesWritten = 0
            scene?.frameMeter.reset()
            appendStabilityLog("[开始] Living Pond V1.1.2 | 目标 30 分钟 | 采样间隔 60 秒")
            appendStabilityLog("[设备] \(ProcessInfo.processInfo.operatingSystemVersionString) | 目标帧率 \(view?.preferredFramesPerSecond ?? 60)")
            appendStabilityLog("[初始环境] 池水=静态 | 细雨画面=\(rain ? "开" : "关") | 窗口=\(interactive ? "互动" : "Finder桌面")")
            stabilityMenu?.title="停止稳定性记录（\(stabilitySamplesWritten)/30）"
            let timer=Timer(timeInterval:60,repeats:true) { [weak self] _ in self?.writeStabilitySnapshot() }
            stabilityTimer=timer
            RunLoop.main.add(timer,forMode:.common)
        } catch {
            presentAlert(title:"无法开始采样",message:error.localizedDescription)
        }
    }

    private func appendStabilityLog(_ message:String) {
        let date=ISO8601DateFormatter().string(from:Date())
        guard let data="\(date)  \(message)\n".data(using:.utf8),
              let handle=FileHandle(forWritingAtPath:stabilityLogURL.path) else { return }
        handle.seekToEndOfFile()
        handle.write(data)
        handle.closeFile()
    }

    /// Flushes a bounded in-memory batch at minute boundaries; no disk IO in update().
    private func flushPendingSlowEvents() {
        guard stabilityActive, let scene=scene else { return }
        let batch=scene.frameMeter.drainSlowEvents()
        if batch.events.isEmpty && batch.omitted == 0 { return }
        let formatter=ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var rows=[String]()
        rows.reserveCapacity(batch.events.count+2)
        rows.append("[长帧事件批次] 事件=\(batch.events.count)，因限额省略=\(batch.omitted)；仅采集 >50ms 的 update 回调间隔")
        for event in batch.events {
            rows.append(String(format:"[长帧] %@ | 间隔=%.1fms | 前一帧逻辑耗时=%.2fms | 前一帧场景阶段耗时=%.2fms | %@",
                               formatter.string(from:event.occurredAt), event.gapMS,
                               event.precedingWorkMS, event.precedingScenePhaseMS, event.context))
        }
        appendStabilityLog(rows.joined(separator:"\n"))
    }

    /// Snapshot CPU and resident memory using ps on a utility queue, never on the
    /// SpriteKit render/update thread. These are approximate periodic measurements.
    private func sampleProcessStats(forMinute minute:Int) {
        let pid=ProcessInfo.processInfo.processIdentifier
        DispatchQueue.global(qos:.utility).async { [weak self] in
            let process=Process()
            process.executableURL=URL(fileURLWithPath:"/bin/ps")
            process.arguments=["-o","%cpu=","-o","rss=","-p",String(pid)]
            let output=Pipe()
            process.standardOutput=output
            process.standardError=Pipe()
            var result="not available"
            do {
                try process.run()
                let data=output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if let string=String(data:data,encoding:.utf8) {
                    let trimmed=string.trimmingCharacters(in:.whitespacesAndNewlines)
                    if !trimmed.isEmpty { result=trimmed }
                }
            } catch { result="ps failed: \(error.localizedDescription)" }
            let summary=result
            DispatchQueue.main.async { [weak self] in
                guard let self=self, self.stabilityActive || self.stabilitySamplesWritten >= 30 else { return }
                self.appendStabilityLog("[进程采样：第 \(minute) 分钟] CPU% / RSS(KB)：\(summary)（近似值）")
            }
        }
    }

    private func writeStabilitySnapshot() {
        guard stabilityActive, let pond=scene else { return }
        stabilitySamplesWritten += 1
        flushPendingSlowEvents()
        let mode=interactive ? "互动浮层" : "Finder 桌面（图标下方）"
        let report=pond.diagnostic(mode:mode,preferredFPS:view?.preferredFramesPerSecond ?? 60)
        let thermal=String(describing:ProcessInfo.processInfo.thermalState)
        appendStabilityLog("[第 \(stabilitySamplesWritten)/30 分钟] 休眠=\(sleeping) | 暂停=\(paused) | 热状态=\(thermal) | 池水=静态 | 细雨画面=\(rain ? "开" : "关")\n\(report)\n---")
        sampleProcessStats(forMinute: stabilitySamplesWritten)
        stabilityMenu?.title="停止稳定性记录（\(stabilitySamplesWritten)/30）"
        if stabilitySamplesWritten >= 30 { stopStabilityMonitoring(completed:true) }
    }

    private func stopStabilityMonitoring(completed:Bool) {
        guard stabilityActive else { return }
        stabilityTimer?.invalidate()
        stabilityTimer=nil
        flushPendingSlowEvents()
        stabilityActive=false
        appendStabilityLog(completed ? "[完成] 30 分钟采样结束" : "[手动停止] 已保留采样数据")
        stabilityMenu?.title="开始 30 分钟稳定性记录…"
    }

    @objc private func openStabilityLog() {
        guard FileManager.default.fileExists(atPath:stabilityLogURL.path) else {
            presentAlert(title:"还没有稳定性日志",message:"先选择「开始 30 分钟稳定性记录…」，再运行鱼塘。")
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([stabilityLogURL])
    }

    @objc private func showAbout() {
        presentAlert(title:"一池清宁 · V1.1.2",
                     message:"静水、锦鲤与细雨。\n\n11 条锦鲤 · 原生 SpriteKit\n菜单栏轻轻控制，桌面图标照常使用。")
    }
    @objc private func quitApp() { NSApp.terminate(nil) }

    private func presentAlert(title:String,message:String) {
        let alert=NSAlert()
        alert.messageText=title
        alert.informativeText=message
        alert.addButton(withTitle:"知道了")
        NSApp.activate(ignoringOtherApps:true)
        alert.runModal()
    }
    @objc private func willSleep() {
        sleeping=true
        scene?.resetFrameClock()
        if stabilityActive { appendStabilityLog("[系统事件] 即将休眠") }
        view?.isPaused=true
        _=sound.setSuspended(true)
    }
    @objc private func didWake() {
        sleeping=false
        scene?.resetFrameClock()
        view?.isPaused=paused
        scene?.setUserPaused(paused)
        _=sound.setSuspended(paused)
        if stabilityActive { appendStabilityLog("[系统事件] 已唤醒") }
    }
    @objc private func screensChanged() {
        guard let screen=NSScreen.main ?? NSScreen.screens.first else { return }
        window?.setFrame(screen.frame,display:true,animate:false)
        scene?.resetFrameClock()
        if stabilityActive { appendStabilityLog("[系统事件] 屏幕布局发生变化") }
    }
    @objc private func spaceChanged() {
        scene?.resetFrameClock()
        if stabilityActive { appendStabilityLog("[系统事件] Space 已切换") }
    }
}

// Sync login status from macOS, including changes made in System Settings.
extension PondApp: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        loginMenu?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}
