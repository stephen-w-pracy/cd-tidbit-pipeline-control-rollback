# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

A companion repository for a 10–15 minute Harness "Technical Tidbit" video demonstrating four pipeline controls in Harness CD/CI NextGen: **Input Sets, execution-time variables, conditional execution, and post-prod rollback**. These are treated as four coordinate controls shown in the order of a deploy-and-recover cycle (not as three controls analyzed through rollback). The app is a tiny Python HTTP server that displays a version badge and the running image's name/tag — the visual payoff is seeing the page advance across runs and revert on rollback.

All documentation (README, specs, video script) must stay in parity. See `specs/build.md` for the design rationale (skill interpretation, learning objectives, decisions, controls/variables tables) and `docs/parity-matrix.md` for the cross-doc change-impact checklist.

## Architecture

### Application
- `app/server.py` — Python stdlib HTTP server (~20 lines). Serves HTML from `/app/content/index.html` (mounted ConfigMap) or `PAGE_CONTENT` env var.
- `app/Dockerfile` — python:3.12-alpine image, exposes port 8080.

### Kubernetes Manifests (Go-templated, resolved by Harness at deploy time)
- `k8s/deployment.yaml` — Deployment using `{{.Values.image}}` for the container image. Includes `imagePullSecrets: ghcr-cred` for private GHCR packages. Mounts ConfigMap at `/app/content`.
- `k8s/service.yaml` — ClusterIP Service (port 80 → 8080).
- `k8s/configmap.yaml` — HTML page template rendered with Go templating. Uses `{{.Values.app_version}}`, `{{.Values.env_name}}`, `{{.Values.env_color}}`, `{{.Values.image}}`.
- `k8s/Dev.yaml`, `k8s/Prod.yaml` — Per-environment values files. Selected by the Service's Values YAML path `k8s/<+env.name>.yaml`. They set `env_name`, `env_color` (Dev blue `#0d6efd`, Prod green `#198754`), and read artifact details: `app_version` from `<+artifact.version>`, `image` from `<+artifact.image>`.

### Harness Resources (`.harness/`)
- `pipeline.yaml` — Three-stage pipeline: Build (CI) → Deploy to Dev → Deploy to Prod (conditional on `target_envs.contains("prod")`). `app_version` is `v<+pipeline.sequenceId>`, used as the CI image tag and artifact version. Both deploy stages independently supply `serviceInputs` with the artifact version.
- `service.yaml` — Kubernetes Service entity. Defines manifest paths (pulled from GitHub), values path `k8s/<+env.name>.yaml`, and a GithubPackageRegistry artifact source with `version: <+input>`. No service variables.
- `environment-dev.yaml` — Dev environment (PreProduction).
- `environment-prod.yaml` — Prod environment (Production).
- `infra-dev.yaml` — Dev_Infra infrastructure definition (KubernetesDirect, namespace `web-dev`).
- `infra-prod.yaml` — Prod_Infra infrastructure definition (KubernetesDirect, namespace `web-prod`).
- `connector-github.yaml` — GitHub code connector (Repo type, points at this repo).
- `connector-ghcr.yaml` — GHCR Docker registry connector (DockerRegistry type).
- `connector-k8s.yaml` — K8s cluster connector (InheritFromDelegate, selector from `${DELEGATE_SELECTOR}` in `.env`).
- `ghcr-token-secret.yaml` — Secret reference for the GitHub PAT used by connectors.
- `inputsets/dev-only.yaml` — Sets `target_envs: dev`, supplies Dev environment/infra. Prod stage skipped.
- `inputsets/full-release.yaml` — Sets `target_envs: dev,prod`, supplies both environments/infras.

### Supporting Files
- `scripts/setup.sh` — Automated provisioning: renders `.harness/` templates and creates every Harness resource via the NG REST API, plus cluster namespaces, the GHCR imagePullSecret, and a Helm-installed delegate. Idempotent (POST → PUT on conflict). Honors `--dry-run`.
- `scripts/validate-setup.sh` — Pre-flight checks (kubectl, cluster, namespaces, delegate).
- `scripts/cleanup.sh` — Tears down the full tutorial: Harness project, cluster namespaces, delegate, and GHCR package. Honors `--dry-run` for preview.
- `scripts/port-forward.sh` — Foreground port-forward to Dev (8080) and Prod (8081). Auto-reconnects on pod rotation; Ctrl-C cleans both up.
- `specs/build.md` — Design spec: skill interpretation, learning objectives, decisions, controls/variables tables, resource table.
- `video/script.md` — Narrator script (5 acts), read while performing the on-screen actions.
- `video/production-spec.md` — Video production reference: act structure, shot lists, key callouts, production notes.

