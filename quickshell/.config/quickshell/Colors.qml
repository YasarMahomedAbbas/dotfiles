pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Theme palette, rendered by `theme-switch` into ~/.config/theme/quickshell-colors.json
// and watched live — switching themes recolors the bar instantly, no restart.
// The defaults below (dark-nord) are only a fallback for when that file is
// missing or malformed, so the bar always renders something sane.
Singleton {
    id: root

    property color bg0: "#0a0b0e"
    property color bg1: "#1b1f27"
    property color bg2: "#29303c"
    property color bg3: "#3a4150"

    property color fg0: "#eceff4"
    property color fg1: "#d8dee9"
    property color fg2: "#60697d"

    property color accent:  "#88c0d0"
    property color accent2: "#5e81ac"
    property color blue:    "#81a1c1"
    property color teal:    "#8fbcbb"
    property color red:     "#bf616a"
    property color orange:  "#d08770"
    property color yellow:  "#ebcb8b"
    property color green:   "#a3be8c"
    property color purple:  "#b48ead"
    property color muted:   "#3b4252"

    function apply(data) {
        for (var k in data)
            if (root.hasOwnProperty(k))
                root[k] = data[k];
    }

    function load() {
        try {
            var t = file.text();
            if (t && t.length)
                root.apply(JSON.parse(t));
        } catch (e) {
            console.warn("Colors: could not load theme file:", e);
        }
    }

    Component.onCompleted: root.load()

    FileView {
        id: file
        path: Quickshell.env("HOME") + "/.config/theme/quickshell-colors.json"
        watchChanges: true
        onFileChanged: { reload(); root.load(); }
        onLoaded: root.load()
    }
}
