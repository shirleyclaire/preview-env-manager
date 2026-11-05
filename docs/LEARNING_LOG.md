# Learning Log

## Step 1: Spring Boot Application Scaffolding & Health Endpoints

### 1. What was built
- A minimal Spring Boot application (`preview-demo`, package `com.example.previewdemo`) targeting **Java 21** using Spring Boot **4.1.2** with the Maven wrapper (`mvnw` and `mvnw.cmd`).
- Externalized configuration in `src/main/resources/application.properties` with fallback defaults for `GIT_SHA` and `APP_ENV`.
- Two application endpoints:
  - `GET /`: returns an HTML page displaying application message, Git SHA, environment name, and the hostname.
  - `GET /api/info`: returns a JSON object with `message`, `gitSha`, `environment`, and `hostname`.
- Spring Boot Actuator health endpoints with Kubernetes liveness and readiness probes enabled (`/actuator/health`, `/actuator/health/liveness`, `/actuator/health/readiness`).
- MockMvc unit tests asserting HTTP status 200, HTML content, JSON structure, and actuator health UP without requiring any environment variables to be set.
- A clean `.gitignore`, `README.md`, and comprehensive architecture documentation in `docs/DESIGN.md`.
- Staged all files in a newly initialized Git repository on branch `main`.

### 2. Why
- **Clean Baseline**: Every preview environment manager needs a lightweight, reliable workload that boots in seconds and exposes its identity (commit SHA, environment, and pod hostname) directly to the user and automated tests.
- **Kubernetes-Ready**: Container orchestrators require liveness and readiness probes to know when a container is ready to take traffic and when it has failed and needs restarting.
- **Repeatability**: Using the Maven wrapper guarantees that any CI runner (like GitHub Actions) and local developer environment builds the exact same binary without needing a globally installed Maven.

### 3. How it works in plain language
- When the application starts, Spring reads default values from `application.properties`. If environment variables `GIT_SHA` or `APP_ENV` exist (such as when running inside a Kubernetes Pod), Spring overrides the defaults.
- The `AppController` reads these values and detects the machine or container's hostname via `HOSTNAME` (or system network lookups).
- When you visit `http://localhost:8080/`, it injects these values into a minimal HTML template.
- When Kubernetes or a monitoring tool asks `/actuator/health/readiness`, Spring Actuator checks if the web server is ready to accept requests and replies with `{"status":"UP"}`.

### 4. Commands used
```bash
# Verify the build and run unit tests
./mvnw clean verify

# Run the application locally
java -jar target/preview-demo-0.0.1-SNAPSHOT.jar

# Test the endpoints
curl -i http://localhost:8080/
curl -i http://localhost:8080/api/info
curl -i http://localhost:8080/actuator/health
curl -i http://localhost:8080/actuator/health/liveness
curl -i http://localhost:8080/actuator/health/readiness
```

### 5. What could break
- If port `8080` is already in use by another local application (e.g., Docker or another server), Spring Boot will fail to bind the port. You can change `server.port` in `application.properties` or stop the conflicting process.
- If unescaped string formatting specifiers (like raw `%` symbols inside CSS style blocks) are passed to Java's `String.formatted()`, a `UnknownFormatConversionException` occurs. This was prevented by using `.replace()` for template variable substitution.

### 6. Question to check your understanding
Why do we enable separate **liveness** (`/actuator/health/liveness`) and **readiness** (`/actuator/health/readiness`) probes in Kubernetes rather than just using a single general `/actuator/health` endpoint?
*(Hint: Think about what Kubernetes should do if an app is still starting up or loading a big cache versus when an app encounters an unrecoverable deadlock).*



## Step 2: Multi-Stage Containerization & Non-Root Execution

### 1. What was built
- A multi-stage `Dockerfile`:
  - **Stage 1 (Builder)**: Uses pinned `eclipse-temurin:21.0.13_9-jdk-jammy`, copies `.mvn/`, `mvnw`, and `pom.xml`, downloads dependencies via `./mvnw dependency:resolve -B` into a cached layer, copies source files, and builds the JAR with `-DskipTests`.
  - **Stage 2 (Runtime)**: Uses pinned `eclipse-temurin:21.0.13_9-jre-jammy`, creates a dedicated non-root user `appuser:appgroup` (UID/GID 1001), copies only the compiled JAR, exposes port 8080, and runs the application under `USER appuser`.
