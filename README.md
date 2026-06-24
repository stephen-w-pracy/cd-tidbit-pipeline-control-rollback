# CD Pipeline Controls — Build, Deploy, Rollback

This repository accompanies a Technical Tidbit video. It provides a
reproducible demo you can run in your own Harness account and Kubernetes
cluster to practice four Harness pipeline controls in a realistic build →
deploy → recover workflow.

## What You Will Learn

By the end, you will be able to use four pipeline controls:

1. **Input Sets** — run a pipeline with an Input Set, and switch Input Sets to
   change what the run does (here: which environments are targeted).
2. **Execution-time variables** — use values resolved when the run executes
   rather than authored in advance: the build sequence id as the version/tag,
   and the image name and version read in the deploy stage from the artifact
   the build stage produced.
3. **Conditional execution** — use a stage condition so a stage runs only when
   a criterion is met (here: deploy to Prod only when the target list includes
   `prod`).
4. **Post-prod rollback** — trigger a post-production rollback and confirm the
   prior version is restored.

## Repository Structure

```
app/
  server.py                    # Python HTTP server (serves HTML from ConfigMap)
  Dockerfile                   # Container image definition
k8s/
  deployment.yaml              # Kubernetes Deployment (with imagePullSecrets)
  service.yaml                 # ClusterIP Service
  configmap.yaml               # HTML page template (Go templating)
  Dev.yaml                     # Values file for the Dev environment
  Prod.yaml                    # Values file for the Prod environment
.harness/
  pipeline.yaml                # CI/CD pipeline (Build → Dev → Prod)
  service.yaml                 # Harness Service entity
  environment-dev.yaml         # Dev environment definition
  environment-prod.yaml        # Prod environment definition
  infra-dev.yaml               # Dev infrastructure definition
  infra-prod.yaml              # Prod infrastructure definition
  connector-github.yaml        # GitHub code connector
  connector-ghcr.yaml          # GHCR Docker registry connector
  connector-k8s.yaml           # K8s cluster connector
  ghcr-token-secret.yaml       # Secret reference for GitHub PAT
  inputsets/
    dev-only.yaml              # Deploys to Dev only
    full-release.yaml          # Deploys to Dev and Prod
scripts/
  setup.sh                     # Automated provisioning (Harness + cluster + delegate)
  cleanup.sh                   # Tears everything down (Harness project + cluster + GHCR package)
  port-forward.sh              # Foreground port-forward to Dev (8080) and Prod (8081)
  validate-setup.sh            # Pre-flight environment checks
docs/
  resource-map.md              # Identifier graph + templating-layer ownership
  placeholders.md              # ${VAR} → .env → consuming-files table
  parity-matrix.md             # README ↔ scripts ↔ specs cross-reference
specs/
  build.md                     # Design spec (skill, objectives, decisions, tables)
video/
  script.md                    # Narrator script (5 acts)
  production-spec.md           # Video production reference (shot lists, timings)
```

## Prerequisites

