# Pipeline Controls Exemplar — Build, Deploy, Rollback

This repository accompanies a Technical Tidbit video. It provides a reproducible
demo you can run in your own Harness account and Kubernetes cluster to explore
how pipeline controls behave during a post-production rollback.

## What You Will Learn

- How Input Sets, execution-time inputs, and conditional execution work in a CI/CD pipeline
- What happens during a post-prod rollback (what is honored vs. bypassed)
- A minimal, repeatable workflow: build → deploy → deploy again → roll back

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
  corrections.md               # Correctness fixes applied to the draft
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
git clone https://github.com/<your-username>/tidbits-pipeline-controls.git
cd tidbits-pipeline-controls
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

You need a registry to push the built image. Choose one:

#### Option A: GitHub Container Registry (GHCR)

1. In GitHub, create a Personal Access Token (classic) with the `write:packages` scope
2. In Harness, go to **Connectors → New Connector → Docker Registry**
3. Configure:
   - Name: `container-registry`
   - Provider Type: **Other**
   - Docker Registry URL: `https://ghcr.io`
   - Username: your GitHub username
   - Password: create a Harness Secret with your GitHub PAT
4. Test and save

Your image repo path will be: `ghcr.io/<your-username>/pipeline-controls-demo`

#### Option B: Docker Hub

