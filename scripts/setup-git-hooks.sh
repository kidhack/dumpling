#!/usr/bin/env bash
# Install Git hooks that block pushes containing secrets.
# Run after: git init
# Usage: ./scripts/setup-git-hooks.sh

cd "$(git rev-parse --show-toplevel)" || exit 1
git config core.hooksPath .githooks
echo "Git hooks installed. Pushes with .env or secrets will be blocked."
