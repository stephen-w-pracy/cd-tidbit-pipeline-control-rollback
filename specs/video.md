# Video Spec and Script (Draft)

This spec describes the production details and script for a 10–15 minute
demonstration video. The video demonstrates the instructions in the root
directory README.md.

Parity between the video demonstration and written instructions is important.

See the [README.md](../README.md) in the repo root for the learner's
instructions. See [build.md](./build.md) for the overall demo design, learning
objectives, and implementation details, and [corrections.md](./corrections.md)
for the verified fixes and design decisions that shaped the current pipeline.

## Framing

This tidbit demonstrates **four pipeline controls**, in the order they occur in
a real deploy-and-recover cycle:

1. **Input Sets** — choose what the run does
2. **Execution-time variables** — values resolved when the run executes (the
   sequence-id version/tag, and the artifact name/tag shown on the page)
3. **Conditional execution** — the Prod stage runs only when targeted
4. **Post-prod rollback** — recover the prior version

Each act demonstrates a control; the goal is that the learner can *use* each one.
Rollback behavior internals (it's a separate execution replaying resolved YAML)
are a brief aside in Act 5, not the focus.

> Note on version numbers: the page version is `v<+pipeline.sequenceId>`, which
> increments every run. In a fresh project the first two runs are v1 and v2; in
> a project already used for setup runs they'll be higher. The acts below use
> **vN** and **vN+1** for two consecutive runs — on camera, read out whatever
> your actual build numbers are.

## Video Demonstration Script and Production Notes

### Act 1 — Overview and Setup (2–3 min)

- Overview of the demo scenario and the four controls to be covered
- Walkthrough of setup:
  - Show the Harness Delegate running in the cluster
  - Show the three connectors (Kubernetes, Container Registry, GitHub)
  - Show the Service — note the ConfigMap is a Service manifest and the Values YAML path is `k8s/<+env.name>.yaml` — the Environments (named Dev and Prod), and the Infrastructure definitions (release name `release-<+INFRA_KEY_SHORT_ID>`)
  - Import the pipeline from Git and walk through the structure
- Highlight the three stages:
  - **Build** (always runs): builds and pushes the image, tagged `v<+pipeline.sequenceId>` — first sighting of an execution-time variable
  - **Deploy to Dev** (always runs): rolling deploy of Deployment, Service, and versioned ConfigMap; reads the artifact name/tag onto the page
  - **Deploy to Prod** (conditional): guarded by `target_envs.contains("prod")`
- Show the two Input Sets (dev-only and full-release) and that they set `target_envs`

#### Script (TBD)

### Act 2 — Control 1: Input Sets; deploy vN (2–3 min)

- Run the pipeline and choose the **Full Release** Input Set; show how the Input Set populates `target_envs = dev,prod`
- Show the Build stage completing — the image is pushed tagged with this run's version
- Show Deploy to Dev and Deploy to Prod succeed (no prompts; the run proceeds straight through)
- Call out the version number for this run (**vN**)
- Visit the Dev URL: page shows vN, blue Dev badge, and the image name:tag
- Visit the Prod URL: page shows vN, green Prod badge, same image name:tag
- Point out that the image reference on the page came from the artifact the Build stage produced — read in the deploy stage at execution time (Control 2 preview)

#### Script (TBD)

### Act 3 — Control 2: Execution-time variables; deploy vN+1 (2–3 min)

- Run again with **Full Release**; the version auto-increments — nothing typed
- Show both environments update; note the new version number (**vN+1**)
- On the page, show the version and the image tag both advanced to vN+1 — emphasize these values are computed at execution time (sequence id; artifact tag read downstream), not authored in advance
- This vN+1 release is the one we'll roll back from

#### Script (TBD)

### Act 4 — Control 3: Conditional execution; Dev-Only Input Set (1–2 min)

- Run with the **Dev Only** Input Set (`target_envs = dev`)
- Show the Prod stage is **skipped** — the `when` condition `target_envs.contains("prod")` evaluates false
- Contrast with Act 2/3, where Full Release made the same condition true
- Briefly: the Input Set value is merged into the pipeline at run start, which is what the condition then evaluates

#### Script (TBD)

### Act 5 — Control 4: Post-prod rollback (3–4 min)

- From Deployments (or Services → Instances), trigger rollback of the **vN+1** Prod deployment
- Show the rollback execution run and complete
- Visit the Prod URL: page shows **vN** again, with the vN image reference — the visual payoff
- Brief aside (good-to-know, keep it short): a post-prod rollback is a *separate
  execution*, not a re-run with rollback toggled on. It replays the original
  run's resolved YAML and runs only the rollback steps. Optional on-screen proof:
  `<+pipeline.executionMode>` resolves to `POST_EXECUTION_ROLLBACK`. Because the
  original resolved YAML is replayed, Input Sets aren't re-applied and conditions
  aren't re-evaluated — the recorded outcome is what comes back.
- Recap the four controls the learner just used: Input Sets, execution-time
  variables, conditional execution, post-prod rollback

#### Script (TBD)
