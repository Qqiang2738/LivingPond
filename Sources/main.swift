import AppKit

// One-time preference continuity while switching from version-named app bundles
// to the stable bundle identifier "studio.livingpond.app".
// Never migrates the experimental school toggle or auto-registers login items.
private func migrateLegacyPreferencesIfNeeded() {
    let current = UserDefaults.standard
    let marker = "pondPreferencesMigratedV112"
    if current.bool(forKey: marker) { return }
    let legacyBundles = [
        "studio.livingpond.native.v111", "studio.livingpond.native.v110",
        "studio.livingpond.native.v10", "studio.livingpond.native.v096",
        "studio.livingpond.native.v0951", "studio.livingpond.native.v095",
        "studio.livingpond.native.v0945", "studio.livingpond.native.v0944"
    ]
    let keys = ["pondRainEnabled", "pondSoundEnabled", "nativePondLowPower",
                "pondRainVolume", "pondCustomRainFilename", "pondRainFieldRecording942"]
    for key in keys where current.object(forKey: key) == nil {
        for bundle in legacyBundles {
            if let saved = UserDefaults(suiteName: bundle)?.object(forKey: key) {
                current.set(saved, forKey: key)
                break
            }
        }
    }
    current.set(true, forKey: marker)
}

migrateLegacyPreferencesIfNeeded()
let application = NSApplication.shared
let controller = PondApp()
application.delegate = controller
application.setActivationPolicy(.accessory)
application.run()
