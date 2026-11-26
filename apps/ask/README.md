# Veranda Ask

A conversation with OpenAI's models for Veranda (DECISIONS V116), through
the Wi-Fi modem of TexElec's "Serial & ESP32 Network Card" (Zimodem; the
SDK's `vrnet`, `docs/NET.md`). It uses **your ChatGPT plan** (ChatGPT Plus
or Pro) through OpenAI's "Sign in with ChatGPT" plan usage for locally run
apps, or **an OpenAI API key** (paid by the token). It talks to the
Responses API (`https://api.openai.com/v1/responses`), streamed.

It is Veranda Claude's sibling: the same window, conversation, keys, Stop,
File > Save, Alt+Tab (see `apps/claude/README.md`); it is built from
Veranda Claude's files (with `-DASK`) and its own.

## Before you start

The same two things as for Veranda Claude: the modem must know `ATCS`
(Zimodem's TLS connect: check its version with `ATI` in Veranda Term),
and the modem does **not** check the server's certificate (use a network
you trust).

## Sign in with ChatGPT (your plan)

The X16 has no web browser, so the sign-in is done on a PC on your home
network, the way OpenAI describes it for a machine without one: the
browser on the PC signs in **for the X16** (its own host ID), and the
credentials go to the X16, which renews them itself from then on. The PC
keeps no copy.

1. Copy `PC/chatgpt_signin.py` from the SD card to a PC with a browser and
   Python 3, and run it there:

       python3 chatgpt_signin.py

   It prints a 6-digit code and the PC's address (port 8643).
2. In Veranda Ask: **Settings**, Server **ChatGPT plan**, the PC's address
   (`192.168.1.20:8643`), **Tab**, the code, then **Return** (or click
   **Continue with ChatGPT**). The page closes; the status bar says
   "Signing in: finish in the browser on your PC".
3. On the PC the browser opens OpenAI's sign-in page: sign in, allow
   Veranda Ask. The X16 gets its credentials in the reply to its request,
   says "Signed in", and the first time shows the plan's notice ("You're
   using your ChatGPT plan ... Got it"). The helper exits.

