## historizer: keep the current branch squashed to one commit on top of its upstream, while mirroring every individual commit onto a sibling

`<current>-<suffix>` branch (full history preserved).

The squash target ("base") is the current branch's upstream ref
(e.g. `origin/<current>`), i.e. the latest commit you've pushed.
The mirror branch is also created at that point on first run.

Idempotent. Tracks the last squashed commit at:
   refs/historizer/<branch>/last-squash

# Configuration:
   1. Built-in defaults: suffix=history, base=upstream of current branch
   2. <script-dir>/config
   3. ~/.config/historizer/config
   4. <repo-root>/.historizer
   5. Environment: HISTORIZER_SUFFIX, HISTORIZER_BASE
   6. CLI flags: `--suffix <s>`, `--base <ref>`

# Config file format:
   suffix=history

# Usage:
   historize [--suffix SUFFIX] [--base REF]
   historize --status
   historize --help

# Note
The branch must have an upstream configured (`git push -u origin <branch>` once,
or `git branch --set-upstream-to=...`) — otherwise pass `--base` explicitly.
