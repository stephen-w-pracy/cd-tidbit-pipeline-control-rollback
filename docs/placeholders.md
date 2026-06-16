# Placeholder → `.env` → Consumers

Authoritative map of every `${VAR}` placeholder in `.harness/`: where its value
comes from (`.env`) and which files consume it. `scripts/setup.sh` renders these
with `envsubst`, restricted to exactly this variable list so that Harness
`<+...>` expressions are left untouched.

> This is the canonical version of the partial table in `PLAN.md`. Keep it in
> sync with `.env.example`, `scripts/setup.sh` (the `ENVSUBST_VARS` list), and
> the `.harness/` files. Referenced from `CLAUDE.md`.

---

## The variables

| Placeholder | `.env` key | Example | Consumed by (`.harness/` files) |
|---|---|---|---|
| `${HARNESS_ACCOUNT_ID}` | `HARNESS_ACCOUNT_ID` | `SAn9tg9eRrWyEJyLZ01ibw` | connector-github, connector-ghcr, connector-k8s |
| `${HARNESS_ORG}` | `HARNESS_ORG` | `default` | every `.harness/*.yaml` + both input sets |
| `${HARNESS_PROJECT}` | `HARNESS_PROJECT` | `pipeline_controls` | every `.harness/*.yaml` + both input sets |
| `${GITHUB_USERNAME}` | `GITHUB_USERNAME` | `stephen-w-pracy` | connector-github (URL + username), connector-ghcr (URL + username), pipeline.yaml (Build `repo`) |
| `${GITHUB_REPO}` | `GITHUB_REPO` | `cd-tidbit-pipeline-control-rollback` | connector-github (URL) |
| `${GITHUB_PAT}` | `GITHUB_PAT` | *(secret)* | ghcr-token-secret.yaml (`value`) |
| `${DELEGATE_SELECTOR}` | `DELEGATE_SELECTOR` | `helm-delegate` | connector-k8s (`delegateSelectors`) |

### `.env` keys with no `${VAR}` placeholder

These drive the script's behavior but are not substituted into any `.harness/` file:

| `.env` key | Used by | Purpose |
|---|---|---|
| `HARNESS_API_KEY` | `setup.sh` | `x-api-key` header for all Harness API calls |
| `CREATE_PROJECT` | `setup.sh` | `true` → create the project; `false` → use existing org/project |
| `DELEGATE_NAME` | `setup.sh` | `--set delegateName=` for the Helm delegate install |

> `GITHUB_PAT` is consumed twice: as the rendered value of the `ghcr_token`
> Harness secret **and** (directly by `setup.sh`, not via envsubst) as the
> cluster `ghcr-cred` imagePullSecret password.

---

## Rules

1. **Only these seven `${VAR}` names are substituted.** `setup.sh` passes an
   explicit `ENVSUBST_VARS` list to `envsubst`. Any other `${...}` literal in a
   `.harness/` file would be left as-is (there are none today — keep it that way).
2. **Harness expressions are not placeholders.** `<+env.name>`,
   `<+artifact.image>`, `<+input>`, `<+INFRA_KEY_SHORT_ID>`, etc. use angle
   brackets and are resolved by Harness at run/deploy time — never by envsubst.
   See [resource-map.md §3](resource-map.md#3-templating-layers--who-resolves-what).
3. **Identifiers are not templated.** Resource identifiers (`ghcr`,
   `ghcr_token`, `pipelinecontrolsdemo`, …) are fixed and account-independent.
   Only display values, URLs, and account/org/project/username are placeholders.
4. **Manual pasters must substitute by hand.** Anyone pasting `.harness/` YAML
   into the Harness UI instead of running `setup.sh` must replace each `${...}`
   with their own value first (the README notes this).

---

## Verifying a render

```bash
# Render one file and confirm no stray ${...} remain:
set -a; source .env; set +a
envsubst '${HARNESS_ACCOUNT_ID} ${HARNESS_ORG} ${HARNESS_PROJECT} ${GITHUB_USERNAME} ${GITHUB_REPO} ${GITHUB_PAT} ${DELEGATE_SELECTOR}' \
  < .harness/connector-github.yaml | grep -n '\${' || echo "clean"

# Sweep all templated files at once:
for f in .harness/*.yaml .harness/inputsets/*.yaml; do
  grep -Hn '\${' "$f"   # shows any placeholder; cross-check against the table above
done
```

A correctly-authored file shows only the seven approved placeholders here and no
others.
