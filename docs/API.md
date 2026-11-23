# Veranda API reference

Generated from `api/veranda.api` by `tools/apigen.py`; do not edit.

Registers r0-r15 are the words at `$02-$21` (rNL/rNH the bytes). A "wide" call is the 16-bit Y twin of a classic GEOS call. Dropped GEOS calls keep their address and return x = `UNSUPPORTED`.

## Classic GEOS calls

| Call | Address | In | Out | |
|---|---|---|---|---|
| `InterruptMain` | `$8800` | - | - | the interrupt's GEOS part (for applications that take over the interrupt) |
| `InitProcesses` | `$8803` | r0 table (ptr), a count (u8) | - | install a process table |
| `RestartProcess` | `$8806` | x process (u8) | - | restart a process's timer |
| `EnableProcess` | `$8809` | x process (u8) | - | make a process run at the next main loop pass |
| `BlockProcess` | `$880C` | x process (u8) | - | stop a process's events |
| `UnblockProcess` | `$880F` | x process (u8) | - | allow a process's events again |
| `FreezeProcess` | `$8812` | x process (u8) | - | stop a process's timer |
| `UnfreezeProcess` | `$8815` | x process (u8) | - | restart a process's timer where it stopped |
| `HorizontalLine` | `$8818` | a pattern (u8), r3 x1 (u16), r4 x2 (u16), r11L y (u8) | - | horizontal line with a pattern byte |
| `InvertLine` | `$881B` | r3 x1 (u16), r4 x2 (u16), r11L y (u8) | - | invert a horizontal line |
| `RecoverLine` | `$881E` | r3 x1 (u16), r4 x2 (u16), r11L y (u8) | - | copy a horizontal line from the back screen |
| `VerticalLine` | `$8821` | a pattern (u8), r3L y1 (u8), r3H y2 (u8), r4 x (u16) | - | vertical line with a pattern byte |
| `Rectangle` | `$8824` | r2L top (u8), r2H bottom (u8), r3 left (u16), r4 right (u16) | - | fill a rectangle with the current pattern |
| `FrameRectangle` | `$8827` | a pattern (u8), r2L top (u8), r2H bottom (u8), r3 left (u16), r4 right (u16) | - | rectangle outline with a pattern byte |
| `InvertRectangle` | `$882A` | r2L top (u8), r2H bottom (u8), r3 left (u16), r4 right (u16) | - | invert a rectangle |
| `RecoverRectangle` | `$882D` | r2L top (u8), r2H bottom (u8), r3 left (u16), r4 right (u16) | - | copy a rectangle from the back screen |
| `DrawLine` | `$8830` | n recover (flag), c ink (flag), r3 x1 (u16), r11L y1 (u8), r4 x2 (u16), r11H y2 (u8) | - | line: N set recover, else C set ink, C clear paper [noc] |
| `DrawPoint` | `$8833` | n recover (flag), c ink (flag), r3 x (u16), r11L y (u8) | - | point: flags as DrawLine [noc] |
| `GraphicsString` | `$8836` | r0 string (ptr) | - | interpret a graphics string |
| `SetPattern` | `$8839` | a pattern (u8) | - | select fill pattern 0-33 |
| `TestPoint` | `$883F` | r3 x (u16), r11L y (u8) | c set (flag) | c = the pixel's value |
| `BitmapUp` | `$8842` | r0 bitmap (ptr), r1L x (u8), r1H y (u8), r2L width (u8), r2H height (u8) | - | draw a compacted bitmap; x and width in cards (8 pixels) |
| `PutChar` | `$8845` | a char (u8), r11 x (u16), r1H y (u8) | - | draw a character; r11 advances |
| `PutString` | `$8848` | r0 string (ptr), r11 x (u16), r1H y (u8) | - | draw a string with style codes |
| `UseSystemFont` | `$884B` | - | - | select the system font |
| `StartMouseMode` | `$884E` | c place (flag), r11 x (u16), y y (u8) | - | pointer on; with C set placed at r11, y [noc] |
| `DoMenu` | `$8851` | r0 menu (ptr), a item (u8) | - | draw a menu and start menu handling |
| `RecoverMenu` | `$8854` | - | - | remove the last menu level |
| `RecoverAllMenus` | `$8857` | - | - | remove all menu levels |
| `DoIcons` | `$885A` | r0 icons (ptr) | - | draw an icon table and start icon handling |
| `DShiftLeft` | `$885D` | x reg (u8), y count (u8) | - | shift the word at zero page x left y times [noc] |
| `BBMult` | `$8860` | x reg (u8), y reg2 (u8) | - | byte * byte [noc] |
| `BMult` | `$8863` | x reg (u8), y reg2 (u8) | - | word * byte [noc] |
| `DMult` | `$8866` | x reg (u8), y reg2 (u8) | - | word * word [noc] |
| `Ddiv` | `$8869` | x reg (u8), y reg2 (u8) | - | word / word, remainder in r8 [noc] |
| `DSdiv` | `$886C` | x reg (u8), y reg2 (u8) | - | signed word / word [noc] |
| `Dabs` | `$886F` | x reg (u8) | - | absolute value of a word [noc] |
| `Dnegate` | `$8872` | x reg (u8) | - | negate a word [noc] |
| `Ddec` | `$8875` | x reg (u8) | - | decrement a word, Z set when it reaches 0 [noc] |
| `ClearRam` | `$8878` | r0 count (u16), r1 addr (ptr) | - | clear memory |
| `FillRam` | `$887B` | r0 count (u16), r1 addr (ptr), r2L value (u8) | - | fill memory |
| `MoveData` | `$887E` | r0 source (ptr), r1 dest (ptr), r2 count (u16) | - | copy memory (overlapping is fine) |
| `InitRam` | `$8881` | r0 table (ptr) | - | store bytes from an InitRam table |
| `PutDecimal` | `$8884` | a format (u8), r0 value (u16), r11 x (u16), r1H y (u8) | - | draw a number |
| `GetRandom` | `$8887` | - | - | update random |
| `MouseUp` | `$888A` | - | - | pointer on |
| `MouseOff` | `$888D` | - | - | pointer off |
| `DoPreviousMenu` | `$8890` | - | - | back one menu level |
| `ReDoMenu` | `$8893` | - | - | redraw the menu |
| `GetSerialNumber` | `$8896` | - | r0 serial (u16) | a constant number on Veranda |
| `Sleep` | `$8899` | r0 frames (u16) | - | continue after r0 frames (returns to the caller's caller) |
| `ClearMouseMode` | `$889C` | - | - | pointer and menu handling off |
| `i_Rectangle` | `$889F` | inline parameters | - | Rectangle with inline parameters |
| `i_FrameRectangle` | `$88A2` | inline parameters | - | FrameRectangle with inline parameters |
| `i_RecoverRectangle` | `$88A5` | inline parameters | - | RecoverRectangle with inline parameters |
| `i_GraphicsString` | `$88A8` | inline parameters | - | GraphicsString with an inline string |
| `i_BitmapUp` | `$88AB` | inline parameters | - | BitmapUp with inline parameters |
| `i_PutString` | `$88AE` | inline parameters | - | PutString with inline parameters |
| `GetRealSize` | `$88B1` | a char (u8), x mode (u8) | y width (u8) | size of a character in a style; x height, a baseline |
| `i_FillRam` | `$88B4` | inline parameters | - | FillRam with inline parameters |
| `i_MoveData` | `$88B7` | inline parameters | - | MoveData with inline parameters |
| `GetString` | `$88BA` | r0 buffer (ptr), r2L max (u8), r11 x (u16), r1H y (u8), r1L flags (u8), r4 fault (ptr) | - | text input |
| `GotoFirstMenu` | `$88BD` | - | - | back to the main menu |
| `InitTextPrompt` | `$88C0` | a height (u8) | - | text cursor of this height |
| `MainLoop` | `$88C3` | - | - | the main loop [noc] [noreturn] |
| `DrawSprite` | `$88C6` | r3L sprite (u8), r4 picture (ptr) | - | sprite picture (GEOS 24x21, 1 bpp) |
| `GetCharWidth` | `$88C9` | a char (u8) | a width (u8) | width of a character in the current font |
| `LoadCharSet` | `$88CC` | r0 font (ptr) | - | select a font |
| `PosSprite` | `$88CF` | r3L sprite (u8), r4 x (u16), r5L y (u8) | - | sprite position |
| `EnablSprite` | `$88D2` | r3L sprite (u8) | - | sprite on |
| `DisablSprite` | `$88D5` | r3L sprite (u8) | - | sprite off |
| `CallRoutine` | `$88D8` | a low (u8), x high (u8) | - | call a routine (nothing if 0) [noc] |
| `CalcBlksFree` | `$88DB` | - | r4 free (u16) | free space in blocks of 254 bytes (capped at 65535); r3 the total |
| `SaveFile` | `$88ED` | r9 header (ptr), r10L page (u8) | x error (u8) | write a GEOS file described by an info block |
| `SmallPutChar` | `$8902` | a char (u8), r11 x (u16), r1H y (u8) | - | PutChar without the style codes |
| `GetFile` | `$8908` | r6 name (ptr), r0L options (u8), r2 disk (ptr), r3 document (ptr), r7 load (ptr) | x error (u8) | load and start an application or desk accessory, or load a file |
| `FindFile` | `$890B` | r6 name (ptr) | x error (u8) | find a file; its entry in dirEntryBuf |
| `CRC` | `$890E` | r0 data (ptr), r1 count (u16) | r2 crc (u16) | CRC-16 of memory |
| `LdFile` | `$8911` | r9 entry (ptr) | x error (u8) | load a file from its directory entry |
| `LdApplic` | `$891D` | r9 entry (ptr), r0L options (u8) | x error (u8) | load and start an application from its directory entry |
| `GetFHdrInfo` | `$8929` | r9 entry (ptr) | x error (u8) | read a file's info block into fileHeader |
| `EnterDeskTop` | `$892C` | - | - | quit to the desktop: DESKTOP.cvt if there is one (another desktop the user chose), else the shell, SHELL.cvt; in /VERANDA, else the root [noreturn] |
| `StartAppl` | `$892F` | r7 start (ptr) | - | start the application in memory [noreturn] [noc] |
| `DeleteFile` | `$8938` | r0 name (ptr) | x error (u8) | delete a file |
| `FindFTypes` | `$893B` | r6 buffer (ptr), r7L type (u8), r7H max (u8), r10 class (ptr) | r7H left (u8) | names of the files of a type (and class) |
| `RstrAppl` | `$893E` | - | - | a desk accessory ends: the application that opened it comes back as it was, returning from its GetFile [noreturn] |
| `ToBASIC` | `$8941` | r0 command (ptr) | - | quit to BASIC (r0: a command for BASIC or 0): Veranda gone, its banks and the resident core freed; with r1 = TOBASIC_KEEP Veranda stays in memory (DECISIONS V64, the RBOOT model: the resident core, the kernel banks, their copy and bank RB above MEMTOP, $8800 and a lowered bank count; SYS 40608 or RBOOT comes back to the desktop in the shell's folder) [noreturn] |
| `ImprintRectangle` | `$8950` | r2L top (u8), r2H bottom (u8), r3 left (u16), r4 right (u16) | - | copy a rectangle to the back screen |
| `i_ImprintRectangle` | `$8953` | inline parameters | - | ImprintRectangle with inline parameters |
| `DoDlgBox` | `$8956` | r0 box (ptr) | r0L result (u8) | dialog box |
| `RenameFile` | `$8959` | r6 old (ptr), r0 new (ptr) | x error (u8) | rename a file |
| `InitForIO` | `$895C` | - | - | nothing on Veranda (kept for sources) |
| `DoneWithIO` | `$895F` | - | - | nothing on Veranda (kept for sources) |
| `DShiftRight` | `$8962` | x reg (u8), y count (u8) | - | shift the word at zero page x right y times [noc] |
| `CopyString` | `$8965` | x from (u8), y to (u8) | - | copy a 0-terminated string (zero page pointers) [noc] |
| `CopyFString` | `$8968` | x from (u8), y to (u8), a count (u8) | - | copy a bytes (zero page pointers) [noc] |
| `CmpString` | `$896B` | x a (u8), y b (u8) | - | compare 0-terminated strings; Z set if equal [noc] |
| `CmpFString` | `$896E` | x a (u8), y b (u8), a count (u8) | - | compare a bytes [noc] |
| `FirstInit` | `$8971` | - | - | reset the system variables |
| `OpenRecordFile` | `$8974` | r0 name (ptr) | x error (u8) | open a record file (held in banked RAM) |
| `CloseRecordFile` | `$8977` | - | x error (u8) | close it, writing it back if changed |
| `NextRecord` | `$897A` | - | x error (u8) | next record |
| `PreviousRecord` | `$897D` | - | x error (u8) | previous record |
| `PointRecord` | `$8980` | a record (u8) | x error (u8), y data (u8) | select a record; y = $FF if it holds data, 0 if it is empty (GEOS: its track) |
| `DeleteRecord` | `$8983` | - | x error (u8) | delete the current record |
| `InsertRecord` | `$8986` | - | x error (u8) | insert an empty record before the current one |
| `AppendRecord` | `$8989` | - | x error (u8) | add an empty record after the current one |
| `ReadRecord` | `$898C` | r7 dest (ptr), r2 max (u16) | x error (u8) | read the current record; r7 moves past the data (r7 at $A000-$BFFF: in the caller's bank) |
| `WriteRecord` | `$898F` | r7 source (ptr), r2 count (u16) | x error (u8) | replace the current record (r7 at $A000-$BFFF: in the caller's bank) |
| `UpdateRecordFile` | `$8995` | - | x error (u8) | write the record file back now |
| `GetPtrCurDkNm` | `$8998` | x reg (u8) | - | zero page x = pointer to the volume name [noc] |
| `PromptOn` | `$899B` | - | - | text cursor on |
| `PromptOff` | `$899E` | - | - | text cursor off |
| `OpenDisk` | `$89A1` | - | x error (u8) | read the current directory again |
| `DoInlineReturn` | `$89A4` | a count (u8) | - | return from an inline call [noc] |
| `GetNextChar` | `$89A7` | - | a char (u8) | the next key, 0 if none |
| `BitmapClip` | `$89AA` | r0 bitmap (ptr), r1L x (u8), r1H y (u8), r2L width (u8), r2H height (u8), r11L skipleft (u8), r11H skipright (u8), r12 skiptop (u16) | - | draw part of a bitmap |
| `SetDevice` | `$89B0` | a device (u8) | x error (u8) | only 8 (the SD card) exists |
| `IsMseInRegion` | `$89B3` | r2L top (u8), r2H bottom (u8), r3 left (u16), r4 right (u16) | a inside (u8) | a = $FF if the pointer is inside |
| `RstrFrmDialogue` | `$89BF` | - | - | close the dialog box (from inside it) |
| `Panic` | `$89C2` | - | - | the panic box (as a BRK): the caller's address and the application's name; OK goes back to the shell with the kernel banks restored from their copy [noreturn] |
| `BitOtherClip` | `$89C5` | r0 bitmap (ptr), r1L x (u8), r1H y (u8), r2L width (u8), r2H height (u8), r11L skipleft (u8), r11H skipright (u8), r12 skiptop (u16), r13 app (ptr), r14 sync (ptr) | - | BitmapClip with the data from a routine |
| `TempHideMouse` | `$89D7` | - | - | hide the pointer until it moves (GEOS 128) |
| `HideOnlyMouse` | `$89F2` | - | - | hide the pointer (GEOS 128) |

## Wide calls (16-bit Y)

| Call | Address | In | Out | |
|---|---|---|---|---|
| `WHorizontalLine` | `$8A00` | a pattern (u8), r3 x1 (u16), r4 x2 (u16), r11 y (u16) | - | HorizontalLine |
| `WInvertLine` | `$8A03` | r3 x1 (u16), r4 x2 (u16), r11 y (u16) | - | InvertLine |
| `WRecoverLine` | `$8A06` | r3 x1 (u16), r4 x2 (u16), r11 y (u16) | - | RecoverLine |
| `WVerticalLine` | `$8A09` | a pattern (u8), r4 x (u16), r11 y1 (u16), r12 y2 (u16) | - | VerticalLine |
| `WRectangle` | `$8A0C` | r3 left (u16), r11 top (u16), r4 right (u16), r12 bottom (u16) | - | Rectangle |
| `WFrameRectangle` | `$8A0F` | a pattern (u8), r3 left (u16), r11 top (u16), r4 right (u16), r12 bottom (u16) | - | FrameRectangle |
| `WInvertRectangle` | `$8A12` | r3 left (u16), r11 top (u16), r4 right (u16), r12 bottom (u16) | - | InvertRectangle |
| `WRecoverRectangle` | `$8A15` | r3 left (u16), r11 top (u16), r4 right (u16), r12 bottom (u16) | - | RecoverRectangle |
| `WImprintRectangle` | `$8A18` | r3 left (u16), r11 top (u16), r4 right (u16), r12 bottom (u16) | - | ImprintRectangle |
| `WDrawLine` | `$8A1B` | a mode (u8), r3 x1 (u16), r11 y1 (u16), r4 x2 (u16), r12 y2 (u16) | - | DrawLine; a = DRAW_INK, DRAW_ERASE or DRAW_RECOVER |
| `WDrawPoint` | `$8A1E` | a mode (u8), r3 x (u16), r11 y (u16) | - | DrawPoint |
| `WTestPoint` | `$8A21` | r3 x (u16), r11 y (u16) | a set (u8) | a = 1 if the pixel is set (c too) |
| `WBitmapUp` | `$8A24` | r0 bitmap (ptr), r1L x (u8), r2L width (u8), r11 y (u16), r12 height (u16) | - | BitmapUp; x and width in cards; height bit 15 (DECISIONS V81): raw rows, width bytes each, no compaction (with the clip off and the bitmap on the screen a column at a time, VERA stepping by the stride: some 5 times as fast) (API 5) |
| `WPutChar` | `$8A27` | a char (u8), r11 x (u16), r12 y (u16) | - | PutChar |
| `WPutString` | `$8A2A` | r0 string (ptr), r11 x (u16), r12 y (u16) | - | PutString |
| `WSmallPutChar` | `$8A2D` | a char (u8), r11 x (u16), r12 y (u16) | - | SmallPutChar |
| `WPutDecimal` | `$8A30` | a format (u8), r0 value (u16), r11 x (u16), r12 y (u16) | - | PutDecimal |
| `WGetString` | `$8A33` | r0 buffer (ptr), r2L max (u8), r11 x (u16), r12 y (u16), r1L flags (u8), r4 fault (ptr) | - | GetString |
| `WPosSprite` | `$8A36` | r3L sprite (u8), r4 x (u16), r11 y (u16) | - | PosSprite |
| `WIsMseInRegion` | `$8A39` | r3 left (u16), r11 top (u16), r4 right (u16), r12 bottom (u16) | a inside (u8) | IsMseInRegion |
| `WStartMouseMode` | `$8A3C` | a place (u8), r11 x (u16), r12 y (u16) | - | StartMouseMode; a <> 0: place the pointer |
| `WSetMouseRegion` | `$8A3F` | r3 left (u16), r11 top (u16), r4 right (u16), r12 bottom (u16) | - | the pointer's region |
| `WSetWindow` | `$8A42` | r11 top (u16), r12 bottom (u16) | - | the clip window's top and bottom |

## New calls

| Call | Address | In | Out | |
|---|---|---|---|---|
| `GetVersion` | `$8A45` | - | a level (u8) | API level (API_LEVEL); x.y the version |
| `SetVideoMode` | `$8A48` | a mode (u8) | x error (u8) | MODE_640x480, MODE_640x240 or MODE_320x240; clears both screens |
| `SetColors` | `$8A4B` | r0 paper (u16), r1 ink (u16) | - | paper and ink, $0RGB each (palette entries 0 and 1); $FFFF leaves one as it is (the ink alone: r0 = $FFFF); an application starts in white paper and black ink |
| `CopyRect` | `$8A4E` | r3L x (u8), r3H width (u8), r11 y (u16), r12 height (u16), r4L tox (u8), r13 toy (u16) | - | copy a screen area (x and width in cards) on the screens dispBufferOn selects; overlapping is fine |
| `ScrollRect` | `$8A51` | r3L x (u8), r3H width (u8), r11 top (u16), r12 bottom (u16), r13 dy (i16), a pattern (u8) | - | move an area up (dy < 0) or down by dy lines; the uncovered lines get the pattern |
| `ReadRow` | `$8A54` | r0 buffer (ptr), r3L x (u8), r3H count (u8), r11 y (u16) | - | bytes of a screen row (dispBufferOn bit 6: the back screen) into memory |
| `WriteRow` | `$8A57` | r0 buffer (ptr), r3L x (u8), r3H count (u8), r11 y (u16) | - | bytes from memory into a screen row (the screens dispBufferOn selects) |
| `FOpen` | `$8A5A` | r0 name (ptr), a mode (u8) | a handle (u8) | open a file: a = 'r', 'w' (create or replace) or 'm' (read and write); x = error (TOO_MANY_FILES: three streams open already, V68) |
| `FRead` | `$8A5D` | a handle (u8), r0 buffer (ptr), r1 count (u16) | r1 done (u16) | read up to r1 bytes; x = error |
| `FWrite` | `$8A60` | a handle (u8), r0 buffer (ptr), r1 count (u16) | x error (u8) | write r1 bytes |
| `FSeek` | `$8A63` | a handle (u8), r0 poslow (u16), r1 poshigh (u16) | x error (u8) | move to a byte position |
| `FClose` | `$8A66` | a handle (u8) | x error (u8) | close a file |
| `DirOpen` | `$8A69` | r0 pattern (ptr) | x error (u8) | start reading the current directory (pattern "*" for all); a pattern that starts with "=" is CMDR-DOS's listing option ("=L": the long listing, sizes in bytes and dates), sent as "$=L" ..., and DirNext then gives the lines raw (DECISIONS V70) |
| `DirNext` | `$8A6C` | r0 entry (ptr) | x error (u8) | the next entry: name (0-terminated), size, type; x <> 0 at the end; after DirOpen "=..." the next line raw: +0 'R', +1 its number (word), +3 its text 0-terminated (at most 122 bytes: a 125-byte entry), the header line first and the footer (the free space) last (DECISIONS V70) |
| `ChDir` | `$8A6F` | r0 path (ptr) | x error (u8) | change the current directory |
| `MkDir` | `$8A72` | r0 path (ptr) | x error (u8) | make a directory |
| `FDelete` | `$8A75` | r0 name (ptr) | x error (u8) | delete any file |
| `FRename` | `$8A78` | r0 old (ptr), r1 new (ptr) | x error (u8) | rename any file |
| `BankAlloc` | `$8A7B` | a count (u8) | a first (u8) | allocate RAM banks for the application; x = error |
| `BankFree` | `$8A7E` | a first (u8) | - | free them |
| `BankCopy` | `$8A81` | r0 source (ptr), r1 dest (ptr), r2 count (u16), r3L frombank (u8), r3H tobank (u8) | - | copy memory between banks (bank 0: below $A000 as it is) |
| `LoadOverlay` | `$8A84` | a record (u8), r7 dest (ptr) | x error (u8) | copy overlay record a of the running application (kept in RAM banks) to r7 (at $A000-$BFFF: in the caller's bank); r7 = 0: nothing copied, r1L (and a) the RAM bank that holds the record and r0 its address ($A000 with overlays = banked: run it there; API 2) |
| `GetMouse` | `$8A87` | - | a buttons (u8) | mouseButtons, and the wheel movement in x (cleared) |
| `GetKeyMods` | `$8A8A` | - | a mods (u8) | keyMods |
| `LogText` | `$8A8D` | r0 text (ptr) | - | write a line to the emulator's console (nothing on hardware) |
| `RecordInfo` | `$8A90` | a write (u8), r0 buffer (ptr) | x error (u8) | the open record file's info block (256 bytes, as fileHeader): to r0 (a = 0) or from r0 (a <> 0; written back with the file) |
| `ExportRect` | `$8A93` | r0 name (ptr), r3 left (u16), r11 top (u16), r4 right (u16), r12 bottom (u16), a screen (u8) | x error (u8) | write a screen area to a file (any name) as a BMP picture, rows bottom-up, padded to 4 bytes; a bit 0: 0 the foreground, 1 the back screen; bit 7 clear: 1 bpp (1 = ink, the palette's paper and ink); bit 7 set, with the colour map shown: 4 bpp in palette entries 0-15, each paper pixel in its card's colour, ink entry 1 (in tile mode, V101: 8 bpp, all 256 entries, each paper pixel its tile's); clipped to the screen (INCOMPATIBLE: nothing left) |
| `ColorRect` | `$8A96` | r3L x (u8), r3H width (u8), r11L y (u8), r11H height (u8), a colour (u8) | - | the paper colour (palette entry 0-15; 0 the normal paper) of an area of cards (8 x 8 pixels; clipped to the screen); the first call shows the colour map (every card 0), a = $FF clears and hides it (SetVideoMode does too), a = COLOR_BUF ($FE) gives each card its own colour from r0 (a byte a card, its low nibble; r3H bytes a row, the rows one after the other: a picture, DECISIONS V78; not in tile mode), a = COLOR_CANVAS ($FC, V166) the canvas (COLOR_CANVAS; normal colours do nothing while it is on), a = COLOR_TILES ($FD) shows the map in tile mode (V101: layer 0 in 4 bpp 8 x 8 tiles at VRAM_TILES, $13000-$16BFF, which the program fills with its tiles and palette rows 2-13; colour c is solid tile c in palette row 0; menus and dialog boxes then recover from the back screen; hiding the map then puts palette entries 32-255 back from VRAM_TILEPAL, $12C00, where the program keeps its rows first); the ink stays palette entry 1 (SetColors); menus, dialog boxes and desk accessories show over the normal paper (the cards under them come back after), and a card under one gets its colour when it is uncovered |
| `GetCardColor` | `$8A99` | r3L x (u8), r11L y (u8) | a colour (u8) | a card's paper colour from the colour map (0 when it is hidden; in tile mode 0 for a card of the program's own tiles) |
| `FSize` | `$8A9C` | a handle (u8) | r0 sizelow (u16), r1 sizehigh (u16), r2 poslow (u16), r3 poshigh (u16), x error (u8) | an open file's size (r0 low word, r1 high word) and position (r2, r3), from the DOS's tell command (API 2) |
| `PutCards` | `$8A9F` | r0 text (ptr), r1 font (ptr), r3L x (u8), r3H count (u8), r11 y (u16), a flags (u8) | - | text in 8 x 8 cells: r3H characters (or up to a 0) at card column r3L, top row r11; glyph c is the 8 bytes at r1 + 8 * c (rows top first); a bit 0 reverse, bit 1 bold; opaque; the screens dispBufferOn selects, the clip window's rows; r0 and r1 below $A000 (API 2) |
| `PrintOpen` | `$8AA2` | r0 name (ptr), a flags (u8) | x error (u8), r1 rowbytes (u16), r2 rows (u16), r3 width (u16) | start a document printed to a PDF file (any name; it is replaced): a = PRINT_LETTER for US Letter (else A4) + PRINT_300DPI for 300 dpi (else 150); a page is a 1 bpp bitmap of r3 dots across (r1 bytes a row, bit 7 the left dot, 1 = ink) and r2 rows; one document at a time (INCOMPATIBLE); r4-r15 changed (API 2) |
| `PrintBand` | `$8AA5` | r0 buffer (ptr), a rows (u8) | x error (u8) | a rows of the page from r0 (r1 of PrintOpen bytes each, top first; at $A000-$BFFF in the caller's RAM bank, on into the next bank at $C000), coded as they come; a page is full after its last row, and the next row starts a new page; BFR_OVERFLOW: too many pages (90 a document); r0-r15 changed (API 2) |
| `PrintPage` | `$8AA8` | - | x error (u8) | the current page ends: its rows not sent are white (with none sent: a blank page); r0-r15 changed (API 2) |
| `PrintClose` | `$8AAB` | - | x error (u8) | the document ends (a page being sent ends as with PrintPage) and the file is closed; r0-r15 changed (API 2) |
| `PrintRect` | `$8AAE` | r3 left (u16), r11 top (u16), r4 right (u16), r12 bottom (u16), a flags (u8) | x error (u8) | a screen area (clipped to the screen) printed as a page of its own of the open document, scaled at printer resolution: a bit 0 the back screen (else the foreground), PRINT_FIT the largest size inside a quarter-inch margin (else 80 screen pixels an inch, as GEOS printed, clipped at the margin), PRINT_COLOR the ink in its colour (palette entry 1) and, with the colour map shown, the paper colours; centred across, at the top; INCOMPATIBLE: no document, or nothing left; r0-r15 changed (API 2) |
| `SetClock` | `$8AB1` | r0L year (u8), r0H month (u8), r1L day (u8), r1H hour (u8), r2L minutes (u8), r2H seconds (u8), r3H weekday (u8) | - | set the date and time: the X16's battery-backed clock (the ROM's clock_set_date_time: r0L years since 1900, r0H month 1-12, r1L day, r1H hour 0-23, r2L minutes, r2H seconds, r3H day of the week 1-7) and Veranda's year ... seconds at once (API 2) |
| `DefMouse` | `$8AB4` | - | - | the system's handling of a button change (the menus, the icons, else otherPressVec), for a program's own mouseVector to pass a change on to (GEOS's mouseVector holds its handling; Veranda's is 0) (API 2) |
| `RmDir` | `$8AB7` | r0 path (ptr) | x error (u8) | remove an empty directory (API 2) |
| `SetPointer` | `$8ABA` | a shape (u8) | a old (u8) | the pointer's shape (sprite 0): PTR_ARROW, PTR_BUSY (animated), PTR_IBEAM or PTR_CROSS (their hot spot in the middle); returns the shape before; the arrow while a menu level or a dialog box is open; Veranda shows PTR_BUSY by itself while the main loop has not run for a third of a second (a file load, the loader, a long call); a program that draws sprite 0 itself (DrawSprite) gets its own picture back with PTR_ARROW + PTR_OWN (API 2) |
| `Beep` | `$8ABD` | - | - | the system beep: a short two-note chime on VERA's PSG voice 15, played by the interrupt (about a quarter of a second; the call returns at once); dialog boxes use it for errors; PlaySound(SND_ERROR) since API 4 (silent with the settings' sounds off) (API 2) |
| `SysPrefs` | `$8AC0` | a op (u8), r0 buffer (ptr) | x error (u8) | the system's settings and alarms (DECISIONS V56; r0 below $A000): a = PREFS_GET the settings block (PREFS_SIZE bytes: paper, ink, blankDelay words; the flags PREFS_NOSOUND, PREFS_MENUTICK and the pointer's speed 0-2 in bits 0-1; the video mode of programs that keep theirs, $FF none; the time zone in quarter hours; 6 bytes the control panel's; byte PREFS_VOLUME: PREFS_VOLSET + 63 - the sounds' volume, API 4) to r0, PREFS_SET from r0 (blankDelay, the sounds and the speed at once, the colours and the mode from the next program's start), ALARMS_GET the alarm table (ALARM_MAX entries of ALARM_SIZE: year 0-99, month, day, hour, minute, the state ALARM_ARMED or ALARM_DONE, a text of up to 24 characters and its 0) to r0, ALARMS_SET from r0 (entries already due are marked done); a due alarm beeps and shows a box over any program. Read at start-up from "Veranda Prefs" and "Veranda Alarms" in the system folder (API 2); DESK_GET the desktop's path (DESK_SIZE bytes, curDirName's layout; 0: not set) to r0, DESK_SET from r0: the shell's own folder, kept across programs and crashes, which applications leave alone (DECISIONS V63; API 3); r0-r3 kept |
| `LoadFont` | `$8AC3` | r0 name (ptr), a size (u8) | a handle (u8) | a font into RAM banks, once for every program: the record of that point size of the GEOS font file name (the FAT file name.cvt, up to 31 characters) in the fonts folder /VERANDA/FONTS, else in the current directory; "System" (9) and "Veranda UI" (12) are built in; returns its handle (0 the system font, FONT_UI, 2-16) for UseFont, or FONT_NONE and x the error (FILE_NOT_FOUND: no such file or size; INCOMPATIBLE: not a font; STRUCT_MISMAT; NO_BANKS; BFR_OVERFLOW: 16 fonts); r0-r3 kept (API 3) |
| `UseFont` | `$8AC6` | a handle (u8) | x error (u8) | select a font LoadFont gave (0 the system font, as UseSystemFont); text then draws with it at the speed of a font in the program's memory less the cost of a row copy (DECISIONS V62); curIndexTable and cardDataPntr are then not addresses in the program's memory: use GetCharWidth; x = INV_RECORD if there is no such font; r0-r3 kept (API 3) |
| `FontInfo` | `$8AC9` | a handle (u8), r0 name (ptr) | a size (u8) | a font's point size; r1L its height, r1H its baseline; its name to r0 (FONT_NAME_LEN bytes; r0 = 0: not wanted); x = INV_RECORD if there is no such font (API 3) |
| `FontList` | `$8ACC` | r0 buffer (ptr), a max (u8) | a count (u8) | the installed fonts: at most a names of FONT_NAME_LEN bytes at r0 ("System", "Veranda UI", then the fonts folder's in alphabetical order); r0-r3 kept (API 3) |
| `FontSizes` | `$8ACF` | r0 name (ptr), r1 buffer (ptr) | a count (u8) | the point sizes a font has (FontList's names), in increasing order at r1 (up to 62 bytes); x = the error (a = 0); r0-r3 kept (API 3) |
| `FontFlush` | `$8AD2` | r0 name (ptr) | - | forget the sizes of a font that LoadFont loaded (their RAM banks freed; the current font stays), so that the next LoadFont reads its file again: after a program wrote it (the Font Editor); r0-r3 kept (API 3) |
| `PlaySound` | `$8AD5` | a id (u8) | - | a system sound on VERA's PSG voices 14 and 15, played by the interrupt (the call returns at once; DECISIONS V69): SND_ERROR (Beep's), SND_WARNING, SND_ALARM, SND_STARTUP, SND_EXIT, SND_APP, SND_OPEN, SND_CLOSE, SND_MENU, SND_TRASH; a new sound replaces the one playing, but nothing replaces the alarm; silent with the settings' sounds off (PREFS_NOSOUND) but the alarm, SND_MENU only with PREFS_MENUTICK; the volume the settings' (PREFS_VOLUME); the kernel plays them at its own events (start-up, an application's start, a desk accessory's, a question's dialog box, a menu, the alarm, the way to BASIC); a, x, y: a changed (API 4) |
| `TaskCtl` | `$8AD8` | a op (u8), x task (u8), r0 buffer (ptr) | x error (u8) | the switcher: applications put aside whole into RAM banks (their RAM, zero page, system variables, the menus' and dialog boxes' state, their open record file and overlays, VRAM with both screens and the colour map, packed) and brought back exactly as they were; one full-screen application runs at a time (DECISIONS V83). a = TASK_INFO: task x (0 .. TASK_MAX - 1) to r0, TASK_REC bytes (TR_STATE: 0 free, TASK_ASIDE; TR_BANKS the RAM banks it holds; TR_NAME its GEOS name, 17 bytes; TR_NOTE the note it was started with, TASK_NOTE_LEN bytes), a = its state; x = $FF: the summary to r0, TASK_SUM bytes (TS_COUNT tasks put aside, TS_FREE free RAM banks, TS_BANKS RAM banks there are for programs, TS_ERR the error of the last start that failed and sent the desktop instead (NO_BANKS ...), cleared by this read, TS_NAME its name, 17 bytes); TASK_RESUME: task x comes back, where it was, and the caller ends (as by GetFile: its streams closed, its banks freed; returns only on an error); TASK_END: task x is dropped, its banks freed (what it had not saved is lost); TASK_NOTE: r0's text (up to TASK_NOTE_LEN bytes with its 0, below $A000) goes with the next application that starts and stays with it while it is aside (the shell: the program's path); TASK_ASIDE: switchReq = SWITCH_ASIDE (the caller is put aside at its main loop's next pass); TASK_ROOM: a = the RAM banks the caller may still take (API 7; DECISIONS V145: in Roomy mode a program that does not fit in the free banks is put aside onto the card); x = 0, else the error (INV_RECORD: no such task or op); r0-r3 changed (API 6) |

## GEOS calls not on Veranda

| Call | Address | In | Out | |
|---|---|---|---|---|
| `GetScanLine` | `$883C` | - | - | the screen is in VRAM: use ReadRow/WriteRow |
| `ChkDkGEOS` | `$88DE` | - | - | disk images only |
| `NewDisk` | `$88E1` | - | - | disk images only |
| `GetBlock` | `$88E4` | - | - | block access: use streams |
| `PutBlock` | `$88E7` | - | - | block access: use streams |
| `SetGEOSDisk` | `$88EA` | - | - | disk images only |
| `SetGDirEntry` | `$88F0` | - | - | directory blocks: not on FAT32 |
| `BldGDirEntry` | `$88F3` | - | - | directory blocks: not on FAT32 |
| `GetFreeDirBlk` | `$88F6` | - | - | directory blocks: not on FAT32 |
| `WriteFile` | `$88F9` | - | - | block chains: use streams |
| `BlkAlloc` | `$88FC` | - | - | block allocation: not on FAT32 |
| `ReadFile` | `$88FF` | - | - | block chains: use streams |
| `FollowChain` | `$8905` | - | - | block chains: not on FAT32 |
| `EnterTurbo` | `$8914` | - | - | no disk turbo |
| `LdDeskAcc` | `$8917` | - | - | use GetFile on the desk accessory |
| `ReadBlock` | `$891A` | - | - | block access: use streams |
| `WriteBlock` | `$8920` | - | - | block access: use streams |
| `VerWriteBlock` | `$8923` | - | - | block access: use streams |
| `FreeFile` | `$8926` | - | - | block chains: use DeleteFile |
| `ExitTurbo` | `$8932` | - | - | no disk turbo |
| `PurgeTurbo` | `$8935` | - | - | no disk turbo |
| `FastDelFile` | `$8944` | - | - | block chains: use DeleteFile |
| `GetDirHead` | `$8947` | - | - | disk images only |
| `PutDirHead` | `$894A` | - | - | disk images only |
| `NxtBlkAlloc` | `$894D` | - | - | block allocation: not on FAT32 |
| `SetNextFree` | `$8992` | - | - | block allocation: not on FAT32 |
| `FindBAMBit` | `$89AD` | - | - | disk images only |
| `ReadByte` | `$89B6` | - | - | block chains: use FRead |
| `FreeBlock` | `$89B9` | - | - | disk images only |
| `ChangeDiskDevice` | `$89BC` | - | - | disk images only |
| `StashRAM` | `$89C8` | - | - | REU: use BankCopy |
| `FetchRAM` | `$89CB` | - | - | REU: use BankCopy |
| `SwapRAM` | `$89CE` | - | - | REU: use BankCopy |
| `VerifyRAM` | `$89D1` | - | - | REU: use BankCopy |
| `DoRAMOp` | `$89D4` | - | - | REU: use BankCopy |
| `SetMsePic` | `$89DA` | - | - | GEOS 128: use DrawSprite on sprite 0 |
| `SetNewMode` | `$89DD` | - | - | GEOS 128: use SetVideoMode |
| `NormalizeX` | `$89E0` | - | - | GEOS 128: not needed |
| `MoveBData` | `$89E3` | - | - | GEOS 128 banks: use BankCopy |
| `SwapBData` | `$89E6` | - | - | GEOS 128 banks: use BankCopy |
| `VerifyBData` | `$89E9` | - | - | GEOS 128 banks: use BankCopy |
| `DoBOp` | `$89EC` | - | - | GEOS 128 banks: use BankCopy |
| `AccessCache` | `$89EF` | - | - | GEOS 128: not needed |
| `SetColorMode` | `$89F5` | - | - | GEOS 128 VDC colour: use SetColors |
| `ColorCard` | `$89F8` | - | - | GEOS 128 VDC colour |
| `ColorRectangle` | `$89FB` | - | - | GEOS 128 VDC colour |

## System variables

| Name | Address | Size | |
|---|---|---|---|
| `r0` | `$0002` | 2 | pseudo register |
| `r1` | `$0004` | 2 | pseudo register |
| `r2` | `$0006` | 2 | pseudo register |
| `r3` | `$0008` | 2 | pseudo register |
| `r4` | `$000A` | 2 | pseudo register |
| `r5` | `$000C` | 2 | pseudo register |
| `r6` | `$000E` | 2 | pseudo register |
| `r7` | `$0010` | 2 | pseudo register |
| `r8` | `$0012` | 2 | pseudo register |
| `r9` | `$0014` | 2 | pseudo register |
| `r10` | `$0016` | 2 | pseudo register |
| `r11` | `$0018` | 2 | pseudo register |
| `r12` | `$001A` | 2 | pseudo register |
| `r13` | `$001C` | 2 | pseudo register |
| `r14` | `$001E` | 2 | pseudo register |
| `r15` | `$0020` | 2 | pseudo register |
| `a0` | `$0050` | 2 | application register |
| `a1` | `$0052` | 2 | application register |
| `a2` | `$0054` | 2 | application register |
| `a3` | `$0056` | 2 | application register |
| `a4` | `$0058` | 2 | application register |
| `a5` | `$005A` | 2 | application register |
| `a6` | `$005C` | 2 | application register |
| `a7` | `$005E` | 2 | application register |
| `a8` | `$0060` | 2 | application register |
| `a9` | `$0062` | 2 | application register |
| `curPattern` | `$0022` | 2 | pointer to the current fill pattern |
| `string` | `$0024` | 2 | pointer used by text routines |
| `baselineOffset` | `$0026` | 1 | current font: baseline |
| `curSetWidth` | `$0027` | 2 | current font: bytes per scanline of its bitmap |
| `curHeight` | `$0029` | 1 | current font: height |
| `curIndexTable` | `$002A` | 2 | current font: offset table |
| `cardDataPntr` | `$002C` | 2 | current font: bitmap |
| `currentMode` | `$002E` | 1 | text style bits |
| `dispBufferOn` | `$002F` | 1 | bit 7 draw to the foreground, bit 6 to the back screen |
| `mouseOn` | `$0030` | 1 | mouse and menu state bits |
| `msePicPtr` | `$0031` | 2 | pointer picture |
| `windowTop` | `$0033` | 1 | clip window top (classic byte view) |
| `windowBottom` | `$0034` | 1 | clip window bottom (classic byte view) |
| `leftMargin` | `$0035` | 2 | text: left margin |
| `rightMargin` | `$0037` | 2 | text: right margin |
| `pressFlag` | `$0039` | 1 | input event bits |
| `mouseXPos` | `$003A` | 2 | pointer x |
| `mouseYPos` | `$003C` | 1 | pointer y (classic byte view; mouseYPosW is the real one) |
| `returnAddress` | `$003D` | 2 | inline calls: return address |
| `fileHeader` | `$0400` | 256 | the info block of the last file opened (GEOS layout) |
| `dirEntryBuf` | `$0500` | 30 | the directory entry of the last file found (GEOS layout) |
| `curRecord` | `$051E` | 1 | record file: current record |
| `usedRecords` | `$051F` | 1 | record file: records in use |
| `fileWritten` | `$0520` | 1 | record file: changed since opened |
| `fileSize` | `$0521` | 2 | record file: size in blocks of 254 bytes |
| `appMain` | `$0523` | 2 | called every main loop pass |
| `intTopVector` | `$0525` | 2 | called at the start of the interrupt |
| `intBotVector` | `$0527` | 2 | called at the end of the interrupt |
| `mouseVector` | `$0529` | 2 | called on a click |
| `keyVector` | `$052B` | 2 | called on a key |
| `inputVector` | `$052D` | 2 | called on input device changes |
| `mouseFaultVec` | `$052F` | 2 | called when the pointer leaves its region |
| `otherPressVec` | `$0531` | 2 | called on a click not on a menu or icon |
| `StringFaultVec` | `$0533` | 2 | called when GetString's input is too long |
| `alarmTmtVector` | `$0535` | 2 | called when the alarm goes off |
| `BRKVector` | `$0537` | 2 | called on BRK |
| `RecoverVector` | `$0539` | 2 | recovers areas under menus and dialogs (r2L top, r2H bottom, r3 left, r4 right; r11, r12 wide); 0: Veranda chooses (the save-under stack if the application draws to the foreground only, else the back screen) |
| `selectionFlash` | `$053B` | 1 | icon and menu flash time |
| `alphaFlag` | `$053C` | 1 | text prompt state |
| `iconSelFlg` | `$053D` | 1 | icon selection behaviour |
| `faultData` | `$053E` | 1 | pointer fault bits |
| `menuNumber` | `$053F` | 1 | menu level |
| `mouseTop` | `$0540` | 1 | pointer region top (classic byte view) |
| `mouseBottom` | `$0541` | 1 | pointer region bottom (classic byte view) |
| `mouseLeft` | `$0542` | 2 | pointer region left |
| `mouseRight` | `$0544` | 2 | pointer region right |
| `stringX` | `$0546` | 2 | GetString: x |
| `stringY` | `$0548` | 1 | GetString: y (classic byte view) |
| `keyData` | `$0549` | 1 | the last key |
| `mouseData` | `$054A` | 1 | bit 7 = button up |
| `inputData` | `$054B` | 1 | input device data |
| `random` | `$054C` | 2 | changes every interrupt |
| `dblClickCount` | `$054E` | 1 | double click timer |
| `year` | `$054F` | 1 | clock |
| `month` | `$0550` | 1 | clock |
| `day` | `$0551` | 1 | clock |
| `hour` | `$0552` | 1 | clock |
| `minutes` | `$0553` | 1 | clock |
| `seconds` | `$0554` | 1 | clock |
| `alarmSetFlag` | `$0555` | 1 | alarm state |
| `sysDBData` | `$0556` | 1 | the dialog box result |
| `curDrive` | `$0557` | 1 | always 8: the SD card |
| `graphMode` | `$0558` | 1 | the video mode (SetVideoMode) |
| `pointerShape` | `$0559` | 1 | the pointer's shape as SetPointer set it (PTR_ARROW ...); 0 when an application starts (API 2) |
| `blankDelay` | `$055A` | 2 | seconds without input (a key, a pointer move, a button) before the screen blanks (VERA's display window closed: the whole screen the border, palette entry 0 black; DC_VIDEO and VRAM untouched); 600 at start-up, 0: never; the key or pointer move that wakes it is not passed on (API 2) |
| `uiFont` | `$055C` | 1 | the font native programs' menus and dialog boxes use: 0 the system font (as GEOS: classic tables keep it), else a font's handle (FONT_UI, or one from LoadFont); 0 when a program or accessory starts (API 3) |
| `uiLook` | `$055D` | 1 | the look of a native program's menus (DECISIONS V74): 0 GEOS 64's (classic tables keep it); LOOK_BAR the Veranda look: a horizontal main menu becomes the full-width menu bar (the Veranda mark, item 0 in bold: the program's name, its menus on 8-pixel cards, the sound and the date and time at the right, kept up to date), vertical menus open under their item with 16-line items and no separators; bits 0-3 (LOOK_HILITE) a palette entry: the bar's cards in entry 2 (the chrome) and an open menu or a chosen item in that colour (the colour map) instead of inverted; 0 when a program or accessory starts (API 4) |
| `longNames` | `$055E` | 1 | the GEOS file calls' names (DECISIONS V82): 0 GEOS's, at most 16 characters (as GEOS: classic programs keep it); LONG_NAMES: FindFile, GetFile (the program and its document, r6 and r3), OpenRecordFile, SaveFile, DeleteFile, LdFile and GetFHdrInfo after FindFile take FAT names of up to LONG_MAX characters (0-terminated; a GEOS file's name without its ".cvt"); 0 when a program or accessory starts (API 5) |
| `clipOn` | `$055F` | 1 | the clip rectangle (DECISIONS V81): 0 off (as GEOS: every call as before); not 0: the drawing (WRectangle, WInvertRectangle, WRecoverRectangle, WImprintRectangle, WFrameRectangle, the lines and points, the text, WBitmapUp and the rows) touches only the pixels in leftMargin .. rightMargin by windowTopW .. windowBottomW (a character partly in them drawn so; one wholly left or right of them skipped, without StringFaultVec), WVerticalLine (bank T) too; PutCards, CopyRect, ScrollRect and the colours are not clipped; 0 when a program or accessory starts (API 5) |
| `mouseYPosW` | `$0560` | 2 | pointer y |
| `windowTopW` | `$0562` | 2 | clip window top |
| `windowBottomW` | `$0564` | 2 | clip window bottom |
| `mouseTopW` | `$0566` | 2 | pointer region top |
| `mouseBottomW` | `$0568` | 2 | pointer region bottom |
| `stringYW` | `$056A` | 2 | GetString: y |
| `screenWidth` | `$056C` | 2 | pixels |
| `screenHeight` | `$056E` | 2 | lines |
| `mouseButtons` | `$0570` | 1 | bit 0 left, 1 right, 2 middle (1 = down) |
| `mouseWheel` | `$0571` | 1 | wheel movement since the last read (signed) |
| `keyMods` | `$0572` | 1 | modifier keys: bit 0 shift, 1 ctrl, 2 alt, 3 Commodore/GUI |
| `appBank` | `$0573` | 1 | the RAM bank mapped when Veranda calls the application (vectors, processes, Sleep) |
| `mouseSource` | `$0574` | 2 | 0: the X16 mouse; else a routine (in the interrupt): r0 = x, r1 = y, a = buttons; c clear: a device position (the pointer moves by its change), c set: the pointer's position (limited to the region) |
| `dosStatus` | `$0576` | 1 | the last CMDR-DOS status (two digits as a number: 0 ok, 62 not found, 63 exists ...) |
| `keyDataMods` | `$0577` | 1 | the modifier keys held when keyData (or GetNextChar's key) was typed, as keyMods; bit 4 (KEYM_ARROW): an arrow key (KEY_LEFT is BACKSPACE's code) (API 2) |
| `switchReq` | `$057A` | 1 | SWITCH_ASIDE (bit 7): at the main loop's next pass (at its top level: not inside a dialog box, not while a desk accessory runs) the running application is put aside whole into RAM banks and the desktop comes, with the application in its dock (DECISIONS V83); Alt+Tab and TaskCtl(TASK_ASIDE) set it, the kernel clears it; a program that cannot be put aside (its info block's flag APPF_STAY, streams or a listing open, not enough RAM banks) gets a box that asks whether it may quit; nothing for the desktop itself (API 6) |
| `intFirstVector` | `$0578` | 2 | called first in every interrupt, before Veranda saves anything (the interrupted code's banks mapped, a x y free, at most a few hundred cycles, or longer with its own source masked and interrupts on: PCM from AFLOW, V52); return c set when its device needs nothing more: if VERA has no enabled interrupt pending either, the interrupt ends there (a serial port's FIFO, VERA's line interrupt); 0: none; cleared when an application or accessory starts (API 2) |
| `asideVector` | `$057B` | 2 | called by the switcher (DECISIONS V91) just before it puts the running application aside or asks whether it may quit it (switchReq: Alt+Tab, TaskCtl(TASK_ASIDE)), from the main loop's top level (the application's bank mapped, interrupts on, r0-r15 free): a program whose device interrupts through intFirstVector turns the device's interrupt off there, since the kernel stops calling intFirstVector next (and turns VERA's line interrupt off); nothing is called when the program comes back, or goes on (the box's Cancel): it arms the device again from its main loop (appMain); 0: none; cleared when an application or accessory starts |
| `deskNote` | `$057D` | 1 | why the kernel opened the desk accessory that runs (DECISIONS V120): a click on the menu bar's clock opens Preferences with DN_CLOCK (its date and time), on its sound with DN_VOLUME (the volume pop-up under the pointer); 0 for an accessory a program opened (GetFile); the kernel sets it before its GetFile and clears it after |
| `dataFileName` | `$0580` | 17 | GetFile: a document's name; a name longer than 16 characters (dataLongName) in its short form (DECISIONS V82: the first 11 characters less the extension's, "~", the CRC-16 of the long name in 4 hexadecimal digits, the extension of up to 4 characters with its dot), which every GEOS file call and FOpen take for the long one |
| `curDirName` | `$05A0` | 64 | the current directory (path) |
| `dbFileNames` | `$0600` | 442 | a dialog box's file list (DBGETFILES): up to DB_MAX_FILES names of 17 bytes, in the order found |
| `dataLongName` | `$07C0` | 64 | GetFile: a document's whole name (up to LONG_MAX characters and a 0: a GEOS document's without ".cvt", a plain file's with its extension); dataFileName holds it, or its short form when it is longer than 16 (API 5) |

## Constants

| Name | Value | |
|---|---|---|
| `CLASSIC_BASE` | `$8800` | the classic jump table (GEOS 64 address - $3900) |
| `NEW_BASE` | `$8A00` | the table of wide and new calls |
| `API_LEVEL` | `$7` | GetVersion returns it; an application may ask for at most this |
| `DN_CLOCK` | `$1` | deskNote: the menu bar's clock was clicked (Preferences: the date and time) |
| `DN_VOLUME` | `$2` | deskNote: the menu bar's sound was clicked (Preferences: the volume pop-up) |
| `KEY_F1` | `$1` | key code |
| `KEY_F2` | `$2` | key code |
| `KEY_F3` | `$3` | key code |
| `KEY_F4` | `$4` | key code |
| `KEY_F5` | `$5` | key code |
| `KEY_F6` | `$6` | key code |
| `KEY_TAB` | `$9` | key code |
| `KEY_F7` | `$E` | key code |
| `KEY_F8` | `$F` | key code |
| `KEY_UP` | `$10` | key code |
| `KEY_DOWN` | `$11` | key code |
| `KEY_HOME` | `$12` | key code |
| `KEY_CLEAR` | `$13` | key code |
| `KEY_STOP` | `$16` | key code |
| `KEY_ESC` | `$1B` | key code |
| `KEY_INSERT` | `$1C` | key code |
| `KEY_DELETE` | `$1D` | key code |
| `KEY_RIGHT` | `$1E` | key code |
| `KEY_LEFT` | `$8` | key code (BACKSPACE) |
| `SHORTCUT` | `$80` | key code bit: Alt (Commodore) + a key |
| `KEY_PGUP` | `$81` | key code (API 2) |
| `KEYM_ARROW` | `$10` | keyDataMods bit: the key was an arrow key (API 2) |
| `KEY_PGDN` | `$82` | key code (API 2; without Ctrl: Ctrl+B is 2) |
| `KEY_END` | `$83` | key code (API 2; without Ctrl: Ctrl+D is 4) |
| `KEY_F9` | `$89` | key code (API 2) |
| `KEY_F10` | `$8A` | key code (API 2) |
| `KEY_F11` | `$8B` | key code (API 2) |
| `KEY_F12` | `$8C` | key code (API 2) |
| `CLICK_COUNT` | `$1E` | frames for a double click |
| `MOUSE_SPRNUM` | `$0` | the pointer's sprite |
| `ST_FLASH` | `$80` | iconSelFlg: flash a selected icon |
| `ST_INVERT` | `$40` | iconSelFlg: invert a selected icon |
| `ST_WR_FORE` | `$80` | dispBufferOn: draw to the foreground |
| `ST_WR_BACK` | `$40` | dispBufferOn: draw to the back screen |
| `ST_WRGS_FORE` | `$20` | dispBufferOn: GetString and GraphicsString to the foreground only (dialog boxes) |
| `MODE_640x480` | `$0` | video mode |
| `MODE_640x240` | `$1` | video mode |
| `MODE_320x240` | `$2` | video mode |
| `DRAW_ERASE` | `$0` | wide line and point mode: paper |
| `DRAW_INK` | `$1` | wide line and point mode: ink |
| `DRAW_RECOVER` | `$80` | wide line and point mode: from the back screen |
| `UNSUPPORTED` | `$FE` | x on return of a dropped GEOS call |
| `HORIZONTAL` | `$0` | menu |
| `VERTICAL` | `$80` | menu |
| `CONSTRAINED` | `$40` | menu |
| `UN_CONSTRAINED` | `$0` | menu |
| `MENU_ACTION` | `$0` | menu item |
| `SUB_MENU` | `$80` | menu item |
| `DYN_SUB_MENU` | `$40` | menu item |
| `WIDE_MENU` | `$20` | menu flags byte (offset 6): two more bytes follow it, the high bytes of top and bottom; items from offset 9 |
| `WIDE_ICONS` | `$80` | icon table count byte: the pointer y is a word (header 5 bytes) and each icon 10 bytes, the high bytes of y and height last |
| `WIDE_DB` | `$20` | dialog box's first byte: its own position has word Y fields (bits 0-4: shadow) |
| `DEF_DB_POS` | `$80` | dialog box at the default position |
| `SET_DB_POS` | `$0` | dialog box at its own position |
| `OK` | `$1` | dialog icon and result |
| `CANCEL` | `$2` | dialog icon and result |
| `YES` | `$3` | dialog icon and result |
| `NO` | `$4` | dialog icon and result |
| `OPEN` | `$5` | dialog icon and result |
| `DISK` | `$6` | dialog icon and result |
| `DBTXTSTR` | `$B` | dialog item: text |
| `DBVARSTR` | `$C` | dialog item: text through a register |
| `DBGETSTRING` | `$D` | dialog item: text input |
| `DBSYSOPV` | `$E` | dialog item: a click anywhere closes it |
| `DBGRPHSTR` | `$F` | dialog item: GraphicsString |
| `DBGETFILES` | `$10` | dialog item: file list (r7L type, r10 class or 0, r5 the name chosen); also the result when no file matches |
| `DB_MAX_FILES` | `$1A` | DBGETFILES: the most names listed (30 before API 5: dataLongName took the end of dbFileNames) |
| `LONG_NAMES` | `$1` | longNames: the file calls take long names (API 5) |
| `LONG_MAX` | `$3F` | the longest name the file calls take (longNames, dataLongName) |
| `DBOPVEC` | `$11` | dialog item: user vector on a click |
| `DBUSRICON` | `$12` | dialog item: user icon |
| `DB_USR_ROUT` | `$13` | dialog item: user routine |
| `EOF` | `$0` | string end |
| `BACKSPACE` | `$8` | string code |
| `FORWARDSPACE` | `$9` | string code |
| `TAB` | `$9` | string code |
| `LF` | `$A` | string code: next line |
| `HOME` | `$B` | string code: top left |
| `UPLINE` | `$C` | string code: line up |
| `PAGE_BREAK` | `$C` | string code (documents) |
| `CR` | `$D` | string code: next line, left margin |
| `ULINEON` | `$E` | string code: underline on |
| `ULINEOFF` | `$F` | string code: underline off |
| `ESC_GRAPHICS` | `$10` | string code: a GraphicsString follows |
| `ESC_RULER` | `$11` | string code (documents) |
| `REV_ON` | `$12` | string code: reverse on |
| `REV_OFF` | `$13` | string code: reverse off |
| `GOTOX` | `$14` | string code: .word x |
| `GOTOY` | `$15` | string code: .byte y |
| `GOTOXY` | `$16` | string code: .word x, .byte y |
| `NEWCARDSET` | `$17` | string code: .word font |
| `BOLDON` | `$18` | string code: bold on |
| `ITALICON` | `$19` | string code: italic on |
| `OUTLINEON` | `$1A` | string code: outline on |
| `PLAINTEXT` | `$1B` | string code: all styles off |
| `SET_UNDERLINE` | `$80` | currentMode bit |
| `SET_BOLD` | `$40` | currentMode bit |
| `SET_REVERSE` | `$20` | currentMode bit |
| `SET_ITALIC` | `$10` | currentMode bit |
| `SET_OUTLINE` | `$8` | currentMode bit |
| `SET_SUPERSCRIPT` | `$4` | currentMode bit |
| `SET_SUBSCRIPT` | `$2` | currentMode bit |
| `SET_PLAINTEXT` | `$0` | currentMode |
| `SET_LEFTJUST` | `$80` | PutDecimal format |
| `SET_RIGHTJUST` | `$0` | PutDecimal format |
| `SET_SURPRESS` | `$40` | PutDecimal format: no leading zeros |
| `SET_NOSURPRESS` | `$0` | PutDecimal format |
| `MOVEPENTO` | `$1` | GraphicsString: .word x, .byte y |
| `LINETO` | `$2` | GraphicsString: .word x, .byte y |
| `RECTANGLETO` | `$3` | GraphicsString: .word x, .byte y |
| `NEWPATTERN` | `$5` | GraphicsString: .byte pattern |
| `ESC_PUTSTRING` | `$6` | GraphicsString: .word x, .byte y, a string |
| `FRAME_RECTO` | `$7` | GraphicsString: .word x, .byte y |
| `PEN_X_DELTA` | `$8` | GraphicsString: .word dx |
| `PEN_Y_DELTA` | `$9` | GraphicsString: .word dy |
| `PEN_XY_DELTA` | `$A` | GraphicsString: .word dx, .word dy |
| `DBI_X_0` | `$1` | dialog icon column |
| `DBI_X_1` | `$9` | dialog icon column |
| `DBI_X_2` | `$11` | dialog icon column |
| `DBI_Y_0` | `$8` | dialog icon row |
| `DBI_Y_1` | `$28` | dialog icon row |
| `DBI_Y_2` | `$48` | dialog icon row |
| `DEF_DB_TOP` | `$20` | default dialog box (classic 320x200 coordinates) |
| `DEF_DB_BOT` | `$7F` | default dialog box |
| `DEF_DB_LEFT` | `$40` | default dialog box |
| `DEF_DB_RIGHT` | `$FF` | default dialog box |
| `TXT_LN_X` | `$10` | dialog text column |
| `TXT_LN_1_Y` | `$10` | dialog text line |
| `TXT_LN_2_Y` | `$20` | dialog text line |
| `TXT_LN_3_Y` | `$30` | dialog text line |
| `TXT_LN_4_Y` | `$40` | dialog text line |
| `TXT_LN_5_Y` | `$50` | dialog text line |
| `SET_RUNABLE` | `$80` | process flag |
| `SET_BLOCKED` | `$40` | process flag |
| `SET_FROZEN` | `$20` | process flag |
| `SET_NOTIMER` | `$10` | process flag |
| `SET_MSE_ON` | `$80` | mouseOn bit |
| `SET_MENUON` | `$40` | mouseOn bit |
| `SET_ICONSON` | `$20` | mouseOn bit |
| `SET_KEYPRESS` | `$80` | pressFlag bit |
| `SET_INPUTCHG` | `$40` | pressFlag bit |
| `SET_MOUSE` | `$20` | pressFlag bit |
| `SET_OFFTOP` | `$80` | faultData bit |
| `SET_OFFBOTTOM` | `$40` | faultData bit |
| `SET_OFFLEFT` | `$20` | faultData bit |
| `SET_OFFRIGHT` | `$10` | faultData bit |
| `SET_OFFMENU` | `$8` | faultData bit |
| `OFF_CFILE_TYPE` | `$0` | directory entry: CBM type |
| `OFF_DE_TR_SC` | `$1` | directory entry: first block (on Veranda: 0) |
| `OFF_FNAME` | `$3` | directory entry: name (16, $A0 padded) |
| `OFF_GHDR_PTR` | `$13` | directory entry: info block (on Veranda: 0) |
| `OFF_GSTRUC_TYPE` | `$15` | directory entry: 0 sequential, 1 record file |
| `OFF_GFILE_TYPE` | `$16` | directory entry: GEOS file type |
| `OFF_YEAR` | `$17` | directory entry: date and time (5) |
| `OFF_SIZE` | `$1C` | directory entry: size in blocks |
| `O_GHIC_WIDTH` | `$2` | info block: icon width (3) |
| `O_GHIC_HEIGHT` | `$3` | info block: icon height (21) |
| `O_GHIC_PIC` | `$4` | info block: icon picture |
| `O_GHCMDR_TYPE` | `$44` | info block: CBM type |
| `O_GHGEOS_TYPE` | `$45` | info block: GEOS type |
| `O_GHSTR_TYPE` | `$46` | info block: structure |
| `O_GHST_ADDR` | `$47` | info block: load address |
| `O_GHEND_ADDR` | `$49` | info block: end address |
| `O_GHST_VEC` | `$4B` | info block: start address |
| `O_GHFNAME` | `$4D` | info block: class (permanent name) |
| `O_128_FLAGS` | `$60` | info block: GEOS 128 flags (Veranda: the video mode, D) |
| `O_GH_AUTHOR` | `$61` | info block: author |
| `O_GHP_DISK` | `$61` | info block: a document's parent disk |
| `O_GHP_FNAME` | `$75` | info block: a document's parent application |
| `O_GHINFO_TXT` | `$A0` | info block: description |
| `NOT_GEOS` | `$0` | file type |
| `BASIC` | `$1` | file type |
| `ASSEMBLY` | `$2` | file type |
| `DATA` | `$3` | file type |
| `SYSTEM` | `$4` | file type |
| `DESK_ACC` | `$5` | file type |
| `APPLICATION` | `$6` | file type |
| `ST_DA_ROOM` | `$20` | GetFile option, a desk accessory (V168): DA_ROOM (2) banks left free for it after the application is put aside, else NO_BANKS (the shell then lends its desktop's banks and tries again) |
| `ST_LD_DATA` | `$80` | GetFile option: r3 names a document, kept in dataLongName and dataFileName (its short form if longer than 16; DECISIONS V82); the application starts with r0L = the options |
| `APPL_DATA` | `$7` | file type |
| `FONT` | `$8` | file type |
| `AUTO_EXEC` | `$E` | file type |
| `NO_BLOCKS` | `$1` | error |
| `INV_TRACK` | `$2` | error |
| `INSUFF_SPACE` | `$3` | error: the card is full |
| `FULL_DIRECTORY` | `$4` | error |
| `FILE_NOT_FOUND` | `$5` | error |
| `BAD_BAM` | `$6` | error |
| `UNOPENED_VLIR` | `$7` | error |
| `INV_RECORD` | `$8` | error |
| `OUT_OF_RECORDS` | `$9` | error |
| `STRUCT_MISMAT` | `$A` | error |
| `BFR_OVERFLOW` | `$B` | error |
| `CANCEL_ERR` | `$C` | error |
| `DEV_NOT_FOUND` | `$D` | error |
| `INCOMPATIBLE` | `$E` | error |
| `FILE_EXISTS` | `$F` | error (Veranda) |
| `TOO_MANY_FILES` | `$10` | error (Veranda): no free stream |
| `NOT_VERANDA` | `$11` | error (Veranda): not a Veranda application (no VRND in its info block) |
| `TOO_NEW` | `$12` | error (Veranda): the application needs a newer API level |
| `NO_BANKS` | `$13` | error (Veranda): not enough free RAM banks |
| `DOS_ERROR` | `$14` | error (Veranda): CMDR-DOS reported an error (the status in dosStatus) |
| `KEYPRESS_BIT` | `$7` | pressFlag |
| `INPUT_BIT` | `$6` | pressFlag |
| `MOUSE_BIT` | `$5` | pressFlag |
| `TOBASIC_KEEP` | `$4B56` | ToBASIC: r1 = this keeps Veranda in memory (V64) |
| `COLOR_BUF` | `$FE` | ColorRect: each card's colour from the buffer at r0 (V78) |
| `COLOR_TILES` | `$FD` | ColorRect: the colour map on as 4 bpp tiles at VRAM_TILES, cleared (the shell's desktop picture, V101; a program's through the SDK's vrpic.h, V105) |
| `COLOR_CANVAS` | `$FC` | ColorRect: the canvas (V166): in the 320 x 240 mode an 8 bpp picture on layer 0 at VR_CANVAS ($02800-$153FF) under the 1 bpp screen, x = 0 on (r0 the program's cover routine: a = 0 cover, 1 uncover, the cards at r1: x, width, y, height), x = 1 its VRAM and the save-under's free part zeroed (asideVector: packs small); the SDK's vrcanvas.h |
| `PRINT_LETTER` | `$1` | PrintOpen: US Letter (else A4) |
| `PRINT_300DPI` | `$2` | PrintOpen: 300 dpi (else 150) |
| `PRINT_BACK` | `$1` | PrintRect: the back screen |
| `PRINT_FIT` | `$2` | PrintRect: fit to the page |
| `PRINT_COLOR` | `$80` | PrintRect: the ink and paper colours |
| `PTR_ARROW` | `$0` | SetPointer: the arrow |
| `PTR_BUSY` | `$1` | SetPointer: busy (animated) |
| `PTR_IBEAM` | `$2` | SetPointer: the I-beam (text) |
| `PTR_CROSS` | `$3` | SetPointer: the crosshair (drawing) |
| `PTR_OWN` | `$80` | SetPointer: with PTR_ARROW, sprite 0's own picture (DrawSprite on sprite 0) |
| `PREFS_GET` | `$0` | SysPrefs: the settings to r0 |
| `PREFS_SET` | `$1` | SysPrefs: the settings from r0 |
| `ALARMS_GET` | `$2` | SysPrefs: the alarm table to r0 |
| `ALARMS_SET` | `$3` | SysPrefs: the alarm table from r0 |
| `DESK_GET` | `$4` | SysPrefs: the desktop's path to r0 (API 3) |
| `DESK_SET` | `$5` | SysPrefs: the desktop's path from r0 (API 3) |
| `DESK_SIZE` | `$40` | SysPrefs: the desktop's path's size (curDirName's) |
| `PREFS_SIZE` | `$10` | SysPrefs: the settings block's size |
| `PREFS_NOBEEP` | `$80` | the settings' flags (byte 6): Beep is silent (PREFS_NOSOUND's old name) |
| `PREFS_NOSOUND` | `$80` | the settings' flags (byte 6): the sounds off (PlaySound and Beep silent, but the alarm) (API 4) |
| `PREFS_MENUTICK` | `$40` | the settings' flags (byte 6): a soft tick when a menu opens or an item is chosen (API 4) |
| `PREFS_POLISH` | `$4` | the settings' flags (byte 6): the keyboard is Polish (programmers): right Alt + a c e l n o s x z (Shift: capitals) gives the ISO-8859-16 letters (DECISIONS V142; API 7) |
| `PREFS_SWITCH` | `$30` | the settings' flags (byte 6): how the switcher puts programs aside (DECISIONS V145): 0 by the machine (Roomy below 2 MB, Fast from 2 MB), PREFS_FAST or PREFS_ROOMY (API 7) |
| `PREFS_FAST` | `$10` | the settings' flags (byte 6), PREFS_SWITCH: Fast: programs aside stay in RAM banks, so the switcher keeps banks free (a program that holds too many is asked to quit instead) (API 7) |
| `PREFS_ROOMY` | `$20` | the settings' flags (byte 6), PREFS_SWITCH: Roomy: a program that does not fit in the free RAM banks is put aside onto the card (/VERANDA/.SYSTEM/TASKS), so programs may use all banks but two (API 7) |
| `PREFS_VOLUME` | `$F` | SysPrefs: the settings' byte of the sounds' volume, PREFS_VOLSET + 63 - the volume (0-63, in VERA's 0.5 dB steps); without PREFS_VOLSET (a file saved before DECISIONS V72) full volume (API 4) |
| `PREFS_VOLSET` | `$80` | the settings' byte PREFS_VOLUME: bit 7, the volume is stored (DECISIONS V72; without it full volume) (API 4) |
| `ALARM_SIZE` | `$20` | SysPrefs: an alarm entry's size |
| `ALARM_MAX` | `$8` | SysPrefs: the entries in the alarm table |
| `ALARM_ARMED` | `$1` | an alarm entry's state (byte 5): waiting |
| `ALARM_DONE` | `$2` | an alarm entry's state: shown |
| `FONT_UI` | `$1` | LoadFont, UseFont: the built-in Veranda UI font (12 points) |
| `FONT_NONE` | `$FF` | LoadFont: no font (x the error) |
| `LOOK_BAR` | `$80` | uiLook: the Veranda look of menus (DECISIONS V74) |
| `LOOK_HILITE` | `$F` | uiLook: the selection's palette entry (0: inverted, no colours) |
| `FONT_NAME_LEN` | `$20` | FontList, FontInfo: a name's bytes with its 0 |
| `SND_ERROR` | `$1` | PlaySound: an error (Beep) |
| `SND_WARNING` | `$2` | PlaySound: a warning or a question (a dialog box with YES and NO plays it) |
| `SND_ALARM` | `$3` | PlaySound: the alarm (plays with the sounds off; nothing cuts it) |
| `SND_STARTUP` | `$4` | PlaySound: the start-up chime (the first program after boot) |
| `SND_EXIT` | `$5` | PlaySound: leaving Veranda (ToBASIC plays it to its end) |
| `SND_APP` | `$6` | PlaySound: an application starts |
| `SND_OPEN` | `$7` | PlaySound: a desk accessory opens (or a window) |
| `SND_CLOSE` | `$8` | PlaySound: a desk accessory closes (or a window) |
| `SND_MENU` | `$9` | PlaySound: a menu tick (only with PREFS_MENUTICK) |
| `SND_TRASH` | `$A` | PlaySound: the trash emptied |
| `TASK_INFO` | `$0` | TaskCtl: a task's record, or (x = $FF) the summary |
| `TASK_RESUME` | `$1` | TaskCtl: bring task x back; the caller ends |
| `TASK_END` | `$2` | TaskCtl: drop task x (its banks freed) |
| `TASK_NOTE` | `$3` | TaskCtl: r0's note goes with the next application started |
| `TASK_ASIDE` | `$4` | TaskCtl: put the caller aside at the main loop's next pass (switchReq); TaskCtl(TASK_INFO): a task's state, put aside |
| `TASK_ROOM` | `$5` | TaskCtl: a = the RAM banks the caller may still take with BankAlloc and be put aside (Fast: the free banks less the desktop's reserve and a small program's packed data; Roomy: the free banks and those of the programs aside in RAM, less two) (API 7) |
| `TASK_MAX` | `$8` | TaskCtl: tasks that can be put aside at once |
| `TASK_NOTE_LEN` | `$60` | TaskCtl: a note's bytes with its 0 |
| `TASK_REC` | `$73` | TaskCtl(TASK_INFO): a task's record's bytes |
| `TR_STATE` | `$0` | TaskCtl's record: the state |
| `TR_BANKS` | `$1` | TaskCtl's record: the RAM banks it holds |
| `TR_NAME` | `$2` | TaskCtl's record: its GEOS name (17 bytes) |
| `TR_NOTE` | `$13` | TaskCtl's record: its note (TASK_NOTE_LEN bytes) |
| `TASK_SUM` | `$15` | TaskCtl(TASK_INFO, $FF): the summary's bytes |
| `TS_COUNT` | `$0` | TaskCtl's summary: tasks put aside |
| `TS_FREE` | `$1` | TaskCtl's summary: free RAM banks |
| `TS_BANKS` | `$2` | TaskCtl's summary: RAM banks for programs |
| `TS_ERR` | `$3` | TaskCtl's summary: the error of the last start that failed (0 none; cleared by the read) |
| `TS_NAME` | `$4` | TaskCtl's summary: that program's name (17 bytes) |
| `SWITCH_ASIDE` | `$80` | switchReq: put the application aside at the main loop's next pass |
| `APPF_STAY` | `$4` | an application's info block flags (byte 143) bit 2: it is never put aside; the switcher asks to quit it instead (API 6) |

## Folders

| Name | Path | |
|---|---|---|
| `VR_SYSDIR` | `/VERANDA` | the system folder: VERANDA.PRG, VERANDA.SYS, RBOOT, SHELL.cvt, DESKTOP.cvt |
| `VR_APPSDIR` | `/VERANDA/APPS` | the applications and desk accessories |
| `VR_DATADIR` | `/VERANDA/.SYSTEM` | the system's data (hidden): settings, alarms, the scraps, Note File, the albums, SHELL.DSK, the trash |
| `VR_FONTSDIR` | `/VERANDA/FONTS` | the fonts |
| `VR_DOCSDIR` | `/DOCUMENTS` | the user's documents: where programs save and open first, where the shell opens |
| `VR_TRASHDIR` | `/VERANDA/.SYSTEM/TRASH` | the trash |
| `VR_WALLDIR` | `/VERANDA/WALLPAPERS` | the desktop pictures (V78): Dusk.cvt, the default, and the user's (tools/mkwall.py) |
| `VR_HELPDIR` | `/VERANDA/HELP` | the help files (V93): VeraBASIC's KEYWORDS.HLP, TUTORIAL.HLP, ERRORS.HLP, EDITOR.HLP; other programs' help may go here too |
| `VR_SYSPATH` | `//VERANDA/:` | VR_SYSDIR in CMD's syntax, for FOpen by a path |
| `VR_DATAPATH` | `//VERANDA/.SYSTEM/:` | VR_DATADIR in CMD's syntax |
| `VR_FONTSPATH` | `//VERANDA/FONTS/:` | VR_FONTSDIR in CMD's syntax |
| `VR_HELPPATH` | `//VERANDA/HELP/:` | VR_HELPDIR in CMD's syntax |
| `VR_ROOTPATH` | `//:` | the root in CMD's syntax |
