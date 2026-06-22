# Harness Resource Map

The single source of truth for **how the `.harness/` and `k8s/` resources
reference each other**, and **which templating engine owns each token**. Use it
to answer "who references this identifier?" and "what resolves this `${...}` /
`<+...>` / `{{...}}`?" without grepping every file.

> Keep this in sync when you rename an identifier, add a cross-reference, or
> change a templated value. It is referenced from `CLAUDE.md`.

---

## 1. Identifier registry

Every Harness resource has a stable **identifier** (account-independent — these
are *not* templated). Display `name`s may differ from identifiers; both are
listed where they diverge.

| Resource | File | `identifier` | `name` |
|---|---|---|---|
| Pipeline | `.harness/pipeline.yaml` | `pipeline_controls_exemplar` | Pipeline Controls Exemplar |
| Service | `.harness/service.yaml` | `pipelinecontrolsdemo` | pipeline-controls-demo |
| Secret | `.harness/ghcr-token-secret.yaml` | `ghcr_token` | ghcr_token |
| GitHub connector | `.harness/connector-github.yaml` | `github` | pipeline-demo-github |
| GHCR connector | `.harness/connector-ghcr.yaml` | `pipelinedemoghcr` | pipeline-demo-ghcr |
| K8s connector | `.harness/connector-k8s.yaml` | `pipelinedemocluster` | pipeline-demo-cluster |
| Dev environment | `.harness/environment-dev.yaml` | `Dev` | Dev |
| Prod environment | `.harness/environment-prod.yaml` | `Prod` | Prod |
| Dev infra | `.harness/infra-dev.yaml` | `Dev_Infra` | Dev_Infra |
| Prod infra | `.harness/infra-prod.yaml` | `Prod_Infra` | Prod_Infra |
| Dev Only input set | `.harness/inputsets/dev-only.yaml` | `dev_only` | Dev Only |
| Full Release input set | `.harness/inputsets/full-release.yaml` | `full_release` | Full Release |
| Service manifest | inside `service.yaml` | `pipeline_controls` | — |
| Artifact source | inside `service.yaml` / pipeline `serviceInputs` | `pipelinecontrolsdemo` | — |

**Load-bearing names** (not free to rename):
- `Dev` / `Prod` environment names drive the values-file selection
  `k8s/<+env.name>.yaml` → must match `k8s/Dev.yaml` / `k8s/Prod.yaml`.
- The artifact source identifier in the pipeline `serviceInputs`
  (`pipelinecontrolsdemo`) must match the source identifier in `service.yaml`.

---

## 2. Reference graph (who points at whom)

```
pipeline.yaml (pipeline_controls_exemplar)
├─ properties.ci.codebase.connectorRef ──────────► github            (connector)
├─ Build step
│  └─ connectorRef ──────────────────────────────► pipelinedemoghcr  (connector)
│     repo: ghcr.io/${GITHUB_USERNAME}/pipeline-controls-demo
├─ Deploy_to_Dev
│  ├─ service.serviceRef ─────────────────────────► pipelinecontrolsdemo (service)
│  │  └─ serviceInputs…sources[].identifier ──────► pipelinecontrolsdemo (artifact source)
│  └─ environment.environmentRef         = <+input>  (supplied by input set → Dev)
│     environment.infrastructureDefinitions = <+input> (→ Dev_Infra)
└─ Deploy_to_Prod  (when target_envs.contains("prod"))
   ├─ service.serviceRef ─────────────────────────► pipelinecontrolsdemo (service)
   └─ environment.* = <+input>  (→ Prod / Prod_Infra via input set)

service.yaml (pipelinecontrolsdemo)
├─ manifests[].store.connectorRef ───────────────► github            (connector)
│  paths: k8s/deployment.yaml, service.yaml, configmap.yaml
│  valuesPaths: k8s/<+env.name>.yaml
└─ artifacts.primary.sources[].connectorRef ─────► github            (connector)
   packageName: pipeline-controls-demo (GithubPackageRegistry)

connector-github.yaml (github)
├─ authentication…tokenRef ──────────────────────► ghcr_token        (secret)
└─ apiAccess.spec.tokenRef ──────────────────────► ghcr_token        (secret)

connector-ghcr.yaml (pipelinedemoghcr)
└─ auth.spec.passwordRef ────────────────────────► ghcr_token        (secret)

connector-k8s.yaml (pipelinedemocluster)
└─ delegateSelectors[] = ${DELEGATE_SELECTOR}      (matches delegate tag)

infra-dev.yaml (Dev_Infra)
├─ environmentRef ───────────────────────────────► Dev                  (environment)
└─ spec.connectorRef ────────────────────────────► pipelinedemocluster  (connector)
   namespace: web-dev

infra-prod.yaml (Prod_Infra)
├─ environmentRef ───────────────────────────────► Prod                 (environment)
└─ spec.connectorRef ────────────────────────────► pipelinedemocluster  (connector)
   namespace: web-prod

inputsets/dev-only.yaml (dev_only) & full-release.yaml (full_release)
├─ pipeline.identifier ──────────────────────────► pipeline_controls_exemplar
├─ variables: target_envs = "dev"  /  "dev,prod"
├─ Deploy_to_Dev  → environmentRef Dev,  infra Dev_Infra
└─ Deploy_to_Prod → environmentRef Prod, infra Prod_Infra
```

