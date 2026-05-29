#!/usr/bin/env bash
set -euo pipefail

echo "=== Pipeline Controls — Teardown ==="
echo

for ns in web-dev web-prod; do
  echo "Cleaning namespace: $ns"
  kubectl delete deploy pipeline-controls-demo -n "$ns" --ignore-not-found
  kubectl delete svc pipeline-controls-demo -n "$ns" --ignore-not-found
  kubectl delete configmap pipeline-controls-content -n "$ns" --ignore-not-found
  echo
done

echo "Done. Resources removed from web-dev and web-prod."
