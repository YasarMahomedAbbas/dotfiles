import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris

Item {
    implicitWidth: visible ? row.implicitWidth : 0
    implicitHeight: 34

    // Pick the actively playing player, or the first one available
    readonly property MprisPlayer player: {
        for (var i = 0; i < Mpris.players.count; i++) {
            var p = Mpris.players.get(i)
            if (p.isPlaying) return p
        }
        return Mpris.players.count > 0 ? Mpris.players.get(0) : null
    }

    visible: player !== null && (player.trackTitle !== "" || player.isPlaying)

    RowLayout {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        // Play / Pause
        Text {
            text: (player && player.isPlaying) ? "󰏤" : "󰐊"
            font.pixelSize: 15
            font.family: "JetBrainsMono Nerd Font"
            color: Colors.green

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (player) player.togglePlaying()
            }
        }

        // Next
        Text {
            text: "󰒭"
            font.pixelSize: 14
            font.family: "JetBrainsMono Nerd Font"
            color: Colors.fg2
            visible: player && player.canGoNext

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (player) player.next()
            }
        }

        // Track info
        Text {
            id: trackLabel
            property string title:  player ? player.trackTitle  : ""
            property string artist: player ? player.trackArtist : ""
            text: artist.length > 0 ? artist + " – " + title : title
            elide: Text.ElideRight
            maximumLineCount: 1
            Layout.maximumWidth: 200
            font.pixelSize: 11
            font.family: "JetBrainsMono Nerd Font"
            font.weight: Font.Medium
            color: Colors.fg1
        }
    }
}
