import QtQuick
import Quickshell
import Quickshell.Io
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
  property var prefs: null

  readonly property string windowMode: root.prefs ? root.prefs.windowMode : "overlay"
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

  // Welcher Bereich beim nächsten Öffnen zuerst steht. Leer heißt: der übliche.
  // Wird beim Aufbau der Library wieder geleert, sonst landete jedes spätere
  // Öffnen dort, wo man einmal hin wollte.
  property string startSection: ""

  function openAt(section) {
    root.startSection = section || ""
    // Steht das Fenster schon, wechselt der Bereich sofort — sonst passiert auf
    // den Klick nichts Sichtbares, weil open() nur ein offenes Fenster fokussiert.
    if (root.opened && root.library) {
      root.library.selectSection(section)
      root.startSection = ""
    }
    root.open()
  }

  // Die gerade gebaute Library, damit openAt() sie erreicht. Es gibt immer nur
  // eine: Overlay und Fenster schließen sich gegenseitig aus.
  property var library: null

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
  //
  // Through hyprctl rather than Quickshell's Hyprland.dispatch: the same
  // expression that focuses the window from a shell did nothing through the
  // module, and a focus request that silently does nothing is worse than a
  // process spawn.
  function focusToplevel() {
    focusProc.running = true
  }

  Process {
    id: focusProc
    // Two syntaxes, because this plugin is not installed on one machine only.
    // Current Hyprland takes a Lua expression and refuses the classic string
    // form outright - `focuswindow title:...` comes back "')' expected near
    // 'title'" - while the releases before it take only the string. Try the
    // Lua one, fall back to the old one when it is rejected.
    command: ["bash", "-lc",
              "hyprctl dispatch \"hl.dsp.focus({ window = 'title:^" + root.windowTitle + "$' })\" 2>/dev/null"
              + " | grep -qx ok || hyprctl dispatch focuswindow title:^" + root.windowTitle + "$ >/dev/null 2>&1"]
  }

  // One library, built into whichever surface is showing it. Switching shape
  // rebuilds it, which is why the mode switch reopens the window.
  Component {
    id: libraryComponent

    Library {
      bar: root.bar
      cliamp: root.cliamp
      prefs: root.prefs
      opened: true
      onCloseRequested: root.close()
      onBarTitleRequested: function (show) {
        if (root.prefs) root.prefs.setShowTitle(show)
      }
      onLanguageRequested: function (lang) {
        if (root.prefs) root.prefs.setLanguage(lang)
      }
      onWindowModeRequested: function (mode) {
        if (root.prefs) root.prefs.setWindowMode(mode)
        root.opened = false
        reopenTimer.restart()
      }

      Component.onCompleted: {
        root.library = this
        if (root.startSection) {
          selectSection(root.startSection)
          root.startSection = ""
        }
      }
      Component.onDestruction: if (root.library === this) root.library = null
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
      // Loader ist ein Fokusbereich: ohne dieses focus bekommt nichts darin je
      // den Tastaturfokus, und der keyCatcher der Library sieht keine Taste —
      // kein Escape, kein /, keine Pfeile. Nicht forceActiveFocus auf item:
      // das setzte den Fokus auf die Wurzel der Library und nähme ihn dem
      // Fänger darin wieder weg.
      focus: true
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
    //
    // Only a close that follows a real showing counts. `visible` also goes
    // false while the window is being created, and taking that for a close
    // cleared `opened` behind the bar's back - after which asking for the
    // window again looked like a first open and never focused anything.
    property bool everShown: false

    onVisibleChanged: {
      if (visible) {
        stacked.everShown = true
      } else if (stacked.everShown && !root.overlayMode) {
        stacked.everShown = false
        root.opened = false
      }
    }

    Loader {
      active: stacked.visible
      // Loader ist ein Fokusbereich: ohne dieses focus bekommt nichts darin je
      // den Tastaturfokus, und der keyCatcher der Library sieht keine Taste —
      // kein Escape, kein /, keine Pfeile. Nicht forceActiveFocus auf item:
      // das setzte den Fokus auf die Wurzel der Library und nähme ihn dem
      // Fänger darin wieder weg.
      focus: true
      anchors.fill: parent
      sourceComponent: libraryComponent
    }
  }
}
