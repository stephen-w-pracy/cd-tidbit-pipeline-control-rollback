# Pipeline Controls Exemplar — Deploy, Control, Rollback (Draft)

This repository accompanies a 10–15 minute Technical Tidbit video. It lets you
reproduce the demo in your own Harness account and Kubernetes cluster to
explore how pipeline controls behave during a post-production rollback.

## What you will learn

- How Input Sets, execution-time inputs, and conditional execution work in a CD pipeline
- What changes during a post-prod rollback (what is honored vs bypassed)
- A minimal, repeatable workflow to deploy v1 → v2 → rollback to v1

## Repository structure

```
.harness/
  pipeline.yaml                # Harness pipeline definition
  inputsets/
    dev-only.yaml              # Runs Dev only
    full-release.yaml          # Runs Dev then Prod
docs/
  rollback-behavior.md         # Deep-dive on rollback mechanics
k8s/
  deployment.yaml              # NGINX Deployment (image tag substituted)
  service.yaml                 # ClusterIP Service for quick verification
README.md                      # This file
```

## Prerequisites

- A Kubernetes cluster that can run the Harness Delegate
- A GitHub account to fork/clone this repo and import into Harness.
  Alternatively, you can copy and paste the YAML into Harness and your cluster. 
- A Harness NextGen account with a Project you can edit
- Permissions to run pipelines and trigger rollbacks

## Scenario overview and objectives (TBD)

## Setup

- Create Harness Resources
  1.  Harness Delegate with access to your Kubernetes cluster
  2.  Kubernetes Connector (e.g., `k8s-demo-connector`) with Delegate access
  3.  Service, Environment, and Infrastructure definitions (or use inline in the stage if preferred)

- Clone Demo code (this repo)
  1. Clone this repository locally.
  2. `.harness/pipeline.yaml`
     - **Identifiers**: account/org/project (if present in your import flow)
     - **Connector**: `k8s-demo-connector` → your Kubernetes connector
     - **Service/Env/Infra**: align with names you have in Harness (Dev, Prod)

- Create pipeline and Input Sets in Harness
  1. In your Project, go to **Pipelines → New Pipeline → Import YAML** → paste `pipeline.yaml`
  2. **Pipelines → [Your Pipeline] → Input Sets → New → Import YAML** → add `dev-only.yaml` and `full-release.yaml`
  3. Verify Kubernetes manifests exist in the repo (`k8s/deployment.yaml`, `k8s/service.yaml`). No build step is required; images are public NGINX tags and two sites with custom default index pages.
  
- Connect Harness to Your Cluster
  - Create delegate using Harness Helm charts
  - Create a Kubernetes Connector:
      - Name: `k8s-demo-connector`
      - Auth: via Delegate (recommended) or direct credentials
  - Ensure a Delegate with cluster access is running and mapped to the Project/Org/Account.

- Create service
  - Create a Service named `nginx-web` with Type: Kubernetes.
  - Attach manifests from the repo path `k8s/` (`deployment.yaml` and `service.yaml`).
  - Parameterize:
      - `image.tag` — will be provided via pipeline variable and Input Sets.
  
- Create  Environments and Infrastructure
  - Create two Environments:
      - **Dev** — namespace: `web-dev`
      - **Prod** — namespace: `web-prod`
  - For each Environment, create an Infrastructure definition that uses `k8s-demo-connector` and the appropriate namespace.

## How the pipeline works

- **Stage 1: Deploy to Dev**
  - Always runs
  - Applies `k8s/deployment.yaml` and `k8s/service.yaml`
- **Stage 2: Deploy to Prod**
  - Runs only if pipeline variable `target_env` includes `prod`
  - Prompts at execution time to confirm the image tag
  - Contains explicit **rollback steps** for post-prod rollback

## Run the Demo

> [!NOTE] The following steps are MVP, ideally the deployment would replace the
> nginx site default indexes with new versions to make it visually obvious when
> the rollback restores the previous version. This can be done with a simple
> build step that copies different HTML/CSS files into the same path in the
> image for v1 vs v2, or by using different public images that have distinct
> content.

