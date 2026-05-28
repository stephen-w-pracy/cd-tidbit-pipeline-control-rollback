# Pipeline Controls Exemplar - Build spec (Draft)

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

- [Install the Harness Delegate](https://developer.harness.io/docs/platform/tutorials/install-delegate)
- [Pipeline Infrastructure Setup](https://developer.harness.io/docs/platform/references/pipeline-infra/)
- [CD Helm Chart Tutorial](https://developer.harness.io/docs/continuous-delivery/get-started/tutorials/kubernetes-container-deployments/helm-chart#delegate)
- [Harness CD documentation](https://developer.harness.io/docs/continuous-delivery)

## Repo Structure

```plaintext
pipeline-controls-exemplar/
├── README.md                       # Demo instructions for the learner
├── .harness/
│   ├── pipeline.yaml               # Full pipeline with conditionals + exec inputs
│   └── inputsets/
│       ├── dev-only.yaml           # Runs Dev only
│       └── full-release.yaml       # Runs Dev and Prod
├── k8s/
│   ├── deployment.yaml             # K8s Deployment with image placeholder
│   └── service.yaml                # K8s Service (ClusterIP or LoadBalancer)
└── spec/
    ├── build.md                    # This spec
    └── video.yaml                  # Script for demo video recording
```

## Design Decisions

- **No custom build.** We use public nginx images so learners don't need CI or a Harness Artifact Registry.
  - nginx sites should be single HTML pages and a CSS style sheet to visually differentiate v1 vs v2.
- **Hardcode connectors, environments, and infrastructure** to reduce cognitive load. Only the image tag and a simple env gate remain dynamic.
- **Keep rollback-focused execution-time input minimal and purposeful** (e.g., confirm a rollback image tag).

## Implementation Overview

1. Create a Kubernetes Connector pointing to your cluster (via Delegate or direct credentials).
2. Define a Service (K8s manifests from repo), Environment (Dev and Prod), and Infrastructure definitions (same cluster, different namespaces recommended).
3. Import the provided `pipeline.yaml` and the two Input Sets.
4. Run a full release to deploy v1 to Dev and Prod.
5. Run another full release to deploy v2 to Dev and Prod.
6. Trigger a post-prod rollback from Services → Instances or Executions and observe control behaviors.

## Pipeline Controls in This Scenario

| Control               | Where it's used                                                              | Why it matters during rollback                                             |
| ---                   | ---                                                                          | ---                                                                        |
| Input Sets            | Select between dev-only and full-release                                     | Not re-applied during rollback; original execution's merged YAML is reused |
| Execution-time inputs | Rollback step in Prod stage requests a tag confirmation                      | Still pauses the rollback for input if configured on rollback nodes        |
| Conditional execution | Prod stage guarded by a pipeline variable (e.g., `target_env` includes prod) | Bypassed for non-rollback steps; conditions on rollback steps still apply  |

## Harness variables

There are several learner-specific values that must be configured in Harness
for the pipeline. They are currently represented by hardcoded placholders in
the input sets and the pipeline YAML. The Pipeline YAML placeholders should
be replaced with `<+input>` variables that can be defined in the input sets.
Some of these values will be available at execution time (like the Harness
account, org, and project identifiers) so those should have the appropriate var
references e.g. `<+account.identifier>`, but some might need to be manually
configured, like the learner's git repo connector. 
See [Define Variables](https://developer.harness.io/docs/platform/variables-and-expressions/add-a-variable/#reference-variables)
for documentaion on referncing variables in Harness.

| Placeholder                  | Where it appears          | What to put                                                 |
| ---                          | ---                       | ---                                                         |
| YOUR_ORG_ID                  | pipeline.yaml, input sets | Your Harness org identifier                                 |
| YOUR_PROJECT_ID              | pipeline.yaml, input sets | Your Harness project identifier                             |
| DEV_ENV_ID / PROD_ENV_ID     | pipeline.yaml             | Existing Environment identifiers                            |
| DEV_INFRA_ID / PROD_INFRA_ID | pipeline.yaml             | Infrastructure identifiers inside those Environments        |
| DOCKER_CONNECTOR             | pipeline.yaml             | Docker Registry connector identifier                        |
| GIT_CONNECTOR                | pipeline.yaml             | Git connector identifier that can fetch k8s/deployment.yaml |
| YOUR_REPO_NAME               | pipeline.yaml             | Repository name hosting the k8s folder                      |


