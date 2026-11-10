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

# One install attempt. Returns 0 = done, 2 = the dongle's version check refused this package (try another),
# 1 = anything else.
program_once() { # $1 = package zip, $2 = what it is
	echo "Installing $2 (about 10-30 seconds; ignore any J-Link warning)..."
	"$NU" device program --firmware "$1" --traits nordicDfu 2>&1 | tee "$WORK/last-run.log"
	[ "${PIPESTATUS[0]}" -eq 0 ] && return 0
	grep -q SdVersionFailure "$WORK/last-run.log" && return 2
	return 1
}

ensure_dfu() {
	echo "Waiting for the dongle in update mode..."
	while ! wait_for_dfu; do
		bold "I can't see the dongle in update mode."
		update_mode_steps
		ask "Press Return when you've done that (or Ctrl-C to stop)... "
	done
}

program() { # $1 = package zip, $2 = what it is; retries real failures, returns 2 on a version refusal
	local tries=0 rc
	while :; do
		tries=$((tries + 1))
		ensure_dfu
		program_once "$1" "$2"
		rc=$?
		[ $rc -ne 1 ] && return $rc
		[ $tries -ge 3 ] && fail "Installing $2 failed 3 times. Nothing is broken: send Claude a screenshot of this window."
		bold "That didn't go through. Let's retry."
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
	for pkg in s140-6.1.1-nosd.zip s140-6.1.1.zip; do
		curl -fL --progress-bar -o "$pkg" "$BASE/$pkg" || fail "Couldn't download the radio stack."
	done
fi

bold "Put the dongle in update mode:"
update_mode_steps
ask "Press Return when its light is fading in and out... "

if [ "$MODE" != app ]; then
	bold "Step 1 of 2: Nordic's radio stack (SoftDevice S140 6.1.1, one time only)"
	# Dongles ship either with no radio stack or with an older one; each package is only accepted by one kind,
	# and a refused package changes nothing, so try both.
	sd_done=0
	for pkg in s140-6.1.1-nosd.zip s140-6.1.1.zip; do
		program "$WORK/$pkg" "the radio stack"
		rc=$?
		[ $rc -eq 0 ] && { sd_done=1; break; }
		echo "(That version didn't match this dongle; trying the other one.)"
	done
	[ $sd_done -eq 1 ] || fail "The dongle refused both radio-stack versions. Nothing is broken: send Claude a screenshot of this window."
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
