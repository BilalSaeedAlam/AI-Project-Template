#!/usr/bin/env bash
# agent-guard.sh — PreToolUse guard for the subagents in .claude/agents/.
#
# Reads the hook JSON from stdin. Prints a deny/ask decision, or prints nothing, which leaves the
# call to Claude Code's normal permission flow (it is never auto-approved by this script).
#
# Usage (from agent frontmatter hooks):
#   agent-guard.sh bash-readonly [--tests]  Read-only allowlist (+ test-commands.txt with --tests).
#                                           Anything else is denied.
#   agent-guard.sh bash-diagnostic          Destructive/consequential patterns are denied.
#                                           Read-only allowlist and test-commands.txt pass through.
#                                           Anything else requires user approval (ask).
#   agent-guard.sh write deny|ask DIR...    Write/Edit inside DIR... (relative to project root)
#                                           pass through; anything else is denied or asks the user.
#
# Technology-agnostic, best-effort pattern matching. It is a guardrail, not a sandbox.
# Requires bash + sed + grep (Git Bash on Windows, default on macOS/Linux).

set -u
set -f  # no filename globbing when splitting commands

mode="${1:-}"
[ $# -gt 0 ] && shift

decide() { # $1 = deny|ask   $2 = reason (no double quotes)
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"agent-guard: %s"}}\n' "$1" "$2"
  exit 0
}

input="$(cat | tr -d '\r\n')"