### Navigation Aids (read these first)
- `docs/resource-map.md` — The `.harness/`/`k8s/` identifier graph (who references whom) and which templating engine (`${VAR}` envsubst / `<+...>` Harness / `{{.Values}}` Go) owns each token. Start here before tracing a reference or changing an ID.
- `docs/placeholders.md` — Canonical `${VAR}` → `.env` key → consuming-files table, with render-verification commands.
- `docs/parity-matrix.md` — Maps each control/golden-path run to its README anchor, `video/script.md` act, `video/production-spec.md` act, and `specs/build.md` section, plus a change-impact checklist. Consult before editing demo steps to know what else must change.

## Common Commands

```bash
make validate          # Run pre-flight checks
make cleanup           # Tear down everything setup.sh created (project, namespaces, delegate, GHCR package)
make build-local       # Build Docker image locally
make run-local         # Run container locally on port 8080
make port-forward      # Foreground port-forward to Dev (8080) + Prod (8081), auto-reconnects on pod rotation
make port-forward-dev  # Forward local:8080 to Dev service (one-shot)
make port-forward-prod # Forward local:8081 to Prod service (one-shot)
```

## Key Conventions

- **Four coordinate controls**: The tidbit demonstrates Input Sets, execution-time variables, conditional execution, and post-prod rollback as four things the learner can *use*, in lifecycle order. Rollback internals are a brief aside, not the spine. (See `specs/build.md` "Skill Statement and Interpretation".)
- **Parity**: Changes to README demo steps, pipeline YAML, or video script acts must be reflected across all of them (and in `build.md`). See `docs/parity-matrix.md` for the cross-doc change-impact checklist.
- **Same image, different config**: The Docker image is built once. Environments differ only by their values file (`Dev.yaml` / `Prod.yaml`), which drives the ConfigMap content (environment name, accent color, image reference).
- **Execution-time variables, no prompt**: Demonstrated by `v<+pipeline.sequenceId>` (CI tag + version label) and by artifact expressions (`<+artifact.version>`, `<+artifact.image>`) resolved in the CD stage values files and shown on the page. `executionInput()` was deliberately dropped: it adds on-camera timeout/typing risk, and "execution-time variable" is broader than a prompt.
- **ConfigMap is a Service manifest, versioned by Harness**: It is *not* applied as a separate K8sApply step. Keeping it in the Service Manifests means Harness versions it and rewrites the Deployment's reference each release, so pods roll on change and a rolling rollback reverts it. This is what makes the visual payoff reliable.
- **Go templating + Harness expressions**: All K8s manifests use Go templating (`{{.Values.x}}`). The per-env values files contain Harness expressions (`<+artifact.image>`, `<+artifact.version>`) which Harness resolves before feeding them to the Go template engine. The manifests are *not* valid standalone YAML for `kubectl apply`.
- **No service variables**: The Service entity has no `variables` block. Display values (`app_version`, `image`) come directly from artifact expressions in the values files, keeping the Service decoupled from any specific pipeline.
- **Version from sequence id**: `app_version` is `v<+pipeline.sequenceId>` and auto-increments per run; there is no version to type.
- **Environment names are load-bearing**: Environments must be named `Dev` and `Prod` to match the values file names selected by `<+env.name>`.
- **Release name**: Infrastructure definitions use `release-<+INFRA_KEY_SHORT_ID>` (the Harness default) so versioning/rollback chains stay intact.
- **Runtime input with default**: `target_envs` is `<+input>.default(dev)` — a runtime input that input sets can override. Without an input set, it defaults to `dev` (Prod skipped).
- **imagePullSecrets for private GHCR**: The deployment references a `ghcr-cred` Kubernetes secret. GHCR packages are private by default; learners must create this secret in each namespace or make their package public.
- **Rollback requires two successful deploys**: Harness needs at least two successful releases in the infrastructure's history before post-prod rollback is available.
- **No external dependencies**: The Python server uses stdlib only. No pip install, no requirements.txt.
