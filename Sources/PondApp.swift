import AppKit
import CoreGraphics
import SpriteKit
import UniformTypeIdentifiers
import ServiceManagement
import QuartzCore

// Restrained, opaque-on-glass controls for the nonblocking status popover.
// Never use NSMenu tracking or a second animated window.
private enum PondControlPalette {
    // A fully opaque surface must not sample whichever app sits behind the panel.
    static let panel = NSColor(calibratedRed:0.102,green:0.173,blue:0.174,alpha:1)
    static let text = NSColor(calibratedRed:0.94,green:0.96,blue:0.94,alpha:1)
    static let secondary = NSColor(calibratedRed:0.77,green:0.84,blue:0.80,alpha:1)
    static let accent = NSColor(calibratedRed:0.77,green:0.91,blue:0.82,alpha:1)
    static let subtle = NSColor(calibratedRed:0.68,green:0.78,blue:0.73,alpha:1)
    static let hover = NSColor(calibratedRed:0.43,green:0.63,blue:0.57,alpha:0.18)
    static let border = NSColor(calibratedRed:0.73,green:0.83,blue:0.77,alpha:0.19)
}

private enum PondControlAccessory {
    case none
    case chevron
    case action(String)
    case toggle(Bool)
}

private final class PondControlRow: NSButton {
    private var hoverArea: NSTrackingArea?

