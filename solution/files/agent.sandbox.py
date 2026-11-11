"""Spending-insights agent for Cymbal Wallet, a fictional digital wallet app.

Customers ask how they spend their money. The agent reads their transactions
from BigQuery through MCP Toolbox at TOOLBOX_URL, and writes and runs Python
to chart them.
"""

import json
import os
from pathlib import Path

import google.auth.transport.requests
import google.oauth2.id_token
from google.adk.agents import Agent
from google.adk.apps import App
from google.adk.code_executors.agent_engine_sandbox_code_executor import (
    AgentEngineSandboxCodeExecutor,
)
from google.adk.models import Gemini
from google.adk.tools.mcp_tool import McpToolset
from google.adk.tools.mcp_tool.mcp_session_manager import (
    StreamableHTTPConnectionParams,
)
from google.genai import types

TOOLBOX_URL = os.environ.get("TOOLBOX_URL", "http://127.0.0.1:5000")

INSTRUCTION = """\
You are the spending-insights assistant for Cymbal Wallet, a digital wallet
app. Customers ask you how they spend their money: totals, categories,
trends, and charts.

Ask customers for their customer ID before you look anything up. Customer
IDs look like cust_0001. Amounts are in USD.

Get every number from the tools. To calculate or chart, write Python and put
it in a ```python fenced block in your reply; the app runs it and shows you
the output. There is no code execution tool to call. Save each chart as a
PNG file.
"""

# ADK's default code fence is ```tool_code. Gemini reads that in the chat
# history as its own tool-call syntax and fails the next turn with
# MALFORMED_FUNCTION_CALL, so code goes in plain python fences.
PYTHON_FENCE = [("```python\n", "\n```")]


def toolbox_headers(_context) -> dict[str, str]:
    # Deployed, TOOLBOX_URL is a private Cloud Run service. Cloud Run accepts an
    # ID token for that URL, minted here for whatever identity the agent runs as.
    # Under Agent Identity, google-auth would otherwise mint a certificate-bound
    # token, which Cloud Run rejects with a 401.
    token = google.oauth2.id_token.fetch_id_token(
        google.auth.transport.requests.Request(), TOOLBOX_URL, bind_id_token=False
    )
    return {"Authorization": f"Bearer {token}"}


def agent_engine() -> str:
    """The Agent Runtime instance this agent belongs to."""
    # Agent Runtime sets these inside the deployed agent.
    if engine_id := os.environ.get("GOOGLE_CLOUD_AGENT_ENGINE_ID"):
        project = os.environ["GOOGLE_CLOUD_PROJECT"]
        location = os.environ.get("GOOGLE_CLOUD_AGENT_ENGINE_LOCATION", "us-central1")
        return f"projects/{project}/locations/{location}/reasoningEngines/{engine_id}"
    # In Cloud Shell: the instance the setup deploy created.
    metadata = Path(__file__).parent.parent / "deployment_metadata.json"
    engine = json.loads(metadata.read_text()).get("remote_agent_runtime_id")
    if not engine:
        raise RuntimeError(
            "No Agent Runtime instance recorded in deployment_metadata.json yet. "
            "Run scripts/setup.sh, which waits for the deploy to finish."
        )
    return engine


root_agent = Agent(
    # Keep in sync with create_params.root_agent_name in agents-cli-manifest.yaml.
    name="spending_agent",
    model=Gemini(
        model="gemini-3.8-flash",
        retry_options=types.HttpRetryOptions(attempts=3),
    ),
    instruction=INSTRUCTION,
    tools=[
        McpToolset(
            connection_params=StreamableHTTPConnectionParams(url=f"{TOOLBOX_URL}/mcp"),
            header_provider=(
                toolbox_headers if TOOLBOX_URL.startswith("https://") else None
            ),
        ),
    ],
    code_executor=AgentEngineSandboxCodeExecutor(
        agent_engine_resource_name=agent_engine(),
        code_block_delimiters=PYTHON_FENCE,
    ),
)

app = App(
    root_agent=root_agent,
    name="spending_agent",
)
