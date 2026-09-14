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

  // Zwei Karten, zwei Schalter: popupOpen ist die angeklickte mit Tastatur,
  // schwebeKarte die am Zeiger. Nie beide zugleich — sonst stünden zwei
  // Fassungen desselben Inhalts übereinander.
  property bool popupOpen: false
  property bool schwebeKarte: false
  readonly property bool karteOffen: popupOpen || schwebeKarte
  property bool hovered: false

  // Nur das Spektrum in der Leiste: dann ist der Titel nichts, was dauerhaft
  // Platz kostet — er kommt beim Überfahren dazu, und der Klick gehört dem
  // Abspielen statt dem Fenster. Wer den Titel stehen lässt, bekommt das
  // gewohnte Verhalten.
  readonly property bool spectrumOnly: !prefs.showTitle
  readonly property bool titelSichtbar: !root.bar.vertical
      && root.title !== ""
      && (prefs.showTitle || root.hovered)

  function close() {
    popupOpen = false
    schwebeKarte = false
  }

  // Im Spektrum-Modus gehört der Klick dem Abspielen, also kann er den Popover
  // nicht auch noch öffnen — sonst bliebe das Fenster hinter dem Rechtsklick
  // verborgen, den niemand sucht. Deshalb dieselbe Geste wie beim Titel: wer
  // stehenbleibt, bekommt die Karte mit den Angaben und den beiden Wegen
  // weiter. Die Verzögerung ist da, damit ein Vorbeifahren nichts aufklappt.
  Timer {
    id: karteOeffnen
    interval: 420
    onTriggered: if (root.hovered && root.spectrumOnly && !root.popupOpen) root.schwebeKarte = true
  }

  // Zwischen Leiste und Karte liegt eine Lücke, über die der Zeiger muss.
  // Sofort zu schließen hieße, die Karte nie erreichen zu können.
  Timer {
    id: karteSchliessen
    interval: 260
    onTriggered: if (!root.hovered && !popup.containsMouse) root.schwebeKarte = false
  }

  // Die angeklickte Karte auf oder zu. Die am Zeiger geht dabei weg: sie
  // zeigt dasselbe, nur ohne Tastatur.
  function karteUmschalten() {
    karteOeffnen.stop()
    schwebeKarte = false
    popupOpen = !popupOpen
  }

  function playPause() {
    if (cliamp.connected) {
      cliamp.playPause()
      return
    }
    if (root.mediaService && root.activePlayer) {
      root.mediaService.runAction("playPause", false, root.mediaService.playerKey(root.activePlayer))
    }
  }

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
      // Im Spektrum-Modus wächst die Breite beim Überfahren von 0 auf den
      // Titel und wieder zurück. Über die Breite statt über visible, damit die
      // Leiste sich nicht ruckartig umbaut — und damit der Titel nicht
      // erscheint, bevor Platz für ihn da ist.
      width: root.titelSichtbar ? Math.min(root.maxLabelWidth, labelText.implicitWidth) : 0
      height: glyph.height
      clip: true
      anchors.verticalCenter: parent.verticalCenter
      visible: width > 0

      Behavior on width {
        NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
      }

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
          running: root.isPlaying && labelText.needsScroll && !root.karteOffen && !root.bar.vertical
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
        // Spektrum allein: der Klick liegt auf dem, was man sieht — den
        // tanzenden Balken — und die tun das Naheliegende. Steht der Titel da,
        // führt der Klick weiter ins Programm.
        if (root.spectrumOnly) root.playPause()
        else root.karteUmschalten()
        return
      }
      if (mouse.button === Qt.MiddleButton) {
        if (root.activePlayer && root.mediaService) root.mediaService.runAction("next", false)
        else if (cliamp.connected) cliamp.next()
      } else if (mouse.button === Qt.RightButton) {
        // Der Weg zur Karte mit Tastatur, in beiden Modi: im Spektrum-Modus
        // liegt der Linksklick auf Play/Pause, und die Karte am Zeiger kann
        // keine Tasten annehmen.
        root.karteUmschalten()
      }
    }
    onWheel: function(wheel) {
      const vor = wheel.angleDelta.y < 0
      if (root.activePlayer && root.mediaService) {
        root.mediaService.runAction(vor ? "next" : "previous", false)
      } else if (cliamp.connected) {
        if (vor) cliamp.next()
        else cliamp.previous()
      }
    }
    onEntered: {
      root.hovered = true
      if (root.spectrumOnly) {
        karteSchliessen.stop()
        karteOeffnen.restart()
      }
      // Im Spektrum-Modus steht der Titel jetzt in der Leiste selbst — eine
      // Sprechblase mit demselben Text daneben wäre doppelt.
      if (root.bar && !root.spectrumOnly) {
        root.bar.showTooltip(root, root.hasMedia ? (root.title + (root.artist ? " — " + root.artist : "")) : "")
      }
    }
    onExited: {
      root.hovered = false
      karteOeffnen.stop()
      if (root.spectrumOnly && root.schwebeKarte) karteSchliessen.restart()
      if (root.bar) root.bar.hideTooltip(root)
    }
  }

  // Der Inhalt der Karte, einmal beschrieben und in beide Fassungen geladen.
  // Zwei sind es, weil eine Karte nicht beides sein kann: die am Zeiger darf
  // die Tastatur nicht an sich nehmen — sonst verlöre jedes Vorbeifahren an der
  // Leiste dem Fenster darunter den Fokus —, und ohne Tastatur gibt es keine
  // Tastenkürzel. Also hängt die eine am Zeiger und die andere am Klick.
  Component {
    id: karteInhalt

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

      // Die Wege weiter. Sie stehen oben bei den Angaben statt unten hinter
      // der Quellenliste: wer die Karte öffnet, will meistens genau hierhin,
      // und hinter einer langen Liste fände er sie nicht.
      Row {
        width: parent.width
        spacing: Style.space(6)

        Button {
          text: "Open window"
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          onClicked: {
            root.popupOpen = false
            app.open()
          }
        }

        Button {
          iconText: "󰒓"
          text: "Settings"
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          onClicked: {
            root.popupOpen = false
            app.openAt("settings")
          }
        }
      }


      // Dieselben Wege über die Tastatur, und sie stehen auch da. Nur in der
      // angeklickten Fassung: die am Zeiger hat keinen Tastaturfokus, und
      // Tasten anzubieten, die dort nichts tun, wäre gelogen.
      Row {
        visible: tastenKarte.open
        width: parent.width
        spacing: Style.space(12)

        Repeater {
          model: [
            {taste: "o", was: "window"},
            {taste: "s", was: "settings"},
            {taste: "space", was: "play/pause"},
            {taste: "esc", was: "close"},
          ]

          Row {
            id: tastenZeile
            required property var modelData
            spacing: Style.space(5)

            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: tastenName.implicitWidth + Style.space(10)
              height: Style.space(18)
              radius: Style.space(4)
              color: Qt.alpha(root.bar.foreground, 0.1)

              Text {
                id: tastenName
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: tastenZeile.modelData.taste
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: tastenZeile.modelData.was
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }

      PanelSeparator { foreground: root.bar.foreground }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(6)

        Button {
          iconText: "󰒮"
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          enabled: cliamp.connected || (root.activePlayer && root.activePlayer.canGoPrevious)
          opacity: enabled ? 1.0 : 0.4
          onClicked: {
            if (root.activePlayer && root.mediaService) root.mediaService.runAction("previous", false, root.mediaService.playerKey(root.activePlayer))
            else cliamp.previous()
          }
        }

        Button {
          iconText: root.isPlaying ? "󰏤" : "󰐊"
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.panelGap
          verticalPadding: Style.spacing.controlPaddingY
          iconSize: Style.font.iconLarge
          enabled: cliamp.connected || (root.activePlayer && (root.activePlayer.canTogglePlaying || root.activePlayer.canPlay || root.activePlayer.canPause))
          opacity: enabled ? 1.0 : 0.4
          onClicked: root.playPause()
        }

        Button {
          iconText: "󰒭"
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          enabled: cliamp.connected || (root.activePlayer && root.activePlayer.canGoNext)
          opacity: enabled ? 1.0 : 0.4
          onClicked: {
            if (root.activePlayer && root.mediaService) root.mediaService.runAction("next", false, root.mediaService.playerKey(root.activePlayer))
            else cliamp.next()
          }
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

  // Zeiger-Fassung: nur im Spektrum-Modus, ohne Fokusgriff und ohne Tastatur.
  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    triggerMode: "hover"
    open: root.schwebeKarte
    onContainsMouseChanged: {
      if (popup.containsMouse) karteSchliessen.stop()
      else if (root.spectrumOnly && !root.hovered) karteSchliessen.restart()
    }
    contentWidth: popup.fittedContentWidth(Style.space(320))
    contentHeight: popup.fittedContentHeight(schwebeInhalt.item ? schwebeInhalt.item.implicitHeight : 0)

    Loader {
      id: schwebeInhalt
      anchors.fill: parent
      sourceComponent: karteInhalt
    }
  }

  // Klick-Fassung: dieselbe Karte, aber als Tastaturfeld. KeyboardPanel nimmt
  // den Fokus kurz exklusiv, damit die Tasten auch dann ankommen, wenn die
  // Karte aus der Leiste heraus aufgeht und nicht aus einem Fenster.
  KeyboardPanel {
    id: tastenKarte
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    focusTarget: tastenFaenger
    contentWidth: Style.space(320)
    contentHeight: (tastenInhalt.item ? tastenInhalt.item.implicitHeight : 0)
        + tastenKarte.padding * 2 + Border.top(tastenKarte.borderSpec) + Border.bottom(tastenKarte.borderSpec)

    Item {
      id: tastenFaenger
      anchors.fill: parent
      focus: true

      // BeforeItem, damit die Karte die Taste sieht, bevor ein Knopf darin sie
      // für sich nimmt — sonst hinge das Kürzel davon ab, wo der Fokus gerade
      // steht.
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Escape) {
          root.close()
        } else if (event.text === "o" || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.close()
          app.open()
        } else if (event.text === "s") {
          root.close()
          app.openAt("settings")
        } else if (event.key === Qt.Key_Space) {
          root.playPause()
        } else if (event.key === Qt.Key_Left || event.text === "p") {
          if (root.activePlayer && root.mediaService) root.mediaService.runAction("previous", false, root.mediaService.playerKey(root.activePlayer))
          else if (cliamp.connected) cliamp.previous()
        } else if (event.key === Qt.Key_Right || event.text === "n") {
          if (root.activePlayer && root.mediaService) root.mediaService.runAction("next", false, root.mediaService.playerKey(root.activePlayer))
          else if (cliamp.connected) cliamp.next()
        } else {
          return
        }
        event.accepted = true
      }

      Loader {
        id: tastenInhalt
        anchors.fill: parent
        sourceComponent: karteInhalt
      }
    }
  }
}
