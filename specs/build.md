# Pipeline Controls Demo - Build Spec (Draft)

This spec describes the learner instructions, the script of a 10–15 minute
Tidbits video, and an accompanying, reproducible repo that demonstrates four
Harness pipeline controls: Input Sets, execution-time variables, conditional
execution, and post-prod rollback.

Target audience: CD practitioners and learners who want to use these four
pipeline controls in a realistic build → deploy → recover workflow.

See the [README.md](../README.md) in the repo root for the learner's
instructions. See [corrections.md](./corrections.md) for the verified
correctness fixes and design decisions applied to the original draft.

> [!NOTE]
> The learner README, this document, and the video script are being brought
> into parity. The pipeline YAML, manifests, README, and this spec reflect the
> decisions in corrections.md; the video script (video.md) still needs its
> per-act scripts written.

## Skill Statement and Interpretation

This tidbit covers the intermediate-tier pipeline-controls skill:

> Pipeline Controls: Use Input Sets, execution-time variables, conditional
> execution, and post-prod rollback.

These are treated as **four coordinate controls** the learner should be able to
use, demonstrated in the natural order of a deployment lifecycle. Post-prod
rollback is the fourth control (recover from the run you configured), shown as
the closing beat — not as a lens for analyzing the other three. The rationale
(curriculum structure, tier placement) is recorded in `corrections.md` §0.

## Learning Objectives

After completing this tidbit, a learner can:

1. **Input Sets** — Create and run a pipeline with an Input Set, and switch
   between Input Sets to change what the run does (here: which environments are
   targeted).
2. **Execution-time variables** — Use values that are resolved at execution time
   rather than authored in advance: the build sequence id as a version/tag, and
   artifact details (image name and tag) read in a later stage from the artifact
   an earlier stage produced.
3. **Conditional execution** — Use a stage condition so a stage runs only when a
   criterion is met (here: deploy to Prod only when the target list includes
   `prod`).
4. **Post-prod rollback** — Trigger a post-production rollback and confirm the
   prior version is restored.

## Documentation Resources

