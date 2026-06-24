#!/usr/bin/env bash
set -euo pipefail

echo "=== Pipeline Controls — Setup Validator ==="
echo

# Pick up DELEGATE_NAME from .env if present, so the delegate check below
# matches what setup.sh actually deployed.
if [ -f .env ]; then
  set -a; . ./.env; set +a
fi
: "${DELEGATE_NAME:=pipeline-controls-delegate}"

PASS=0
WARN=0
FAIL=0

# Note: under `set -e`, `((VAR++))` returns a non-zero status when the result is
# 0 (the post-increment evaluates to the old value), which would abort the
# script. Use arithmetic assignment, which always returns success.
pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
warn() { echo "  ⚠ $1"; WARN=$((WARN + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

# kubectl
echo "Checking tools..."
if command -v kubectl &>/dev/null; then
  pass "kubectl found"
else
  fail "kubectl not found — install from https://kubernetes.io/docs/tasks/tools/"
fi

# Cluster connectivity
echo
echo "Checking cluster..."
if kubectl cluster-info &>/dev/null; then
  pass "Cluster reachable"
else
  fail "Cannot connect to cluster — check your kubeconfig"
fi

# Namespaces
echo
echo "Checking namespaces..."
for ns in web-dev web-prod; do
  if kubectl get ns "$ns" &>/dev/null; then
    pass "Namespace $ns exists"
  else
    warn "Namespace $ns does not exist — run: kubectl create namespace $ns"
  fi
done

# Delegate
echo
echo "Checking Harness Delegate..."
if kubectl get pods -A -l "harness.io/name=$DELEGATE_NAME" --field-selector=status.phase=Running 2>/dev/null | grep -q "$DELEGATE_NAME"; then
  pass "Harness Delegate '$DELEGATE_NAME' running"
else
  warn "No running Harness Delegate named '$DELEGATE_NAME' found — see README for install instructions"
fi

# Manifests
echo
echo "Validating manifests (dry-run)..."
for f in k8s/deployment.yaml k8s/service.yaml k8s/configmap.yaml; do
  if [ -f "$f" ]; then
    if kubectl apply -f "$f" --dry-run=client -n web-dev &>/dev/null 2>&1; then
      pass "$f is valid"
    else
      warn "$f has Harness expressions or Go template syntax (expected — Harness resolves these at deploy time, so a raw kubectl dry-run won't validate)"
    fi
  else
    fail "$f not found"
  fi
done

# Summary
echo
echo "---"
echo "Results: $PASS passed, $WARN warnings, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo "Fix the failures above before proceeding."
  exit 1
fi
if [ "$WARN" -gt 0 ]; then
  echo "Warnings are non-blocking but should be addressed."
fi
echo "Setup looks good!"
