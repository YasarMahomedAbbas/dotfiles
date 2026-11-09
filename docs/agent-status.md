# agent-status (replaced)

The Claude status machinery this page described — `claude-hook-state`, the
`@claude_state` / `@claude_pane` / `@claude_detail` / `@claude_ts` tmux options, the
window-name marks written by `pipeline-status`, and the agent sidebar — has been replaced
by the **agent board**: one state file per Claude process, read by the `board` CLI.

See **[agent-board.md](agent-board.md)**; §5 "Terminal side" covers the sesh picker, its
preview, the tmux pill and roster, the Stream Deck, and the parts of the old system that
remain (`ticket-context`, `pipeline-status`, `ticket-pill`, `ticket-window`).
