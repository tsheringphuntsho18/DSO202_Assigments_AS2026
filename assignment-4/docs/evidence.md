# Evidence Log — DSO202 Assignment 4

Command output for every task, in the order the brief requires. Screenshot
placeholders mark exactly what must be captured manually.

## Task 1 — Repository, Chart Contract and Cluster

### Tool check (section 3.2)

```text
$ docker version --format '{{.Server.Version}}'
29.4.0
$ kind version
kind v0.32.0 go1.26.3 linux/amd64
$ kubectl version --client
Client Version: v1.34.1
Kustomize Version: v5.7.1
$ helm version --short
v3.22.1+gd6c1a0e
$ git --version
git version 2.34.1
$ argocd version --client
argocd: v3.5.6+c2b1e30
  GoVersion: go1.26.10
  Platform: linux/amd64
$ kubeseal --version
kubeseal version: 0.40.0
```

Sealed Secrets Helm repository check:

```text
$ helm repo add sealed-secrets https://bitnami.github.io/sealed-secrets
$ helm repo update
$ helm search repo sealed-secrets/sealed-secrets --versions | head -5
<!-- TODO: run in Task 4, before installing the controller -->
```

### Chart contract (C1–C11)

| # | Requirement | Satisfied where |
| --- | --- | --- |
| C1 | Image repo/tag are values | `charts/tasktracker/values.yaml` (`frontend.image`, `backend.image`, `database.image`); overridden per environment in `environments/<env>/values.yaml` |
| C2 | Per-tier config from values, no template edit needed | `charts/tasktracker/templates/configmap.yaml` reads `.Values.config.*`; backend/frontend env vars read the rendered ConfigMap |
| C3 | No Secret rendered; `existingSecret: tasktracker-credentials` | `charts/tasktracker/values.yaml` (`existingSecret`), used via `task-tracker.secretName` helper in `_helpers.tpl`; `templates/secret.yaml` deleted |
| C4 | Readiness probes, backend `GET /api/status` | `templates/backend.yaml` (`httpGet /api/status`), `templates/frontend.yaml` (`httpGet /`), `templates/database.yaml` (`tcpSocket`) |
| C5 | `sync-wave` db=0, backend=1, frontend=2 | `templates/database.yaml`, `templates/backend.yaml`, `templates/frontend.yaml` annotations |
| C6 | `progressDeadlineSeconds: 120` | `templates/backend.yaml`, `templates/frontend.yaml` Deployment spec |
| C7 | Requests/limits on every container | every container in `templates/*.yaml` and the smoke-test Job |
| C8 | No Namespace/ResourceQuota/LimitRange/Role/RoleBinding rendered | confirmed by `helm template \| grep kind:` (Task 1, step 6) — only ConfigMap, Deployment, Job, PersistentVolumeClaim, Service appear |
| C9 | Ingress disabled by default if present | chart has no Ingress template; not applicable |
| C10 | Frontend Service `NodePort`, port a value (30080 dev / 30081 staging) | `templates/frontend.yaml` Service; `environments/dev/values.yaml` and `environments/staging/values.yaml` (`frontend.service.nodePort`) |
| C11 | `helm lint` clean; `helm template` succeeds for both envs | see below |

### `helm lint` (both environments)

```text
$ helm lint charts/tasktracker -f environments/dev/values.yaml
==> Linting charts/tasktracker
[INFO] Chart.yaml: icon is recommended

1 chart(s) linted, 0 chart(s) failed

$ helm lint charts/tasktracker -f environments/staging/values.yaml
==> Linting charts/tasktracker
[INFO] Chart.yaml: icon is recommended

1 chart(s) linted, 0 chart(s) failed
```

### Rendered kinds (both environments identical)

```text
$ helm template tasktracker charts/tasktracker -f environments/dev/values.yaml | grep '^kind:' | sort | uniq -c
      1 kind: ConfigMap
      3 kind: Deployment
      1 kind: Job
      1 kind: PersistentVolumeClaim
      4 kind: Service

$ helm template tasktracker charts/tasktracker -f environments/staging/values.yaml | grep '^kind:' | sort | uniq -c
      1 kind: ConfigMap
      3 kind: Deployment
      1 kind: Job
      1 kind: PersistentVolumeClaim
      4 kind: Service
```

### Cluster creation

```text
$ kind get clusters
dso202-assignment-01

$ kind delete cluster --name dso202-assignment-01
Deleting cluster "dso202-assignment-01" ...
Deleted nodes: ["dso202-assignment-01-worker2" "dso202-assignment-01-control-plane" "dso202-assignment-01-worker"]

$ kind create cluster --name dso202-gitops --config cluster/kind-cluster.yaml
Creating cluster "dso202-gitops" ...
 ✓ Ensuring node image (kindest/node:v1.36.1)
 ✓ Preparing nodes
 ✓ Writing configuration
 ✓ Starting control-plane
 ✓ Installing CNI
 ✓ Installing StorageClass
 ✓ Joining worker nodes
Set kubectl context to "kind-dso202-gitops"

$ kubectl config current-context
kind-dso202-gitops

$ kubectl get nodes
NAME            STATUS   ROLES           AGE   VERSION
control-plane   Ready    control-plane   30s   v1.36.1
worker-node-1   Ready    <none>          17s   v1.36.1
worker-node-2   Ready    <none>          17s   v1.36.1

$ docker ps --filter name=dso202-gitops --format '{{.Names}}   {{.Ports}}'
dso202-gitops-worker
dso202-gitops-worker2
dso202-gitops-control-plane   127.0.0.1:30080->30080/tcp, 127.0.0.1:41115->6443/tcp
```

