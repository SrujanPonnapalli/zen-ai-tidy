#!/bin/sh
# Installs Zen AI Tidy into Zen: builds the helper, installs the fx-autoconfig loader,
# and symlinks the script + helper into the profile. Rerun after every Zen update
# (updates wipe the loader files from Zen.app). Usage: ./install.sh [profile-dir]
set -eu
cd "$(dirname "$0")"
REPO=$(pwd)
ZEN_APP=${ZEN_APP:-/Applications/Zen.app}
ZEN_DATA="$HOME/Library/Application Support/zen"
FXAC_COMMIT=dfdab56 # reviewed fx-autoconfig commit

if [ $# -ge 1 ]; then
  PROFILE=$1
else
  # The profile Zen opens by default, from installs.ini.
  rel=$(awk -F= '/^Default=/{print $2; exit}' "$ZEN_DATA/installs.ini")
  PROFILE="$ZEN_DATA/$rel"
fi
[ -d "$PROFILE" ] || { echo "profile not found: $PROFILE" >&2; exit 1; }
echo "profile: $PROFILE"

echo "building tidy-helper…"
mkdir -p bin
swiftc -O helper/main.swift -o bin/tidy-helper
./bin/tidy-helper --check

echo "installing fx-autoconfig ($FXAC_COMMIT)…"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
git clone -q https://github.com/MrOtherGuy/fx-autoconfig "$tmp/fxac"
git -C "$tmp/fxac" checkout -q "$FXAC_COMMIT"
cp "$tmp/fxac/program/config.js" "$ZEN_APP/Contents/Resources/config.js"
mkdir -p "$ZEN_APP/Contents/Resources/defaults/pref"
cp "$tmp/fxac/program/defaults/pref/config-prefs.js" "$ZEN_APP/Contents/Resources/defaults/pref/config-prefs.js"
mkdir -p "$PROFILE/chrome/utils" "$PROFILE/chrome/JS"
cp "$tmp/fxac/profile/chrome/utils/"* "$PROFILE/chrome/utils/"

echo "linking script and helper…"
ln -sf "$REPO/chrome/JS/zen-ai-tidy.uc.mjs" "$PROFILE/chrome/JS/zen-ai-tidy.uc.mjs"
ln -sf "$REPO/bin/tidy-helper" "$PROFILE/chrome/tidy-helper"

# fx-autoconfig only picks up new scripts after the startup cache is cleared.
rm -rf "$HOME/Library/Caches/zen/Profiles/$(basename "$PROFILE")/startupCache"
echo "done. Quit and reopen Zen."
