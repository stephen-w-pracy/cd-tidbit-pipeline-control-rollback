#!/usr/bin/env bash
#
# cleanup.sh — Tear down everything setup.sh created.
#
# Deletes (in this order, reverse-dependency):
#   1. Harness pipeline + input sets
#   2. Harness infrastructures, environments, service
#   3. Harness connectors and secret
#   4. Harness project (catches anything missed by 1–3)
#   5. Cluster namespaces (web-dev, web-prod) — cascades to deployments,
#      services, configmaps, the ghcr-cred imagePullSecret, etc.
#   6. Harness Delegate — `helm uninstall` + delete `harness-delegate` namespace
#   7. GHCR package `pipeline-controls-demo` (all versions)
#
# Re-runnable: missing resources are skipped, not errored.
#
# Usage:
#   ./scripts/cleanup.sh --dry-run    # preview every DELETE; change nothing
#   ./scripts/cleanup.sh -y           # skip the confirmation prompt
#   ./scripts/cleanup.sh              # interactive confirm
#
set -euo pipefail

# --- Parse args ---
DRY_RUN=false
ASSUME_YES=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    -y|--yes)  ASSUME_YES=true ;;
    -h|--help)
      awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
      exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

# --- Locate repo root ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BASE_URL="${HARNESS_BASE_URL:-https://app.harness.io}"

# --- Output helpers (matches setup.sh) ---
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
          GITHUB_USERNAME GITHUB_PAT DELEGATE_NAME)
missing=()
for v in "${REQUIRED[@]}"; do
  [ -n "${!v:-}" ] || missing+=("$v")