    init(label:String, icon:String, code:Int, accessory:PondControlAccessory = .none,
         quiet:Bool = false, target:AnyObject, action:Selector) {
        super.init(frame:.zero)
        self.tag=code
        self.target=target
        self.action=action
        self.title=""
        self.isBordered=false
        self.focusRingType = .none
        self.wantsLayer=true
        self.layer?.cornerRadius=10
        self.layer?.backgroundColor=NSColor.clear.cgColor
        self.setAccessibilityLabel(label)

        let pictogram=NSImageView()
        pictogram.image=NSImage(systemSymbolName:icon, accessibilityDescription:nil)
        pictogram.contentTintColor=quiet ? PondControlPalette.subtle : PondControlPalette.accent
        pictogram.imageScaling = .scaleProportionallyDown
        pictogram.translatesAutoresizingMaskIntoConstraints=false
        addSubview(pictogram)

        let name=NSTextField(labelWithString:label)
        name.font=NSFont.systemFont(ofSize:quiet ? 12.5 : 13.5,
                                    weight:quiet ? .regular : .medium)
        name.textColor=quiet ? PondControlPalette.secondary : PondControlPalette.text
        name.lineBreakMode = .byTruncatingTail
        name.translatesAutoresizingMaskIntoConstraints=false
        addSubview(name)

        NSLayoutConstraint.activate([
            pictogram.leadingAnchor.constraint(equalTo:leadingAnchor,constant:12),
            pictogram.centerYAnchor.constraint(equalTo:centerYAnchor),
            pictogram.widthAnchor.constraint(equalToConstant:17),
            pictogram.heightAnchor.constraint(equalToConstant:17),
            name.leadingAnchor.constraint(equalTo:pictogram.trailingAnchor,constant:11),
            name.centerYAnchor.constraint(equalTo:centerYAnchor)
        ])

        var right:NSView?
        switch accessory {
        case .none:
            break
        case .chevron:
            let image=NSImageView()
            image.image=NSImage(systemSymbolName:"chevron.right",accessibilityDescription:nil)
            image.contentTintColor=PondControlPalette.secondary
            image.translatesAutoresizingMaskIntoConstraints=false
            addSubview(image)
            NSLayoutConstraint.activate([
                image.widthAnchor.constraint(equalToConstant:9),
                image.heightAnchor.constraint(equalToConstant:12)
            ])
            right=image
        case .action(let caption):
            let value=NSTextField(labelWithString:caption)
            value.font=NSFont.systemFont(ofSize:11.5,weight:.medium)
            value.textColor=PondControlPalette.accent
            value.translatesAutoresizingMaskIntoConstraints=false
            addSubview(value)
            right=value
        case .toggle(let on):
            let track=NSView()
            track.wantsLayer=true
            track.layer?.backgroundColor=(on
                 ? PondControlPalette.accent
                 : NSColor(calibratedRed:0.39,green:0.47,blue:0.46,alpha:1)).cgColor
            track.layer?.cornerRadius=10
            track.translatesAutoresizingMaskIntoConstraints=false
            let knob=NSView()
            knob.wantsLayer=true
            knob.layer?.backgroundColor=(on
                 ? NSColor(calibratedRed:0.12,green:0.25,blue:0.22,alpha:1)
                 : NSColor(calibratedWhite:0.87,alpha:1)).cgColor
            knob.layer?.cornerRadius=7
            knob.translatesAutoresizingMaskIntoConstraints=false
            track.addSubview(knob)
            addSubview(track)
            NSLayoutConstraint.activate([
                track.widthAnchor.constraint(equalToConstant:34),
                track.heightAnchor.constraint(equalToConstant:20),
                knob.widthAnchor.constraint(equalToConstant:14),
                knob.heightAnchor.constraint(equalToConstant:14),
                knob.centerYAnchor.constraint(equalTo:track.centerYAnchor)
            ])
            if on {
                knob.trailingAnchor.constraint(equalTo:track.trailingAnchor,constant:-3).isActive=true
            } else {
                knob.leadingAnchor.constraint(equalTo:track.leadingAnchor,constant:3).isActive=true
            }
            setAccessibilityLabel(label + (on ? "，已开启" : "，已关闭"))
            right=track
        }
        if let trailing=right {
            NSLayoutConstraint.activate([
                trailing.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-13),
                trailing.centerYAnchor.constraint(equalTo:centerYAnchor),
                name.trailingAnchor.constraint(lessThanOrEqualTo:trailing.leadingAnchor,constant:-8)
            ])
        } else {
            name.trailingAnchor.constraint(lessThanOrEqualTo:trailingAnchor,constant:-12).isActive=true
        }
    }

    required init?(coder:NSCoder) { fatalError("Use init(label:icon:code:accessory:quiet:target:action:)") }

    override func updateTrackingAreas() {
        if let old=hoverArea { removeTrackingArea(old) }
        let area=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],
                                owner:self,userInfo:nil)
        addTrackingArea(area)
        hoverArea=area
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event:NSEvent) {
        layer?.backgroundColor=PondControlPalette.hover.cgColor
    }
    override func mouseExited(with event:NSEvent) {
        layer?.backgroundColor=NSColor.clear.cgColor
    }
}

/// Tiny hand-drawn ceramic food jar. It is part of the existing feeding HUD,
/// not another window and not an image asset loaded every frame.
private final class PondFoodJarButton: NSButton {
    var hasFood=false { didSet { needsDisplay=true } }

    override func draw(_ dirtyRect:NSRect) {
        let outer=NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:11,yRadius:11)
        (hasFood
         ? NSColor(calibratedRed:0.38,green:0.46,blue:0.33,alpha:1)
         : NSColor(calibratedRed:0.19,green:0.31,blue:0.28,alpha:1)).setFill()
        outer.fill()
        NSColor(calibratedRed:0.64,green:0.76,blue:0.62,alpha:0.55).setStroke()
        outer.lineWidth=0.7
        outer.stroke()

