#!/bin/bash
# Gate vb_spec (VeraBASIC phase 0, docs/DECISIONS.md V85): the keyword
# table, the token format and the PC tokenizer.
#
#   tools/gate_vb_spec.sh        (OUT=dir: where it works; VB_FUZZ=n programs)
#
# 1. tools/vbgen.py's completeness check passes on vbasic/keywords.tbl,
#    and fails on a copy that lacks one keyword's example, another's help
#    and another's syntax; what it generates is what is committed
#    (vbasic/gen/tokens.inc, tools/vbtokens_gen.py,
#    vbasic/gen/HELP/KEYWORDS.HLP, docs/vbasic/manual/reference.md and
#    tokens.md)
# 2. tokens.inc assembles with ca65: the tables linked alone at $A000 (an
#    overlay's place) and decoded as the X16 lexer will read them
#    (tests/vbasic/check_tokens_inc.py); every overlay's entry macro
#    expands against stub entries
# 3. the 5-byte floats; G1 (tok(detok(T)) == T byte for byte, raw and
#    prepared) and G2 (detok(tok(S)) is the expected canonical form, and
#    idempotent) on the corpus (tests/vbasic/corpus), on every keyword's
#    example and on VB_FUZZ generated programs; every block offset at its
#    partner; the program document written, read by vpack.py and read back
# 4. prepare reports every planted structural error at its line, and
#    nothing else (tests/vbasic/errors: "' expect LINE: message" lines)
set -e
cd "$(dirname "$0")/.."
OUT=${OUT:-build/gate/vb_spec}
PY="python3 -I -B"
FUZZ=${VB_FUZZ:-400}

ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT/gen" "$OUT/inc"

# 1. the generator
$PY tools/vbgen.py --out "$OUT/gen" >"$OUT/vbgen.txt" || { cat "$OUT/vbgen.txt"; fail "vbgen.py"; }
ok "$(sed 's/^vbgen: //' "$OUT/vbgen.txt"): every one has syntax, help and an example"
for f in vbasic/gen/tokens.inc tools/vbtokens_gen.py vbasic/gen/HELP/KEYWORDS.HLP \
	docs/vbasic/manual/reference.md docs/vbasic/manual/tokens.md docs/vbasic/manual/refcard.md; do
	cmp -s "$OUT/gen/$f" "$f" || fail "$f is out of date (python3 -I tools/vbgen.py)"
done
ok "the generated files are current"
$PY - vbasic/keywords.tbl "$OUT/broken.tbl" <<'EOF'
import re, sys
src = open(sys.argv[1], encoding='latin-1').read().split('\n')
out, cur, drop = [], None, {'BEEP': 'example:', 'ASIDE': 'help:', 'TROFF': 'syntax:'}
for line in src:
    m = re.match(r'(kw|const) (\S+(?: [A-Z]+)?) *\|', line)
    if m:
        cur = m.group(2).strip()
    if cur in drop and line.strip().startswith(drop[cur]):
        continue
    out.append(line)
open(sys.argv[2], 'w', encoding='latin-1').write('\n'.join(out))
EOF
if $PY tools/vbgen.py --tbl "$OUT/broken.tbl" --check-only 2>"$OUT/broken.txt"; then
	fail "vbgen.py accepts a table with a keyword lacking its example"
fi
for w in "BEEP has no example" "ASIDE has no help text" "TROFF has no syntax line"; do
	grep -q "$w" "$OUT/broken.txt" || { cat "$OUT/broken.txt"; fail "vbgen.py does not say: $w"; }
done
ok "vbgen.py refuses a table whose keywords lack an example, a help text, a syntax line"

# 2. the ca65 include
$PY tests/vbasic/check_tokens_inc.py wrap "$OUT/inc"
ca65 -g -I vbasic/gen -o "$OUT/inc/tables.o" "$OUT/inc/tables.s" || fail "tokens.inc does not assemble (tables)"
ca65 -I vbasic/gen -o "$OUT/inc/entries.o" "$OUT/inc/entries.s" || fail "tokens.inc does not assemble (entries)"
ld65 -C "$OUT/inc/tables.cfg" -o "$OUT/inc/tables.bin" -Ln "$OUT/inc/tables.lbl" "$OUT/inc/tables.o" ||
	fail "the tables do not link"
ok "vbasic/gen/tokens.inc assembles with ca65 ($(ca65 --version 2>&1 | head -1 | sed 's/ - .*//'))"
$PY tests/vbasic/check_tokens_inc.py check "$OUT/inc/tables.bin" "$OUT/inc/tables.lbl" || fail "the linked tables"

# 3. G1 and G2
C="$PY tests/vbasic/check_vb_spec.py"
$C floats || fail "the float encoding"
$C corpus tests/vbasic/corpus || fail "G1 / G2 on the corpus"
$C fuzzfiles tests/vbasic/corpus || fail "the committed fuzz programs"
$C examples vbasic/keywords.tbl || fail "G1 / G2 on the examples"
$C fuzz 1 "$FUZZ" || fail "G1 / G2 on generated programs"

# 4. the planted errors
$C errors tests/vbasic/errors || fail "the planted structural errors"
$PY tools/vbtokens.py check tests/vbasic/errors/err_endif_missing.bas >"$OUT/check.txt" || true
grep -qx "tests/vbasic/errors/err_endif_missing.bas:13: END IF missing for IF in line 4" "$OUT/check.txt" ||
	fail "vbtokens.py check does not print file:line: message"
ok "vbtokens.py check prints file:line: message"
echo "gate vb_spec: pass"