done
[ ${#missing[@]} -eq 0 ] || die "Missing required .env values: ${missing[*]}"

if [ "$DRY_RUN" = true ]; then
  echo "### DRY RUN — no DELETE calls or destructive commands will be executed. ###"
fi

# Redact the same literal secrets setup.sh redacts (PAT + API key).
redact() {
  sed -E "s|${GITHUB_PAT}|<GITHUB_PAT>|g; s|${HARNESS_API_KEY}|<HARNESS_API_KEY>|g"
}

# --- Confirmation ---
if [ "$ASSUME_YES" != true ] && [ "$DRY_RUN" != true ]; then
  echo
  echo "About to DELETE the following:"
  echo "  • Harness project '$HARNESS_PROJECT' in org '$HARNESS_ORG' (account $HARNESS_ACCOUNT_ID)"
  echo "    — and every connector, service, environment, infra, pipeline, input set, secret in it"
  echo "  • Cluster namespaces: web-dev, web-prod (all resources inside)"
  echo "  • Harness Delegate '$DELEGATE_NAME' (helm uninstall + namespace delete)"
  echo "  • GHCR package: pipeline-controls-demo (all versions)"
  echo
  read -r -p "Type 'yes' to proceed: " reply
  [ "$reply" = "yes" ] || die "Aborted."
fi

# --- Harness API helper ---
# api_delete <label> <url>
# Treats 2xx and 404 as success (404 = already gone).
api_delete() {
  local label="$1" url="$2"
  if [ "$DRY_RUN" = true ]; then
    {
      echo "    curl -X DELETE '$url'"
      echo "      -H 'x-api-key: <REDACTED>'"
    } | redact >&2
    info "(dry-run) $label"
    return 0
  fi
  local resp code
  resp="$(curl -sS -X DELETE "$url" \
    -H "x-api-key: $HARNESS_API_KEY" \
    -w $'\n%{http_code}')"
  code="$(printf '%s' "$resp" | tail -n1)"
  if [[ "$code" =~ ^2 ]]; then
    ok "$label deleted"
  elif [[ "$code" == "404" ]]; then
    info "$label not found (skipped)"
  else
    warn "$label DELETE returned HTTP $code"
  fi
}

ACCT="accountIdentifier=$HARNESS_ACCOUNT_ID"
ORG="orgIdentifier=$HARNESS_ORG"
PROJ="projectIdentifier=$HARNESS_PROJECT"

# --- 1. Pipeline + input sets ----------------------------------------------
step "Harness pipeline & input sets"
PIPE="pipelineIdentifier=pipelinecontrols"
for is in dev_only full_release; do
  api_delete "Input set $is" \
    "$BASE_URL/pipeline/api/inputSets/$is?$ACCT&$ORG&$PROJ&$PIPE"
done
api_delete "Pipeline pipelinecontrols" \
  "$BASE_URL/pipeline/api/pipelines/pipelinecontrols?$ACCT&$ORG&$PROJ"

# --- 2. Infrastructures, environments, service -----------------------------
step "Harness infra, environments, service"
for i in Dev_Infra:Dev Prod_Infra:Prod; do
  id="${i%%:*}"; envref="${i##*:}"
  api_delete "Infrastructure $id" \
    "$BASE_URL/ng/api/infrastructures/$id?$ACCT&$ORG&$PROJ&environmentIdentifier=$envref"
done
for envid in Dev Prod; do
  api_delete "Environment $envid" \
    "$BASE_URL/ng/api/environmentsV2/$envid?$ACCT&$ORG&$PROJ"
done
api_delete "Service pipelinecontrolsdemo" \
  "$BASE_URL/ng/api/servicesV2/pipelinecontrolsdemo?$ACCT&$ORG&$PROJ"

# --- 3. Connectors & secret ------------------------------------------------
step "Harness connectors & secret"
# Includes both the new identifiers and the legacy ones in case they linger.
for c in pipelinedemocluster pipelinedemoghcr github k8scluster ghcr; do
  api_delete "Connector $c" \
    "$BASE_URL/ng/api/connectors/$c?$ACCT&$ORG&$PROJ"
done
api_delete "Secret ghcr_token" \
  "$BASE_URL/ng/api/v2/secrets/ghcr_token?$ACCT&$ORG&$PROJ"

# --- 4. Project -----------------------------------------------------------
step "Harness project"
api_delete "Project $HARNESS_PROJECT" \
  "$BASE_URL/ng/api/projects/$HARNESS_PROJECT?$ACCT&$ORG"

# --- 5. Cluster namespaces ------------------------------------------------
step "Cluster namespaces"
for ns in web-dev web-prod; do
  if [ "$DRY_RUN" = true ]; then
    info "would: kubectl delete namespace $ns --ignore-not-found"
    continue
  fi
  if kubectl get ns "$ns" &>/dev/null; then
    kubectl delete namespace "$ns" --wait=false >/dev/null
    ok "namespace $ns delete initiated"
  else
    info "namespace $ns not found"
  fi
done

# --- 6. Harness Delegate --------------------------------------------------
step "Harness Delegate"
if [ "$DRY_RUN" = true ]; then
  info "would: helm uninstall harness-delegate -n harness-delegate"
  info "would: kubectl delete namespace harness-delegate --ignore-not-found"
else
  if helm status harness-delegate -n harness-delegate &>/dev/null; then
    helm uninstall harness-delegate -n harness-delegate >/dev/null 2>&1 \
      && ok "helm release harness-delegate uninstalled" \
      || warn "helm uninstall failed (release may already be removed)"
  else
    info "helm release harness-delegate not found"
  fi
  if kubectl get ns harness-delegate &>/dev/null; then
    kubectl delete namespace harness-delegate --wait=false >/dev/null
    ok "namespace harness-delegate delete initiated"
  else
    info "namespace harness-delegate not found"
  fi
fi

# --- 7. GHCR package ------------------------------------------------------
step "GHCR package"
GH_API="https://api.github.com/user/packages/container/pipeline-controls-demo"
if [ "$DRY_RUN" = true ]; then
  info "would: curl -X DELETE $GH_API  -H 'Authorization: token <GITHUB_PAT>'"
else
  resp="$(curl -sS -X DELETE "$GH_API" \
    -H "Authorization: token $GITHUB_PAT" \
    -H "Accept: application/vnd.github.v3+json" \
    -w $'\n%{http_code}')"
  code="$(printf '%s' "$resp" | tail -n1)"
  body="$(printf '%s' "$resp" | sed '$d')"
  case "$code" in
    204) ok "GHCR package pipeline-controls-demo deleted" ;;
    404) info "GHCR package pipeline-controls-demo not found" ;;
    403) warn "GHCR package delete returned 403 — your GitHub PAT needs the 'delete:packages' scope" ;;
    *)   warn "GHCR package delete returned HTTP $code: $(printf '%s' "$body" | head -c 200)" ;;
  esac
fi

# --- Done -----------------------------------------------------------------
step "Done"
echo "Cleanup complete."
echo
echo "If any items were 'not found', they were already gone — that's fine."
echo "To re-provision from a clean slate: ./scripts/setup.sh"
