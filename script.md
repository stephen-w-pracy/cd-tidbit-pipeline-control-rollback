# Narrator Script — Pipeline Controls Tidbit

Read this aloud while performing the actions described in brackets. Each act maps
to the production spec in `specs/video.md`.

---

## Act 1 — Overview and Setup (2–3 min)

### Narration

> In this tidbit, we'll use four Harness pipeline controls together in a real
> deploy-and-recover workflow. By the end, you'll have used Input Sets,
> execution-time variables, conditional execution, and post-prod rollback.

> Let me show you what's already set up.

**[Show Pipeline Studio — three stages visible]**

> Here's our pipeline. Three stages: Build, Deploy to Dev, and Deploy to Prod.
> The Build stage pushes a container image tagged with the pipeline's sequence
> id — that's our version number, and it's the first execution-time variable
> we'll see. It doesn't exist until the run starts.

**[Click into the Deploy to Prod stage → Advanced → Conditional Execution]**

> The Prod stage has a condition: it only runs when `target_envs` contains
> "prod." That's our conditional execution control. What sets that variable?
> Input Sets.

**[Navigate to Input Sets tab]**

> We have two Input Sets. "Dev Only" sets `target_envs` to just `dev` — Prod
> will be skipped. "Full Release" sets it to `dev,prod` — both environments
> deploy.

**[Navigate to Services → pipeline-controls-demo]**

> Our Service pulls Kubernetes manifests from GitHub — a Deployment, Service,
> and ConfigMap. The ConfigMap is the HTML page you'll see in the browser. It's
> part of the Service manifests, which means Harness versions it. That's what
> makes rollback work visually — the page content rolls back with the image.

> The Values YAML path uses an expression: `k8s/<+env.name>.yaml`. Dev gets
> `Dev.yaml` with a blue accent, Prod gets `Prod.yaml` with green. Same image,
> different config.

**[Navigate to Environments → show Dev and Prod]**

> Two environments: Dev is Pre-Production, Prod is Production. Each has an
> infrastructure definition pointing at its namespace.

> That's the setup. Let's run it.

---

## Act 2 — Input Sets + Conditional Execution (2–3 min)

### Narration

> Let's start with the Dev Only input set — this shows both Input Sets and
> conditional execution in one run.

**[Click Run on the pipeline]**

> I'll select the Dev Only input set.

**[Select "Dev Only" from the input set dropdown]**

> Notice it sets `target_envs` to `dev`. That's the value the Prod stage's
> condition will evaluate.

**[Click Run Pipeline]**

> Build is running... it pushes the image tagged with this run's version.

**[Wait for Build to complete, then Dev deploy]**

> Dev deployed successfully. Now look at the Prod stage.

**[Point to the Prod stage showing "Skipped" or "Condition not met"]**

> Skipped. The condition `"dev".contains("prod")` is false. The Input Set chose
> what this run does — it targeted Dev only, so Prod didn't run.

> Let's verify Dev is live.

**[Switch to terminal, run port-forward]**

```bash
kubectl port-forward svc/pipeline-controls-demo 8080:80 -n web-dev
```

**[Open browser to localhost:8080]**

> There's our page. Blue badge says Dev. The version is v1 — that came from
> the sequence id. And the image URI at the bottom shows exactly what's running.

---

## Act 3 — Execution-time Variables (2–3 min)

### Narration

> Now let's talk about execution-time variables. I'll run with Full Release
> this time.

**[Click Run → select Full Release input set]**

> Full Release sets `target_envs` to `dev,prod`. But notice — I'm not typing a
> version number anywhere. The version comes from the sequence id, which
> Harness computes when the run starts.

**[Click Run Pipeline]**

> This is run number 2, so the version will be v2. Let's watch.

**[Wait for Build to complete]**

> The Build stage tagged and pushed the image as v2. That's our first
> execution-time variable — computed at run start, used downstream.

**[Wait for both deploys to complete]**

> Both stages succeeded — Dev and Prod. The condition
> `"dev,prod".contains("prod")` was true this time.

> Let's check Prod.

**[Switch to terminal]**

```bash
kubectl port-forward svc/pipeline-controls-demo 8081:80 -n web-prod
```

**[Open browser to localhost:8081]**

> Green badge says Prod. Version v2. And here's the second execution-time
> variable — the image URI. This comes from `<+artifact.image>`, which Harness
> resolved from the artifact the Build stage pushed. A later stage reading
> what an earlier stage produced, at execution time.

> Same image on both environments. Only the badge color and environment name
> differ — that's the per-environment values file at work.

---

## Act 4 — Full Release Again (1–2 min)

### Narration

> I need to run Full Release one more time. Rollback needs at least two
> successful deployments to work — it needs a version to roll back *to*.

**[Click Run → select Full Release → Run Pipeline]**

> This will be v3.

**[Wait for execution to complete — all three stages green]**

> Done. Prod now has two successful releases in its history: v2 and v3.
> Let's verify.

**[Port-forward to Prod, show v3 in browser]**

> v3, green badge. Now let's recover v2.

---

## Act 5 — Post-prod Rollback (3–4 min)

### Narration

> For the final control, I'll trigger a post-prod rollback. This isn't a
> re-run of the pipeline — it's a separate execution that reverts to the prior
> release.

**[Navigate: Deployments (global nav) → Services]**

> From the global navigation, I go to Deployments, then Services.

**[Click pipeline-controls-demo]**

> Here's our service. I can see it's deployed to both environments.

**[Click "View Instances and Rollback"]**

> This panel shows each environment's current state. I'll click Rollback on the
> Prod row.

**[Click Rollback on the Prod row]**

> The dialog confirms what's about to happen. Current artifact: v3. Rollback
> artifact: v2. That's the prior successful release.

**[Click Confirm]**

> A rollback execution starts. Let's watch the logs.

**[Show execution logs — Initialize, Rollback, Wait for Steady State]**

> It found the previous release, rolled back the Deployment, and waited for
> steady state. Done.

> Let's check the page.

**[Port-forward to Prod, refresh browser]**

> And there it is — v2 is back. The version reverted, the image URI reverted.
> The ConfigMap rolled back with the Deployment because it's a versioned
> Service manifest.

**[Port-forward to Dev briefly]**

> Dev is still on v3. Only Prod was rolled back.

### Brief Aside

> One thing worth knowing: a post-prod rollback is a separate execution, not
> the same pipeline re-run. Input Sets aren't re-applied, conditions aren't
> re-evaluated. Harness replays the original run's resolved state and runs only
> the rollback steps. That's why the prior version comes back cleanly.

---

## Closing (30 seconds)

### Narration

> That's four pipeline controls in one workflow.
>
> **Input Sets** chose what deployed.
> **Execution-time variables** computed the version and artifact details at runtime.
> **Conditional execution** skipped or ran Prod based on the input.
> **Post-prod rollback** recovered the prior version when we needed it.
>
> The README in this repo has the full setup guide if you want to try it
> yourself. Thanks for watching.

**[End card]**
