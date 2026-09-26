# cliamp on GNOME

Notes for building a GNOME version, written on the Omarchy machine so the work can start
on the GNOME one without starting from zero. **Nothing here is built yet.**

## Why it does not simply run there

GNOME is Wayland too, but that is not the question. Omarchy's bar is a
Quickshell `PanelWindow`, and a panel needs the **`wlr-layer-shell`** protocol:
the one that lets a client say "I am a bar, pin me to the top edge, reserve my
height, keep me above everything". Hyprland, Sway, KDE and COSMIC implement it.
**Mutter does not**, and has declined to for years
([mutter#973](https://gitlab.gnome.org/GNOME/mutter/-/issues/973),
[gnome-shell#1141](https://gitlab.gnome.org/GNOME/gnome-shell/-/issues/1141)).
On GNOME only the shell draws the top bar, and anything that wants a place in
it is a **GNOME Shell extension** — GJS and St, not QML.

A Quickshell `FloatingWindow`, on the other hand, is an ordinary xdg toplevel,
and runs on GNOME like any other window.

## What there is to port

- **cliamp itself** — Omarchy installs it; on GNOME install it yourself first.
  Everything else assumes it is on `PATH`.
- **The window** (`src/App.qml`, a `FloatingWindow`, with `Library.qml`,
  `Favorites.qml`, `Prefs.qml`) — runs under Quickshell on GNOME. The pure JS
  (`Model.js`, `MediaModel.js`, `RadioBrowser.js`, `Ard.js`, `Texte.js`) moves
  as it is.
- **The spectrum in the bar** (`src/BarWidget.qml`) — a bar widget, so on GNOME
  a Shell extension. This is the only rewrite.
- **Playback controls** — cliamp speaks MPRIS, so GNOME's own media controls in
  the quick settings / notification list already show and drive it. The
  extension does not need to repeat that; the spectrum and "open the window"
  are what it adds.

## What has to be replaced

| Omarchy / Hyprland | Where | GNOME |
|---|---|---|
| `qs.Commons`, `qs.Ui` | every QML file, `dev/link.sh` | A small `Commons` of our own with the tokens used (`Style.space/font/spacing/gaps/corner`, `Color.accent/menu/urgent`), fed from `org.gnome.desktop.interface` |
| `hyprctl dispatch … focus` | `src/App.qml` — raise the window if it is already open | Let the one window process raise itself over its own IPC; GNOME lets no client focus another's window |
| `omarchy-cliamp` entry points | launcher / menu | A `.desktop` entry and a GNOME custom keybinding |

## Check first, on the GNOME machine

- `gnome-shell --version` — the extension API moved to ES modules in 45 and
  keeps shifting; target the version that is there, and say so in `metadata.json`.
- Is Quickshell available? AUR on Arch; on Fedora/Ubuntu it has to be built.
- `python3` — the helpers need nothing beyond the standard library.

## Naming — an open question, deliberately not decided yet

Once this runs on GNOME too, "omarchy" in the name is no longer the whole
truth. Renaming is still left until a GNOME build actually exists, because the
name lives in more places than the repo, and not all of them are cheap:

- **The GitHub repo** — cheap. GitHub redirects the old URL, clones keep working.
- **The plugin id** (`manifest.json` `id`) — expensive. A marketplace listing
  and every user's entry in `~/.config/omarchy/shell.json` are keyed on it.
  Keep it; it only ever means something to Omarchy anyway.
- **State and cache paths** (`~/.local/state/omarchy/…`, `~/.cache/omarchy/…`)
  — a rename signs everybody out unless the old path is migrated.
- **Anything registered elsewhere** — redirect schemes, app registrations,
  `User-Agent` strings.

The likely answer: rename the repo (and the README's headline) when the GNOME
part lands, keep the plugin id, and give the GNOME extension its own uuid.