1. In Docker Hub, create an Access Token at [hub.docker.com/settings/security](https://hub.docker.com/settings/security)
2. In Harness, go to **Connectors → New Connector → Docker Registry**
3. Configure:
   - Name: `container-registry`
   - Provider Type: **DockerHub**
   - Docker Registry URL: `https://index.docker.io/v2/`
   - Username: your Docker Hub username
   - Password: create a Harness Secret with your Docker Hub access token
4. Test and save

Your image repo path will be: `<your-dockerhub-username>/pipeline-controls-demo`

### 5. Create a Git Connector

This allows Harness to fetch pipeline YAML and manifests from your fork.

1. Go to **Connectors → New Connector → GitHub**
2. Configure:
   - Name: `github`
   - URL Type: **Repository**
   - Connection Type: **HTTP**
   - GitHub Repository URL: `https://github.com/<your-username>/tidbits-pipeline-controls`
   - Authentication: **Username and Token** → your GitHub username + PAT (needs `repo` scope)
3. Connectivity Mode: **Connect through a Harness Delegate**
4. Test and save

### 6. Create Kubernetes Namespaces

```bash
kubectl create namespace web-dev
kubectl create namespace web-prod
```

### 7. Create Environments and Infrastructure in Harness

Create two Environments in your Harness project:

- **Dev** — type: Pre-Production
- **Prod** — type: Production

> **Environment names matter.** The Service selects its values file by
> environment name (`<+env.name>.yaml`), so the environments must be named
> exactly **Dev** and **Prod** to match `k8s/Dev.yaml` and `k8s/Prod.yaml`.

For each Environment, create an Infrastructure Definition:
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
   - Repository: your fork name
   - Branch: `main`
   - Manifest (Files) Paths: `k8s/deployment.yaml`, `k8s/service.yaml`, `k8s/configmap.yaml`
   - Values YAML Path: `k8s/<+env.name>.yaml`
5. Add primary artifact:
   - Type: **Docker Registry**
   - Connector: `container-registry`
   - Image Path: your registry path from Step 4 (e.g., `ghcr.io/<user>/pipeline-controls-demo`)
   - Tag: `<+input>`

The ConfigMap is part of the Service manifests (not applied as a separate step),
so Harness versions it and the rolling deploy and rollback carry it forward and
back along with the Deployment. The Values YAML path uses `<+env.name>`, so the
Dev stage picks up `k8s/Dev.yaml` (blue badge) and the Prod stage picks up
`k8s/Prod.yaml` (green badge) automatically.

### 9. Import the Pipeline

1. In your project, go to **Pipelines → Create a Pipeline → Import from Git**
2. Select your `github` connector
3. Repository: your fork
4. Branch: `main`
5. YAML Path: `.harness/pipeline.yaml`
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

- **Build**: Builds the container image from `app/Dockerfile` and pushes to your registry, tagged with the version label
- **Deploy to Dev**: Rolls out the Deployment, Service, and (versioned) ConfigMap to the `web-dev` namespace
- **Deploy to Prod**: Only runs if `target_envs` includes `prod`. Pauses for an execution-time input (`prod_confirm`) before rolling out to `web-prod`

The same container image is deployed to both environments. The HTML page content
comes from a ConfigMap that Harness renders with Go templating. The values
differ per environment via `k8s/Dev.yaml` and `k8s/Prod.yaml` (selected by
`<+env.name>`): the environment name and accent color (Dev blue, Prod green).

**Version label.** The version shown on the page and used as the image tag is
derived automatically from the pipeline's execution sequence id
(`v<+pipeline.sequenceId>`). It increments by one on every run — there is no
version to type in. Your first two runs in a fresh project would be `v1` and
`v2`, but if you've run the pipeline a few times during setup you'll see higher
numbers (e.g. `v7`, `v8`). That's expected; just note your own numbers as you go.

---

## Run the Demo

> The version label comes from the execution sequence id, so it advances on
> each run. Below we call the two releases **vN** and **vN+1** (two consecutive
> runs). Substitute your actual build numbers.

### Step 1: Deploy vN to Dev and Prod

1. Run the pipeline with the **Full Release** Input Set
2. The Build stage runs, then Deploy to Dev. When the Prod stage starts, it
   **pauses for the `prod_confirm` execution-time input** — select **approve**
   to continue
3. Note the version number shown in the run (this is your **vN**)
4. Verify both environments are live:
   ```bash
   kubectl port-forward svc/pipeline-controls-demo 8080:80 -n web-dev
   # Visit http://localhost:8080 — shows vN with a blue Dev badge

   kubectl port-forward svc/pipeline-controls-demo 8081:80 -n web-prod
   # Visit http://localhost:8081 — shows vN with a green Prod badge
   ```

### Step 2: Deploy vN+1 to Dev and Prod

1. Run the pipeline again with **Full Release**
2. Approve the `prod_confirm` input when the Prod stage pauses
3. Note the new version number (**vN+1**) — this is our "bad" release
4. Verify vN+1 is live in both environments (page shows the new number)

### Step 3: (Optional) Dev-Only Run

1. Run with the **Dev Only** Input Set
2. Observe the Prod stage is skipped due to conditional execution (`target_envs` = `dev`)
3. This contrasts with rollback behavior, where the original run's resolved YAML is replayed rather than re-evaluating Input Sets

### Step 4: Trigger a Post-Prod Rollback

1. Go to **Deployments** (or **Services → Instances**)
2. Find the **vN+1** Prod execution and click **Rollback**
3. Observe what happens:
   - A new execution is created for the rollback
   - Non-rollback steps become pass-through
   - Only the rollback step executes
   - The original run's resolved YAML is replayed (Input Sets are not re-applied)

### Step 5: Confirm vN is Restored

```bash
kubectl port-forward svc/pipeline-controls-demo 8081:80 -n web-prod
# Visit http://localhost:8081 — shows vN again
```

---

## Rollback Behavior — What to Look For

| Control | Normal Execution | During Rollback |
|---------|-----------------|-----------------|
| Input Sets | Applied at run time, merged into YAML | NOT re-applied; uses original execution's processed YAML |
| Execution-time inputs | Pauses for user input | Still pauses if configured on rollback steps |
| Conditional execution | Evaluated on every step | Bypassed on non-rollback steps (pass-through); evaluated on rollback steps |

**Key insight**: When you roll back, Harness replays the original execution's resolved YAML. The Input Set that selected "dev,prod" is already baked in — it won't be re-evaluated. Only rollback-specific steps actually execute.

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
Ensure the Input Set sets `target_envs` to include `prod` (e.g., `dev,prod`). You can also override variables at run time in the UI.

**Badge color is the same in both environments**
Check that your environments are named exactly **Dev** and **Prod** and that the Service's Values YAML path is `k8s/<+env.name>.yaml`. If the name doesn't match a values file, the wrong (or no) values are applied.

**Rollback button not available**
Only successful executions within the permitted window expose post-prod rollback. Verify your user has rollback permissions for the Prod environment.

**Prod stage stuck waiting for input**
Expected. The Prod stage pauses for the `prod_confirm` execution-time input. Select **approve** to proceed. Note that execution-time inputs have a timeout — if left too long, the run can fail.

**ImagePullBackOff errors**
Verify the image was pushed successfully during the Build stage. Check that the Kubernetes cluster can reach your registry (GHCR or Docker Hub).

**Pipeline import fails**
Ensure your Git connector can reach your fork. The PAT needs `repo` scope for private repos (or the repo must be public).
