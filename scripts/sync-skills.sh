#!/usr/bin/env bash
# Sync every skill in this repo into a consumer repo checkout.
#
# Usage: scripts/sync-skills.sh <consumer-repo-dir>
#
# - A "skill" is any directory containing a SKILL.md (may be nested in category folders).
# - Skills are flattened into <consumer>/.agents/skills/<skill-dir-name>/ (the real files).
# - <consumer>/.claude/skills/<skill-dir-name> is a relative symlink to the .agents copy,
#   because Claude Code does not read .agents/skills.
# - .agents/skills is replaced wholesale, so added, edited and deleted skills all propagate.
# - Fails loudly if two skills share a directory name.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <consumer-repo-dir>" >&2
  exit 2
fi

src="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dest="$(cd "$1" && pwd)"

# Collect skill directories (relative to $src), excluding repo plumbing.
skill_dirs=()
while IFS= read -r -d '' f; do
  skill_dirs+=("$(dirname "${f#./}")")
done < <(cd "$src" && find . \( -name .git -o -name .github -o -name scripts -o -name node_modules \) -prune \
  -o -name SKILL.md -type f -print0 | sort -z)

if [[ ${#skill_dirs[@]} -eq 0 ]]; then
  echo "error: no SKILL.md files found in $src; refusing to wipe the consumer's skills" >&2
  exit 1
fi

# Name collision check.
collisions="$(printf '%s\n' "${skill_dirs[@]}" | awk -F/ '{ n[$NF] = n[$NF] "\n    " $0; c[$NF]++ }
  END { for (k in c) if (c[k] > 1) printf "  \"%s\":%s\n", k, n[k] }')"
if [[ -n "$collisions" ]]; then
  echo "error: skill directory names must be unique, but these collide:" >&2
  echo "$collisions" >&2
  exit 1
fi

agents_dir="$dest/.agents/skills"
claude_dir="$dest/.claude/skills"

# Remove our previous symlinks (only symlinks that point into .agents/skills).
if [[ -d "$claude_dir" ]]; then
  while IFS= read -r -d '' link; do
    case "$(readlink "$link")" in
      ../../.agents/skills/*) rm "$link" ;;
    esac
  done < <(find "$claude_dir" -mindepth 1 -maxdepth 1 -type l -print0)
fi

rm -rf "$agents_dir"
mkdir -p "$agents_dir" "$claude_dir"

for rel in "${skill_dirs[@]}"; do
  name="$(basename "$rel")"
  cp -R "$src/$rel" "$agents_dir/$name"
  if [[ -e "$claude_dir/$name" || -L "$claude_dir/$name" ]]; then
    echo "error: $claude_dir/$name already exists and is not managed by this sync" >&2
    exit 1
  fi
  ln -s "../../.agents/skills/$name" "$claude_dir/$name"
done

echo "Synced ${#skill_dirs[@]} skills into $dest"
