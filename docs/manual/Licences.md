# Licences

## Veranda

Veranda (the kernel, the desktop, the SDK, the tools and the programs in
this repository's `apps/` folder) is under the **MIT licence**.
Copyright (c) 2026 Marcin Spoczynski. See [LICENSE](../../LICENSE).

This includes: the desktop, Paint, Colour Paint, Veranda Edit, View, Archive, Term,
Veranda FTP, Veranda Gopher, Veranda Gemini, Veranda Chat, Veranda
Claude, Veranda Ask, Disk Tools, About this X16, Veranda Update, FontEd,
Calculator, Note Pad, Dex, Calendar, Preferences, Photo Manager, Text
Manager, Veranda Setup, VeraBASIC and VeraBASIC Run, the fonts Gate
Sans and Gate Mono, the desktop pictures Dusk, Still Water, Low Hills and Sunroom Tiles, the icons, and
the PC helpers in `/PC`.

Code that came from elsewhere into Veranda's tree:

- **Packet16**, Marcin Spoczynski's FTP client for the X16 (MIT): the FTP
  protocol and the modem driver (`vrnet`) of the network programs.
- **Commander Calc**'s inflate code (MIT, the same author): Veranda
  Gemini's PNG decoder is based on it.

Programs that were **read but not copied** (no code taken): Bo
Zimmerman's geoBrowser (Apache-2.0) for View, GEOS-W128's BBS client
for Term's features.

## Programs from other repositories

These programs come from their own repositories and keep their own
licences:

| Program | Licence | Author, origin |
|---|---|---|
| Veranda Write (Commander Write) | MIT | Copyright (c) 2026 Marcin Spoczynski. Its spelling dictionaries are a separate download with their own licences: EN.DIC from SCOWL (its permissive notice, EN.DIC.txt), PL.DIC from Morfologik (BSD 2-clause) chosen by FrequencyWords (CC BY-SA 4.0), PL.DIC.txt. |
| Veranda Calc (Commander Calc) | MIT | Copyright (c) 2026 Marcin Spoczynski |
| MOD Player (x16-mod) | MIT | Copyright (c) 2026 Marcin Spoczynski. Its own replay engine. Martin Cameron's micromod (BSD 3-Clause) is used only as a test reference and is not in the player. |
| VIDKIT Player | MIT | Copyright (c) 2026 Anthony W. Henry. The parts of its window ported from MOD Player keep their notice (Copyright (c) 2026 Marcin Spoczynski, MIT). Built with Prog8 and Prog8 for Veranda (below). |
| VIDKIT | MIT | Copyright (c) 2026 Anthony W. Henry: the banked-RAM video and audio streaming library, packed inside VIDKIT Player. |
| Lighthouse Pinball | MIT | Copyright (c) 2026 Marcin Spoczynski; an original game |
| Harbour Walls | MIT | Copyright (c) 2026 Marcin Spoczynski; an original game |
| SID Player | GPL-3.0-or-later | a port of the CommanderSID project's player, Copyright (C) 2026 Marcin Spoczynski. No C64 ROMs and no tunes are included. |
| Veranda Solitaire | GPL-3.0-or-later | Copyright (C) 2026 the Veranda Solitaire authors. The rules are PySolFC's (github.com/shlomif/PySolFC; PySol by Markus F.X.J. Oberhumer, PySolFC by Skomoroh and its maintainers and contributors), translated into C. Deal numbers from pysol_cards (Shlomi Fish, Expat licence). The cards are drawn for Veranda. |
| geoChess | the author's permission (see below) | Scott Hutter |

### geoChess

geoChess is by **Scott Hutter** ([github.com/geos64128/geochess](https://github.com/geos64128/geochess)),
with contributions from the authors in its repository's history. Its
source says: *"You are free to modify this code as desired, as long as
original author credit is mentioned for both the GEOS code and the
included AI engines."* The upstream repository has **no licence file**;
this permission is the only statement of terms.

Its chess engine is derived from **BMCP v1.0 by Maksim Korzh**
(chessprogramming.org/BMCP), itself based on ideas from **micro-Max by
H.G. Muller**. The engine's header carries Maksim Korzh's notice (the
WTFPL, version 2).

The Veranda port of geoChess is kept with geoChess, not in Veranda's
MIT tree.

### Prog8 and Prog8 for Veranda

VIDKIT Player is written in **Prog8**
([github.com/irmen/prog8](https://github.com/irmen/prog8), Irmen de
Jong). The Prog8 compiler is under the **GPL-3.0**; the programs it
builds are not covered by it (its README: the files the compiler
creates "are excluded from the GPL and are free to use in whatever way
desired").

**Prog8 for Veranda** ([github.com/veranda-x16/veranda-prog8](https://github.com/veranda-x16/veranda-prog8)),
the kit the player is built with, is under the **MIT licence**,
Copyright (c) 2026 Anthony W. Henry. Its parts taken from Veranda (the
API library made from Veranda's API list, the look ported from the SDK)
keep Veranda's notice: MIT, Copyright (c) 2026 Marcin Spoczynski.

## Other GEOS programs

Veranda uses GEOS's programming interface, so other GEOS programs whose
source is available can be ported to it. Such ports keep their own
authors' terms and are not covered by this manual.

## Services the network programs use

These are run by other people. Veranda's programs only talk to them:

- **NewsWaffle** and **Gemipedia** (gemi.dev, by Acidus): web pages and
  Wikipedia as Gemini pages, used by Veranda Gemini. Wikipedia's text
  is under Wikipedia's own licences.
- **Anthropic's API** and **Claude Code**: Veranda Claude. **OpenAI's
  API** and Sign in with ChatGPT: Veranda Ask. Your use follows their
  terms.
- **Zimodem** is the modem's firmware on the ESP32; it is not part of
  Veranda.
