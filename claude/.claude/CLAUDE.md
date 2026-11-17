# Global instructions

## Tooling
- Prefer `rg` (ripgrep) over `grep` and `fd` over `find` in all shell commands.
## My assistant (todo list, reminders)
- My todo list, reminders, agenda and the rest of my personal assistant are reached with the `assistant` skill (`~/.claude/skills/assistant/pa`, e.g. `pa list`, `pa add "17:30 call mum"`): use it whenever I ask about my todos, reminders or what's on my list.

## Notes / vault
- My Obsidian vault is at `~/projects/vault/My-Vault`. When I ask you to "make a note" or reference "the vault", this is it. Idea/project notes live under `25-ideas/<project>/`. Notes use frontmatter: `type: note`, `status: active`, `domain: personal`, `created: <YYYY-MM-DD>`, `tags:`. Link between notes with `[[wikilinks]]`.