**Note on the GitHub PAT:** the *same* secret `ghcr_token` backs three things —
the GitHub connector auth, the GitHub connector API access, and the GHCR
connector password. The PAT is also used directly (outside Harness) as the
cluster `ghcr-cred` imagePullSecret. One token, four consumers.

**Provisioning / dependency order** (used by `scripts/setup.sh`):
`project → namespaces + ghcr-cred → delegate → secret → connectors → service →
environments → infrastructures → pipeline → input sets`. Each resource must
exist before anything that references it.

---

## 3. Templating layers — who resolves what

Three engines resolve tokens, in this order. They never overlap; knowing the
owner tells you *when* and *by what* a token is replaced.

| Token form | Engine | Resolved when | Resolved by | Example |
|---|---|---|---|---|
| `${VAR}` | **envsubst** | Setup time | `scripts/setup.sh` (restricted var list) | `${GITHUB_USERNAME}`, `${HARNESS_ORG}` |
| `<+...>` | **Harness expressions** | Run / deploy time | Harness pipeline engine | `<+pipeline.sequenceId>`, `<+artifact.image>`, `<+env.name>`, `<+input>` |
| `{{.Values.x}}` | **Go templating** | Deploy time (after Harness resolves values) | Harness K8s manifest renderer | `{{.Values.image}}`, `{{.Values.env_color}}` |

### Where each appears

- **`${VAR}`** — only in `.harness/*.yaml` and `.harness/inputsets/*.yaml`
  (account/org/project/github/delegate values). **Never** in `k8s/`.
- **`<+...>`** — in `.harness/pipeline.yaml` (sequenceId, input, variables),
  `.harness/service.yaml` (`<+env.name>`, `<+input>`), `.harness/infra-*.yaml`
  (`<+INFRA_KEY_SHORT_ID>`), and `k8s/Dev.yaml` / `k8s/Prod.yaml`
  (`<+artifact.version>`, `<+artifact.image>`).
- **`{{.Values.x}}`** — only in the rendered K8s manifests
  `k8s/deployment.yaml` and `k8s/configmap.yaml`.

### The resolution chain that produces the page

```
pipeline run starts
  └─ <+pipeline.sequenceId>  ─► e.g. 2     (Harness, run time)
       app_version = "v2"
       image tag   = "v2"  ─► pushed to ghcr.io/<user>/pipeline-controls-demo:v2

deploy stage (Dev or Prod)
  └─ <+env.name> ─► "Dev"/"Prod"  selects k8s/Dev.yaml or k8s/Prod.yaml
       k8s/<env>.yaml:
         app_version: <+artifact.version>  ─► "v2"   (Harness resolves artifact)
         image:       <+artifact.image>    ─► ghcr.io/<user>/…:v2
       ↓ values handed to Go templater
       configmap.yaml: {{.Values.app_version}} ─► v2
                       {{.Values.env_color}}   ─► #198754 (Prod)
       deployment.yaml: {{.Values.image}}      ─► ghcr.io/<user>/…:v2
```

> **Why the `k8s/` manifests are not valid standalone YAML for `kubectl apply`:**
> they contain `{{.Values.x}}` that only the Harness renderer fills. The
> per-env values files in turn contain `<+artifact.*>` that only Harness
> resolves. Two engines feed each other before a manifest is apply-ready.

---

## 4. Quick lookups

**"What references identifier X?"** — see §2 graph. The commonly-confused ones:
- `ghcr_token` ← github connector (×2), ghcr connector.
- `github` connector ← service (manifest store + artifact source), pipeline (codebase).
- `pipelinedemocluster` ← infra-dev, infra-prod.
- `pipelinecontrolsdemo` (service) ← both deploy stages' `serviceRef`.

**"Which file feeds this `${VAR}`?"** — see [placeholders.md](placeholders.md).

**"If I edit a demo step, what else changes?"** — see [parity-matrix.md](parity-matrix.md).
