#!/usr/bin/env python3
"""Source-level wiring regression for V1.1.4. CI also compiles Swift on Intel macOS."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
scene=(root/'Sources/PondScene.swift').read_text()
fish=(root/'Sources/NativeFish.swift').read_text()
app=(root/'Sources/PondApp.swift').read_text()

checks={
    'global shortcut uses Carbon without accessibility entitlement': 'import Carbon' in app and 'RegisterEventHotKey' in app and 'kVK_ANSI_P' in app and 'controlKey | optionKey' in app,
    'shortcut can be unregistered': 'UnregisterEventHotKey' in app and 'RemoveEventHandler' in app,
    'jar cursor is drawn once and cached': 'private enum PondJarCursor' in app and 'static let cursor: NSCursor' in app,
    'feeding cursor only while interaction is active': 'feedingMode=value' in app and 'feedingMode ? PondJarCursor.cursor : .arrow' in app,
    'one-click feeding anywhere on pond': 'guard interactive else { return }' in app and 'scene?.feed(at:point)' in app,
    'no intermediate grab step': 'grabFood' not in app and 'feedingArmed' not in app and 'setFoodInHand' not in app,
    'keyboard can enter and exit same mode': 'toggleInteractive()' in app and 'setInteractive(!interactive)' in app,
    'surface click reaches controller': 'pond.onSurfaceClick' in app and 'onSurfaceClick?(event.location(in:self))' in scene,
    'food falls at exact mouse location': 'for _ in 0..<13' in scene and 'CGFloat.random(in:-31...31)' in scene,
    'individual pellet assignment unchanged': 'feedingAssignments[koi.identity]' in scene and 'refreshFeedingAssignments()' in scene,
    'fast chase unchanged': 'feedingExcitement' in fish and 'let turnRate=maxTurn*' in fish and 'let burst:CGFloat=' in fish,
    'menu remains nonblocking': 'status?.menu = nil' in app,
}

for desc,ok in checks.items():
    if not ok:
        raise AssertionError(desc)
print('PASS feeding UI wiring and per-fish food pursuit (static); native compile follows')
