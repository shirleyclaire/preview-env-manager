# ==========================================
# Stage 1: Build stage
# ==========================================
FROM eclipse-temurin:21.0.13_9-jdk-jammy AS builder

WORKDIR /build

# Copy Maven wrapper and POM first to leverage Docker layer caching for dependencies
COPY .mvn/ .mvn/
COPY mvnw pom.xml ./

# Ensure the Maven wrapper has execution permissions and pre-fetch dependencies
RUN chmod +x mvnw && ./mvnw dependency:resolve -B

# Copy the application source code and compile/package the executable JAR (skipping tests)
COPY src/ ./src/
RUN ./mvnw clean package -DskipTests -B

# ==========================================
# Stage 2: Runtime stage
# ==========================================
FROM eclipse-temurin:21.0.13_9-jre-jammy AS runner

# Create a dedicated non-root user and group (UID/GID 1001)
RUN groupadd -g 1001 appgroup && \
    useradd -u 1001 -g appgroup -m -s /bin/sh appuser

WORKDIR /app

# Copy the packaged jar from the builder stage with ownership assigned to appuser
COPY --from=builder --chown=appuser:appgroup /build/target/preview-demo-0.0.1-SNAPSHOT.jar /app/app.jar

# Build argument GIT_SHA passed at build time, defaulted to "dev", and persisted as an ENV var
ARG GIT_SHA=dev
ENV GIT_SHA=${GIT_SHA}

# Sensible JVM container limits (heap size constrained to 75% of container RAM, G1GC)
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75.0 -XX:+UseG1GC"

# Expose standard application port
EXPOSE 8080

# Switch to the non-root user
USER appuser

# Launch the Spring Boot application
ENTRYPOINT ["java", "-jar", "/app/app.jar"]