- Build-time provenance injection: `ARG GIT_SHA=dev` converted to `ENV GIT_SHA=${GIT_SHA}`.
- JVM cgroup container memory optimization: `ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75.0 -XX:+UseG1GC"`.
- A `.dockerignore` file excluding `target/`, `.git/`, IDE directories, documentation, and infrastructure scripts.

### 2. Why
- **Multi-Stage Builds**: Compiling Java requires a full JDK (with compilers, headers, and build tools, ~500MB+). At runtime, only a lightweight JRE (~150MB) and the JAR are required. Multi-stage builds keep production container images small and secure.
- **Layer Caching**: Dependency resolution (`dependency:resolve`) is separated from source code compilation. Because dependencies change rarely compared to application code, Docker caches the dependency layer, speeding up rebuilds from minutes to seconds.
- **Non-Root Principle**: Running containers as `root` is a major security vulnerability in Kubernetes. If a container vulnerability is exploited, running as non-root (UID 1001) prevents root privileges on the underlying Kubernetes host node.
- **Dynamic Container RAM Limits**: JVMs by default may detect host physical memory instead of container memory limits. Setting `-XX:MaxRAMPercentage=75.0` instructs the JVM to use at most 75% of the container's allotted cgroup memory limit, preventing Kubernetes OOM (Out Of Memory) kills.

### 3. How it works in plain language
- Docker runs the first "builder" container, downloads the required dependencies, compiles the Java code, and produces `preview-demo-0.0.1-SNAPSHOT.jar`.
- Docker then discards the entire builder container and starts a fresh "runner" container.
- It copies only the JAR into `/app/app.jar`, assigns ownership to `appuser`, drops root permissions, sets the Git commit SHA environment variable, and starts Java with sensible memory limits.

### 4. Commands used
```bash
# Build the Docker image with a custom GIT_SHA
docker build --build-arg GIT_SHA=local123 -t preview-demo:local .

# Run the container in the background
docker run -d -p 8080:8080 --name preview-demo preview-demo:local

# Verify the container is running and inspect the process user (must NOT be root)
docker exec preview-demo whoami
# Output: appuser

docker exec preview-demo id
# Output: uid=1001(appuser) gid=1001(appgroup) groups=1001(appgroup)

# Query the running container endpoint
curl -i http://localhost:8080/api/info

# Stop and remove the test container
docker stop preview-demo && docker rm preview-demo
```

### 5. What could break
- If `mvnw` loses executable permissions on Linux systems, the build will fail (`permission denied: ./mvnw`). We prevent this with `RUN chmod +x mvnw`.
- If line endings of `mvnw` are converted to Windows CRLF, bash inside the Linux container will fail with `/bin/sh: ./mvnw: /bin/sh^M: bad interpreter`. Git attributes should enforce LF for shell scripts.
- If Docker Desktop is not started on the developer's workstation, Docker CLI commands will fail to connect to the Docker daemon pipe.

### 6. Question to check your understanding
Why is it dangerous to run a container as the `root` user in a shared Kubernetes cluster, even if the container is isolated from other containers?


## Step 3: GitHub Actions CI Pipeline (Build and Test)

### 1. What was built
- Created `.github/workflows/ci-cd.yml` defining the initial continuous integration pipeline with a single `build-test` job.
- Triggers on every `push` to `main` and every `pull_request` targeting `main`.
- Enforced strict least-privilege security permissions: `permissions: contents: read`.
- Configured steps using official pinned major versions of GitHub Actions (`actions/checkout@v7`, `actions/setup-java@v6`, `actions/upload-artifact@v7`).
- Configured Temurin Java 21 with automatic Maven dependency caching (`cache: 'maven'`).
- Added execution permissions step for `mvnw` (`chmod +x mvnw`) and executed `./mvnw -B verify`.
- Configured conditional artifact upload (`if: always()`) so Surefire XML/HTML test reports in `target/surefire-reports/` are preserved and downloadable even if a test fails.

### 2. Why
- **Shift-Left Quality & Fast Feedback**: Every PR and commit must be automatically tested on a clean Ubuntu runner before it is merged or deployed. If a test fails, the pipeline halts immediately.
- **Least-Privilege Security**: GitHub Actions runners inherit a default `GITHUB_TOKEN`. Restricting permissions to `contents: read` prevents a compromised action or compromised dependency from writing to the repo or modifying PRs.
- **Post-Mortem Diagnostics**: By configuring `if: always()` on the artifact upload step, developers can download and inspect test failure logs directly from the GitHub Actions web interface without re-running builds locally.
- **Build Performance**: `actions/setup-java` with `cache: 'maven'` caches `~/.m2/repository` based on the hash of `pom.xml`, shaving minutes off consecutive CI runs.

