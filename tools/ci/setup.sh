#!/bin/bash
# The tools of the GitHub workflows, pinned (DECISIONS V139).
#
#   tools/ci/setup.sh cc65            cc65 built from its pinned commit
#   tools/ci/setup.sh emu             the official x16emu R49 and the R49 ROM
#   tools/ci/setup.sh modem           x16emu with the Zimodem back-end (EMU_NET)
#   tools/ci/setup.sh all             cc65 and emu
#
# Into $CI_TOOLS (default $HOME/ci-tools; the workflows cache it): cc65 in
# $CI_TOOLS/cc65 (CC65_HOME), x16emu and rom.bin in $CI_TOOLS/x16. It
# prints the lines for $GITHUB_ENV / $GITHUB_PATH when they are set.
#
# The versions:
#   cc65    commit 547d923 of github.com/cc65/cc65 (2026-07-11), the cc65
#           every build of Veranda has used ("cc65 V2.19 - Git 547d923")
#   x16emu  R49, the official release (x16emu_linux-x86_64-r49.zip of
#           github.com/X16Community/x16-emulator, 2025-11-19)
#   ROM     R49 (Release.R49.ROM.Image.zip of github.com/X16Community/x16-rom):
#           the ROM of the user's X16. Downloaded from the official release
#           at run time, checked by its SHA-256, never committed, never in a
#           release, never uploaded as an artifact: the ROM holds the
#           Commodore KERNAL and Microsoft BASIC under the X16 project's
#           licence "to use this code in the context of the X16 computer"
#           (its LICENSE.md); running X16 software in the X16's emulator is
#           that, redistributing the ROM is not (docs/PUBLISHING.md).
#   modem   x16emu R49 plus the Zimodem back-end for -uart (the commits of
#           ~/Projects/x16-emulator-modem's branch modem, published as
#           veranda-x16/x16-emulator, branch modem: a fork of
#           X16Community/x16-emulator, BSD 2-Clause), built at its pinned
#           commit; Veranda Update's check of a release (tools/ci/updcheck.sh)
set -e
CI_TOOLS=${CI_TOOLS:-$HOME/ci-tools}
CC65_COMMIT=547d923588d870aacf0b0016c67d0f6a92a70f83
EMU_URL=https://github.com/X16Community/x16-emulator/releases/download/r49/x16emu_linux-x86_64-r49.zip
EMU_SHA=efb2d4ad36ae4244370004891aa67bdf85d2ec01b42b7f12f97b48b62aff009d
ROM_URL=https://github.com/X16Community/x16-rom/releases/download/r49/Release.R49.ROM.Image.zip
ROM_SHA=95b4e3566fa44f23dda9c8295b18a5fa9ea297e5db49dc978ae241e6114e39aa
ROMBIN_SHA=b81654cc8c87ed96e3ffc7c8e7c312c9f3b7b870c7bb34de61e61eac931b819a
MODEM_URL=https://github.com/veranda-x16/x16-emulator.git
MODEM_COMMIT=97ffc0ed32feea4c3c9e56c98b0409ae0da5b4d7
mkdir -p "$CI_TOOLS"
env_line() {
	echo "  $1=$2"
	[ -z "$GITHUB_ENV" ] || echo "$1=$2" >> "$GITHUB_ENV"
}
path_line() {
	[ -z "$GITHUB_PATH" ] || echo "$1" >> "$GITHUB_PATH"
}

cc65() {
	local d=$CI_TOOLS/cc65
	if [ ! -x "$d/bin/cl65" ] || [ "$(cat "$d/COMMIT" 2>/dev/null)" != "$CC65_COMMIT" ]; then
		rm -rf "$d" "$CI_TOOLS/cc65-src"
		git clone -q https://github.com/cc65/cc65.git "$CI_TOOLS/cc65-src"
		git -C "$CI_TOOLS/cc65-src" checkout -q "$CC65_COMMIT"
		make -C "$CI_TOOLS/cc65-src" -j"$(nproc)" >/dev/null
		mkdir -p "$d"
		cp -r "$CI_TOOLS/cc65-src/bin" "$CI_TOOLS/cc65-src/asminc" "$CI_TOOLS/cc65-src/cfg" \
			"$CI_TOOLS/cc65-src/include" "$CI_TOOLS/cc65-src/lib" "$CI_TOOLS/cc65-src/target" "$d/"
		echo "$CC65_COMMIT" > "$d/COMMIT"
		rm -rf "$CI_TOOLS/cc65-src"
	fi
	"$d/bin/cc65" --version 2>&1 | grep -q "Git ${CC65_COMMIT:0:7}" || { "$d/bin/cc65" --version; echo "setup: not cc65 ${CC65_COMMIT:0:7}" >&2; exit 1; }
	echo "setup: cc65 $("$d/bin/cc65" --version 2>&1)"
	env_line CC65_HOME "$d"
	path_line "$d/bin"
}

fetch() {        # url sha256 file
	curl -fsSL --retry 3 -o "$3" "$1"
	echo "$2  $3" | sha256sum -c --quiet - || { echo "setup: $1: not the SHA-256 it should have" >&2; exit 1; }
}

emu() {
	local d=$CI_TOOLS/x16
	if [ ! -x "$d/x16emu" ] || ! echo "$ROMBIN_SHA  $d/rom.bin" | sha256sum -c --quiet - 2>/dev/null; then
		rm -rf "$d"
		mkdir -p "$d/dl"
		fetch "$EMU_URL" "$EMU_SHA" "$d/dl/emu.zip"
		fetch "$ROM_URL" "$ROM_SHA" "$d/dl/rom.zip"
		unzip -q -o "$d/dl/emu.zip" x16emu -d "$d"
		unzip -q -o "$d/dl/rom.zip" rom.bin -d "$d"
		rm -rf "$d/dl"
		chmod +x "$d/x16emu"
	fi
	echo "$ROMBIN_SHA  $d/rom.bin" | sha256sum -c --quiet - || exit 1
	echo "setup: x16emu R49 and ROM R49 in $d"
	env_line EMU "$d/x16emu"
	env_line ROM "$d/rom.bin"
	env_line R49 "$d/rom.bin"
}

modem() {
	local d=$CI_TOOLS/x16modem
	if [ ! -x "$d/x16emu" ] || [ "$(cat "$d/COMMIT" 2>/dev/null)" != "$MODEM_COMMIT" ]; then
		rm -rf "$d" "$CI_TOOLS/modem-src"
		git clone -q --branch modem "$MODEM_URL" "$CI_TOOLS/modem-src"
		git -C "$CI_TOOLS/modem-src" checkout -q "$MODEM_COMMIT"
		make -C "$CI_TOOLS/modem-src" >/dev/null
		mkdir -p "$d"
		cp "$CI_TOOLS/modem-src/build/x16emu" "$d/"
		echo "$MODEM_COMMIT" > "$d/COMMIT"
		rm -rf "$CI_TOOLS/modem-src"
	fi
	"$d/x16emu" -h 2>&1 | grep -q -- "modem\[:<options>\]" || { echo "setup: $d/x16emu has no modem back-end" >&2; exit 1; }
	echo "setup: x16emu with the Zimodem back-end (${MODEM_COMMIT:0:7}) in $d"
	env_line EMU_NET "$d/x16emu"
}

case ${1:-all} in
cc65) cc65 ;;
emu) emu ;;
modem) modem ;;
all) cc65; emu ;;
*) echo "usage: tools/ci/setup.sh cc65|emu|all" >&2; exit 2 ;;
esac
