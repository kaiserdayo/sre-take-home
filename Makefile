# ---------------------------------------------------------------------------- #
#  Makefile — CandidateApi local development & validation                      #
# ---------------------------------------------------------------------------- #

.PHONY: build test run docker-build docker-run kustomize-dev kustomize-test lint clean

SOLUTION     := SreTakeHome.sln
DOCKERFILE   := src/CandidateApi/Dockerfile
IMAGE_NAME   := candidate-api
IMAGE_TAG    := local

# ---- .NET ----------------------------------------------------------------- #

build:
	dotnet build $(SOLUTION) -c Release

test:
	dotnet test $(SOLUTION) -c Release --logger "trx;LogFileName=test-results.trx"

run:
	dotnet run --project src/CandidateApi/CandidateApi.csproj --urls http://localhost:5000

pack:
	dotnet pack src/CandidateApi.Contracts/CandidateApi.Contracts.csproj -c Release -o ./artifacts/packages

# ---- Docker --------------------------------------------------------------- #

docker-build:
	docker build -t $(IMAGE_NAME):$(IMAGE_TAG) -f $(DOCKERFILE) .

docker-run: docker-build
	docker run --rm -p 8080:8080 $(IMAGE_NAME):$(IMAGE_TAG)

# ---- Kubernetes (local validation) ---------------------------------------- #

kustomize-dev:
	kubectl kustomize deploy/overlays/dev

kustomize-test:
	kubectl kustomize deploy/overlays/test

# ---- Lint ----------------------------------------------------------------- #

lint:
	@echo "--- Dockerfile lint ---"
	hadolint $(DOCKERFILE) || true
	@echo "--- Kubeconform (dev) ---"
	kubectl kustomize deploy/overlays/dev | kubeconform -strict -summary || true
	@echo "--- Kubeconform (test) ---"
	kubectl kustomize deploy/overlays/test | kubeconform -strict -summary || true

# ---- Clean ---------------------------------------------------------------- #

clean:
	dotnet clean $(SOLUTION)
	rm -rf artifacts/ test-results/