Or, with the X16's card in the PC: `python3 chatgpt_signin.py --card
/path/to/the/card/VERANDA` writes the credentials into
`VERANDA/.SYSTEM/ASK.CFG` directly.

The code works for one sign-in; five wrong codes stop the helper. Only
private addresses may connect to it (127/8, 10/8, 172.16/12, 192.168/16,
IPv6 local). The code and the credentials cross your network as plain
HTTP during the sign-in. Esc on the X16 cancels a sign-in (the helper
ends it; tokens that came too late are revoked).

**While you use the plan** the toolbar says "Using ChatGPT plan: <the
model>" and the status bar "Manage usage: chatgpt.com/settings/usage"
(the X16 cannot open links: the address is shown). The models are the
plan's own list, fetched at the sign-in (up to 8, in OpenAI's order):
choose one in Settings.

**Renewal:** an access token lasts an hour. When the X16's clock says it
has expired (its JWT's `exp`, 2 minutes early), or the API refuses it
(401) while the clock cannot say (not set, or found wrong) or the error
says the token expired, Veranda Ask renews it once with the refresh
token, writes the new
pair to ASK.CFG **before** using it (the refresh token rotates: an old one
is dead), and sends the turn again. The clock is trusted only when it is
set (2026 or later; an unset X16 reads 1 January 2000, and the status bar
then says "Set the clock: click "Set clock" in the menu bar") and a fresh
token is not already expired by it (a wrong time zone): otherwise the turn
goes and a 401 renews. Whatever came whole of a 200's tokens is kept, however the
connection ended (Content-Length, chunked, keep-alive or closed): a new
access token with the old refresh token when no new one came, a new
refresh token alone when the access token is longer than 5,119
characters (the next turn renews first). What could not be kept is said
precisely ("the reply's access_token is longer than 5119", "no
access_token in the reply", "the reply was cut at N bytes").
A 401 for a token the clock says is still good is not renewed (OpenAI
renews near a token's end, and a 401 alone does not say the sign-in has
ended): the box says "The plan did not accept the sign-in (401). Kept.",
the tokens stay, and ASK.LOG has OpenAI's reason; see **When the plan
refuses** below.

**ASK.LOG** (`/VERANDA/.SYSTEM/ASK.LOG`, written after every request,
2.5 KB at most): the last renewal (with the turn whose 401 asked for it)
and the last turn: the request line, its Host, the length and byte sum
of the token it carried ("authorization: Bearer + 2046 bytes, sum
41234", or the renewal's "refresh_token: ..."; never the token), the
body's length; the status line and the headers that matter (lower case,
260 bytes of them at most; Date, Server, Alt-Svc and the like left out;
a Set-Cookie's value never), a renewal's JSON keys and their values'
lengths, an error's body (360 bytes) with every token-like string cut to
its first 6 characters, the result, the host, the X16's clock, the
bytes. No token,
no cookie: it can be photographed or copied to a PC when something fails.
Esc during a renewal lets it finish (so the new tokens are kept), then
stops the turn. A network failure keeps the old credentials. When the
sign-in has ended for good (the refresh token expired after 30 days,
reused, revoked), it says **"The sign-in has ended: sign in again from
your PC"**; the X16's host ID and client_id are kept for that.

**The plan's limits:** "Usage limit reached. Review your plan or this
app's limit in ChatGPT settings: chatgpt.com/settings/usage" (no reset
time is given); "Your ChatGPT plan can't be used in this app: Plus or Pro
is needed" (not eligible: use an API key instead); "Plan usage is not
available right now: try again later".

## When the plan refuses

Put the card in the PC and run

    python3 /path/to/the/card/PC/chatgpt_signin.py --card /path/to/the/card/VERANDA --check

It signs in as `--card` does, then sends from the PC exactly the
X16's own turn ("Reply with OK": the same headers, body and model as
ASK.CFG gives the X16) and its renewal, and says what happened, with
OpenAI's error body (anything token-like cut to 6 characters; no token
is ever printed). "PC call OK" means OpenAI takes the request: then the
X16's sending is the suspect, and the next ASK.LOG's "authorization:
Bearer + N bytes, sum S" should equal the access token's N and S that
the check prints. "PC call 401" shows OpenAI's reason. A renewal that
works writes the new tokens to the card. The renewal waits for the
token reply's `earliest_refresh_at` when it is less than 5 minutes
away, and is not tried when it is further.

## Your tokens on the card

The credentials (the client_id OpenAI issued to this X16, the access and
refresh tokens) are kept **as plain text** in
`/VERANDA/.SYSTEM/ASK.CFG`. The SD card is FAT: there are no file
permissions. Anyone with the card can use your plan through them, until
they expire or you sign in again. The card is yours to keep: don't lend
it with them on it (Settings > OpenAI API key and deleting the `access=`
and `refresh=` lines, or the file, removes them).

## An OpenAI API key instead

Settings, Server **OpenAI API key**: type or paste (Ctrl+V) the key
(platform.openai.com, API keys; paid by the token), Tab, the model's name
(`gpt-6.2-sol` by default). Or a line `key=sk-...` in ASK.CFG from a PC.
The same request goes out with the key as its bearer.

## ASK.CFG

    server=plan              (or api)
    model=gpt-6.2-sol        the plan's model
    apimodel=gpt-6.2-sol     the API key's model
    key=sk-...               the API key
    signin=192.168.1.20:8643 the PC's helper
    host_id=urn:uuid:...     this X16's ext_agent_host_id (kept for good)
    client_id=oaiapp_...     issued at the first sign-in
    login=you@example.com    the next sign-in's login_hint
    expires=3600, got=...    the access token's life, when it came (the X16's clock)
    m=gpt-6.2-sol GPT-6.2 Sol   the plan's models (up to 8)
    notice=1                 the plan's notice was seen
    system=...               a system prompt of one's own (one line)
    access=..., refresh=...  the tokens

It is written as ASK.TMP, then ASK.CFG is replaced by it (read: ASK.CFG,
else ASK.TMP). Tests only: `api=host:port`, `auth=host:port`, `tls=0`.

## Code in replies

When the reply has code, the model is asked to put it in a Markdown fenced
block (a line ```` ``` ```` with the language, the code, a line
```` ``` ````). Veranda Ask finds these blocks when the reply has come:
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
8 KB of text at most (the conversation keeps 24 KB).

Then a reply's block in the same language is the file's next version:
its [Save...] offers the file's own name ("Replace GAME.PRG?"), and a
`.PRG` is tokenized again, so "attach, ask to fix line 30, save over the
file, run it" is a short loop. Only the newest version of the file is
sent whole; the older ones go as "[GAME.PRG, older version, 23 lines]".

Running the program from Ask is not there yet: Veranda's way to
BASIC (`ToBASIC`, the shell's BASIC) types at most 10 characters for
BASIC, in the system folder; quit to BASIC and `LOAD"/DOCUMENTS/GAME.PRG"`.

## Chats: every conversation kept

After every turn the conversation is saved to
`/DOCUMENTS/Chats/Ask` (the folders are made when missing): one file a
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
    app=Ask
    title=How do I draw a circle
    model=gpt-6.2-sol
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
  1,484 (cached 34) out 42" (with the ChatGPT plan no money is shown, only tokens; with an API key also tokens only: OpenAI's prices are not in the program). Settings > Conversation... shows the
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
  to the cheapest model (the plan's cheapest: a model named "nano", else "mini"; with an API key the one model typed) summarises the conversation in 150
  words at most; from then on the summary (sent as your message,
  "Summary of our conversation so far: ...") and a short answer stand
  for the turns before it, which stay on the screen, dimmed. New still
  starts afresh.
- **Short answers** (the page): one fixed sentence more in the system
  prompt.
- **Ctrl+Return** sends one question to the cheapest model.
- A hint on the status bar (in place of the tokens) when a turn sent
  more than 8 KB: "Long conversation: each question resends it. New
  starts fresh."

**The prompt cache.** OpenAI caches the start of a request by itself
when it was seen shortly before. Nothing in the request changes from one
turn to the next but the new question: the instructions are fixed (one
per setting), the old messages go byte for byte as before, so the
"cached" tokens grow with the conversation. Remember, a shortened block
or a compaction change the start once.

The page's settings are kept in `ASK.CFG`: `remember=all` (or `10`, `4`,
`1`), `answers=normal` (`short`), `oldcode=short` (`full`),
`compact=asked` (`auto`).

## Help with another program's text

Another program (Veranda Write first) can ask Veranda Ask to rewrite,
shorten, correct, translate (English, Polish), summarise a text, or
answer a question about it (DECISIONS V199; the files and their format:
`docs/AIREQ.md`). The program writes `/VERANDA/.SYSTEM/AI.IN` (the text)
and `AI.REQ` (the action, `back` its name), and `START.REQ`, and goes
aside; the desktop starts Veranda Ask, which shows the request (the
message exactly as it would go) with **Send** and **Cancel**: nothing
leaves the X16 before Send. The answer streams into the window; then
**Use this** (`AI.OUT`, `AI.RES` "ok"), **Try again** or **Cancel**
(`AI.RES` "cancelled"), and the program comes back. Not signed in, or
no key: a box, `AI.RES` "error not-set-up"; no network card, no RAM
banks for it, the modem silent: a box, `AI.RES` "error network" (V201).
An expired access token is renewed as for any turn. The request
uses the sign-in or key of Settings, a system prompt of its own and its
one message; it is not kept in Chats. `rq.c`, overlay 11.

## For developers

A turn is `POST /v1/responses` (HTTP/1.1, `Connection: close`) with
`Authorization: Bearer`, `Content-Type: application/json`, `Accept:
text/event-stream`; the body `{"model", "instructions" (the system
prompt), "input": [{"role": "user"|"assistant", "content": "..."}, ...]
(the whole conversation), "store": false, "stream": true}` and nothing
else (no `previous_response_id`, no sampling or limit fields). The reply's
events (`parse.c` with `pick.c`): `response.output_text.delta` (its
`delta`), `response.completed` (the only success; `usage`),
`response.incomplete`, `response.failed` (`response.error.code`,
`message`), `error`; a stream that ends without `response.completed` is
kept with a note. Errors: `{"error": {"code", "message", "param"}}` or
`{"detail"}`. The renewal is `POST /api/accounts/oauth/token` to
auth.openai.com, form-encoded `grant_type=refresh_token`, `client_id`,
`refresh_token`, `resource=https://api.openai.com/v1` (no scope); its JSON
is read byte by byte and its tokens go straight into a RAM bank (an access
token is about 2 KB: room for 5,119 characters, the refresh token 1,023),
into the second of two credential slots (see Renewal for what is kept).
`Accept-Encoding: identity` is sent with every request. The sign-in is `POST /x16/signin` to the helper (`code`,
`host_id`, `client_id`, `login`); its reply is lines `key=value`
(`wait=1` every 10 s while the browser signs in, then the set, `end=ok`).

The helper (`tools/chatgpt_signin.py`, Python 3's standard library) does
the OAuth: PKCE S256, fresh state and nonce, the 127.0.0.1:1455 callback
listening before the browser opens, `client_id=dynamic_agent_client` and
`agent_name_hint` at the first registration (the issued client_id after),
`ext_agent_host_id`, the token exchange with the issued client_id, the
id_token's RS256 signature checked against the JWKS (in the standard
library: the PKCS#1 v1.5 padding and the SHA-256 DigestInfo exactly), its
`iss`, `aud`, `exp`, `nonce`, and the granted scope holding
`chatgpt.tokens.use.direct`; then `GET /v1/models`. It was written from
the protocol's description only; nothing of OpenAI's sample code (whose
licence is non-commercial) is in it.

Build: `make` (against `build/sdk`), `make test`, `make run`. The gate is
`tools/gate_ask.sh` (a fake of OpenAI's sign-in and API on localhost,
`tests/fake_openai.py`, its RSA key a test key; the real servers are never
called) with the helper's own test, `tests/test_chatgpt_signin.py`.

MIT licence (see LICENSE).
