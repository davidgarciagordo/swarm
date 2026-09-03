#!/usr/bin/env bash
# tests/test_push_guard.sh — backstop DETERMINISTA de la fase 6: el dominio delivery es el primero
# con `git push` real, y su seguridad no puede depender solo de la prosa de agents/release-manager.md.
#
# Mismo patrón que el backstop `composer update` de fase 5b (BARE_TWO_WORD_DENIED): la prosa dice qué
# hacer, el guard hace imposible lo contrario. Aquí se deniega, para CUALQUIER agent_type:
#   - `git push` sin `<remote> <rama>` explícitos (la forma bare empuja al upstream configurado, que
#     el agente no controla ni ha previsualizado);
#   - push a una rama protegida (master/main/develop/trunk), en cualquiera de sus formas de refspec
#     (`master`, `HEAD:master`, `refs/heads/master`);
#   - flags destructivos (--force/-f/--force-with-lease/--delete/--mirror/--all/--prune/--tags) y sus
#     variantes con `=` y en cluster de flags cortos (`-fu`);
#   - refspec con `+` (force implícito) o con destino vacío (`:rama` = borrado remoto);
#   - `gh pr merge|close|edit|ready|review|reopen|comment|lock|unlock|checkout` (auto-merge de un PR
#     es la propiedad de seguridad que esta fase existe para NO tener), `gh auth login|logout|...`,
#     y los subcomandos DESTRUCTIVOS de `git remote` (set-url/rename/remove/prune/...).
#
# Y las dos únicas formas mutantes que el bootstrap de remoto necesita (ruling 3, Task 2b), cada una
# acotada a su forma exacta para que un flag no la convierta en otra cosa:
#   - `git remote add <nombre> <url>`: exactamente dos posicionales y CERO flags. `git remote add` es
#     aditivo (falla si el nombre ya existe, así que no puede pisar un remoto del owner), pero
#     `--mirror=push` lo convertiría en un remoto que borra ramas en cada push: por eso, cero flags.
#   - `gh repo create <nombre> [flags de un conjunto CERRADO]`: `--public`/`--private`/`--source`/
#     `--remote`/`--push`/`--description`. Cualquier otro flag (`--template`, `--clone`, `--team`…)
#     deniega el segmento entero. `gh repo` sin `create` detrás sigue denegado por completo.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
HOOK="$PLUGIN_ROOT/hooks/bash-guard.py"

guard() { # guard <agent_type> <command> -> "allow" | "deny"
  local out
  out="$(printf '{"agent_type": "%s", "tool_name": "Bash", "tool_input": {"command": "%s"}}' "$1" "$2" | python3 "$HOOK")"
  if echo "$out" | grep -q '"permissionDecision": "deny"'; then echo deny; else echo allow; fi
}

A=swarm:release-manager

# --- la ÚNICA forma permitida ---
assert_eq "allow" "$(guard $A 'git push origin feature/export-csv')" "the one allowed push form: git push <remote> <branch>"
assert_eq "allow" "$(guard $A 'git push origin release/2026-09')" "a slash in the branch name is fine"
assert_eq "allow" "$(guard $A 'git push -u origin feature/x')" "-u is not destructive, still two positionals"

# --- forma incompleta: nunca ---
assert_eq "deny"  "$(guard $A 'git push')" "bare git push (implicit upstream) is denied"
assert_eq "deny"  "$(guard $A 'git push origin')" "git push <remote> with no refspec is denied"
assert_eq "deny"  "$(guard $A 'git push origin feature/a feature/b')" "two refspecs at once is denied"

# --- ramas protegidas, en todas sus formas de refspec ---
assert_eq "deny"  "$(guard $A 'git push origin master')" "push to master is denied"
assert_eq "deny"  "$(guard $A 'git push origin main')" "push to main is denied"
assert_eq "deny"  "$(guard $A 'git push origin develop')" "push to develop is denied"
assert_eq "deny"  "$(guard $A 'git push origin trunk')" "push to trunk is denied"
assert_eq "deny"  "$(guard $A 'git push origin HEAD:master')" "push HEAD:master is denied (dst is what counts)"
assert_eq "deny"  "$(guard $A 'git push origin refs/heads/main')" "fully qualified protected ref is denied"
assert_eq "deny"  "$(guard $A 'git push origin feature/x:master')" "src:dst onto a protected dst is denied"

# --- refspecs peligrosos ---
assert_eq "deny"  "$(guard $A 'git push origin +feature/x')" "leading + (force refspec) is denied"
assert_eq "deny"  "$(guard $A 'git push origin :feature/x')" "empty src (remote branch deletion) is denied"

# --- flags destructivos y sus variantes ---
assert_eq "deny"  "$(guard $A 'git push --force origin feature/x')" "--force is denied"
assert_eq "deny"  "$(guard $A 'git push -f origin feature/x')" "-f is denied"
assert_eq "deny"  "$(guard $A 'git push -fu origin feature/x')" "-f inside a short-flag cluster is denied"
assert_eq "deny"  "$(guard $A 'git push --force-with-lease origin feature/x')" "--force-with-lease is denied"
assert_eq "deny"  "$(guard $A 'git push --force-with-lease=refs/heads/x origin feature/x')" "--flag=value form is denied too"
assert_eq "deny"  "$(guard $A 'git push --delete origin feature/x')" "--delete is denied"
assert_eq "deny"  "$(guard $A 'git push --mirror origin')" "--mirror is denied"
assert_eq "deny"  "$(guard $A 'git push --all origin')" "--all is denied"
assert_eq "deny"  "$(guard $A 'git push --tags origin feature/x')" "--tags is denied (v1 creates no tags)"

