#!/usr/bin/env bash
# Deletes what this lab created in your project
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
set -a; source .env; set +a
P=$GOOGLE_CLOUD_PROJECT
TOOLBOX_SA="toolbox-sa@$P.iam.gserviceaccount.com"

scripts/toolbox.sh stop

# A deploy started with --no-wait is only recorded once its status is checked.
[[ -n $(jq -r '.remote_agent_runtime_id // empty' deployment_metadata.json) ]] ||
  agents-cli deploy --status --project="$P" --no-confirm-project 2>/dev/null

if [[ -n $(jq -r '.remote_agent_runtime_id // empty' deployment_metadata.json) ]]; then
  # Read the principal first: deleting the agent does not remove its project
  # bindings, and afterwards nothing names the principal any more.
  principal=$(uv run python scripts/engine.py principal)
  echo "Deleting the agent, with its sandboxes and sessions..."
  uv run python scripts/engine.py delete
  if [[ $principal == principal://* ]]; then
    for role in $(gcloud projects get-iam-policy "$P" --flatten='bindings[].members' \
      --filter="bindings.members:$principal" --format='value(bindings.role)'); do
      gcloud projects remove-iam-policy-binding "$P" --member="$principal" \
        --role="$role" --condition=None --quiet >/dev/null && echo "Removed $role from the agent's principal."
    done
  fi
  printf '{\n  "remote_agent_runtime_id": null,\n  "deployment_timestamp": null\n}\n' >deployment_metadata.json
fi
rm -f .sandbox-warm

gcloud run services delete wallet-toolbox --project="$P" --region="$REGION" --quiet
gcloud secrets delete wallet-toolbox-tools --project="$P" --quiet
# Remove the project binding before the account, or it stays behind as deleted:serviceAccount.
gcloud projects remove-iam-policy-binding "$P" --member="serviceAccount:$TOOLBOX_SA" \
  --role=roles/bigquery.jobUser --condition=None --quiet >/dev/null
gcloud iam service-accounts delete "$TOOLBOX_SA" --project="$P" --quiet

for dataset in wallet_insights wallet_risk; do
  bq --project_id="$P" rm -r -f -d "$dataset"
done
