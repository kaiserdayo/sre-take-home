# Reviewer Validation Guide

Step-by-step instructions to verify the CI/CD pipeline and Kubernetes deployment.

---

## Option A: Validate CI Only (No Cloud Required)

This validates the PR workflow, Docker build, and manifest correctness without any Azure infrastructure.

### Prerequisites

- GitHub account (to fork the repo)
- No Azure subscription needed

### Steps

1. **Fork the repository** to your own GitHub account.

2. **Open a pull request** — create a branch, make any small change (e.g., edit the README), and open a PR against `main`.

3. **Observe the PR workflow** — three jobs should trigger:
   - `Build & Test` — restores, builds, runs unit tests, packs NuGet
   - `Docker Build` — validates the Dockerfile compiles successfully
   - `Lint & Validate` — runs Hadolint and kubeconform

4. **Check test results** — the `dorny/test-reporter` action posts a test summary as a PR check.

5. **Validate locally** (optional):
   ```bash
   # Build and test
   make build
   make test

   # Docker
   make docker-build
   make docker-run
   # Visit http://localhost:8080/health/ready

   # Validate manifests
   make lint
   ```

---

## Option B: Full End-to-End (Azure Required)

This validates the complete pipeline including deployment to AKS.

### Prerequisites

- Azure subscription with permissions to create:
  - AKS cluster
  - Azure Container Registry
  - Azure AD app registration
- GitHub repository with Environments configured

### Step 1: Azure Infrastructure

```bash
# Create resource group
az group create -n rg-sre-takehome -l centralus

# Create ACR
az acr create -n sretakehomeacr -g rg-sre-takehome --sku Basic

# Create AKS cluster
az aks create \
  -n aks-sre-takehome \
  -g rg-sre-takehome \
  --node-count 2 \
  --enable-managed-identity \
  --generate-ssh-keys

# Attach ACR to AKS
az aks update -n aks-sre-takehome -g rg-sre-takehome \
  --attach-acr sretakehomeacr

# Get credentials
az aks get-credentials -n aks-sre-takehome -g rg-sre-takehome
```

### Step 2: OIDC Federation

```bash
# Create app registration
APP_ID=$(az ad app create --display-name "github-sre-take-home" --query appId -o tsv)

# Create service principal
az ad sp create --id $APP_ID

# Add federated credential for main branch
az ad app federated-credential create --id $APP_ID \
  --parameters '{
    "name": "github-main",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:<YOUR_GITHUB_USER>/sre-take-home:ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"]
  }'

# Grant roles
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
az role assignment create --assignee $APP_ID \
  --role Contributor \
  --scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/rg-sre-takehome
az role assignment create --assignee $APP_ID \
  --role AcrPush \
  --scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/rg-sre-takehome/providers/Microsoft.ContainerRegistry/registries/sretakehomeacr
```

### Step 3: GitHub Configuration

1. Go to **Settings → Secrets and variables → Actions**

2. Add **Repository Secrets:**
   - `AZURE_CLIENT_ID` = `<APP_ID from above>`
   - `AZURE_TENANT_ID` = `<your Azure AD tenant ID>`
   - `AZURE_SUBSCRIPTION_ID` = `<your subscription ID>`

3. Add **Repository Variables:**
   - `ACR_NAME` = `sretakehomeacr`

4. Create **Environments** (`dev` and `test`):
   - Go to **Settings → Environments**
   - Create `dev` environment, add secrets:
     - `AKS_CLUSTER_NAME` = `aks-sre-takehome`
     - `AKS_RESOURCE_GROUP` = `rg-sre-takehome`
   - Create `test` environment with the same secrets
   - (Optional) Add **required reviewers** to `test` for a manual promotion gate

### Step 4: Trigger the Pipeline

1. Merge a PR into `main` (or push directly).
2. Watch the **Build & Deploy** workflow in the Actions tab.
3. Verify:
   - Image appears in ACR: `az acr repository list -n sretakehomeacr`
   - Dev deployment: `kubectl get pods -n candidate-api-dev`
   - Test deployment: `kubectl get pods -n candidate-api-test`
   - Health check: `kubectl port-forward svc/candidate-api 8080:80 -n candidate-api-dev` → `curl http://localhost:8080/health/ready`

### Cleanup

```bash
az group delete -n rg-sre-takehome --yes --no-wait
az ad app delete --id $APP_ID
```

---

## Option C: Local Kubernetes (kind)

If you have Docker and `kind` installed, you can validate the K8s manifests locally:

```bash
# Create a local cluster
kind create cluster --name sre-takehome

# Build and load image
make docker-build
kind load docker-image candidate-api:local --name sre-takehome

# Update image reference and deploy
cd deploy/overlays/dev
kustomize edit set image candidate-api=candidate-api:local
kubectl apply -k .

# Verify
kubectl get pods -n candidate-api-dev
kubectl port-forward svc/candidate-api 8080:80 -n candidate-api-dev
curl http://localhost:8080/health/ready

# Cleanup
kind delete cluster --name sre-takehome
```
