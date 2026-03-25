#!/usr/bin/env bash
# Run the Dumpling agent. Must be run from project root (agent uses relative imports).
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
# Use agent's venv if it exists
if [ -f "$ROOT/agent/.venv/bin/activate" ]; then
  source "$ROOT/agent/.venv/bin/activate"
fi
python -m agent.main
