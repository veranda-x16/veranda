#!/bin/bash
# The tools of the GitHub workflows, pinned (DECISIONS V139).
#
#   tools/ci/setup.sh cc65            cc65 built from its pinned commit
#   tools/ci/setup.sh emu             the official x16emu R49 and the R49 ROM
#   tools/ci/setup.sh modem           x16emu with the Zimodem back-end (EMU_NET)
#   tools/ci/setup.sh prog8           Prog8 12.3.5 (PROG8C, PROG8_JAR), 64tass, Java:
#                                     VIDKIT Player and Prog8 for Veranda (DECISIONS V203)
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
#   prog8   Prog8 12.3.5's compiler, the official release's jar
#           (prog8c-12.3.5-all.jar of github.com/irmen/prog8, its SHA-256 as
#           the release lists it), into $CI_TOOLS/prog8; it runs on Java 17
#           or later (the runner's Temurin; else apt's openjdk-17-jre-headless)
#           and assembles with 64tass (Ubuntu 24.04's package, 1.59.3120; 1.58
#           or later). Off GitHub (no GITHUB_ACTIONS) the machine's own: a
#           prog8c on the PATH, else the same jar in ~/.local/share/prog8 or
#           $CI_TOOLS/prog8 (checked by its SHA-256 too); nothing installed
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
PROG8_VERSION=12.3.5
PROG8_URL=https://github.com/irmen/prog8/releases/download/v$PROG8_VERSION/prog8c-$PROG8_VERSION-all.jar
PROG8_SHA=aee4b749eda3b1397782a416ffe520dc8fc8b2a6a3537e87ae8f08cb0655843b
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

prog8() {
	local d=$CI_TOOLS/prog8 j v
	j=$d/prog8c-$PROG8_VERSION-all.jar
	if [ -z "$GITHUB_ACTIONS" ]; then
		# this machine's own install (nothing downloaded or installed here)
		if command -v prog8c >/dev/null; then
			echo "setup: prog8c on the PATH ($(command -v prog8c))"
			env_line PROG8C prog8c
		else
			for f in "$HOME/.local/share/prog8/prog8c-$PROG8_VERSION-all.jar" "$j"; do
				if echo "$PROG8_SHA  $f" | sha256sum -c --quiet - >/dev/null 2>&1; then
					j=$f
					break
				fi
			done
			echo "$PROG8_SHA  $j" | sha256sum -c --quiet - >/dev/null 2>&1 ||
				{ echo "setup: no Prog8 $PROG8_VERSION here (prog8c, or $PROG8_URL in ~/.local/share/prog8)" >&2; exit 1; }
			env_line PROG8C "java -jar $j"
			env_line PROG8_JAR "$j"
		fi
		command -v 64tass >/dev/null || { echo "setup: no 64tass on the PATH" >&2; exit 1; }
		echo "setup: $(64tass --version 2>&1 | head -1)"
		return
	fi
	if ! echo "$PROG8_SHA  $j" | sha256sum -c --quiet - >/dev/null 2>&1; then
		rm -rf "$d"
		mkdir -p "$d"
		fetch "$PROG8_URL" "$PROG8_SHA" "$j"
	fi
	# Java 17 or later (the jar's classes are version 61)
	v=$(java -version 2>&1 | sed -n 's/.*version "\([0-9]*\).*/\1/p' | head -1)
	if [ -z "$v" ] || [ "$v" -lt 17 ]; then
		sudo apt-get install -y -qq openjdk-17-jre-headless >/dev/null
		v=$(java -version 2>&1 | sed -n 's/.*version "\([0-9]*\).*/\1/p' | head -1)
	fi
	[ -n "$v" ] && [ "$v" -ge 17 ] || { java -version; echo "setup: Prog8 needs Java 17 or later" >&2; exit 1; }
	command -v 64tass >/dev/null || sudo apt-get install -y -qq 64tass >/dev/null
	64tass --version 2>&1 | grep -q 'V1\.\(5[89]\|[6-9][0-9]\)' || { 64tass --version; echo "setup: Prog8 needs 64tass 1.58 or later" >&2; exit 1; }
	java -jar "$j" -version 2>&1 | grep -q "$PROG8_VERSION" || { java -jar "$j" -version; echo "setup: not Prog8 $PROG8_VERSION" >&2; exit 1; }
	echo "setup: Prog8 $PROG8_VERSION in $d, Java $v, $(64tass --version 2>&1 | head -1)"
	env_line PROG8C "java -jar $j"
	env_line PROG8_JAR "$j"
}

case ${1:-all} in
cc65) cc65 ;;
emu) emu ;;
modem) modem ;;
prog8) prog8 ;;
all) cc65; emu ;;
*) echo "usage: tools/ci/setup.sh cc65|emu|modem|prog8|all" >&2; exit 2 ;;
esac
