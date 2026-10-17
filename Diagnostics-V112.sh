#!/bin/bash
# Read-only diagnostics for a locally built app. Always invoke with /bin/bash.
set -uo pipefail
APP="$HOME/Applications/一池清宁.app"
LOG_DIR="$HOME/Library/Logs/LivingPond"
mkdir -p "$LOG_DIR"
OUT="$LOG_DIR/diagnostics-v1.1.2.txt"
{
  echo "Living Pond V1.1.2 diagnostics $(date)"
  echo '--- OS ---'
  sw_vers; uname -m
  echo '--- Installer executable, bundle, architecture ---'
  ls -ld "$APP" "$APP/Contents/MacOS/LivingPond" 2>&1
  /usr/bin/file "$APP/Contents/MacOS/LivingPond" 2>&1
  echo '--- Signature ---'
  /usr/bin/codesign -vvv --deep --strict "$APP" 2>&1
  echo '--- Gatekeeper ---'
  /usr/sbin/spctl -a -vv --type execute "$APP" 2>&1 || true
  echo '--- Quarantine ---'
  /usr/bin/xattr -l "$APP" 2>&1
  /usr/bin/xattr -l "$APP/Contents/MacOS/LivingPond" 2>&1
  echo '--- Bundle id ---'
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" 2>&1
  echo '--- Current running process and memory (RSS KB) ---'
  ps -axo pid,rss,%cpu,etime,command | grep '[/]一池清宁.app/Contents/MacOS/LivingPond' || true
  echo '--- Optional 30-minute in-app stability log ---'
  LOG="$HOME/Library/Logs/LivingPond/stability-v1.1.2.log"
  if [[ -f "$LOG" ]]; then tail -55 "$LOG"; else echo 'Not recorded yet'; fi
  echo '--- Recent app-related launch denials ---' 
  /usr/bin/log show --last 5m --style compact --predicate '(process == "syspolicyd" OR process == "amfid" OR process == "launchservicesd") AND (eventMessage CONTAINS[c] "LivingPond" OR eventMessage CONTAINS[c] "studio.livingpond")' 2>&1 | tail -50
} > "$OUT"
echo "DIAGNOSTIC_REPORT: $OUT"
cat "$OUT"
