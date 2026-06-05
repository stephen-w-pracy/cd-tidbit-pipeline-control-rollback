# Corrections Spec (Draft)

This document records correctness issues found in the draft repo and the fixes
applied before the Tidbit ships, plus the design decisions that shaped the final
demo. Each correctness item is grounded in the Harness CD documentation (paths
cited relative to the developer-hub docs tree). Items here supersede the README,
`build.md`, and pipeline YAML where they conflict.

Status legend: **Verified** = confirmed against Harness docs; **Decision** =
design choice recorded for parity.

---

## 0. Framing: four parallel controls, not three-controls-through-rollback — **Decision**

The intermediate skill statement is:

> Pipeline Controls: Use Input Sets, execution-time variables, conditional
> execution, and post-prod rollback.

This is read as **four coordinate controls the learner should be able to use**,
demonstrated in the natural order of a deploy-and-recover cycle — not as three
controls examined through the lens of rollback. Supporting evidence:

- It is one of three pipeline-control skills across the 50-skill curriculum, one
  per tier. Beginner: "Test manual triggers and runtime inputs." Intermediate
  (this one). Advanced: "Implement matrix, chained, or looping executions."
- This is the *only* explicit mention of Input Sets, execution-time variables,
  and conditional execution in the whole curriculum, so the tidbit's job is to
  let a learner *use* each one.
- Deep rollback-interaction behavior (what each control does during a rollback)
  is advanced systems behavior; if the curriculum wanted it, the advanced tier
  is where it would sit, and it isn't there.

Consequence: rollback is the closing beat (recover from the run you configured),
demonstrated as a control in its own right. The "behavior of each control during
rollback" material is reduced to a brief good-to-know aside, not the spine. The
learning objectives are therefore four flat "can do X" statements (see
`build.md`).

---

## 1. `env_color` cannot vary per environment as written — **Verified**

### Symptom

The badge accent color is meant to differ by environment (Dev blue, Prod
green). It does not. When the pipeline runs via the `full-release` Input Set,
both Dev and Prod render the same color.

### Root cause

`k8s/configmap.yaml` referenced the color through a Harness *expression*:

```
background: <+pipeline.variables.env_color>;
```

A Harness expression like this resolves correctly at deploy time (the same
mechanism that resolves `<+artifacts.primary.image>`), so the value is not
*invalid* — but it resolves to the single pipeline-variable value for the whole
run. There is only one `env_color` pipeline variable per execution, so Dev and
Prod cannot differ.

The draft *attempted* to vary the color with per-stage inline `Values` overrides
on each K8sApply step (`env_overrides` → `env_color: "#0d6efd"` / `"#198754"`).
Those overrides were never consumed, because the ConfigMap read a pipeline
variable, not a values key. The override mechanism and the manifest reference
were disconnected.

### Why the override doc matters here

Harness draws a clear line between the two mechanisms:

> Harness Variables and Expressions may be added to values.yaml, not the
> manifests themselves. This provides more flexibility.
>
> — `continuous-delivery/deploy-srv-diff-platforms/kubernetes/cd-k8s-ref/example-kubernetes-manifests-using-go-templating.md`

Per-resource variation is the job of **Go templating** (`{{.Values.x}}`) fed by
a values file, not of a global `<+...>` expression. Harness K8s manifests use
Go templating plus Sprig functions; values files support both Go templating and
Harness expressions.

> For Kubernetes manifests, the values file uses Go templating to template
> manifest files.
>
> — `continuous-delivery/deploy-srv-diff-platforms/kubernetes/cd-kubernetes-category/add-and-override-values-yaml-files.md`

### Fix (applied)

`k8s/configmap.yaml` now uses Go template keys: `{{.Values.env_color}}`,
`{{.Values.env_name}}`, `{{.Values.app_version}}`, `{{.Values.image_name}}`,
`{{.Values.image_tag}}`. Per-environment values come from `k8s/Dev.yaml` and
`k8s/Prod.yaml`, selected by the Service's Values YAML path `k8s/<+env.name>.yaml`.

> You can override the values YAML file for a stage's Environment by mapping the
> Environment name to the values file or folder. Next, you use the `<+env.name>`
> Harness expression in the values YAML path.
>
> — `add-and-override-values-yaml-files.md`

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

The draft applied `configmap.yaml` through a **K8sApply** step, separate from
the Service manifests deployed by **K8sRollingDeploy**. The Apply step does not
version ConfigMaps, and has no rollback:

> The Apply step does not version ConfigMap and Secret objects. ConfigMap and
> Secret objects are overwritten on each deployment.
>
> — `continuous-delivery/deploy-srv-diff-platforms/kubernetes/kubernetes-executions/deploy-manifests-using-apply-step.md`