# Extract a top-level JSON string field (handles escaped quotes). Empty if absent.
field() {
  printf '%s' "$input" | sed -nE "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"(([^\"\\\\]|\\\\.)*)\".*/\1/p"
}

# Paths / names that likely hold secrets. Applied to commands and write targets.
SECRET_RE='(^|[^a-z0-9_])\.env($|[^a-z0-9_])|\.env\.|\.pem($|[^a-z])|\.key($|[^a-z])|\.pfx|\.p12|id_rsa|id_ed25519|(^|/)secrets?/|credentials\.json'

# Destructive or consequential command patterns (denied in every mode).
DESTRUCTIVE_RE='(^|[;&| ])(sudo|mkfs|shutdown|reboot|dd +if=)|rm +(-[a-z]*[rf]|--recursive|--force)|(chmod|chown) +-r|git +(push|reset +--hard|clean|checkout +--|restore|rebase|filter-branch|filter-repo|update-ref|reflog +expire|gc +--prune|stash +(drop|clear))|git +branch +.*(-d|--delete)|git +tag +.*(-d|--delete)|terraform +(apply|destroy|import|taint|state +(rm|mv|push))|pulumi +(up|destroy)|kubectl +(apply|delete|create|patch|replace|scale|rollout|drain|cordon|edit|set|label|annotate|exec)|helm +(install|upgrade|uninstall|delete|rollback)|docker +(push|rm|rmi|system +prune|volume +rm)|(npm|yarn|pnpm|cargo|gem|twine|poetry) +publish|(^|[ /])(aws|gcloud|az) +.*(delete|remove|terminate|put-|create|update|modify|attach|detach|deploy|set-iam|add-iam|remove-iam|rotate|invoke|publish|send)|(vercel|netlify|fly|flyctl|heroku|firebase|serverless|sls|wrangler|shopify) +.*(deploy|publish|push|destroy|delete|--prod)|curl +.*(-x *|--request *)(post|put|patch|delete)|wget +.*--(post|method)|drop +(table|database|schema)|truncate +table|delete +from|update +[a-z0-9_."]+ +set|insert +into|alter +table|claude +.*(--dangerously|--permission-mode|--allowed-?tools)'

# Case-sensitive: curl flags that send a request body (-d/-F/-T differ from -f/-t by case).
CURL_BODY_RE='curl +.* (-d|--data[a-z-]*|-F|--form|-T|--upload-file)( |=)'

# Read-only command allowlist, checked per pipeline segment.
ro_segment() {
  local s="$1"
  printf '%s' "$s" | grep -Eqi -- '--output|--exec|(^| )-exec|-execdir|-delete|(^| )-ok( |$)|-fprint|-fls|--pre( |=)|--open-files-in-pager' && return 1
  printf '%s' "$s" | grep -Eq '^sort +(.* )?-o' && return 1
  printf '%s' "$s" | grep -Eqi '^git +branch +.*(-[dmcfu]( |$)|--(delete|move|copy|force|set-upstream|unset-upstream|edit-description))' && return 1
  printf '%s' "$s" | grep -Eq '^(git +(status|diff|log|show|blame|ls-files|ls-tree|rev-parse|grep|shortlog|describe|merge-base|cat-file|diff-tree|name-rev|for-each-ref)( |$)|git +branch( |$)|git +(worktree +list|remote +-v|remote +show|stash +list|tag +(-l|--list)|config +(--get|--list|-l))( |$)|git +reflog( +show)?( +[^ ]+)?$|(ls|pwd|wc|grep|rg|find|stat|du|sort|cut|diff|which|echo|jq)( |$))'
}

readonly_cmd() {
  local c="$1"
  printf '%s' "$c" | grep -Eq '[;&<>`]|\$\(|\|\|' && return 1
  local IFS='|'
  local seg
  for seg in $c; do
    seg="$(printf '%s' "$seg" | sed -E 's/^ +//; s/ +$//')"
    [ -z "$seg" ] && return 1
    ro_segment "$seg" || return 1
  done
  return 0
}

test_cmd() { # command starts with a prefix listed in test-commands.txt and has no shell operators
  local c="$1" f
  f="$(dirname "$0")/test-commands.txt"
  [ -f "$f" ] || return 1
  printf '%s' "$c" | grep -Eq '[;&|<>`]|\$\(' && return 1
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    line="$(printf '%s' "$line" | sed -E 's/\r$//; s/^ +//; s/ +$//')"
    case "$line" in ''|'#'*) continue ;; esac
    case "$c" in "$line"|"$line "*) return 0 ;; esac
  done < "$f"
  return 1
}

norm_path() {
  printf '%s' "$1" | sed -e 's#\\\\#/#g' -e 's#\\#/#g' | sed -E 's#^/([a-zA-Z])/#\1:/#' | tr 'A-Z' 'a-z'
}

case "$mode" in
  bash-readonly|bash-diagnostic)
    cmd="$(field command)"
    [ -z "$cmd" ] && decide deny "could not read the command"
    # JSON unescape (\" and \\); newlines become command separators.
    cmd="$(printf '%s' "$cmd" | sed -e 's/\\n/ ; /g' -e 's/\\t/ /g' -e 's/\\"/"/g' -e 's/\\\\/\\/g' -e 's/^ *//')"
    lc="$(printf '%s' "$cmd" | tr 'A-Z' 'a-z')"

    printf '%s' "$lc" | grep -Eq "$SECRET_RE" && decide deny "command references a likely secret file"
    { printf '%s' "$lc" | grep -Eq "$DESTRUCTIVE_RE" || printf '%s' "$cmd" | grep -Eq "$CURL_BODY_RE"; } && decide deny "destructive or consequential command; a human must run or approve it outside this agent"

    readonly_cmd "$cmd" && exit 0
    if [ "$mode" = "bash-readonly" ]; then
      if [ "${1:-}" = "--tests" ] && test_cmd "$cmd"; then exit 0; fi
      decide deny "this agent may only run read-only inspection commands (see .claude/hooks/agent-guard.sh)"
    fi
    test_cmd "$cmd" && exit 0
    decide ask "command is not on the read-only or test allowlist; confirm it is non-destructive"
    ;;

  write)
    policy="${1:-deny}"
    [ $# -gt 0 ] && shift
    case "$policy" in deny|ask) ;; *) decide deny "invalid guard policy" ;; esac

    target="$(field file_path)"
    [ -z "$target" ] && decide deny "could not read the target path"
    p="$(norm_path "$target")"
    root="$(norm_path "${CLAUDE_PROJECT_DIR:-$(pwd)}")"
    root="${root%/}"
    case "$p" in /*|[a-z]:/*) ;; *) p="$root/$p" ;; esac
    case "/$p/" in */../*) decide deny "path traversal is not allowed" ;; esac
    printf '%s' "$p" | grep -Eq "$SECRET_RE" && decide deny "target looks like a secret file"

    for d in "$@"; do
      d="$(norm_path "$d")"; d="${d%/}"
      case "$p" in "$root/$d"/*) exit 0 ;; esac
    done
    decide "$policy" "this agent may only write under: $* (project-relative)"
    ;;

  *)
    decide deny "unknown guard mode"
    ;;
esac
