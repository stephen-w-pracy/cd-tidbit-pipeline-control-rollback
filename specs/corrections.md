# Corrections Spec (Draft)

This document records correctness issues found in the draft repo and the fixes
to apply before the Tidbit ships. Each item is grounded in the Harness CD
documentation (paths cited relative to the developer-hub docs tree). Items here
supersede the current README, `build.md`, and pipeline YAML where they conflict;
all three must be brought back into parity once these fixes land.

Status legend: **Verified** = confirmed against Harness docs.

---

## 1. `env_color` cannot vary per environment as written — **Verified**

### Symptom

The badge accent color is meant to differ by environment (Dev blue, Prod
green). It does not. When the pipeline runs via the `full-release` Input Set,
both Dev and Prod render the same color.

### Root cause

`k8s/configmap.yaml` references the color through a Harness *expression*:

```
background: <+pipeline.variables.env_color>;
```

A Harness expression like this resolves correctly at deploy time (the same
mechanism that resolves `<+artifact.image>`), so the value is not *invalid* —
but it resolves to the single pipeline-variable value for the whole run. There
is only one `env_color` pipeline variable per execution, so Dev and Prod cannot
differ.

The draft *attempts* to vary the color with per-stage inline `Values` overrides
on each K8sApply step (`env_overrides` → `env_color: "#0d6efd"` / `"#198754"`).
Those overrides are never consumed, because the ConfigMap reads a pipeline
variable, not a values key. The override mechanism and the manifest reference
are disconnected.

### Why the override doc matters here

Harness draws a clear line between the two mechanisms:

> Harness Variables and Expressions may be added to values.yaml, not the
> manifests themselves. This provides more flexibility.
>
> — `continuous-delivery/deploy-srv-diff-platforms/kubernetes/cd-k8s-ref/example-kubernetes-manifests-using-go-templating.md`

Per-resource variation is the job of **Go templating** (`{{.Values.x}}`) fed by
a values file, not of a global `<+...>` expression. Harness K8s manifests use
Go templating (Go template v0.4.5) plus Sprig functions; values files support
both Go templating and Harness expressions.

> For Kubernetes manifests, the values file uses Go templating to template
> manifest files.
>
> — `continuous-delivery/deploy-srv-diff-platforms/kubernetes/cd-kubernetes-category/add-and-override-values-yaml-files.md`

### Fix

Change the ConfigMap to use a Go template key for the color (and version — see
item 4):

```
background: {{.Values.env_color}};
```

Supply the value per environment using a values file whose path is keyed on the
environment name. The override doc documents this exact pattern: commit
`Dev.yaml` and `Prod.yaml`, and point the Service's values-file path at
`<+env.name>.yaml`. Harness selects the right file per stage automatically.

> You can override the values YAML file for a stage's Environment by mapping the
> Environment name to the values file or folder. Next, you use the `<+env.name>`
> Harness expression in the values YAML path.
>
> — `add-and-override-values-yaml-files.md`

This keeps the draft's original intent (per-stage color) but wires it through
the mechanism that actually works.

### Alternatives considered

- Key the badge off `<+env.name>` only (already renders "Dev"/"Prod"
  correctly) and drop the color story — simplest, but loses the visual contrast.
- Move `env_color` from a pipeline variable to an **environment** variable and
  reference `<+env.variables.env_color>` — works, but a values file keyed on
  `<+env.name>` is more idiomatic and pairs naturally with item 2.

---

## 2. ConfigMap applied via K8sApply is unversioned and outside rollback — **Verified**

### Symptom

Two related risks to the demo's central payoff:

1. After a deploy, the page may not visibly update, because a Deployment that
   mounts a ConfigMap as a volume does not restart pods when the ConfigMap
   content changes on its own.
2. On rollback, the badge may not revert, because the rollback step does not
   undo the separately-applied ConfigMap.

### Root cause

The draft applies `configmap.yaml` through a **K8sApply** step, separate from
the Service manifests deployed by **K8sRollingDeploy**. The Apply step does not
version ConfigMaps, and has no rollback:

