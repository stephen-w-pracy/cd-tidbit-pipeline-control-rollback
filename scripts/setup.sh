#!/usr/bin/env bash
#
# setup.sh — Provision the Pipeline Controls tidbit in your Harness account.
#
# Reads values from .env (copy .env.example → .env first), renders the
# templated YAML in .harness/, and creates everything via the Harness NG API:
# project (optional), secret, connectors, service, environments,
# infrastructures, pipeline, and input sets. Also prepares the cluster
# (namespaces + image pull secret) and installs a Harness Delegate via Helm.
#
# Re-runnable: existing resources are updated (PUT) rather than duplicated.
#
# Usage:
#   cp .env.example .env      # then fill in your values
#   ./scripts/setup.sh
#   ./scripts/setup.sh --dry-run   # print every API call and command; change nothing
#
set -euo pipefail

# --- Parse args ---
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    -h|--help)
      # Print only the leading header comment block (skip shebang, stop at the
      # first non-comment line).
      awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
      exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

# --- Locate repo root (script lives in scripts/) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HARNESS_DIR="$REPO_ROOT/.harness"

BASE_URL="${HARNESS_BASE_URL:-https://app.harness.io}"

# --- Output helpers ---
info()  { echo "  → $1"; }
ok()    { echo "  ✓ $1"; }
warn()  { echo "  ⚠ $1"; }
die()   { echo "  ✗ $1" >&2; exit 1; }
step()  { echo; echo "=== $1 ==="; }

# --- Load .env ---
[ -f "$REPO_ROOT/.env" ] || die ".env not found. Copy .env.example to .env and fill it in."
set -a
# shellcheck disable=SC1091
source "$REPO_ROOT/.env"
set +a

# --- Validate required vars ---
REQUIRED=(HARNESS_ACCOUNT_ID HARNESS_API_KEY HARNESS_ORG HARNESS_PROJECT \
          GITHUB_USERNAME GITHUB_REPO GITHUB_PAT DELEGATE_SELECTOR DELEGATE_NAME)
missing=()
for v in "${REQUIRED[@]}"; do
  [ -n "${!v:-}" ] || missing+=("$v")
