import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Development harness: the real window, on fixture data, rendered offscreen.
//
//   dev/run.sh                 # start it
//   dev/shot.sh out.png        # photograph what it is drawing
//   dev/shot.sh out.png queue  # after switching to that section
//
// This loads App.qml itself rather than a copy of its parts, so what is being
// looked at is the window the shell would host — the same layout, the same key
// handling. What differs is underneath it: `cliamp` here is a stub that answers
// every IPC call out of the fixtures below, so nothing starts a player, nothing
// touches your queue, and the harness is safe to run while you are listening to
// something.
//
// The one live thing is the Broadcast section: its adapters really do call
// api.ardaudiothek.de and the Radio Browser. Everything else is local.
ShellRoot {
  id: harness

  // Stands in for Cliamp.qml: the same properties the window binds to, and a
  // call() that answers from fixtures instead of from a socket.
  QtObject {
    id: stubCliamp

    property bool connected: true
    property bool live: false
    property bool watch: false
    property bool daemonOwned: false
    property bool wantVisualizer: false
    property var snapshot: ({})
    property var bands: [0.8, 0.62, 0.55, 0.4, 0.35, 0.3, 0.42, 0.28, 0.2, 0.1]
    property bool playing: true
    property string streamTitle: "Rosalia De Souza - Maria Moita"
    property string trackTitle: "SomaFM Bossa Beyond"
    property string trackArtist: "Rosalia De Souza"
    property string station: "SomaFM Bossa Beyond"
    property real position: 59
    property real duration: 0
    property bool seekable: false
    property bool shuffle: false
    property string repeat: "All"
    property bool mono: false
    property real speed: 1
    property string eqPreset: "Rock"
    property var eqBands: [5, 4, 2, -1, -2, 2, 4, 5, 5, 5]
    property real volumeDb: 0

    function call(operation, params, handler) {
      var result = harness.fixtureFor(operation, params)
      if (handler) Qt.callLater(function () { handler(result, {ok: true}) })
      return null
    }

    function refresh() {}
    function playPause() {}
    function next() {}
    function previous() {}
    function stop() {}
    function seekAbsolute(secs) {}
    function adjustVolume(delta) {}
    function setShuffle(on) { stubCliamp.shuffle = on }
    function setRepeat(mode) { stubCliamp.repeat = mode }
    function setEqPreset(name) { stubCliamp.eqPreset = name }
    function setSpeed(value) { stubCliamp.speed = value }
    function handOffToTerminal() {}
  }

  function fixtureFor(operation, params) {
    var provider = params && params.provider ? params.provider : ""
    if (operation === "provider.catalog" && provider === "radio") {
      return {ok: true, playlists: [
        {id: "loc:ask", name: "Use my location", provider: "radio"},
        {id: "l:1", name: "SomaFM Beat Blender", provider: "radio"},
        {id: "l:2", name: "SomaFM Bossa Beyond", provider: "radio"},
        {id: "l:3", name: "SomaFM Deep Space One", provider: "radio"}
      ]}
    }
    if (operation === "provider.catalog" && provider === "podcast") {
      return {ok: true, playlists: [
        {id: "c:https://example.org/feed.xml", name: "Apokalypse & Filterkaffee", section: "Top Shows (DE)", track_count: 1901, favoritable: true},
        {id: "c:https://example.org/other.xml", name: "Lanz + Precht", section: "Top Shows (DE)", track_count: 265, favoritable: true}
      ]}
    }
    if (operation === "provider.playlists") {
      return {ok: true, playlists: [{id: "Favorites", name: "Favorites", provider: "local", section: "Favorites"}]}
    }
    if (operation === "provider.tracks") {
      return {ok: true, tracks: [
        {title: "Maria Moita", artist: "Rosalia De Souza", path: "https://example.org/a.mp3", duration_secs: 245},
        {title: "Tema In Hi-Fi", artist: "Nicola Conte", path: "https://example.org/b.mp3", duration_secs: 312}
      ]}
    }
    if (operation === "queue.list") {
      return {ok: true, tracks: [
        {title: "SomaFM Bossa Beyond", path: "https://example.org/bossa", stream: true},
        {title: "NCS Trap", path: "https://example.org/ncs", stream: true}
      ]}
    }
    if (operation === "history") {
      return {ok: true, history: [
        {track: {title: "SomaFM Indie Pop Rocks!", path: "https://example.org/indie", stream: true}, played_at: "2026-09-14T15:00:49Z"}
      ]}
    }
    if (operation === "device") {
      return {ok: true, devices: [
        {name: "alsa_output.platform-sound.HiFi__Headphones__sink", description: "Headphones"},
        {name: "bluez_output.70_F9_4A_8A_3A_8B.1", description: "Bluetooth speaker", active: true}
      ]}
    }
    return {ok: true}
  }

  FloatingWindow {
    id: window
    implicitWidth: 1100
    implicitHeight: 760
    color: Color.menu.background

    Library {
      id: app
      anchors.fill: parent
      anchors.margins: 0
      cliamp: stubCliamp
      Component.onCompleted: app.open()
    }
  }

  IpcHandler {
    target: "dev"

    function show(): string {
      return app.opened ? app.section : "closed"
    }

    function section(name: string): void {
      app.selectSection(name)
    }

    function shot(path: string): void {
      // The window's content item is created by Quickshell rather than by the
      // QML engine, and grabToImage refuses it ("item has no QML engine"). Its
      // first child is an ordinary QML item that fills it, so that is what
      // gets photographed.
      var item = app
      if (!item) { console.log("shot", path, "no window yet"); return }
      var started = item.grabToImage(function (result) {
        console.log("shot", path, result ? result.saveToFile(path) : "no result")
      })
      if (!started) console.log("shot", path, "grab refused - is the window mapped?")
    }
  }
}