---

## Task 2 — Install Argo CD Declaratively

### Render check (step 2)

```text
$ kubectl kustomize bootstrap/argocd | grep -E '^kind: (Deployment|StatefulSet)$' | sort | uniq -c
      6 kind: Deployment
      1 kind: StatefulSet

$ kubectl kustomize bootstrap/argocd | grep 'image:' | sort -u
        image: ghcr.io/dexidp/dex:v2.45.1
        image: public.ecr.aws/docker/library/redis:8.2.3-alpine
        image: quay.io/argoproj/argocd:v3.5.6
```

Matches expectations exactly: 6 Deployments, 1 StatefulSet, no Docker Hub image, Argo CD pinned to v3.5.6.

### Apply (step 3) and readiness (step 4)

```text
$ kubectl apply -k bootstrap/argocd --server-side --force-conflicts
namespace/argocd serverside-applied
customresourcedefinition.apiextensions.k8s.io/applications.argoproj.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/applicationsets.argoproj.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/appprojects.argoproj.io serverside-applied
... (62 objects total: namespace, 3 CRDs, ServiceAccounts, Roles/RoleBindings,
     ClusterRoles/ClusterRoleBindings, ConfigMaps, Secrets, Services,
     Deployments, the application-controller StatefulSet, NetworkPolicies)

$ kubectl wait --for=condition=Available deployment --all -n argocd --timeout=600s
deployment.apps/argocd-applicationset-controller condition met
deployment.apps/argocd-dex-server condition met
deployment.apps/argocd-notifications-controller condition met
deployment.apps/argocd-redis condition met
deployment.apps/argocd-repo-server condition met
deployment.apps/argocd-server condition met

$ kubectl rollout status statefulset/argocd-application-controller -n argocd --timeout=600s
partitioned roll out complete: 1 new pods have been updated...

$ kubectl get pods -n argocd
NAME                                                READY   STATUS    RESTARTS   AGE
argocd-application-controller-0                     1/1     Running   0          25m
argocd-applicationset-controller-58bb5c7479-gf7hc   1/1     Running   0          25m
argocd-dex-server-dd6b85d9c-2btvf                   1/1     Running   0          25m
argocd-notifications-controller-6b85c65458-8ckjb    1/1     Running   0          25m
argocd-redis-869b85489d-cx4mw                       1/1     Running   0          25m
argocd-repo-server-5bf66565cd-9rmjg                 1/1     Running   0          25m
argocd-server-7474bb8f76-x4tz9                      1/1     Running   0          25m

$ kubectl get crd | grep argoproj.io
applications.argoproj.io      2026-11-18T11:40:26Z
applicationsets.argoproj.io   2026-11-18T11:40:27Z
appprojects.argoproj.io       2026-11-18T11:40:27Z
```

Note: the first sync took ~25 minutes on this network because every node had
to pull `quay.io/argoproj/argocd:v3.5.6` (222 MB) independently — this was a
slow/shared connection, not a configuration fault; no pod ever reported a
real error, only transient `CreateContainerConfigError` while
`argocd-redis`'s `redis-initial-password` init container was still pulling
its own image copy.

### Sign-in (step 5)

```text
$ kubectl port-forward svc/argocd-server -n argocd 8080:443
Forwarding from 127.0.0.1:8080 -> 8080
Forwarding from [::1]:8080 -> 8080

$ argocd admin initial-password -n argocd
-nLKpMNB5kVx3eRX
This password must be only used for first time login. We strongly recommend
you update the password using `argocd account update-password`.

$ argocd login localhost:8080 --username admin --insecure
'admin:login' logged in successfully
Context 'localhost:8080' updated
```

<!-- SCREENSHOT PLACEHOLDER: Argo CD UI at https://localhost:8080 immediately
     after signing in as admin, showing the (still empty) Applications list -->

### Local settings confirmation (step 6)

```text
$ kubectl get configmap argocd-cm -n argocd -o yaml | grep -E 'timeout.reconciliation|accounts.reviewer'
  accounts.reviewer: login
  timeout.reconciliation: 60s
  timeout.reconciliation.jitter: 10s

$ argocd version
argocd: v3.5.6+c2b1e30
argocd-server: v3.5.6
```

---

## Task 3 — AppProjects and the Root Application

<!-- TODO -->

---

## Task 4 — Platform Layer and Sealed Secrets

<!-- TODO -->

---

## Task 5 — Deliver the Workloads to dev and staging

<!-- TODO -->

---

## Task 6 — Access Control for Argo CD Users

<!-- TODO -->

---

## Task 7 — A Release, a Faulty Release, and Recovery

<!-- TODO -->

---

## Task 8 — Drift, Pruning and Project Guardrails

<!-- TODO -->

---

## Task 9 — Rebuild from Git

<!-- TODO -->
