# CachyOS ships a default fish config; only source it where it exists (not on Ubuntu/GNOME).
if test -f /usr/share/cachyos-fish-config/cachyos-config.fish
    source /usr/share/cachyos-fish-config/cachyos-config.fish
end

starship init fish | source

# tmuxifier (only if installed)
set -x TMUXIFIER_LAYOUT_PATH "$HOME/.tmuxifier/layouts"
if test -f "$HOME/.tmuxifier/init.fish"
    source "$HOME/.tmuxifier/init.fish"

    function load
        tmuxifier load-session $argv
    end
end

# opencode (only if installed)
if test -d "$HOME/.opencode/bin"
    fish_add_path "$HOME/.opencode/bin"
end