done
[ ${#missing[@]} -eq 0 ] || die "Missing required .env values: ${missing[*]}"
CREATE_PROJECT="${CREATE_PROJECT:-true}"

if [ "$DRY_RUN" = true ]; then
  echo "### DRY RUN — no API calls, kubectl, or helm commands will be executed. ###"
fi

# --- Check dependencies ---
step "Checking dependencies"
for tool in curl envsubst kubectl helm jq yq; do
  command -v "$tool" &>/dev/null && ok "$tool" || die "$tool not found — please install it"
done

# Mask secret *values* before printing anything in dry-run mode. We redact the
# literal secrets themselves (not fields named "value" — target_envs uses that
# key and is not a secret).
redact() {
  sed -E "s|${GITHUB_PAT}|<GITHUB_PAT>|g; s|${HARNESS_API_KEY}|<HARNESS_API_KEY>|g"
}

# Variables exposed to envsubst. Restricting the list means Harness expressions
# like <+env.name> and ${anything-else} are left untouched.
export HARNESS_ACCOUNT_ID HARNESS_ORG HARNESS_PROJECT GITHUB_USERNAME \
       GITHUB_REPO GITHUB_PAT DELEGATE_SELECTOR
ENVSUBST_VARS='${HARNESS_ACCOUNT_ID} ${HARNESS_ORG} ${HARNESS_PROJECT} ${GITHUB_USERNAME} ${GITHUB_REPO} ${GITHUB_PAT} ${DELEGATE_SELECTOR}'

# Render a templated file to stdout (only our named vars are substituted).
render() { envsubst "$ENVSUBST_VARS" < "$1"; }

# The Harness NG API is not uniform about request bodies:
#   - /ng/api/connectors          wants JSON: the connector YAML converted to a
#                                 {"connector":{...}} object (raw YAML → HTTP 415).
#   - /ng/api/servicesV2,         want JSON: a flat object carrying the entity
#     environmentsV2, infrastructures   YAML as a "yaml" string field.
#   - /pipeline/api/* (pipeline,  accept raw YAML with Content-Type
#     input sets)                 application/yaml.
# These helpers build the first two shapes from a rendered template.

# render_connector_json <file> — convert rendered connector YAML to JSON.
render_connector_json() { render "$1" | yq -o=json; }

# render_entity_json <file> <key=value>... — wrap rendered entity YAML in the
# JSON envelope the CD endpoints expect (yaml field + top-level identifiers).
render_entity_json() {
  local file="$1"; shift
  local y; y="$(render "$file")"
  local args=(--arg yaml "$y")
  local filter='{yaml: $yaml'
  for kv in "$@"; do
    args+=(--arg "${kv%%=*}" "${kv#*=}")
    filter+=", ${kv%%=*}: \$${kv%%=*}"
  done
  filter+='}'
  jq -n "${args[@]}" "$filter"
}

# --- API helper ---------------------------------------------------------------
# api_send <method> <url> <content-type> <data>
# Echoes the HTTP status code to stderr (for logging) and the body to stdout.
api_send() {
  local method="$1" url="$2" ctype="$3" data="$4"
  if [ "$DRY_RUN" = true ]; then
    {
      echo "    curl -X $method '$url'"
      echo "      -H 'x-api-key: <REDACTED>' -H 'Content-Type: $ctype'"
      echo "      --data-binary <<<"
      printf '%s\n' "$data" | redact | sed 's/^/        /'
    } >&2
    # Emit a synthetic 200 so upsert reports success without a network call.
    printf '\n200'
    return 0
  fi
  curl -sS -X "$method" "$url" \
    -H "x-api-key: $HARNESS_API_KEY" \
    -H "Content-Type: $ctype" \
    -w $'\n%{http_code}' \
    --data-binary "$data"
}

# create_or_update <label> <create-method-url> <update-method-url> <ctype> <data>
# Tries to create; if the resource already exists, updates instead.
# Treats 2xx as success; "already exists"/409 triggers the update path.
upsert() {
  local label="$1" create_url="$2" update_url="$3" ctype="$4" data="$5"
  local resp code body
  resp="$(api_send POST "$create_url" "$ctype" "$data")"
  code="$(printf '%s' "$resp" | tail -n1)"
  body="$(printf '%s' "$resp" | sed '$d')"
  if [[ "$code" =~ ^2 ]]; then
    ok "$label created"
    return 0
  fi
  if [[ "$code" == "409" ]] || printf '%s' "$body" | grep -qi "already exists\|duplicate"; then
    resp="$(api_send PUT "$update_url" "$ctype" "$data")"
    code="$(printf '%s' "$resp" | tail -n1)"
    body="$(printf '%s' "$resp" | sed '$d')"
    if [[ "$code" =~ ^2 ]]; then
      ok "$label updated"
      return 0
    fi
  fi
  warn "$label failed (HTTP $code): $(printf '%s' "$body" | head -c 300)"
  return 1
}

ACCT="accountIdentifier=$HARNESS_ACCOUNT_ID"
ORG="orgIdentifier=$HARNESS_ORG"
PROJ="projectIdentifier=$HARNESS_PROJECT"

# --- Project ------------------------------------------------------------------
step "Harness project"
if [ "$CREATE_PROJECT" = "true" ]; then
  proj_body=$(cat <<JSON
{"project":{"identifier":"$HARNESS_PROJECT","name":"$HARNESS_PROJECT","orgIdentifier":"$HARNESS_ORG","modules":["CD","CI"]}}
JSON
)
  upsert "Project $HARNESS_PROJECT" \
    "$BASE_URL/ng/api/projects?$ACCT&$ORG" \
    "$BASE_URL/ng/api/projects/$HARNESS_PROJECT?$ACCT&$ORG" \
    "application/json" "$proj_body" || true
else
  info "CREATE_PROJECT=false — using existing $HARNESS_ORG/$HARNESS_PROJECT"
fi

# --- Cluster prep -------------------------------------------------------------
step "Cluster: namespaces and image pull secrets"
for ns in web-dev web-prod; do
  if [ "$DRY_RUN" = true ]; then
    info "would ensure namespace $ns"
    info "would create/apply secret ghcr-cred in $ns (docker-registry, server=ghcr.io, username=$GITHUB_USERNAME, password=<GITHUB_PAT>)"
    continue
  fi
  kubectl get ns "$ns" &>/dev/null && ok "namespace $ns exists" \
    || { kubectl create namespace "$ns" >/dev/null && ok "namespace $ns created"; }
  # imagePullSecret for private GHCR. --dry-run | apply makes it idempotent.
  kubectl create secret docker-registry ghcr-cred \
    --docker-server=ghcr.io \
    --docker-username="$GITHUB_USERNAME" \
    --docker-password="$GITHUB_PAT" \
    -n "$ns" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  ok "ghcr-cred secret ensured in $ns"
done

# --- Delegate -----------------------------------------------------------------
step "Harness Delegate (Helm)"
if [ "$DRY_RUN" = true ]; then
  info "would check for a running harness-delegate-ng pod; if none:"
  info "  GET $BASE_URL/ng/api/delegate-token-ng?$ACCT&name=default_token  (to read delegate token)"
  info "  helm upgrade --install harness-delegate harness-delegate/harness-delegate-ng \\"
  info "    --namespace harness-delegate --create-namespace --set delegateName=$DELEGATE_NAME \\"
  info "    --set accountId=$HARNESS_ACCOUNT_ID --set delegateToken=<REDACTED> \\"
  info "    --set managerEndpoint=$BASE_URL --set delegateCustomTags=$DELEGATE_SELECTOR"
elif kubectl get pods -A -l "harness.io/name=$DELEGATE_NAME" --field-selector=status.phase=Running 2>/dev/null | grep -q "$DELEGATE_NAME"; then
  ok "a Harness delegate '$DELEGATE_NAME' is already running — skipping install"
else
  info "fetching default delegate token"
  tok_resp="$(curl -sS "$BASE_URL/ng/api/delegate-token-ng?$ACCT&name=default_token" \
    -H "x-api-key: $HARNESS_API_KEY")"
  DELEGATE_TOKEN="$(printf '%s' "$tok_resp" | grep -o '"value":"[^"]*"' | head -n1 | sed 's/"value":"//;s/"//')"
  [ -n "$DELEGATE_TOKEN" ] || die "Could not read default delegate token value. Ensure your API key has delegate-edit permission, or install the delegate manually (see README)."

  helm repo add harness-delegate https://app.harness.io/storage/harness-download/delegate-helm-chart/ >/dev/null 2>&1 || true
  helm repo update harness-delegate >/dev/null 2>&1 || true
  # The Harness delegate-upgrader sidecar takes ownership of the container
  # image field once the delegate self-updates, so subsequent helm upgrades
  # report a field-manager conflict. --force re-applies cleanly in that case.
  if ! helm upgrade --install harness-delegate harness-delegate/harness-delegate-ng \
      --namespace harness-delegate --create-namespace --force \
      --set delegateName="$DELEGATE_NAME" \
      --set accountId="$HARNESS_ACCOUNT_ID" \
      --set delegateToken="$DELEGATE_TOKEN" \
      --set managerEndpoint="$BASE_URL" \
      --set "delegateCustomTags=$DELEGATE_SELECTOR" >/dev/null 2>&1; then
    warn "helm upgrade failed — if a delegate is already running, this is usually safe to ignore. Check 'helm list -n harness-delegate' and 'kubectl get pods -n harness-delegate'."
  else
    ok "delegate installed (tag: $DELEGATE_SELECTOR) — it may take a minute to register"
  fi
fi

# --- Secret -------------------------------------------------------------------
step "Harness resources"
# Secrets need a JSON body; build it directly rather than from the YAML template.
secret_json=$(cat <<JSON
{"secret":{"type":"SecretText","name":"ghcr_token","identifier":"ghcr_token","orgIdentifier":"$HARNESS_ORG","projectIdentifier":"$HARNESS_PROJECT","spec":{"secretManagerIdentifier":"harnessSecretManager","valueType":"Inline","value":"$GITHUB_PAT","type":"SecretText"}}}
JSON
)
upsert "Secret ghcr_token" \
  "$BASE_URL/ng/api/v2/secrets?$ACCT&$ORG&$PROJ" \
  "$BASE_URL/ng/api/v2/secrets/ghcr_token?$ACCT&$ORG&$PROJ" \
  "application/json" "$secret_json"

# Connectors: JSON body ({"connector":{...}}), built from the YAML template.
for c in connector-github connector-ghcr connector-k8s; do
  upsert "Connector $c" \
    "$BASE_URL/ng/api/connectors?$ACCT" \
    "$BASE_URL/ng/api/connectors?$ACCT" \
    "application/json" \
    "$(render_connector_json "$HARNESS_DIR/$c.yaml")"
done

# Service / Environments / Infrastructures: JSON envelope carrying the entity
# YAML as a "yaml" string field, alongside the top-level identifiers.
upsert "Service pipeline-controls-demo" \
  "$BASE_URL/ng/api/servicesV2?$ACCT" \
  "$BASE_URL/ng/api/servicesV2?$ACCT" \
  "application/json" \
  "$(render_entity_json "$HARNESS_DIR/service.yaml" \
      identifier=pipelinecontrolsdemo name=pipeline-controls-demo \
      orgIdentifier="$HARNESS_ORG" projectIdentifier="$HARNESS_PROJECT")"

for e in dev:Dev:PreProduction prod:Prod:Production; do
  file="environment-${e%%:*}"; id="$(echo "$e" | cut -d: -f2)"; etype="${e##*:}"
  upsert "Environment $id" \
    "$BASE_URL/ng/api/environmentsV2?$ACCT" \
    "$BASE_URL/ng/api/environmentsV2?$ACCT" \
    "application/json" \
    "$(render_entity_json "$HARNESS_DIR/$file.yaml" \
        identifier="$id" name="$id" type="$etype" \
        orgIdentifier="$HARNESS_ORG" projectIdentifier="$HARNESS_PROJECT")"
done

for i in dev:Dev_Infra:Dev prod:Prod_Infra:Prod; do
  file="infra-${i%%:*}"; id="$(echo "$i" | cut -d: -f2)"; envref="${i##*:}"
  upsert "Infrastructure $id" \
    "$BASE_URL/ng/api/infrastructures?$ACCT" \
    "$BASE_URL/ng/api/infrastructures?$ACCT" \
    "application/json" \
    "$(render_entity_json "$HARNESS_DIR/$file.yaml" \
        identifier="$id" name="$id" type=KubernetesDirect environmentRef="$envref" \
        orgIdentifier="$HARNESS_ORG" projectIdentifier="$HARNESS_PROJECT")"
done

upsert "Pipeline pipeline_controls_exemplar" \
  "$BASE_URL/pipeline/api/pipelines/v2?$ACCT&$ORG&$PROJ" \
  "$BASE_URL/pipeline/api/pipelines/v2/pipeline_controls_exemplar?$ACCT&$ORG&$PROJ" \
  "application/yaml" "$(render "$HARNESS_DIR/pipeline.yaml")"

PIPE="pipelineIdentifier=pipeline_controls_exemplar"
for is in dev-only:dev_only full-release:full_release; do
  file="${is%%:*}"; id="${is##*:}"
  upsert "Input Set $file" \
    "$BASE_URL/pipeline/api/inputSets?$ACCT&$ORG&$PROJ&$PIPE" \
    "$BASE_URL/pipeline/api/inputSets/$id?$ACCT&$ORG&$PROJ&$PIPE" \
    "application/yaml" "$(render "$HARNESS_DIR/inputsets/$file.yaml")"
done

# --- Done ---------------------------------------------------------------------
step "Done"
echo "Resources provisioned in project '$HARNESS_PROJECT' (org '$HARNESS_ORG')."
echo
echo "Next steps:"
echo "  1. Wait for the delegate to show 'Connected' in Harness (Project Settings → Delegates)."
echo "  2. Run the pipeline with the 'Dev Only' input set, then 'Full Release'."
echo "  3. See the README 'Run the Demo' section for the full golden path."
