## historizer: keep the current branch squashed to one commit on top of a base branch, while mirroring every individual commit onto a sibling

```<current>-<slug>``` branch (full history preserved).

Idempotent. Tracks the last squashed commit at:
   refs/mirror-squash/<branch>/last-squash

# Configuration:
   1. Built-in defaults: slug=history, base=main
   2. ~/.config/mirror-squash/config
   3. <repo-root>/.historizer
   4. Environment: HISTORIZER_SLUG, HISTORIZER_BASE
   5. CLI flags: ``--slug <s>``, ``--base <b>``

# Config file format:
   slug=history
   base=develop

# Usage:
   mirror-squash.sh [--slug SLUG] [--base BRANCH]
   mirror-squash.sh --status
   mirror-squash.sh --help
