# dotfiles

GNU Stow packages (one top-level dir per package, mirroring `$HOME`; `.stowrc` pins the target to `~`).
See README.md for the package list and install steps.

## Every feature ships: branch → commit → push → PR → merge

When a feature or fix is finished, take it all the way to `main`. Don't leave work uncommitted or on an unmerged branch.

1. **Work on a feature branch, never commit straight to `main`.** Name it `feat/<topic>` or `fix/<topic>`.
2. **Commit in conventional-commit style, matching the history:** `feat(<pkg>): …`, `fix(<pkg>): …`, `docs: …`.
   The scope is the package or tool (`herdr`, `herd`, `streamdeck`, `claude`, `wt-dev`, …). Lowercase, present tense, says what the user gets.
   Add a ticket ref in parentheses when there is one, e.g. `(personal-assistant#352)`.
3. **Push** with `git push -u origin <branch>`.
4. **Open a PR** with `gh pr create` (short title in the same style, a body saying what changed and why).
5. **Merge it:** `gh pr merge --merge --delete-branch`.
6. **Pull `main` locally** in the main checkout (`git -C ~/projects/personal/dotfiles pull --ff-only` when it's on `main`), so the stowed symlinks serve the merged files.
   If the main checkout is on someone else's branch, leave it and say so instead.

## Several sessions share this checkout

Other Claude sessions often work in `~/projects/personal/dotfiles` at the same time.

- Do feature work in a **git worktree** off `origin/main`:
  `git fetch origin && git worktree add -b feat/<topic> ../dotfiles-wt-<topic> origin/main`.
  Remove it after the merge: `git worktree remove ../dotfiles-wt-<topic>`.
- In the main checkout, **never switch branches, stash, reset or clean**: another session may be using it,
  and the stowed symlinks in `~` point at it, so a branch switch changes the live config.
- Only stage your own files (`git add <paths>`, not `git add -A`). Leave other people's uncommitted changes alone.

## Stow gotchas

- Symlinks point into the main checkout, so **stow from there, never from a worktree**, and only after the change is on its branch there (normally after merging and pulling `main`).
- **New files need `stow --restow <pkg>`**: stow doesn't link files that didn't exist when the package was last stowed.
- **herdr icons** aren't loaded through symlinks: run `herdr-icons` after adding or changing one.
- Quickshell needs a restart to pick up new components.
- `~/.claude/settings.json` is not managed here; `claude/.claude/CLAUDE.md` is the user's global CLAUDE.md, not this file.
- Update README.md's package list when you add a package or a notable script.
