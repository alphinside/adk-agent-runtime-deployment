#!/usr/bin/env bash
# Checks that the lab is ready and names anything that is missing.
#
# Once the setup deploy finishes, the first run records it in 
# deployment_metadata.json and warms up the code sandbox
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

if [[ ! -f .env ]]; then
  echo "NOT READY: no .env file in $(pwd)."
  exit 1
fi
set -a; source .env; set +a
P=$GOOGLE_CLOUD_PROJECT
problems=()

version=$(agents-cli --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)
[[ $version == 1.12.* ]] ||
  problems+=("agents-cli resolves to '${version:-nothing}' at $(command -v agents-cli), not 1.12.x. Run: uv tool uninstall google-agents-cli && hash -r")

enabled=$(gcloud services list --enabled --project="$P" --format='value(config.name)' 2>/dev/null)
for api in aiplatform bigquery cloudresourcemanager cloudtrace iam logging run secretmanager telemetry; do
  grep -qx "$api.googleapis.com" <<<"$enabled" ||
    problems+=("API $api.googleapis.com is not enabled. Run scripts/setup.sh.")
done

for dataset in wallet_insights wallet_risk; do
  bq --project_id="$P" show "$dataset" &>/dev/null ||
    problems+=("BigQuery dataset $dataset is missing. Run scripts/setup.sh.")
done

[[ -n $(gcloud run services describe wallet-toolbox --project="$P" --region="$REGION" \
  --format='value(status.latestReadyRevisionName)' 2>/dev/null) ]] ||
  problems+=("The MCP Toolbox service wallet-toolbox is not ready on Cloud Run. Run scripts/setup.sh.")

reply=$(curl -s -X POST "http://127.0.0.1:5000/mcp" -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_monthly_spending","arguments":{"customer_id":"cust_0001","month":"2026-10"}}}')
if [[ -z $reply ]]; then
  problems+=("MCP Toolbox is not answering on 127.0.0.1:5000. Run scripts/toolbox.sh start.")
elif ! grep -q groceries <<<"$reply"; then
  problems+=("MCP Toolbox answered, but could not read BigQuery: ${reply:0:300}")
fi

engine=$(jq -r '.remote_agent_runtime_id // empty' deployment_metadata.json)
if [[ -z $engine ]]; then
  # Finishes a deploy started with --no-wait, or says it is still running.
  agents-cli deploy --status --project="$P" --no-confirm-project
  engine=$(jq -r '.remote_agent_runtime_id // empty' deployment_metadata.json)
fi
if [[ -z $engine ]]; then
  problems+=("The agent is not deployed yet. Wait a few minutes and run scripts/check.sh again.")
else
  if [[ ! -f .sandbox-warm ]]; then
    echo "Warming up the code sandbox. The first one in a project takes about 2 minutes..."
    if uv run python scripts/engine.py warm; then
      touch .sandbox-warm
    else
      problems+=("Could not run code in an Agent Runtime sandbox under $engine.")
    fi
  fi
  url="https://$REGION-aiplatform.googleapis.com/reasoningEngines/v1/$engine/api"
  # The agent scales to zero, and the first request after that can time out.
  answered=
  for _ in 1 2 3; do
    answer=$(agents-cli run "Say hello in five words." --mode adk --url "$url" 2>&1) && { answered=yes; break; }
    sleep 20
  done
  [[ -n $answered ]] ||
    problems+=("The deployed agent did not answer. Just after a deploy it can take about 4 minutes to start. ${answer: -300}")
fi

if (( ${#problems[@]} )); then
  echo "NOT READY:"
  printf '  - %s\n' "${problems[@]}"
  exit 1
fi
echo "READY"
