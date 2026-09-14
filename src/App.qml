import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// The window the bar opens, in whichever shape the user asked for.
//
// The library knows nothing about windows, so this file owns everything that is
// about being one: the two surfaces it can live in, the scrim and click-outside
// that only an overlay has, and the IPC a keybinding can call. dev/shell.qml
// hosts the same library in an ordinary window, which is how the harness draws
// it offscreen.
//
// Two shapes, because they suit different habits. The overlay is a layer-shell
// surface over everything, summoned and dismissed; the window is an ordinary
// toplevel that Hyprland tiles, keeps on a workspace, and leaves open beside
// your terminal. Asking for a window that is already open focuses it rather
// than opening a second one.
Item {
  id: root

  property QtObject bar: null
  property var cliamp: null

  readonly property string windowMode: prefs.windowMode
  readonly property bool overlayMode: root.windowMode === "overlay"
  readonly property string windowTitle: "cliamp"

  property bool opened: false

  function open() {
    if (!root.overlayMode && root.opened) {
      // Already on a workspace somewhere: bring it here instead of opening a
      // second copy of the same library.
      root.focusToplevel()
      return
    }
    root.opened = true
  }

  function close() { root.opened = false }

  function toggle() {
    if (!root.overlayMode && root.opened) {
      root.focusToplevel()
      return
    }
    root.opened = !root.opened
  }

  // Matched on the title because a client cannot ask which toplevel is its own.
  // It is this file's own string rather than a guess at somebody else's window,
  // so the match is exact and stays exact.
  function focusToplevel() {
    // Ask through Wayland first: the compositor owns focus policy, and
    // requestActivate is the one route that does not need to know which
    // compositor this is.
    stacked.requestActivate()

    Hyprland.refreshToplevels()
    var all = Hyprland.toplevels ? Hyprland.toplevels.values : []
    for (var i = 0; i < all.length; i++) {
      if (all[i] && String(all[i].title) === root.windowTitle) {
        root.dispatchFocus(all[i])
        return
      }
    }
  }

  function dispatchFocus(toplevel) {
    var matcher = "address:0x" + toplevel.address
    // Two syntaxes, because this plugin is not installed on one machine only.
    // Current Hyprland takes a Lua expression and rejects the classic string
    // form outright - `focuswindow address:0x...` comes back "')' expected
    // near 'address'" - while the releases before it take only the string. An
    // unset usingLua means a Quickshell that does not report it, and the Lua
    // form is the one current Hyprland accepts, so that is the default.
    Hyprland.dispatch(Hyprland.usingLua === false
                      ? "focuswindow " + matcher
                      : "hl.dsp.focus({ window = '" + matcher + "' })")
  }

  Component.onCompleted: Hyprland.refreshToplevels()

  Prefs { id: prefs }

  // One library, built into whichever surface is showing it. Switching shape
  // rebuilds it, which is why the mode switch reopens the window.
  Component {
    id: libraryComponent

    Library {
      bar: root.bar
      cliamp: root.cliamp
      prefs: prefs
      opened: true
      onCloseRequested: root.close()
      onWindowModeRequested: function (mode) {
        prefs.setWindowMode(mode)
        root.opened = false
        reopenTimer.restart()
      }
    }
  }

  Timer {
    id: reopenTimer
    interval: 120
    onTriggered: root.open()
  }

  // Lets a keybinding (or a test) open the library without the bar:
  //   omarchy-shell janrenz.omarchy.cliamp toggle
  IpcHandler {
    target: "janrenz.omarchy.cliamp"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  // ---- overlay ------------------------------------------------------------

  PanelWindow {
    id: overlay
    visible: root.opened && root.overlayMode
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

    Loader {
      active: overlay.visible
      anchors.centerIn: parent
      width: Math.min(Style.space(1100), overlay.width - Style.gapsOut * 2)
      height: Math.min(Style.space(760), overlay.height - Style.gapsOut * 2)
      sourceComponent: libraryComponent
    }
  }

  // ---- ordinary window ----------------------------------------------------

  FloatingWindow {
    id: stacked
    visible: root.opened && !root.overlayMode
    title: root.windowTitle
    color: Color.menu.background
    implicitWidth: 1100
    implicitHeight: 760
    minimumSize: Qt.size(720, 480)

    // Closed from its own titlebar, or by Hyprland: the bar has to agree, or
    // the next click would "focus" a window that is no longer there.
    onVisibleChanged: if (!visible && !root.overlayMode) root.opened = false

    Loader {
      active: stacked.visible
      anchors.fill: parent
      sourceComponent: libraryComponent
    }
  }
}
