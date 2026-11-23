# Veranda (docs/PLAN.md)
#   make            the kernel: build/VERANDA.PRG, build/VERANDA.SYS
#   make api        build/gen/* and docs/API.md from api/veranda.api
#   make gates      every gate so far
#   make sdk        the SDK into build/sdk (SDKDIR=...); its gate: tools/gate_sdk.sh
#   make shell      shell/SHELL.cvt, built with the SDK; its gate: tools/gate_shell.sh
#   make vbasic     VeraBASIC's generated tables, help and reference from vbasic/keywords.tbl;
#                   its gates: tools/gate_vb_spec.sh (the table, G1, G2), gate_vb_core.sh and
#                   gate_vb_speed.sh (VeraBASIC Run), gate_vb_tok.sh (the X16 tokenizer, G3),
#                   gate_vb_ui.sh (the Veranda extensions, part 1), gate_vb_files.sh (part 2:
#                   files, dialogs, the clipboard, icons, tiles, sprites), gate_vb_sdk.sh
#                   (vr_tile in the SDK; gates sdk, shell, edit), gate_vb_ide.sh (VeraBASIC, the
#                   editor: apps/vbasic make ide; textkit, gate edit), gate_vb_quit.sh (every
#                   example started from the shell and quit every way: the shell comes back),
#                   gate_vb_debug.sh (the debugger: breaks, steps, the pane, the screen kept, TRON)
#                   gate_vb_app.sh (Make application, the made application in the shell, the
#                   manual: its listings, HTML and PDF; vbasic.py doc)
all:
	python3 -I -B tools/kbuild.py

api:
	python3 -I -B tools/apigen.py api/veranda.api build/gen --doc docs/API.md

gates:
	tools/gate.sh spec && tools/gate.sh boot && tools/gate.sh gfx1 && tools/gate.sh gfx && tools/gate.sh input && tools/gate.sh ui && tools/gate.sh disk

vbasic:
	python3 -I -B tools/vbgen.py

SDKDIR ?= build/sdk
sdk: api all
	tools/mksdk.sh $(SDKDIR)

shell: sdk
	$(MAKE) -C shell SDK=$(abspath $(SDKDIR))

clean:
	rm -rf build
	$(MAKE) -C shell clean

.PHONY: all api gates sdk shell vbasic clean
