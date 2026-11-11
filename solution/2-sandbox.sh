#!/usr/bin/env bash
# Layer 5, the sandbox: generated code runs in an Agent Runtime sandbox instead
# of on this machine.
set -euo pipefail
cd "$(dirname "$0")/.."
cp solution/files/agent.sandbox.py spending_agent/agent.py
uv run python -W ignore -c "from spending_agent.agent import root_agent; print(root_agent.code_executor.agent_engine_resource_name)"
echo "Restart adk web so the agent loads the change."
