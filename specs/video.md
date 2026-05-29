# Video Spec and Script (Draft)

This spec describes the production details and script for a 10–15 minute
demonstration video. This video will demonstrate the instructions in the root
directory README.md.

Parity between the video demonstration and written instructions is important.

See the [README.md](../README.md) in the repo root for the learner's
instructions.

See [build.md](./build.md) in this directory for the overall demo design and
implementation details.

## Video Demonstration Script and Production Notes

### Act 1 — Overview and Setup (2–3 min)

- Overview of the demo scenario and what will be covered
- Walkthrough of setup steps:
  - Show the Harness Delegate running in the cluster
  - Show the three connectors (Kubernetes, Container Registry, GitHub)
  - Show the Service, Environments, and Infrastructure definitions
  - Import the pipeline from Git and walk through the structure
- Highlight the three stages:
  - **Build** (always runs): builds and pushes the container image
  - **Deploy to Dev** (always runs): applies ConfigMap and rolls out
  - **Deploy to Prod** (conditional): `target_envs.contains("prod")`
- Show the two Input Sets (dev-only and full-release) and what variables they set
- Explain the execution-time input on `app_version` in the full-release set

#### Script (TBD)

### Act 2 — Deploy v1 with Full Release Input Set (2–3 min)

- Run pipeline with the Full Release Input Set
- When prompted for `app_version`, enter `v1`
- Show the Build stage completing (image pushed to registry)
- Show both Dev and Prod deployments succeed
- Visit the Dev URL: page shows "v1" with blue Dev badge
- Visit the Prod URL: page shows "v1" with green Prod badge

#### Script (TBD)

### Act 3 — Deploy v2 with Full Release Input Set (2–3 min)

- Run pipeline again with Full Release
- Enter `v2` when prompted
- Show both environments update
- Visit Prod URL: page now shows "v2" — this is our "bad" release

#### Script (TBD)

### Act 4 — Demonstrate Dev-Only Input Set (optional, 1–2 min)

- Run with the Dev Only Input Set
- Show the Prod stage is skipped due to conditional execution (`target_envs` = `dev`)
- Point out: this Input Set behavior is what gets baked in at execution time
- Contrast with rollback behavior where Input Sets aren't re-evaluated

#### Script (TBD)

### Act 5 — Post-Prod Rollback (3–4 min)

- From Deployments or Services → Instances, trigger rollback of the Prod deployment
- Call out what's happening:
  - Uses the original execution's processed YAML (Input Sets from that run are baked in)
  - Non-rollback nodes become pass-through; only rollback nodes execute
  - If a rollback step has execution-time input, the rollout pauses for input
- Visit Prod URL: page shows "v1" again — the visual payoff
- Summarize the three controls and their rollback behavior:
  - Input Sets: not re-applied
  - Execution-time inputs: still honored on rollback steps
  - Conditional execution: bypassed on normal steps, evaluated on rollback steps

#### Script (TBD)
