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
