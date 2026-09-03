#!/bin/bash
# diagnose.sh — gather power, screen-saver, installed-build and Claude AX info.
# Usage: bash scripts/diagnose.sh   (output is also written to /tmp/apidae-diagnose.txt)
set -u
OUT=/tmp/apidae-diagnose.txt
exec > >(tee "$OUT") 2>&1
cd "$(dirname "$0")/.."

echo "== installed Apidae builds =="
for p in /Applications/Apidae.app "$HOME/Applications/Apidae.app" $(mdfind "kMDItemCFBundleIdentifier == 'app.getapidae.mac'" 2>/dev/null); do
  [ -d "$p" ] || continue
  echo "$p"
  echo "  version: $(defaults read "$p/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null) ($(defaults read "$p/Contents/Info.plist" CFBundleVersion 2>/dev/null))"
  echo "  modified: $(stat -f '%Sm' "$p/Contents/MacOS/Apidae" 2>/dev/null)"
done
echo "running: $(pgrep -lf Apidae | grep -v diagnose)"
echo "repo head: $(git log -1 --format='%h %s' 2>/dev/null)"

echo; echo "== power =="
pmset -g | egrep -i "displaysleep|^ *sleep|disksleep|lidwake|powernap|lowpowermode|Battery|AC Power"
echo "-- assertions mentioning Apidae --"
pmset -g assertions | grep -i -B1 -A3 apidae || echo "(none: is the hive closed right now?)"

echo; echo "== screen saver / lock =="
echo "screensaver idleTime: $(defaults -currentHost read com.apple.screensaver idleTime 2>/dev/null || echo unset)"
echo "askForPassword: $(defaults read com.apple.screensaver askForPassword 2>/dev/null || echo unset) delay: $(defaults read com.apple.screensaver askForPasswordDelay 2>/dev/null || echo unset)"
echo "lock after screensaver (sysprefs): $(sysadminctl -screenLock status 2>&1 | tail -1)"

echo; echo "== Claude processes =="
ps -Ao pid,pcpu,rss,comm | grep -i claude | grep -v grep | sed 's#/Applications/##' | head -20

echo; echo "== Claude AX tree =="
swift scripts/ax-dump.swift "com.anthropic.claudefordesktop" 14 2>&1 | head -400

echo; echo "(full output saved to $OUT)"
