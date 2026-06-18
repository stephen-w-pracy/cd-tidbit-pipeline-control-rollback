# Plan: Learner Setup Automation Script

## Context

The tutorial requires ~15 manual Harness setup steps (connectors, secret,
service, environments, infra, pipeline, input sets) plus cluster prep and
delegate install. This is error-prone and slow for learners. Goal: a single
`scripts/setup.sh` that reads a small `.env` and provisions everything — Harness
resources via the NG REST API, cluster resources via kubectl, and the delegate
via helm.

Decisions:
- Templatize `.harness/` in place (single source of truth; rendered before API calls)
- Full scope: Harness API + cluster (namespaces, imagePullSecret) + delegate (helm)
- Create the project optionally (`CREATE_PROJECT` toggle for learners without project-create permission)

## Status

### Done

- **Identifier normalization** — `stephenwpracyghcr` → `ghcr`, `stephen-w-pracy-ghcr-token` → `ghcr_token`; all cross-references updated in `pipeline.yaml`, `service.yaml`, `connector-*.yaml`.
- **Templatized all `.harness/` YAML** with `${VAR}` placeholders. Render-tested: placeholders resolve, Harness `<+...>` expressions preserved, no stray `${...}` in any rendered file.
- **`.env.example`** created with `CREATE_PROJECT` toggle (handles the project-permission case).
- **`scripts/setup.sh`** written and syntax-checked. Flow: deps check → project (optional) → namespaces + `ghcr-cred` secret → delegate (Helm) → secret/connectors/service/envs/infra/pipeline/input-sets via API. Idempotent `upsert` helper (POST, fall back to PUT on conflict).
- **README** — added "Automated Setup (Optional)" section + a note on `${...}` placeholders for manual pasters.

### Placeholder variables

| Placeholder | Example value |
|---|---|
| `${HARNESS_ACCOUNT_ID}` | `SAn9tg9eRrWyEJyLZ01ibw` |
| `${HARNESS_ORG}` | `default` |
| `${HARNESS_PROJECT}` | `pipeline_controls` |
| `${GITHUB_USERNAME}` | `stephen-w-pracy` |
| `${GITHUB_REPO}` | `cd-tidbit-pipeline-control-rollback` |
| `${GITHUB_PAT}` | (secret) |
| `${DELEGATE_SELECTOR}` | `helm-delegate` |

## API endpoints used (from apidocs.harness.io research)

Base URL `https://app.harness.io`, auth header `x-api-key: <PAT>`.

| Resource | Create | Update | Body |
|---|---|---|---|
| Project | `POST /ng/api/projects` | `PUT /ng/api/projects/{id}` | JSON `{project:{…}}` |
| Connector | `POST /ng/api/connectors` | `PUT /ng/api/connectors` | YAML (id in body) |
| Secret | `POST /ng/api/v2/secrets` | `PUT /ng/api/v2/secrets/{id}` | JSON `{secret:{…value…}}` |
| Service | `POST /ng/api/servicesV2` | `PUT /ng/api/servicesV2` | YAML |
| Environment | `POST /ng/api/environmentsV2` | `PUT …` | YAML |
| Infrastructure | `POST /ng/api/infrastructures` | `PUT …` | YAML (`environmentRef` in body) |
| Pipeline | `POST /pipeline/api/pipelines/v2` | `PUT …/{id}` | YAML (`application/yaml`) |
| Input Set | `POST /pipeline/api/inputSets` | `PUT …/{id}` | YAML (needs `pipelineIdentifier`) |
| Delegate token | `GET /ng/api/delegate-token-ng?name=default_token` | — | value field |

## Verification gaps (resolved against live API)

Verified end-to-end against a real Harness account; the contract differs by
endpoint family:

| Endpoint | Content-Type | Body shape |
|---|---|---|
| `/ng/api/v2/secrets` | `application/json` | `{secret:{…}}` |
| `/ng/api/connectors` | `application/json` | `{connector:{…}}` (raw YAML → **HTTP 415**) |
| `/ng/api/servicesV2`, `/environmentsV2`, `/infrastructures` | `application/json` | `{…ids, type, yaml: "<entity yaml>"}` |
| `/pipeline/api/pipelines/v2`, `/inputSets` | `application/yaml` | raw YAML |

Connectors are converted YAML → JSON with `yq -o=json`; CD entities are wrapped
in a JSON envelope built by `jq` from the rendered YAML and the entity's
identifiers. Pipeline and input-set endpoints take YAML directly. The
delegate-token endpoint returns an unredacted `value` field when the API key
has delegate-edit permission.

## Dry-run flag (done)

`setup.sh --dry-run` prints each API request (method, URL, content-type,
rendered YAML/JSON body) and each cluster/Helm command without executing
anything. Secrets (GitHub PAT, Harness API key, delegate token) are redacted in
the printed output. `--help` prints the header usage block. Verified: all 13
resources render with placeholders resolved, no secret literals leak, and
non-secret `value:` fields (e.g. `target_envs`) are left intact.

## Verification checklist

- [x] `envsubst` render produces valid YAML, no stray `${...}`
- [x] Run `setup.sh` against a real Harness project; all 13 resources created
- [x] Re-run `setup.sh` to confirm idempotency (POST → PUT fallback works for every resource)
- [ ] Run the pipeline with dev-only and full-release input sets end-to-end
- [ ] Re-run from a fully empty project (current run reused existing resources for some lines)

## Files changed

- `.harness/*.yaml`, `.harness/inputsets/*.yaml` — normalized IDs + `${VAR}` placeholders
- `.env.example` (new)
- `scripts/setup.sh` (new)
- `README.md` — automated-setup section + placeholder note

## Deferred (separate tasks)

- Update `specs/build.md` + `specs/corrections.md` stale expressions (`<+artifacts.primary.*>`, `image_name`/`image_tag`, "two registry options")
- End-to-end tutorial test in a fresh account
- Final screenshots (clean v1/v2/v3)
- Record video; add video link to README; merge PR #2