# --- gh: crear/leer sí, mergear/cerrar/mover el árbol NO ---
assert_eq "allow" "$(guard $A 'gh auth status')" "gh auth status is allowed (availability probe)"
assert_eq "allow" "$(guard $A 'gh pr create --base master --head feature/x --title T --body-file /tmp/n.md')" "gh pr create is allowed"
assert_eq "allow" "$(guard $A 'gh pr view 12')" "gh pr view is allowed"
assert_eq "deny"  "$(guard $A 'gh pr merge 12 --squash')" "gh pr merge is DENIED — a human merges the PR (permanent design property)"
assert_eq "deny"  "$(guard $A 'gh pr close 12')" "gh pr close is denied"
assert_eq "deny"  "$(guard $A 'gh pr edit 12 --title x')" "gh pr edit is denied"
assert_eq "deny"  "$(guard $A 'gh pr ready 12')" "gh pr ready is denied"
assert_eq "deny"  "$(guard $A 'gh pr checkout 12')" "gh pr checkout is denied (never moves the working tree)"
assert_eq "deny"  "$(guard $A 'gh auth login')" "gh auth login is denied (interactive, mutates credentials)"

# --- gh repo: SOLO `create`, y solo con su conjunto cerrado de flags (ruling 3, Task 2b) ---
assert_eq "allow" "$(guard $A 'gh repo create owner/repo --private --source=. --remote=origin --push')" "the one allowed gh repo form: create with closed flags"
assert_eq "allow" "$(guard $A 'gh repo create owner/repo --public --source=. --remote=origin --push')" "--public is in the closed flag set too"
assert_eq "allow" "$(guard $A 'gh repo create owner/repo --public --source . --remote origin --push')" "the space form of a value flag is accepted (its value is consumed, not counted as a positional)"
assert_eq "deny"  "$(guard $A 'gh repo delete owner/repo')" "gh repo delete is denied (only create is reachable)"
assert_eq "deny"  "$(guard $A 'gh repo rename other')" "gh repo rename is denied"
assert_eq "deny"  "$(guard $A 'gh repo edit --visibility public')" "gh repo edit is denied"
assert_eq "deny"  "$(guard $A 'gh repo clone owner/repo')" "gh repo clone is denied (writes a tree the owner did not ask for)"
assert_eq "deny"  "$(guard $A 'gh repo')" "bare gh repo is denied (no third word at all)"
assert_eq "deny"  "$(guard $A 'gh repo create owner/repo --template evil/repo')" "an out-of-set flag denies the whole segment (flag injection)"
assert_eq "deny"  "$(guard $A 'gh repo create owner/repo --clone')" "--clone is not in the closed set"
assert_eq "deny"  "$(guard $A 'gh repo create')" "gh repo create with no repo name is denied"
assert_eq "deny"  "$(guard $A 'gh repo create a b')" "two positionals after create is denied (one name, exactly)"

# --- git remote: leer sí; `add` sí en su forma exacta; el resto de mutantes NO ---
assert_eq "allow" "$(guard $A 'git remote -v')" "git remote -v is allowed"
assert_eq "allow" "$(guard $A 'git remote get-url origin')" "git remote get-url is allowed"
assert_eq "allow" "$(guard $A 'git remote add origin https://example.com/x.git')" "git remote add <name> <url> is allowed (additive: fails if the name exists)"
assert_eq "deny"  "$(guard $A 'git remote add --mirror=push origin https://example.com/x.git')" "--mirror=push would turn every push into a destructive one: denied"
assert_eq "deny"  "$(guard $A 'git remote add -f origin https://example.com/x.git')" "no flags at all on git remote add"
assert_eq "deny"  "$(guard $A 'git remote add origin')" "git remote add with no URL is denied"
assert_eq "deny"  "$(guard $A 'git remote set-url origin https://example.com/x.git')" "git remote set-url is denied (never rewrites the owner's remote — ruling 14)"
assert_eq "deny"  "$(guard $A 'git remote -v set-url origin https://example.com/x.git')" "git remote -v set-url … is denied too (a leading flag does not hide the subcommand)"
assert_eq "deny"  "$(guard $A 'git remote rename origin upstream')" "git remote rename is denied"
assert_eq "deny"  "$(guard $A 'git remote remove origin')" "git remote remove is denied"

# --- el backstop es GLOBAL: ningún otro agente gana push por tener el prefijo en el futuro ---
assert_eq "deny"  "$(guard swarm:implementation-orchestrator 'git push origin feature/x')" "implementation-orchestrator has no push at all"
assert_eq "deny"  "$(guard swarm:delivery-orchestrator 'git push origin feature/x')" "the domain orchestrator does NOT push — only its leaf does"
assert_eq "deny"  "$(guard swarm:handoff-writer 'git push origin feature/x')" "handoff-writer never pushes"
assert_eq "deny"  "$(guard swarm:delivery-orchestrator 'gh repo create owner/repo --private --source=. --remote=origin --push')" "the domain orchestrator creates no repository — only its leaf does"
assert_eq "deny"  "$(guard swarm:delivery-orchestrator 'git remote add origin https://example.com/x.git')" "the domain orchestrator adds no remote"
assert_eq "deny"  "$(guard swarm:orchestrator 'gh repo create owner/repo --private --source=. --remote=origin --push')" "the ROOT never runs leaf work: no gh at all (spec §3.2 rule 4)"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
