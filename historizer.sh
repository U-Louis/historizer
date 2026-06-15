#!/usr/bin/env bash

set -uo pipefail

cli_suffix=""
cli_base=""
mode=run

while (( $# )); do
  case "$1" in
    -s|--status) mode=status ;;
    --suffix)      cli_suffix="${2:-}"; shift ;;
    --base)      cli_base="${2:-}"; shift ;;
    -h|--help)
      cat <<'EOF'
Usage: historize [options]

  On the current branch:
    1. Cherry-picks every commit not yet mirrored onto <current>-<suffix>,
       creating that branch if it doesn't exist.
    2. Squashes the current branch back to one commit on top of <base>.

Options:
  -s, --status        Dry run: print plan, change nothing.
      --suffix SUFFIX Suffix for the mirror branch (default: history).
                      Mirror branch name is "<current>-<SUFFIX>".
      --base BRANCH   Base branch the squash sits on top of (default: main).
  -h, --help          Show this help.

Configuration (later overrides earlier):
  ~/.config/historizer/config
  <repo-root>/.historizer
  env: HISTORIZER_SUFFIX, HISTORIZER_BASE
  flags: --suffix, --base

Config file (sourced as bash):
  suffix=history
  base=develop
EOF
      exit 0
      ;;
    *) echo "historize: unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

suffix="history"
base="main"

global_config="${XDG_CONFIG_HOME:-$HOME/.config}/historizer/config"
[[ -f "$global_config" ]] && source "$global_config"

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "historize: not in a git repo." >&2
  exit 1
}
[[ -f "$repo_root/.historizer" ]] && source "$repo_root/.historizer"

suffix="${HISTORIZER_SUFFIX:-$suffix}"
base="${HISTORIZER_BASE:-$base}"
[[ -n "$cli_suffix" ]] && suffix="$cli_suffix"
[[ -n "$cli_base" ]] && base="$cli_base"

if [[ -z "$suffix" ]]; then
  echo "historize: 'suffix' must not be empty." >&2
  exit 1
fi
if [[ -z "$base" ]]; then
  echo "historize: 'base' must not be empty." >&2
  exit 1
fi

current=$(git symbolic-ref --short HEAD 2>/dev/null) || {
  echo "historize: HEAD is detached." >&2
  exit 1
}

if [[ "$current" == "$base" ]]; then
  echo "historize: refusing to run on the base branch '$base'." >&2
  exit 1
fi

if [[ "$current" == *"-${suffix}" ]]; then
  echo "historize: refusing to run on '$current' (looks like a mirror branch)." >&2
  exit 1
fi

mirror="${current}-${suffix}"

if ! git rev-parse --verify --quiet "refs/heads/$base" >/dev/null; then
  echo "historize: base branch '$base' does not exist locally." >&2
  exit 1
fi

if ! git diff --quiet HEAD --; then
  echo "historize: working tree has uncommitted changes. Commit or stash first." >&2
  exit 1
fi

merge_base=$(git merge-base "$base" "$current") || {
  echo "historize: cannot find merge-base between '$base' and '$current'." >&2
  exit 1
}

marker_ref="refs/historizer/${current}/last-squash"
if git show-ref --verify --quiet "$marker_ref"; then
  from_ref=$(git rev-parse --verify "$marker_ref")
else
  from_ref="$merge_base"
fi

mirror_exists=0
if git show-ref --verify --quiet "refs/heads/$mirror"; then
  mirror_exists=1
fi

new_commits=$(git rev-list --reverse "${from_ref}..HEAD")
squash_count=$(git rev-list --count "${merge_base}..HEAD")

if [[ "$mode" == status ]]; then
  echo "Branch:        $current @ $(git rev-parse --short HEAD)"
  if (( mirror_exists )); then
    echo "Mirror:        $mirror @ $(git rev-parse --short "$mirror")"
  else
    echo "Mirror:        $mirror (will be created at $(git rev-parse --short "$merge_base"))"
  fi
  echo "Base:          $base @ $(git rev-parse --short "$base")"
  echo "Slug:          $suffix"
  echo "Merge-base:    $(git rev-parse --short "$merge_base")"
  echo "Cherry-pick from: $(git rev-parse --short "$from_ref")"
  echo "Plan:"
  if [[ -z "$new_commits" ]]; then
    echo "  - nothing to cherry-pick onto '$mirror'"
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
  echo "Creating mirror branch '$mirror' at $(git rev-parse --short "$merge_base")..."
  git branch "$mirror" "$merge_base"
fi

if [[ -z "$new_commits" ]]; then
  echo "Nothing to cherry-pick onto '$mirror'."
else
  count=$(printf '%s\n' "$new_commits" | wc -l | tr -d ' ')
  echo "Cherry-picking $count commit(s) onto '$mirror'..."
  git checkout --quiet "$mirror"
  while IFS= read -r c; do
    [[ -z "$c" ]] && continue
    if ! git cherry-pick --allow-empty "$c"; then
      {
        echo "historize: cherry-pick failed on '$mirror'."
        echo "  Resolve, then run:"
        echo "    git cherry-pick --continue   (or --abort)"
        echo "    git checkout $current"
        echo "    historize                    # re-run when ready"
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
