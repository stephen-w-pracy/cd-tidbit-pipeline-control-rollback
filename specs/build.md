# Pipeline Controls Exemplar - Build Spec (Draft)

This spec describes creating learner instructions, the script of a 10–15 minute
Tidbits video, and an accompanying, reproducible repo that demonstrates how
pipeline controls behave during a post-production rollback in Harness CD
NextGen.

Target audience: CD practitioners and learners who want to understand how Input
Sets, execution-time inputs, and conditional execution interact with post-prod
rollback.

See the [README.md](../README.md) in the repo root for the learner's
instructions. See [corrections.md](./corrections.md) for the verified
correctness fixes that have been applied to the original draft.

> [!NOTE]
> The learner README, this document, and the video script are being brought
> into parity. The pipeline YAML, manifests, and README reflect the fixes in
> corrections.md; the video script (video.md) still needs its per-act scripts
> written.

## Documentation Resources

- [Install the Harness Delegate](https://developer.harness.io/docs/platform/delegates/install-delegates/overview/)
- [Harness CD documentation](https://developer.harness.io/docs/continuous-delivery)
- [Harness CI documentation](https://developer.harness.io/docs/continuous-integration)
- [Docker Registry Connector](https://developer.harness.io/docs/platform/connectors/cloud-providers/ref-cloud-providers/docker-registry-connector-settings-reference/)
- [Define Variables](https://developer.harness.io/docs/platform/variables-and-expressions/add-a-variable/#reference-variables)
- [Add and override values YAML files](https://developer.harness.io/docs/continuous-delivery/deploy-srv-diff-platforms/kubernetes/cd-kubernetes-category/add-and-override-values-yaml-files)
- [Kubernetes releases and versioning](https://developer.harness.io/docs/continuous-delivery/deploy-srv-diff-platforms/kubernetes/cd-k8s-ref/kubernetes-releases-and-versioning)

## Repo Structure

```plaintext
tidbits-pipeline-controls/
├── README.md                       # Demo instructions for the learner
├── app/
│   ├── server.py                   # Python HTTP server (stdlib only)
│   └── Dockerfile                  # Container image definition
├── k8s/
│   ├── deployment.yaml             # K8s Deployment (image from pipeline artifact)
│   ├── service.yaml                # K8s Service (ClusterIP, port 80 → 8080)
│   ├── configmap.yaml              # HTML page template (Go templating)
│   ├── Dev.yaml                    # Values for the Dev environment (blue badge)
│   └── Prod.yaml                   # Values for the Prod environment (green badge)
├── .harness/
│   ├── pipeline.yaml               # CI/CD pipeline: Build → Dev → Prod
│   └── inputsets/
│       ├── dev-only.yaml           # Deploys to Dev only
│       └── full-release.yaml       # Deploys to Dev and Prod
├── scripts/
│   ├── validate-setup.sh           # Pre-flight environment checks
│   └── teardown.sh                 # Resource cleanup
└── specs/
    ├── build.md                    # This spec
    ├── video.md                    # Video production script
    └── corrections.md              # Verified correctness fixes
```

## Design Decisions

- **CI stage builds a custom image.** A tiny Python HTTP server is containerized. This gives learners a realistic CI/CD flow and enables visual verification (visit the URL, see the page change on rollback).
- **Same image, different config.** The image is built once in CI. The page content comes from a ConfigMap rendered with Go templating; per-environment values (`Dev.yaml`, `Prod.yaml`) supply the environment name and accent color. This is a realistic 12-factor pattern.
- **ConfigMap is a Service manifest, not a separate Apply step.** Keeping the ConfigMap in the Service's Manifests section means Harness versions it and updates the Deployment's reference to it on each release. As a result, pods roll when content changes, and a rolling rollback reverts the ConfigMap along with the Deployment — which is what makes the visual payoff work.
- **Per-environment values via `<+env.name>`.** The Service's Values YAML path is `k8s/<+env.name>.yaml`, so the Dev stage uses `Dev.yaml` and the Prod stage uses `Prod.yaml` automatically. This is how the badge color differs per environment.
- **Version label from the execution sequence id.** `app_version` is `v<+pipeline.sequenceId>`, which increments on each run with no manual entry. More realistic than typed `v1`/`v2`, and it removes a manual prompt from the demo flow.
- **Two registry options documented.** GHCR (learner already has GitHub) and Docker Hub (familiar, free tier). Both documented with connector setup steps.
- **Harness Cloud for CI.** The Build stage uses Harness Cloud infrastructure so learners don't need to set up a build farm.
- **Visual differentiation via version badge.** A clean HTML page with a version badge and environment name. Dev uses blue accent, Prod uses green. On rollback, the version text reverts — the visual payoff.

## Pipeline Architecture

```
┌─────────┐     ┌──────────────┐     ┌───────────────┐
│  Build  │────▶│ Deploy to Dev│────▶│ Deploy to Prod│
│ (always)│     │   (always)   │     │ (conditional) │
└─────────┘     └──────────────┘     └───────────────┘
```

- **Build**: Builds `app/Dockerfile`, pushes to learner's registry with `app_version` (`v<+pipeline.sequenceId>`) as the tag
- **Deploy to Dev**: Rolling deploy of the Deployment, Service, and versioned ConfigMap to `web-dev` namespace
- **Deploy to Prod**: Guarded by `target_envs.contains("prod")`. Pauses for the `prod_confirm` execution-time input before rolling out. Rollback steps configured.

## Pipeline Controls in This Scenario

| Control               | Where it's used                                                         | Why it matters during rollback                                             |
| ---                   | ---                                                                     | ---                                                                        |
| Input Sets            | Select between dev-only and full-release (set `target_envs`)            | Not re-applied during rollback; original execution's merged YAML is reused |
| Execution-time inputs | `prod_confirm` on the Prod stage, prompted mid-run via `executionInput()` | Still pauses the rollback for input if configured on rollback nodes        |
| Conditional execution | Prod stage guarded by `target_envs.contains("prod")`                    | Bypassed for non-rollback steps; conditions on rollback steps still apply  |

## Pipeline Variables

| Variable      | Type   | Default                | Purpose                                                          |
| ---           | ---    | ---                    | ---                                                              |
| `target_envs` | String | `dev`                  | Controls which stages run (dev or dev,prod)                      |
| `app_version` | String | `v<+pipeline.sequenceId>` | Version label shown on the page, also used as image tag; auto-increments |

Per-environment presentation values (environment name, accent color) live in the
values files `k8s/Dev.yaml` and `k8s/Prod.yaml`, selected by `<+env.name>`, not
in pipeline variables.

### Stage Variables

| Variable       | Stage         | Type   | Value                                              | Purpose                                              |
| ---            | ---           | ---    | ---                                                | ---                                                  |
| `prod_confirm` | Deploy to Prod | String | `<+input>.selectOneFrom(approve,hold).executionInput()` | Mid-run confirmation gate before the Prod rollout |

## Harness Resources Required

The learner must create these in their Harness project:

| Resource              | Name (suggested)            | Purpose                                      |
| ---                   | ---                         | ---                                          |
| Delegate              | `pipeline-controls-delegate`| Runs in K8s cluster, executes pipeline steps |
| Kubernetes Connector  | `k8s-cluster`               | Points to the learner's cluster via Delegate |
| Docker Connector      | `container-registry`        | Push/pull images (GHCR or Docker Hub)        |
| GitHub Connector      | `github`                    | Fetch pipeline YAML and K8s manifests        |
| Service               | `pipeline-controls-demo`    | K8s service definition with manifests + values + artifact |
| Environment (Dev)     | `Dev`                       | Pre-Production, namespace `web-dev`; name must match `Dev.yaml` |
| Environment (Prod)    | `Prod`                      | Production, namespace `web-prod`; name must match `Prod.yaml` |
| Infrastructure (Dev)  | (learner's choice)          | K8s infra in Dev env, namespace `web-dev`, release name `release-<+INFRA_KEY_SHORT_ID>` |
| Infrastructure (Prod) | (learner's choice)          | K8s infra in Prod env, namespace `web-prod`, release name `release-<+INFRA_KEY_SHORT_ID>` |
