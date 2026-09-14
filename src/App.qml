import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// The window the bar opens: a layer-shell surface with the library inside it.
//
// The library knows nothing about windows, so this file owns the three things
// that are about being a window — the scrim and the click-outside that closes
// it, the keyboard grab, and the IPC a keybinding can call. dev/shell.qml hosts
// the same library in an ordinary window instead, which is how the harness can
// draw it offscreen.
Item {
  id: root

  property QtObject bar: null
  property var cliamp: null

  readonly property bool opened: library.opened

  function open() { library.open() }
  function close() { library.close() }
  function toggle() { library.toggle() }

  // Lets a keybinding (or a test) open the library without the bar:
  //   omarchy-shell janrenz.omarchy.cliamp toggle
  IpcHandler {
    target: "janrenz.omarchy.cliamp"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  PanelWindow {
    id: window
    visible: library.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-cliamp"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    Library {
      id: library
      bar: root.bar
      cliamp: root.cliamp
      anchors.centerIn: parent
      width: Math.min(Style.space(1100), window.width - Style.gapsOut * 2)
      height: Math.min(Style.space(760), window.height - Style.gapsOut * 2)
    }
  }
}