> The Apply step does not version ConfigMap and Secret objects. ConfigMap and
> Secret objects are overwritten on each deployment.
>
> — `continuous-delivery/deploy-srv-diff-platforms/kubernetes/kubernetes-executions/deploy-manifests-using-apply-step.md`

The same doc's Rolling-vs-Apply table is explicit: the Apply step has **no
rollback** (Rolling Deployment step: Rollback = Yes; Apply step: Rollback = No).
So `K8sRollingRollback` reverts the Deployment, but not the Apply-applied
ConfigMap.

### Why default versioning fixes both problems

When a ConfigMap is part of the Service manifests (deployed by the rolling
step), Harness versions it by default and rewrites the references to it in
managed workloads:

> By default, all ConfigMaps and Secrets are versioned by Harness. The
> corresponding references for these ConfigMaps and Secrets in other manifest
> objects are also updated (for example, managed workloads like Deployment...).
>
> — `continuous-delivery/deploy-srv-diff-platforms/kubernetes/cd-k8s-ref/kubernetes-releases-and-versioning.md`

Because the Deployment's ConfigMap reference changes each release, the
Deployment spec changes, pods roll, and the new page content actually appears.
Release history is the incrementing series that rollback replays, so reverting
the release reverts the Deployment's ConfigMap reference along with the image —
the badge flips back. That is the visual payoff working end to end.

### Fix

- Remove both K8sApply steps (`Apply_ConfigMap`, `Apply_ConfigMap_Prod`) and
  their inline `env_overrides`.
- Add `k8s/configmap.yaml` to the Service's **Manifests** section alongside the
  Deployment and Service so it is deployed (and versioned) by the rolling step.
- Let `K8sRollingDeploy` / `K8sRollingRollback` carry the version label and
  color forward and back.

### Knock-on README change

Currently README Step 8 lists `configmap.yaml` in the Service manifests *and*
the pipeline applies it via K8sApply — the same resource on two paths. After
this fix there is a single path (Service manifests), which also removes that
duplication.

---

## 3. Release name must be set for reliable versioning/rollback — **Verified**

### Issue

Versioning and rollback chains depend on a unique, stable **Release Name** per
deployment target. The draft does not mention setting it.

> Do not change the release name value between deployments... If you change the
> release name value between deployments, this will reset the versioning number
> and will stop rollbacks up to that point (breaking the versioning chain).
>
> — `kubernetes-releases-and-versioning.md`

### Fix

In each Infrastructure Definition (Dev and Prod), set **Release Name** to the
Harness-recommended default:

```
release-<+INFRA_KEY_SHORT_ID>
```

`<+INFRA_KEY>` is a hash of `serviceIdentifier-environmentIdentifier-connectorRef-namespace`;
`<+INFRA_KEY_SHORT_ID>` is the shortened form now pre-populated by Harness in the
infrastructure **Release Name** field.

> Harness now uses `<+INFRA_KEY_SHORT_ID>` in the default expression that
> Harness uses to generate a release name... the Release name field... is now
> pre-populated with `release-<+INFRA_KEY_SHORT_ID>`.
>
> — `platform/variables-and-expressions/harness-expressions-reference.md`

