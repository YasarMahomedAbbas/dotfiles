import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import "Colors.js" as C

Item {
    id: root
    implicitWidth: 720
    implicitHeight: card.implicitHeight

    signal requestClose()

    SystemClock { id: clock; precision: SystemClock.Precision.Minutes }

    // ── Calendar state ───────────────────────────────────────────────
    property int viewYear:  clock.date.getFullYear()
    property int viewMonth: clock.date.getMonth()
    onVisibleChanged: if (visible) {
        viewYear  = clock.date.getFullYear()
        viewMonth = clock.date.getMonth()
        proc.running = true
        todoProc.running = true
    }

    readonly property var monthNames: [
        "January","February","March","April","May","June",
        "July","August","September","October","November","December"
    ]
    readonly property var dayNames: ["Mo","Tu","We","Th","Fr","Sa","Su"]
    function daysInMonth(y, m) { return new Date(y, m + 1, 0).getDate() }
    function firstDayOfWeek(y, m) {
        var d = new Date(y, m, 1).getDay()
        return d === 0 ? 6 : d - 1
    }

    readonly property string greeting: {
        var h = clock.date.getHours()
        if (h < 5)  return "Good night"
        if (h < 12) return "Good morning"
        if (h < 18) return "Good afternoon"
        return "Good evening"
    }

    // ── Weather state ────────────────────────────────────────────────
    property string currentTemp: "--"
    property string feelsLike:   "--"
    property string currentDesc: "Loading…"
    property string currentIcon: "󰔏"
    property string humidity:    "--"
    property string windspeed:   "--"
    property string location:    ""
    property var    forecast:    []

    // ── Obsidian todos ───────────────────────────────────────────────
    property var todos: []

    readonly property string vaultName: "My-Vault"
    readonly property string dashFile:  "90-meta/home.md"

    function weatherIcon(code) {
        var c = parseInt(code)
        if (c === 113) return "󰖙"
        if (c === 116) return "󰖕"
        if (c === 119 || c === 122) return "󰖐"
        if (c === 143 || c === 248 || c === 260) return "󰖑"
        if (c === 200 || c >= 386) return "󰖓"
        if (c === 176 || c === 293 || c === 263) return "󰼵"
        if (c >= 179 && c <= 230) return "󰖘"
        if (c >= 281 && c <= 377) return (c >= 323 && c <= 377) ? "󰖘" : "󰖗"
        return "󰖐"
    }

    Process {
        id: proc
        command: ["bash", "-c", "curl -sf --max-time 8 'https://wttr.in/?format=j1' 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    var cur  = data.current_condition[0]
                    currentTemp = cur.temp_C
                    feelsLike   = cur.FeelsLikeC
                    currentDesc = cur.weatherDesc[0].value
                    currentIcon = weatherIcon(cur.weatherCode)
                    humidity    = cur.humidity
                    windspeed   = cur.windspeedKmph
                    var area = data.nearest_area && data.nearest_area[0]
                    location = area ? area.areaName[0].value : ""
                    var fc = []
                    for (var i = 0; i < Math.min(4, data.weather.length); i++) {
                        var day = data.weather[i]
                        fc.push({
                            date: day.date, max: day.maxtempC, min: day.mintempC,
                            icon: weatherIcon(day.hourly[4].weatherCode)
                        })
                    }
                    forecast = fc
                } catch (e) { currentDesc = "Unavailable" }
            }
        }
    }

    Process {
        id: todoProc
        command: ["python3",
            Quickshell.shellDir + "/scripts/obsidian-todos.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { todos = JSON.parse(text) }
                catch (e) { todos = [] }
            }
        }
    }

    // Opens Obsidian straight to the dashboard note.
    Process {
        id: openProc
        command: ["xdg-open",
            "obsidian://open?vault=" + encodeURIComponent(vaultName) +
            "&file=" + encodeURIComponent(dashFile)]
    }

    // ── Card chrome ──────────────────────────────────────────────────
    Rectangle {
        id: card
        anchors.fill: parent
        implicitHeight: main.implicitHeight + 36
        radius: 20
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0x3b/255, 0x42/255, 0x52/255, 0.97) }
            GradientStop { position: 1.0; color: Qt.rgba(0x2e/255, 0x34/255, 0x40/255, 0.98) }
        }
        border.width: 1
        border.color: Qt.rgba(0x4c/255, 0x56/255, 0x6a/255, 0.45)

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.5)
            shadowVerticalOffset: 8
            shadowBlur: 1.0
            autoPaddingEnabled: true
        }

        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right
                      topMargin: 1; leftMargin: 20; rightMargin: 20 }
            height: 1
            color: Qt.rgba(0xec/255, 0xef/255, 0xf4/255, 0.08)
        }

        ColumnLayout {
            id: main
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 18 }
            spacing: 16

            // ── Header: greeting + date, big clock ────────────────────
            RowLayout {
                Layout.fillWidth: true

                ColumnLayout {
                    spacing: 2
                    Text {
                        text: greeting
                        font.pixelSize: 16; font.weight: Font.DemiBold
                        font.family: "JetBrainsMono Nerd Font"
                        color: C.accent
                    }
                    Text {
                        text: Qt.formatDateTime(clock.date, "dddd, dd MMMM yyyy")
                        font.pixelSize: 11
                        font.family: "JetBrainsMono Nerd Font"
                        color: C.fg1
                    }
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: Qt.formatDateTime(clock.date, "HH:mm")
                    font.pixelSize: 34; font.weight: Font.Bold
                    font.family: "JetBrainsMono Nerd Font"
                    color: C.fg0
                }
            }

            Rectangle {
                Layout.fillWidth: true; height: 1
                color: Qt.rgba(0x4c/255, 0x56/255, 0x6a/255, 0.35)
            }

            // ── Two panes: weather station | calendar ─────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 18

                // ░░ Weather station ░░
                ColumnLayout {
                    Layout.preferredWidth: 266
                    Layout.alignment: Qt.AlignTop
                    spacing: 14

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14
                        Text {
                            text: currentIcon
                            font.pixelSize: 52
                            font.family: "JetBrainsMono Nerd Font"
                            color: C.teal
                        }
                        ColumnLayout {
                            spacing: 0
                            RowLayout {
                                spacing: 2
                                Text {
                                    text: currentTemp
                                    font.pixelSize: 34; font.weight: Font.Bold
                                    font.family: "JetBrainsMono Nerd Font"
                                    color: C.fg0
                                }
                                Text {
                                    text: "°C"
                                    font.pixelSize: 15
                                    font.family: "JetBrainsMono Nerd Font"
                                    color: C.fg2
                                    Layout.alignment: Qt.AlignTop; Layout.topMargin: 5
                                }
                            }
                            Text {
                                text: currentDesc
                                font.pixelSize: 11
                                font.family: "JetBrainsMono Nerd Font"
                                color: C.fg2
                            }
                            Text {
                                text: location !== "" ? "󰍎  " + location : ""
                                visible: location !== ""
                                font.pixelSize: 10
                                font.family: "JetBrainsMono Nerd Font"
                                color: C.muted
                            }
                        }
                        Item { Layout.fillWidth: true }
                    }

                    // detail chips
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Repeater {
                            model: [
                                { icon: "󰖎", val: feelsLike + "°", lbl: "Feels", col: C.blue },
                                { icon: "󰖌", val: humidity + "%",  lbl: "Humid", col: C.teal },
                                { icon: "󰖝", val: windspeed,        lbl: "km/h",  col: C.accent2 }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: chipCol.implicitHeight + 14
                                radius: 12
                                color: Qt.rgba(0x43/255, 0x4c/255, 0x5e/255, 0.40)
                                ColumnLayout {
                                    id: chipCol
                                    anchors.centerIn: parent
                                    spacing: 2
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: modelData.icon
                                        font.pixelSize: 16
                                        font.family: "JetBrainsMono Nerd Font"
                                        color: modelData.col
                                    }
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: modelData.val
                                        font.pixelSize: 12; font.weight: Font.DemiBold
                                        font.family: "JetBrainsMono Nerd Font"
                                        color: C.fg0
                                    }
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: modelData.lbl
                                        font.pixelSize: 8
                                        font.family: "JetBrainsMono Nerd Font"
                                        color: C.muted
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        text: "FORECAST"
                        font.pixelSize: 9; font.weight: Font.Bold
                        font.family: "JetBrainsMono Nerd Font"
                        color: C.muted
                        Layout.topMargin: 2
                    }

                    // forecast rows
                    Repeater {
                        model: forecast
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 10
                            Text {
                                text: Qt.formatDateTime(new Date(modelData.date), "ddd")
                                font.pixelSize: 11; font.weight: Font.Medium
                                font.family: "JetBrainsMono Nerd Font"
                                color: C.fg1
                                Layout.preferredWidth: 34
                            }
                            Text {
                                text: modelData.icon
                                font.pixelSize: 17
                                font.family: "JetBrainsMono Nerd Font"
                                color: C.teal
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: modelData.max + "°"
                                font.pixelSize: 11; font.weight: Font.DemiBold
                                font.family: "JetBrainsMono Nerd Font"
                                color: C.fg0
                            }
                            Text {
                                text: modelData.min + "°"
                                font.pixelSize: 11
                                font.family: "JetBrainsMono Nerd Font"
                                color: C.fg2
                                Layout.preferredWidth: 26
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }
                }

                // vertical divider
                Rectangle {
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    color: Qt.rgba(0x4c/255, 0x56/255, 0x6a/255, 0.30)
                }

                // ░░ Calendar ░░
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: 10
                    readonly property real cellW: width / 7

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: monthNames[viewMonth] + " " + viewYear
                            font.pixelSize: 14; font.weight: Font.DemiBold
                            font.family: "JetBrainsMono Nerd Font"
                            color: C.fg0
                        }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            width: 24; height: 24; radius: 12
                            color: prevHover.containsMouse ? Qt.rgba(0x88/255,0xc0/255,0xd0/255,0.18) : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Text { anchors.centerIn: parent; text: "󰅁"; font.pixelSize: 13
                                   font.family: "JetBrainsMono Nerd Font"; color: C.accent }
                            MouseArea {
                                id: prevHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { viewMonth--; if (viewMonth < 0) { viewMonth = 11; viewYear-- } }
                            }
                        }
                        Rectangle {
                            width: 24; height: 24; radius: 12
                            color: nextHover.containsMouse ? Qt.rgba(0x88/255,0xc0/255,0xd0/255,0.18) : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Text { anchors.centerIn: parent; text: "󰅂"; font.pixelSize: 13
                                   font.family: "JetBrainsMono Nerd Font"; color: C.accent }
                            MouseArea {
                                id: nextHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { viewMonth++; if (viewMonth > 11) { viewMonth = 0; viewYear++ } }
                            }
                        }
                    }

                    Row {
                        Repeater {
                            model: dayNames
                            Text {
                                width: parent.parent.cellW
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData
                                font.pixelSize: 10; font.weight: Font.DemiBold
                                font.family: "JetBrainsMono Nerd Font"
                                color: index >= 5 ? C.red : C.muted
                            }
                        }
                    }

                    Grid {
                        columns: 7
                        Repeater {
                            model: firstDayOfWeek(viewYear, viewMonth) + daysInMonth(viewYear, viewMonth)
                            delegate: Item {
                                width: parent.parent.cellW
                                height: 30
                                readonly property int dayNum: index - firstDayOfWeek(viewYear, viewMonth) + 1
                                readonly property bool isBlank: index < firstDayOfWeek(viewYear, viewMonth)
                                readonly property bool isWeekend: (index % 7) >= 5
                                readonly property bool isToday:
                                    !isBlank && dayNum === clock.date.getDate() &&
                                    viewMonth === clock.date.getMonth() &&
                                    viewYear  === clock.date.getFullYear()

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 27; height: 27; radius: 13.5
                                    color: C.accent; visible: isToday; opacity: 0.45
                                    layer.enabled: isToday
                                    layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 26; autoPaddingEnabled: true }
                                }
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 27; height: 27; radius: 13.5
                                    color: isToday ? C.accent
                                         : dayHover.containsMouse && !isBlank ? Qt.rgba(0x4c/255,0x56/255,0x6a/255,0.45)
                                         : "transparent"
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    Text {
                                        anchors.centerIn: parent
                                        text: isBlank ? "" : dayNum
                                        font.pixelSize: 12
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.weight: isToday ? Font.Bold : Font.Normal
                                        color: isToday ? C.bg0
                                             : isWeekend ? Qt.rgba(0xbf/255,0x61/255,0x6a/255,0.85)
                                             : C.fg1
                                    }
                                    MouseArea {
                                        id: dayHover; anchors.fill: parent
                                        hoverEnabled: !isBlank
                                        cursorShape: isBlank ? Qt.ArrowCursor : Qt.PointingHandCursor
                                    }
                                }
                            }
                        }
                    }
                }

                // vertical divider
                Rectangle {
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    color: Qt.rgba(0x4c/255, 0x56/255, 0x6a/255, 0.30)
                }

                // ░░ Power ░░
                ColumnLayout {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 12

                    Text {
                        text: "POWER"
                        Layout.alignment: Qt.AlignHCenter
                        font.pixelSize: 9; font.weight: Font.Bold
                        font.family: "JetBrainsMono Nerd Font"
                        color: C.muted
                    }

                    PowerActions {
                        vertical: true
                        Layout.alignment: Qt.AlignHCenter
                        onRequestClose: root.requestClose()
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; height: 1
                color: Qt.rgba(0x4c/255, 0x56/255, 0x6a/255, 0.35)
            }

            // ── Tasks · due soonest ───────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "TASKS · DUE SOONEST"
                        font.pixelSize: 9; font.weight: Font.Bold
                        font.family: "JetBrainsMono Nerd Font"
                        color: C.muted
                    }
                    Item { Layout.fillWidth: true }

                    // Open Obsidian → dashboard note
                    Rectangle {
                        implicitWidth: openRow.implicitWidth + 20
                        implicitHeight: 26
                        radius: 13
                        color: openHover.containsMouse
                             ? Qt.rgba(0x88/255, 0xc0/255, 0xd0/255, 0.22)
                             : Qt.rgba(0x43/255, 0x4c/255, 0x5e/255, 0.40)
                        Behavior on color { ColorAnimation { duration: 120 } }
                        RowLayout {
                            id: openRow
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                text: "󰠮"
                                font.pixelSize: 13
                                font.family: "JetBrainsMono Nerd Font"
                                color: C.accent
                            }
                            Text {
                                text: "Open in Obsidian"
                                font.pixelSize: 10; font.weight: Font.DemiBold
                                font.family: "JetBrainsMono Nerd Font"
                                color: C.fg1
                            }
                        }
                        MouseArea {
                            id: openHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                openProc.running = true
                                root.requestClose()
                            }
                        }
                    }
                }

                Text {
                    visible: todos.length === 0
                    text: "󰄬  All clear — nothing due."
                    font.pixelSize: 11
                    font.family: "JetBrainsMono Nerd Font"
                    color: C.fg2
                }

                Repeater {
                    model: todos
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 10

                        // due chip
                        Rectangle {
                            implicitWidth: dueText.implicitWidth + 16
                            implicitHeight: 20
                            radius: 10
                            color: modelData.overdue
                                 ? Qt.rgba(0xbf/255, 0x61/255, 0x6a/255, 0.22)
                                 : Qt.rgba(0x88/255, 0xc0/255, 0xd0/255, 0.18)
                            Text {
                                id: dueText
                                anchors.centerIn: parent
                                text: modelData.rel
                                font.pixelSize: 9; font.weight: Font.DemiBold
                                font.family: "JetBrainsMono Nerd Font"
                                color: modelData.overdue ? C.red : C.teal
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: modelData.text
                            elide: Text.ElideRight
                            font.pixelSize: 12
                            font.family: "JetBrainsMono Nerd Font"
                            color: C.fg0
                        }
                    }
                }
            }
        }
    }
}
