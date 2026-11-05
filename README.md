# Preview Environment Manager

An automated preview environment manager on Kubernetes (Azure AKS + Traefik).

- **Layer 0**: Push to `main` deploys to Kubernetes namespace `production`.
- **Layer 1**: Pull requests dynamically provision isolated preview namespaces `pr-<number>` reachable via `http://pr-<number>.<INGRESS_IP>.nip.io` and tear down on PR close/merge.

