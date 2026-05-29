# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

A companion repository for a 10–15 minute Harness "Technical Tidbit" video demonstrating how pipeline controls (Input Sets, execution-time inputs, conditional execution) behave during a post-production rollback in Harness CD NextGen. The app is a tiny Python HTTP server that displays a version badge — the visual payoff is seeing the page revert on rollback.

All documentation (README, specs, video script) is in **draft** and must stay in parity.

## Architecture

- `app/server.py` — Python stdlib HTTP server (~20 lines). Serves HTML from `/app/content/index.html` (mounted ConfigMap) or `PAGE_CONTENT` env var.
- `app/Dockerfile` — python:3.12-alpine image, exposes port 8080.
- `k8s/deployment.yaml` — Deployment using `<+artifact.image>` (Harness expression). Mounts ConfigMap at `/app/content`.
- `k8s/service.yaml` — ClusterIP Service (port 80 → 8080).
- `k8s/configmap.yaml` — HTML page template with Harness expressions for version (`<+pipeline.variables.app_version>`), environment (`<+env.name>`), and accent color (`<+pipeline.variables.env_color>`).
- `.harness/pipeline.yaml` — Three-stage pipeline: Build (CI, always runs) → Deploy to Dev (always) → Deploy to Prod (conditional on `target_envs`).
- `.harness/inputsets/` — `dev-only.yaml` (skips Prod) and `full-release.yaml` (deploys both, prompts for version).
- `scripts/validate-setup.sh` — Pre-flight checks (kubectl, cluster, namespaces, delegate).
- `scripts/teardown.sh` — Deletes deployed resources from both namespaces.
- `specs/build.md` — Design spec with decisions, pipeline architecture, and resource table.
- `specs/video.md` — Video production script (5 acts).

## Common Commands

```bash
make validate          # Run pre-flight checks
make teardown          # Delete demo resources from cluster
make build-local       # Build Docker image locally
make run-local         # Run container locally on port 8080
make port-forward-dev  # Forward local:8080 to Dev service
make port-forward-prod # Forward local:8081 to Prod service
```

## Key Conventions

- **Parity**: Changes to README demo steps, pipeline YAML, or video script acts must be reflected across all three.
- **Same image, different config**: The Docker image is built once. Environments differ only by their ConfigMap (version badge, environment name, accent color).
- **Harness expressions in k8s/**: The ConfigMap and Deployment use Harness expressions (`<+...>`) that are resolved at deploy time — they are not valid standalone YAML for `kubectl apply`.
- **Two registry options**: README documents both GHCR and Docker Hub setup. Pipeline YAML uses `<+input>` for connector/repo so it works with either.
- **No external dependencies**: The Python server uses stdlib only. No pip install, no requirements.txt.
