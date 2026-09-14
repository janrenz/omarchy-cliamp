# cliamp for Omarchy

A window for [cliamp](https://github.com/bjarneo/cliamp), the retro terminal
music player, and a bar widget that shows what it is playing — with cliamp's own
spectrum drawn in the bar.

The plugin does not play anything itself. cliamp is the engine; this is a second
face for it, over cliamp's v2 IPC. The terminal player and this window are two
views of one instance, so pausing here pauses there.

![the library window](preview.png)

## What it does

- **Bar widget** — the track title, scrolling, with cliamp's spectrum beside it.
  Paused morphs the spectrum into a pause glyph rather than swapping in a
  different icon. Click opens the library; middle-click skips; the wheel moves
  through the queue; right-click keeps the small MPRIS popup.
- **Library window** — radio, podcasts, live radio worldwide, your files, the
  queue, history, settings. Keyboard-first, mouse-complete.
- **Broadcast, wherever you are** — live stations for your country via the
  [Radio Browser](https://www.radio-browser.info/) directory, with the country
  detected from your timezone and switchable in the list. Where a public
  broadcaster publishes a catalogue of its own, an adapter adds it on top; the
  ARD Audiothek (Germany) is the first, with its live streams, its topics and
  its programmes.
- **Stars** — anything is starrable, including things cliamp has no favorite for
  (an ARD programme, a Radio Browser stream, a single episode). Stars live in
  `~/.local/state/omarchy/cliamp-media/favorites.json`. Starring something cliamp
  *does* know — a station, a podcast show — also toggles cliamp's own favorite,
  so the TUI agrees.
- **Works with no terminal open** — if cliamp is not running when you ask for
  something, the plugin starts it headless (`cliamp --daemon`) and says so once.

## Install

```sh
omarchy plugin add https://github.com/janrenz/omarchy-cliamp --enable
```

Needs `cliamp` on `PATH` (`omarchy pkg add cliamp`, or the AUR). Nothing else.

## Keys

| Key | Does |
| --- | --- |
| `↑` `↓` `PgUp` `PgDn` `Home` `End` | Move through the list, never onto a section header |
| `←` `→` | Leave the list for the sidebar, and come back |
| `⏎` | Play, or open a show |
| `⇧⏎`, right-click | Queue next instead |
| `f` | Star, or unstar |
| `Del` | Remove from the queue |
| `/` | Search this section |
| `Esc`, `Backspace` | Back one level, then close |
| `Tab`, `1`…`8` | Switch section |
| `Space` · `n` · `p` | Play/pause · next · previous |
| `+` `−` | Volume, by 1 dB |
| `Ctrl+←` `Ctrl+→` | Seek 10s, where the source can seek |
| `?` | Every key, in the window |

## One socket

Only one cliamp can hold its socket. If the plugin started a background player
and you then run `cliamp` in a terminal, that second instance runs blind beside
the first — same as any two cliamps. Settings → **Hand over to terminal** stops
the background player and opens the terminal one on the current track.

## Developing

```sh
dev/test.sh          # the tests
dev/run.sh           # the window, on fixtures, rendered offscreen
dev/shot.sh out.png  # photograph what the harness is drawing
```

See [AGENTS.md](AGENTS.md) for how it is put together.

## Licence

MIT — see [LICENSE](LICENSE).
