#!/bin/bash
# Claude Code statusline — mirrors Starship/robbyrussell prompt style
# Sections: cwd | git branch | model | context remaining

input=$(cat)

# ---- colors (Starship/robbyrussell palette) ----
RST='\033[0m'
CYAN='\033[38;5;75m'      # directory — robbyrussell cyan
GREEN='\033[38;5;114m'    # git branch — robbyrussell green
YELLOW='\033[38;5;228m'   # git branch parens
PURPLE='\033[38;5;183m'   # model name
CTX_OK='\033[38;5;114m'   # context green (>40%)
CTX_WARN='\033[38;5;215m' # context peach (20-40%)
CTX_CRIT='\033[38;5;203m' # context red (<=20%)
DIM='\033[38;5;245m'      # dim separators
BLUE='\033[38;5;111m'     # cost/usage
RL_OK='\033[38;5;114m'    # rate limit green (<60%)
RL_WARN='\033[38;5;215m'  # rate limit peach (60-80%)
RL_CRIT='\033[38;5;203m'  # rate limit red (>80%)

# Format large numbers: 1234 -> 1.2k, 12345 -> 12.3k
fmt_tokens() {
  local n="$1"
  if [ -z "$n" ] || ! [[ "$n" =~ ^[0-9]+$ ]]; then echo "0"; return; fi
  if [ "$n" -ge 1000000 ]; then
    printf '%.1fM' "$(echo "scale=1; $n / 1000000" | bc)"
  elif [ "$n" -ge 1000 ]; then
    printf '%.1fk' "$(echo "scale=1; $n / 1000" | bc)"
  else
    echo "$n"
  fi
}

# Pick rate limit color based on used percentage
rl_color() {
  local pct="$1"
  if [ -z "$pct" ]; then echo "$DIM"; return; fi
  local p=$(printf '%.0f' "$pct" 2>/dev/null)
  if [ "$p" -gt 80 ] 2>/dev/null; then echo "$RL_CRIT"
  elif [ "$p" -gt 60 ] 2>/dev/null; then echo "$RL_WARN"
  else echo "$RL_OK"
  fi
}

# ---- parse JSON with jq ----
model_name=$(echo "$input" | jq -r '.model.display_name // "Claude"' 2>/dev/null)
effort=$(echo "$input" | jq -r '.effort.level // empty' 2>/dev/null)
cwd=$(echo "$input" | jq -r '.workspace.current_dir // ""' 2>/dev/null)
remaining_pct=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty' 2>/dev/null)

# Rate limits
rl5_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null)
rl5_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty' 2>/dev/null)
rl7_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null)

# Cost and tokens
cost_usd=$(echo "$input" | jq -r '.cost.total_cost_usd // empty' 2>/dev/null)
total_in=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty' 2>/dev/null)
total_out=$(echo "$input" | jq -r '.context_window.total_output_tokens // empty' 2>/dev/null)

# Shorten home directory to ~
home="$HOME"
if [ -n "$cwd" ]; then
  display_cwd="${cwd/#$home/~}"
else
  display_cwd="$(pwd | sed "s|^$HOME|~|")"
fi

# ---- git branch (skip optional locks) ----
git_branch=""
if GIT_OPTIONAL_LOCKS=0 git rev-parse --git-dir >/dev/null 2>&1; then
  git_branch=$(GIT_OPTIONAL_LOCKS=0 git branch --show-current 2>/dev/null)
  [ -z "$git_branch" ] && git_branch=$(GIT_OPTIONAL_LOCKS=0 git rev-parse --short HEAD 2>/dev/null)
fi

# ---- context color ----
ctx_color="$CTX_OK"
ctx_label=""
if [ -n "$remaining_pct" ]; then
  pct_int=$(printf '%.0f' "$remaining_pct" 2>/dev/null || echo "$remaining_pct")
  if [ "$pct_int" -le 20 ] 2>/dev/null; then
    ctx_color="$CTX_CRIT"
  elif [ "$pct_int" -le 40 ] 2>/dev/null; then
    ctx_color="$CTX_WARN"
  fi
  ctx_label="${pct_int}% ctx"
fi

# ---- render ----
# Line 1: robbyrussell-style  cwd  git:(branch)
printf '\033[0m'

line1=""
line1="${line1}$(printf '\033[0m')$(printf '%b' "${CYAN}")${display_cwd}$(printf '%b' "${RST}")"

if [ -n "$git_branch" ]; then
  line1="${line1}  $(printf '%b' "${YELLOW}") $(printf '%b' "${GREEN}")${git_branch}$(printf '%b' "${RST}")"
fi

printf '%b\n' "$line1"

# Line 2: model (effort)  |  context remaining
line2=""
line2="${line2}$(printf '%b' "${PURPLE}")${model_name}$(printf '%b' "${RST}")"

if [ -n "$effort" ]; then
  line2="${line2} $(printf '%b' "${DIM}")(${effort})$(printf '%b' "${RST}")"
fi

if [ -n "$ctx_label" ]; then
  line2="${line2}  $(printf '%b' "${DIM}")|$(printf '%b' "${RST}")  $(printf '%b' "${ctx_color}")${ctx_label}$(printf '%b' "${RST}")"
fi

printf '%b\n' "$line2"

# Line 3: rate limits  |  cost  |  tokens
line3=""

# Rate limits
if [ -n "$rl5_pct" ]; then
  rl5_fmt=$(printf '%.0f' "$rl5_pct" 2>/dev/null)
  rl5_c=$(rl_color "$rl5_pct")
  line3="$(printf '%b' "$rl5_c")5h: ${rl5_fmt}%$(printf '%b' "${RST}")"
  if [ -n "$rl5_reset" ]; then
    if date -r 0 +%s >/dev/null 2>&1; then
      reset_time=$(date -r "$rl5_reset" +"%H:%M" 2>/dev/null)
    else
      reset_time=$(date -d "@$rl5_reset" +"%H:%M" 2>/dev/null)
    fi
    [ -n "$reset_time" ] && line3="${line3}$(printf '%b' "${DIM}") (resets ${reset_time})$(printf '%b' "${RST}")"
  fi
fi

if [ -n "$rl7_pct" ]; then
  rl7_fmt=$(printf '%.0f' "$rl7_pct" 2>/dev/null)
  rl7_c=$(rl_color "$rl7_pct")
  [ -n "$line3" ] && line3="${line3}  $(printf '%b' "${DIM}")|$(printf '%b' "${RST}")  "
  line3="${line3}$(printf '%b' "$rl7_c")7d: ${rl7_fmt}%$(printf '%b' "${RST}")"
fi

# Cost
if [ -n "$cost_usd" ]; then
  cost_fmt=$(printf '$%.2f' "$cost_usd" 2>/dev/null)
  [ -n "$line3" ] && line3="${line3}  $(printf '%b' "${DIM}")|$(printf '%b' "${RST}")  "
  line3="${line3}$(printf '%b' "${BLUE}")${cost_fmt}$(printf '%b' "${RST}")"
fi

# Tokens
if [ -n "$total_in" ] || [ -n "$total_out" ]; then
  tok_in=$(fmt_tokens "$total_in")
  tok_out=$(fmt_tokens "$total_out")
  [ -n "$line3" ] && line3="${line3}  $(printf '%b' "${DIM}")|$(printf '%b' "${RST}")  "
  line3="${line3}$(printf '%b' "${BLUE}")${tok_in} in / ${tok_out} out$(printf '%b' "${RST}")"
fi

if [ -n "$line3" ]; then
  printf '%b\n' "$line3"
fi
