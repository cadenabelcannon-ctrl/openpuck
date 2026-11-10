#!/bin/bash
# OpenPuck updater for the Raytac MDBT50Q-CX(-40) USB-C dongle, macOS.
#
# First time:   curl -fsSL https://cadenabelcannon-ctrl.github.io/openpuck/raytac/flash-raytac.sh | bash
# Later updates (OpenPuck only, skips the one-time SoftDevice step):
#               curl -fsSL https://cadenabelcannon-ctrl.github.io/openpuck/raytac/flash-raytac.sh | bash -s app
#
# Uses Nordic's own nRF Util to talk to the dongle's factory "Open DFU" bootloader. The bootloader itself is
# never replaced, so a failed or interrupted run is always recoverable: put the dongle back in update mode
# and run this again.
set -uo pipefail

BASE="https://cadenabelcannon-ctrl.github.io/openpuck/raytac"
NRFUTIL_URL="https://files.nordicsemi.com/artifactory/swtools/external/nrfutil/executables/universal-apple-darwin/nrfutil"
WORK="$HOME/OpenPuck-Raytac"
MODE="${1:-full}"

bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }
fail() { printf '\n\033[31m%s\033[0m\n' "$*"; exit 1; }
# stdin is this script when it's piped from curl, so prompts read the keyboard directly
ask() { read -r -p "$1" REPLY </dev/tty || true; }

update_mode_steps() {
	echo "  1. Unplug the Raytac dongle."
	echo "  2. Hold down its small button (the end away from the USB plug)."
	echo "  3. Keep holding while you plug it back in, then let go once its light starts to fade in and out."
}

# true once a dongle in update mode is visible
dfu_present() { "$NU" device list --traits nordicDfu --json 2>/dev/null | grep -q nordicDfu; }

wait_for_dfu() {
	for _ in $(seq 1 45); do
		dfu_present && return 0
		sleep 1
	done
	return 1
}

program() { # $1 = package zip, $2 = what it is
	local tries=0
	while :; do
		tries=$((tries + 1))
		echo "Waiting for the dongle in update mode..."
		if ! wait_for_dfu; then
			bold "I can't see the dongle in update mode."
			update_mode_steps
			ask "Press Return when you've done that (or Ctrl-C to stop)... "
			continue
		fi
		echo "Installing $2 (about 10-30 seconds; ignore any J-Link warning)..."
		if "$NU" device program --firmware "$1" --traits nordicDfu; then
			return 0
		fi
		[ $tries -ge 3 ] && fail "Installing $2 failed 3 times. Nothing is broken: send Claude a screenshot of this window."
		bold "That didn't go through. Let's retry."
		update_mode_steps
		ask "Press Return when ready... "
	done
}

[ "$(uname -s)" = Darwin ] || fail "This updater is for macOS."
mkdir -p "$WORK" && cd "$WORK" || fail "Couldn't create $WORK"
NU="$WORK/nrfutil"

bold "OpenPuck for Raytac MDBT50Q-CX-40"
echo "Working folder: $WORK"

if [ ! -x "$NU" ]; then
	bold "Downloading Nordic's nRF Util (one time)..."
	curl -fL --progress-bar -o "$NU" "$NRFUTIL_URL" || fail "Download failed. Check your internet connection and run this again."
	chmod +x "$NU"
fi
if ! "$NU" device --version >/dev/null 2>&1; then
	bold "Installing nRF Util's device tools (one time, can take a minute)..."
	"$NU" install device || fail "Couldn't install nRF Util's device tools. Run this again; if it keeps failing, send Claude a screenshot."
fi

bold "Downloading OpenPuck..."
curl -fL --progress-bar -o OpenPuck-mdbt50q-cx-40.zip "$BASE/OpenPuck-mdbt50q-cx-40.zip" || fail "Couldn't download OpenPuck."
if [ "$MODE" != app ]; then
	curl -fL --progress-bar -o s140-6.1.1.zip "$BASE/s140-6.1.1.zip" || fail "Couldn't download the SoftDevice."
fi

bold "Put the dongle in update mode:"
update_mode_steps
ask "Press Return when its light is fading in and out... "

if [ "$MODE" != app ]; then
	bold "Step 1 of 2: Nordic's radio stack (SoftDevice S140 6.1.1, one time only)"
	program "$WORK/s140-6.1.1.zip" "the radio stack"
	bold "Radio stack installed. Now update mode once more for OpenPuck itself:"
	update_mode_steps
	ask "Press Return when its light is fading in and out... "
	bold "Step 2 of 2: OpenPuck"
else
	bold "Installing OpenPuck"
fi
program "$WORK/OpenPuck-mdbt50q-cx-40.zip" "OpenPuck"

bold "Done! OpenPuck is on the Raytac."
echo "Unplug it and plug it back in normally (no button), then open"
echo "  https://cadenabelcannon-ctrl.github.io/openpuck/"
echo "press Connect, and use Backup & clone -> Import to bring over your pairings and profiles."
