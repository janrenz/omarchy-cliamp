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

  // Whether the bar widget spells out what is playing. Off leaves the
  // spectrum and nothing else — the same information, a tenth of the width.
  property bool showTitle: true

  // "auto" folgt der Systemsprache, "de" und "en" setzen sie fest. Die
  // aufgelöste Sprache steht in `sprache` — die Oberfläche fragt nur die, und
  // weil es eine Eigenschaft ist, zeichnet ein Wechsel alles neu.
  property string language: "auto"

  readonly property string sprache: root.language === "de" || root.language === "en"
      ? root.language
      : (Qt.locale().name.substring(0, 2) === "de" ? "de" : "en")

  readonly property string directory: Quickshell.env("HOME") + "/.local/state/omarchy/cliamp-media"
  readonly property string path: root.directory + "/settings.json"

  function setWindowMode(mode) {
    if (mode !== "overlay" && mode !== "window") return
    if (mode === root.windowMode) return
    root.windowMode = mode
    root.save()
  }

  function setShowTitle(on) {
    if (on === root.showTitle) return
    root.showTitle = on === true
    root.save()
  }

  function setLanguage(lang) {
    if (lang !== "auto" && lang !== "de" && lang !== "en") return
    if (lang === root.language) return
    root.language = lang
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
    root.showTitle = !parsed || parsed.showTitle !== false
    var lang = parsed && parsed.language
    root.language = (lang === "de" || lang === "en") ? lang : "auto"
  }

  function save() {
    file.setText(JSON.stringify({version: 1, windowMode: root.windowMode, showTitle: root.showTitle,
                                 language: root.language}, null, 2) + "\n")
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
