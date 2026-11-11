#!/usr/bin/env bash
# Add a skill: the spending-report skill and the toolset that loads it.
# Includes module 2's change.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p spending_agent/skills
cp -r solution/files/skills/spending-report spending_agent/skills/
cp solution/files/agent.skill.py spending_agent/agent.py
uv run python -W ignore -c "from spending_agent.agent import root_agent; print([type(t).__name__ for t in root_agent.tools])"
echo "Restart adk web so the agent loads the change."
