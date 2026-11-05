# PROJECT CONTEXT

## Project
Preview-environment manager on Kubernetes.
Spring Boot app -> Maven -> Docker -> Azure Container Registry (ACR) -> Azure Kubernetes Service (AKS), automated by GitHub Actions.
- Layer 0: every push to `main` builds, tests, containerizes, and deploys to Kubernetes namespace `production`.
- Layer 1: every pull request gets its own namespace `pr-<number>` with a URL `http://pr-<number>.<INGRESS_IP>.nip.io`. Closing or merging the PR deletes that namespace.

## About me
University student, new to DevOps, learning while building. This is a graded assignment: I need a working demo, screenshots, and documentation. Explain things in plain language.

## Fixed decisions (do not change without asking me)
- Java 21, Maven (with wrapper), latest stable Spring Boot that supports Java 21. Verify the version on start.spring.io or official docs; do not guess.
- Cloud: Azure only. AKS (free-tier control plane, 1 small node) and ACR (Basic SKU).
- CI/CD: GitHub Actions. Workflow files: `ci-cd.yml` (main branch) and `preview.yml` (pull requests).
- GitHub-to-Azure login: OIDC federated credentials only. No client secrets, passwords, or kubeconfigs stored in GitHub or the repo.
- Ingress controller: Traefik. NOT ingress-nginx (it was retired in March 2026).
- Image tags: the full git commit SHA. Never `latest`.
- Kubernetes manifests: plain YAML in `k8s/`, variables filled in with `envsubst`. No Helm for our own app (Helm is allowed only to install Traefik).
- Hostnames: nip.io.
- Scripts: bash, in `infra/` and `scripts/`.

## Rules
1. Do only what the current prompt asks. One step at a time.
2. Before running any command that creates, changes, or deletes cloud resources or deletes files, show me the exact command, explain it in 1-2 sentences, and wait for my approval.
3. Never print, request, or commit secrets. Keep a correct .gitignore.
4. Pin versions. For every GitHub Action, Helm chart, base image, and CLI flag, check the official documentation. Do not invent inputs or flags. If unsure, say "I am not sure" and tell me how to verify.
5. Validate Kubernetes YAML with `kubectl apply --dry-run=server` before applying, once a cluster exists.
6. Everything must be idempotent: running it twice must be safe.
7. If something fails: stop, show the exact error, explain the cause, propose a fix. Never "fix" by disabling tests, adding `|| true`, using `--force`, or skipping checks unless I approve.
8. End-of-step protocol, required for every task:
   a. Run the checks yourself where possible and show me the real output.
   b. List exactly what I must run or click myself, and the output I should expect.
   c. Append a section to docs/LEARNING_LOG.md containing: what was built, why, how it works in plain language, the commands used, what could break, and one question that checks my understanding.
   d. Suggest a git commit message. Commit only after I confirm the step works.
9. At the start of the first task, detect my operating system. If it is Windows, tell me to use Git Bash or WSL and adapt.
10. List every placeholder value I must fill in. Never leave a silent placeholder.

