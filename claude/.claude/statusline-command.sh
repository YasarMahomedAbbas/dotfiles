#!/usr/bin/env bash
# Claude Code statusline, Ember palette (personal-assistant's tokens):
#   ◆ model · dir · branch* · ctx ▰▰▱▱▱▱▱▱▱▱ 9% · 5h ▰▰▱▱▱ 22% ↻ 2h05m
# Context: sage under 20%, fire orange from 20%, rose from 30%; from 20% the
# readout becomes a solid pill so it can't be missed.
# Input: Claude Code statusline JSON on stdin. Deps: jq, awk.

input=$(cat)

IFS=$'\x1f' read -r model cdir ctx r5 r5reset < <(
  printf '%s' "$input" | jq -j '
    [ .model.display_name              // "?"
    , .workspace.current_dir // .cwd   // "."
    , (.context_window.used_percentage // "" | tostring)
    , (.rate_limits.five_hour.used_percentage // "" | tostring)
    , (.rate_limits.five_hour.resets_at       // "" | tostring)
    ] | join("\u001f")'
)

# --- palette (truecolor) ---------------------------------------------------
fg() { printf '\033[38;2;%sm' "$1"; }
bg() { printf '\033[48;2;%sm' "$1"; }
RESET=$'\033[0m'; BOLD=$'\033[1m'
FIRE="224;112;58"      # #e0703a accent
ROSE="255;107;133"     # #ff6b85 needs-attention
SAGE="143;199;154"     # #8fc79a fine
AMBER="229;181;103"    # #e5b567 warming
FROST="230;237;243"    # #e6edf3 strong text
MUTED="164;173;182"    # #a4adb6
FAINT="125;133;142"    # #7d858e
TRACK="57;59;62"       # #393b3e empty bar cells
ONDARK="31;12;3"       # #1f0c03 text on fire
ONROSE="42;7;16"       # #2a0710 text on rose
SEP=" $(fg "$FAINT")·${RESET} "
CAPL=$(printf '\xee\x82\xb6')   # U+E0B6 half-round cap (nerd font)
CAPR=$(printf '\xee\x82\xb4')   # U+E0B4

# context: <20 sage, <30 fire, else rose
ctxcol() { awk -v v="$1" -v a="$SAGE" -v b="$FIRE" -v c="$ROSE" 'BEGIN{print (v<20)?a:(v<30)?b:c}'; }
# rate limit: <50 sage, <80 amber, else rose
limcol() { awk -v v="$1" -v a="$SAGE" -v b="$AMBER" -v c="$ROSE" 'BEGIN{print (v<50)?a:(v<80)?b:c}'; }

# bar <pct> <cells> <rgb> -> ▰▰▰▱▱▱
bar() {
  awk -v v="$1" -v w="$2" -v on="$(fg "$3")" -v off="$(fg "$TRACK")" -v rst="$RESET" 'BEGIN{
    n=int(v/100*w+0.5); if(n>w)n=w; if(n<1&&v>0)n=1;
    s=on; for(i=0;i<n;i++) s=s "\xe2\x96\xb0";
    s=s off; for(i=n;i<w;i++) s=s "\xe2\x96\xb1";
    printf "%s%s", s, rst }'
}

# --- model -----------------------------------------------------------------
out="$(fg "$FIRE")◆${RESET} ${BOLD}$(fg "$FROST")${model}${RESET}"

# --- directory -------------------------------------------------------------
if [ -n "$cdir" ]; then
  case "$cdir" in "$HOME") dir="~" ;; *) dir="${cdir##*/}" ;; esac
  out="${out}${SEP}$(fg "$MUTED")${dir}${RESET}"
fi

# --- git branch + dirty ----------------------------------------------------
if git -C "$cdir" rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git -C "$cdir" symbolic-ref --short HEAD 2>/dev/null || git -C "$cdir" rev-parse --short HEAD 2>/dev/null)
  dirty=""
  [ -n "$(git -C "$cdir" status --porcelain 2>/dev/null | head -1)" ] && dirty="$(fg "$AMBER")*"
  [ -n "$branch" ] && out="${out}${SEP}$(fg "$FROST")${branch}${dirty}${RESET}"
fi

# --- context window --------------------------------------------------------
if [ -n "$ctx" ]; then
  pct=$(awk -v v="$ctx" 'BEGIN{printf "%.0f", v}')
  col=$(ctxcol "$ctx")
  if [ "$pct" -ge 20 ]; then
    on=$ONDARK; [ "$pct" -ge 30 ] && on=$ONROSE
    pill="$(fg "$col")${CAPL}$(bg "$col")$(fg "$on")${BOLD}ctx ${pct}%${RESET}$(fg "$col")${CAPR}${RESET}"
    out="${out}${SEP}$(bar "$ctx" 10 "$col") ${pill}"
  else
    out="${out}${SEP}$(fg "$FAINT")ctx${RESET} $(bar "$ctx" 10 "$col") $(fg "$col")${pct}%${RESET}"
  fi
fi

# --- 5-hour rate limit -----------------------------------------------------
if [ -n "$r5" ]; then
  pct=$(awk -v v="$r5" 'BEGIN{printf "%.0f", v}')
  col=$(limcol "$r5")
  out="${out}${SEP}$(fg "$FAINT")5h${RESET} $(bar "$r5" 5 "$col") $(fg "$col")${pct}%${RESET}"
  if [ -n "$r5reset" ]; then
    left=$(awk -v r="$r5reset" -v n="$(date +%s)" 'BEGIN{
      m=int((r-n)/60); if(m<0)m=0;
      if(m>=60) printf "%dh%02dm", int(m/60), m%60; else printf "%dm", m }')
    out="${out} $(fg "$FAINT")↻ ${left}${RESET}"
  fi
fi

printf '%s' "$out"
