# AI help on a program's text: the request files (DECISIONS V199)

A program (Veranda Write first) can ask **Veranda Ask** to work on a
piece of text: rewrite it, shorten it, fix its grammar and spelling,
translate it between English and Polish, summarise it, or answer a
question about it. Veranda Ask does the talking to OpenAI, with the
sign-in or API key the user set up in Veranda Ask (no second login, no
key in the asking program). The user sees what is asked and what goes
out, and confirms with **Send** before anything leaves the X16; then
sees the answer and chooses **Use this**, **Try again** or **Cancel**.

It is optional: nothing happens unless the user picks it in the asking
program; Veranda Ask need not be set up (the program is told so).

The hand-off is V198's: the asking program writes its request files and
`START.REQ`, puts itself aside, the desktop starts Veranda Ask, and
Veranda Ask brings the program back when it is done.

All the files are in **`/VERANDA/.SYSTEM`** (`vr_cd(VR_DATA)`).

## 1. What the asking program writes

Delete `AI.OUT` and `AI.RES` first (left from an earlier request), then
write, in this order:

### AI.IN: the text

- The selected text, in **Veranda's set, ISO-8859-16** (the Polish
  letters as the font has them), with no formatting codes (only the
  characters).
- A paragraph ends with **CR** (`$0D`); CR LF and LF are taken too.
- **8,192 bytes at most.** A longer text is not sent: Veranda Ask shows
  "The text is too long for Veranda Ask: 8,192 characters at most." and
  answers `error too-long` (below). The asking program should check the
  length itself first and say so without starting Veranda Ask.
- TAB becomes a space. Other control characters and the bytes
  `$7F`-`$9F` are dropped.
- Empty (or missing): `error no-text`.

Veranda Ask deletes AI.IN as soon as it has read it (the text does not
stay on the card).

### AI.REQ: the request

Plain text, one item a line, CR LF (or LF):

    AIREQ 1
    action <action>
    question <text>
    back <program name>

- `AIREQ 1`: the format's version (must be there; a later format will
  say `AIREQ 2`).
- `action`: one of

  | action         | what is asked of the model                                  |
  |----------------|-------------------------------------------------------------|
  | `rewrite`      | rewrite it clearly, the same meaning, tone and length      |
  | `shorten`      | about half as long, its main points and tone kept          |
  | `grammar`      | grammar, spelling and punctuation corrected, nothing else  |
  | `translate-en` | translated into English                                    |
  | `translate-pl` | translated into Polish                                     |
  | `summarise`    | summarised in a few sentences, in the text's language     |
  | `ask`          | the `question` answered about the text                     |

  (`summarize` is taken for `summarise`.)
- `question`: only for `ask` (required there): the user's question, one
  line, ISO-8859-16, 200 bytes at most (cut there).
- `back`: the name the asking program runs as (its GEOS name: the shell
  starts Write as `Veranda Write`), 17 characters at most. When Veranda
  Ask ends it brings back the program of that name that is aside
  (TaskCtl `TASK_INFO`, `TASK_RESUME`); without the line, or when no such
  program is aside, the desktop comes.

Unknown lines are ignored. Veranda Ask reads at most 255 bytes of
AI.REQ and deletes it at once.

### START.REQ, then aside

    /VERANDA/APPS/Veranda Ask

(the path of Veranda Ask, from `vr_cd(VR_APPS)`; a line, CR LF), as V198
describes. Then `TaskCtl(TASK_ASIDE, 0, 0)`: the desktop starts, reads
and deletes START.REQ, and starts Veranda Ask.

If Veranda Ask is already aside, the desktop starts a second copy for
the request (the first stays aside as it was).

## 2. What Veranda Ask does

1. At its start it looks for AI.REQ. None: a normal start.
2. AI.REQ unreadable (no `AIREQ 1`, an unknown action, `ask` with no
   question): a box, `error bad-request`, back.
3. Not set up: no sign-in (the ChatGPT plan) or no key (an API key),
   in Veranda Ask's Settings: a box ("Veranda Ask is not signed in." /
   "Sign in in Veranda Ask first.", or "Veranda Ask has no OpenAI API
   key."), `error not-set-up`, back. Only these are `not-set-up`. The
   user's stored sign-in is used as it is (an expired access token is
   renewed, as for any turn); the asking program never sees it.
   The network card unusable (none found, or no two RAM banks for its
   driver: a program aside holds them): a box, `error network`, back.
