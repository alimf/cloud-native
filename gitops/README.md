# k8s-gitops

GitOps repo for ArgoCD, using the app-of-apps pattern to bootstrap and manage
an observability stack (metrics, logs, traces) on Kubernetes.

## Prerequisites

- A Kubernetes cluster with ArgoCD already installed in the `argocd` namespace.
  This repo does **not** install ArgoCD itself — it only bootstraps Applications
  into an existing ArgoCD.
- A default `StorageClass` available in the cluster (Loki, Tempo, Grafana and
  Prometheus all request PersistentVolumeClaims).

## Architecture

`root-app.yaml` is applied once, manually, to bootstrap everything else:

```
root-app.yaml  (Application, app-of-apps)
  └─ watches apps/ (recurse: true)
       └─ apps/observability/*.yaml  (one Application per component)
```

Each component Application uses ArgoCD's **multi-source** pattern:
one source pulls the Helm chart from its upstream repo, the second source
(`ref: values`) points back at this git repo to supply the values file from
`manifests/observability/<component>/values.yaml`. This keeps chart pins and
value overrides versioned together without vendoring chart code.

All Applications set `syncPolicy.automated: { prune: true, selfHeal: true }`,
so once bootstrapped, pushing changes to `main` is enough — nothing needs to
be applied manually again.

### Repo layout

```
root-app.yaml                              # bootstrap Application (apply manually, once)
apps/observability/                        # one ArgoCD Application manifest per component
manifests/observability/<component>/values.yaml   # Helm values referenced by the matching Application
```

## Components

| Component             | Chart repo                                              | Version  | Purpose                        |
|------------------------|----------------------------------------------------------|----------|---------------------------------|
| kube-prometheus-stack | prometheus-community/helm-charts                          | 65.5.1   | Prometheus, Alertmanager, Grafana |
| loki                   | grafana/helm-charts                                       | 6.24.0   | Log storage (single binary)     |
| tempo                  | grafana/helm-charts                                       | 1.10.3   | Trace storage (single binary)   |
| promtail               | grafana/helm-charts                                       | 6.16.6   | Log shipper → Loki              |
| otel-collector         | open-telemetry/opentelemetry-helm-charts                  | 0.108.0  | OTLP receiver, fans out to Prometheus/Loki/Tempo |

All components deploy into the `observability` namespace (auto-created via
`CreateNamespace=true`).

## Deploying / bootstrapping

```bash
kubectl apply -f root-app.yaml
```

Then watch it sync:

```bash
kubectl get applications -n argocd -w
# or
argocd app list
argocd app get kube-prometheus-stack
```

## Adding a new component

1. Add `apps/observability/<name>.yaml` — an ArgoCD `Application` following the
   existing multi-source pattern (chart source + `ref: values` source).
2. Add `manifests/observability/<name>/values.yaml` with the Helm overrides.
3. Commit and push — `root-app`'s recursive directory watch picks it up automatically.

## Known gaps / TODO

- **Grafana admin password is currently hardcoded in plaintext**
  (`manifests/observability/kube-prometheus-stack/values.yaml`). Replace with
  a sealed-secrets/External Secrets–backed value before this leaves a lab
  environment.
- **No resource requests/limits** on Loki, Tempo, Promtail, or otel-collector —
  only Prometheus has them set. Add them before running on a shared/constrained
  cluster.
- **Promtail is in Grafana's deprecation path** in favor of Grafana Alloy —
  evaluate migrating log shipping to Alloy.
- **All Applications use ArgoCD's `default` AppProject** — fine for a single
  learner cluster, but should be scoped (repo/destination/RBAC) if this grows
  beyond that.
- Chart versions are pinned manually in each `apps/observability/*.yaml` —
  check for newer releases with `helm search repo <repo>/<chart>` before bumping.