### Summary
1. Run with full-release Input Set, `image.tag = v1` (e.g., `nginx:1.25.5`). Validate service endpoint or `kubectl get deploy -n web-prod`.
2. Run with full-release Input Set, `image.tag = v2` (e.g., `nginx:1.26.0`). Validate v2 in Prod.
3. Trigger a post-prod rollback on the v2 execution. If prompted for an execution-time input in rollback, provide the intended rollback tag.
4. Confirm v1 is restored.

### Steps

1. **Release v1 to Dev and Prod**
   - Start the pipeline with the `full-release` Input Set
   - When prompted, use an image tag such as `1.25.5`
   - Verify v1 is live in Dev and Prod
2. **Release v2 to Dev and Prod**
   - Run the pipeline again with `full-release`
   - Provide a newer image tag, e.g., `1.26.0`
   - Verify v2 is live in Prod (this is our "bad" version)
3. **Optional: Dev-only run**
   - Run with the `dev-only` Input Set to see conditional execution skip the Prod stage
4. **Trigger a post-prod rollback**
   - From **Services → Instances** (or Executions), choose the Prod service instance and click **Rollback**
   - Observe a new execution entry created for the rollback
5. **Confirm v1 is restored**
   - Port-forward or curl the service endpoint to verify the NGINX version/tag rolled back

### Notes

#### What's Stable vs. Likely to Change

- **Stable concepts**:
    - Rollback uses original processed YAML from the chosen execution.
    - Only rollback steps execute; other nodes are pass-through.
    - Execution-time inputs on rollback nodes still pause execution.
- **Likely to drift**:
    - UI paths and labels for Rollback and Executions pages.
    - Minor YAML schema details or step naming.


#### What to look for during rollback

- **Input Sets**: not re-applied; rollback uses the original run's processed YAML
- **Execution-time inputs**: still honored if configured on rollback steps; can pause for input
- **Conditional execution**: bypassed on normal steps (turned into pass-through) but evaluated on rollback steps if you added conditions there

> If your original Prod deployment used `<+input>` for critical fields (e.g., artifact tag) without defaults, ensure the rollback steps include sensible prompts or defaults to avoid stalls.

#### Verification tips

- **Kubectl**: `kubectl get deploy,rs,po -n <namespace>`
- **Check pod image**: `kubectl get po -o jsonpath='{range .items[*]}{.metadata.name}:{.spec.containers[0].image}{"\n"}{end}' -n <namespace>`
- **Service reachability**: `kubectl port-forward svc/nginx-web 8080:80 -n <namespace>` then visit http://localhost:8080

#### Configuration notes

- **Image repository**: Defaults to public `nginx` images; no registry connector is required
- **Namespaces**: Set in the stage or manifests to match your cluster policy
- **Connectors and refs**: Replace placeholders like `k8s-demo-connector`, `nginx-web`, `web-dev`, `web-prod` with your actual identifiers

#### Troubleshooting

**Rollback fails due to policy/guardrails**
Check OPA/FF conditions in your Project/Org/Account.

**K8s errors (ImagePullBackOff, RBAC)**
Verify your cluster can pull nginx images and the ServiceAccount has permissions in `web-prod`.

**Pipeline imported but connectors don't resolve**
Open the stage YAML editor and replace `connectorRef`, `infrastructureDefinition`, and any `serviceRef`/`environmentRef` values with your project's identifiers. Re-save and retry.

**Execution is stuck waiting for input**
This is expected if rollback steps include execution-time prompts. Provide the requested value or adjust the rollback step to include a default.

**Prod stage never runs**
Ensure the selected Input Set sets `target_env` to include `prod`. You can also override variables at run time in the UI.

**Rollback button not available**
Only successful executions within the permitted window expose post-prod rollback. Also verify your user has rollback permissions for the target environment.


