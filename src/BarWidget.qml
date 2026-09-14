import QtQuick
import Quickshell
import qs.Ui
import qs.Commons

BarWidget {
  id: root
  moduleName: "janrenz.omarchy.cliamp"

  readonly property var mediaService: bar?.shell?.serviceFor(root.moduleName)
  readonly property var activePlayer: mediaService ? mediaService.activePlayer : null
  readonly property var sourcePlayers: mediaService ? mediaService.sourcePlayers : []

  readonly property bool mprisMedia: activePlayer !== null && (activePlayer.trackTitle || activePlayer.trackArtist)
  // Stopped is not paused: with nothing loaded there is nothing to say, and a
  // widget reading "Paused" at a player that holds no track is a small lie.
  readonly property bool cliampMedia: cliamp.connected
      && (cliamp.playing || cliamp.paused)
      && (cliamp.streamTitle || cliamp.trackTitle) !== ""
  // When cliamp is reachable its state is the authority: MPRIS keeps reporting
  // the last track of a player that has stopped, and the bar should not.
  // MPRIS still answers for everything else on the bus - a browser, Spotify -
  // which is what the popup is for.
  readonly property bool hasMedia: cliamp.connected ? cliampMedia : mprisMedia
  readonly property bool isPlaying: cliamp.connected
      ? cliamp.playing
      : (activePlayer ? activePlayer.isPlaying : false)
  readonly property string playIcon: isPlaying ? "󰏤" : "󰐊"
  // On radio, MPRIS reports the station as the title while cliamp reports the
  // song the station is playing — prefer the song, and keep the station as the
  // secondary label.
  readonly property string title: cliamp.connected
      ? (cliampMedia ? (cliamp.streamTitle || cliamp.trackTitle || "") : "")
      : (mprisMedia ? (activePlayer.trackTitle || "") : "")
  readonly property string artist: cliamp.connected
      ? (cliampMedia ? (cliamp.station || cliamp.trackArtist || "") : "")
      : (mprisMedia ? (activePlayer.trackArtist || "") : "")

  property bool popupOpen: false

  function close() { popupOpen = false }

  // cliamp's IPC client and the full app window both live here so the bar
  // widget is the single entry point: click opens the app, right-click keeps
  // the small MPRIS popup.
  Cliamp {
    id: cliamp
    // The bar shows what plays even when the window is closed.
    watch: true
    wantVisualizer: true
  }

  Prefs { id: prefs }

  App {
    id: app
    bar: root.bar
    cliamp: cliamp
    prefs: prefs
  }
  property real maxLabelWidth: 180

  visible: true
  implicitWidth: row.implicitWidth + Style.space(14)
  implicitHeight: barSize

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(6)

    // The spectrum is the state indicator: it dances while something plays,
    // rests low and dim when paused, and is replaced by a quiet note glyph
    // when nothing is loaded at all.
    Text {
      id: glyph
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.hasMedia
      text: "󰝚"
      color: Qt.darker(root.bar.barForeground, 1.6)
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
    }

    Row {
      id: miniVis
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)
      visible: root.hasMedia && !root.bar.vertical
      height: Math.round(root.barSize * 0.55)

      Repeater {
        model: 5

        Rectangle {
          // Five bars sampled across cliamp's ten bands while it plays. On
          // pause the outer three collapse and the two inner ones grow into a
          // pause glyph — the same five rectangles, morphed, so the widget
          // never jumps between two different shapes.
          readonly property bool pauseStroke: index === 1 || index === 3

          width: root.isPlaying ? Style.space(2) : (pauseStroke ? Style.space(3) : 0)
          height: root.isPlaying
              ? Math.max(Style.space(2), (cliamp.bands[index * 2] || 0) * miniVis.height)
              : (pauseStroke ? miniVis.height : Style.space(2))
          radius: width / 2
          color: root.bar.barForeground
          anchors.bottom: parent.bottom
          opacity: root.isPlaying ? 0.9 : (pauseStroke ? 0.75 : 0)

          Behavior on width {
            NumberAnimation { duration: 190; easing.type: Easing.InOutQuad }
          }

          Behavior on height {
            NumberAnimation { duration: root.isPlaying ? 90 : 190; easing.type: Easing.OutQuad }
          }

          Behavior on opacity {
            NumberAnimation { duration: 190 }
          }
        }
      }
    }

    Item {
      id: scrollClip
      width: Math.min(root.maxLabelWidth, labelText.implicitWidth)
      height: glyph.height
      clip: true
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.bar.vertical && root.title !== "" && prefs.showTitle

      Text {
        id: labelText
        textFormat: Text.PlainText
        text: root.isPlaying ? (root.title + (root.artist ? "  ·  " + root.artist : ""))
                             : (root.hasMedia ? "Paused" : "")
        color: root.bar.barForeground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter

        property bool needsScroll: implicitWidth > scrollClip.width

        NumberAnimation on x {
          id: scrollAnim
          running: root.isPlaying && labelText.needsScroll && !root.popupOpen && !root.bar.vertical
          loops: Animation.Infinite
          duration: Math.max(6000, labelText.implicitWidth * 25)
          from: scrollClip.width
          to: -labelText.implicitWidth
          easing.type: Easing.Linear
          // The animation owns x while it runs; put the label back at the
          // start when it stops, or a paused label sits off-screen.
          onRunningChanged: if (!running) labelText.x = 0
        }
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    onClicked: function(mouse) {
      if (mouse.button === Qt.LeftButton) {
        app.toggle()
        return
      }
      if (!root.activePlayer) return
      if (mouse.button === Qt.MiddleButton) {
        if (root.mediaService) root.mediaService.runAction("next", false)
      } else if (mouse.button === Qt.RightButton) {
        root.popupOpen = !root.popupOpen
      }
    }
    onWheel: function(wheel) {
      if (!root.activePlayer) return
      if (wheel.angleDelta.y > 0 && root.mediaService) root.mediaService.runAction("previous", false)
      else if (wheel.angleDelta.y < 0 && root.mediaService) root.mediaService.runAction("next", false)
    }
    onEntered: if (root.bar) root.bar.showTooltip(root, root.hasMedia ? (root.title + (root.artist ? " — " + root.artist : "")) : "")
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(320))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.space(10)

      Row {
        spacing: Style.space(10)
        width: parent.width

        BorderSurface {
          width: Style.space(64)
          height: Style.space(64)
          radius: Style.spacing.labelGap
          color: Style.normalFillFor(root.bar.foreground, Color.accent)
          borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)

          Image {
            anchors.fill: parent
            anchors.margins: Style.space(2)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            source: root.activePlayer && root.activePlayer.trackArtUrl ? root.activePlayer.trackArtUrl : ""
            visible: source !== ""
          }

          Text {
            anchors.centerIn: parent
            visible: !root.activePlayer || !root.activePlayer.trackArtUrl
            text: "󰝚"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.displayLarge
          }
        }

        Column {
          spacing: Style.space(4)
          width: parent.width - Style.space(74)

          Text {
            textFormat: Text.PlainText
            text: root.title || "Nothing playing"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            elide: Text.ElideRight
            width: parent.width
          }

          Text {
            textFormat: Text.PlainText
            text: root.artist
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
            width: parent.width
            visible: text !== ""
          }

          Text {
            textFormat: Text.PlainText
            text: root.activePlayer && root.activePlayer.trackAlbum ? root.activePlayer.trackAlbum : ""
            color: Qt.darker(root.bar.foreground, 1.6)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: parent.width
            visible: text !== ""
          }
        }
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(6)

        Button {
          iconText: "󰒮"
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          enabled: root.activePlayer && root.activePlayer.canGoPrevious
          opacity: enabled ? 1.0 : 0.4
          onClicked: if (root.mediaService) root.mediaService.runAction("previous", false, root.mediaService.playerKey(root.activePlayer))
        }

        Button {
          iconText: root.activePlayer && root.activePlayer.isPlaying ? "󰏤" : "󰐊"
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.panelGap
          verticalPadding: Style.spacing.controlPaddingY
          iconSize: Style.font.iconLarge
          enabled: root.activePlayer && (root.activePlayer.canTogglePlaying || root.activePlayer.canPlay || root.activePlayer.canPause)
          opacity: enabled ? 1.0 : 0.4
          onClicked: if (root.mediaService) root.mediaService.runAction("playPause", false, root.mediaService.playerKey(root.activePlayer))
        }

        Button {
          iconText: "󰒭"
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          enabled: root.activePlayer && root.activePlayer.canGoNext
          opacity: enabled ? 1.0 : 0.4
          onClicked: if (root.mediaService) root.mediaService.runAction("next", false, root.mediaService.playerKey(root.activePlayer))
        }
      }

      PanelSeparator {
        visible: root.sourcePlayers.length > 1
        foreground: root.bar.foreground
      }

      Column {
        id: sourceList
        visible: root.sourcePlayers.length > 1
        width: parent.width
        spacing: Style.space(4)

        Repeater {
          model: root.sourcePlayers

          BorderSurface {
            id: sourceRow
            required property var modelData

            readonly property var player: modelData
            readonly property bool selected: root.activePlayer && player
              && root.mediaService.playerKey(root.activePlayer) === root.mediaService.playerKey(player)
            readonly property string sourceTitle: player ? (player.trackTitle || player.identity || player.desktopEntry || "Media source") : "Media source"
            readonly property string sourceDetail: player && player.trackArtist ? player.trackArtist : (player && player.identity ? player.identity : "")

            width: sourceList.width
            height: sourceInner.implicitHeight + Style.space(10)
            radius: Style.spacing.labelGap
            color: selected ? Style.selectedFillFor(root.bar.foreground, Color.accent) : "transparent"
            borderSpec: selected ? Border.controlSpec("normal", root.bar.foreground, Color.accent) : Border.none()

            Row {
              id: sourceInner
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: sourceRow.borderLeft + Style.space(8)
              anchors.rightMargin: sourceRow.borderRight + Style.space(8)
              spacing: Style.space(8)

              Text {
                textFormat: Text.PlainText
                text: sourceRow.player && sourceRow.player.isPlaying ? "󰏤" : "󰐊"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                width: Style.space(18)
                horizontalAlignment: Text.AlignHCenter
                anchors.verticalCenter: parent.verticalCenter
              }

              Column {
                width: parent.width - Style.space(26)
                spacing: Style.space(1)
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  textFormat: Text.PlainText
                  text: sourceRow.sourceTitle
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: sourceRow.selected
                  elide: Text.ElideRight
                  width: parent.width
                }

                Text {
                  textFormat: Text.PlainText
                  text: sourceRow.sourceDetail
                  color: Qt.darker(root.bar.foreground, 1.5)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  width: parent.width
                  visible: text !== ""
                }
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.mediaService) root.mediaService.selectPlayer(root.mediaService.playerKey(sourceRow.player))
            }
          }
        }
      }
    }
  }
}
