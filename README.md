# Pipeline Controls Exemplar — Build, Deploy, Rollback

This repository accompanies a Technical Tidbit video. It provides a reproducible
demo you can run in your own Harness account and Kubernetes cluster to practice
four Harness pipeline controls in a realistic build → deploy → recover workflow.

## What You Will Learn

By the end, you will be able to use four pipeline controls:

1. **Input Sets** — run a pipeline with an Input Set, and switch Input Sets to change what the run does (here: which environments are targeted).
2. **Execution-time variables** — use values resolved when the run executes rather than authored in advance: the build sequence id as the version/tag, and the image name and tag read in the deploy stage from the artifact the build stage produced.
3. **Conditional execution** — use a stage condition so a stage runs only when a criterion is met (here: deploy to Prod only when the target list includes `prod`).
4. **Post-prod rollback** — trigger a post-production rollback and confirm the prior version is restored.

## Repository Structure

```
app/
  server.py                    # Python HTTP server (serves HTML from ConfigMap)
  Dockerfile                   # Container image definition
k8s/
  deployment.yaml              # Kubernetes Deployment
  service.yaml                 # ClusterIP Service
  configmap.yaml               # HTML page template (Go templating)
  Dev.yaml                     # Values file for the Dev environment
  Prod.yaml                    # Values file for the Prod environment
.harness/
  pipeline.yaml                # CI/CD pipeline (Build → Dev → Prod)
  inputsets/
    dev-only.yaml              # Deploys to Dev only
    full-release.yaml          # Deploys to Dev and Prod
scripts/
  validate-setup.sh            # Pre-flight environment checks
  teardown.sh                  # Resource cleanup
specs/
  build.md                     # Design spec
  video.md                     # Video production script
  corrections.md               # Correctness fixes + decisions
```

## Prerequisites

