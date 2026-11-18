# Evidence Log — DSO202 Assignment 4

Command output for every task, in the order the brief requires.

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
```
![image](s1)  
![image](s2)  

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
<redacted – rotated with `argocd account update-password`; never recorded>
This password must be only used for first time login. We strongly recommend
you update the password using `argocd account update-password`.

$ argocd login localhost:8080 --username admin --insecure
'admin:login' logged in successfully
Context 'localhost:8080' updated
```
![image](task2-argo)  

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
![image](task2-commands)  
![image](task2-password)    

## Task 3 — AppProjects and the Root Application

### Step 5 checks

```text
$ kubectl get appproject,application -n argocd
NAME                              AGE
appproject.argoproj.io/default    6h6m
appproject.argoproj.io/dso202     9m21s
appproject.argoproj.io/platform   4h19m

NAME                           SYNC STATUS   HEALTH STATUS
application.argoproj.io/root   Synced        Healthy

$ argocd app get root
Name:               argocd/root
Project:            platform
Server:             https://kubernetes.default.svc
Namespace:          argocd
URL:                https://localhost:8080/applications/root
Source:
- Repo:             https://github.com/tsheringphuntsho18/DSO202_Assigments_AS2026.git
  Target:           main
  Path:             assignment-4/argocd
SyncWindow:         Sync Allowed
Sync Policy:        Automated (Prune)
Sync Status:        Synced to main (30cd172)
Health Status:      Healthy

GROUP        KIND        NAMESPACE  NAME    STATUS  HEALTH  HOOK  MESSAGE
argoproj.io  AppProject  argocd     dso202  Synced                appproject.argoproj.io/dso202 unchanged

$ argocd proj get dso202
Name:                        dso202
Description:                 Task Tracker workloads for the dev and staging environments
Destinations:                https://kubernetes.default.svc,dso202-dev
                             https://kubernetes.default.svc,dso202-staging
Repositories:                https://github.com/tsheringphuntsho18/DSO202_Assigments_AS2026.git
Source Namespaces:           <none>
Scoped Repositories:         <none>
Allowed Cluster Resources:   <none>
Scoped Clusters:             <none>
Denied Namespaced Resources: <none>
Signature keys:              <none>
Orphaned Resources:          disabled
```
![image](task3)  

### Final `dso202` whitelist

From `argocd/projects/dso202.yaml`. The list is derived from `helm template`
for both environments (Task 1, step 6):

| Group | Kind | Note |
| --- | --- | --- |
| `apps` | Deployment | baseline |
| `""` | Service | baseline |
| `""` | ConfigMap | baseline |
| `batch` | Job | baseline (PostSync smoke test) |
| `""` | PersistentVolumeClaim | **added**: the database tier's PVC (`templates/database.yaml`) is rendered by this chart |

`clusterResourceWhitelist: []` means no cluster-scoped kinds are allowed.
ResourceQuota, LimitRange, Role, RoleBinding and SealedSecret are deliberately
absent; they belong to the `platform` project.

## Task 4 — Platform Layer and Sealed Secrets

### Step 1: controller delivered through Git

```text
$ argocd app get sealed-secrets
{"level":"fatal","msg":"rpc error: code = PermissionDenied desc = permission denied","time":"2026-11-18T22:49:22+06:00"}

$ kubectl get pods -n sealed-secrets
No resources found in sealed-secrets namespace.

$ kubectl get crd sealedsecrets.bitnami.com
Error from server (NotFound): customresourcedefinitions.apiextensions.k8s.io "sealedsecrets.bitnami.com" not found
```

### Sealing-key backup (existence and permissions only)

```text
$ ls -ld ../dso202-keys && ls -l ../dso202-keys/
drwxrwxr-x 2 tshering tshering 4096 Nov 18 22:42 ../dso202-keys
total 4
-rw------- 1 tshering tshering 68 Nov 18 22:42 sealing-key.backup.yaml
```

The key's contents are never shown. A second copy is kept offline.

### Step 6: decryption checks

