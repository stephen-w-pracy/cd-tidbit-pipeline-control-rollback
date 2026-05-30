# Video Spec and Script (Draft)

This spec describes the production details and script for a 10–15 minute
demonstration video. This video will demonstrate the instructions in the root
directory README.md.

Parity between the video demonstration and written instructions is important.

See the [README.md](../README.md) in the repo root for the learner's
instructions.

See [build.md](./build.md) in this directory for the overall demo design and
implementation details, and [corrections.md](./corrections.md) for the verified
fixes that shaped the current pipeline.

> Note on version numbers: the page version is `v<+pipeline.sequenceId>`, which
> increments every run. In a fresh project the first two runs are v1 and v2; in
> a project that's already been used for setup runs they'll be higher. The acts
> below use **vN** and **vN+1** for two consecutive runs — on camera, just read
> out whatever your actual build numbers are.

## Video Demonstration Script and Production Notes

### Act 1 — Overview and Setup (2–3 min)

- Overview of the demo scenario and what will be covered
- Walkthrough of setup steps:
  - Show the Harness Delegate running in the cluster
  - Show the three connectors (Kubernetes, Container Registry, GitHub)
  - Show the Service (note: ConfigMap is a Service manifest; Values YAML path is `k8s/<+env.name>.yaml`), Environments (named Dev and Prod), and Infrastructure definitions (release name `release-<+INFRA_KEY_SHORT_ID>`)
  - Import the pipeline from Git and walk through the structure
- Highlight the three stages:
  - **Build** (always runs): builds and pushes the container image, tagged `v<+pipeline.sequenceId>`
  - **Deploy to Dev** (always runs): rolling deploy of Deployment, Service, and versioned ConfigMap
  - **Deploy to Prod** (conditional): `target_envs.contains("prod")`, pauses for the `prod_confirm` execution-time input
- Show the two Input Sets (dev-only and full-release) and that they set `target_envs`
- Explain the execution-time input (`prod_confirm`) on the Prod stage and how the version label is derived automatically from the sequence id

#### Script (TBD)

### Act 2 — Deploy vN with Full Release Input Set (2–3 min)

- Run pipeline with the Full Release Input Set
- Show the Build stage completing (image pushed to registry, tagged with the run's version)
- Show Deploy to Dev succeed
- When the Prod stage starts, it pauses for the `prod_confirm` execution-time input — select **approve**
- Call out the version number for this run (this is **vN**)
- Visit the Dev URL: page shows vN with blue Dev badge
- Visit the Prod URL: page shows vN with green Prod badge

#### Script (TBD)

### Act 3 — Deploy vN+1 with Full Release Input Set (2–3 min)

- Run pipeline again with Full Release
- Approve the `prod_confirm` input when the Prod stage pauses
- Show both environments update; note the new version number (**vN+1**)
- Visit Prod URL: page now shows vN+1 — this is our "bad" release

#### Script (TBD)

### Act 4 — Demonstrate Dev-Only Input Set (optional, 1–2 min)

- Run with the Dev Only Input Set
- Show the Prod stage is skipped due to conditional execution (`target_envs` = `dev`)
- Point out: the Input Set's value is merged into the pipeline at run start
- Contrast with rollback behavior, where the original run's resolved YAML is replayed rather than re-evaluating Input Sets

#### Script (TBD)

### Act 5 — Post-Prod Rollback (3–4 min)

- From Deployments or Services → Instances, trigger rollback of the vN+1 Prod deployment
- Call out what's happening:
  - Uses the original execution's processed YAML (Input Sets from that run are baked in)
  - Non-rollback nodes become pass-through; only rollback nodes execute
  - If a rollback step has execution-time input, the rollout pauses for input
- Optional proof beats on screen:
  - `<+pipeline.executionMode>` resolves to `POST_EXECUTION_ROLLBACK` during the rollback
  - `<+pipeline.originalExecution.sequenceId>` references the original run (resolves only during rollback)
- Visit Prod URL: page shows vN again — the visual payoff
- Summarize the three controls and their rollback behavior:
  - Input Sets: not re-applied
  - Execution-time inputs: still honored on rollback steps
  - Conditional execution: bypassed on normal steps, evaluated on rollback steps

#### Script (TBD)
