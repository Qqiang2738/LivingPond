#!/usr/bin/env python3
"""Linux-side static regression checks; not a macOS native compile."""
from pathlib import Path
from PIL import Image
import plistlib, hashlib, re, subprocess, json
p=Path(__file__).resolve().parents[1]
info=plistlib.loads((p/'Info.plist').read_bytes())
assert info['CFBundleIdentifier']=='studio.livingpond.app'
assert info['CFBundleShortVersionString']=='1.1.5'
assert info['CFBundleVersion']=='11151'
assert info['CFBundleDisplayName']=='一池清宁'
assert info['CFBundleIconFile']=='AppIcon'
assert info['LSUIElement'] and info['LSMinimumSystemVersion']=='13.0'
assert not list(p.rglob('*.command'))
assert not (p/'Sources/SchoolFish.swift').exists()
for fn in ('Install-V112.sh','Diagnostics-V112.sh','Review-Old-Versions.sh'):
    assert (p/fn).exists(),fn
    subprocess.run(['bash','-n',str(p/fn)],check=True)
installer=(p/'Install-V112.sh').read_text()
assert '一池清宁.app' in installer and 'LivingPond Native V1' not in installer
assert 'xcrun swiftc -O' in installer
assert 'iconutil -c icns' in installer and 'codesign --verify --deep --strict' in installer
assert 'AppBackups' in installer
assert 'Review-Old-Versions.sh' not in installer
cleaner=(p/'Review-Old-Versions.sh').read_text()
assert 'MOVE TO TRASH' in cleaner and '"--trash"' in cleaner
assert '/bin/mv "$item" "$target"' in cleaner
assert '/bin/rm' not in cleaner and 'rm -rf' not in cleaner
for size in (16,32,128,256,512):
    for scale in (1,2):
        suffix='@2x' if scale==2 else ''
        f=p/f'Resources/AppIcon.iconset/icon_{size}x{size}{suffix}.png'
        with Image.open(f) as im:
            assert im.size==(size*scale,size*scale),(f,im.size)
            assert im.mode=='RGBA'
assert Image.open(p/'Resources/AppIcon-1024.png').size == (1024,1024)
assert Image.open(p/'preview/AppIcon-1024.png').size == (1024,1024)
assert not (p/'Resources/AppIcon.svg').exists(), 'Stale old icon SVG'
for i in range(6):
    with Image.open(p/f'Resources/Art/leaf-{i}.png') as im: assert im.mode=='RGBA' and im.getextrema()[3][0]==0
for i in range(3):
    with Image.open(p/f'Resources/Art/lotus-{i}.png') as im: assert im.mode=='RGBA' and im.getextrema()[3][0]==0
assert Image.open(p/'Resources/Art/pond-bed.jpg').size==(1600,900)
for f in ['forest-rain-tim-kahn.m4a','feed-plop-1.wav','feed-plop-2.wav']:
    assert (p/'Resources/Sound'/f).stat().st_size>1000
assert 'Tim Kahn' in (p/'Resources/Sound/ATTRIBUTION.txt').read_text()
# Confirm all 11-fish engine and assets are identical to working V1.0.0 baseline.
for line in (p/'tests/baseline-v100-engine-sha256.txt').read_text().splitlines():
    fn, digest=line.split('  ',1)
    assert (p/fn).exists()
    # V1.1.4 intentionally changes only feeding logic in these two engine files.
    if fn in ('Sources/NativeFish.swift', 'Sources/PondScene.swift'):
        continue
    actual=hashlib.sha256((p/fn).read_bytes()).hexdigest()
    assert digest==actual,fn
scene=(p/'Sources/PondScene.swift').read_text()
fish=(p/'Sources/NativeFish.swift').read_text()
app=(p/'Sources/PondApp.swift').read_text()
main=(p/'Sources/main.swift').read_text()
all_sources='\n'.join(f.read_text() for f in (p/'Sources').glob('*.swift'))
assert len(list((p/'Sources').glob('*.swift')))==6
assert 'for i in 0..<palettes.count' in scene and '3 / 小 8' in scene
assert 'class NativeFish' in fish
assert 'SchoolFish' not in all_sources and 'pondSchoolEnabled' not in all_sources and 'setSchoolEnabled' not in all_sources
assert 'schoolTrail' not in all_sources and 'MicroFish' not in all_sources
assert 'import WebKit' not in all_sources and 'import SpriteKit' in all_sources
assert 'SKShader' not in scene and 'windPatches' not in scene
assert 'private final class FallingRainDrop' in scene
assert 'private final class FoodPellet' in scene
assert 'onSurfaceClick' in scene and 'feedingAssignments' in scene
assert 'refreshFeedingAssignments()' in scene
assert 'feedingExcitement' in fish and 'let brake:' in fish
assert 'PondFoodJarButton' in app and 'setFoodInHand' in app and 'scatterFoodAt' in app
assert 'PondFeedingView' in app and 'onSurfaceClick' in app
assert 'makeFeedingOverlay()' in app and 'showFeedingOverlay(false)' in app
assert 'loginMenu=addItem(more,"登录时启动"' in app
assert 'NSPopoverDelegate' in app and 'toggleControlPopover' in app
assert 'status?.menu = nil' in app and 'status?.menu=menu' not in app
assert 'pop.show(relativeTo:button.bounds' in app
assert 'refreshComparisonMenu' not in all_sources
assert 'allowedContentTypes' in app and 'allowedFileTypes' not in app
sel=set(re.findall(r'#selector\(([a-zA-Z_]\w*)\)',app))
methods=set(re.findall(r'\bfunc\s+([a-zA-Z_]\w*)\s*\(',app))
assert not (sel-methods), 'Undefined menu action: '+str(sel-methods)
assert 'pondPreferencesMigratedV112' in main
assert 'studio.livingpond.native.v111' in main
assert 'pondSchoolEnabled' not in main
assert 'service.register()' in app and 'service.unregister()' in app
assert 'V1.1.4 RC' in app and 'stability-v1.1.4.log' in app
print('PASS regression: 11-fish scene, feeding-jar UI, responsive feeding, untouched art/sound, selectors')
