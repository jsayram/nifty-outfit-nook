#!/usr/bin/env bash
# Points git at the repo's hooks in .githooks (currently a gitleaks pre-commit hook).
# Run once per clone. Needs gitleaks: brew install gitleaks
set -euo pipefail
cd "$(dirname "$0")/.."

git config core.hooksPath .githooks
echo "Git hooks installed from .githooks"

if ! command -v gitleaks >/dev/null 2>&1; then
    echo "Warning: gitleaks is not installed, so commits will be stopped until it is." >&2
    echo "Install it with: brew install gitleaks" >&2
fi
