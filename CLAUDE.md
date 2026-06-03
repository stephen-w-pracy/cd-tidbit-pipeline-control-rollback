# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

A companion repository for a 10–15 minute Harness "Technical Tidbit" video demonstrating four pipeline controls in Harness CD/CI NextGen: **Input Sets, execution-time variables, conditional execution, and post-prod rollback**. These are treated as four coordinate controls shown in the order of a deploy-and-recover cycle (not as three controls analyzed through rollback). The app is a tiny Python HTTP server that displays a version badge and the running image's name/tag — the visual payoff is seeing the page advance across runs and revert on rollback.

All documentation (README, specs, video script) must stay in parity. See `specs/corrections.md` for the verified fixes and design decisions that define the current architecture (especially §0 framing and §5 on execution-time variables).

## Architecture

- `app/server.py` — Python stdlib HTTP server (~20 lines). Serves HTML from `/app/content/index.html` (mounted ConfigMap) or `PAGE_CONTENT` env var.
- `app/Dockerfile` — python:3.12-alpine image, exposes port 8080.
- `k8s/deployment.yaml` — Deployment using `<+artifacts.primary.image>` (Harness expression). Mounts ConfigMap at `/app/content`.
- `k8s/service.yaml` — ClusterIP Service (port 80 → 8080).
- `k8s/configmap.yaml` — HTML page template rendered with **Go templating**. Uses `{{.Values.app_version}}`, `{{.Values.env_name}}`, `{{.Values.env_color}}`, `{{.Values.image_name}}`, `{{.Values.image_tag}}`.
- `k8s/Dev.yaml`, `k8s/Prod.yaml` — Per-environment values files. Selected by the Service's Values YAML path `k8s/<+env.name>.yaml`. They set `env_name`, `env_color` (Dev blue `#0d6efd`, Prod green `#198754`), and read the artifact details: `app_version` and `image_tag` from `<+artifacts.primary.tag>`, `image_name` from `<+artifacts.primary.imagePath>`.
- `.harness/pipeline.yaml` — Three-stage pipeline: Build (CI, always) → Deploy to Dev (always) → Deploy to Prod (conditional on `target_envs.contains("prod")`). `app_version` is `v<+pipeline.sequenceId>`, used as the CI image tag. No execution-time *input* prompt — execution-time variables are demonstrated by the sequence id and by artifact expressions read in the deploy stage.
- `.harness/inputsets/` — `dev-only.yaml` (sets `target_envs: dev`, skips Prod) and `full-release.yaml` (sets `target_envs: dev,prod`). Neither sets a version; that's derived from the sequence id.
- `scripts/validate-setup.sh` — Pre-flight checks (kubectl, cluster, namespaces, delegate).
- `scripts/teardown.sh` — Deletes deployed resources from both namespaces.
- `specs/build.md` — Design spec: skill interpretation, learning objectives, decisions, controls/variables tables, resource table.
- `specs/video.md` — Video production script (5 acts, one control per act arc).
- `specs/corrections.md` — Verified correctness fixes and design decisions, with doc citations.

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

- **Four coordinate controls**: The tidbit demonstrates Input Sets, execution-time variables, conditional execution, and post-prod rollback as four things the learner can *use*, in lifecycle order. Rollback internals are a brief aside, not the spine. (See corrections.md §0.)
- **Parity**: Changes to README demo steps, pipeline YAML, or video script acts must be reflected across all of them (and in `build.md`).
- **Same image, different config**: The Docker image is built once. Environments differ only by their values file (`Dev.yaml` / `Prod.yaml`), which drives the ConfigMap content (environment name, accent color, image reference).
- **Execution-time variables, no prompt**: Demonstrated by `v<+pipeline.sequenceId>` (CI tag + version label) and by artifact expressions (`<+artifacts.primary.imagePath>` / `.tag`) read in the CD stage and shown on the page. `executionInput()` was deliberately dropped (corrections.md §5): it adds on-camera timeout/typing risk, and "execution-time variable" is broader than a prompt.
- **ConfigMap is a Service manifest, versioned by Harness**: It is *not* applied as a separate K8sApply step. Keeping it in the Service Manifests means Harness versions it and rewrites the Deployment's reference each release, so pods roll on change and a rolling rollback reverts it. This is what makes the visual payoff reliable.
- **Two templating mechanisms, used deliberately**: The Deployment uses the Harness expression `<+artifacts.primary.image>` (resolved in-manifest at deploy time). The ConfigMap uses Go templating `{{.Values.x}}` fed by the per-env values files (which themselves contain Harness expressions). Both are resolved by Harness at deploy time and are *not* valid standalone YAML for `kubectl apply`.
- **Version from sequence id**: `app_version` is `v<+pipeline.sequenceId>` and auto-increments per run; there is no version to type.
- **Environment names are load-bearing**: Environments must be named `Dev` and `Prod` to match the values file names selected by `<+env.name>`.
- **Release name**: Infrastructure definitions use `release-<+INFRA_KEY_SHORT_ID>` (the Harness default) so versioning/rollback chains stay intact.
- **Two registry options**: README documents both GHCR and Docker Hub setup. Pipeline YAML uses `<+input>` for connector/repo so it works with either.
- **No external dependencies**: The Python server uses stdlib only. No pip install, no requirements.txt.