Because this demo deploys one service to two namespaces (`web-dev`,
`web-prod`), the infra key differs per environment, so uniqueness is satisfied
naturally. Add a one-line note to README setup confirming the field is left at
its default (don't blank it out).

---

## 4. Replace hard-coded `v1`/`v2` with the execution sequence — **Verified**

### Issue

`app_version` is hand-entered as `v1`/`v2` (dev-only sets `v1`; full-release
prompts via execution-time input). This makes the learner type the "version,"
which muddies what's being demonstrated and isn't how real pipelines version.

### Fix

Use the built-in incremental execution counter:

> `<+pipeline.sequenceId>`: The incremental sequential Id for the execution of a
> pipeline... The first run of a pipeline receives a sequence Id of 1 and each
> subsequent execution is incremented by 1.
>
> — `platform/variables-and-expressions/harness-expressions-reference.md`

Set `app_version` to `<+pipeline.sequenceId>` (or `v<+pipeline.sequenceId>` for
a nicer badge). The tag and badge then increment automatically per run, with no
manual entry.

### Narrative caveat

The script's clean "v1 → v2 → rollback to v1" storyline assumes the first two
runs are 1 and 2. A learner who ran the pipeline during setup will instead see,
e.g., `v7`/`v8`. Two options:

- **(Preferred)** Keep `sequenceId` for realism; update the script to say "note
  your two build numbers; you'll roll back from the higher to the lower."
- Keep a scripted display label (rename to `release_label`) for narrative
  cleanliness, but tag the *image* with `sequenceId` so image versioning is
  still realistic.

### Bonus teaching beats (rollback)

Two verified expressions make good on-screen "proof" moments in Act 5:

- `<+pipeline.executionMode>` resolves to `POST_EXECUTION_ROLLBACK` during a
  post-prod rollback — a clean way to show you're in a post-prod rollback.
- `<+pipeline.originalExecution.sequenceId>` references the original run's
  sequence Id, but **only resolves during a rollback execution**, not normal
  runs.

Both from `harness-expressions-reference.md`.

---

## 5. Execution-time input syntax — **Verified (correct)**

`full-release.yaml` uses `value: <+input>.executionInput()` for `app_version`.
This is the correct, current syntax.

> When writing pipelines in YAML, append the `executionInput()` method to
> `<+input>`. For example, `<+input>.executionInput()`.
>
> — `platform/variables-and-expressions/runtime-input-usage.md`

No syntax change required. However, two behaviors from the same doc affect how
(and whether) we keep this prompt:

- **Chaining with allowed values / defaults.** Mid-run input can be constrained:
  `<+input>.allowedValues(v1,v2).executionInput()` or
  `<+input>.allowedValues(v1,v2).default(v1).executionInput()`. Note
  `.allowedValues()` is deprecated in favor of `.selectOneFrom()` /
  `.selectManyFrom()`. Constraining a kept prompt makes the demo more robust.
- **Mid-run input times out and can fail the run.** Pipelines don't wait
  indefinitely; if no value is supplied in time, the run fails. A failure
  strategy (**Execution-time Inputs Timeout Errors** → **Proceed with Default
  Values**) can fall back to a default. Relevant on camera: a presenter talking
  through the prompt could hit the timeout mid-demo.

### Interaction with item 4

Adopting `<+pipeline.sequenceId>` for `app_version` (item 4) removes the
execution-time prompt for versioning, eliminating both the manual-typing
awkwardness and the timeout-during-demo risk. But execution-time input is one of
the four named pipeline controls the Tidbit must demonstrate, so it should not
vanish entirely. Recommended: keep an explicit, purpose-built execution-time
input elsewhere (e.g. a "confirm production deploy?" input or approval on the
Prod stage) rather than overloading the version field. This preserves the
control in the narrative while decoupling it from versioning.

---

## Parity checklist (after fixes land)

- [ ] `k8s/configmap.yaml` uses `{{.Values.app_version}}` / `{{.Values.env_color}}`
- [ ] `Dev.yaml` / `Prod.yaml` values files added; Service values path uses `<+env.name>`
- [ ] Both K8sApply steps removed from `.harness/pipeline.yaml`
- [ ] `configmap.yaml` listed once, in Service Manifests (README Step 8)
- [ ] README setup notes Release Name default `release-<+INFRA_KEY_SHORT_ID>`
- [ ] `app_version` set to `<+pipeline.sequenceId>` (or chosen variant)
- [ ] README "Run the Demo" and `video.md` Acts updated for build-number narrative
- [ ] `build.md` Pipeline Controls + Variables tables updated to match
- [ ] Execution-time input repositioned per item 5 (not overloading version field)
