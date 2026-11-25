#!/usr/bin/env bash
# Keeps private details out of the repository: run by the git pre-commit hook on the staged
# files (or on the given files). Fails on
#   - every line of .private-patterns (git-ignored: the real addresses, logins and paths,
#     one extended regex per line, # comments allowed), and
#   - generic leaks: absolute home paths, private network addresses, keys and tokens.
# Install the hook once:  ln -sf ../../tools/check_private.sh .git/hooks/pre-commit
set -euo pipefail
root=$(git rev-parse --show-toplevel)
cd "$root"
if [ $# -gt 0 ]; then files=("$@"); else mapfile -t files < <(git diff --cached --name-only --diff-filter=ACMR); fi
[ ${#files[@]} -eq 0 ] && exit 0

patterns=(
  '/home/[a-z_][a-z0-9_-]*/'
  '/Users/[A-Za-z0-9_-]+/'
  '(^|[^0-9.])(192\.168|10\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]{1,3}\.[0-9]{1,3}([^0-9.]|$)'
  'BEGIN [A-Z ]*PRIVATE KEY'
  'hf_[A-Za-z0-9]{30,}|ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|sk-[A-Za-z0-9]{30,}|AKIA[0-9A-Z]{16}'
)
if [ -f .private-patterns ]; then
  while IFS= read -r p; do [[ -z "$p" || "$p" == \#* ]] || patterns+=("$p"); done < .private-patterns
fi

bad=0
for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  for p in "${patterns[@]}"; do
    # -a: binaries too (image metadata, caches); print only where, never the match
    if grep -qaE -- "$p" "$f"; then
      echo "private detail in $f (pattern #$(( $(printf '%s\n' "${patterns[@]}" | grep -nxF -- "$p" | head -1 | cut -d: -f1) )))" >&2
      bad=1
    fi
  done
done
[ $bad -eq 0 ] || { echo "Commit blocked: move it to design/local/ or scrub it (tools/docs/scrub_paths.py)." >&2; exit 1; }