        let center=bounds.midX
        let body=NSBezierPath(roundedRect:NSRect(x:center-12,y:10,width:24,height:28),
                              xRadius:5,yRadius:5)
        NSColor(calibratedRed:0.66,green:0.55,blue:0.39,alpha:1).setFill()
        body.fill()
        let label=NSBezierPath(roundedRect:NSRect(x:center-9,y:15,width:18,height:15),
                               xRadius:3,yRadius:3)
        NSColor(calibratedRed:0.87,green:0.77,blue:0.56,alpha:1).setFill()
        label.fill()
        let lid=NSBezierPath(roundedRect:NSRect(x:center-14,y:34,width:28,height:8),
                             xRadius:3,yRadius:3)
        NSColor(calibratedRed:0.79,green:0.66,blue:0.47,alpha:1).setFill()
        lid.fill()
        for (x,y) in [(-4.0,-3.0),(4.0,0.0),(0.0,4.0)] {
            let grain=NSBezierPath(ovalIn:NSRect(x:center+x-1.7,y:21+y-1.7,width:3.4,height:3.4))
            NSColor(calibratedRed:0.52,green:0.35,blue:0.20,alpha:1).setFill()
            grain.fill()
        }
        if hasFood {
            for (x,y) in [(-16.0,46.0),(-4.0,49.0),(11.0,47.0)] {
                let fleck=NSBezierPath(ovalIn:NSRect(x:center+x,y:y,width:3.7,height:2.8))
                NSColor(calibratedRed:0.95,green:0.78,blue:0.45,alpha:1).setFill()
                fleck.fill()
            }
        }
    }
}

