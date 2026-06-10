function wt-session --description "Open or create a tmux dev session for a worktree/dir (no layout files)"
    if test -z "$argv[1]"
        echo "Usage: wt-session <path>"
        return 1
    end

    set wt_path (realpath $argv[1])
    # tmux treats "." specially in target names — sanitise the session name
    set session (string replace -a '.' '_' (basename $wt_path))

    # Already running → just go to it
    if tmux has-session -t $session 2>/dev/null
        if set -q TMUX
            tmux switch-client -t $session
        else
            tmux attach -t $session
        end
        return 0
    end

    # Create it, then let the shared layout script build the windows + nvim
    tmux new-session -d -s $session -c $wt_path
    tmux send-keys -t $session:1 "tmux-dev-layout $wt_path" Enter

    if set -q TMUX
        tmux switch-client -t $session
    else
        tmux attach -t $session
    end
end
