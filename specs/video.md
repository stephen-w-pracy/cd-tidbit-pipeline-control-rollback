# Video Spec and Script (Draft)

This spec describes the production details and script for a 10-15 minute
demonstration video This video will demonstrate the instructions in the root
directory README.md. the instructions in the root directory README.md. 

Parity between the video demonstration and written instructions is important.

See the [README.md](../README.md) in the repo root for the learner's
instructions.

See [build.spec](./build.md) in this directory for the overall demo design and
implementation details.

## Video Demonstration Script and Production Notes

### Act 1 — Overview and Setup (2–3 min)

- Overview of the demo scenario and what will be covered.
- Walkthrough of setup steps
  - Create a Harness Delegate with cluster access and ensure it's mapped to the Project/Org/Account.
  - Create a Kubernetes Connector (`k8s-demo-connector`) and point out the key settings.
  - Create a new pipeline from the imported `pipeline.yaml` and walk through the structure.
  - Highlight the two stages (Dev and Prod) and the conditional execution of the Prod stage.
    - Two stages: Deploy to Dev (always runs) and Deploy to Prod (conditional `when: target_env contains prod`).
    - Rolling K8s deployment referencing `k8s/deployment.yaml` and `k8s/service.yaml`.
    - Rollback steps in the Prod stage include an execution-time input for the image tag confirmation.
    - Show the two Input Sets (dev-only and full-release) and what variables they set.

#### Script (TBD)

### Act 2 — Release v1 with full-release Input Set (2–3 min)

- Run pipeline with full-release Input Set.
- Call out the execution-time input confirmation for the Prod rollback step template if present; proceed.
- Verify v1 is live (kubectl or endpoint curl).

#### Script (TBD)

### Act 3 — Release v2 with full-release Input Set (2–3 min)

- Re-run with a newer image tag for nginx (e.g., 1.26.x).
- Confirm v2 is live. Mention this represents a "bad" release.

#### Script (TBD)

### Act 4 — Demonstrate dev-only Input Set (optional, 1–2 min)

- Run with dev-only Input Set to show the Prod stage is skipped by condition.
- This contrasts with rollback behavior, where Input Sets aren't re-applied.

#### Script (TBD)

### Act 5 — Post-Prod Rollback (3–4 min)

- From Services → Instances or Executions, trigger rollback of the Prod deployment that introduced v2.
- Call out what's happening:
    - Uses the original execution's processed YAML (so Input Sets from that run are effectively "baked in").
    - Non-rollback nodes become pass-through; only rollback nodes execute.
    - If a rollback step has execution-time input, the rollout pauses for input.
- Verify v1 is restored.

#### Script (TBD)

