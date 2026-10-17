import Foundation
import AVFoundation

/// Audio has one explicit source and one independent on/off control.
/// The rain-visual toggle must never silently suspend rain audio.
final class PondSoundController {
    private var ambience: AVAudioPlayer?
    private var effects: [AVAudioPlayer] = []
    private var feedFiles: [URL] = []
    private var lastFeed: TimeInterval = 0
    private var feedIndex = 0
    private(set) var enabled = false
    private var suspended = false
    private(set) var sourceName = "尚未载入"
    private(set) var lastError: String?

    var volume: Float = 0.52 {
        didSet {
            volume = max(0.05, min(volume, 1))
            UserDefaults.standard.set(volume, forKey: "pondRainVolume")
            ambience?.volume = volume
        }
    }
    private var supportDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("LivingPond", isDirectory: true)
    }

    init() {
        if let saved = UserDefaults.standard.object(forKey: "pondRainVolume") as? Float {
            volume = max(0.05, min(saved, 1))
        }
        if let dir = Bundle.main.resourceURL?.appendingPathComponent("Sound", isDirectory: true) {
            feedFiles = (1...2).map { dir.appendingPathComponent("feed-plop-\($0).wav") }
        }
        // First launch of V0.9.4.3 selects the newly bundled *real field
        // recording*, even if a previous release was left on its synthetic
        // rain source. Existing custom audio files are never deleted.
        let migration = "pondRainFieldRecording942"
        if !UserDefaults.standard.bool(forKey:migration) {
            UserDefaults.standard.set(true, forKey:migration)
            UserDefaults.standard.removeObject(forKey:"pondCustomRainFilename")
        }
        _ = loadPreferredRain()
    }

    private func loadPlayer(_ file: URL, description: String) -> Bool {
        guard FileManager.default.fileExists(atPath: file.path) else {
            lastError = "音频文件不存在：\(file.lastPathComponent)"
            return false
        }
        do {
            let player = try AVAudioPlayer(contentsOf: file)
            guard player.duration > 0 else {
                lastError = "音频长度为零：\(file.lastPathComponent)"
                return false
            }
            player.numberOfLoops = -1
            player.volume = volume
            guard player.prepareToPlay() else {
                lastError = "系统未能准备播放：\(file.lastPathComponent)"
                return false
            }
            let previous = ambience
            ambience = player
            sourceName = description
            lastError = nil
            if enabled && !suspended {
                guard player.play() else {
                    ambience = previous
                    lastError = "系统拒绝启动音频播放，请检查音频输出设备。"
                    return false
                }
            }
            previous?.stop()
            return true
        } catch {
            lastError = "无法解码音频：\(error.localizedDescription)"
            NSLog("LivingPond audio: %@", lastError ?? "unknown error")
            return false
        }
    }

    @discardableResult func loadPreferredRain() -> Bool {
        if let dir = supportDirectory,
           let filename = UserDefaults.standard.string(forKey: "pondCustomRainFilename"),
           loadPlayer(dir.appendingPathComponent(filename), description: "导入的雨声") { return true }
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Sound/forest-rain-tim-kahn.m4a") {
            return loadPlayer(bundled, description: "内置真实林间细雨 · Tim Kahn")
        }
        lastError = "程序包缺少内置真实细雨录音"
        return false
    }

    /// Returns human-readable result text, not just an ambiguous Bool.
    func importRain(_ source: URL) -> String? {
        guard let dir = supportDirectory else { lastError = "找不到用户音频目录"; return nil }
        let ext = source.pathExtension.lowercased()
        guard ["mp3", "m4a", "aif", "aiff", "wav", "caf"].contains(ext) else {
            lastError = "不支持该格式，请选择 MP3、M4A 或 WAV"; return nil
        }
        let temporary = dir.appendingPathComponent("rain-import-\(UUID().uuidString).\(ext)")
        let final = dir.appendingPathComponent("personal-rain.\(ext)")
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: temporary)
            let probe = try AVAudioPlayer(contentsOf: temporary)
            guard probe.duration > 0 && probe.prepareToPlay() else {
                lastError = "导入文件无法解码或长度为零"; try? FileManager.default.removeItem(at: temporary); return nil
            }
            // Preserve the previous import until the replacement plays successfully.
            guard loadPlayer(temporary, description: "导入的雨声 · \(source.lastPathComponent)") else {
                try? FileManager.default.removeItem(at: temporary); return nil
            }
            if FileManager.default.fileExists(atPath: final.path) { try FileManager.default.removeItem(at: final) }
            try FileManager.default.moveItem(at: temporary, to: final)
            // The active player was opened on the temporary path; swap to the durable file.
            guard loadPlayer(final, description: "导入的雨声 · \(source.lastPathComponent)") else { return nil }
            UserDefaults.standard.set(final.lastPathComponent, forKey: "pondCustomRainFilename")
            return source.lastPathComponent
        } catch {
            lastError = "导入失败：\(error.localizedDescription)"
            try? FileManager.default.removeItem(at: temporary)
            NSLog("LivingPond rain import: %@", lastError ?? "unknown error")
            return nil
        }
    }

    @discardableResult func useBundledRain() -> Bool {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Sound/forest-rain-tim-kahn.m4a"),
              loadPlayer(url, description: "内置真实林间细雨 · Tim Kahn") else { return false }
        UserDefaults.standard.removeObject(forKey: "pondCustomRainFilename")
        return true
    }

    @discardableResult func setEnabled(_ on: Bool) -> Bool {
        if on && ambience == nil && !loadPreferredRain() { enabled = false; return false }
        enabled = on
        return refresh()
    }
    @discardableResult func setSuspended(_ on: Bool) -> Bool { suspended = on; return refresh() }

    @discardableResult private func refresh() -> Bool {
        if enabled && !suspended {
            if ambience?.isPlaying != true {
                guard ambience?.play() == true else {
                    lastError = "音频播放未启动（请检查 Mac 的声音输出设备与系统音量）"
                    NSLog("LivingPond: %@", lastError ?? "audio error")
                    return false
                }
            }
            lastError = nil
        } else {
            ambience?.pause()
            effects.forEach { $0.stop() }
            effects.removeAll()
        }
        return true
    }
    var isPlaying: Bool { ambience?.isPlaying == true }
    func diagnostic() -> String {
        let secs = String(format: "%.1f", ambience?.duration ?? 0)
        return "音源：\(sourceName)\n长度：\(secs) 秒\n雨声开关：\(enabled ? "开" : "关")\n播放状态：\(isPlaying ? "正在播放" : "未播放")\n音量：\(Int(volume * 100))%" + (lastError.map { "\n错误：\($0)" } ?? "")
    }

    func playFeedingRipple() {
        guard enabled && !suspended && !feedFiles.isEmpty else { return }
        let now = Date.timeIntervalSinceReferenceDate
        guard now-lastFeed > 0.14 else { return }
        lastFeed = now
        let file = feedFiles[feedIndex % feedFiles.count];feedIndex += 1
        do {
            effects.removeAll { !$0.isPlaying }
            if effects.count >= 4 { effects.removeFirst().stop() }
            let player = try AVAudioPlayer(contentsOf: file)
            player.volume = volume * 0.24
            player.prepareToPlay()
            if player.play() { effects.append(player) }
        } catch { NSLog("LivingPond feed sound: %@", error.localizedDescription) }
    }
    func stop() { ambience?.stop(); effects.forEach { $0.stop() }; effects.removeAll() }
}
