#!/usr/bin/env bash
# scripts/lib/validate.sh — argument shapes for the memory scripts, sourced (never run). Every value that becomes
# part of a path under .swarm/ (or reaches sed) is checked HERE: the scripts are the boundary, not bash-guard.py.
# swarm_valid <kind> <value>: exit 0 if value fits kind, 1 otherwise.
#   agent    ^[a-z0-9][a-z0-9-]{0,63}$ (file name under findings/, mailbox/, agents/)
#   run      a lowercase uuid (mem-manifest.sh open) or `adhoc` (directory under run/)
#   line     a positive integer (fed to sed)
#   count    a non-negative integer (fed to $((...)), where a name like `now[$(cmd)]` would run cmd)
#   relpath  relative, no `..` component, single line (repo file cited by a finding)
#   oneline  no newline / carriage return (each record is one line)
swarm_valid() {
  local nl=$'\n' cr=$'\r'
  case "$2" in *"$nl"*|*"$cr"*) return 1 ;; esac
  case "$1" in
    agent) [[ "$2" =~ ^[a-z0-9][a-z0-9-]{0,63}$ ]] ;;
    run) [ "$2" = adhoc ] || [[ "$2" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] ;;
    line) [[ "$2" =~ ^[1-9][0-9]{0,8}$ ]] ;;
    count) [[ "$2" =~ ^[0-9]{1,6}$ ]] ;;
    relpath) case "/$2/" in //*|*/../*) return 1 ;; esac; [ -n "$2" ] ;;
    oneline) return 0 ;;
    *) return 1 ;;
  esac
}

# swarm_require <script-label> <kind> <flag> <value>: prints the reason and returns 64 when the value is invalid.
swarm_require() {
  swarm_valid "$2" "$4" && return 0
  printf 'swarm: %s — invalid %s (%s): %q\n' "$1" "$3" "$2" "$4" >&2
  return 64
}
