import Quickshell
import Quickshell.Hyprland

ShellRoot {
    Bar { id: bar }

    // SUPER+W registered in hyprland.lua as:
    // bind(mainMod .. " + W", "Shell: Toggle bar", global("quickshell:togglebar"))
    GlobalShortcut {
        name: "togglebar"
        description: "Toggle bar visibility"
        onPressed: bar.visible = !bar.visible
    }

    // SUPER+SHIFT+W registered in hyprland.lua as:
    // bind(mainMod .. " + SHIFT + W", "Shell: Dashboard", global("quickshell:toggledashboard"))
    GlobalShortcut {
        name: "toggledashboard"
        description: "Toggle dashboard popup"
        onPressed: bar.toggleDashboard()
    }

    // ── Agent board (docs/agent-board.md) ───────────────────────────────

    // The one toast the board makes: a session newly needs you
    Toast {
        id: toast
        screen: bar.screen
        rightOffset: bar.agentsRight
        onOpenRoster: bar.toggleRoster()
    }

    // SUPER+G registered in hyprland.lua as:
    // bind(mainMod .. " + G", "Agents: Roster", global("quickshell:roster"))
    GlobalShortcut {
        name: "roster"
        description: "Agent board roster"
        onPressed: bar.toggleRoster()
    }

    // SUPER+SHIFT+G registered in hyprland.lua as:
    // bind(mainMod .. " + SHIFT + G", "Agents: Checklist wall", global("quickshell:wall"))
    GlobalShortcut {
        name: "wall"
        description: "Agent board checklist wall"
        onPressed: bar.toggleWall("")
    }

    // SUPER+/ registered in hyprland.lua as:
    // bind(mainMod .. " + slash", "Agents: Keys cheatsheet", global("quickshell:keys"))
    GlobalShortcut {
        name: "keys"
        description: "Keys cheatsheet"
        onPressed: bar.toggleKeys()
    }

    // SUPER+space registered in hyprland.lua next to mako's dismiss (both fire):
    // bind(mainMod .. " + space", "Notifications: Dismiss board toast", global("quickshell:dismisstoast"))
    GlobalShortcut {
        name: "dismisstoast"
        description: "Dismiss the agent board toast"
        onPressed: toast.dismiss()
    }
}
