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

