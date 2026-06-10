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

# zoxide — smarter cd (only if installed)
if type -q zoxide
    zoxide init fish | source
end

# fzf — Nord color scheme
set -gx FZF_DEFAULT_OPTS "
--color=bg+:#3b4252,bg:#2e3440,spinner:#81a1c1,hl:#616e88
--color=fg:#d8dee9,header:#616e88,info:#81a1c1,pointer:#81a1c1
--color=marker:#a3be8c,fg+:#eceff4,prompt:#81a1c1,hl+:#88c0d0
--color=border:#434c5e"
