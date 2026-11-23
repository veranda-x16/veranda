# Network setup

Veranda's network programs go online through **TexElec's Serial & ESP32
Network Card**: a card for the X16's expansion slot with an ESP32 chip
that works as a **Wi-Fi modem**. The ESP32 runs the **Zimodem**
firmware, which takes AT commands.

The network programs: [Term](Term.md), [Veranda FTP](Veranda-FTP.md),
[Veranda Gopher](Veranda-Gopher.md), [Veranda Chat](Veranda-Chat.md),
[Veranda Gemini](Veranda-Gemini.md), [Veranda Claude](Veranda-Claude.md),
[Veranda Ask](Veranda-Ask.md) and [Veranda Update](Veranda-Update.md).

## 1. The card

- The card's serial port for the ESP32 is at address **`$9FE0`** from
  the factory. Its DIP switches can move it to another 16-byte range
  from `$9F60` to `$9FF0`. The network programs look for it in all ten
  places, from `$9F60` up. Term uses its own setting (`$9FE0` at first;
  Settings, key P, looks for the card).
- The card's crystal is 14.7456 MHz. This is Term's default.
- Veranda finds the modem's speed by itself: it says `AT` at 115200,
  57600, 38400, 19200 and 9600 baud until the modem answers.

## 2. Check the modem

Two ways:

- **About this X16**: click **Ask the modem**. It sends only `AT` and
  `ATI` and shows the firmware's line (Zimodem's version). See
  [About this X16](About-this-X16.md).
- **Term**: start Term. Its window is a terminal to the modem. Type `ATI`
  and press Return. The modem answers with its version. `ATI2` shows
  its IP address.

## 3. Join your Wi-Fi network

The Wi-Fi network is set **in the modem**, not in Veranda. The modem
keeps it after you turn the X16 off.

In Term, while not connected, type Zimodem's setup command:

    AT+CONFIG

and follow Zimodem's own menu to choose your network and type its
password. (This menu is Zimodem's, not Veranda's: see Zimodem's
documentation if it looks different.) Then check with `ATI2` that the
modem has an IP address.

## 4. TLS: does your modem know ATCS?

The X16 cannot encrypt a connection itself. For **TLS** (the encryption
that HTTPS and Gemini need), Veranda asks the modem to do it, with
Zimodem's command `ATCS"host:port"`. These programs need it:

| Program | Needs TLS |
|---|---|
| Veranda Gemini | yes (port 1965) |
| Veranda Claude with an API key | yes |
| Veranda Ask | yes |
| Veranda Update from GitHub | yes (port 443) |
| Term, FTP, Gopher, Chat | no |
| Claude Code on your PC, Update from your PC | no (plain connections on your home network) |

`ATCS` is in Zimodem's source, but not in its README. If a TLS program
always fails at once with "Could not connect ... (refused, or no such
host)", your firmware may not have `ATCS`: update Zimodem on the ESP32.

## Security: what you must know

- **The modem does not check certificates.** The connection is
  encrypted, but the modem does not check that the server is the real
  one. Someone who controls your network could pretend to be the server
  and read what you send. Use a network you trust.
- **Keys, tokens and passwords are stored as plain text on the SD
  card**, in `/VERANDA/.SYSTEM`:

| File | What is in it |
|---|---|
| `CLAUDE.CFG` | your Anthropic API key, the bridge's password |
| `ASK.CFG` | your ChatGPT sign-in tokens, your OpenAI API key |
| `FTP.SITES` | FTP passwords |
| `CHAT.SERVERS` | IRC server passwords |

  The card is FAT32: it has no file permissions. **Anyone who has your
  card can read them and use your accounts.** Keep the card to
  yourself. Do not lend it with these files on it.
- The PC helpers (`claude_bridge.py`, `chatgpt_signin.py`,
  `web_proxy.py`, `update_server.py`) talk to the X16 over your home
  network **without encryption**. They accept only private (home
  network) addresses. **Never open their ports to the Internet.**

## The PC helpers

The package's `/PC` folder has small Python 3 programs. Copy them to a
PC on the same network as the X16 and run them there.

| Helper | For | Port on the PC |
|---|---|---|
| `claude_bridge.py` | Veranda Claude with your claude.ai plan (through Claude Code) | 8642 |
| `chatgpt_signin.py` | Veranda Ask: Sign in with ChatGPT | 8643 (and 1455 free for the browser) |
| `update_server.py` | Veranda Update from your own package | 8644 |
| `web_proxy.py` | Veranda Gemini: web pages through your own proxy | 1965 |

## Checklist

- The card is in, its Wi-Fi is set (Term: `ATI`, `ATI2`).
- For Gemini, Claude, Ask and Update from GitHub: Zimodem with `ATCS`.
  Port 1965 must be open on your network for Gemini.
- For a PC helper: the PC is on the same network, and its port is open
  to the X16 (a firewall on the PC may block it).

## When it does not work

See [Troubleshooting](Troubleshooting.md#the-modem-does-not-answer).
