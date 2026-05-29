# Pipeline Controls Exemplar - Build Spec (Draft)

This spec describes creating learner instructions, the script of a 10–15 minute
Tidbits video, and an accompanying, reproducible repo that demonstrates how
pipeline controls behave during a post-production rollback in Harness CD
NextGen.

Target audience: CD practitioners and learners who want to understand how Input
Sets, execution-time inputs, and conditional execution interact with post-prod
rollback.

See the [README.md](../README.md) in the repo root for the learner's
instructions.

> [!NOTE]
> The learner README, this document, and the video script are in draft mode and
> currently not in parity. The final version will ensure all three are aligned
> and polished.

## Documentation Resources

- [Install the Harness Delegate](https://developer.harness.io/docs/platform/delegates/install-delegates/overview/)
- [Harness CD documentation](https://developer.harness.io/docs/continuous-delivery)
- [Harness CI documentation](https://developer.harness.io/docs/continuous-integration)
- [Docker Registry Connector](https://developer.harness.io/docs/platform/connectors/cloud-providers/ref-cloud-providers/docker-registry-connector-settings-reference/)
- [Define Variables](https://developer.harness.io/docs/platform/variables-and-expressions/add-a-variable/#reference-variables)

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
│   └── configmap.yaml              # HTML page template with Harness expressions
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
    └── video.md                    # Video production script
```

## Design Decisions

- **CI stage builds a custom image.** A tiny Python HTTP server is containerized. This gives learners a realistic CI/CD flow and enables visual verification (visit the URL, see the page change on rollback).
- **Same image, different config.** The image is built once in CI. Each environment gets its own ConfigMap with version/environment info baked in via Harness expressions. This is a realistic 12-factor pattern.
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

- **Build**: Builds `app/Dockerfile`, pushes to learner's registry with `app_version` as the tag
- **Deploy to Dev**: Applies ConfigMap + rolling deploy to `web-dev` namespace
- **Deploy to Prod**: Guarded by `target_envs.contains("prod")`. Execution-time input confirms version. Rollback steps configured.

## Pipeline Controls in This Scenario

| Control               | Where it's used                                                         | Why it matters during rollback                                             |
| ---                   | ---                                                                     | ---                                                                        |
| Input Sets            | Select between dev-only and full-release                                | Not re-applied during rollback; original execution's merged YAML is reused |
| Execution-time inputs | `app_version` prompted at execution time via full-release Input Set     | Still pauses the rollback for input if configured on rollback nodes        |
| Conditional execution | Prod stage guarded by `target_envs.contains("prod")`                    | Bypassed for non-rollback steps; conditions on rollback steps still apply  |

## Pipeline Variables

| Variable      | Type   | Default      | Purpose                                               |
| ---           | ---    | ---          | ---                                                   |
| `target_envs` | String | `dev`        | Controls which stages run (dev or dev,prod)           |
| `app_version` | String | `<+input>`   | Version label shown on the page, also used as image tag |
| `env_color`   | String | `#0d6efd`    | CSS accent color for the environment badge            |

## Harness Resources Required

The learner must create these in their Harness project:

| Resource              | Name (suggested)            | Purpose                                      |
| ---                   | ---                         | ---                                          |
| Delegate              | `pipeline-controls-delegate`| Runs in K8s cluster, executes pipeline steps |
| Kubernetes Connector  | `k8s-cluster`               | Points to the learner's cluster via Delegate |
| Docker Connector      | `container-registry`        | Push/pull images (GHCR or Docker Hub)        |
| GitHub Connector      | `github`                    | Fetch pipeline YAML and K8s manifests        |
| Service               | `pipeline-controls-demo`    | K8s service definition with manifests + artifact |
| Environment (Dev)     | `Dev`                       | Pre-Production, namespace `web-dev`          |
| Environment (Prod)    | `Prod`                      | Production, namespace `web-prod`             |
| Infrastructure (Dev)  | (learner's choice)          | K8s infra in Dev env, namespace `web-dev`    |
| Infrastructure (Prod) | (learner's choice)          | K8s infra in Prod env, namespace `web-prod`  |
