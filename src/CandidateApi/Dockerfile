# ---------------------------------------------------------------------------- #
#  CandidateApi — Multi-stage Dockerfile                                       #
#  Target runtime: .NET 10 on Ubuntu chiseled (non-root, no shell)             #
# ---------------------------------------------------------------------------- #

# ---- Stage 1: Build -------------------------------------------------------- #
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG BUILD_CONFIGURATION=Release

WORKDIR /src

# Copy solution and project files first for layer caching
COPY ["SreTakeHome.sln", "./"]
COPY ["src/CandidateApi/CandidateApi.csproj", "src/CandidateApi/"]
COPY ["src/CandidateApi.Contracts/CandidateApi.Contracts.csproj", "src/CandidateApi.Contracts/"]
COPY ["tests/CandidateApi.Tests/CandidateApi.Tests.csproj", "tests/CandidateApi.Tests/"]

# Restore — cached unless project files change
RUN dotnet restore "SreTakeHome.sln"

# Copy remaining source
COPY . .

# Build
RUN dotnet build "SreTakeHome.sln" \
    -c ${BUILD_CONFIGURATION} \
    --no-restore

# Run unit tests inside the build stage so a failing test breaks the image build
RUN dotnet test "SreTakeHome.sln" \
    -c ${BUILD_CONFIGURATION} \
    --no-build \
    --logger "trx;LogFileName=test-results.trx" \
    --results-directory /test-results

# ---- Stage 2: Publish ------------------------------------------------------ #
FROM build AS publish
ARG BUILD_CONFIGURATION=Release

RUN dotnet publish "src/CandidateApi/CandidateApi.csproj" \
    -c ${BUILD_CONFIGURATION} \
    --no-build \
    -o /app/publish \
    /p:UseAppHost=false

# ---- Stage 3: NuGet pack (Contracts) --------------------------------------- #
FROM build AS nuget-pack
ARG BUILD_CONFIGURATION=Release

RUN dotnet pack "src/CandidateApi.Contracts/CandidateApi.Contracts.csproj" \
    -c ${BUILD_CONFIGURATION} \
    --no-build \
    -o /packages

# ---- Stage 4: Runtime ------------------------------------------------------ #
FROM mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled AS runtime

# OCI image metadata
LABEL org.opencontainers.image.title="CandidateApi" \
      org.opencontainers.image.description="Coterie SRE take-home Candidate API" \
      org.opencontainers.image.source="https://github.com/kaiserdayo/sre-take-home" \
      org.opencontainers.image.vendor="Coterie"

WORKDIR /app
EXPOSE 8080
ENV ASPNETCORE_URLS=http://+:8080

# Copy published output
COPY --from=publish /app/publish .

# Chiseled images run as non-root ($APP_UID=1654) by default.
# Explicitly set for clarity and policy compliance.
USER $APP_UID

# No HEALTHCHECK directive — chiseled images have no shell, and Kubernetes
# liveness/readiness probes are the authoritative health mechanism.

ENTRYPOINT ["dotnet", "CandidateApi.dll"]