The same doc's Rolling-vs-Apply table is explicit: the Apply step has **no
rollback**. So `K8sRollingRollback` reverts the Deployment, but not the
Apply-applied ConfigMap.

### Why default versioning fixes both problems

> By default, all ConfigMaps and Secrets are versioned by Harness. The
> corresponding references for these ConfigMaps and Secrets in other manifest
> objects are also updated (for example, managed workloads like Deployment...).
>
> — `continuous-delivery/deploy-srv-diff-platforms/kubernetes/cd-k8s-ref/kubernetes-releases-and-versioning.md`

Because the Deployment's ConfigMap reference changes each release, the
Deployment spec changes, pods roll, and the new page content actually appears.
Release history is the incrementing series that rollback replays, so reverting
the release reverts the Deployment's ConfigMap reference along with the image —
the badge flips back.

### Fix (applied)

- Both K8sApply steps and their inline `env_overrides` removed from the pipeline.
- `k8s/configmap.yaml` is now part of the Service's **Manifests** section
  alongside the Deployment and Service, so it is deployed and versioned by the
  rolling step.
- `K8sRollingDeploy` / `K8sRollingRollback` carry it forward and back.

### Related note (declarative rollback)

`kubernetes-rollback.md` documents an alternative — *declarative rollback*
(`enableDeclarativeRollback: true`) — which hashes ConfigMaps/Secrets onto the
workload so config-only changes reliably restart pods, for rolling and
blue/green. This demo uses standard rolling rollback with default versioning,
which is sufficient because the Deployment's ConfigMap reference changes per
release. Declarative rollback is noted as a more robust alternative but is not
required here.

---

## 3. Release name must be set for reliable versioning/rollback — **Verified**

### Issue

Versioning and rollback chains depend on a unique, stable **Release Name** per
deployment target.

> Do not change the release name value between deployments... If you change the
> release name value between deployments, this will reset the versioning number
> and will stop rollbacks up to that point (breaking the versioning chain).
>
> — `kubernetes-releases-and-versioning.md`

### Fix (applied)

README Step 7 instructs leaving the infra **Release Name** at the pre-populated
default `release-<+INFRA_KEY_SHORT_ID>`.

> Harness now uses `<+INFRA_KEY_SHORT_ID>` in the default expression that
> Harness uses to generate a release name... the Release name field... is now
> pre-populated with `release-<+INFRA_KEY_SHORT_ID>`.
>
> — `platform/variables-and-expressions/harness-expressions-reference.md`

This demo deploys one service to two namespaces, so the infra key differs per
environment and uniqueness is satisfied naturally.

---

## 4. Version label from the execution sequence id — **Verified**

### Issue

The draft hand-entered `app_version` as `v1`/`v2` (dev-only set `v1`;
full-release prompted via execution-time input). This made the learner type the
"version," which muddied what was being demonstrated and isn't how real
pipelines version.

### Fix (applied)

`app_version` is `v<+pipeline.sequenceId>`.

> `<+pipeline.sequenceId>`: The incremental sequential Id for the execution of a
> pipeline... The first run of a pipeline receives a sequence Id of 1 and each
> subsequent execution is incremented by 1.
>
> — `platform/variables-and-expressions/harness-expressions-reference.md`

The tag and badge increment automatically per run, with no manual entry. This
doubles as the primary demonstration of the **execution-time variable** control:
the value does not exist until the run starts.

### Narrative caveat

The clean "v1 → v2 → rollback to v1" storyline assumes the first two runs are 1
and 2. A learner who ran the pipeline during setup will see higher numbers. The
README and `video.md` use **vN / vN+1** and tell the learner to read their own
build numbers.

---

## 5. Execution-time variables: drop the prompt, use naturally-computed values — **Decision + Verified**

### Decision

The draft demonstrated "execution-time variables" with the narrowest option —
an `executionInput()` prompt on `app_version`. That was set aside for two
reasons:

1. "Execution-time variable" is broader than `executionInput()`. It means *any*
   value resolved at execution time, most of which are not prompts.
2. A mid-run prompt adds on-camera risk (it has a timeout that can fail the run)
   and manual typing that muddies the demo.

The control is now demonstrated with **naturally-computed execution-time
values**, no prompt:

- **`v<+pipeline.sequenceId>`** in the CI stage — tags the image and becomes the
  version label. Undefined until the run starts.
- **Artifact expressions read back in the CD stage** — the Dev and Prod values
  files set `image_name: <+artifacts.primary.imagePath>` and
  `image_tag: <+artifacts.primary.tag>`, which the ConfigMap renders onto both
  pages. This shows a later stage consuming the artifact an earlier stage built,
  without storing anything on the build runner.

