# Video Production Spec

This spec defines the structure, timing, and shot list for the Technical Tidbit
video. It is a production reference — what to show, in what order, and how long
each segment should take.

For the narrator's spoken script and step-by-step demonstration actions, see
[script.md](../script.md) in the repo root.

For the overall demo design, learning objectives, and implementation details,
see [build.md](./build.md). For verified correctness decisions, see
[corrections.md](./corrections.md).

---

## Format

- **Length:** 10–15 minutes
- **Style:** Screen recording with voiceover narration
- **Resolution:** 1920x1080 minimum
- **Framing:** Four pipeline controls demonstrated in lifecycle order

---

## Act Structure

| Act | Title | Duration | Controls Demonstrated |
|-----|-------|----------|----------------------|
| 1 | Overview and Setup | 2–3 min | (context) |
| 2 | Input Sets + Conditional Execution | 2–3 min | Input Sets, Conditional execution |
| 3 | Execution-time Variables | 2–3 min | Execution-time variables |
| 4 | Full Release + Rollback Setup | 2–3 min | Input Sets (revisited) |
| 5 | Post-prod Rollback | 2–3 min | Post-prod rollback |

---

## Act 1 — Overview and Setup

**Purpose:** Orient the viewer. Show what exists, set expectations.

### Shots

1. **Pipeline Studio** — show the three-stage pipeline (Build → Dev → Prod)
2. **Service configuration** — manifest paths, values YAML path `k8s/<+env.name>.yaml`, artifact source
3. **Environments** — Dev (PreProduction) and Prod (Production)
4. **Infrastructure definitions** — namespaces `web-dev` / `web-prod`, release name default
5. **Input Sets** — show both: Dev Only (`target_envs: dev`) and Full Release (`target_envs: dev,prod`)
6. **Connectors** — brief: GitHub, GHCR, K8s cluster

### Key Callouts

- The ConfigMap is a Service manifest (versioned by Harness, rolls back with the Deployment)
- `app_version` is `v<+pipeline.sequenceId>` — first mention of execution-time variables
- Prod stage has a `when` condition on `target_envs`
- Two Input Sets control what `target_envs` resolves to

---

## Act 2 — Input Sets + Conditional Execution (Dev Only)

**Purpose:** Show Input Sets driving the pipeline, and conditional execution skipping Prod.

**Pipeline run:** Dev Only input set → produces **v1**

### Shots

1. **Run Pipeline dialog** — select Dev Only input set, show `target_envs: dev` populated
2. **Execution view** — Build completes, Dev deploys, Prod stage shows "Skipped" with condition
3. **Prod stage detail** — click into it, show the `when` condition evaluation (false)
4. **Dev app** — port-forward, show the page with blue badge, v1, image URI

### Key Callouts

- The Input Set set `target_envs` to `dev`
- The Prod stage's `when` condition: `"dev".contains("prod")` → false → skipped
- Dev deployed successfully with the auto-generated version

---

## Act 3 — Execution-time Variables (Full Release v2)

**Purpose:** Show values computed at execution time — version auto-increments, artifact details appear on the page.

**Pipeline run:** Full Release input set → produces **v2**

### Shots

1. **Run Pipeline dialog** — select Full Release, show `target_envs: dev,prod`
2. **Build stage** — show the image being tagged with v2 (no manual entry)
3. **Deploy to Prod — Service step logs** — show artifact version resolving to v2
4. **Dev app** — show v2, blue badge
5. **Prod app** — show v2, green badge, same image URI

### Key Callouts

- Version incremented automatically (v1 → v2) — nothing typed
- The page displays `<+artifact.version>` and `<+artifact.image>` — values resolved at execution time
- Same image deployed to both environments; only the ConfigMap values differ (color, env name)
- Prod ran this time because `"dev,prod".contains("prod")` → true

---

## Act 4 — Full Release Again (v3, Rollback Setup)

**Purpose:** Create the second successful Prod deploy (required for rollback).

**Pipeline run:** Full Release input set → produces **v3**

### Shots

1. **Run Pipeline** — brief, no need to re-explain
2. **Execution completes** — all three stages green
3. **Prod app** — show v3, green badge

### Key Callouts

- Rollback needs two successful deploys to work — this is the second
- v3 is the "current" version we'll roll back from
- Brief: "Now Prod has a history: v2, then v3. Let's recover v2."

---

## Act 5 — Post-prod Rollback

**Purpose:** Demonstrate rollback and the visual payoff.

### Shots

1. **Navigation** — Deployments (global nav) → Services → pipeline-controls-demo
2. **View Instances and Rollback** — click the button, show the panel with Prod row
3. **Rollback dialog** — shows current artifact (v3) and rollback target (v2)
4. **Confirm** — click Confirm
5. **Rollback execution** — show the execution logs (Initialize, Rollback, Wait for Steady State)
6. **Prod app** — show v2 restored (green badge, previous version, previous image URI)
7. **Dev app** — still on v3 (only Prod was rolled back)

### Key Callouts

- Rollback is triggered from the Services panel, not by re-running the pipeline
- It's a separate execution that replays the original resolved YAML
- Both the Deployment and ConfigMap reverted (because the ConfigMap is a versioned Service manifest)
- The version and image on the page went backward — visual proof it worked

### Brief Aside (30 seconds max)

- A post-prod rollback is mode `POST_EXECUTION_ROLLBACK`
- Input Sets aren't re-applied; conditions aren't re-evaluated
- The prior release's state is what comes back

---

## Closing (30 seconds)

- Recap: four controls used in one workflow
  1. Input Sets — chose what deployed
  2. Execution-time variables — version and artifact details computed at runtime
  3. Conditional execution — Prod skipped or ran based on the input
  4. Post-prod rollback — recovered the prior version
- Point to the README for self-guided practice
- End card

---

## Production Notes

- **Version numbers:** Use a fresh project or reset the sequence if possible so
  the video shows v1/v2/v3. If higher numbers appear, that's fine — just read
  them naturally.
- **Screenshots for README:** Capture final screenshots during the video recording
  session (same versions, same state) so README images match the video exactly.
- **Pauses:** Leave 1–2 seconds of dead air between acts for editing cuts.
- **Browser tabs:** Pre-open port-forward terminals so the switch to the app page
  is instant.
