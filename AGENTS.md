# AGENTS.md

An Omarchy shell plugin: a window and a bar widget for cliamp, the terminal
music player. Quickshell/QML on top of cliamp's v2 IPC — there is no player in
here. Read `README.md` for what it does; this file is about changing it.

## Orientation, in one pass

```
manifest.json        schemaVersion 1. kinds, entryPoints, bar-widget metadata.
src/Cliamp.qml       The client. One `call()` over `cliamp remote call`, the
                     spectrum feed, the volume read, and the daemon it starts
                     when nothing is listening on the socket. Everything that
                     talks to cliamp goes through here.
src/Model.js         Pure JS: rows, stars, cursor movement, hints. No Qt types,
                     so `node dev/test-model.js` runs it.
src/Ard.js           ARD Audiothek adapter: shows, episodes, topics, live.
src/RadioBrowser.js  Radio Browser adapter: live radio for any country.
src/Favorites.qml    The star store. JSON under ~/.local/state, atomic writes.
src/Library.qml      The library: state and view, with no window around it.
src/App.qml          The layer-shell window that hosts Library, the scrim, the
                     keyboard grab, and the IpcHandler a keybinding can call.
src/BarWidget.qml    The bar: title, spectrum, pause morph, click to open.
src/Service.qml      MPRIS service (cloned from omarchy.media), for the popup
src/MediaModel.js    and the other players in the bus.
dev/                 Offscreen harness and the tests. See below.
skills/              What an agent needs to drive cliamp on this machine.
```

## The two rules that matter

**One call path.** Every read and write to cliamp goes through
`Cliamp.call(operation, params, handler)`. It is the only place that knows the
response shape (sync answers carry `snapshot` at the top level, async ones
carry a `job` with `result` and `snapshot` inside it), the only place that
starts a daemon, and the only place that retries. A `Process` spawning `cliamp`
anywhere else is a bug.

**Background reads never start a player.** `call()` starts a daemon when the
socket is missing; `poll()` does not. The bar polls every three seconds from the
moment the shell starts, and a login that silently starts playing music is not
something anybody asked for. When you add a background read, use `poll()`.

## Shaping belongs in Model.js

If a decision can be made without a compositor — which rows an answer becomes,
what a star keys on, where the cursor lands, what the hint bar says — it goes in
`Model.js` and gets a test. `Library.qml` should read as bindings and calls.

Two decisions worth keeping: the cursor never lands on a section header
(`nextIndex` steps over them), and it stops at the ends rather than wrapping —
wrapping in a 300-station list loses the reader.

## Stars

`Favorites.qml` holds the plugin's own stars because cliamp has nowhere to put
most of them: its `provider.favorite` covers a radio station or a podcast show,
and nothing else. A starred stream keeps its playable track in the entry, so
Favorites can play an ARD programme without asking the Audiothek again.

`Model.favoriteKey` keys a playable row on its URL, so the same station starred
from Radio and from Broadcast is one star, not two. Rows with nothing to star —
a topic, a country — return `""`, and everything checks that before offering the
button.

## Adding a broadcaster

`RadioBrowser.js` covers every country; a broadcaster adapter adds its own
catalogue on top where one is published. ARD is the model: a file of pure
functions that fetch, shape, and map to a cliamp track, with no Qt types beyond
`XMLHttpRequest`, so `dev/test-adapters.js` can hand it a fake one.

To add another, write the adapter, give it the same three shapes
(`{kind: "show"}`, `{kind: "episode"}`, `{kind: "live"}` plus `toTrack`), and
fold it into `loadBroadcast()` behind a country check. Keep `publicCatalog` a
property, not an `if` scattered through the file.

## The harness

```sh
dev/test.sh          # every test
dev/run.sh           # the library, on fixtures, offscreen
dev/shot.sh out.png  # photograph it
dev/shot.sh out.png queue
```

The harness mounts `Library.qml` in an ordinary window — which is why the window
and the view are separate files. It never talks to cliamp: `dev/shell.qml` has a
stub with the same properties, answering from fixtures, so it is safe to run
while you are listening to something. The one live thing is the Broadcast
section, whose adapters really do call their APIs.

## Things that will bite

- **Bar widgets do not hot-reload.** Editing `Library.qml` reloads; editing
  `BarWidget.qml` needs `omarchy restart shell`.
- **A signal cannot share a property's name.** `signal snapshotChanged()` beside
  `property var snapshot` refuses to load the whole plugin.
- **`Process.command` is not a live binding to change under a running process.**
  Set it before `running = true`.
- **An animation owns the property it animates.** The scrolling title's
  `NumberAnimation on x` leaves `x` where it stopped, so the label is put back
  by hand when it stops — otherwise a paused title sits off-screen.
- **The harness caches compiled QML.** `dev/run.sh` sets
  `QML_DISABLE_DISK_CACHE=1`; without it an edit to a staged file appears to do
  nothing, because the stage's paths never change.
- **Offscreen Quickshell has no layer shell.** `PanelWindow` fails to load under
  `QT_QPA_PLATFORM=offscreen`; that is why the harness hosts `Library`.
- **`vis` and `theme` are TUI-only.** The daemon refuses them. The spectrum
  comes from `cliamp visstream`, which does work headless.

## Branches, while a marketplace review is open

`main` is what the marketplace validates, and a listing review binds to an exact
commit. Every push to `main` while a submission is open invalidates the snapshot
that was reviewed and restarts the round — a docs-only commit moves HEAD exactly
as far as a feature does. That has already cost two rounds on the Teams listing.

So while a submission is open: `main` is frozen at the submitted commit, and
everything lands on `dev`. When the listing is approved, merge `dev` into `main`
in one go, and only then open the update request — it binds a SHA the same way,
so the merge has to be in it. When no submission is open, `main` is fine to
commit to directly.

Editing the submission issue body is what re-runs validation and the security
baseline against current HEAD. The bot edits its two comments in place rather
than posting new ones, so watch `updated_at`, not `created_at`.

Getting a *published* listing onto a newer commit is a different route: the
**Plugin verification** form (`verify-plugin.yml`), **Verify and publish a newer
upstream commit**, with the plugin id, the repository root URL, and the full
40-character SHA.

## Before a commit

```sh
dev/test.sh
omarchy plugin validate .
omarchy restart shell   # then click the widget: the bar is not covered by tests
```
