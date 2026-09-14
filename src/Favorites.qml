import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Stars that belong to the plugin rather than to cliamp.
//
// cliamp's own favorites cover what its providers know about (radio stations,
// podcast shows). Anything the window discovers elsewhere — an ARD programme,
// a Radio Browser stream, a single episode — has nowhere to live there, so it
// lives here and survives restarts.
Item {
  id: root

  property var entries: []
  readonly property var index: Model.indexFavorites(root.entries)
  readonly property string directory: Quickshell.env("HOME") + "/.local/state/omarchy/cliamp-media"
  readonly property string path: root.directory + "/favorites.json"

  signal changed()

  function starred(row) {
    return Model.isStarred(root.index, Model.favoriteKey(row))
  }

  function canStar(row) {
    return Model.favoriteKey(row) !== ""
  }

  // Returns true when the row ended up starred.
  function toggle(row, track) {
    var result = Model.toggleFavorite(root.entries, row, track)
    if (!result.changed) return false
    root.entries = result.entries
    root.save()
    root.changed()
    return result.starred
  }

  function rows() {
    return Model.favoriteRows(root.entries)
  }

  function load(raw) {
    var parsed = null
    try {
      parsed = JSON.parse(raw || "{}")
    } catch (e) {
      parsed = null
    }
    root.entries = (parsed && parsed.entries) || []
  }

  function save() {
    file.setText(JSON.stringify({version: 1, entries: root.entries}, null, 2) + "\n")
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
