import QtQuick
import QtQuick.Layouts
import Quickshell

PanelWindow {
    id: root

    // Popup state — only one open at a time
    property bool dashboardOpen: false
    property bool powerOpen:     false

    function closeAll() {
        dashboardOpen = false
        powerOpen     = false
    }

    // Toggle the dashboard popup; ensure the bar is visible when opening it
    // (so the keybind still works after the bar has been hidden).
    function toggleDashboard() {
        var was = dashboardOpen
        closeAll()
        if (!was) visible = true
        dashboardOpen = !was
    }

    readonly property int barH: 42

    readonly property int activePopupH: {
        if (dashboardOpen) return dashboardPopup.implicitHeight + 12
        if (powerOpen)     return powerPopup.implicitHeight     + 12
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

        // Right group — system cluster island
        Island {
            id: rightIsland
            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }

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

    // ── Popup area (below bar strip) ─────────────────────────────────
    Item {
        anchors { top: barStrip.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        clip: true

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
    }

    // Close all popups when clicking outside
    MouseArea {
        anchors.fill: parent
        anchors.topMargin: root.barH
        z: -1
        onClicked: root.closeAll()
    }
}
