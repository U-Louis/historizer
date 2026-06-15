#!/usr/bin/env bash

set -uo pipefail

cli_slug=""
cli_base=""
mode=run

while (( $# )); do
  case "$1" in
    -s|--status) mode=status ;;
    --slug)      cli_slug="${2:-}"; shift ;;
    --base)      cli_base="${2:-}"; shift ;;
    -h|--help)
      cat <<'EOF'
Usage: mirror-squash.sh [options]

  On the current branch:
    1. Cherry-picks every commit added since the last squash onto
       <current-branch>-<slug>, creating that branch if it doesn't exist.
    2. Squashes the current branch back to one commit on top of <base>.

Options:
  -s, --status        Dry run: print plan, change nothing.
      --slug SLUG     Suffix for the mirror branch (default: history).
                      Mirror branch name is "<current>-<SLUG>".
      --base BRANCH   Base branch the squash sits on top of (default: main).
  -h, --help          Show this help.

Configuration (later overrides earlier):
  ~/.config/mirror-squash/config
  <repo-root>/.mirror-squash
  env: MIRROR_SQUASH_SLUG, MIRROR_SQUASH_BASE
  flags: --slug, --base

Config file (sourced as bash):
  slug=history
  base=develop
EOF
      exit 0
      ;;
    *) echo "mirror-squash: unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

slug="history"
base="main"

global_config="${XDG_CONFIG_HOME:-$HOME/.config}/mirror-squash/config"
[[ -f "$global_config" ]] && source "$global_config"

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "mirror-squash: not in a git repo." >&2
  exit 1
}
[[ -f "$repo_root/.mirror-squash" ]] && source "$repo_root/.mirror-squash"

slug="${MIRROR_SQUASH_SLUG:-$slug}"
base="${MIRROR_SQUASH_BASE:-$base}"
[[ -n "$cli_slug" ]] && slug="$cli_slug"
[[ -n "$cli_base" ]] && base="$cli_base"

if [[ -z "$slug" ]]; then
  echo "mirror-squash: 'slug' must not be empty." >&2
  exit 1
fi
if [[ -z "$base" ]]; then
  echo "mirror-squash: 'base' must not be empty." >&2
  exit 1
fi

current=$(git symbolic-ref --short HEAD 2>/dev/null) || {
  echo "mirror-squash: HEAD is detached." >&2
  exit 1
}

if [[ "$current" == "$base" ]]; then
  echo "mirror-squash: refusing to run on the base branch '$base'." >&2
  exit 1
fi

if [[ "$current" == *"-${slug}" ]]; then
  echo "mirror-squash: refusing to run on '$current' (looks like a mirror branch with suffix '-${slug}')." >&2
  exit 1
fi

mirror="${current}-${slug}"

if ! git rev-parse --verify --quiet "refs/heads/$base" >/dev/null; then
  echo "mirror-squash: base branch '$base' does not exist locally." >&2
  exit 1
fi

if ! git diff --quiet HEAD --; then
  echo "mirror-squash: working tree has uncommitted changes. Commit or stash first." >&2
  exit 1
fi

merge_base=$(git merge-base "$base" "$current") || {
  echo "mirror-squash: cannot find merge-base between '$base' and '$current'." >&2
  exit 1
}

marker_ref="refs/mirror-squash/${current}/last-squash"
from_ref=""
if git show-ref --verify --quiet "$marker_ref"; then
  from_ref=$(git rev-parse --verify "$marker_ref")
fi

mirror_exists=0
if git show-ref --verify --quiet "refs/heads/$mirror"; then
  mirror_exists=1
fi

new_commits=""
if (( mirror_exists )) && [[ -n "$from_ref" ]]; then
  new_commits=$(git rev-list --reverse "${from_ref}..HEAD")
fi

squash_count=$(git rev-list --count "${merge_base}..HEAD")

if [[ "$mode" == status ]]; then
  echo "Branch:        $current @ $(git rev-parse --short HEAD)"
  if (( mirror_exists )); then
    echo "Mirror:        $mirror @ $(git rev-parse --short "$mirror")"
  else
    echo "Mirror:        $mirror (will be created)"
  fi
  echo "Base:          $base @ $(git rev-parse --short "$base")"
  echo "Slug:          $slug"
  echo "Merge-base:    $(git rev-parse --short "$merge_base")"
  if [[ -n "$from_ref" ]]; then
    echo "Last squash:   $(git rev-parse --short "$from_ref")"
  else
    echo "Last squash:   (none yet)"
  fi
  echo "Plan:"
  if (( ! mirror_exists )); then
    echo "  - create '$mirror' at HEAD"
  elif [[ -z "$from_ref" ]]; then
    echo "  - mirror exists with no marker: only set marker, no cherry-pick"
  elif [[ -z "$new_commits" ]]; then
    echo "  - mirror is up to date: nothing to mirror"
  else
    n=$(printf '%s\n' "$new_commits" | wc -l | tr -d ' ')
    echo "  - cherry-pick $n commit(s) onto '$mirror':"
    git log --oneline --reverse "${from_ref}..HEAD" | sed 's/^/      /'
  fi
  if (( squash_count <= 1 )); then
    echo "  - squash skipped: $squash_count commit(s) on '$current' since '$base'"
  else
    echo "  - squash $squash_count commits on '$current' into 1"
  fi
  exit 0
fi

if (( ! mirror_exists )); then
  echo "Creating mirror branch '$mirror' at HEAD..."
  git branch "$mirror" "$current"
elif [[ -z "$from_ref" ]]; then
  echo "Mirror '$mirror' exists but no marker; assuming it's in sync."
elif [[ -z "$new_commits" ]]; then
  echo "Nothing new to mirror onto '$mirror'."
else
  count=$(printf '%s\n' "$new_commits" | wc -l | tr -d ' ')
  echo "Mirroring $count commit(s) onto '$mirror'..."
  git checkout --quiet "$mirror"
  while IFS= read -r c; do
    [[ -z "$c" ]] && continue
    if ! git cherry-pick --allow-empty "$c"; then
      {
        echo "mirror-squash: cherry-pick failed on '$mirror'."
        echo "  Resolve, then run:"
        echo "    git cherry-pick --continue   (or --abort)"
        echo "    git checkout $current"
        echo "    $0                            # re-run when ready"
      } >&2
      exit 1
    fi
  done <<< "$new_commits"
  git checkout --quiet "$current"
fi

if (( squash_count <= 1 )); then
  echo "'$current' has $squash_count commit(s) since '$base' — nothing to squash."
else
  msg=$(git log --reverse --pretty=format:'* %s%n%n%b' "${merge_base}..HEAD")
  echo "Squashing $squash_count commits on '$current'..."
  git reset --soft --quiet "$merge_base"
  git commit --quiet --allow-empty -m "$current" -m "$msg"
fi

git update-ref "$marker_ref" HEAD

echo
echo "Done."
echo "  $current  -> $(git rev-parse --short HEAD)  ($(git rev-list --count "${merge_base}..HEAD") commit since $base)"
echo "  $mirror -> $(git rev-parse --short "$mirror")  ($(git rev-list --count "${merge_base}..$mirror") commit(s) of preserved history)"
