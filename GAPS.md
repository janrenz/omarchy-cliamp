# GAPS

What this does not do yet, and why — so nobody rediscovers it the hard way.

## cliamp's own limits

- **Radio drops are given up on after ~31s.** cliamp reconnects a dropped
  stream five times with 1/2/4/8/16s backoff and then stops. Any outage longer
  than half a minute — wifi roaming, suspend, a router reboot — outlives the
  budget and playback simply stops. The fix belongs upstream in
  `ui/model/update.go`; until it lands, the window shows the stall but cannot
  heal it.
- **One socket, two players.** Starting `cliamp` in a terminal beside a running
  background daemon gives you a second, blind instance. The hand-over in
  Settings is the workaround, not a fix; cliamp has no attach mode.
- **Hand-over loses the position.** It restarts the terminal player on the
  current track with `--auto-play`; for a podcast that means the start of the
  episode, because the CLI takes no seek offset.
- **`vis` and `theme` are refused headless.** The visualiser *mode* cannot be
  changed while cliamp runs as a daemon, so Settings offers the spectrum as
  on/off only. `visstream` itself works headless, which is what the animation
  uses.
- **Volume is not in the runtime snapshot.** It is read by parsing
  `cliamp status`, refreshed when the window opens and after each adjustment.

## This plugin

- **Podcast chart country is cliamp's, not ours.** `[podcast] country` in
  `~/.config/cliamp/config.toml` decides the Top Shows list; Settings shows the
  value and where it lives rather than writing that file.
- **EQ bands are a readout.** Presets are switchable; the ten bands are drawn
  but not draggable. `eq --band N` exists, so this is work, not a wall.
- **One broadcaster adapter.** ARD only. The shape is there for others (see
  AGENTS.md); nobody has written BBC, SRF, ORF or NPR.
- **Local files are playlists only.** cliamp's local provider has no catalogue
  paging, so Files lists saved playlists and searches the library; it does not
  browse directories.
- **No per-episode resume.** cliamp has no podcast progress store, so an episode
  restarts from the beginning.
- **Artwork is fetched per row.** Lists of 300 stations pull 300 favicons from
  the directory. It is asynchronous and cached by Qt, but it is not batched.
- **The queue is not drag-reorderable.** `queue.move` exists; the list does not
  offer it yet — `Del` removes, and that is all.

## Tests

- `dev/test-model.js` and `dev/test-adapters.js` cover shaping, stars,
  navigation and both adapters. Nothing covers the QML itself: the harness
  renders it, but no assertion reads the picture.
