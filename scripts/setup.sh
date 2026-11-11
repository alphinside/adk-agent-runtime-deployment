#!/usr/bin/env bash
# Pre-work for the lab. Run it once, at least 15 minutes before the session:
# it waits for the first Agent Runtime deploy, which takes 5 to 10 minutes,
# then warms up the code sandbox. Safe to rerun; rerunning also resets the data.
set -euo pipefail
cd "$(dirname "$0")/.."

[[ -f .env ]] || { echo "No .env here. Create it first (see .env.example)." >&2; exit 1; }
set -a; source .env; set +a
: "${GOOGLE_CLOUD_PROJECT:?Set GOOGLE_CLOUD_PROJECT in .env}"
: "${REGION:?Set REGION in .env}"
P=$GOOGLE_CLOUD_PROJECT
TOOLBOX_SA="toolbox-sa@$P.iam.gserviceaccount.com"
TOOLBOX_SERVICE=wallet-toolbox
TOOLBOX_SECRET=wallet-toolbox-tools
TOOLBOX_IMAGE=us-central1-docker.pkg.dev/database-toolbox/toolbox/toolbox:1.12.0

# A new service account can take a moment before IAM accepts it in a binding.
retry() { for _ in 1 2 3 4 5 6; do "$@" && return; sleep 10; done; return 1; }

echo "[1/5] Agents CLI: checking the version"
echo "  $(command -v agents-cli || echo 'agents-cli: not found')"
version=$(agents-cli --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)
if [[ $version != 1.12.* ]]; then
  echo "This lab needs Agents CLI 1.12.x; this shell runs '${version:-none}'." >&2
  echo "Cloud Shell ships 1.12.0, but an older copy in ~/.local/bin comes first on PATH. Remove it with:" >&2
  echo "  uv tool uninstall google-agents-cli && hash -r" >&2
  exit 1
fi
echo "  version $version"

echo
echo "[2/5] APIs: enabling the nine the lab uses"
gcloud services enable \
  aiplatform.googleapis.com \
  bigquery.googleapis.com \
  cloudresourcemanager.googleapis.com \
  cloudtrace.googleapis.com \
  iam.googleapis.com \
  logging.googleapis.com \
  run.googleapis.com \
  secretmanager.googleapis.com \
  telemetry.googleapis.com \
  --project="$P"

echo
echo "[3/5] Data: wallet_insights for the agent, wallet_risk that nothing may read"
for dataset in wallet_insights wallet_risk; do
  bq --project_id="$P" mk --force --location="$REGION" --dataset "$dataset" >/dev/null
done
bq --project_id="$P" --location="$REGION" query --nouse_legacy_sql --quiet <data/seed.sql >/dev/null

echo
echo "[4/5] MCP Toolbox: toolbox-sa, a private copy on Cloud Run, a local copy for modules 0 to 3"
echo "  Service account toolbox-sa: runs BigQuery jobs, reads wallet_insights only"
gcloud iam service-accounts describe "$TOOLBOX_SA" --project="$P" &>/dev/null ||
  gcloud iam service-accounts create toolbox-sa --project="$P" \
    --display-name="MCP Toolbox for the spending-insights lab" >/dev/null
retry gcloud projects add-iam-policy-binding "$P" --member="serviceAccount:$TOOLBOX_SA" \
  --role=roles/bigquery.jobUser --condition=None --quiet >/dev/null
# A DCL grant, because dataset-level `bq add-iam-policy-binding` is not
# available in every project.
retry bq --project_id="$P" --location="$REGION" query --nouse_legacy_sql --quiet \
  "GRANT \`roles/bigquery.dataViewer\` ON SCHEMA \`$P.wallet_insights\` TO \"serviceAccount:$TOOLBOX_SA\"" >/dev/null

echo "  Cloud Run service $TOOLBOX_SERVICE: private, runs as toolbox-sa, for the deployed agent"
# Cloud Run mounts tools.yaml from Secret Manager. Nothing in it is secret.
if gcloud secrets describe "$TOOLBOX_SECRET" --project="$P" &>/dev/null; then
  gcloud secrets versions add "$TOOLBOX_SECRET" --project="$P" \
    --data-file=mcp-toolbox/tools.yaml >/dev/null
else
  gcloud secrets create "$TOOLBOX_SECRET" --project="$P" \
    --replication-policy=automatic --data-file=mcp-toolbox/tools.yaml >/dev/null
fi
retry gcloud secrets add-iam-policy-binding "$TOOLBOX_SECRET" --project="$P" \
  --member="serviceAccount:$TOOLBOX_SA" --role=roles/secretmanager.secretAccessor \
  --condition=None --quiet >/dev/null
gcloud run deploy "$TOOLBOX_SERVICE" --project="$P" --region="$REGION" \
  --image="$TOOLBOX_IMAGE" \
  --service-account="$TOOLBOX_SA" \
  --no-allow-unauthenticated \
  --set-secrets="/app/tools.yaml=$TOOLBOX_SECRET:latest" \
  --set-env-vars="GOOGLE_CLOUD_PROJECT=$P,REGION=$REGION" \
  --args="--config=/app/tools.yaml,--address=0.0.0.0,--port=8080" \
  --quiet
TOOLBOX_CLOUD_URL=$(gcloud run services describe "$TOOLBOX_SERVICE" --project="$P" \
  --region="$REGION" --format='value(status.url)')

echo "  Local copy on 127.0.0.1:5000, runs as you, for adk web in modules 0 to 3"
uv sync --quiet
scripts/toolbox.sh start

echo
echo "[5/5] Agent Runtime: the instance spending-insights, with its own Agent Identity"
if [[ -n $(jq -r '.remote_agent_runtime_id // empty' deployment_metadata.json) ]]; then
  echo "  The agent is already deployed. Skipping the first deploy."
else
  agents-cli deploy --project="$P" --no-confirm-project --agent-identity \
    --update-env-vars="TOOLBOX_URL=$TOOLBOX_CLOUD_URL"
fi
# Warmed here so module 2's first code run does not wait for it.
if [[ ! -f .sandbox-warm ]]; then
  echo "  Code sandbox: warming one up, about 2 minutes the first time in a project"
  uv run python scripts/engine.py warm ||
    { echo "Could not run code in an Agent Runtime sandbox. Rerun scripts/setup.sh." >&2; exit 1; }
  touch .sandbox-warm
fi

cat <<'SUMMARY'

What setup created, and where the lab uses it:
  wallet_insights            the agent's data, read through MCP Toolbox in every module
  wallet_risk                data nothing may read; module 4 checks that toolbox-sa can't
  toolbox-sa                 MCP Toolbox's own identity, reads wallet_insights only
  wallet-toolbox             private MCP Toolbox on Cloud Run; the agent calls it from module 4
  Toolbox on 127.0.0.1:5000  runs as you, for adk web in modules 0 to 3
  spending-insights          Agent Runtime instance with its own Agent Identity; module 2's
                             sandbox runs under it, module 4 deploys into it

Setup is done. Run scripts/check.sh to confirm, then uv run adk web.
SUMMARY
