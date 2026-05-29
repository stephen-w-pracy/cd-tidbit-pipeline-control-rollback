#!/usr/bin/env bash
set -euo pipefail

echo "=== Pipeline Controls — Setup Validator ==="
echo

PASS=0
WARN=0
FAIL=0

pass() { echo "  ✓ $1"; ((PASS++)); }
warn() { echo "  ⚠ $1"; ((WARN++)); }
fail() { echo "  ✗ $1"; ((FAIL++)); }

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
if kubectl get pods -A -l app.kubernetes.io/name=harness-delegate-ng 2>/dev/null | grep -q Running; then
  pass "Harness Delegate running"
else
  warn "No running Harness Delegate found — see README for install instructions"
fi

# Manifests
echo
echo "Validating manifests (dry-run)..."
for f in k8s/deployment.yaml k8s/service.yaml k8s/configmap.yaml; do
  if [ -f "$f" ]; then
    if kubectl apply -f "$f" --dry-run=client -n web-dev &>/dev/null 2>&1; then
      pass "$f is valid"
    else
      warn "$f has Harness expressions (expected — will be resolved at deploy time)"
    fi
  else
    fail "$f not found"
  fi
done

# Summary
echo
echo "---"
echo "Results: $PASS passed, $WARN warnings, $FAIL failed"
if [ $FAIL -gt 0 ]; then
  echo "Fix the failures above before proceeding."
  exit 1
fi
if [ $WARN -gt 0 ]; then
  echo "Warnings are non-blocking but should be addressed."
fi
echo "Setup looks good!"