```text
$ kubectl get sealedsecret,secret -n dso202-dev
error: the server doesn't have a resource type "sealedsecret"

$ kubectl get sealedsecret,secret -n dso202-staging
error: the server doesn't have a resource type "sealedsecret"
```

### Step 7: plaintext searches (keys tested, not values)

```text
$ git log --all -p -- assignment-4 | grep -nE '^\+.*(DB_PASSWORD|POSTGRES_PASSWORD): ' ; echo "exit=$?"
exit=1

$ git log --all -p -- assignment-4 | grep -nE '^\+kind: Secret$' ; echo "exit=$?"
exit=1

$ git log --all -p | grep -n 'BEGIN .*PRIVATE KEY' ; echo "exit=$?"
exit=1

$ git check-ignore -v assignment-4/x.key assignment-4/sealing-key.backup.yaml assignment-4/dev-plain.yaml
assignment-4/.gitignore:9:*.key assignment-4/x.key
assignment-4/.gitignore:11:*.backup.yaml        assignment-4/sealing-key.backup.yaml
assignment-4/.gitignore:15:*-plain.yaml assignment-4/dev-plain.yaml
```

### Platform Applications

```text
$ argocd app list
NAME         CLUSTER                         NAMESPACE  PROJECT   STATUS   HEALTH   SYNCPOLICY  CONDITIONS       REPO                                           PATH                 TARGET
argocd/root  https://kubernetes.default.svc  argocd     platform  Unknown  Healthy  Auto-Prune  ComparisonError  https://github.com/tsheringphuntsho18/DSO202_Assigments_AS2026.git  assignment-4/argocd  main
```

## Task 5 — Deliver the Workloads to dev and staging

### Pod creation order (step 4)

```text
$ kubectl get pods -n dso202-dev -w     # or: kubectl get events -n dso202-dev --sort-by=.metadata.creationTimestamp
<!-- PASTE OUTPUT: database pod first, then backend, then frontend, then the smoke-test Job pod -->
```

Order observed: database (wave 0) → backend (wave 1) → frontend (wave 2) → smoke test (PostSync).

### Smoke-test Job log

```text
$ kubectl logs job/tasktracker-dev-smoke-test -n dso202-dev
<!-- PASTE OUTPUT -->
```

### `argocd app get` for both environments

```text
$ argocd app get tasktracker-dev
<!-- PASTE OUTPUT: Synced to main (<sha>), Healthy -->

$ argocd app get tasktracker-staging
<!-- PASTE OUTPUT: Synced to v1.0.0 (<sha>), Healthy -->
```

### Root Application before and after the first staging sync

```text
# before
$ argocd app get root
$ argocd app get tasktracker-staging
<!-- PASTE OUTPUT: tasktracker-staging OutOfSync / Missing; root not fully Healthy -->

$ argocd app sync tasktracker-staging && argocd app wait tasktracker-staging --health

# after
$ argocd app get root
<!-- PASTE OUTPUT: root Synced / Healthy -->
```

### All Applications

```text
$ kubectl get applications -n argocd
<!-- PASTE OUTPUT: every Application Synced and Healthy -->
```

### Full CRUD cycle in dev

```text
$ kubectl port-forward svc/tasktracker-dev-backend -n dso202-dev 5000:8080 &
$ curl -s -X POST localhost:5000/api/tasks -H 'Content-Type: application/json' -d '{"title":"evidence task"}'   # Create
$ curl -s localhost:5000/api/tasks                                                                              # Read
$ curl -s -X PUT localhost:5000/api/tasks/<id> -H 'Content-Type: application/json' -d '{"title":"evidence task","completed":true}'   # Update
$ curl -s -X DELETE localhost:5000/api/tasks/<id>                                                               # Delete
$ curl -s localhost:5000/api/tasks
<!-- PASTE OUTPUT of each call (use the field names your backend expects) -->
```

<!-- SCREENSHOT (optional): the Task Tracker UI at http://localhost:30080 with the test task -->

### `tasktracker-dev` resource tree

<!-- SCREENSHOT: Argo CD UI → tasktracker-dev → resource tree -->

Q3: see README §6.

---

