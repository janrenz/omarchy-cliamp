import QtQuick
import Quickshell
import Quickshell.Io

import qs.Ui
import qs.Commons
import "Model.js" as Model
import "Texte.js" as Texte
import "Ard.js" as Ard
import "RadioBrowser.js" as RadioBrowser

// The library itself: browse radio, podcasts and public-broadcaster catalogues,
// drive the queue, and control playback. Everything reaches the player over
// cliamp's v2 IPC, so the TUI and this window are two views of one instance.
//
// This is the view and its state, with no window around it. App.qml wraps it in
// the layer-shell window the bar opens; dev/shell.qml mounts it in an ordinary
// window so the harness can render it offscreen. Neither knows what the other
// does, and both get the same library.
Item {
  id: root

  property QtObject bar: null
  property var cliamp: null
  property var prefs: null
  property bool opened: false

  // The window is App.qml's business: the library asks, rather than closing a
  // surface it does not own.
  signal closeRequested()
  signal windowModeRequested(string mode)
  signal barTitleRequested(bool show)
  signal languageRequested(string lang)

  // Browsing stack: each level is {title, rows}. The top level is whatever the
  // current section last loaded.
  property var stack: []
  property var rows: []
  property string section: "radio"
  property string heading: "Radio"
  property string filter: ""
  property string searchQuery: ""
  property int selected: 0
  property bool loading: false
  property string error: ""
  property bool helpOpen: false
  property bool navFocus: false
  property bool spectrumEnabled: true

  property string country: "US"
  property string countryName: ""
  readonly property bool publicCatalog: root.country === "DE"

  property var devices: []
  property string activeDevice: ""

  // Jeder sichtbare Text läuft hier durch. Die Funktion liest prefs.sprache,
  // und weil das eine Eigenschaft ist, zeichnen sich alle Bindungen neu, sobald
  // die Sprache umgestellt wird — ohne das Fenster neu zu bauen.
  function t(text) {
    return Texte.t(text, root.prefs ? root.prefs.sprache : "en")
  }

  readonly property var sections: [
    {key: "favorites", label: t("Favorites"), icon: "󰓒", hint: t("Everything you starred")},
    {key: "radio", label: t("Radio"), icon: "󰐹", hint: t("cliamp's own station list")},
    {key: "podcast", label: t("Podcasts"), icon: "󰦔", hint: t("Apple directory and RSS")},
    {key: "broadcast", label: t("Broadcast"), icon: "󰜟", hint: t("Live radio worldwide")},
    {key: "local", label: t("Files"), icon: "󰉋", hint: t("Saved and local playlists")},
    {key: "queue", label: t("Queue"), icon: "󰲹", hint: t("What plays next")},
    {key: "history", label: t("History"), icon: "󰄉", hint: t("Recently played")},
    {key: "settings", label: t("Settings"), icon: "󰒓", hint: t("Output, sound, session")}
  ]

  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color subdued: Qt.darker(Color.menu.text, 1.45)
  readonly property color faint: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.08)
  readonly property color selectedBackground: Color.menu.selectedBackground
  readonly property color selectedText: Color.menu.selectedText
  readonly property string fontFamily: Style.font.menuFamily

  readonly property bool listSection: root.section !== "settings"

  readonly property var visibleRows: Model.filterRows(root.rows, root.filter)

  readonly property var currentRow: root.visibleRows[root.selected] || null

  // Contextual key hints, in the order they are worth knowing.
  readonly property var hints: Model.hintsFor(root.section, root.stack.length > 0)

  function open() {
    root.opened = true
    if (root.cliamp) root.cliamp.live = true
    root.selectSection(root.section)
  }

  function close() {
    root.opened = false
    root.helpOpen = false
    if (root.cliamp) root.cliamp.live = false
    root.closeRequested()
  }

  function toggle() { root.opened ? root.close() : root.open() }

  function fail(message) {
    root.loading = false
    root.error = String(message || "")
  }

  function setRows(title, list) {
    root.loading = false
    root.error = ""
    root.heading = title
    root.rows = list || []
    root.selected = root.firstSelectable(root.rows)
    root.filter = ""
  }

  function firstSelectable(list) { return Model.firstSelectable(list) }

  function labelFor(key) {
    for (var i = 0; i < root.sections.length; i++) if (root.sections[i].key === key) return root.sections[i].label
    return key
  }

  function push(title, list) {
    root.stack = root.stack.concat([{title: root.heading, rows: root.rows}])
    root.setRows(title, list)
  }

  // Back to a named level: the breadcrumb's crumbs are clickable, and clicking
  // the first one from three levels deep should land there, not one step up.
  function backTo(level) {
    if (level < 0 || level >= root.stack.length) return
    var target = root.stack[level]
    root.stack = root.stack.slice(0, level)
    root.setRows(target.title, target.rows)
  }

  function back() {
    if (!root.stack.length) return false
    var level = root.stack[root.stack.length - 1]
    root.stack = root.stack.slice(0, root.stack.length - 1)
    root.setRows(level.title, level.rows)
    return true
  }

  function selectSection(key) {
    root.section = key
    root.navFocus = false
    root.stack = []
    root.filter = ""
    root.error = ""
    root.searchQuery = ""
    searchField.text = ""
    root.selected = 0
    root.loading = true
    // Name the section and drop the previous one's rows now: a list that is
    // still showing Radio under a "loading…" chip reads as a section that
    // arrived wrong rather than one that has not arrived.
    root.rows = []
    root.heading = root.labelFor(key)
    if (key === "favorites") loadFavorites()
    else if (key === "radio") loadRadio()
    else if (key === "podcast") loadPodcasts()
    else if (key === "broadcast") loadBroadcast()
    else if (key === "local") loadLocal()
    else if (key === "queue") loadQueue()
    else if (key === "history") loadHistory()
    else if (key === "settings") loadSettings()
  }

  // ---- row builders (shaping lives in Model.js, so dev/ can test it) -------

  function headerRow(title) { return Model.headerRow(title) }
  function playlistRows(result, provider) { return Model.playlistRows(result, provider) }
  function trackRows(result) { return Model.trackRows(result) }

  function loadFavorites() {
    root.setRows("Favorites", favorites.rows())
  }

  // ---- cliamp-backed sections ---------------------------------------------

  function loadRadio() {
    root.cliamp.call("provider.catalog", {provider: "radio", limit: 500}, function (result) {
      root.setRows("Radio", root.playlistRows(result, "radio"))
    })
  }

  function loadPodcasts() {
    root.cliamp.call("provider.catalog", {provider: "podcast", limit: 200}, function (result) {
      root.setRows("Podcasts", root.playlistRows(result, "podcast"))
    })
  }

  // The local provider has no catalogue pages, only saved playlists.
  function loadLocal() {
    root.cliamp.call("provider.playlists", {provider: "local", limit: 200}, function (result) {
      root.setRows("Files", root.playlistRows(result, "local"))
    })
  }

  function loadQueue() {
    root.cliamp.call("queue.list", {limit: 500}, function (result) {
      root.setRows("Queue", Model.queueRows(result))
    })
  }

  function loadHistory() {
    root.cliamp.call("history", {limit: 200}, function (result) {
      root.setRows("History", Model.historyRows(result))
    })
  }

  function loadSettings() {
    root.loading = false
    root.heading = "Settings"
    root.rows = []
    root.cliamp.call("device", {name: "list"}, function (result) {
      var list = (result && result.devices) || []
      root.devices = list
      for (var i = 0; i < list.length; i++) if (list[i].active || list[i].current) root.activeDevice = list[i].name
    })
  }

  // ---- broadcast: live radio and public-service catalogues -----------------
  //
  // Radio Browser covers every country; where a public broadcaster publishes
  // its own catalogue, an adapter adds its shows on top. ARD is the first one.

  function loadBroadcast() {
    root.loading = true
    RadioBrowser.topStations(root.country, 60, function (stations) {
      var rows = [{
        kind: "country-picker",
        title: t("Country · ") + (root.countryName || root.country),
        subtitle: "Pick where the dial starts",
        art: ""
      }, root.headerRow(t("Top stations · ") + root.country)].concat(stations)

      if (!root.publicCatalog) {
        root.setRows("Broadcast", rows)
        return
      }
      // Germany: fold the ARD Audiothek in — live streams plus its own topics.
      Ard.liveStations(function (ardStations) {
        Ard.categories(function (categories) {
          var extra = [root.headerRow("ARD live")].concat(ardStations)
            .concat([root.headerRow("ARD Audiothek · Rubriken")]).concat(categories)
          root.setRows("Broadcast", rows.concat(extra))
        }, root.fail)
      }, root.fail)
    }, root.fail)
  }

  function openCountryPicker() {
    root.loading = true
    RadioBrowser.countries(function (countries) {
      root.push("Country", countries)
    }, root.fail)
  }

  function setCountry(row) {
    root.country = row.id
    root.countryName = row.title
    root.stack = []
    root.selectSection("broadcast")
  }

  function openArdCategory(row) {
    root.loading = true
    Ard.categoryShows(row.id, function (shows) { root.push(row.title, shows) }, root.fail)
  }

  function openArdShow(row) {
    root.loading = true
    Ard.episodes(row.id, row.title, 60, function (episodes) { root.push(row.title, episodes) }, root.fail)
  }

  // ---- activation ---------------------------------------------------------

  function activate(row, queueNext) {
    if (!row || row.header) return

    if (row.kind === "playlist") {
      root.loading = true
      root.cliamp.call("provider.tracks", {provider: row.provider, playlist: row.id, limit: 300}, function (result) {
        var rows = root.trackRows(result)
        // A radio station resolves to its single stream: play it outright
        // instead of making the user drill into a list of one.
        if (row.provider === "radio" && rows.length === 1) {
          root.playRow(rows[0], queueNext)
          root.loading = false
          return
        }
        root.push(row.title, rows)
      })
      return
    }

    if (row.kind === "feed") {
      root.loading = true
      root.cliamp.call("provider.tracks", {provider: "podcast", playlist: row.feedPath, limit: 300}, function (result) {
        root.push(row.title, root.trackRows(result))
      })
      return
    }

    if (row.kind === "country-picker") { root.openCountryPicker(); return }
    if (row.kind === "country") { root.setCountry(row); return }
    if (row.kind === "category") { root.openArdCategory(row); return }
    if (row.kind === "show") { root.openArdShow(row); return }
    if (row.kind === "episode" || row.kind === "live") {
      root.playTrackObject(root.trackFor(row), queueNext)
      return
    }
    if (row.kind === "queued") {
      if (queueNext) root.cliamp.call("queue.enqueue", {index: row.index}, null)
      else root.cliamp.call("queue.play", {index: row.index}, null)
      return
    }
    root.playRow(row, queueNext)
  }

  function playRow(row, queueNext) {
    if (!row || !row.track) return
    root.playTrackObject(row.track, queueNext)
  }

  function playTrackObject(track, queueNext) {
    root.cliamp.call(queueNext ? "track.queue" : "track.play", {track: track}, function () {
      if (!queueNext) root.cliamp.refresh()
    })
  }

  // A star is the plugin's own; where cliamp keeps a favorite or subscription
  // of its own for the same thing, toggle that too so the TUI agrees.
  function toggleFavorite(row) {
    var target = row || root.currentRow
    if (!target || !favorites.canStar(target)) return
    favorites.toggle(target, root.trackFor(target))
    if (target.kind === "playlist" && target.favoritable) {
      root.cliamp.call("provider.favorite", {provider: target.provider, playlist: target.id}, null)
    } else if (target.kind === "feed") {
      root.cliamp.call("provider.favorite", {provider: "podcast", playlist: target.feedPath}, null)
    }
    if (root.section === "favorites") root.loadFavorites()
  }

  // The playable track behind a row, for stars and for playback alike.
  function trackFor(row) {
    if (!row) return null
    if (row.track) return row.track
    if (row.kind === "episode") return Ard.toTrack(row)
    if (row.kind === "live") return row.votes === undefined ? Ard.toTrack(row) : RadioBrowser.toTrack(row)
    return null
  }

  function removeSelected() {
    var row = root.currentRow
    if (!row || row.kind !== "queued") return
    root.cliamp.call("queue.remove", {index: row.index}, function () { root.loadQueue() })
  }

  function runSearch() {
    var query = root.searchQuery
    if (!query) return
    root.loading = true
    if (root.section === "broadcast") {
      RadioBrowser.search(query, root.country, 40, function (stations) {
        if (!root.publicCatalog) {
          root.push(t("Broadcast · ") + query, stations)
          return
        }
        Ard.search(query, 25, function (shows) {
          var rows = [root.headerRow("Stations")].concat(stations)
            .concat([root.headerRow("ARD Audiothek")]).concat(shows)
          root.push("Broadcast · " + query, rows)
        }, function () { root.push(t("Broadcast · ") + query, stations) })
      }, root.fail)
      return
    }
    var provider = root.section === "podcast" ? "podcast" : root.section === "local" ? "local" : "radio"
    root.cliamp.call("provider.search", {provider: provider, query: query, limit: 60}, function (result) {
      root.push(root.heading + " · " + query, root.trackRows(result))
    })
  }

  function move(delta) {
    if (!root.visibleRows.length) return
    root.selected = Model.nextIndex(root.visibleRows, root.selected, delta)
    listView.positionViewAtIndex(root.selected, ListView.Contain)
  }

  function formatDuration(secs) { return Model.formatDuration(secs) }

  // Walk the sidebar; the content follows immediately so the nav is never a
  // dead end you have to confirm.
  function stepSection(delta) {
    var index = 0
    for (var i = 0; i < root.sections.length; i++) if (root.sections[i].key === root.section) index = i
    var next = Math.max(0, Math.min(root.sections.length - 1, index + delta))
    if (next === index) return
    var keepFocus = root.navFocus
    root.selectSection(root.sections[next].key)
    root.navFocus = keepFocus
  }

  function jumpToSection(number) {
    if (number < 1 || number > root.sections.length) return
    root.selectSection(root.sections[number - 1].key)
  }

  Component.onCompleted: if (root.opened) root.open()

  Favorites {
    id: favorites
    onChanged: if (root.section === "favorites") root.loadFavorites()
  }

  Process {
    id: countryProc
    running: true
    command: ["bash", "-lc", "zone=$(timedatectl show -p Timezone --value 2>/dev/null); awk -v z=$zone '$0 !~ /^#/ && $3 == z { split($1, c, \",\"); print c[1]; exit }' /usr/share/zoneinfo/zone1970.tab"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var code = String(text || "").trim()
        if (code.length === 2) root.country = code
      }
    }
  }

