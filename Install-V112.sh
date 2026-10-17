#!/bin/bash
# 一池清宁 V1.1.2: run with /bin/bash, never by double-clicking.
# This is a user-level, source-only, offline build; no downloaded executable is run.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
APP_NAME="一池清宁.app"
DEST="$HOME/Applications/$APP_NAME"
LOG_DIR="$HOME/Library/Logs/LivingPond"
mkdir -p "$LOG_DIR" "$HOME/Applications"
LOG_FILE="$LOG_DIR/build-v1.1.2.log"
exec > >(tee "$LOG_FILE") 2>&1
printf '\n一池清宁 V1.1.2 | %s\n' "$(date)"
echo '[1/8] Checking macOS, CPU and Swift tools'
if [[ "$(uname -s)" != "Darwin" ]]; then echo 'ERROR: macOS required.' >&2; exit 1; fi
ARCH="$(uname -m)"
case "$ARCH" in x86_64|arm64) ;; *) echo "ERROR: Unsupported CPU: $ARCH" >&2; exit 1 ;; esac
xcrun --find swiftc >/dev/null || { echo 'ERROR: Please install Xcode Command Line Tools.' >&2; exit 1; }
printf 'macOS %s | CPU %s | Swift %s\n' "$(sw_vers -productVersion)" "$ARCH" "$(xcrun --find swiftc)"
# Never launch another live desktop pond on top of an already-running copy.
# Check the process command, without killing or modifying any running app.
while IFS= read -r commandLine; do
  if [[ "$commandLine" == *"/Contents/MacOS/LivingPond" || "$commandLine" == *"/Contents/MacOS/LivingPond "* ]]; then
    echo 'ERROR: 已有一池清宁/旧版鱼塘正在运行。请先从菜单中退出旧版，再安装。' >&2
    exit 3
  fi
done < <(/bin/ps -axo command=)
echo '[2/8] Building within ~/Applications (away from Downloads)'
WORK="$(mktemp -d "$HOME/Applications/.LivingPond-v112.XXXXXXXX")"
cleanup() { if [[ -n "${WORK:-}" && -d "$WORK" ]]; then rm -rf "$WORK"; fi; }
trap cleanup EXIT
STAGED="$WORK/$APP_NAME"
mkdir -p "$STAGED/Contents/MacOS" "$STAGED/Contents/Resources/Art" "$STAGED/Contents/Resources/Sound"
# macOS cp -X: do not inherit downloaded source extended attributes.
cp -X "$ROOT/Info.plist" "$STAGED/Contents/Info.plist"
cp -X -R "$ROOT/Resources/Art/." "$STAGED/Contents/Resources/Art/"
cp -X -R "$ROOT/Resources/Sound/." "$STAGED/Contents/Resources/Sound/"
# Generate the official .icns locally from provided, original PNG iconset.
/usr/bin/iconutil -c icns "$ROOT/Resources/AppIcon.iconset" -o "$STAGED/Contents/Resources/AppIcon.icns"
test -s "$STAGED/Contents/Resources/AppIcon.icns"
echo '[3/8] Compiling native Swift/AppKit/SpriteKit source'
xcrun swiftc -O -target "$ARCH-apple-macosx13.0" \
 "$ROOT/Sources/main.swift" \
 "$ROOT/Sources/PondApp.swift" \
 "$ROOT/Sources/PondScene.swift" \
 "$ROOT/Sources/FrameMetrics.swift" \
 "$ROOT/Sources/NativeFish.swift" \
 "$ROOT/Sources/PondSoundController.swift" \
 -framework AppKit -framework SpriteKit -framework CoreGraphics -framework AVFoundation -framework ServiceManagement -framework QuartzCore \
 -o "$STAGED/Contents/MacOS/LivingPond"
chmod 755 "$STAGED/Contents/MacOS/LivingPond"
echo '[4/8] Verifying executable and bundle metadata'
/usr/bin/file "$STAGED/Contents/MacOS/LivingPond"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$STAGED/Contents/Info.plist"
echo '[5/8] Checking locally built bundle for inherited quarantine'
if /usr/bin/xattr -lr "$STAGED" 2>/dev/null | grep -q 'com.apple.quarantine'; then
  echo 'NOTE: locally generated staging bundle inherited a download quarantine tag.'
  # Scope restricted to this newly compiled staging bundle.
  /usr/bin/xattr -dr com.apple.quarantine "$STAGED"
fi
echo '[6/8] Signing and verifying the newly compiled local app'
/usr/bin/codesign --force --sign - "$STAGED"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$STAGED"
echo '[7/8] Installing into user Applications (stable app name)'
if [[ -e "$DEST" ]]; then
  BACKUP_DIR="$HOME/Library/Application Support/LivingPond/AppBackups"
  mkdir -p "$BACKUP_DIR"
  BACKUP="$BACKUP_DIR/一池清宁-$(date '+%Y%m%d-%H%M%S')-backup.app"
  mv "$DEST" "$BACKUP"
  echo "Backed up previous stable app: $BACKUP"
fi
if ! mv "$STAGED" "$DEST"; then
  echo "INSTALL_FAILED: restore the previous installed app if possible" >&2
  if [[ -n "${BACKUP:-}" && -d "$BACKUP" && ! -e "$DEST" ]]; then mv "$BACKUP" "$DEST"; fi
  exit 1
fi
/usr/bin/codesign --verify --deep --strict --verbose=2 "$DEST"
if /usr/bin/xattr -p com.apple.quarantine "$DEST" >/dev/null 2>&1; then
  echo 'WARNING: app quarantine tag remains. See diagnostics.'
else
  echo 'Verified: installed app has no top-level quarantine tag.'
fi
echo "INSTALL_OK: $DEST"
echo '[8/8] Requesting app launch'
if /usr/bin/open -n -a "$DEST"; then
 echo 'Launch was requested. Please check menu bar for koi icon.'
 echo 'If any system alert appears, run Diagnostics-V112.sh via /bin/bash and share the report.'
else
 echo 'LAUNCH_FAILED: open declined. Run diagnostic script.'
fi
echo "Build log: $LOG_FILE"
