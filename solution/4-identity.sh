#!/usr/bin/env bash
# Layer 1, the agent's own identity: deploys the agent in place, lets its
# principal invoke the MCP Toolbox service and nothing else, and removes the
# project-wide roles/aiplatform.user that the first deploy granted.
# Run 3-skill.sh first if your agent is not at the end of module 3.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a
P=$GOOGLE_CLOUD_PROJECT

TOOLBOX_URL=$(gcloud run services describe wallet-toolbox --project="$P" --region="$REGION" \
  --format='value(status.url)')
# agents-cli resets the two content variables on every deploy, so pass all three each time.
agents-cli deploy --project="$P" --no-confirm-project \
  --update-env-vars="TOOLBOX_URL=$TOOLBOX_URL,OTEL_SEMCONV_STABILITY_OPT_IN=gen_ai_latest_experimental,ADK_CAPTURE_MESSAGE_CONTENT_IN_SPANS=true,OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT=SPAN_AND_EVENT"

PRINCIPAL=$(uv run python scripts/engine.py principal)
echo "Agent Identity: $PRINCIPAL"
gcloud run services add-iam-policy-binding wallet-toolbox --project="$P" --region="$REGION" \
  --member="$PRINCIPAL" --role=roles/run.invoker --quiet >/dev/null
if gcloud projects get-iam-policy "$P" --flatten='bindings[].members' \
  --filter="bindings.members:$PRINCIPAL AND bindings.role:roles/aiplatform.user" \
  --format='value(bindings.role)' | grep -q .; then
  gcloud projects remove-iam-policy-binding "$P" --member="$PRINCIPAL" \
    --role=roles/aiplatform.user --condition=None --quiet >/dev/null
fi
echo "Granted roles/run.invoker on wallet-toolbox and removed roles/aiplatform.user."
echo "Grants take 2 to 3 minutes to apply. Waiting 3 minutes..."
sleep 180
echo "Done. Ask the deployed agent a spending question."