### 3. How it works in plain language
- Whenever code is pushed to `main` or a pull request is submitted, GitHub automatically spins up a clean, isolated Ubuntu virtual machine.
- It clones the repository, installs the Temurin JDK 21 distribution, and restores any cached Maven libraries.
- It runs `./mvnw -B verify` in non-interactive batch mode (`-B`), compiling the project and running all MockMvc tests.
- Regardless of whether the tests pass or fail, it zips the `target/surefire-reports/` directory and attaches it to the workflow summary page as a downloadable artifact.

### 4. Commands used
```bash
# Check git status and branch
git status
git branch

# Add remote (once username is provided)
git remote add origin https://github.com/shirleyclaire/preview-env-manager.git

# Push to GitHub
git push -u origin main
```

### 5. What could break
- If `mvnw` lacks executable permissions in the repository or git index, Linux runners will fail with `permission denied`. We added `chmod +x mvnw` in the workflow to guard against this.
- If someone uses `@main` or unpinned action tags, an upstream release by a third party could introduce breaking changes or security vulnerabilities without warning.
- If tests produce no surefire reports (e.g., compile error prior to test execution), `actions/upload-artifact` might warn or fail unless handled. In standard Maven builds, Surefire reports are generated on any test run.

### 6. Question to check your understanding
Why is it critical to set `if: always()` on the test report upload step rather than letting it run with default behavior?
*(Hint: When do developers most urgently need to inspect test report files?)*


## Step 4: Azure Environment Pre-Flight Inspection Script

### 1. What was built
- Created `infra/00-precheck.sh`: A strictly read-only bash script that performs pre-flight checks against Azure without creating, changing, or deleting any cloud resources.
- Verifies that Azure CLI (`az`) is installed and has an active login session (`az account show`).
- Displays the active subscription ID, name, tenant, and state.
- Inspects the registration state of 4 essential resource providers:
  - `Microsoft.ContainerService` (AKS)
  - `Microsoft.ContainerRegistry` (ACR)
  - `Microsoft.Network` (VNet/LoadBalancer/Public IP)
  - `Microsoft.Compute` (VM node pools)
- Scans Azure Policy assignments for any "Allowed locations" geographic restrictions.
- For any region passed as an argument (e.g. `eastus`), queries available virtual machine sizes with 2 vCPUs and at least 4 GiB memory, highlighting any capacity/quota restrictions.
- Documents pricing references for the Azure Pricing Calculator and the Azure Retail Prices API.
- Fully documented every `az` command in script comments.

### 2. Why
- **Fail Fast & Cost Safety**: Attempting to deploy an AKS cluster or ACR before checking provider registration or regional quota often leads to opaque failures 15 minutes into a cloud provisioning script.
- **Student & Sandbox Guardrails**: Many university student subscriptions restrict deployments to specific regions (e.g., East US or West US). Detecting policy restrictions before writing terraform or deployment scripts saves hours of debugging.
- **Read-Only Guarantee**: Infrastructure engineers use read-only inspection scripts to safely audit environments without risk of incurring costs or breaking running services.

### 3. How it works in plain language
- The script connects to Azure using your existing CLI login and asks Azure for information: "What subscription is selected? Are the required services turned on? Does my organization restrict where I can build things? What 2-core machines are available in this region?"
- It prints the answers in clean, color-coded tables so you can choose the optimal region and VM size before provisioning any real infrastructure.

### 4. Commands used
```bash
# Make the script executable
chmod +x infra/00-precheck.sh

# Run the pre-check inspection for a specific region (e.g., eastus)
./infra/00-precheck.sh eastus
```

### 5. What could break
- If the user has not installed the Azure CLI or has not run `az login`, the script halts immediately with installation and login guidance.
- If a region has zero quota for a specific VM family (such as `Standard_B2s` or `Standard_D2s_v5`), `Restrictions` will indicate `NotAvailableForSubscription`, signaling that another size or region must be chosen.

### 6. Question to check your understanding
Why must resource providers like `Microsoft.ContainerService` be "Registered" before you can create a Kubernetes cluster in an Azure subscription?
*(Hint: What does registration tell Azure Resource Manager about your subscription's access to that service's API?)*
