import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland

PanelWindow {
    id: root

    // Popup state — only one open at a time
    property bool dashboardOpen: false
    property bool powerOpen:     false
    // Agent board (docs/agent-board.md)
    property bool rosterOpen:    false
    property bool wallOpen:      false
    property bool keysOpen:      false
    property string wallFocusKey: ""

    readonly property bool anyPopupOpen: dashboardOpen || powerOpen || rosterOpen || wallOpen || keysOpen

    // Take keyboard focus only while a popup is open, so Escape can close it
    // without the bar stealing focus the rest of the time.
    focusable: anyPopupOpen

    // Grab input while a popup is open: a click anywhere outside this window
    // fires `cleared`, which closes the popup.
    HyprlandFocusGrab {
        windows: [root]
        active: root.anyPopupOpen
        onCleared: root.closeAll()
    }

    function closeAll() {
        dashboardOpen = false
        powerOpen     = false
        rosterOpen    = false
        wallOpen      = false
        keysOpen      = false
    }

    // Toggle the dashboard popup; ensure the bar is visible when opening it
    // (so the keybind still works after the bar has been hidden).
    function toggleDashboard() {
        var was = dashboardOpen
        closeAll()
        if (!was) visible = true
        dashboardOpen = !was
    }

    // Agent board popups: each toggles itself, closes whatever else is open,
    // and re-shows the bar if it was hidden (so the keybinds always work).
    function toggleRoster() {
        var was = rosterOpen
        closeAll()
        if (!was) visible = true
        rosterOpen = !was
    }
    function toggleWall(key) {
        var was = wallOpen
        closeAll()
        if (!was) { visible = true; wallFocusKey = key || "" }
        wallOpen = !was
    }
    function toggleKeys() {
        var was = keysOpen
        closeAll()
        if (!was) visible = true
        keysOpen = !was
    }

    readonly property int barH: 42
    readonly property int screenH: screen ? screen.height : 1440
    readonly property int bigPopupMaxH: screenH - barH - 40

    // Distance from the screen's right edge to the agents island's right edge:
    // the roster and the toast hang from there.
    readonly property real agentsRight: agentsIsland.visible
        ? 10 + rightGroup.width - (agentsIsland.x + agentsIsland.width) : 10

    readonly property int activePopupH: {
        if (dashboardOpen) return dashboardPopup.implicitHeight + 12
        if (powerOpen)     return powerPopup.implicitHeight     + 12
        if (rosterOpen)    return rosterPopup.implicitHeight    + 12
        if (wallOpen)      return wallPopup.implicitHeight      + 12
        if (keysOpen)      return keysPopup.implicitHeight      + 12
        return 0
    }

    anchors { top: true; left: true; right: true }
    // Snap the surface to its needed size instantly — animating the layershell
    // window height per-frame is what causes stutter. The popups animate their
    // own opacity/position instead, which is cheap and smooth.
    implicitHeight: barH + activePopupH
    exclusiveZone: barH

    color: "transparent"

    // ── Bar strip (transparent — islands float over the desktop) ──────
    Item {
        id: barStrip
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: root.barH

        // Left group — workspaces island + floating window title
        RowLayout {
            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
            spacing: 10

            Island {
                hpad: 11
                Workspaces {}
            }

            WindowTitle {}
        }

        // Center group — clock island, pinned to the true screen centre so it
        // never shifts when the title or right cluster change width
        Island {
            anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter }
            Clock {
                onToggleCalendar: root.toggleDashboard()
            }
        }

        // Right group — agents island, keys hint, system cluster island
        RowLayout {
            id: rightGroup
            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
            spacing: 8

            // Agent board: needs-you / running / background counts + live stack.
            // Hidden until the `board` CLI answers.
            AgentsIsland {
                id: agentsIsland
                visible: Board.available
                open: root.rosterOpen
                onToggleRoster: root.toggleRoster()
            }

            // "⊞ /" — opens the keys cheatsheet
            KeysHint {
                onToggleKeys: root.toggleKeys()
            }

            Island {
                id: rightIsland

                RowLayout {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 14

                    Media   {}
                    Volume  {}
                    Network {}
                    SysStats{}
                    Battery {}

                    Weather {
                        onToggleWeather: root.toggleDashboard()
                    }

                    PowerButton {
                        onTogglePower: {
                            var was = root.powerOpen
                            root.closeAll()
                            root.powerOpen = !was
                        }
                    }
                }
            }
        }
    }

    // ── Popup area (below bar strip) ─────────────────────────────────
    Item {
        anchors { top: barStrip.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        clip: true

        // Escape closes whichever popup is open. Grab focus while open so the
        // key reaches us even though the bar isn't normally focusable.
        focus: root.anyPopupOpen
        Keys.onEscapePressed: root.closeAll()

        // Dashboard — calendar + weather, under the centre clock
        DashboardPopup {
            id: dashboardPopup
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 4
            visible: root.dashboardOpen
            opacity: root.dashboardOpen ? 1 : 0
            y: root.dashboardOpen ? 0 : -8
            Behavior on opacity { NumberAnimation { duration: 160 } }
            Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }
            onRequestClose: root.closeAll()
        }

        // Power menu — far right
        PowerPopup {
            id: powerPopup
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.top: parent.top
            anchors.topMargin: 4
            visible: root.powerOpen
            opacity: root.powerOpen ? 1 : 0
            y: root.powerOpen ? 0 : -8
            Behavior on opacity { NumberAnimation { duration: 160 } }
            Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }
            onClosePopup: root.closeAll()
        }

        // Roster — hangs from the agents island
        Roster {
            id: rosterPopup
            anchors.right: parent.right
            anchors.rightMargin: Math.max(10, Math.min(root.agentsRight, parent.width - width - 10))
            anchors.top: parent.top
            anchors.topMargin: 4
            width: implicitWidth
            maxHeight: root.bigPopupMaxH
            active: root.rosterOpen
            visible: root.rosterOpen
            opacity: root.rosterOpen ? 1 : 0
            y: root.rosterOpen ? 0 : -8
            Behavior on opacity { NumberAnimation { duration: 160 } }
            Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }
            onRequestClose: root.closeAll()
            onOpenWall: function (key) { root.toggleWall(key) }
            onOpenKeys: root.toggleKeys()
        }

        // Checklist wall — centred, most of the screen
        ChecklistWall {
            id: wallPopup
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 4
            width: Math.min(parent.width * 0.94, 1800)
            maxHeight: root.bigPopupMaxH
            focusKey: root.wallFocusKey
            active: root.wallOpen
            visible: root.wallOpen
            opacity: root.wallOpen ? 1 : 0
            y: root.wallOpen ? 0 : -8
            Behavior on opacity { NumberAnimation { duration: 160 } }
            Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }
            onRequestClose: root.closeAll()
            onOpenKeys: root.toggleKeys()
        }

        // Keys cheatsheet — centred
        KeysCheatsheet {
            id: keysPopup
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 4
            width: Math.min(parent.width * 0.9, 1500)
            maxHeight: root.bigPopupMaxH
            active: root.keysOpen
            visible: root.keysOpen
            opacity: root.keysOpen ? 1 : 0
            y: root.keysOpen ? 0 : -8
            Behavior on opacity { NumberAnimation { duration: 160 } }
            Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }
            onRequestClose: root.closeAll()
        }
    }

    // Close all popups when clicking outside
    MouseArea {
        anchors.fill: parent
        anchors.topMargin: root.barH
        z: -1
        onClicked: root.closeAll()
    }
}
