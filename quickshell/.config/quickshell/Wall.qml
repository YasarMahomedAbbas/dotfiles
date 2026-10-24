import QtQuick
import QtQuick.Layouts

// The wall (SUPER+G; replaces the roster): every session at a glance. A card per
// pipeline in two columns, plus a card for a plain session while it needs you or
// finished unseen; every other plain session is a one-liner under the cards.
//   h/l ←/→ move · j/k ↓/↑ a row · ⏎ jump · 1-9 answer · f focus view
//   s s stack · v design · y copy link · o open stack · t ticket · / filter · ? keys · esc
Item {
    id: root

    property bool   active: false
    property string focusKey: ""         // session to select on open
    property int    maxHeight: 900

    signal requestClose()
    signal openFocus(string key)
    signal openKeys()

    readonly property string mono: "JetBrainsMono Nerd Font"

    property int    sel: 0
    property string filter: ""
    property bool   filtering: false

    readonly property var live: Board.sessions.filter(function (s) { return !s.stale && Board.matches(s, root.filter) })
    readonly property var cards: live.filter(function (s) { return Board.wantsCard(s) })
    readonly property var liners: live.filter(function (s) { return !Board.wantsCard(s) })
    readonly property var order: cards.concat(liners)
    readonly property var cur: order.length ? order[Math.max(0, Math.min(sel, order.length - 1))] : null

    implicitHeight: Math.min(col.implicitHeight + 40, maxHeight)

    onActiveChanged: {
        if (!active) return
        sel = 0; filter = ""; filtering = false
        acts.confirmKey = ""; acts.flash = ""
        for (var i = 0; i < order.length; i++) if (order[i].key === focusKey) sel = i
        Board.refresh()
        Qt.callLater(function () { keys.forceActiveFocus() })
        Qt.callLater(ensureVisible)
    }
    onSelChanged: { acts.moved(cur); Qt.callLater(ensureVisible) }

    function move(d) {
        if (!order.length) return
        sel = Math.max(0, Math.min(order.length - 1, sel + d))
    }
    // j/k: a row of cards is two wide; among the one-liners a row is one
    function row(d) {
        if (sel < cards.length && sel + d * 2 < cards.length && sel + d * 2 >= 0) move(d * 2)
        else move(d)
    }
    function ensureVisible() {
        var it = sel < cards.length ? cardRep.itemAt(sel) : null
        if (!it) return
        var y = it.y
        if (y < flick.contentY) flick.contentY = y
        else if (y + it.height > flick.contentY + flick.height) flick.contentY = y + it.height - flick.height
    }

    BoardActions {
        id: acts
        onRequestClose: root.requestClose()
    }

    // Key handler. Not `focus: true` up front: it takes focus when the popup
    // opens, so it never holds the bar's focus while hidden.
    Item {
        id: keys
        Keys.onPressed: function (e) {
            var t = e.text, s = root.cur
            if (e.key === Qt.Key_Escape) {
                if (acts.confirmKey) acts.confirmKey = ""
                else if (root.filter) root.filter = ""
                else root.requestClose()
            }
            else if (t === "l" || e.key === Qt.Key_Right || e.key === Qt.Key_Tab) root.move(1)
            else if (t === "h" || e.key === Qt.Key_Left || e.key === Qt.Key_Backtab) root.move(-1)
            else if (t === "j" || e.key === Qt.Key_Down) root.row(1)
            else if (t === "k" || e.key === Qt.Key_Up) root.row(-1)
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) acts.jump(s)
            else if (t === "f") root.openFocus(s ? s.key : "")
            else if (t === "/") { root.filtering = true; filterInput.forceActiveFocus() }
            else if (t === "?") root.openKeys()
            else if (!acts.key(t, s)) return
            e.accepted = true
        }
    }

    Glass { anchors.fill: parent; radius: 18 }

    ColumnLayout {
        id: col
        anchors { fill: parent; margins: 20 }
        spacing: 14

        // ── header: title, counts, keys ─────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 4; Layout.rightMargin: 4
            spacing: 14

            Text {
                text: "Where we're at"
                color: Colors.fg0
                font.family: root.mono; font.pixelSize: 17
            }
            CountChip { visible: Board.needsYou > 0; text: "● " + Board.needsYou + " needs you"; c: Colors.attn; tint: true }
            CountChip { visible: Board.working > 0; text: "▶ " + Board.working; c: Colors.fg0 }
            CountChip { visible: Board.background > 0; text: "◐ " + Board.background; c: Colors.blue }
            CountChip { visible: Board.unseen > 0; text: "✓ " + Board.unseen + " new"; c: Colors.green }

            // filter field: `/` focuses it, ⏎/↓ returns to the cards, esc clears
            Rectangle {
                visible: root.filtering || root.filter !== ""
                Layout.fillWidth: true
                implicitHeight: 24
                radius: 8
                color: Qt.rgba(0, 0, 0, 0.3)
                border.width: 1
                border.color: root.filtering ? Colors.alpha(Colors.attn, 0.5) : Qt.rgba(1, 1, 1, 0.12)
                TextInput {
                    id: filterInput
                    anchors { left: parent.left; leftMargin: 10; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    text: root.filter
                    onTextEdited: { root.filter = text; root.sel = 0 }
                    color: Colors.fg0
                    font.family: root.mono; font.pixelSize: 12
                    Keys.onPressed: function (e) {
                        if (e.key === Qt.Key_Escape) { root.filter = ""; root.filtering = false; keys.forceActiveFocus(); e.accepted = true }
                        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Down) {
                            root.filtering = false; keys.forceActiveFocus(); e.accepted = true
                        }
                    }
                }
            }
            Item { Layout.fillWidth: true; visible: !(root.filtering || root.filter !== "") }

            Text {
                text: acts.flash || (acts.confirmKey ? "s again to switch the stack · esc cancels"
                     : "SUPER+G · h/j/k/l · ⏎ jump · 1-9 answer · f focus · s v y o t / · esc")
                color: acts.flash ? Colors.attn : acts.confirmKey ? Colors.yellow : Colors.fg2
                font.family: root.mono; font.pixelSize: 11
            }
        }

        // the stack switch a first `s` would make
        Text {
            visible: acts.confirmKey !== ""
            Layout.fillWidth: true
            Layout.leftMargin: 4
            text: acts.confirmText
            color: Colors.yellow
            wrapMode: Text.Wrap
            font.family: root.mono; font.pixelSize: 11
        }

        // ── cards ───────────────────────────────────────────────────────
        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: grid.implicitHeight
            contentHeight: grid.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            GridLayout {
                id: grid
                width: flick.width
                columns: 2
                columnSpacing: 12
                rowSpacing: 12

                Repeater {
                    id: cardRep
                    model: root.cards
                    delegate: WallCard {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignTop
                        session: modelData
                        selected: index === root.sel
                        onClicked: root.sel = index
                        onActivated: acts.jump(modelData)
                        onAnswer: function (n) { acts.answer(modelData, n) }
                    }
                }
            }
        }

        // ── the plain sessions, one line each ───────────────────────────
        Flow {
            visible: root.liners.length > 0
            Layout.fillWidth: true
            Layout.leftMargin: 4
            spacing: 18
            Text {
                text: root.cards.length ? "also open:" : "open:"
                color: Colors.fg2
                font.family: root.mono; font.pixelSize: 12
            }
            Repeater {
                model: root.liners
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    readonly property bool isSel: root.sel === root.cards.length + index
                    readonly property bool quiet: Board.kind(modelData) === "idle"
                    implicitWidth: lr.implicitWidth + 12
                    implicitHeight: lr.implicitHeight + 6
                    radius: 6
                    color: isSel ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
                    border.width: isSel ? 1 : 0
                    border.color: Colors.attn
                    Row {
                        id: lr
                        anchors.centerIn: parent
                        spacing: 8
                        Text {
                            text: Board.glyph(modelData) + " " + Board.title(modelData)
                            color: quiet ? Colors.fg2 : Board.kindColor(modelData)
                            font.family: root.mono; font.pixelSize: 12
                        }
                        Text {
                            text: Board.oneLiner(modelData)
                            color: Colors.fg2
                            font.family: root.mono; font.pixelSize: 12
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.sel = root.cards.length + index
                        onDoubleClicked: acts.jump(modelData)
                    }
                }
            }
        }

        Text {
            visible: root.order.length === 0
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: !Board.available ? "`" + Board.boardCmd + "` isn't available yet"
                : root.filter ? "nothing matches “" + root.filter + "”" : "no Claude sessions"
            color: Colors.fg2
            font.family: root.mono; font.pixelSize: 12
        }
    }
}
