# Operational Runbook — CandidateApi

## Table of Contents

1. [Readiness Check Failure](#scenario-1-readiness-check-failure)
2. [Deployment Rollback](#scenario-2-deployment-rollback)
3. [Image Pull Failure](#scenario-3-image-pull-failure)
4. [Pod CrashLoopBackOff](#scenario-4-pod-crashloopbackoff)
5. [Pipeline Failure Reference](#pipeline-failure-reference)

---

## Scenario 1: Readiness Check Failure

### Detection

- Kubernetes removes the pod from the Service endpoints.
- `kubectl get pods -n <namespace>` shows pods with `0/1 READY`.
- The `/health/ready` endpoint returns HTTP 503 with a `Degraded` status and the unhealthy dependency listed.

### Diagnosis

```bash
# Check which dependencies are failing
kubectl port-forward svc/candidate-api 8080:80 -n candidate-api-dev
curl -s http://localhost:8080/health/ready | jq .

# Example output when degraded:
# {
#   "status": "Degraded",
#   "checkedAtUtc": "2026-04-19T12:00:00Z",
#   "dependencies": [
#     { "name": "postgres", "type": "database", "healthy": true },
#     { "name": "redis", "type": "cache", "healthy": false }
#   ]
# }

# Check pod events
kubectl describe pod -l app.kubernetes.io/name=candidate-api -n candidate-api-dev

# Check application logs
kubectl logs -l app.kubernetes.io/name=candidate-api -n candidate-api-dev --tail=100
```

### Remediation

1. **If a dependency is unhealthy:** The readiness check is configuration-driven (`appsettings.json`). In production, this would connect to actual health endpoints. For this application, dependency health is configured statically — check if a ConfigMap or environment variable override set `Healthy: false`.

2. **If the API itself is crashing:** See [Scenario 4](#scenario-4-pod-crashloopbackoff).

3. **If the readiness probe is too aggressive:** Increase `failureThreshold` or `periodSeconds` in the deployment manifest.

---

## Scenario 2: Deployment Rollback

### When to Roll Back

- Smoke test fails after deployment (automated in the pipeline).
- Monitoring shows elevated error rates or latency after deployment.
- A critical bug is discovered post-deployment.

### Automated Rollback

The pipeline's smoke test step will fail the workflow if `/health/ready` doesn't return HTTP 200. This prevents auto-promotion to the test environment but does **not** automatically roll back the dev deployment.

### Manual Rollback

```bash
# View rollout history
kubectl rollout history deployment/candidate-api -n candidate-api-dev

# Roll back to previous revision
kubectl rollout undo deployment/candidate-api -n candidate-api-dev

# Roll back to a specific revision
kubectl rollout undo deployment/candidate-api -n candidate-api-dev --to-revision=3

# Verify rollback
kubectl rollout status deployment/candidate-api -n candidate-api-dev
kubectl get pods -n candidate-api-dev
```

### Post-Rollback

1. Confirm the service is healthy: `curl http://<service>/health/ready`
2. Identify the failing commit in the GitHub Actions run.
3. Revert the commit or push a fix to `main` — the pipeline will deploy the corrected version.

---

## Scenario 3: Image Pull Failure

### Detection

```bash
kubectl get pods -n candidate-api-dev
# STATUS: ImagePullBackOff or ErrImagePull

kubectl describe pod <pod-name> -n candidate-api-dev
# Look for: "Failed to pull image" in Events
```

### Diagnosis

| Cause | Check |
|-------|-------|
| Wrong image tag | Verify the tag exists: `az acr repository show-tags -n <acr> --repository candidate-api` |
| ACR authentication | Verify AKS-ACR attachment: `az aks check-acr -n <cluster> -g <rg> --acr <acr>.azurecr.io` |
| ACR is down | Check Azure status: `az acr show -n <acr> --query provisioningState` |

### Remediation

```bash
# Re-attach ACR if detached
az aks update -n <cluster> -g <rg> --attach-acr <acr>

# Verify fix
kubectl delete pod <pod-name> -n candidate-api-dev
# Kubernetes will create a replacement pod
```

---

## Scenario 4: Pod CrashLoopBackOff

### Detection

```bash
kubectl get pods -n candidate-api-dev
# STATUS: CrashLoopBackOff, RESTARTS > 3
```

### Diagnosis

```bash
# Check logs from the current (crashing) container
kubectl logs <pod-name> -n candidate-api-dev

# Check logs from the previous crash
kubectl logs <pod-name> -n candidate-api-dev --previous

# Check events
kubectl describe pod <pod-name> -n candidate-api-dev
```

### Common Causes

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `ConfigurationBindingException` | Missing or malformed `appsettings.json` / env vars | Fix ConfigMap or environment overlay |
| `OptionsValidationException` | Required config section `CandidateApi` missing | Ensure `ASPNETCORE_ENVIRONMENT` is set and matching appsettings file exists |
| Port already in use | `ASPNETCORE_URLS` conflict | Verify container port matches Dockerfile `EXPOSE` (8080) |
| OOM Killed | Memory limit too low | Increase `resources.limits.memory` in deployment |

---

## Pipeline Failure Reference

| Workflow Step | Failure Mode | Action |
|--------------|-------------|--------|
| `dotnet restore` | NuGet feed unreachable | Check GitHub Packages status; verify `GITHUB_TOKEN` permissions |
| `dotnet test` | Test failure | Review test output in PR check; fix failing test |
| `docker build` | Dockerfile syntax or build error | Run `make docker-build` locally to reproduce |
| `az acr login` | OIDC token exchange failure | Verify federated credential subject matches branch; check Azure AD app registration |
| `kubectl apply` | Manifest validation error | Run `make lint` locally; check kubeconform output |
| `rollout status` | Timeout (pods not ready) | Check pod logs and events; may be a health check or resource issue |
| Smoke test | HTTP != 200 | Port-forward and manually test `/health/ready` to identify the failing dependency |
