function wt-session --description "Open or create a tmuxifier session for an existing worktree path"
    set wt_path (realpath $argv[1])

    if test -z "$wt_path"
        echo "Usage: wt-session <worktree-path>"
        return 1
    end

    set session_name (basename $wt_path)

    # If session already exists, just switch to it
    if tmux has-session -t $session_name 2>/dev/null
        tmux switch-client -t $session_name
        return 0
    end

    set layout_file "$HOME/.tmuxifier/layouts/$session_name.session.sh"

    printf '#!/usr/bin/env bash

REPO="%s"

session_root "$REPO"

if initialize_session "%s"; then

  # Window 1: Editor (75/25 split)
  window_root "$REPO"
  new_window "editor"
  split_h 25
  select_pane 1

  # Window 2: Git
  window_root "$REPO"
  new_window "git"
  run_cmd "lazygit"

  # Window 3: Dev
  window_root "$REPO"
  new_window "dev"

  # Window 4: Files
  window_root "$REPO"
  new_window "files"
  run_cmd "yazi"

  select_window 1

fi

finalize_and_go_to_session
' $wt_path $session_name >$layout_file

    tmuxifier load-session $session_name
end