- A Kubernetes cluster accessible from the internet (for Harness Delegate)
- `kubectl` configured to access your cluster
- A Harness account (free tier works) — [sign up](https://app.harness.io/auth/#/signup)
- A GitHub account (for forking this repo and as a container registry via GHCR)
- Permissions to run pipelines and trigger rollbacks in Harness

## Setup

### 1. Fork and Clone This Repository

Fork this repository to your GitHub account, then clone it locally:

```bash
git clone https://github.com/<your-username>/cd-tidbit-pipeline-control-rollback.git
cd cd-tidbit-pipeline-control-rollback
```

### 2. Install the Harness Delegate

The Delegate is an agent that runs in your cluster and executes pipeline tasks.

```bash
helm repo add harness-delegate https://app.harness.io/storage/harness-download/delegate-helm-chart/
helm repo update

helm install harness-delegate harness-delegate/harness-delegate-ng \
  --namespace harness-delegate --create-namespace \
  --set delegateName=pipeline-controls-delegate \
  --set accountId=<YOUR_ACCOUNT_ID> \
  --set delegateToken=<YOUR_DELEGATE_TOKEN> \
  --set managerEndpoint=https://app.harness.io
```

Find your Account ID and Delegate Token in **Harness → Account Settings → Account Resources → Delegates → New Delegate**.

See [Install Delegate](https://developer.harness.io/docs/platform/delegates/install-delegates/overview/) for full options.

### 3. Create a Kubernetes Connector

In your Harness project:

1. Go to **Connectors → New Connector → Kubernetes Cluster**
2. Name: `k8s-cluster` (or your preference)
3. Connection method: **Use a Harness Delegate** → select the delegate you just installed
4. Test the connection and save

### 4. Create a Container Registry Connector

You need a registry to push the built image. The following instructions are 
for GitHub Container Registry (GHCR), but the steps are similar for other
registries. See [Conect to an Artifact repository](https://developer.harness.io/docs/platform/connectors/artifact-repositories/connect-to-an-artifact-repo)
on Harness Developer Hub.

#### Create a GitHub Container Registry (GHCR) Connector

1. In GitHub, create a Personal Access Token (classic) with the `write:packages` scope
2. In Harness, go to **Connectors → New Connector → Docker Registry**
3. Configure:
   - Name: `container-registry` **THIS MIGHT NOT BE NECESSARY**, as you can select GitHub Package Registry directly in the Service artifact configuration and use the GitHub connector. But API access must be enabled.
   - Provider Type: **Other**
   - Docker Registry URL: `https://ghcr.io`
   - Username: your GitHub username
   - Password: create a Harness Secret with your GitHub PAT
3. Connectivity Mode: **Connect through a Harness Platform**
4. Test and save

Your image repo path will be: `ghcr.io/<your-username>/pipeline-controls-demo`

### 5. Create a GitHub Connector

Harness will pull YAML from your repo's fork, so you'll need to set up a 
Git connector.

1. Go to **Connectors → New Connector → GitHub**
2. Configure:
   - Name: `pipeline-demo-github`
   - URL Type: **Repository**
   - Connection Type: **HTTP**
   - GitHub Repository URL: `https://github.com/<your-username>/ci-tidbit-pipeline-controls-rollback`
   - Authentication: Use the Harness secret that you created with your GitHub PAT (the same one used for GHCR)
3. Connectivity Mode: **Connect through a Harness Platform**
4. Test and save

### 6. Create Kubernetes Namespaces

```bash
kubectl create namespace web-dev
kubectl create namespace web-prod
```

### 7. Create Environments and Infrastructure in Harness

Create two Environments in your Harness project:

1. Go to **Environments → New Environment**

1. Create two environments:

- **Dev** — type: Pre-Production
- **Prod** — type: Production

> [!NOTE] 
> **Environment names matter.** The Service selects its values file by
> environment name (`<+env.name>.yaml`), so the environments must be named
> exactly **Dev** and **Prod** to match `k8s/Dev.yaml` and `k8s/Prod.yaml`.

For each Environment, create an Infrastructure Definition:
- Name: `Dev_Infra` and `Prod_Infra` 
- Infrastructure Type: **Kubernetes**
- Connector: select `k8s-cluster`
- Namespace: `web-dev` for Dev, `web-prod` for Prod
- **Release Name**: leave it at the pre-populated default,
  `release-<+INFRA_KEY_SHORT_ID>`. This gives each environment a unique,
  stable release name, which Harness needs to track ConfigMap/Secret versions
  and to roll back correctly. Don't blank this field out.

### 8. Create a Service in Harness

1. Go to **Services → New Service**
2. Name: `pipeline-controls-demo`
3. Deployment Type: **Kubernetes**
4. Add the manifest:
   - Type: **K8s Manifest** → **GitHub**
   - Connector: `github`
   - Manifest Identifier: `pipeline_controls`
   - Branch: `main`
   - Manifest (Files) Paths: `k8s/deployment.yaml`, `k8s/service.yaml`, `k8s/configmap.yaml`
   - Values YAML Path: `k8s/<+env.name>.yaml`. Set the field type to `f(x)`.
5. Add primary artifact:
   - Type: **GitHub Package Registry**
   - Connector: `pipeline-demo-github` **SELECT GitHub Connector**
   - Package Name:  `pipeline-controls-demo`  **might not need**
   - Version: `<+input>` **not sure about this**

The ConfigMap is part of the Service manifests (not applied as a separate step),
so Harness versions it and the rolling deploy and rollback carry it forward and
back along with the Deployment. The Values YAML path uses `<+env.name>`, so the
Dev stage picks up `k8s/Dev.yaml` (blue badge) and the Prod stage picks up
`k8s/Prod.yaml` (green badge) automatically.

### 9. Import the Pipeline

1. In your project, go to **Pipelines → Create a Pipeline → Import from Git**
1. Select **Third-party Git provider**
2. Select your `pipeline-demo-github` connector
3. Repository: `cd-tidbit-pipeline-control-rollback` (your fork)
4. Branch: `main`
5. YAML Path: `.harness/pipeline.yaml` **ERrror: OrgIdentifier and projectIdentifier must be in the YAML** Maybe simply deleting them will work.
6. Save

Alternatively, create a new pipeline via the YAML editor and paste the contents of `.harness/pipeline.yaml`.

### 10. Import Input Sets

1. Go to your pipeline → **Input Sets → New Input Set → Import from Git**
2. Import `.harness/inputsets/dev-only.yaml`
3. Import `.harness/inputsets/full-release.yaml`

---

## How the Pipeline Works

```
┌─────────┐     ┌──────────────┐     ┌───────────────┐
│  Build  │────▶│ Deploy to Dev│────▶│ Deploy to Prod│
│ (always)│     │   (always)   │     │ (conditional) │
└─────────┘     └──────────────┘     └───────────────┘
```

- **Build**: Builds the container image from `app/Dockerfile` and pushes to your registry, tagged with the version label (`v<+pipeline.sequenceId>`)
- **Deploy to Dev**: Rolls out the Deployment, Service, and (versioned) ConfigMap to the `web-dev` namespace
- **Deploy to Prod**: Runs only if `target_envs` includes `prod` (conditional execution). Same rolling deploy to the `web-prod` namespace

The same container image is deployed to both environments. The HTML page content
comes from a ConfigMap that Harness renders with Go templating. The values differ
per environment via `k8s/Dev.yaml` and `k8s/Prod.yaml` (selected by
`<+env.name>`): the environment name and accent color (Dev blue, Prod green).

**The four controls, in the pipeline:**

- **Input Sets** decide which environments deploy by setting `target_envs` (`dev-only` → `dev`; `full-release` → `dev,prod`).
- **Execution-time variables** show up twice: the version/tag is `v<+pipeline.sequenceId>` (computed at run start, no typing), and the page displays the running image's name and tag, which the deploy stage reads from the artifact the build stage produced (`<+artifacts.primary.imagePath>` and `<+artifacts.primary.tag>`).
- **Conditional execution** is the Prod stage's `when` condition, `target_envs.contains("prod")`.
- **Post-prod rollback** uses the rolling-rollback steps on the deploy stages.

**Version label.** The version shown on the page and used as the image tag is
derived automatically from the pipeline's execution sequence id
(`v<+pipeline.sequenceId>`). It increments by one on every run — there is no
version to type in. Your first two runs in a fresh project would be `v1` and
`v2`, but if you've run the pipeline a few times during setup you'll see higher
numbers (e.g. `v7`, `v8`). That's expected; just note your own numbers as you go.

---

## Run the Demo

Each step below exercises one of the four controls. The version label comes from
the execution sequence id, so it advances on each run. We call the two releases
**vN** and **vN+1** (two consecutive runs) — substitute your actual build numbers.

### Step 1 — Input Sets: deploy vN to Dev and Prod

1. Run the pipeline and choose the **Full Release** Input Set. Notice it sets `target_envs` to `dev,prod`.
2. The run proceeds straight through: Build, then Deploy to Dev, then Deploy to Prod (no prompts).
3. Note the version number shown in the run (this is your **vN**).
4. Verify both environments are live:
   ```bash
   kubectl port-forward svc/pipeline-controls-demo 8080:80 -n web-dev
   # Visit http://localhost:8080 — vN, blue Dev badge, and the image name:tag

   kubectl port-forward svc/pipeline-controls-demo 8081:80 -n web-prod
   # Visit http://localhost:8081 — vN, green Prod badge, same image name:tag
   ```

The image name and tag on the page come from the artifact the Build stage pushed,
read back in the deploy stage — your first look at execution-time variables.

### Step 2 — Execution-time variables: deploy vN+1

1. Run the pipeline again with **Full Release**. The version auto-increments — nothing to type.
2. Note the new version number (**vN+1**). This will be our "bad" release.
3. Re-check either page: the version *and* the image tag have both advanced to vN+1. These values were computed at execution time — the sequence id at run start, and the artifact tag read downstream into the page.

### Step 3 — Conditional execution: Dev-Only run

1. Run with the **Dev Only** Input Set (`target_envs` = `dev`).
2. Observe the **Prod stage is skipped**: its `when` condition `target_envs.contains("prod")` is false.
3. Contrast with Steps 1–2, where Full Release made the same condition true and Prod ran.

### Step 4 — Post-prod rollback: restore vN

1. Go to **Deployments** (or **Services → Instances**).
2. Find the **vN+1** Prod deployment and click **Rollback**.
3. A separate rollback execution runs and completes.

### Step 5 — Confirm vN is restored

```bash
kubectl port-forward svc/pipeline-controls-demo 8081:80 -n web-prod
# Visit http://localhost:8081 — shows vN again, with the vN image reference
```

---

## Good to Know: What a Post-Prod Rollback Actually Is

A post-prod rollback is **not** a re-run of the pipeline with rollback steps
switched on. It is a *separate execution* that replays the original run's
already-resolved YAML and runs only the rollback steps. A couple of consequences
worth knowing:

| Control | Normal run | Post-prod rollback |
|---------|-----------|--------------------|
| Input Sets | Merged into the YAML at run start | Not re-applied; the original run's resolved YAML is replayed |
| Conditional execution | Evaluated as the run proceeds | Not re-evaluated; the original resolved outcome is replayed |
| Execution mode | `<+pipeline.executionMode>` = `NORMAL` | `<+pipeline.executionMode>` = `POST_EXECUTION_ROLLBACK` |

You don't need this to complete the demo — it's background for understanding why
the prior version comes back cleanly.

---

## Verification Commands

```bash
# Check deployment status
kubectl get deploy,po -n web-dev
kubectl get deploy,po -n web-prod

# Check which image is running
kubectl get po -o jsonpath='{range .items[*]}{.metadata.name}: {.spec.containers[0].image}{"\n"}{end}' -n web-prod

# Port-forward to view the page
kubectl port-forward svc/pipeline-controls-demo 8080:80 -n web-dev
kubectl port-forward svc/pipeline-controls-demo 8081:80 -n web-prod
```

---

## Troubleshooting

**Build stage fails with registry auth errors**
Verify your container registry connector credentials. For GHCR, ensure the PAT has `write:packages` scope. For Docker Hub, ensure the access token is valid.

**Prod stage never runs**
Expected with the **Dev Only** Input Set. To deploy Prod, use **Full Release** (or set `target_envs` to include `prod` at run time).

**Badge color is the same in both environments**
Check that your environments are named exactly **Dev** and **Prod** and that the Service's Values YAML path is `k8s/<+env.name>.yaml`. If the name doesn't match a values file, the wrong (or no) values are applied.

**Image name or tag is blank on the page**
The page reads `<+artifacts.primary.imagePath>` and `<+artifacts.primary.tag>` from the Service's primary artifact. Confirm the Service has a primary artifact configured and that the run actually built/selected one.

**Rollback button not available**
Only successful executions within the permitted window expose post-prod rollback. Verify your user has rollback permissions for the Prod environment.

**ImagePullBackOff errors**
Verify the image was pushed successfully during the Build stage. Check that the Kubernetes cluster can reach your registry (GHCR or Docker Hub).

**Pipeline import fails**
Ensure your Git connector can reach your fork. The PAT needs `repo` scope for private repos (or the repo must be public).
