# SRE Take-Home Assessment

## Instructions

Fork this repository and follow the guidelines below. Try to spend 4 hours or less on the project. When you are finished, or when you have run out of time, share a link to your forked repository back with the hiring team for review.

This exercise is intentionally open-ended. We care about how you approach the work, how you communicate tradeoffs, and how you shape a delivery pipeline around a realistic application.

## The Assignment

As an SRE at Coterie, you will often need to stand up CI/CD pipelines for application teams shipping .NET services. A common scenario is a .NET API that needs to be built, tested, containerized, packaged, and deployed to Kubernetes by GitHub Actions.

This repository contains a .NET 10 solution with:

- A Web API project at `src/CandidateApi`
- A contracts library at `src/CandidateApi.Contracts` that should be packaged as a NuGet package
- A unit test project at `tests/CandidateApi.Tests`

The API is intentionally simple so you can focus on delivery and operations work instead of application development. It includes:

- `GET /` for service metadata
- `GET /health/live` for liveness
- `GET /health/ready` for readiness based on configured dependencies
- `GET /api/work-items` for sample application data

## What You Should Build

Create two GitHub Actions workflows:

1. When a developer opens or updates a pull request, trigger a build of the solution and run unit tests.
2. When changes are merged into the `main` branch, trigger a build and deploy to a development environment. If development succeeds, automatically promote the same build to a test environment.

Your target deployment platform should be a Kubernetes cluster or clusters.

## Requirements

- A build is triggered from a pull request
- A build and deployment are triggered from a push to `main`
- A Dockerfile is created that containerizes the .NET API and is built in CI
- A NuGet package is produced from `CandidateApi.Contracts` as part of the build
- Two environments are configured: development and test
- The .NET API is deployed to both environments
- The deployment approach is documented clearly enough for a reviewer to follow

## Local Development

The repo is pinned to .NET 10 through `global.json`.

Typical commands:

```bash
dotnet restore
dotnet build SreTakeHome.sln
dotnet test SreTakeHome.sln
dotnet run --project src/CandidateApi/CandidateApi.csproj --urls http://localhost:5000
```

Once the API is running, useful endpoints are:

- `http://localhost:5000/`
- `http://localhost:5000/health/live`
- `http://localhost:5000/health/ready`
- `http://localhost:5000/api/work-items`

If you want to simulate a failing readiness check, update the dependency values under `CandidateApi` in `src/CandidateApi/appsettings.json` or use environment-specific configuration.

## Expectations

There are a lot of moving parts here: .NET builds, unit tests, Docker images, NuGet packaging, GitHub Actions workflows, environment promotion, and Kubernetes deployments. A 100% complete solution is welcome, but not required.

If you do not have access to infrastructure needed to fully deploy the service, it is okay to mock pieces of the solution. You can use placeholder manifests, commented workflow steps, or documented assumptions. If you want a fully working deployment target, feel free to use a free or trial environment such as Microsoft Azure or another provider.

We value:

- Clear automation and repeatability
- Practical tradeoff decisions
- Thoughtful documentation
- Sensible security and secret handling
- Observability and deployment safety considerations

## What To Submit

Please include:

- Your GitHub Actions workflow files
- Any Docker or Kubernetes manifests you created
- Notes about assumptions, tradeoffs, or incomplete pieces
- Instructions a reviewer can use to validate your solution

## Questions

Feel free to reach out with questions or concerns regarding the assessment. This is a free-form exercise on purpose, and there are multiple reasonable ways to approach it.
