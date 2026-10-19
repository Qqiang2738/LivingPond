#!/usr/bin/env python3
"""Source-level wiring regression for V1.1.4. CI also compiles Swift on Intel macOS."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
scene=(root/'Sources/PondScene.swift').read_text()
fish=(root/'Sources/NativeFish.swift').read_text()
app=(root/'Sources/PondApp.swift').read_text()

checks={
    'food jar is interactive': 'class PondFoodJarButton' in app and 'action=#selector(grabFood)' in app,
    'hand must be loaded first': 'guard interactive,feedingArmed else { return }' in app,
    'one handful per grab': 'setFoodInHand(false)' in app and 'setFoodInHand(true)' in app,
    'water click routed through controller': 'pond.onSurfaceClick' in app and 'onSurfaceClick?(event.location(in:self))' in scene,
    'pellets spread at click point': 'for _ in 0..<13' in scene and 'CGFloat.random(in:-31...31)' in scene,
    'different pellet targets': 'feedingAssignments[koi.identity]' in scene and 'refreshFeedingAssignments()' in scene,
    'responsive turn and chase': 'feedingExcitement' in fish and 'let turnRate=maxTurn*' in fish and 'let burst:CGFloat=' in fish,
    'no blocking menu': 'status?.menu = nil' in app,
    'quiet pond unaffected by hand': 'scene?.feed(at:point)' in app and 'guard interactive,feedingArmed' in app,
}
for desc,ok in checks.items():
    if not ok:
        raise AssertionError(desc)
print('PASS feeding UI wiring and per-fish food pursuit (static); native compile follows')