4. Otherwise its window shows:
   - the toolbar: **Send**, **Cancel**, and the action and
     the model ("Rewrite - GPT-6.2 Sol");
   - in the conversation a note: who asks, what, that the message below
     goes to OpenAI (the plan or the API key, the model) only when Send
     is clicked, that Cancel goes back with no change and nothing is
     kept in Chats;
   - the message exactly as it will be sent (the task, the question, the
     text between its markers);
   - the status bar: "Rewrite: 412 characters. Send, or Cancel (Esc)."

   **Send** (or Return): the request goes out (below). **Cancel** (or
   Esc, Ctrl+Q, the close box, Quit): `cancelled`, back. Nothing is sent
   before Send.
5. The answer streams into the conversation as it comes (the preview).
   Esc or **Stop** stops it. Then:
   - a complete answer: **Use this** (Return), **Try again** (T: the
     same request again, the answer replaced), **Cancel**;
   - no answer, or a cut one (an error, the connection lost, the usage
     limit: Veranda Ask's own boxes and notes say why): **Send** (again),
     **Cancel**. A modem that does not answer at Send: it is looked for
     again once ("Looking for the modem: Send again in a moment."); still
     silent at the next Send: `error network`, back.
6. **Use this**: AI.OUT and AI.RES written, back.

What is sent: one request (Veranda Ask's normal one: `POST
/v1/responses`, `store: false`, streamed) with a system prompt of its
own (`rq_sys` in `apps/ask/rq.c`: only the result, no introduction or
comment, no Markdown, the paragraphs kept, the language kept unless
translating, plain characters) and **one message**: the task line (for
`ask` also "Question: ..."), a blank line, `<<<TEXT`, the text,
`TEXT>>>`. No earlier conversation, no chat file, no compaction, and
Veranda Ask's "short answers" and own system prompt do not apply. ASK.LOG
holds what it holds for any turn (the request's length, never its text
or a token).

## 3. What the asking program reads when it is back

### AI.RES: the result (written last)

CR LF lines:

    AIRES 1
    <result>
    <key> <value>
    ...

| result                | lines after it                                                                 |
|-----------------------|--------------------------------------------------------------------------------|
| `ok`                  | `action <action>`, `service plan` or `service api`, `model <model sent>`, `bytes <AI.OUT's length>` |
| `cancelled`           | none: the user chose Cancel (or Esc, Quit); no AI.OUT                          |
| `error not-set-up`    | `message <text>`: not signed in, or no API key (only these)                    |
| `error network`       | `message <text>`: no network card, no RAM banks for it, the modem silent        |
| `error too-long`      | `message <text>`: AI.IN over 8,192 bytes                                       |
| `error no-text`       | `message <text>`                                                               |
| `error bad-request`   | `message <text>`                                                               |
| `error write`         | `message <text>`: AI.OUT could not be written                                  |

The `message` is plain ASCII, for the asking program's own box. For
`not-set-up` it should tell the user how to set it up: start Veranda
Ask, Settings: sign in with ChatGPT or an API key (Veranda Ask's
manual page). Any other code (`network` among them, V201; a code a later
Veranda Ask may add): show its `message` as it is; it says what is wrong.

**No AI.RES** when the program is back means the request is still open
(the user put Veranda Ask aside with Alt+Tab and came back through the
dock): say "Veranda Ask has not answered yet" and keep nothing.

### AI.OUT: the answer (with `ok` only)

- ISO-8859-16, **CR** at each paragraph's end (no LF), no formatting.
- Blank lines and spaces at its start and end left out; the markers
  `<<<TEXT` / `TEXT>>>`, if the model sent them back, left out.
- The characters Veranda's set has not (shown with Veranda Ask's
  private glyphs, `$80`-`$9F`) are `?`; other control characters a
  space; TAB stays.
- Up to about 15 KB (what the conversation keeps of a reply); a cut
  answer is never offered for Use this.

The asking program replaces the selection with AI.OUT (or, for
`summarise` and `ask`, may show it or insert it after the selection: its
own choice), then deletes AI.OUT and AI.RES.

## 4. Limits

- The text: 8,192 bytes; the question: 200 bytes; the answer: about 15 KB.
- Only Veranda Ask hosts it (OpenAI: the ChatGPT plan or an API key).
  Veranda Claude does not read these files yet.
- One request at a time: a second one before the first's AI.RES is read
  replaces the first's files.
- The answer is whatever the model returns; the system prompt asks for
  the transformed text only, but the user should read it before Use this.

## 5. Tests

`tools/gate_ask.sh` (`ONLY=request`), `tests/check_aireq.py` (the runs,
what the fake server must receive, what AI.OUT must hold),
`tests/ai_standin.c` (a stand-in for Veranda Write: the whole hand-off
through the real desktop), `tests/fake_openai.py` (its answers to a
request: `request_answer`).
