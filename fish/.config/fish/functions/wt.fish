function wt --description "Create a git worktree as a sibling dir and open a tmux session"
    # Usage: wt [-b] <branch>
    #   -b  create a new branch from current HEAD

    set new_branch false
    set branch ""

    for arg in $argv
        switch $arg
            case -b
                set new_branch true
            case '*'
                set branch $arg
        end
    end

    if test -z "$branch"
        echo "Usage: wt [-b] <branch>"
        echo "  -b  create a new branch from current HEAD"
        return 1
    end

    set repo_root (git rev-parse --show-toplevel 2>/dev/null)
    if test $status -ne 0
        echo "Not in a git repository"
        return 1
    end

    set repo_name (basename $repo_root)
    set parent_dir (dirname $repo_root)
    set safe_branch (string replace -a '/' '-' $branch)
    set wt_path "$parent_dir/$repo_name-$safe_branch"

    if $new_branch
        git worktree add -b $branch $wt_path
    else
        git worktree add $wt_path $branch
    end

    if test $status -ne 0
        echo "Failed to create worktree at $wt_path"
        return 1
    end

    wt-session $wt_path
end