- A Kubernetes cluster accessible from the internet (for Harness Delegate)
- `kubectl` configured to access your cluster
- A Harness account (free tier works) — [sign up](https://app.harness.io/auth/#/signup)
- A GitHub account (for forking this repo and as a container registry via GHCR)
- A GitHub Personal Access Token (classic) with these scopes: `repo`, `write:packages`, `delete:packages`
- Permissions to run pipelines and trigger rollbacks in Harness
- Either permission to **create a Harness project**, or an existing org + project you can write resources into

## Setup

This repository contains a `scripts/setup.sh` script that provisions everything
for you using the [Automated](#automated-setup) steps. Alternatively, you can follow
the [Manual](#manual-setup) steps below. 

Whichever method you choose, follow these two steps first.

1. Collect Required Variable Values

   | Variable                     | Where to find it                                                                                                                  |
   |------------------------------|-----------------------------------------------------------------------------------------------------------------------------------|
   | Hrness Account ID            | In the acount URL: <code>https:&#47;&#47;app.harness.io/ng/account/<strong style="color:orange">ACCOUNT_ID</strong>/...</code>    |
   | Harness Org                  | In org URL: <code>https:&#47;&#47;app.harness.io/ng/ACCOUNT_ID/all/orgs/<strong style="color:orange">ORG_ID</strong>/...</code>   |
   | Harness Project              | In the project URL: <code>.../ACCOUNT_ID/all/orgs/ORG_ID/projects/<strong style="color:orange">PROJECT_ID</strong>/...</code>[^1] |
   | Harness PAT                  | In **User profile** -> **My API Keys** -> **<API_KEY>** -> **Tokens**[^2]                                                         |
   | GitHub username              | For your fork and GHCR                                                                                                            |
   | GitHub Personal Access Token | Classic token with `repo`, `write:packages`, and `delete:packages` scopes                                                         |
   
   [^1]: The automated setup can create a Harness project and PAT for you.
   [^2]: You can create a new API key and/or token if you don't have one already or want to use one specifically for this demo.

2. Fork and Clone This Repository

   Fork this repository to your GitHub account, then clone it locally:
   
   ```bash
   git clone https://github.com/<your-username>/cd-tidbit-pipeline-control-rollback.git
   cd cd-tidbit-pipeline-control-rollback
   ```

### Automated Setup

Requirements: `make`, `curl`, `kubectl`, `helm`, `jq`, `yq`, and `envsubst` (part of `gettext`).

`scripts/setup.sh` provisions everything for you: the Harness project
(optional), secret, connectors, service, environments, infrastructures,
pipeline, and input sets — plus your cluster namespaces, the GHCR image pull
secret (your PAT), and a Harness Delegate via Helm.

1. Create a `.env` file from the example and fill in your values:

   ```bash
   cp .env.example .env          
   ```

   Edit this file and supply mising the variable values.

2. Dry-run the setup script. It prints each API request, rendered YAML
   body, and cluster/Helm command, with secrets redacted, without touching your
   account or cluster.

   ```bash
   ./scripts/setup.sh --dry-run   
   ```
   Review the output to ensure the correct values are being used. If you see
   any errors, fix them in `.env` and re-run the dry run. 

3. Run the setup script for real. 

   ```bash
   ./scripts/setup.sh   
   ```

   The script reads `.env` (gitignored), renders the templated YAML in `.harness/`,
   and creates each resource via the Harness API. It's re-runnable — existing
   resources are updated rather than duplicated. Set `CREATE_PROJECT=false` in
   `.env` to target an existing org/project instead of creating one.

4. Proceed to [How The Pipeline Works](#how-the-pipeline-works) to exercise the
   pipeline controls.

### Manual Setup

### 1. Install the Harness Delegate

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

Find your Account ID and Delegate Token in **Project Settings -> Delegates → New Delegate**.

See [Install Delegate](https://developer.harness.io/docs/platform/delegates/install-delegates/overview/) for full options.

### 2. Create a Kubernetes Connector

In your Harness project:

1. Go to **Connectors → New Connector → Kubernetes Cluster**
2. Name: `pipeline-demo-cluster`
3. Connection method: **Use a Harness Delegate** → select the delegate you just installed
4. Test the connection and save

### 3. Create a GitHub Connector

Harness needs access to your fork for both code (pipeline, manifests) and the container registry (GHCR).

1. Go to **Connectors → New Connector → GitHub**
2. Configure:
   - Name: `pipeline-demo-github`
   - URL Type: **Repository**
   - Connection Type: **HTTP**
   - GitHub Repository URL: `https://github.com/<your-username>/cd-tidbit-pipeline-control-rollback`
   - Authentication: **Username and Token** — use your GitHub username and a Harness Secret containing your PAT
   - Enable API Access: **Token** — select the same secret
3. Connectivity Mode: **Connect through Harness Platform**
4. Test and save

### 4. Create a GHCR Connector

This connector allows the Build stage to push images to GitHub Container Registry.

1. Go to **Connectors → New Connector → Docker Registry**
2. Configure:
   - Name: `pipeline-demo-ghcr`
   - Provider Type: **Other**
   - Docker Registry URL: `https://ghcr.io/<your-username>`
   - Authentication: **Username and Password** — use your GitHub username and the same PAT secret
3. Connectivity Mode: **Connect through Harness Platform**
4. Test and save

### 5. Create Kubernetes Namespaces

```bash
kubectl create namespace web-dev
kubectl create namespace web-prod
```

### 6. Create Image Pull Secrets

GHCR packages are private by default. Your cluster needs credentials to pull images.

```bash
kubectl create secret docker-registry ghcr-cred \
  --docker-server=ghcr.io \
  --docker-username=<your-github-username> \
  --docker-password=<your-github-pat> \
  -n web-dev

kubectl create secret docker-registry ghcr-cred \
  --docker-server=ghcr.io \
  --docker-username=<your-github-username> \
  --docker-password=<your-github-pat> \
  -n web-prod
```

> [!NOTE]
> If you make your GHCR package public (in GitHub → Packages → package settings
> → Danger Zone → Change visibility), you can skip this step. The deployment
> manifest still references the secret, but Kubernetes will proceed if the
> secret doesn't exist and the registry allows anonymous pulls.

### 7. Create Environments and Infrastructure in Harness

Create two Environments in your Harness project:

1. Go to **Environments → New Environment**
2. Create:
   - **Dev** — type: Pre-Production
   - **Prod** — type: Production

> [!NOTE]
> The Service selects its values file by environment name
> (`k8s/<+env.name>.yaml`), so the environments must be named exactly **Dev**
> and **Prod** to match `k8s/Dev.yaml` and `k8s/Prod.yaml`.

For each Environment, create an Infrastructure Definition:
- Name: `Dev_Infra` / `Prod_Infra`
- Infrastructure Type: **Kubernetes**
- Connector: select `pipeline-demo-cluster`
- Namespace: `web-dev` for Dev, `web-prod` for Prod
- **Release Name**: leave at the default `release-<+INFRA_KEY_SHORT_ID>`. This
  gives each environment a unique, stable release name that Harness uses to
  track versions and roll back correctly.

### 8. Create a Service in Harness

1. Go to **Services → New Service**
2. Name: `pipeline-controls-demo`
3. Deployment Type: **Kubernetes**
4. Add the manifest:
   - Type: **K8s Manifest** → Store: **GitHub**
   - Connector: `pipeline-demo-github`
   - Manifest Identifier: `pipeline_controls`
   - Branch: `main`
   - File/Folder Path: `k8s/deployment.yaml`, `k8s/service.yaml`, `k8s/configmap.yaml`
   - Values YAML Path: `k8s/<+env.name>.yaml` (set the field type to Expression `f(x)`)
5. Add primary artifact:
   - Type: **GitHub Package Registry**
   - Connector: `pipeline-demo-github`
   - Package Name: `pipeline-controls-demo`
   - Package Type: **container**
   - Version: set to Runtime Input (`<+input>`)

The ConfigMap is part of the Service manifests (not applied as a separate step),
so Harness versions it alongside the Deployment. A rolling deploy or rollback
carries both forward and back together.

> [!NOTE] 
> The YAML files in `.harness/` contain `${...}` placeholders (e.g.
> `${HARNESS_ORG}`, `${GITHUB_USERNAME}`) used by the automated setup script.
> If you paste these files manually, replace each placeholder with your own
> value first. Harness expressions like `<+env.name>` are **not** placeholders
> and should be left as-is.

### 9. Create the Pipeline

1. In your project, go to **Pipelines → Create a Pipeline**
2. Switch to the **YAML** editor and paste the contents of `.harness/pipeline.yaml` (substituting the `${...}` placeholders)
3. Confirm the `connectorRef` and `repo` values in the Build step match your connector and GHCR image path
4. Save

### 10. Create Input Sets

1. Go to your pipeline → **Input Sets → New Input Set**
2. Switch to the **YAML** editor and paste the contents of `.harness/inputsets/dev-only.yaml` (substituting the `${...}` placeholders)
3. Save, then repeat for `.harness/inputsets/full-release.yaml`

You're now ready to run the pipeline.

## How the Pipeline Works

```mermaid
flowchart LR
    A((build)) --> B{"<code>dev</code> in<br/><code>target_envs</code>?"}
    B -->|yes| C("deploy<br/>dev")
    B -->|no| D
    C --> D{"<code>prod</code> in<br/><code>target_envs</code>?"}
    D -->|yes| E["deploy<br/>prod"] --> F
    D -->|no| F((("end")))

    style A fill:#4f46e5,stroke:#312e81,color:#fff
    style C fill:#0891b2,stroke:#164e63,color:#fff
    style E fill:#16a34a,stroke:#14532d,color:#fff
    style F fill:#e5e7eb,stroke:#6b7280,color:#111
```

- **Build**: Builds the container image from `app/Dockerfile` and pushes to GHCR, tagged with `v<+pipeline.sequenceId>`
- **Deploy to Dev**: Rolls out the Deployment, Service, and versioned ConfigMap to the `web-dev` namespace
- **Deploy to Prod**: Runs only if `target_envs` includes `prod` (conditional execution). Same rolling deploy to `web-prod`

The same container image is deployed to both environments. The HTML page content
comes from a ConfigMap rendered with Go templating. The values differ per
environment via `k8s/Dev.yaml` and `k8s/Prod.yaml` (selected by `<+env.name>`):
Dev shows a blue badge, Prod shows green.

**The four controls in action:**

| Control                  | Where                                                                 | What it does                                                                 |
|--------------------------|-----------------------------------------------------------------------|------------------------------------------------------------------------------|
| Input Sets               | `target_envs` variable                                                | Dev Only sets `dev` (Prod skipped); Full Release sets `dev,prod` (Prod runs) |
| Execution-time variables | `v<+pipeline.sequenceId>`, `<+artifact.version>`, `<+artifact.image>` | Version auto-increments; artifact details flow into the page at deploy time  |
| Conditional execution    | Prod stage `when` condition                                           | `target_envs.contains("prod")` gates the Prod deploy                         |
| Post-prod rollback       | Service → View Instances and Rollback                                 | Reverts Prod to the prior release (image + ConfigMap)                        |

**Version label.** The version shown on the page and used as the image tag is
derived from the pipeline's execution sequence id (`v<+pipeline.sequenceId>`).
It increments by one on every run — there is nothing to type. Your first run in
a fresh project will be `v1`, but if you've run the pipeline during setup
you'll see higher numbers. That's expected.

## Run the Demo

The golden path below exercises all four controls. Each pipeline run advances
the version by one. We use **v1**, **v2**, **v3** as examples — substitute your
actual numbers.

> [!NOTE]
> The version numbers are derived from the pipeline's execution sequence id
> (`v<+pipeline.sequenceId>`). Your first run in a fresh project will be `v1`,
> but if you've run the pipeline during setup you'll see higher numbers. That's
> expected.

### Step 1 — Dev Only: deploy v1, skip Prod

1. Go to your pipeline and click **Run**
2. Select the **Dev Only** Input Set
3. Notice `target_envs` is set to `dev`
4. Click **Run Pipeline**

**What happens:**
- Build pushes `pipeline-controls-demo:v1`
- Deploy to Dev succeeds
- Deploy to Prod is **skipped** (conditional execution: `"dev".contains("prod")` is false)

Verify Dev is live using the utility script:

```bash
make port-forward-dev
# Or, if you prefer to forward manually:
# kubectl port-forward svc/pipeline-controls-demo 8080:80 -n web-dev
```

> [!NOTE]
>
> `make port-forward-dev` runs in the foreground and reconnects the service
> automatically each time the pipeline rolls out a new pod in the `web-dev`
> namespace (or a rollback rotates them back). Ctrl-C stops forwards cleanly.
>
> `make port-forward-prod` does the same for the production service in `web-prod`.
> `make port-forward` forwards both services simultaneously.

Visit the development app in your browser: [http://localhost:8080](http://localhost:8080). You
should see the page with a blue badge and the version number `v1`:

![Dev app showing v1 with blue badge](readme-assets/app-dev-v1.jpg)

### Step 2 — Full Release: deploy v2 to Dev and Prod

1. Run the pipeline again with the **Full Release** Input Set
2. Notice `target_envs` is now `dev,prod`

**What happens:**
- Build pushes `pipeline-controls-demo:v2`
- Deploy to Dev succeeds
- Deploy to Prod **runs** (conditional execution: `"dev,prod".contains("prod")` is true)

Verify Dev and Prod are now at `v2`:

```bash
make port-forward
# Or, if you prefer to forward manually:
# kubectl port-forward svc/pipeline-controls-demo 8080:80 -n web-dev
# kubectl port-forward svc/pipeline-controls-demo 8081:80 -n web-prod
```

Visit the development app in your browser: [http://localhost:8080](http://localhost:8080). You
should see the page with a blue badge and the version number `v2`:

![Dev app showing v2 with blue badge](readme-assets/app-dev-v2.jpg)

Visit the production app in your browser: [http://localhost:8081](http://localhost:8081). You
should see the page with a green badge and the version number `v2`:

![Prod app showing v2 with green badge](readme-assets/app-prod-v2.jpg)

The version and image on the page are execution-time variables — the sequence id
computed at run start, and the artifact details resolved during deployment.

### Step 3 — Full Release again: deploy v3

Run **Full Release** one more time. This creates a second successful Prod
deployment, which is required for rollback (Harness needs a prior release to
revert to).

Visit the development app in your browser: [http://localhost:8080](http://localhost:8080). You
should see the page with a blue badge and the version number `v3`:

![Dev app showing v3 with blue badge](readme-assets/app-dev-v3.jpg)

Visit the production app in your browser: [http://localhost:8081](http://localhost:8081). You
should see the page with a green badge and the version number `v3`:

![Prod app showing v3 with green badge](readme-assets/app-prod-v3.jpg)

### Step 4 — Post-prod rollback: restore v2

1. In the Harness global navigation, go to **Deployments → Services**
2. Click **pipeline-controls-demo**
3. Click **View Instances and Rollback**

![View Instances panel showing environments and Rollback button](readme-assets/harness-view-instances.jpg)

4. On the **Prod** row, click **Rollback**
5. The confirmation dialog shows the current artifact and the rollback target:

![Rollback confirmation dialog](readme-assets/harness-rollback-confirm.jpg)

6. Click **Confirm**

A rollback execution runs. It reverts the Deployment and ConfigMap to the
previous release:

![Rollback execution logs](readme-assets/harness-rollback-logs.jpg)

### Step 5 — Confirm v2 is restored

Visit the production app in your browser: [http://localhost:8081](http://localhost:8081). You
should see the page with a green badge and the version number `v2`:

![Prod app reverted to previous version, v2, with green badge](readme-assets/app-prod-v2.jpg)

### Step 6 — Confirm Dev is unaffected

Visit the development app in your browser: [http://localhost:8080](http://localhost:8080). You
should see the that Dev remains at `v3`:

![Dev app showing v3 with blue badge](readme-assets/app-dev-v3.jpg)

## Good to Know: What a Post-Prod Rollback Actually Is

A post-prod rollback is **not** a re-run of the pipeline with rollback steps
switched on. It is a *separate execution* that replays the original run's
already-resolved YAML and runs only the rollback steps.

| Control               | Normal run                             | Post-prod rollback                                          |
|-----------------------|----------------------------------------|-------------------------------------------------------------|
| Input Sets            | Merged into the YAML at run start      | Not re-applied; the original resolved YAML is replayed      |
| Conditional execution | Evaluated as the run proceeds          | Not re-evaluated; the original resolved outcome is replayed |
| Execution mode        | `<+pipeline.executionMode>` = `NORMAL` | `<+pipeline.executionMode>` = `POST_EXECUTION_ROLLBACK`     |

Rollback requires at least **two successful deployments** to the same
environment. If only one release exists, there is nothing to revert to.

## Cleanup

### Automated

If you used `scripts/setup.sh` to create the resources for this tutorial, you
can use `scripts/cleanup.sh` to delete them all.

1. Dry-run the cleanup script to preview what it will delete:

   ```bash
   ./scripts/cleanup.sh --dry-run
   ```

2. Run the cleanup script. If you want to run it interactively, remove the `-y`
   flag:

   ```bash
   ./scripts/cleanup.sh -y          # YOLO
   ```

### Manual

#### Harness Resources

Delete the Harness project, which will cascade-delete all child resources.

1. In Harness, navigate to your project

1. In the upper-right corner, click the 3-dot menu and select **Delete**:

   ![Delete project menu](readme-assets/harness-delete-project.jpg)

1. In the confirmation dialog, click **Yes, I want to delete this project** and then type the project name to confirm

#### Cluster Resources

1. Delete the Harness Delegate 

   ```bash
   helm uninstall harness-delegate -n harness-delegate
   ```

1. Delete the delegate namespace

   ```bash
   kubectl delete namespace harness-delegate
   ```

1. Delete the `web-dev` and `web-prod` namespaces in your cluster

   ```bash
   kubectl delete namespace web-dev web-prod
   ```

#### GHCR Package

1. In GitHub, navigate to your main user page

1. In Select the **Packages** tab

1. Select `pipeline-controls-demo`

2. Click **Delete package** and confirm

---

## Troubleshooting

**Build stage fails with 429 Too Many Requests**
The web application is built from a Python base image in a public registry.
Sometimes public registries throttle requests. Wait a few minutes and re-run
the pipeline.

**Build stage fails with registry auth errors**
Verify your GHCR connector credentials. The PAT needs `write:packages` scope.
Ensure the connector URL includes your username: `https://ghcr.io/<your-username>`.

**Prod stage never runs**
Expected with the **Dev Only** Input Set. To deploy Prod, use **Full Release**
(or set `target_envs` to include `prod` at run time).

**Badge color is the same in both environments**
Check that your environments are named exactly **Dev** and **Prod** and that the
Service's Values YAML path is `k8s/<+env.name>.yaml`.

**ImagePullBackOff / 401 Unauthorized**
Your GHCR package is private (the default). Create the `ghcr-cred` secret in the
target namespace (see Step 7 above), or make the package public in GitHub.

**x509: certificate signed by unknown authority**
Your cluster can't verify the registry's TLS certificate. This commonly happens
with corporate TLS inspection proxies (Zscaler, Netskope). Add your corporate
CA bundle to the cluster's trusted certificates, or switch to a cluster outside
the inspection path.

**Rollback says "No previous eligible release found"**
Harness needs at least two successful deployments to the environment before
rollback is available. Run Full Release twice, then try rollback on the second
deployment.

**Pipeline import fails**
Ensure your Git connector can reach your fork. The PAT needs `repo` scope for
private repos (or the repo must be public).

### Helpful commands for inspecting the cluster

```bash
# Check deployment status
kubectl get deploy,po -n web-dev
kubectl get deploy,po -n web-prod

# Check which image is running
kubectl get po -o jsonpath='{range .items[*]}{.metadata.name}: {.spec.containers[0].image}{"\n"}{end}' -n web-prod

# Port-forward to view the page (recommended — auto-reconnects when pods rotate)
make port-forward          # Dev → http://127.0.0.1:8080  Prod → http://127.0.0.1:8081

# Or one environment at a time:
kubectl port-forward svc/pipeline-controls-demo 8080:80 -n web-dev
kubectl port-forward svc/pipeline-controls-demo 8081:80 -n web-prod
```

