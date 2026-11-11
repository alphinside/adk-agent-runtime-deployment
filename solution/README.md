# Solution

Everything the codelab changes, one script per module. If a module goes wrong, run its script from the folder that holds `pyproject.toml`, and carry on. Every script is safe to rerun.

| Module | Run | What it does |
|---|---|---|
| The sandbox | `solution/2-sandbox.sh` | Swaps `UnsafeLocalCodeExecutor` for `AgentEngineSandboxCodeExecutor` in `spending_agent/agent.py` |
| Add a skill | `solution/3-skill.sh` | Adds `spending_agent/skills/spending-report/` and the `SkillToolset` that loads it. Includes module 2 |
| The agent's own identity | `solution/4-identity.sh` | Deploys the agent in place, grants its principal `roles/run.invoker` on `wallet-toolbox`, removes its `roles/aiplatform.user`, and waits 3 minutes for the grants to apply |

Modules 1 and 5 change no files. Module 5 reads traces that module 4's deploy already records with their content.

After 2 or 3, restart `adk web`. Run `4-identity.sh` only once your agent is at the end of module 3.

`files/` holds the finished files the scripts copy:

| File | Becomes |
|---|---|
| `files/agent.sandbox.py` | `spending_agent/agent.py` after module 2 |
| `files/agent.skill.py` | `spending_agent/agent.py` after module 3 |
| `files/skills/spending-report/` | `spending_agent/skills/spending-report/` |
