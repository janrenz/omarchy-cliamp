import QtQuick
import Quickshell
import Quickshell.Io

// Client for cliamp's v2 IPC API (`cliamp remote`).
//
// Sync operations answer with a top-level `snapshot`; async ones answer with a
// `job` that carries both `result` and `snapshot`. Either way every response
// refreshes runtime state, so the UI stays current without a dedicated poll
// for anything but the play position.
Item {
  id: root

  property var snapshot: ({})
  property bool connected: false
  // `live` is the app being on screen (one second); `watch` is the bar widget
  // keeping the title and spectrum current at a slower beat.
  property bool live: false
  property bool watch: false
  // Spectrum from `cliamp visstream`, ten bands in 0..1. The bar widget wants
  // it whenever something plays; the window wants it at a higher frame rate.
  property var bands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  property bool wantVisualizer: false
  property real volumeDb: 0

  // cliamp need not be open: when the socket is missing, start a headless
  // daemon and replay the call that found it missing.
  property bool daemonStarting: false
  property bool daemonOwned: false
  property var retryQueue: []

  readonly property string playbackState: snapshot.state || "stopped"
  readonly property bool playing: playbackState === "playing"
  readonly property bool paused: playbackState === "paused"
  readonly property var track: snapshot.track || ({})
  readonly property var logicalTrack: snapshot.logical_track || ({})
  readonly property string streamTitle: track.stream_title || ""
  readonly property string trackTitle: track.title || ""
  readonly property string trackArtist: track.artist || ""
  readonly property string station: track.station || logicalTrack.title || ""
  readonly property string artUrl: track.album_art_url || ""
  readonly property real position: snapshot.position || 0
  readonly property real duration: snapshot.duration || track.duration_secs || 0
  readonly property bool seekable: snapshot.seekable === true
  readonly property bool shuffle: snapshot.shuffle === true
  readonly property string repeat: snapshot.repeat || "Off"
  readonly property bool mono: snapshot.mono === true
  readonly property real speed: snapshot.speed || 1
  readonly property string eqPreset: snapshot.eq_preset || ""
  readonly property var eqBands: snapshot.eq_bands || []
  readonly property string visualizer: snapshot.visualizer || ""
  readonly property int playlistRevision: snapshot.playlist_revision || 0
  readonly property int queueLength: snapshot.total || 0

  signal snapshotUpdated()
  signal callFailed(string operation, string message)

  function applyEnvelope(payload) {
    if (!payload) return
    var snap = payload.snapshot
    if (!snap && payload.job) snap = payload.job.snapshot
    if (snap) {
      root.snapshot = snap
      root.connected = true
      root.snapshotUpdated()
    }
  }

  // call("provider.search", {provider: "podcast", query: "ARD"}, function (result, payload) {...})
  // `result` is the operation's own result object, already unwrapped.
  function call(operation, params, handler) {
    return dispatch({operation: operation, params: params || {}, handler: handler || null, tries: 0, autostart: true})
  }

  // Background reads must never start a player nobody asked for.
  function poll(operation, params, handler) {
    return dispatch({operation: operation, params: params || {}, handler: handler || null, tries: 0, autostart: false})
  }

  function dispatch(request) {
    var proc = callComponent.createObject(root, {
      request: request,
      command: ["cliamp", "remote", "call", request.operation, "--params", JSON.stringify(request.params), "--wait"]
    })
    if (proc) proc.running = true
    return proc
  }

  // A call that never reached the socket: start the daemon and try again.
  function requeue(request) {
    root.connected = false
    if (!request.autostart) {
      if (request.handler) request.handler(null, null)
      return
    }
    if (request.tries >= 3) {
      if (request.handler) request.handler(null, null)
      root.callFailed(request.operation, "cliamp is not reachable")
      return
    }
    request.tries++
    root.startDaemon()
    root.retryQueue = root.retryQueue.concat([request])
    retryTimer.restart()
  }

  function refresh() { call("runtime.snapshot", {}, null) }

  function startDaemon() {
    if (root.daemonStarting) return
    root.daemonStarting = true
    root.daemonOwned = true
    daemonProc.running = true
    daemonCooldown.restart()
  }

  // Only one cliamp can hold the socket, so a TUI started by hand would run
  // blind next to our daemon. Hand the session over instead: stop the daemon,
  // then open the terminal player on what was playing.
  function handOffToTerminal() {
    var path = String((root.track && root.track.path) || "")
    var quoted = "'" + path.replace(/'/g, "'\\''") + "'"
    handOffProc.command = ["bash", "-lc",
      "pkill -TERM -f '^cliamp --daemon' >/dev/null 2>&1; sleep 1; "
      + (path ? "omarchy-launch-terminal cliamp " + quoted + " --auto-play" : "omarchy-launch-terminal cliamp")]
    handOffProc.running = true
    root.daemonOwned = false
  }

  function adjustVolume(delta) {
    call("volume.adjust", {value: delta}, function () { statusProc.running = true })
  }

  function playPause() { call("toggle", {}, null) }
  function next() { call("next", {}, null) }
  function previous() { call("prev", {}, null) }
  function stop() { call("stop", {}, null) }
  function seekAbsolute(secs) { call("seek.absolute", {value: secs}, null) }
  function setVolume(db) { call("volume", {value: db}, null) }
  function setShuffle(on) { call("shuffle", {name: on ? "on" : "off"}, null) }
  function setRepeat(mode) { call("repeat", {name: mode}, null) }
  function setEqPreset(name) { call("eq", {name: name}, null) }
  function setSpeed(value) { call("speed", {value: value}, null) }

  // Hand cliamp a track it never had in a provider list — how ARD Audiothek
  // episodes and any bare URL reach the player.
  function playTrack(track, handler) { call("track.play", {track: track}, handler) }
  function queueTrack(track, handler) { call("track.queue", {track: track}, handler) }

  Component {
    id: callComponent

    Process {
      id: proc
      property var request: null
      readonly property string operation: proc.request ? proc.request.operation : ""
      readonly property var handler: proc.request ? proc.request.handler : null

      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: {
          var payload = null
          try {
            payload = JSON.parse(text || "")
          } catch (e) {
            payload = null
          }

          // A cliamp that is not listening writes to stderr, exits 1, and
          // leaves stdout empty. Parsing `text || "{}"` turned that into a
          // perfectly valid empty object, which read as a successful call with
          // nothing in it - so the daemon was never started and the window sat
          // on "loading…". Require the envelope cliamp actually sends.
          if (!payload || payload.version !== 2) {
            root.requeue(proc.request)
            Qt.callLater(proc.destroy)
            return
          }

          root.applyEnvelope(payload)

          var job = payload.job
          var result = job ? job.result : payload.result
          var failed = payload.ok === false || (job && job.state === "failed")
          if (failed) {
            var message = (job && job.error) || payload.error || "failed"
            root.callFailed(proc.operation, String(message))
          }
          if (proc.handler) proc.handler(result || null, payload)
          Qt.callLater(proc.destroy)
        }
      }

      onExited: function(code, status) {
        if (code !== 0) root.connected = false
      }
    }
  }

  // Headless player: same socket, same IPC, no terminal needed.
  Process {
    id: daemonProc
    command: ["bash", "-lc", "setsid -f cliamp --daemon >/dev/null 2>&1"]
  }

  Process { id: handOffProc }

  // Say it once, so a daemon that appeared on its own is not a mystery.
  Process {
    id: daemonNotice
    command: ["notify-send", "-a", "cliamp", "cliamp started in the background",
              "Control it from the bar. To use the terminal player, hand the session over from the Sound tab."]
  }

  Timer {
    id: daemonCooldown
    interval: 4000
    onTriggered: {
      root.daemonStarting = false
      if (root.daemonOwned && !noticeShown) { noticeShown = true; daemonNotice.running = true }
    }

    property bool noticeShown: false
  }

  Timer {
    id: retryTimer
    interval: 1800
    onTriggered: {
      var queued = root.retryQueue
      root.retryQueue = []
      for (var i = 0; i < queued.length; i++) root.dispatch(queued[i])
    }
  }

  // Spectrum feed. cliamp serves it headless too, so the animation survives
  // the TUI being closed.
  Process {
    id: visProc
    running: root.wantVisualizer && root.playing
    command: ["cliamp", "visstream", "--fps", root.live ? "30" : "15"]
    stdout: SplitParser {
      onRead: function (line) {
        try {
          var frame = JSON.parse(line)
          if (frame && frame.bands) root.bands = frame.bands
        } catch (e) {
          // A frame that arrives half-written is simply skipped.
        }
      }
    }
  }

  onPlayingChanged: if (!root.playing) root.bands = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

  // `volume` is not part of the runtime snapshot; the status command has it.
  Process {
    id: statusProc
    command: ["cliamp", "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var match = /Volume:\s*(-?[0-9.]+)\s*dB/.exec(text || "")
        if (match) root.volumeDb = parseFloat(match[1])
      }
    }
  }

  onLiveChanged: if (root.live) statusProc.running = true

  // Position only moves on its own; everything else arrives with a response.
  Timer {
    running: root.live || root.watch
    interval: root.live ? 1000 : 3000
    repeat: true
    triggeredOnStart: true
    onTriggered: root.poll("runtime.status", {}, null)
  }
}