- [Install the Harness Delegate](https://developer.harness.io/docs/platform/delegates/install-delegates/overview/)
- [Harness CD documentation](https://developer.harness.io/docs/continuous-delivery)
- [Harness CI documentation](https://developer.harness.io/docs/continuous-integration)
- [Docker Registry Connector](https://developer.harness.io/docs/platform/connectors/cloud-providers/ref-cloud-providers/docker-registry-connector-settings-reference/)
- [Input Sets and Overlays](https://developer.harness.io/docs/platform/pipelines/input-sets)
- [Built-in and artifact expressions](https://developer.harness.io/docs/platform/variables-and-expressions/harness-expressions-reference)
- [Conditional execution settings](https://developer.harness.io/docs/platform/pipelines/step-skip-condition-settings)
- [Add and override values YAML files](https://developer.harness.io/docs/continuous-delivery/deploy-srv-diff-platforms/kubernetes/cd-kubernetes-category/add-and-override-values-yaml-files)
- [Kubernetes releases and versioning](https://developer.harness.io/docs/continuous-delivery/deploy-srv-diff-platforms/kubernetes/cd-k8s-ref/kubernetes-releases-and-versioning)
- [Post-deployment rollback](https://developer.harness.io/docs/continuous-delivery/manage-deployments/rollback-deployments)

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
│   ├── setup.sh                    # Automated provisioning
│   ├── cleanup.sh                  # Tears everything down (Harness + cluster + GHCR)
│   ├── port-forward.sh             # Foreground port-forward to Dev + Prod
│   └── validate-setup.sh           # Pre-flight environment checks
└── specs/
    ├── build.md                    # This spec
    ├── video.md                    # Video production script
    └── corrections.md              # Verified correctness fixes + decisions
```

## Design Decisions

- **CI stage builds a custom image.** A tiny Python HTTP server is containerized. This gives learners a realistic CI/CD flow and enables visual verification (visit the URL, see the page change and revert).
- **Same image, different config.** The image is built once in CI. The page content comes from a ConfigMap rendered with Go templating; per-environment values (`Dev.yaml`, `Prod.yaml`) supply the environment name and accent color. This is a realistic 12-factor pattern.
- **ConfigMap is a Service manifest, not a separate Apply step.** Keeping the ConfigMap in the Service's Manifests section means Harness versions it and updates the Deployment's reference to it on each release. As a result, pods roll when content changes, and a rolling rollback reverts the ConfigMap along with the Deployment — which is what makes the visual payoff work.
- **Per-environment values via `<+env.name>`.** The Service's Values YAML path is `k8s/<+env.name>.yaml`, so the Dev stage uses `Dev.yaml` and the Prod stage uses `Prod.yaml` automatically. This is how the badge color differs per environment.
- **Execution-time variables, demonstrated without a prompt.** Two naturally-computed values stand in for the control: `v<+pipeline.sequenceId>` (tags the image in CI, becomes the version label) and artifact expressions (`<+artifacts.primary.imagePath>` / `<+artifacts.primary.tag>`) read back in the CD stage and rendered on the page. The latter shows a later stage consuming an earlier stage's artifact. An `executionInput()` prompt was deliberately not used (see corrections.md §5) — it adds on-camera timeout risk and manual typing, and "execution-time variable" is broader than a prompt.
- **Image name and tag on the page.** Both environments display the running image's name and tag, making the execution-time artifact values visible and concrete.
- **Two registry options documented.** GHCR (learner already has GitHub) and Docker Hub (familiar, free tier). Both documented with connector setup steps.
- **Harness Cloud for CI.** The Build stage uses Harness Cloud infrastructure so learners don't need to set up a build farm.
- **Visual differentiation via version badge.** A clean HTML page with a version badge, environment name, and image reference. Dev uses blue accent, Prod uses green. On rollback, the version and image revert — the visual payoff.

## Pipeline Architecture

```
┌─────────┐     ┌──────────────┐     ┌───────────────┐
│  Build  │────▶│ Deploy to Dev│────▶│ Deploy to Prod│
│ (always)│     │   (always)   │     │ (conditional) │
└─────────┘     └──────────────┘     └───────────────┘
```

- **Build**: Builds `app/Dockerfile`, pushes to learner's registry with `app_version` (`v<+pipeline.sequenceId>`) as the tag
- **Deploy to Dev**: Rolling deploy of the Deployment, Service, and versioned ConfigMap to `web-dev` namespace; reads artifact name/tag onto the page
- **Deploy to Prod**: Guarded by `target_envs.contains("prod")` (conditional execution). Same rolling deploy to `web-prod`. Rollback steps configured.

## Pipeline Controls in This Scenario

| Control                | Where it's used                                                                                  | How the learner sees it                                                  |
| ---                    | ---                                                                                              | ---                                                                      |
| Input Sets             | `dev-only` and `full-release` set `target_envs`                                                  | Pick an Input Set at run time; it changes which environments deploy      |
| Execution-time variables | `v<+pipeline.sequenceId>` (CI tag + version label); `<+artifacts.primary.imagePath>` / `.tag` read in CD | Version auto-increments each run; image name/tag appear on the page      |
| Conditional execution  | Prod stage `when` condition: `target_envs.contains("prod")`                                       | Prod stage runs with full-release, is skipped with dev-only              |
| Post-prod rollback     | `K8sRollingRollback` rollback steps on both deploy stages                                         | Trigger rollback from Deployments; page reverts to the prior version     |

### Rollback behavior (brief aside)

A post-prod rollback is a separate execution (mode `POST_EXECUTION_ROLLBACK`)
that replays the original run's resolved YAML and runs only rollback steps — not
a re-run with rollback toggled on. Consequently Input Sets are not re-applied and
conditions are not re-evaluated; the original resolved outcome is replayed. This
is a good-to-know aside in the video, not the core of the lesson. Details and
verification status in `corrections.md`.

## Pipeline Variables

| Variable      | Type   | Default                   | Purpose                                                        |
| ---           | ---    | ---                       | ---                                                            |
| `target_envs` | String | `dev`                     | Controls which stages run (dev or dev,prod); set by Input Sets |
| `app_version` | String | `v<+pipeline.sequenceId>` | Version label and image tag; auto-increments per run           |

Per-environment presentation values live in the values files `k8s/Dev.yaml` and
`k8s/Prod.yaml`, selected by `<+env.name>`:

| Values key   | Dev.yaml                          | Prod.yaml                         | Rendered as                  |
| ---          | ---                               | ---                               | ---                          |
| `env_name`   | `Dev`                             | `Prod`                            | Badge text                   |
| `env_color`  | `#0d6efd` (blue)                  | `#198754` (green)                 | Badge + version color        |
| `app_version`| `<+artifacts.primary.tag>`        | `<+artifacts.primary.tag>`        | Large version number         |
| `image_name` | `<+artifacts.primary.imagePath>`  | `<+artifacts.primary.imagePath>`  | Image reference (name)       |
| `image_tag`  | `<+artifacts.primary.tag>`        | `<+artifacts.primary.tag>`        | Image reference (tag)        |

There are no stage variables; the previous `prod_confirm` execution-time input
was removed (see corrections.md §5).

## Harness Resources Required

The learner must create these in their Harness project:

| Resource              | Name (suggested)            | Purpose                                      |
| ---                   | ---                         | ---                                          |
| Delegate              | `pipeline-controls-delegate`| Runs in K8s cluster, executes pipeline steps |
| Kubernetes Connector  | `pipeline-demo-cluster`     | Points to the learner's cluster via Delegate |
| Docker Connector      | `pipeline-demo-ghcr`        | Push/pull images (GHCR or Docker Hub)        |
| GitHub Connector      | `pipeline-demo-github`      | Fetch pipeline YAML and K8s manifests        |
| Service               | `pipeline-controls-demo`    | K8s service definition with manifests + values + artifact |
| Environment (Dev)     | `Dev`                       | Pre-Production, namespace `web-dev`; name must match `Dev.yaml` |
| Environment (Prod)    | `Prod`                      | Production, namespace `web-prod`; name must match `Prod.yaml` |
| Infrastructure (Dev)  | (learner's choice)          | K8s infra in Dev env, namespace `web-dev`, release name `release-<+INFRA_KEY_SHORT_ID>` |
| Infrastructure (Prod) | (learner's choice)          | K8s infra in Prod env, namespace `web-prod`, release name `release-<+INFRA_KEY_SHORT_ID>` |
