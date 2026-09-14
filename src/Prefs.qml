import QtQuick
import Quickshell
import Quickshell.Io

// The handful of choices the window makes about itself, kept beside the stars
// rather than in shell.json: they are set from inside the window, and a plugin
// that rewrites the bar's own config file to remember a preference is a plugin
// that can corrupt the bar.
Item {
  id: root

  // "overlay" — a layer-shell surface centred over everything, dismissed by
  // clicking away from it. "window" — an ordinary window in the stack, which
  // Hyprland tiles, moves between workspaces, and keeps until it is closed.
  property string windowMode: "overlay"

  readonly property string directory: Quickshell.env("HOME") + "/.local/state/omarchy/cliamp-media"
  readonly property string path: root.directory + "/settings.json"

  function setWindowMode(mode) {
    if (mode !== "overlay" && mode !== "window") return
    if (mode === root.windowMode) return
    root.windowMode = mode
    root.save()
  }

  function load(raw) {
    var parsed = null
    try {
      parsed = JSON.parse(raw || "{}")
    } catch (e) {
      parsed = null
    }
    var mode = parsed && parsed.windowMode
    root.windowMode = (mode === "window" || mode === "overlay") ? mode : "overlay"
  }

  function save() {
    file.setText(JSON.stringify({version: 1, windowMode: root.windowMode}, null, 2) + "\n")
  }

  Component.onCompleted: mkdirProc.running = true

  Process {
    id: mkdirProc
    command: ["mkdir", "-p", root.directory]
  }

  FileView {
    id: file
    path: root.path
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.load(text())
    onLoadFailed: root.load("{}")
    onFileChanged: reload()
  }
}