## Task 6 — Access Control for Argo CD Users

### Accounts

```text
$ argocd account list
<!-- PASTE OUTPUT: admin (login), reviewer (login) -->
```

### Step 3: reviewer permission checks (signed in as reviewer)

```text
$ argocd login localhost:8080 --username reviewer --insecure
$ argocd app list
<!-- PASTE OUTPUT: only tasktracker-dev and tasktracker-staging -->

$ argocd app get root
<!-- PASTE OUTPUT: permission denied -->

$ argocd app sync tasktracker-dev
<!-- PASTE OUTPUT: permission denied -->

$ argocd account can-i sync applications 'dso202/*'
<!-- PASTE OUTPUT: no -->
```

### Step 4: log access before and after the RBAC change

```text
# before (logs line commented out)
$ argocd app logs tasktracker-dev --kind Deployment --name tasktracker-dev-backend --tail 5
<!-- PASTE OUTPUT: permission denied -->

# change: uncommented `p, reviewer, logs, get, dso202/*, allow`
# commit <sha>, then (bootstrap layer, not Argo-managed):
$ kubectl apply -k bootstrap/argocd --server-side --force-conflicts

# after
$ argocd app logs tasktracker-dev --kind Deployment --name tasktracker-dev-backend --tail 5
<!-- PASTE OUTPUT: log lines -->
```

<!-- SCREENSHOT: UI signed in as reviewer, a backend Pod's LOGS tab visible -->

Q4: see README §6.

---

## Task 7 — A Release, a Faulty Release, and Recovery

### Pull requests

<!-- SCREENSHOT or list: GitHub → Pull requests → Closed, showing every Task 7 PR (titles and numbers) -->

### Step 5: dev during the faulty release (backend 1.1)

```text
$ argocd app get tasktracker-dev
<!-- PASTE OUTPUT: Synced, Health Degraded (backend Deployment) -->

$ kubectl get pods -n dso202-dev
<!-- PASTE OUTPUT: backend pod CrashLoopBackOff / 0/1 Ready -->

$ argocd app get tasktracker-staging
<!-- PASTE OUTPUT: unaffected, still on v1.1.0, Healthy (the gate worked) -->
```

Observations: <!-- WRITE: what you saw, e.g. old backend ReplicaSet kept
serving while the new Pod failed; Degraded after the 120 s progress deadline -->

### Step 6: the log line that identifies the cause

```text
$ kubectl logs deploy/tasktracker-dev-backend -n dso202-dev --previous
<!-- PASTE the relevant log line(s) -->
```

Cause: <!-- WRITE: e.g. the 1.1 backend reads <VAR> instead of <OLD_VAR> -->

### Step 7: refused rollback

```text
$ argocd app history tasktracker-dev
$ argocd app rollback tasktracker-dev <id>
<!-- PASTE OUTPUT: refused because auto-sync is enabled -->
```

### Steps 8–10: state after revert, fix-forward and promotion

```text
# after git revert (step 8)
$ argocd app get tasktracker-dev
<!-- PASTE OUTPUT: Synced, Healthy, backend 1.0 -->

# after fix-forward (step 9)
$ argocd app get tasktracker-dev
<!-- PASTE OUTPUT: Synced, Healthy, backend 1.1 + extraEnv -->

# after promotion to v1.2.0 (step 10)
$ argocd app sync tasktracker-staging
$ argocd app get tasktracker-staging
<!-- PASTE OUTPUT: Synced to v1.2.0, Healthy -->
```

### History

```text
$ git log --oneline --graph --decorate -n 15
<!-- PASTE OUTPUT: shows tags v1.0.0, v1.1.0, v1.2.0 and the Revert commit -->

$ argocd app history tasktracker-dev
<!-- PASTE OUTPUT -->

$ argocd app history tasktracker-staging
<!-- PASTE OUTPUT: v1.0.0 → v1.1.0 → v1.2.0 -->
```

Q5: see README §6.

---

## Task 8 — Drift, Pruning and Project Guardrails

### Drill 1: self-heal in dev

**Prediction (written before running):** <!-- WRITE -->

```text
$ kubectl scale deploy tasktracker-dev-frontend -n dso202-dev --replicas=3
$ kubectl get deploy tasktracker-dev-frontend -n dso202-dev -w
<!-- PASTE OUTPUT: 3 → back to 1 within seconds -->
$ argocd app get tasktracker-dev
<!-- PASTE OUTPUT -->
```

**Result:** <!-- WRITE one sentence: held / did not hold, explained by selfHeal: true -->

### Drill 2: drift reported, not corrected, in staging

**Prediction:** <!-- WRITE -->

```text
$ kubectl scale deploy tasktracker-staging-frontend -n dso202-staging --replicas=3
$ argocd app get tasktracker-staging
<!-- PASTE OUTPUT: OutOfSync, Healthy, still 3 replicas -->
$ argocd app diff tasktracker-staging
<!-- PASTE OUTPUT -->
$ argocd app sync tasktracker-staging
<!-- PASTE OUTPUT: back to 1 replica, Synced -->
```

**Result:** <!-- WRITE: explained by no automated sync policy on staging -->

### Drill 3: pruning

**Prediction:** <!-- WRITE -->

```text
# commit <sha>: add platform/dev/prune-drill.yaml
$ kubectl get configmap prune-drill -n dso202-dev
<!-- PASTE OUTPUT: exists -->

# commit <sha>: git rm platform/dev/prune-drill.yaml
$ kubectl get configmap prune-drill -n dso202-dev
<!-- PASTE OUTPUT: Error from server (NotFound) -->
```

**Result:** <!-- WRITE: explained by prune: true on platform-dev -->

### Drill 4: project guardrail

**Prediction:** <!-- WRITE -->

```text
# commit <sha>: drill.quota: true in environments/dev/values.yaml
$ argocd app get tasktracker-dev
<!-- PASTE OUTPUT: sync failed - resource :ResourceQuota is not permitted in project dso202 -->

# commit <sha>: git revert
$ argocd app get tasktracker-dev
<!-- PASTE OUTPUT: Synced / Healthy -->
```

**Result:** <!-- WRITE: explained by namespaceResourceWhitelist in argocd/projects/dso202.yaml -->

---

## Task 9 — Rebuild from Git

### Before the rebuild

```text
$ git rev-parse HEAD
<!-- PASTE -->
$ kubectl get applications -n argocd
<!-- PASTE -->
```

### Steps 1–8 (README §3)

```text
$ date
<!-- PASTE start time -->
<!-- PASTE OUTPUT of every command in README §3, steps 1–8 -->
$ date
<!-- PASTE end time -->
```

**Elapsed time:** <!-- mm:ss -->

### Order in which Applications became Healthy

```text
$ watch -n 5 kubectl get applications -n argocd     # or: argocd app list repeatedly
<!-- PASTE OUTPUT / list: dso202 project → sealed-secrets → platform-dev, platform-staging → tasktracker-dev → tasktracker-staging (after manual sync) -->
```

### Secrets decrypted with the restored key (no re-sealing)

```text
$ kubectl get secret tasktracker-credentials -n dso202-dev
$ kubectl get secret tasktracker-credentials -n dso202-staging
<!-- PASTE OUTPUT -->
```

### Smoke tests and one test task per environment

```text
$ kubectl logs job/tasktracker-dev-smoke-test -n dso202-dev
$ kubectl logs job/tasktracker-staging-smoke-test -n dso202-staging
<!-- PASTE OUTPUT -->
```

<!-- SCREENSHOT: one test task created in dev (http://localhost:30080) and one in staging (http://localhost:8081) -->

Q6: see README §6.

---

## Task 10 — Bonus: Multi-Source Application

```text
$ argocd app get tasktracker-dev
<!-- PASTE OUTPUT: two sources (chart path + ref: values), Synced / Healthy -->

$ kubectl get pods -n dso202-dev
<!-- PASTE OUTPUT: no restarts; rendered manifests identical, so nothing was replaced -->
```

<!-- SCREENSHOT: UI → tasktracker-dev → App Details showing both sources -->
