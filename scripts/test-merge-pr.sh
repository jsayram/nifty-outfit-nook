#!/usr/bin/env bash
# Tests the stale-base guard in merge-pr.sh with a fake `gh`. Never touches GitHub.
# Usage: scripts/test-merge-pr.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/gh" <<'STUB'
#!/usr/bin/env bash
# Fake gh. Scenario comes from $FAKE_STATUS (compare status) and $FAKE_HEAD2 (head after the CI wait).
case "$1 $2" in
  "pr view") n=$(cat "$FAKE_DIR/n" 2>/dev/null || echo 0); echo $((n+1)) > "$FAKE_DIR/n"
             if [[ $n -eq 0 ]]; then echo "develop aaaa1111"; else echo "develop ${FAKE_HEAD2:-aaaa1111}"; fi ;;
  "pr checks") echo "all checks passed" ;;
  "api repos/{owner}/{repo}/git/ref/heads/develop") echo "bbbb2222" ;;
  "api repos/{owner}/{repo}/compare/bbbb2222...aaaa1111") echo "${FAKE_STATUS:-ahead}" ;;
  "api --method") echo "MERGE CALLED" >> "$FAKE_DIR/merged"; echo "Pull Request successfully merged" ;;
  *) echo "unexpected gh call: $*" >&2; exit 99 ;;
esac
STUB
chmod +x "$tmp/gh"

run() { # name, expected exit, expected text, env...
  local name="$1" want="$2" text="$3"; shift 3
  rm -f "$tmp/n" "$tmp/merged"
  set +e; out="$(env PATH="$tmp:$PATH" FAKE_DIR="$tmp" "$@" "$here/merge-pr.sh" --dry-run 7 2>&1)"; code=$?; set -e
  if [[ $code -eq $want && "$out" == *"$text"* && ! -e "$tmp/merged" ]]; then echo "PASS: $name"
  else echo "FAIL: $name (exit $code)"; echo "$out"; exit 1; fi
}

run "up to date passes"        0 "Dry run: PR #7 is up to date"  FAKE_STATUS=ahead
run "identical passes"         0 "Dry run: PR #7 is up to date"  FAKE_STATUS=identical
run "stale base refused"       1 "develop moved: merge origin/develop into your branch, push, and wait for CI." FAKE_STATUS=diverged
run "behind base refused"      1 "develop moved: merge origin/develop into your branch, push, and wait for CI." FAKE_STATUS=behind
run "head changed during CI"   1 "the head changed"              FAKE_STATUS=ahead FAKE_HEAD2=cccc3333
echo "All merge-pr.sh guard tests passed."