### Verification

Artifact expressions are documented for use in values files:

> Use `<+artifacts.primary.image>` or `<+artifacts.primary.imagePath>` in your
> `values.yaml` file when you want to deploy an artifact you have added to the
> Artifacts section of a CD stage service definition.
>
> `<+artifacts.primary.imagePath>`: The image name, such as `nginx`.
> `<+artifacts.primary.tag>`: example value `stable`.
>
> — `platform/variables-and-expressions/harness-expressions-reference.md`
> (Service artifacts expressions)

The same reference confirms `<+pipeline.sequenceId>` and shows the canonical
pattern of tagging a CI build with it and pulling the same tag in a later stage.

### Consequence

- The `prod_confirm` execution-time input and its confirmation step are removed
  from the Prod stage.
- `executionInput()` is not used anywhere in the final demo. (Its syntax was
  verified correct, for the record: `<+input>.executionInput()`, per
  `runtime-input-usage.md` — but it is not needed.)
- Conditional execution is still cleanly shown by the Prod stage's `when`
  condition on `target_envs`; the removed step did not affect it.

---

## 6. `validate-setup.sh` arithmetic under `set -e` — **Fixed**

`((PASS++))` returns a non-zero status when the pre-increment value is 0, which
under `set -euo pipefail` aborts the script. Replaced with `PASS=$((PASS + 1))`.
The manifest dry-run warning text was also updated to mention Go templating (not
just Harness expressions), since the templated manifests won't validate under a
raw `kubectl --dry-run`.

---

## 7. Deployment used the wrong artifact expression — **Verified + Fixed**

`k8s/deployment.yaml` set the container image to `<+artifact.image>` (singular
`artifact`, no `.primary`). The documented expression is the plural form with
the artifact identifier:

> `<+artifacts.primary.image>`: The full location path to the Docker image...
>
> — `platform/variables-and-expressions/harness-expressions-reference.md`
> (Service artifacts expressions)

The singular `<+artifact.image>` is not a documented expression and would likely
fail to resolve, leaving an invalid image reference. Changed to
`<+artifacts.primary.image>`, consistent with the values files and the
deployment-type artifact configuration. (Pre-existing in the draft; not
introduced by these changes.)

---

## Rollback behavior (brief aside, not the spine) — partially verified

Kept as a short good-to-know in the README/video, no longer the centerpiece. A
post-prod rollback is a **separate execution** (mode
`POST_EXECUTION_ROLLBACK`) that replays the original run's resolved YAML and
runs only rollback steps — it is *not* a re-run with rollback steps toggled on.

Verified from `manage-deployments/rollback-deployments.md` and the expressions
reference: new execution with its own sequence id; only rollback steps run;
original execution's processed YAML is the reference; rollback-step expressions
resolve from the original execution; `<+pipeline.executionMode>` and
`<+pipeline.originalExecution.*>` (the latter resolves only during rollback).

**Not verified / deliberately not relied upon:** whether an `executionInput()`
on a rollback node re-prompts during a post-prod rollback. Since the prompt was
dropped (item 5), the tidbit no longer depends on this claim. If future work
re-introduces a rollback-node input, this must be confirmed in-product first.

---

## Open verification items (before recording)

These rest on documentation, not an in-product run. Worth a smoke test:

1. **Artifact expressions resolve inside a values file selected by `<+env.name>`**
   in *this* stage layout (Dev defines the artifact via `serviceInputs`; Prod
   inherits via `useFromStage`). Documented as supported; not run end-to-end here.
2. **Standard rolling rollback reverts the ConfigMap content visibly** (pods
   restart) given default versioning. Mechanism verified from docs; the
   declarative-rollback note (§2) is the fallback if it doesn't.

---

## Parity checklist

- [x] `k8s/configmap.yaml` uses Go template keys (color, env name, version, image name/tag)
- [x] `Dev.yaml` / `Prod.yaml` values files added; Service values path uses `<+env.name>`
- [x] Image name + tag shown on both pages via artifact expressions
- [x] `k8s/deployment.yaml` uses `<+artifacts.primary.image>`
- [x] Both K8sApply steps removed from `.harness/pipeline.yaml`
- [x] `prod_confirm` execution-time input and confirm step removed
- [x] `app_version` set to `v<+pipeline.sequenceId>`
- [x] `validate-setup.sh` arithmetic fixed
- [x] README reflects flat four-control objectives + build-number narrative
- [x] `build.md` objectives, controls table, variables table updated
- [x] `video.md` acts updated (no prompt; image-on-page beat; rollback as closing control)
- [x] `CLAUDE.md` architecture notes updated