BorderSurface {
  id: card
  anchors.fill: parent
  radius: Style.cornerRadius
    color: root.background
    borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
    padding: Style.spacing.panelPadding

    MouseArea { anchors.fill: parent; onClicked: {} }

    Item {
      id: keyCatcher
      anchors.fill: parent
      anchors.topMargin: card.contentTopInset
      anchors.rightMargin: card.contentRightInset
      anchors.bottomMargin: card.contentBottomInset
      anchors.leftMargin: card.contentLeftInset
      focus: true

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function (event) {
        var typing = searchField.activeFocus

        if (root.helpOpen) {
          root.helpOpen = false
          event.accepted = true
          return
        }
        if (event.key === Qt.Key_Escape) {
          if (typing) { searchField.focus = false; keyCatcher.forceActiveFocus() }
          else if (root.navFocus) root.navFocus = false
          else if (root.filter) { root.filter = ""; searchField.text = "" }
          else if (!root.back()) root.close()
          event.accepted = true
        } else if (event.key === Qt.Key_Question || (event.key === Qt.Key_Slash && (event.modifiers & Qt.ShiftModifier))) {
          root.helpOpen = true
          event.accepted = true
        } else if (event.key === Qt.Key_Slash && !typing) {
          searchField.forceActiveFocus()
          event.accepted = true
        } else if (event.key === Qt.Key_Down) {
          if (root.navFocus) root.stepSection(1)
          else root.move(1)
          event.accepted = true
        } else if (event.key === Qt.Key_Up) {
          if (root.navFocus) root.stepSection(-1)
          else root.move(-1)
          event.accepted = true
        } else if (event.key === Qt.Key_PageDown) {
          root.move(8); event.accepted = true
        } else if (event.key === Qt.Key_PageUp) {
          root.move(-8); event.accepted = true
        } else if (event.key === Qt.Key_Home && !typing) {
          root.selected = root.firstSelectable(root.visibleRows); listView.positionViewAtBeginning(); event.accepted = true
        } else if (event.key === Qt.Key_End && !typing) {
          root.selected = Model.lastSelectable(root.visibleRows); listView.positionViewAtEnd(); event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          if (root.navFocus) root.navFocus = false
          else root.activate(root.currentRow, (event.modifiers & Qt.ShiftModifier) !== 0)
          event.accepted = true
        } else if (event.key === Qt.Key_Backspace && !typing) {
          root.back(); event.accepted = true
        } else if (event.key === Qt.Key_Delete) {
          root.removeSelected(); event.accepted = true
        } else if (event.key === Qt.Key_F && !typing) {
          root.toggleFavorite(null); event.accepted = true
        } else if (event.key === Qt.Key_Space && !typing) {
          root.cliamp.playPause(); event.accepted = true
        } else if (event.key === Qt.Key_N && !typing) {
          root.cliamp.next(); event.accepted = true
        } else if (event.key === Qt.Key_P && !typing) {
          root.cliamp.previous(); event.accepted = true
        } else if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) {
          root.cliamp.adjustVolume(1); event.accepted = true
        } else if (event.key === Qt.Key_Minus && !typing) {
          root.cliamp.adjustVolume(-1); event.accepted = true
        } else if (event.key === Qt.Key_Left && !typing) {
          if (event.modifiers & Qt.ControlModifier) {
            if (root.cliamp.seekable) root.cliamp.call("seek", {value: -10}, null)
          } else if (!root.navFocus) {
            root.navFocus = true
          }
          event.accepted = true
        } else if (event.key === Qt.Key_Right && !typing) {
          if (event.modifiers & Qt.ControlModifier) {
            if (root.cliamp.seekable) root.cliamp.call("seek", {value: 10}, null)
          } else if (root.navFocus) {
            root.navFocus = false
          }
          event.accepted = true
        } else if (event.key === Qt.Key_Tab) {
          var index = 0
          for (var i = 0; i < root.sections.length; i++) if (root.sections[i].key === root.section) index = i
          root.selectSection(root.sections[(index + 1) % root.sections.length].key)
          event.accepted = true
        } else if (!typing && event.key >= Qt.Key_1 && event.key <= Qt.Key_8) {
          root.jumpToSection(event.key - Qt.Key_0)
          event.accepted = true
        }
      }

      // ---- header ---------------------------------------------------------
      Item {
        id: headerItem
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Style.space(38)

        Row {
          anchors.left: parent.left
          anchors.right: searchField.left
          anchors.rightMargin: Style.space(16)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(8)

          // Where this list came from. A drilled-in list that only says
          // "Apokalypse & Filterkaffee" leaves the way back to a keystroke
          // nobody has been told about.
          Repeater {
            model: root.stack

            Row {
              spacing: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.title
                color: root.subdued
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
                textFormat: Text.PlainText

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.backTo(index)
                }
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "›"
                color: Qt.rgba(root.subdued.r, root.subdued.g, root.subdued.b, 0.6)
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
                textFormat: Text.PlainText
              }
            }
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.heading
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
            textFormat: Text.PlainText
          }

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: statusText.implicitWidth + Style.space(16)
            height: Style.space(22)
            radius: height / 2
            color: root.error ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.14) : root.faint
            visible: statusText.text !== ""

            Text {
              id: statusText
              anchors.centerIn: parent
              text: root.loading ? t("loading…")
                  : root.error ? root.error
                  : root.listSection ? root.visibleRows.length + (root.visibleRows.length === 1 ? t(" item") : t(" items")) : ""
              color: root.error ? Color.urgent : root.subdued
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              textFormat: Text.PlainText
            }
          }
        }

        TextField {
          id: searchField
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(320)
          foreground: root.foreground
          placeholderText: root.section === "broadcast" ? t("Search stations and shows…")
                         : root.section === "podcast" ? t("Search podcasts…")
                         : root.section === "radio" ? t("Search stations…")
                         : root.section === "local" ? t("Search your library…")
                         : t("Filter…")
          visible: root.listSection
          onTextChanged: {
            if (root.section === "queue" || root.section === "history") root.filter = text
            else root.searchQuery = text
          }
          onAccepted: root.runSearch()
        }
      }

      // ---- body -----------------------------------------------------------
      Item {
        id: bodyArea
        anchors.top: headerItem.bottom
        anchors.topMargin: Style.space(14)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: hintBar.top
        anchors.bottomMargin: Style.space(10)

        Column {
          id: sidebar
          width: Style.space(182)
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          spacing: Style.space(3)

          Repeater {
            model: root.sections

            Rectangle {
              id: sectionRow
              width: sidebar.width
              height: Style.space(38)
              radius: Style.spacing.labelGap
              readonly property bool active: modelData.key === root.section
              color: active ? root.selectedBackground : (sectionMouse.containsMouse ? root.faint : "transparent")
              border.width: active && root.navFocus ? 1 : 0
              border.color: Color.accent

              Row {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(12)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(10)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.icon
                  color: sectionRow.active ? root.selectedText : root.subdued
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  textFormat: Text.PlainText
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.label
                  color: sectionRow.active ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  textFormat: Text.PlainText
                }
              }

              Text {
                anchors.right: parent.right
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                text: String(index + 1)
                color: root.subdued
                opacity: sectionMouse.containsMouse ? 0.8 : 0.35
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                textFormat: Text.PlainText
              }

              MouseArea {
                id: sectionMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.selectSection(modelData.key)
              }
            }
          }

          Item { width: 1; height: Style.space(10) }

          // Session state, so a daemon that started itself is visible.
          Text {
            width: sidebar.width
            text: root.cliamp && root.cliamp.connected
                ? (root.cliamp.daemonOwned ? t("󰄬  cliamp · background") : t("󰄬  cliamp · connected"))
                : t("󰅖  cliamp · offline")
            color: root.subdued
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            textFormat: Text.PlainText
          }
        }

        // ---- list ----------------------------------------------------------
        Item {
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.left: sidebar.right
          anchors.leftMargin: Style.space(16)
          anchors.right: parent.right
          visible: root.listSection

          ListView {
            id: listView
            anchors.fill: parent
            opacity: root.navFocus ? 0.55 : 1.0

            Behavior on opacity {
              NumberAnimation { duration: 120 }
            }
            anchors.rightMargin: Style.space(8)
            clip: true
            model: root.visibleRows
            currentIndex: root.selected
            spacing: Style.space(2)
            boundsBehavior: Flickable.StopAtBounds

            delegate: Item {
              width: listView.width
              height: modelData.header ? Style.space(32) : Style.space(56)

              // section header
              Item {
                anchors.fill: parent
                visible: modelData.header === true

                Text {
                  id: headerLabel
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(4)
                  anchors.bottom: parent.bottom
                  anchors.bottomMargin: Style.space(7)
                  text: (modelData.title || "").toUpperCase()
                  color: root.subdued
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 1.4
                  textFormat: Text.PlainText
                }

                Rectangle {
                  anchors.left: headerLabel.right
                  anchors.leftMargin: Style.space(10)
                  anchors.right: parent.right
                  anchors.verticalCenter: headerLabel.verticalCenter
                  height: 1
                  color: root.faint
                }
              }

              // row
              Rectangle {
                id: rowSurface
                anchors.fill: parent
                visible: !modelData.header
                radius: Style.space(7)
                readonly property bool current: index === root.selected
                readonly property bool control: modelData.kind === "country-picker"
                color: current ? root.selectedBackground : (rowMouse.containsMouse ? root.faint : "transparent")
                border.width: control ? 1 : 0
                border.color: control ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.45) : "transparent"

                Behavior on color {
                  ColorAnimation { duration: 90 }
                }

                // The cursor as a rail rather than a filled row: it marks the
                // line without washing the artwork beside it out.
                Rectangle {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(2)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(3)
                  height: rowSurface.current ? parent.height - Style.space(18) : 0
                  radius: width / 2
                  color: Color.accent
                  visible: !rowSurface.control

                  Behavior on height {
                    NumberAnimation { duration: 120; easing.type: Easing.OutQuad }
                  }
                }

                Rectangle {
                  id: artwork
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(40)
                  height: Style.space(40)
                  radius: Style.space(6)
                  color: root.faint
                  clip: true

                  Image {
                    anchors.fill: parent
                    source: modelData.art || ""
                    visible: source !== "" && status === Image.Ready
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 128
                    sourceSize.height: 128
                    opacity: rowMouse.containsMouse || rowSurface.current ? 1.0 : 0.9

                    Behavior on opacity {
                      NumberAnimation { duration: 120 }
                    }
                  }

                  Text {
                    anchors.centerIn: parent
                    visible: !modelData.art
                    text: modelData.kind === "country-picker" || modelData.kind === "country" ? "󰇧"
                        : modelData.kind === "live" ? "󰐹"
                        : modelData.kind === "feed" || modelData.kind === "show" ? "󰦔"
                        : modelData.kind === "category" ? "󰉹"
                        : modelData.kind === "playlist" ? "󰲹" : "󰝚"
                    color: rowSurface.current ? root.selectedText : root.subdued
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.subtitle
                    textFormat: Text.PlainText
                  }

                  // A hairline, so pale artwork still has an edge.
                  Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.07)
                  }
                }

                Column {
                  anchors.left: artwork.right
                  anchors.leftMargin: Style.space(12)
                  anchors.right: rowActions.left
                  anchors.rightMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(3)

                  Text {
                    width: parent.width
                    text: modelData.title
                    color: rowSurface.current ? root.selectedText : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                  }

                  Text {
                    width: parent.width
                    text: modelData.subtitle || ""
                    color: root.subdued
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    visible: text !== ""
                    textFormat: Text.PlainText
                  }
                }

                Row {
                  id: rowActions
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)

                  // Fixed width, so durations line up down the list instead of
                  // drifting with whatever buttons sit beside them.
                  Item {
                    width: Style.space(52)
                    height: Style.space(20)
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                      anchors.right: parent.right
                      anchors.rightMargin: Style.space(8)
                      anchors.verticalCenter: parent.verticalCenter
                      text: root.formatDuration(modelData.duration)
                      color: root.subdued
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      textFormat: Text.PlainText
                    }
                  }

                  Button {
                    iconText: "󰐊"
                    foreground: root.foreground
                    opacity: rowMouse.containsMouse || rowSurface.current ? 1.0 : 0.0
                    visible: opacity > 0
                    tooltipText: t("Play  ·  ⏎")
                    onClicked: root.activate(modelData, false)

                    Behavior on opacity {
                      NumberAnimation { duration: 110 }
                    }
                  }

                  Button {
                    iconText: "󰲹"
                    foreground: root.foreground
                    opacity: (rowMouse.containsMouse || rowSurface.current)
                             && ["track", "episode", "live", "queued"].indexOf(modelData.kind) >= 0 ? 1.0 : 0.0
                    visible: opacity > 0
                    tooltipText: t("Play next  ·  ⇧⏎")
                    onClicked: root.activate(modelData, true)

                    Behavior on opacity {
                      NumberAnimation { duration: 110 }
                    }
                  }

                  Button {
                    iconText: favorites.starred(modelData) ? "󰓎" : "󰓒"
                    foreground: favorites.starred(modelData) ? Color.accent : root.foreground
                    opacity: !favorites.canStar(modelData) ? 0.0
                             : (favorites.starred(modelData) || rowMouse.containsMouse || rowSurface.current ? 1.0 : 0.0)
                    visible: opacity > 0
                    tooltipText: favorites.starred(modelData) ? t("Remove star  ·  f") : t("Star  ·  f")
                    onClicked: root.toggleFavorite(modelData)

                    Behavior on opacity {
                      NumberAnimation { duration: 110 }
                    }
                  }
                }

                MouseArea {
                  id: rowMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  cursorShape: Qt.PointingHandCursor
                  onClicked: function (mouse) {
                    root.selected = index
                    root.activate(modelData, mouse.button === Qt.RightButton)
                  }
                }
              }
            }
          }

          // Something to look at while a list loads, in the shape of the list
          // that is coming: an empty pane under a "loading…" chip reads as a
          // section that arrived wrong.
          Column {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            spacing: Style.space(2)
            visible: root.loading && root.visibleRows.length === 0

            SequentialAnimation on opacity {
              running: root.loading
              loops: Animation.Infinite
              NumberAnimation { from: 0.55; to: 0.28; duration: 700; easing.type: Easing.InOutQuad }
              NumberAnimation { from: 0.28; to: 0.55; duration: 700; easing.type: Easing.InOutQuad }
            }

            Repeater {
              model: 7

              Item {
                width: parent.width
                height: Style.space(56)

                Rectangle {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(40)
                  height: Style.space(40)
                  radius: Style.space(6)
                  color: root.faint
                }

                Column {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(64)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(7)

                  Rectangle {
                    width: Style.space(150 + (index % 3) * 60)
                    height: Style.space(9)
                    radius: height / 2
                    color: root.faint
                  }

                  Rectangle {
                    width: Style.space(90 + (index % 2) * 40)
                    height: Style.space(7)
                    radius: height / 2
                    color: root.faint
                  }
                }
              }
            }
          }

          // Empty and error states, instead of a blank pane.
          Column {
            anchors.centerIn: parent
            spacing: Style.space(8)
            visible: !root.loading && root.visibleRows.length === 0

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.error ? "󰅖"
                  : root.section === "favorites" ? "󰓒"
                  : root.section === "queue" ? "󰲹"
                  : root.section === "history" ? "󰄉"
                  : root.section === "local" ? "󰉋" : "󰝚"
              color: root.subdued
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              textFormat: Text.PlainText
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.error ? root.error
                  : root.filter ? t("Nothing matches this filter.")
                  : root.section === "favorites" ? t("Nothing starred yet. Press f on a station, a show or an episode and it lands here.")
                  : root.section === "queue" ? t("The queue is empty. Play something from Radio or Broadcast.")
                  : root.section === "history" ? t("Nothing played yet.")
                  : root.section === "local" ? t("No saved playlists yet. cliamp's playlist command makes them.")
                  : t("Nothing here yet. Press / to search.")
              width: Math.min(Style.space(420), parent.parent.width - Style.space(60))
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              color: root.subdued
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              textFormat: Text.PlainText
            }
          }

          // Scroll position, thin and out of the way.
          Rectangle {
            anchors.right: parent.right
            width: Style.space(3)
            radius: width / 2
            color: root.faint
            visible: listView.contentHeight > listView.height
            y: listView.visibleArea.yPosition * parent.height
            height: Math.max(Style.space(24), listView.visibleArea.heightRatio * parent.height)
          }
        }

        // ---- settings --------------------------------------------------------
        Flickable {
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.left: sidebar.right
          anchors.leftMargin: Style.space(16)
          anchors.right: parent.right
          visible: root.section === "settings"
          clip: true
          contentHeight: settingsColumn.implicitHeight
          boundsBehavior: Flickable.StopAtBounds

          // Two columns, because one made the pane taller than the window and
          // put the last group below a fold nothing announced.
          Row {
            id: settingsColumn
            width: parent.width
            spacing: Style.space(24)

            Column {
              width: (parent.width - Style.space(24)) / 2
              spacing: Style.space(18)

              // Output
              Column {
                width: parent.width
                spacing: Style.space(8)

                Text {
                  text: t("OUTPUT")
                  color: root.subdued
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1.2
                  textFormat: Text.PlainText
                }

                Repeater {
                  model: root.devices

                  Rectangle {
                    width: parent.width
                    height: Style.space(34)
                    radius: Style.spacing.labelGap
                    readonly property bool active: modelData.active === true || modelData.current === true || modelData.name === root.activeDevice
                    color: active ? root.selectedBackground : (deviceMouse.containsMouse ? root.faint : "transparent")

                    Text {
                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(10)
                      anchors.right: parent.right
                      anchors.rightMargin: Style.space(10)
                      anchors.verticalCenter: parent.verticalCenter
                      text: (parent.active ? "󰄬  " : "    ") + (modelData.description || modelData.name || "")
                      color: parent.active ? root.selectedText : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                      textFormat: Text.PlainText
                    }

                    MouseArea {
                      id: deviceMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        root.activeDevice = modelData.name
                        root.cliamp.call("device", {name: modelData.name}, function () { root.loadSettings() })
                      }
                    }
                  }
                }
              }

              // Equalizer
              Column {
                width: parent.width
                spacing: Style.space(8)

                Text {
                  text: t("EQUALIZER") + (root.cliamp && root.cliamp.eqPreset ? " · " + root.cliamp.eqPreset : "")
                  color: root.subdued
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1.2
                  textFormat: Text.PlainText
                }

                Flow {
                  width: parent.width
                  spacing: Style.space(6)

                  Repeater {
                    model: ["Flat", "Rock", "Pop", "Jazz", "Classical", "Bass", "Treble", "Vocal", "Electronic", "Acoustic"]

                    Button {
                      text: modelData
                      bordered: true
                      foreground: root.foreground
                      selected: root.cliamp && root.cliamp.eqPreset === modelData
                      onClicked: root.cliamp.setEqPreset(modelData)
                    }
                  }
                }

                // Band readout, so a preset is not just a name: bars grow up from
                // the zero line for a boost and down for a cut.
                Row {
                  height: Style.space(44)
                  spacing: Style.space(6)

                  Repeater {
                    model: root.cliamp ? root.cliamp.eqBands : []

                    Rectangle {
                      width: Style.space(16)
                      height: Style.space(44)
                      radius: Style.space(3)
                      color: root.faint

                      Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        y: parent.height / 2
                        height: 1
                        color: root.subdued
                        opacity: 0.45
                      }

                      Rectangle {
                        readonly property real span: Math.min(1, Math.abs(modelData) / 12)
                        width: parent.width
                        height: Math.max(2, span * (parent.height / 2 - Style.space(2)))
                        y: modelData >= 0 ? parent.height / 2 - height : parent.height / 2
                        radius: Style.space(3)
                        color: Color.accent
                        opacity: modelData === 0 ? 0.35 : 0.9
                      }
                    }
                  }
                }
              }

              // Playback
              Column {
                width: parent.width
                spacing: Style.space(8)

                Text {
                  text: t("PLAYBACK")
                  color: root.subdued
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1.2
                  textFormat: Text.PlainText
                }

                Flow {
                  width: parent.width
                  spacing: Style.space(6)

                  Repeater {
                    model: [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

                    Button {
                      text: modelData + "×"
                      bordered: true
                      foreground: root.foreground
                      selected: root.cliamp && Math.abs(root.cliamp.speed - modelData) < 0.01
                      onClicked: root.cliamp.setSpeed(modelData)
                    }
                  }
                }

                Flow {
                  width: parent.width
                  spacing: Style.space(6)

                  Repeater {
                    model: ["off", "all", "one"]

                    Button {
                      text: t("repeat ") + modelData
                      bordered: true
                      foreground: root.foreground
                      selected: root.cliamp && root.cliamp.repeat.toLowerCase() === modelData
                      onClicked: root.cliamp.setRepeat(modelData)
                    }
                  }

                  Button {
                    text: t("shuffle")
                    bordered: true
                    foreground: root.foreground
                    selected: root.cliamp && root.cliamp.shuffle
                    onClicked: root.cliamp.setShuffle(!root.cliamp.shuffle)
                  }

                  Button {
                    text: t("mono")
                    bordered: true
                    foreground: root.foreground
                    selected: root.cliamp && root.cliamp.mono
                    onClicked: root.cliamp.call("mono", {name: root.cliamp.mono ? "off" : "on"}, null)
                  }

                  Button {
                    text: t("spectrum")
                    bordered: true
                    foreground: root.foreground
                    selected: root.spectrumEnabled
                    onClicked: root.spectrumEnabled = !root.spectrumEnabled
                  }
                }
              }
            }

            Column {
              width: (parent.width - Style.space(24)) / 2
              spacing: Style.space(18)

              // Discovery
              Column {
                width: parent.width
                spacing: Style.space(8)

                Text {
                  text: t("DISCOVERY")
                  color: root.subdued
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1.2
                  textFormat: Text.PlainText
                }

                Flow {
                  width: parent.width
                  spacing: Style.space(8)

                  Button {
                    text: t("Broadcast country · ") + (root.countryName || root.country)
                    bordered: true
                    foreground: root.foreground
                    onClicked: {
                      root.selectSection("broadcast")
                      root.openCountryPicker()
                    }
                  }
                }

                Text {
                  width: parent.width
                  text: t("Detected from your timezone. Podcast charts follow cliamp's own setting in ~/.config/cliamp/config.toml.")
                  color: root.subdued
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                  textFormat: Text.PlainText
                }
              }

              // Window
              Column {
                width: parent.width
                spacing: Style.space(8)

                Text {
                  text: t("WINDOW")
                  color: root.subdued
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1.2
                  textFormat: Text.PlainText
                }

                Flow {
                  width: parent.width
                  spacing: Style.space(6)

                  Button {
                    text: t("Floating overlay")
                    bordered: true
                    foreground: root.foreground
                    selected: !root.prefs || root.prefs.windowMode === "overlay"
                    onClicked: root.windowModeRequested("overlay")
                  }

                  Button {
                    text: t("Normal window")
                    bordered: true
                    foreground: root.foreground
                    selected: root.prefs && root.prefs.windowMode === "window"
                    onClicked: root.windowModeRequested("window")
                  }
                }

                Flow {
                  width: parent.width
                  spacing: Style.space(6)

                  Button {
                    text: t("Title in the bar")
                    bordered: true
                    foreground: root.foreground
                    selected: !root.prefs || root.prefs.showTitle
                    onClicked: root.barTitleRequested(true)
                  }

                  Button {
                    text: t("Spectrum only")
                    bordered: true
                    foreground: root.foreground
                    selected: root.prefs && !root.prefs.showTitle
                    onClicked: root.barTitleRequested(false)
                  }
                }

                Text {
                  width: parent.width
                  text: t("An overlay sits above everything and closes when you click away from it. A normal window is one Hyprland tiles and keeps on its workspace \u2014 opening it again focuses the one you have rather than making a second. Switching reopens the window. The bar can show what is playing or just the spectrum — with the title gone, clicking it plays and pauses, and the card comes up while you rest on it.")
                  color: root.subdued
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                  textFormat: Text.PlainText
                }
              }

              // Language
              Column {
                width: parent.width
                spacing: Style.space(8)

                Text {
                  text: t("LANGUAGE")
                  color: root.subdued
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1.2
                  textFormat: Text.PlainText
                }

                Flow {
                  width: parent.width
                  spacing: Style.space(6)

                  Button {
                    text: t("System")
                    bordered: true
                    foreground: root.foreground
                    selected: !root.prefs || root.prefs.language === "auto"
                    onClicked: root.languageRequested("auto")
                  }

                  Button {
                    text: t("English")
                    bordered: true
                    foreground: root.foreground
                    selected: root.prefs && root.prefs.language === "en"
                    onClicked: root.languageRequested("en")
                  }

                  Button {
                    text: t("German")
                    bordered: true
                    foreground: root.foreground
                    selected: root.prefs && root.prefs.language === "de"
                    onClicked: root.languageRequested("de")
                  }
                }

                Text {
                  width: parent.width
                  text: t("The interface follows your system language unless you pick one here.")
                  color: root.subdued
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                  textFormat: Text.PlainText
                }
              }

              // Session
              Column {
                width: parent.width
                spacing: Style.space(8)

                Text {
                  text: t("SESSION")
                  color: root.subdued
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1.2
                  textFormat: Text.PlainText
                }

                Flow {
                  width: parent.width
                  spacing: Style.space(8)

                  Button {
                    text: t("Hand over to terminal")
                    bordered: true
                    foreground: root.foreground
                    onClicked: {
                      root.cliamp.handOffToTerminal()
                      root.close()
                    }
                  }

                  Button {
                    text: t("Reconnect")
                    bordered: true
                    foreground: root.foreground
                    onClicked: root.cliamp.refresh()
                  }
                }

                Text {
                  width: parent.width
                  text: t("Only one cliamp can hold the socket. Handing over stops the background player and opens the terminal one on the current track.")
                  color: root.subdued
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                  textFormat: Text.PlainText
                }
              }
            }
          }
          }
        }

      // ---- key hints --------------------------------------------------------
      Row {
        id: hintBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: transportBar.top
        anchors.bottomMargin: Style.space(10)
        height: Style.space(18)
        spacing: Style.space(14)

        Repeater {
          model: root.hints

          Row {
            spacing: Style.space(5)

            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: keyLabel.implicitWidth + Style.space(10)
              height: Style.space(18)
              radius: Style.space(4)
              color: root.faint

              Text {
                id: keyLabel
                anchors.centerIn: parent
                text: modelData.key
                color: root.subdued
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                textFormat: Text.PlainText
              }
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: t(modelData.label)
              color: root.subdued
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              textFormat: Text.PlainText
            }
          }
        }
      }

      // ---- transport --------------------------------------------------------
      Rectangle {
        id: transportBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Style.space(74)
        radius: Style.spacing.labelGap
        color: root.faint

        Item {
          anchors.fill: parent
          anchors.leftMargin: Style.space(14)
          anchors.rightMargin: Style.space(16)

          // The artwork of what is playing, where a player puts it.
          Rectangle {
            id: nowArt
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(46)
            height: Style.space(46)
            radius: Style.space(7)
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
            clip: true

            Image {
              anchors.fill: parent
              source: root.cliamp && root.cliamp.artUrl ? root.cliamp.artUrl : ""
              visible: source !== "" && status === Image.Ready
              asynchronous: true
              fillMode: Image.PreserveAspectCrop
              sourceSize.width: 128
              sourceSize.height: 128
            }

            Text {
              anchors.centerIn: parent
              visible: !root.cliamp || !root.cliamp.artUrl
              text: root.cliamp && root.cliamp.playing ? "󰝚" : "󰝟"
              color: root.subdued
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              textFormat: Text.PlainText
            }

            Rectangle {
              anchors.fill: parent
              radius: parent.radius
              color: "transparent"
              border.width: 1
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
            }
          }

          Column {
            anchors.left: nowArt.right
            anchors.leftMargin: Style.space(14)
            anchors.right: spectrum.left
            anchors.rightMargin: Style.space(16)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(5)

            Text {
              width: parent.width
              text: root.cliamp ? (root.cliamp.streamTitle || root.cliamp.trackTitle || t("Nothing playing")) : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              elide: Text.ElideRight
              textFormat: Text.PlainText
            }

            Text {
              width: parent.width
              text: root.cliamp ? [root.cliamp.trackArtist, root.cliamp.station].filter(function (part) { return part }).join(" · ") : ""
              color: root.subdued
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              textFormat: Text.PlainText
            }

            Item {
              width: parent.width
              height: Style.space(10)

              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: Style.space(3)
                radius: height / 2
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)

                Rectangle {
                  height: parent.height
                  radius: height / 2
                  color: Color.accent
                  width: {
                    if (!root.cliamp || !root.cliamp.duration) return 0
                    var ratio = root.cliamp.position / root.cliamp.duration
                    return Math.max(0, Math.min(1, ratio)) * parent.width
                  }
                }
              }

              MouseArea {
                anchors.fill: parent
                enabled: root.cliamp && root.cliamp.seekable && root.cliamp.duration > 0
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: function (mouse) {
                  root.cliamp.seekAbsolute((mouse.x / width) * root.cliamp.duration)
                }
              }
            }
          }

          // cliamp's own spectrum, straight off `cliamp visstream`.
          Row {
            id: spectrum
            anchors.right: controls.left
            anchors.rightMargin: Style.space(16)
            anchors.verticalCenter: parent.verticalCenter
            height: Style.space(36)
            spacing: Style.space(3)
            visible: root.spectrumEnabled && root.cliamp && root.cliamp.playing

            Repeater {
              model: 10

              Rectangle {
                width: Style.space(4)
                radius: width / 2
                color: Color.accent
                opacity: 0.85
                anchors.bottom: parent.bottom
                height: Math.max(Style.space(3), ((root.cliamp && root.cliamp.bands[index]) || 0) * spectrum.height)

                Behavior on height {
                  NumberAnimation { duration: 70; easing.type: Easing.OutQuad }
                }
              }
            }
          }

          Row {
            id: controls
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.cliamp ? (root.formatDuration(root.cliamp.position) + (root.cliamp.duration ? " / " + root.formatDuration(root.cliamp.duration) : "")) : ""
              color: root.subdued
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              textFormat: Text.PlainText
              rightPadding: Style.space(8)
            }

            Button {
              iconText: "󰒮"
              foreground: root.foreground
              tooltipText: t("Previous  ·  p")
              onClicked: root.cliamp.previous()
            }

            Button {
              iconText: root.cliamp && root.cliamp.playing ? "󰏤" : "󰐊"
              foreground: root.foreground
              tooltipText: t("Play / pause  ·  space")
              onClicked: root.cliamp.playPause()
            }

            Button {
              iconText: "󰒭"
              foreground: root.foreground
              tooltipText: t("Next  ·  n")
              onClicked: root.cliamp.next()
            }

            Button {
              iconText: "󰓛"
              foreground: root.foreground
              tooltipText: t("Stop")
              onClicked: root.cliamp.stop()
            }

            Button {
              iconText: "󰒟"
              foreground: root.foreground
              selected: root.cliamp && root.cliamp.shuffle
              tooltipText: t("Shuffle")
              onClicked: root.cliamp.setShuffle(!root.cliamp.shuffle)
            }

            Button {
              iconText: "󰑖"
              foreground: root.foreground
              selected: root.cliamp && root.cliamp.repeat !== "Off"
              tooltipText: t("Repeat · ") + (root.cliamp ? root.cliamp.repeat : "")
              onClicked: root.cliamp.setRepeat(root.cliamp.repeat.toLowerCase() === "off" ? "all" : root.cliamp.repeat.toLowerCase() === "all" ? "one" : "off")
            }

            Button {
              iconText: "󰝞"
              foreground: root.foreground
              tooltipText: t("Quieter  ·  −")
              onClicked: root.cliamp.adjustVolume(-1)
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.cliamp ? (root.cliamp.volumeDb > 0 ? "+" : "") + root.cliamp.volumeDb.toFixed(0) + " dB" : ""
              color: root.subdued
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              textFormat: Text.PlainText
            }

            Button {
              iconText: "󰝝"
              foreground: root.foreground
              tooltipText: t("Louder  ·  +")
              onClicked: root.cliamp.adjustVolume(1)
            }
          }
        }
      }

      // ---- keyboard help ----------------------------------------------------
      Rectangle {
        anchors.fill: parent
        anchors.margins: -card.contentLeftInset
        visible: root.helpOpen
        color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.96)
        radius: Style.cornerRadius
        z: 30

        MouseArea {
          anchors.fill: parent
          onClicked: root.helpOpen = false
        }

        Column {
          anchors.centerIn: parent
          width: Math.min(Style.space(640), parent.width - Style.space(80))
          spacing: Style.space(14)

          Text {
            text: t("Keyboard")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            textFormat: Text.PlainText
          }

          Grid {
            width: parent.width
            columns: 2
            columnSpacing: Style.space(30)
            rowSpacing: Style.space(9)

            Repeater {
              model: [
                {key: "↑ ↓ · PgUp PgDn", label: t("Move through the list")},
                {key: "Home · End", label: t("First / last entry")},
                {key: "⏎", label: t("Play, or open a show")},
                {key: "⇧⏎ · right-click", label: t("Queue next instead")},
                {key: "f", label: t("Favorite station / subscribe to show")},
                {key: "Del", label: t("Remove from the queue")},
                {key: "/", label: t("Search this section")},
                {key: "Esc · Backspace", label: t("Back, then close")},
                {key: "Tab · 1…7", label: t("Switch section")},
                {key: "Space", label: t("Play / pause")},
                {key: "n · p", label: t("Next / previous track")},
                {key: "+ · −", label: t("Volume by 1 dB")},
                {key: "← · →", label: t("Seek 10s (when seekable)")},
                {key: "?", label: t("This help")}
              ]

              Row {
                spacing: Style.space(10)
                width: (parent.width - Style.space(30)) / 2

                Rectangle {
                  width: Style.space(150)
                  height: Style.space(22)
                  radius: Style.space(4)
                  color: root.faint

                  Text {
                    anchors.centerIn: parent
                    text: modelData.key
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    textFormat: Text.PlainText
                  }
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.label
                  color: root.subdued
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  textFormat: Text.PlainText
                }
              }
            }
          }

          Text {
            text: t("Any key closes this.")
            color: root.subdued
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            textFormat: Text.PlainText
          }
        }
      }
    }
  }
}
