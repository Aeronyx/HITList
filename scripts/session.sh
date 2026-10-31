#!/bin/zsh
# Start a delegated Opus 5.5 Claude Code session for one brief, in its own git worktree, on George's
# API credit.
#
# Usage: scripts/session.sh <slug> <brief-file> <effort> [model]
#   slug        worktree ../HITList-<slug> and branch <slug>, created from master if missing
#   brief-file  a file in briefs/, e.g. 14-design-system.md
#   effort      low | medium | high | xhigh | max
#   model       default claude-opus-5-5
#
# The API key is read from ~/.config/hitlist/api.env (a one-line `export ANTHROPIC_API_KEY=...`).
# Create it once with:
#   mkdir -p ~/.config/hitlist && read -s "k?Anthropic API key: " && printf 'export ANTHROPIC_API_KEY=%s\n' "$k" > ~/.config/hitlist/api.env && chmod 600 ~/.config/hitlist/api.env && unset k
# Pass --plan to use the Claude subscription instead (the key is left unset).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
usePlan=0
args=()
for a in "$@"; do [[ "$a" == "--plan" ]] && usePlan=1 || args+=("$a"); done
(( ${#args} >= 3 )) || { sed -n '2,15p' "$0"; exit 2; }
slug="${args[1]}"; brief="${args[2]}"; effort="${args[3]}"; model="${args[4]:-claude-opus-5-5}"
[[ -f "$ROOT/briefs/$brief" ]] || { echo "no such brief: briefs/$brief"; exit 2; }

if (( usePlan )); then
  unset ANTHROPIC_API_KEY
  echo "Using the Claude subscription (no API key)."
else
  [[ -f ~/.config/hitlist/api.env ]] || { echo "Missing ~/.config/hitlist/api.env; see the header of $0 for the one-time setup."; exit 2; }
  source ~/.config/hitlist/api.env
  [[ -n "${ANTHROPIC_API_KEY:-}" ]] || { echo "ANTHROPIC_API_KEY is empty in ~/.config/hitlist/api.env"; exit 2; }
  export ANTHROPIC_API_KEY
  echo "Using API credit (key ending …${ANTHROPIC_API_KEY[-4,-1]})."
fi

wt="$ROOT/../HITList-$slug"
if [[ ! -d "$wt" ]]; then
  git -C "$ROOT" worktree add "$wt" -b "$slug" master
else
  echo "Reusing worktree $wt"
fi
cd "$wt"
exec claude --model "$model" --effort "$effort" --permission-mode auto \
  "Read briefs/COMMON.md, then briefs/$brief, and carry it out completely, following every rule in both."
