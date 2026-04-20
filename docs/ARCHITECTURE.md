# Architecture & Decision Record

This document captures the key design decisions, alternatives considered, and trade-offs made for the CI/CD pipeline and deployment configuration.

---

## Decision 1: Kustomize over Helm

**Choice:** Kustomize with base + overlays.

**Why:** This is a single application deployed to two environments with minimal configuration variance (namespace, ASPNETCORE_ENVIRONMENT, region label). Kustomize's overlay model handles this cleanly without the complexity of Helm charts, values files, and template syntax. Kustomize is built into `kubectl`, reducing toolchain dependencies.

**When Helm would be better:** If this API needed to be deployed by multiple teams with significantly different configurations, or if we needed to publish it as a reusable chart to a chart museum, Helm's templating would be justified.

---

## Decision 2: GitHub OIDC Federation (No Service Principal Secrets)

**Choice:** Azure AD workload identity federation via `azure/login@v2` with OIDC.

**Why:** Long-lived service principal client secrets are a security liability — they can leak, they expire and break pipelines silently, and they require manual rotation. OIDC federation lets GitHub Actions request short-lived tokens scoped to specific branches, with full audit trail in Azure AD sign-in logs.

**Alternative:** `AZURE_CREDENTIALS` JSON secret with client ID + client secret. Simpler to set up initially, but creates a rotation burden and a wider blast radius if compromised.

---

## Decision 3: ACR-Attach Instead of ImagePullSecret

**Choice:** AKS-ACR integration via `az aks update --attach-acr`.

**Why:** This grants the AKS kubelet identity the `AcrPull` role on the registry. No `imagePullSecret` to create, rotate, or inject into service accounts. It's the Azure-native approach and eliminates an entire class of "image pull backoff" incidents caused by expired secrets.

**Alternative:** Create a `docker-registry` type secret and reference it in the deployment. Works on any cluster but adds operational overhead.

---

## Decision 4: Chiseled Base Image

**Choice:** `mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled`.

**Why:** Chiseled images are Microsoft's answer to distroless — Ubuntu-based but stripped of package manager, shell, and non-essential libraries. This produces a smaller image (~100MB vs ~220MB for the full aspnet image), reduces attack surface (no shell for an attacker to use), and runs as non-root by default.

**Trade-off:** No shell means you can't `kubectl exec` into the container for debugging. For production incidents, this is a feature (use logs, not shells). For local debugging, use the full `aspnet` image via a build arg override.

---

## Decision 5: NuGet via GitHub Packages

**Choice:** Publish `CandidateApi.Contracts` to GitHub Packages NuGet feed.

**Why:** The reviewer already has GitHub access. Azure Artifacts would require an Azure DevOps organization or additional Azure setup friction that doesn't add value for this assessment. GitHub Packages integrates natively with `GITHUB_TOKEN` — no additional secrets needed.

**How it works:** The main workflow pushes the NuGet on every merge with `--skip-duplicate`. For versioned releases, the `contracts-release.yml` workflow triggers on `contracts-v*` tags and overrides the version from the tag.

---

## Decision 6: Auto-Promotion (Dev → Test)

**Choice:** Automatic promotion after dev smoke test passes. No manual gate by default.

**Why:** The assessment specifies "automatically promote the same build to a test environment." The `test` GitHub Environment can optionally have required reviewers enabled for a manual gate — this is a one-click configuration change in GitHub Settings, documented in VALIDATION.md.

**Production consideration:** For production deployments, a manual approval gate, progressive rollout (canary), or automated integration test suite should gate promotion.

---

## Decision 7: RollingUpdate with maxUnavailable: 0

**Choice:** `RollingUpdate` strategy with `maxSurge: 1`, `maxUnavailable: 0`.

**Why:** Ensures zero-downtime deployments — Kubernetes always brings up a new pod and confirms it's ready before terminating an old one. Combined with readiness probes on `/health/ready`, traffic is never routed to an unhealthy pod.

**Alternative:** Blue-green via Argo Rollouts or Flagger would give instant rollback but adds controller dependencies. For a mid-level assessment, RollingUpdate with proper probes demonstrates the same safety principles with less operational surface area.

---

## Decision 8: Multi-Stage Docker Build with Tests

**Choice:** Run `dotnet test` inside the Docker build stage.

**Why:** This ensures the exact same SDK version, OS, and restore cache that produces the release binary also runs the tests. It prevents "works on my machine" divergence between CI test runner and Docker build environment. If tests fail, the image build fails — you can never push an image with failing tests.

**Trade-off:** Test execution adds ~30s to the Docker build. In the GitHub Actions workflow, we also run tests in a separate job for faster PR feedback and test result reporting. The Docker-embedded tests are the safety net; the workflow job tests are for developer experience.

---

## What's Not Built (And Why)

| Item | Reason |
|------|--------|
| IaC (Terraform/Bicep) | Senior extension; would require a live Azure subscription for the reviewer to validate. Documented OIDC setup commands serve as lightweight IaC. |
| Observability stack | Senior extension; would need Prometheus + Grafana deployed. The health endpoints and structured logging in the API provide the foundation. |
| Image signing (Cosign) | Low ROI for assessment scope. Noted as a next step for supply chain security. |
| Progressive delivery | Argo Rollouts / Flagger add operator dependencies. RollingUpdate with probes achieves zero-downtime for this scope. |
| Ingress / TLS | Cluster-specific. Documented as a TODO in the deployment manifests. A reviewer deploying to a real cluster would add an Ingress resource for their domain. |
