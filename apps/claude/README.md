# Veranda Claude

A conversation with Claude, Anthropic's AI model, for Veranda (DECISIONS
V114), through the Wi-Fi modem of TexElec's "Serial & ESP32 Network
Card" (Zimodem; the SDK's `vrnet`, `docs/NET.md`). It talks to the
Anthropic Messages API (`https://api.anthropic.com/v1/messages`) with
your own API key; the API is paid by the token. Or, with a claude.ai
plan, to your own **Claude Code on a PC** through a small bridge
(DECISIONS V115; below).

## Before you start: two things to check

**1. Your modem must know `ATCS`.** The X16 cannot do TLS (the
encryption every HTTPS site needs). Veranda Claude asks the modem to do
it: Zimodem's connect command takes an `S` modifier,
`ATCS"api.anthropic.com:443"`, and the ESP32 then opens a TLS
connection, over which the X16 speaks plain HTTP/1.1. This modifier is
in Zimodem's source (`connSettings.ino`, `wificlientnode.h`) but **not
in its README**, and it has **not been tried on the card yet**. Check
your firmware's version with Veranda Term (type `ATI` in its serial
terminal); if a connection always fails at once ("Could not connect to
api.anthropic.com (refused, or no such host)"), the firmware probably
has no `ATCS`: update Zimodem on the ESP32.

**2. The certificate is not checked.** Zimodem's secure client is made
with `setInsecure()`: the connection is encrypted, but the modem does
not check that it is really talking to api.anthropic.com. Someone who
controls your network could pretend to be the API and read your key and
your conversation. Use a network you trust.

## An API key

Make one at **console.anthropic.com** (Settings, API keys). The first
time Veranda Claude starts without a key it says so and opens
**Settings**: type the key there (about 108 characters; it is shown as
stars but for its last 4), or paste it with Ctrl+V, and press Return
(Save). Easier: write it on the SD card from a PC, as a line in
`/VERANDA/.SYSTEM/CLAUDE.CFG`:

    key=sk-ant-api03-...

The key is kept there **as plain text**: anyone with the card can use
it (and spend your money). The same file keeps the model
(`model=claude-opus-5-5`, `claude-sonnet-5-5` or `claude-haiku-5-5`),
and may hold your own system prompt on one line (`system=...`; without
it Veranda Claude asks Claude for plain ASCII text, no Markdown, short
paragraphs, which suits the X16's 74 columns).

## Claude Code on my PC (your claude.ai plan)

A claude.ai subscription cannot be used by other programs: it is for
Anthropic's own apps, Claude Code among them. So Veranda Claude does not
sign in with it; it talks to **your own Claude Code**, running on your
PC, through `tools/claude_bridge.py` (on the SD card as
`PC/claude_bridge.py`). The X16 is only the screen and the keyboard.

1. On a PC where Claude Code (`claude`) is installed and signed in, with
   Python 3:

       python3 claude_bridge.py --password something-long

   (or set `CLAUDE_BRIDGE_PASSWORD`; without either it makes one up and
   prints it). It listens on port 8642 and prints the PC's address.
2. In Veranda Claude: **Settings**, Server **Claude Code on my PC** (a
   click, or Right), the PC's address (`192.168.1.20:8642`; without a
   port, 8642), **Tab**, the password, Return.

The status bar says "on my PC" after the model; the model chosen is the
one Claude Code uses. Each turn the bridge runs `claude -p` once with
**every tool off** (`--tools ""`, `--disallowedTools "*"`), no MCP
servers, no slash commands, `--safe-mode`, in an empty folder of its own
(`~/.cache/veranda-claude-bridge/work`): the X16 cannot make the PC run a
command or read a file. The bridge never reads Claude Code's login; it
only runs the program. Claude Code keeps the conversation as a session:
the bridge resumes it (`--resume`) and sends only your new message;
after an error, a restart of the bridge, or turns dropped on the X16, it
starts a new session with the conversation so far. Errors come as boxes
in a few words ("usage limit reached (5-hour), resets Fri 15:00", "not
signed in: run claude on the PC, then /login"); a wrong password is a
401 box; the bridge not running, "Is claude_bridge.py running on the
PC?". One turn at a time; only private addresses (127/8, 10/8,
172.16/12, 192.168/16, IPv6 local) may connect.

**Plain TCP:** the connection to the bridge has no TLS. The password and
the conversation cross your home network unencrypted, and the password
is kept as plain text in `CLAUDE.CFG` (`bpass=`).

CLAUDE.CFG keeps both servers' settings, so switching loses nothing:

    server=bridge            (or api)
    key=sk-ant-api03-...     the API key
    bridge=192.168.1.20:8642
    bpass=something-long

`python3 claude_bridge.py --help` lists its options (`--port`, `--bind`,
`--claude` for another `claude` program, `--workdir`, `--timeout`).

## Using it

- **Type** in the box at the bottom and press **Return** (or click
  **Send**). Shift+Return starts a new line; Left, Right, Home, End,
  Backspace, Delete edit; Up and Down move between the box's lines;
  Ctrl+V pastes the clipboard's text.
- Your turns have a blue badge and a light background, Claude's an
  orange spark; the program's notes a yellow one, and a turn that was
  left out (not answered, or declined) a red one.
- Claude **thinks first**: the reply's row says "Thinking ..." with the
  seconds, for a few seconds (more with Opus). Then the text comes as it
  is written. **Esc** (or **Stop**) stops it: what came is kept.
- **PgUp, PgDn**, the wheel and the scroll bar scroll the conversation
  (Look 3's: an arrow a row, the track a page, the thumb dragged); Esc
  goes back to the newest. Ctrl+Q quits.
- **Settings** (the toolbar, or the Settings menu): the server (the
  Anthropic API or Claude Code on my PC: a click, Left, Right), the key
  or the bridge's address and password (Tab moves between them), the
  model. The Settings menu also switches the model at once: **Claude
  Opus 5.5** (the default, the most capable), **Claude Sonnet 5.5**,
  **Claude Haiku 5.5** (the fastest, the cheapest).
- **File > New conversation** (Ctrl+N, the toolbar's New) starts again
  (the conversation is kept in Chats); **File > Export as text...**
  (Ctrl+S, Save) writes it to `/DOCUMENTS` as a text file (UTF-8, CR LF).

## Code in replies

When the reply has code, Claude is asked to put it in a Markdown fenced
block (a line ```` ``` ```` with the language, the code, a line
```` ``` ````). Veranda Claude finds these blocks when the reply has come:
their rows are shaded (in Classic, a rule at their left), and the
opening fence's row shows the language and its labels:

    ```basic      [Copy]  [Save...]  [Save .PRG]       (saved: PROGRAM.BAS)

- **[Copy]** puts the code on Veranda's clipboard (the Text Scrap:
  Latin-1, a CR at each line's end), for Veranda Edit, Veranda Write or
  any program that pastes.
- **[Save...]** asks a name (from the language: `PROGRAM.BAS`,
  `CODE.ASM`, `CODE.C`, `CODE.PY`, `CODE.TXT`; long names are fine) and
  writes the code to `/DOCUMENTS` as plain text (CR LF). It asks before
  it replaces a file.
- **[Save .PRG]** (BASIC only: the tag `basic`, `bas`, `x16basic`,
  `commodore-basic`, or numbered lines) writes a program the X16's ROM
  BASIC can `LOAD` and `RUN`: it is tokenized as the ROM's own BASIC
  does it (its keywords, the X16's own as `$CE` and a byte, the line
  links, `$0801`). Letters in either case become the X16's capitals;
  `{93}`-style codes (two hex digits) are the bytes with no plain form
  (colour and cursor codes); the line numbers must go up.
- **The Code menu**: Copy last code block (**Ctrl+K**), Save last code
  block... (**Ctrl+E**; for BASIC it asks whether as a program), Go to
  code block... (by its number), Copy last reply, Attach a file...
  (**Ctrl+Shift+A**).

## A file with your question

**Attach** (the toolbar) or Code > Attach a file... asks a file's name
in `/DOCUMENTS`: plain text, a Veranda Write document (`.cwr`: its text
only, without the styles), or a tokenized BASIC program (`.PRG`, made
text with the ROM's keywords). The toolbar says "Attached: GAME.PRG (23
lines) [Remove]" (a click on it removes it); the next question takes it
along, after your text, as "Attached file GAME.PRG:" and a fenced block.
12 KB of text at most (the conversation keeps 32 KB).

Then a reply's block in the same language is the file's next version:
its [Save...] offers the file's own name ("Replace GAME.PRG?"), and a
`.PRG` is tokenized again, so "attach, ask to fix line 30, save over the
file, run it" is a short loop. Only the newest version of the file is
sent whole; the older ones go as "[GAME.PRG, older version, 23 lines]".

Running the program from Claude is not there yet: Veranda's way to
BASIC (`ToBASIC`, the shell's BASIC) types at most 10 characters for
BASIC, in the system folder; quit to BASIC and `LOAD"/DOCUMENTS/GAME.PRG"`.

## Chats: every conversation kept

After every turn the conversation is saved to
`/DOCUMENTS/Chats/Claude` (the folders are made when missing): one file a
chat, named with a number and a short title, the first question's first
40 characters (`0007 How do I draw a circle.chat`). **File > Chats...**
(**Ctrl+L**, the toolbar's **Chats**) lists the 16 newest, newest first,
with their date and size: **Open** (or Return) puts one back on the
screen and you go on with it, **Rename**, **Delete** (asked first),
**New**. A chat too big for the memory opens with its newest part (a
note says how many older messages were left out; the file keeps them).
The next question after opening is sent as any other: Remember and
Compact apply, and a chat that was compacted sends its summary and the
turns after it, not everything. **File > New conversation** no longer
asks (the old one is saved); **File > Export as text...** (Ctrl+S)
writes a conversation as a text file, as before.

The file, version 2 (V143: the font's bytes, Veranda's set ISO-8859-16
and the private box glyphs at $80-$9F; a version 1 file, CP437, is still
read, its letters made the set's; CR LF; written as `CHAT.TMP`, then the
old one deleted and `CHAT.TMP` renamed):

    VERANDA CHAT 2
    app=Claude
    title=How do I draw a circle
    model=claude-opus-5-5
    created=2026-11-21 08:00          (the X16's clock)
    updated=2026-11-21 08:05
    file=GAME.PRG                     (the file attached last: Save back)

    u 23                              each message: its kind, its length
    How do I draw a circle?           in bytes, a CR LF, its text, a CR LF
    a 412
    ...
    end

The kinds: `u` yours, `a` the reply, `n` a note, `x` and `y` a turn left
out, `s` a compaction's summary (sent as yours), `c` and `d` compacted
(shown dimmed, not sent). A file that is not a chat, is damaged, or says
a newer version than 1 is refused with a box (the conversation on the
screen stays). No key, token or password is ever written into a chat
file.

## What a question costs: the conversation is sent every time

The API keeps nothing between requests: **each question sends the whole
conversation again**, as every API chat program does. A long
conversation costs more each turn. What helps:

- **The usage**: after each turn the status bar shows the tokens: "in
  1,484 (cached 34) out 42", and with an API key an estimate in dollars ("$0.0069": Anthropic's list prices, in the source: Opus 5.5 $4 in / $20 out a million tokens, Sonnet 5.5 $2 / $10, Haiku 5.5 $0.10 / $0.50; a cache write 1.25 times the input, a cache read $0.20, $0.10 and $0.01; only an estimate: the bill is Anthropic's). With Claude Code on my PC: tokens only. Settings > Conversation... shows the
  conversation's total.
- **Remember** (Settings > Conversation...): everything (the default),
  the last 10 messages, the last 4, or only the question. The request
  then carries only the messages before the question that are kept
  (always from one of your messages, so the turns alternate).
- **Old code shortened** (on unless you turn it off): a code block that
  was saved or copied, once it is older than the last reply, or any
  block two turns old, is sent as one line ("[code block: 23 lines,
  saved as PROGRAM.BAS]"). The screen keeps everything.
- **Compact** (Settings > Compact conversation, or the page's Compact
  now; or by itself when what is sent is longer than 6 KB): one request
  to the cheapest model (Claude Haiku 5.5) summarises the conversation in 150
  words at most; from then on the summary (sent as your message,
  "Summary of our conversation so far: ...") and a short answer stand
  for the turns before it, which stay on the screen, dimmed. New still
  starts afresh.
- **Short answers** (the page): one fixed sentence more in the system
  prompt, and `max_tokens` 1024 instead of 4096.
- **Ctrl+Return** sends one question to the cheapest model.
- A hint on the status bar (in place of the tokens) when a turn sent
  more than 8 KB: "Long conversation: each question resends it. New
  starts fresh."

**The prompt cache.** The request asks the API to cache what it has
seen (a top-level `cache_control`: the API puts its breakpoint on the
last block and moves it on as the conversation grows), and nothing in
the request changes from one turn to the next but the new question: the
system prompt is fixed (one per setting: short answers add one fixed
sentence), the old messages go byte for byte as before. So the turns
before are read from the cache (the "cached" tokens, a tenth of the
price or less). What changes the start of the request costs one full
read again: switching the model, Remember (the first message moves),
an old code block shortened, a compaction.

The page's settings are kept in `CLAUDE.CFG`: `remember=all` (or `10`, `4`,
`1`), `answers=normal` (`short`), `oldcode=short` (`full`),
`compact=asked` (`auto`).

## What to know

- **Every turn sends the whole conversation** (the API remembers
  nothing between requests; above: Remember, Compact, old code
  shortened). It is kept in 32 KB of RAM (the whole chat stays in its file); when that is full the oldest
  turns are dropped (a note says so) and Claude no longer sees them.
- **Errors**: a wrong key (401) or a busy API (429, 529) show a box and
  put your text back in the input box: Return sends it again. A reply
  that Claude declines (a refusal) is marked and left out of the
  conversation; rephrase and try again. A reply cut by its length limit
  is kept, with a note.
- The answer comes as fast as the modem and the X16 can take it: about
  2 to 3 KB/s of the API's stream (much of it is the stream's own
  framing), so a long reply shows a few lines a second.
- Alt+Tab works while a reply comes: the modem holds the connection.

## For developers

Requests are `POST /v1/messages` (HTTP/1.1, `Connection: close`, one
connection a turn) with `anthropic-version: 2026-10-21` and
`anthropic-beta: server-side-fallback-2026-07-01`; the body has
`"stream": true`, `"fallbacks": "default"` (a declined request is
retried on another model by the API; not for Haiku, which has none),
`"output_config": {"effort": "low"}`, a top-level `cache_control`,
`max_tokens` 4096 and no `thinking` (Opus 5.5 always thinks; its thinking
blocks come empty and are skipped). The reply's server-sent events are
read byte by byte (`parse.c`): the status, chunked transfer, the JSON of
each event; text deltas are folded from Unicode to the font (V143:
Veranda's set ISO-8859-16 at $A0-$FF, the ROM's glyphs of it, so Polish
is kept and typed with right Alt; CP437's symbols below $20 and its box
lines at $80-$9F; typographic quotes, dashes and the ellipsis to ASCII;
emoji to `?`). What is sent goes as JSON's \uXXXX escapes of each
character's Unicode.

In bridge mode the request is the same (the bridge ignores the
API-only fields); it is sent with plain `ATC` (`net_tls` off). The bridge
answers in the API's shapes: `message_start`, `content_block_start`,
`content_block_delta` (`text_delta`, as Claude Code's partial messages
come), `content_block_stop`, `message_delta` (stop_reason, usage),
`message_stop`, pings while Claude Code thinks; its failures as an
`error` event, or 401 / 400 / 503 / 529 with the API's error JSON.

The code blocks, files and what a turn sends (DECISIONS V123) are three
banks of their own: `code.c` (the blocks, the clipboard: the SDK's
scrap library compiled there), `file.c` (saved, tokenized, attached:
the ROM's crunch ported; `tools/x16basic.py` is the host's reference,
`basictok.h` its keyword table) and `conv.c` (a turn's plan, compaction,
the usage, the Conversation page), and `hist.c` the chats. The scroll
bar (the SDK's `vrscroll.c`) and the menus are `sbar.c`'s, beside the
parser in overlay 3 (V149). 15 RAM banks in all; Alt+Tab works at 512
KB.

Build: `make` (against `build/sdk`), `make test`, `make run`. The gates
are `tools/gate_claude.sh` (a fake API on localhost,
`tests/claude_server.py`, never the real one) and
`tools/gate_claude_bridge.sh` (the real bridge on localhost running a
fake Claude Code, `tests/fake_claude.py`; and the bridge on its own,
`tests/test_claude_bridge.py`).

MIT licence (see LICENSE).