/// The closed-hand cursor marks a loaded handful. No polling and no cursor
/// image allocations during SpriteKit's update loop.
private final class PondFeedingView: SKView {
    var foodReady=false { didSet { window?.invalidateCursorRects(for:self) } }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds,cursor:foodReady ? .closedHand : .arrow)
    }
}

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
    // Keep NSMenuItems as lightweight state holders, but never attach an NSMenu
    // to the status item. Native menu tracking interrupts the pond render loop.
    private var menuState: NSMenu?
    private var controlPopover: NSPopover?
    private enum ControlPage { case home, settings, audio, diagnostics }
    private var controlPage: ControlPage = .home
    private var interactionMenu: NSMenuItem?
    private var pauseMenu: NSMenuItem?
    private var rainMenu: NSMenuItem?
    private var soundMenu: NSMenuItem?
    private var volumeMenu: NSMenuItem?
    private var volumePresetItems: [NSMenuItem] = []
    private var feedingOverlay: NSView?
    private var foodJarButton: PondFoodJarButton?
    private var feedingHintLabel: NSTextField?
    private var feedingArmed = false
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
        menuState = menu
        // Clicking the menu-bar icon shows a non-modal AppKit popover instead.
        // In particular: never set status.menu, which enters menu-tracking mode.
        status?.menu = nil
        status?.button?.target = self
        status?.button?.action = #selector(toggleControlPopover)
    }

    /// The control surface is a transient NSViewController, not an NSMenu.
    /// Status-menu tracking can starve a continuously rendering SpriteKit scene;
    /// a non-modal popover leaves the ordinary app run loop in charge.
    @objc private func toggleControlPopover() {
        if let existing = controlPopover, existing.isShown {
            existing.performClose(nil)
            return
        }
        guard let button = status?.button else { return }
        let pop = controlPopover ?? NSPopover()
        pop.behavior = .transient
        pop.animates = false
        // Also keep the system-drawn arrow and chrome in a dark appearance.
        pop.appearance = NSAppearance(named:.darkAqua)
        pop.delegate = self
        controlPopover = pop
        loginMenu?.state = SMAppService.mainApp.status == .enabled ? .on : .off
        showControlPage(.home)
        // Do not force activation of the fullscreen desktop window.
        pop.show(relativeTo:button.bounds, of:button, preferredEdge:.minY)
    }

    private func showControlPage(_ page:ControlPage) {
        controlPage=page
        let width:CGFloat=304
        let rowWidth:CGFloat=width-32
        // NSVisualEffectView's behindWindow blending allowed white web pages
        // and bright editor windows to wash out the entire control palette.
        // A plain layer-backed NSView is intentionally fully opaque.
        let background=NSView(frame:NSRect(x:0,y:0,width:width,height:1))
        background.appearance=NSAppearance(named:.darkAqua)
        background.wantsLayer=true
        background.layer?.backgroundColor=PondControlPalette.panel.cgColor
        background.layer?.cornerRadius=16
        background.layer?.masksToBounds=true
        background.layer?.borderColor=PondControlPalette.border.cgColor
        background.layer?.borderWidth=0.8

        let stack=NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing=0
        stack.translatesAutoresizingMaskIntoConstraints=false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo:background.leadingAnchor,constant:16),
            stack.trailingAnchor.constraint(equalTo:background.trailingAnchor,constant:-16),
            stack.topAnchor.constraint(equalTo:background.topAnchor,constant:15)
        ])
        var contentHeight:CGFloat=0

        func space(_ pts:CGFloat) {
            let v=NSView()
            v.translatesAutoresizingMaskIntoConstraints=false
            v.heightAnchor.constraint(equalToConstant:pts).isActive=true
            stack.addArrangedSubview(v)
            contentHeight += pts
        }
        func divider() {
            let line=NSView()
            line.wantsLayer=true
            line.layer?.backgroundColor=PondControlPalette.border.cgColor
            line.translatesAutoresizingMaskIntoConstraints=false
            NSLayoutConstraint.activate([
                line.widthAnchor.constraint(equalToConstant:rowWidth),
                line.heightAnchor.constraint(equalToConstant:1)
            ])
            stack.addArrangedSubview(line)
            contentHeight += 1
        }
        func row(_ label:String,_ icon:String,_ code:Int,_ accessory:PondControlAccessory = .none,
                 quiet:Bool=false,height:CGFloat=42) {
            let button=PondControlRow(label:label,icon:icon,code:code,accessory:accessory,
                                      quiet:quiet,target:self,action:#selector(controlAction(_:)))
            button.translatesAutoresizingMaskIntoConstraints=false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant:rowWidth),
                button.heightAnchor.constraint(equalToConstant:height)
            ])
            stack.addArrangedSubview(button)
            contentHeight += height
        }
        func heading(_ text:String, hasBack:Bool) {
            let container=NSView()
            container.translatesAutoresizingMaskIntoConstraints=false
            let title=NSTextField(labelWithString:text)
            title.font=NSFont.systemFont(ofSize:15.5,weight:.semibold)
            title.textColor=PondControlPalette.text
            title.translatesAutoresizingMaskIntoConstraints=false
            container.addSubview(title)
            NSLayoutConstraint.activate([
                container.widthAnchor.constraint(equalToConstant:rowWidth),
                container.heightAnchor.constraint(equalToConstant:32),
                title.centerYAnchor.constraint(equalTo:container.centerYAnchor)
            ])
            if hasBack {
                let back=NSButton(title:"",target:self,action:#selector(controlAction(_:)))
                back.tag=91
                back.isBordered=false
                back.focusRingType = .none
                back.image=NSImage(systemSymbolName:"chevron.left",accessibilityDescription:"返回")
                back.contentTintColor=PondControlPalette.accent
                back.setAccessibilityLabel("返回更多设置")
                back.translatesAutoresizingMaskIntoConstraints=false
                container.addSubview(back)
                NSLayoutConstraint.activate([
                    back.leadingAnchor.constraint(equalTo:container.leadingAnchor,constant:0),
                    back.centerYAnchor.constraint(equalTo:container.centerYAnchor),
                    back.widthAnchor.constraint(equalToConstant:26),
                    back.heightAnchor.constraint(equalToConstant:28),
                    title.leadingAnchor.constraint(equalTo:back.trailingAnchor,constant:6)
                ])
                if page == .settings { back.tag=90; back.setAccessibilityLabel("返回") }
            } else {
                let icon=NSImageView()
                icon.image=NSImage(systemSymbolName:"fish.fill",accessibilityDescription:nil)
                icon.contentTintColor=PondControlPalette.accent
                icon.translatesAutoresizingMaskIntoConstraints=false
                container.addSubview(icon)
                NSLayoutConstraint.activate([
                    icon.leadingAnchor.constraint(equalTo:container.leadingAnchor,constant:8),
                    icon.centerYAnchor.constraint(equalTo:container.centerYAnchor),
                    icon.widthAnchor.constraint(equalToConstant:18),
                    icon.heightAnchor.constraint(equalToConstant:18),
                    title.leadingAnchor.constraint(equalTo:icon.trailingAnchor,constant:10)
                ])
            }
            stack.addArrangedSubview(container)
            contentHeight += 32
        }
        switch page {
        case .home:
            heading("一池清宁",hasBack:false)
            space(10); divider(); space(8)
            row(interactive ? "结束喂鱼" : "喂鱼","hand.tap.fill",1,.action(interactive ? "完成" : "开始"))
            row(paused ? "继续鱼塘" : "暂停鱼塘",paused ? "play.fill" : "pause.fill",2)
            row("细雨涟漪","cloud.drizzle.fill",3,.toggle(rain))
            row("细雨声",soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",4,.toggle(soundEnabled))
            space(9); divider(); space(5)
            row("更多设置","slider.horizontal.3",10,.chevron,quiet:true)
            row("退出一池清宁","power",5,quiet:true,height:38)
        case .settings:
            heading("更多设置",hasBack:true)
            space(10); divider(); space(8)
            row("声音选项","speaker.wave.2",11,.chevron)
            row("登录时启动","arrow.clockwise",6,.toggle(SMAppService.mainApp.status == .enabled))
            row("省电模式 · 30 FPS","leaf",7,.toggle(lowPower))
            row("诊断与日志","chart.xyaxis.line",12,.chevron)
            space(8); divider(); space(6)
            row("关于一池清宁","info.circle",15,quiet:true,height:38)
        case .audio:
            heading("声音选项",hasBack:true)
            space(10); divider(); space(12)
            let caption=NSTextField(labelWithString:"细雨音量")
            caption.font=NSFont.systemFont(ofSize:11.5,weight:.medium)
            caption.textColor=PondControlPalette.secondary
            caption.translatesAutoresizingMaskIntoConstraints=false
            caption.heightAnchor.constraint(equalToConstant:20).isActive=true
            stack.addArrangedSubview(caption)
            contentHeight += 20
            space(5)
            let levels=NSStackView()
            levels.orientation = .horizontal
            levels.spacing=5
            levels.alignment = .centerY
            levels.distribution = .fillEqually
            levels.translatesAutoresizingMaskIntoConstraints=false
            let volume=Int((sound.volume*100).rounded())
            for pct in [15,30,50,70,100] {
                let chosen=pct == volume
                let chip=NSButton(title:"\(pct)%",target:self,action:#selector(controlAction(_:)))
                chip.tag=1000+pct
                chip.isBordered=false
                chip.focusRingType = .none
                chip.wantsLayer=true
                chip.layer?.cornerRadius=8
                chip.layer?.backgroundColor=(chosen
                    ? NSColor(calibratedRed:0.37,green:0.58,blue:0.48,alpha:0.45)
                    : NSColor(calibratedWhite:1,alpha:0.07)).cgColor
                chip.attributedTitle=NSAttributedString(string:"\(pct)%",attributes:[
                    .font:NSFont.systemFont(ofSize:11.5,weight:chosen ? .semibold : .medium),
                    .foregroundColor:chosen ? PondControlPalette.text : PondControlPalette.secondary
                ])
                chip.setAccessibilityLabel("雨声音量 \(pct)%")
                chip.translatesAutoresizingMaskIntoConstraints=false
                chip.heightAnchor.constraint(equalToConstant:34).isActive=true
                levels.addArrangedSubview(chip)
            }
            NSLayoutConstraint.activate([
                levels.widthAnchor.constraint(equalToConstant:rowWidth),
                levels.heightAnchor.constraint(equalToConstant:34)
            ])
            stack.addArrangedSubview(levels)
            contentHeight += 34
            space(12); divider(); space(6)
            row("导入自己的雨声","square.and.arrow.down",8,.chevron)
            row("恢复内置雨声","arrow.uturn.backward",9)
            row("检查播放状态","waveform",13,quiet:true)
        case .diagnostics:
            heading("诊断与日志",hasBack:true)
            space(10); divider(); space(8)
            row("画面性能","speedometer",14,.chevron)
            row("重新开始性能采样","arrow.counterclockwise",16)
            row(stabilityActive ? "停止稳定性记录" : "开始 30 分钟记录","clock",17)
            row("查看稳定性日志","doc.text.magnifyingglass",18,.chevron)
        }

        let height:CGFloat=contentHeight+30
        background.setFrameSize(NSSize(width:width,height:height))
        let controller=NSViewController()
        controller.view=background
        controller.preferredContentSize=background.frame.size
        controlPopover?.contentViewController=controller
        controlPopover?.contentSize=background.frame.size
    }

    /// Keep switches and volume controls in place; only dismiss when leaving
    /// the control surface for a modal task or for desktop feeding.
    @objc private func controlAction(_ sender:NSButton) {
        switch sender.tag {
        case 10: showControlPage(.settings); return
        case 11: showControlPage(.audio); return
        case 12: showControlPage(.diagnostics); return
        case 90: showControlPage(.home); return
        case 91: showControlPage(.settings); return
        case 2: togglePause(); showControlPage(.home); return
        case 3: toggleRain(); showControlPage(.home); return
        case 4: toggleSound(); showControlPage(.home); return
        case 7: toggleLowPower(); showControlPage(.settings); return
        case 1015,1030,1050,1070,1100:
            let selection=NSMenuItem(title:"",action:nil,keyEquivalent:"")
            selection.tag=sender.tag-1000
            changeVolume(selection)
            showControlPage(.audio)
            return
        default: break
        }
        controlPopover?.performClose(nil)
        switch sender.tag {
        case 1: toggleInteractive()
        case 5: quitApp()
        case 6: toggleLaunchAtLogin()
        case 8: importSound()
        case 9: useBundledSound()
        case 13: showAudioStatus()
        case 14: showPerformance()
        case 15: showAbout()
        case 16: resetPerformance()
        case 17: toggleStabilityMonitoring()
        case 18: openStabilityLog()
        default: break
        }
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
        let sk=PondFeedingView(frame:container.bounds)
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
        pond.onSurfaceClick = { [weak self] point in self?.scatterFoodAt(point) }
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
            overlay.widthAnchor.constraint(equalToConstant:346),
            overlay.heightAnchor.constraint(equalToConstant:86)
        ])
        window.contentView=container
        window.orderFrontRegardless()
        self.window=window
        self.view=sk
        self.scene=pond
        self.feedingOverlay=overlay
    }

    /// A small permanent-position HUD appears only while feeding.
    /// The jar is a real clickable control; the fish pond stays unobstructed.
    private func makeFeedingOverlay() -> NSView {
        let hud=NSView(frame:.zero)
        hud.wantsLayer=true
        hud.layer?.backgroundColor=NSColor(calibratedRed:0.102,green:0.173,
                                            blue:0.174,alpha:0.97).cgColor
        hud.layer?.cornerRadius=17
        hud.layer?.masksToBounds=true
        hud.layer?.borderWidth=0.8
        hud.layer?.borderColor=NSColor(calibratedRed:0.72,green:0.84,
                                       blue:0.77,alpha:0.22).cgColor

        let jar=PondFoodJarButton(frame:.zero)
        jar.isBordered=false
        jar.title=""
        jar.focusRingType = .none
        jar.target=self
        jar.action=#selector(grabFood)
        jar.toolTip="抓取一把鱼食"
        jar.setAccessibilityLabel("鱼食罐，点击抓一把鱼食")
        jar.translatesAutoresizingMaskIntoConstraints=false

        let title=NSTextField(labelWithString:"鱼食罐")
        title.font=NSFont.systemFont(ofSize:13,weight:.semibold)
        title.textColor=NSColor(calibratedWhite:0.94,alpha:1)
        title.translatesAutoresizingMaskIntoConstraints=false

        let hint=NSTextField(labelWithString:"点击小罐，抓取一把鱼食")
        hint.font=NSFont.systemFont(ofSize:11,weight:.regular)
        hint.textColor=NSColor(calibratedRed:0.73,green:0.85,blue:0.78,alpha:1)
        hint.translatesAutoresizingMaskIntoConstraints=false
        hint.lineBreakMode = .byTruncatingTail

        let finish=NSButton(title:"完成",target:self,action:#selector(endInteractiveMode))
        finish.translatesAutoresizingMaskIntoConstraints=false
        finish.isBordered=false
        finish.focusRingType = .none
        finish.wantsLayer=true
        finish.layer?.cornerRadius=9
        finish.layer?.backgroundColor=NSColor.white.withAlphaComponent(0.13).cgColor
        finish.attributedTitle=NSAttributedString(string:"完成",attributes:[
            .foregroundColor:NSColor.white.withAlphaComponent(0.92),
            .font:NSFont.systemFont(ofSize:12,weight:.medium)
        ])
        finish.keyEquivalent=""
        finish.toolTip="结束喂鱼（Esc）"
        finish.setAccessibilityLabel("完成喂鱼")

        hud.addSubview(jar)
        hud.addSubview(title)
        hud.addSubview(hint)
        hud.addSubview(finish)
        NSLayoutConstraint.activate([
            jar.leadingAnchor.constraint(equalTo:hud.leadingAnchor,constant:13),
            jar.centerYAnchor.constraint(equalTo:hud.centerYAnchor),
            jar.widthAnchor.constraint(equalToConstant:62),
            jar.heightAnchor.constraint(equalToConstant:62),
            title.leadingAnchor.constraint(equalTo:jar.trailingAnchor,constant:12),
            title.topAnchor.constraint(equalTo:hud.topAnchor,constant:21),
            hint.leadingAnchor.constraint(equalTo:title.leadingAnchor),
            hint.topAnchor.constraint(equalTo:title.bottomAnchor,constant:6),
            hint.trailingAnchor.constraint(lessThanOrEqualTo:finish.leadingAnchor,constant:-5),
            finish.trailingAnchor.constraint(equalTo:hud.trailingAnchor,constant:-12),
            finish.centerYAnchor.constraint(equalTo:hud.centerYAnchor),
            finish.widthAnchor.constraint(equalToConstant:52),
            finish.heightAnchor.constraint(equalToConstant:29)
        ])
        foodJarButton=jar
        feedingHintLabel=hint
        return hud
    }

    @objc private func grabFood() {
        guard interactive else { return }
        setFoodInHand(true)
    }

    private func setFoodInHand(_ loaded:Bool) {
        feedingArmed=loaded
        foodJarButton?.hasFood=loaded
        feedingHintLabel?.stringValue=loaded
            ? "点击水面，撒下一把"
            : "点击小罐，抓取一把鱼食"
        (view as? PondFeedingView)?.foodReady=loaded
    }

    private func scatterFoodAt(_ point:CGPoint) {
        guard interactive,feedingArmed else { return }
        scene?.feed(at:point)
        // One handful per pick-up; prevents accidental uncontrolled feeding.
        setFoodInHand(false)
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
        setFoodInHand(false)
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

// The popover disappears when the user clicks outside, including on the pond.
// The clock reset is defensive only; avoiding NSMenu tracking is the real change.
extension PondApp: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        scene?.resetFrameClock()
    }
}
