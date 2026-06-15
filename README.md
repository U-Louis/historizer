## historizer: keep the current branch squashed to one commit on top of a base branch, while mirroring every individual commit onto a sibling

`<current>-<suffix>` branch (full history preserved).

Idempotent. Tracks the last squashed commit at:
   refs/historizer/<branch>/last-squash

# Configuration:
   1. Built-in defaults: suffix=history, base=main
   2. ~/.config/historizer/config
   3. <repo-root>/.historizer
   4. Environment: HISTORIZER_SUFFIX, HISTORIZER_BASE
   5. CLI flags: `--suffix <s>`, `--base <b>`

# Config file format:
   suffix=history
   base=develop

# Usage:
   historize [--suffix SUFFIX] [--base BRANCH]
   
   historize --status
   
   historize --help
