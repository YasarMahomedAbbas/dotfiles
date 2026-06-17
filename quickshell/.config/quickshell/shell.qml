import Quickshell
import Quickshell.Hyprland

ShellRoot {
    Bar { id: bar }

    // SUPER+W registered in hyprland.conf as:
    // bind = $mainMod, W, global, quickshell:togglebar
    GlobalShortcut {
        name: "togglebar"
        description: "Toggle bar visibility"
        onPressed: bar.visible = !bar.visible
    }

    // SUPER+SHIFT+W registered in hyprland.conf as:
    // bind = $mainMod SHIFT, W, global, quickshell:toggledashboard
    GlobalShortcut {
        name: "toggledashboard"
        description: "Toggle dashboard popup"
        onPressed: bar.toggleDashboard()
    }
}
