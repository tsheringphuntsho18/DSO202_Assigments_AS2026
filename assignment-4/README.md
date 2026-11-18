# DSO202 Assignment 4 — GitOps Delivery of the Task Tracker with Argo CD

## 1. Purpose

This directory delivers the Task Tracker (frontend, backend, PostgreSQL, built
in Assignments 1–3) to two environments, `dso202-dev` and `dso202-staging`, on a
local kind cluster, using Argo CD as the GitOps controller.

After a one-time hand-applied bootstrap (Argo CD itself, the `platform`
AppProject and the `root` Application), **nothing in the cluster is created,
changed or deleted with `kubectl`**. Every change is a commit to this
repository, and Argo CD pulls it and reconciles the cluster to match:

| Environment | Application | Follows | Sync |
| --- | --- | --- | --- |
| dev | `tasktracker-dev` | branch `main` | automated, prune, self-heal |
| staging | `tasktracker-staging` | a release tag (`v1.0.0` → `v1.1.0` → `v1.2.0`) | manual only (promotion gate) |

The four GitOps principles, and where each is shown in `docs/evidence.md`:

1. **Declarative.** Every object after the bootstrap is a file in this directory (Tasks 3–5).
2. **Versioned and immutable.** Argo CD, the chart and the images are pinned, staging is pinned to a tag, and a release is a commit (Task 7).
3. **Pulled automatically.** Argo CD polls Git every 60 s; nothing pushes to the cluster (Tasks 3–5).
4. **Continuously reconciled.** Drift is corrected in dev, reported in staging, and removed files are pruned (Task 8).

**Repository note.** The brief names a dedicated repository `dso202-gitops`.
This submission lives at `assignment-4/` inside the combined repository
`https://github.com/tsheringphuntsho18/DSO202_Assigments_AS2026.git`, so every
Application path is prefixed with `assignment-4/`. The repository URL is
written identically in every file, and the repository is public.

### Repository Layout
```text
assignment-4/
├── README.md                                   
├── .gitignore                                  
├── cluster/
│   └── kind-cluster.yaml                       
├── bootstrap/                                  
│   ├── argocd/
│   │   ├── namespace.yaml                      
│   │   ├── kustomization.yaml                  
│   │   ├── argocd-cm-patch.yaml                
│   │   └── argocd-rbac-cm-patch.yaml           
│   └── root/
│       ├── platform-project.yaml               
│       └── root-app.yaml                       
├── argocd/                                     
│   ├── projects/
│   │   └── dso202.yaml                         
│   └── applications/
│       ├── sealed-secrets.yaml                 
│       ├── platform-dev.yaml                   
│       ├── platform-staging.yaml               
│       ├── tasktracker-dev.yaml                
│       └── tasktracker-staging.yaml            
├── platform/                                   
│   ├── dev/
│   │   ├── namespace.yaml                      
│   │   ├── quota-and-limits.yaml               
│   │   ├── rbac.yaml                           
│   │   └── tasktracker-credentials.sealed.yaml 
│   └── staging/                                
├── charts/
│   └── tasktracker/                            
│       ├── Chart.yaml
│       ├── values.yaml                         
│       └── templates/
│           ├── ...                             
│           └── smoke-test-job.yaml             
├── environments/
│   ├── dev/values.yaml                         
│   └── staging/values.yaml                     
└── docs/
    └── evidence.md                             
```

## 2. Pinned versions (section 3.1)

| Component | Version |
| --- | --- |
| Argo CD | v3.5.6 |
| `argocd` CLI | v3.5.6 |
| Sealed Secrets Helm chart | 2.20.0 |
| Sealed Secrets controller | 0.40.0 |
| `kubeseal` CLI | v0.40.0 |
| kind | v0.32.0 |
| kind node image | `kindest/node:v1.36.1` (digest-pinned in `cluster/kind-cluster.yaml`) |
| kubectl (client) | v1.34.1 |
| Helm | v3.22.1 |
| Smoke-test image | `busybox:1.37` |

Task Tracker images (tutor-issued; only tags `1.0` and `1.1` are used):

| Tier | Image | Baseline | Release (Task 7) |
| --- | --- | --- | --- |
| Frontend | `sarojsanyasi/dso202-frontend` | `1.0` | `1.1` |
| Backend | `sarojsanyasi/dso202-backend` | `1.0` | `1.1` |
| Database | `sarojsanyasi/dso202-db` | `1.0` | unchanged |

`latest`, `stable`, `master` and `HEAD` are not used anywhere.

## 3. Building the whole environment from an empty machine (Task 9)

Prerequisites: Docker (about 6 GB of memory), kind, kubectl, Helm, `argocd` and
`kubeseal` at the versions above. The sealing-key backup must be present
outside the repository at `~/dso202-keys/sealing-key.backup.yaml`.

```bash
# 0. Get the repository
git clone https://github.com/tsheringphuntsho18/DSO202_Assigments_AS2026.git
cd DSO202_Assigments_AS2026/assignment-4
date                                                        # start time

# 1. Create the cluster
kind create cluster --config cluster/kind-cluster.yaml     # cluster name: dso202-gitops

# 2. Pre-load images (avoids Docker Hub anonymous pull limits)
docker login
for i in frontend:1.0 frontend:1.1 backend:1.0 backend:1.1 db:1.0; do
  docker pull sarojsanyasi/dso202-$i
  kind load docker-image sarojsanyasi/dso202-$i --name dso202-gitops
done
docker pull busybox:1.37 && kind load docker-image busybox:1.37 --name dso202-gitops

# 3. Restore the sealing key BEFORE the controller starts, so existing
#    SealedSecrets in Git decrypt without re-sealing
kubectl create namespace sealed-secrets
kubectl apply -f ~/dso202-keys/sealing-key.backup.yaml

# 4. Install Argo CD (bootstrap layer)
kubectl apply -k bootstrap/argocd --server-side --force-conflicts
kubectl wait --for=condition=Available deployment --all -n argocd --timeout=600s
kubectl rollout status statefulset/argocd-application-controller -n argocd --timeout=600s

# 5. Create the platform project and the root Application (last hand-applied step)
kubectl apply -f bootstrap/root

# 6. Sign in
kubectl port-forward svc/argocd-server -n argocd 8080:443 >/dev/null 2>&1 &
argocd login localhost:8080 --username admin \
  --password "$(argocd admin initial-password -n argocd | head -1)" --insecure
argocd account update-password --account admin            # rotate immediately

# 7. Wait for the waves: dso202 project -> sealed-secrets -> platform-* -> tasktracker-dev
argocd app wait root sealed-secrets platform-dev platform-staging tasktracker-dev --health --timeout 900
kubectl get secret tasktracker-credentials -n dso202-dev   # decrypted with the restored key

# 8. Promote staging through the gate (pinned tag, manual sync)
argocd app sync tasktracker-staging
argocd app wait tasktracker-staging --health --timeout 600
kubectl get applications -n argocd
date                                                        # end time

# 9. Local accounts are not in Git: set the reviewer password again
argocd account update-password --account reviewer
```

Access:

- dev frontend: http://localhost:30080
- staging frontend: `kubectl port-forward svc/tasktracker-staging-frontend -n dso202-staging 8081:8080`, then http://localhost:8081
- Argo CD UI: https://localhost:8080

## 4. Cleanup

```bash
pkill -f "port-forward svc/argocd-server" || true
pkill -f "port-forward svc/tasktracker" || true
kind delete cluster --name dso202-gitops
# optional: remove the pre-loaded images from the local Docker cache
docker rmi sarojsanyasi/dso202-frontend:1.0 sarojsanyasi/dso202-frontend:1.1 \
  sarojsanyasi/dso202-backend:1.0 sarojsanyasi/dso202-backend:1.1 sarojsanyasi/dso202-db:1.0 busybox:1.37
```

Do **not** delete `~/dso202-keys/`. Without it the SealedSecrets in Git cannot
be decrypted on a new cluster.

## 5. Credential handling

- The database credentials (`DB_USER`, `DB_PASSWORD`, `POSTGRES_USER`,
  `POSTGRES_PASSWORD`) exist in Git **only** as `SealedSecret` objects:
  `platform/dev/tasktracker-credentials.sealed.yaml` and
  `platform/staging/tasktracker-credentials.sealed.yaml`. Each environment has
  different values and was sealed separately.
- The plaintext input was generated with `kubectl create secret ... --dry-run=client`
  into `~/dso202-plain/`, outside the repository. It is never committed, and
  `.gitignore` blocks `*-plain.yaml`, `secrets-plain/`, `*.key`, `*sealing-key*`
  and `*.backup.yaml` in case such a file is ever created inside the repository.
- Sealing uses the default **strict** scope, so a SealedSecret decrypts only
  under its own name and namespace.
- The Sealed Secrets controller decrypts them in-cluster into the Secret
  `tasktracker-credentials`. The chart never renders a Secret; it only
  references `existingSecret: tasktracker-credentials` (contract C3).
- The controller's private sealing key is backed up to
  `~/dso202-keys/sealing-key.backup.yaml` (directory `700`, file `600`), with a
  second offline copy. It is never committed, pasted or logged.
- Argo CD local account passwords (admin, reviewer) live only in the cluster
  (`argocd-secret`). The initial admin password is rotated on every build and
  is not recorded in this repository.
- Plaintext absence was verified over the whole Git history (Task 4, step 7).

## 6. Written answers

### Q1 (Task 3): Why is `platform` applied by hand while `dso202` comes from the root Application? What if `dso202` could deploy into `argocd`?

The root Application has to belong to a project, and Argo CD refuses to
create an Application whose project does not exist. `platform` is therefore
a prerequisite of the root Application and cannot be delivered by it; it is
part of the hand-applied bootstrap, like Argo CD itself. Keeping it out of
Git-driven delivery is also deliberate: `platform` is administrator-level
(any namespace in its list, every cluster-scoped kind). If it were delivered
from `argocd/`, a single merged commit could widen the project that controls
everything else. Changing it requires cluster-admin access, not just a merge.

`dso202` is an ordinary, restricted project. It is created by the root
Application (wave -3, before any Application that uses it), so it is
versioned, reviewed through Git and self-healed if edited.

If `dso202` could deploy into the `argocd` namespace, anyone able to commit
to the workload chart or values could create or overwrite Argo CD's own
objects there: new Applications in any project, an AppProject with
`*` destinations, `argocd-cm` and `argocd-rbac-cm` (new accounts, new
policies), or `argocd-secret`. Because the application controller holds
cluster-wide rights, that is an escalation from "deploy the Task Tracker"
to full control of the cluster. This is why the Argo CD documentation treats
a project that can deploy into the Argo CD namespace as equivalent to admin,
and why only `platform` may target it.

### Q2 (Task 4): Strict scope in Sealed Secrets: what does it prevent, what is lost, and what if the sealing key is lost?

**Prevents:** with strict scope, the Secret's name and namespace are part of
the encryption. The sealed `tasktracker-credentials` for `dso202-dev` can
only be decrypted as `tasktracker-credentials` in `dso202-dev`. Someone who
can create objects in another namespace (or rename the object) cannot copy
the ciphertext from the public repository into a namespace they control and
have the controller decrypt it for them. Dev credentials also cannot be
replayed into staging.

**Lost:** flexibility. One sealed file cannot be reused across environments
or namespaces, and renaming or moving the Secret means sealing it again from
plaintext. That is why dev and staging each have their own sealed file.

**If the sealing key is lost** (cluster destroyed with no backup), every
SealedSecret in Git becomes undecryptable; they are useless ciphertext. A new
controller generates a new key pair, so the team must:

1. Obtain the plaintext credentials from the authoritative source (password
   manager or the running database), or rotate them if that source is also
   gone.
2. Re-seal each environment's Secret against the new controller with
   `kubeseal`, and commit the new SealedSecrets.
3. Back up the new key immediately, outside Git.

This is why the key was backed up straight after the controller was
installed, and why Task 9 restores it before the controller starts.

### Q3 (Task 5): `Synced` vs `Healthy`, with an example

- **Synced / OutOfSync** compares *desired with live*: whether the objects in
  the cluster match what Git (at the target revision) renders.
- **Healthy / Progressing / Degraded / Missing** says *whether the objects
  work*: Argo CD's health checks, for example whether a Deployment has
  reached its desired available replicas within `progressDeadlineSeconds`.

They are independent. In this assignment `tasktracker-dev` was **Synced but
Degraded** during the faulty release in Task 7: the Deployment in the cluster
matched Git exactly (image `sarojsanyasi/dso202-backend:1.1`), but the backend
Pods never became Ready, so after 120 s the Deployment exceeded its progress
deadline and Argo CD reported it Degraded:

```text
<!-- PASTE: argocd app get tasktracker-dev during the Task 7 faulty release,
     showing "Sync Status: Synced" and "Health Status: Degraded" -->
```

It can also be provoked by committing an image tag that cannot start, or by
lowering a container's memory limit below what it needs. The reverse case,
**OutOfSync but Healthy**, is Task 8 Drill 2: staging scaled by hand to 3
replicas works fine but no longer matches Git.

### Q4 (Task 6): Argo CD RBAC vs Kubernetes RBAC, and SSO

| | Argo CD RBAC | Kubernetes RBAC (Assignment 2) |
| --- | --- | --- |
| Controls | What a user of **Argo CD** (UI, CLI, API) may do with Argo CD resources: applications, projects, **logs**, exec, repositories, clusters, accounts; actions such as `get`, `sync`, `delete`, `override` | What a Kubernetes subject (user, group, ServiceAccount) may do through the **Kubernetes API**: verbs on resources such as pods, services and secrets |
| Configured in | ConfigMap `argocd-rbac-cm` (`policy.csv`, `policy.default`), accounts in `argocd-cm`. Here: `bootstrap/argocd/argocd-rbac-cm-patch.yaml` | Role/ClusterRole + RoleBinding/ClusterRoleBinding objects. Here: `platform/*/rbac.yaml` |
| Enforced by | `argocd-server` | `kube-apiserver` |

The two layers are separate. The `reviewer` account has no Kubernetes
credentials at all. Argo CD reads the cluster with its own ServiceAccount
and then filters what reviewer may see using `policy.csv`. That is why logs
needed their own `p, reviewer, logs, get, dso202/*, allow` line in Argo CD 3.x
and no Kubernetes Role.

**With SSO**, users would no longer be local accounts (`accounts.reviewer`
would be removed from `argocd-cm`). Policies would be attached to a role, and
the role mapped to an identity-provider **group** taken from the OIDC token,
for example:

```text
p, role:dso202-reviewer, applications, get, dso202/*, allow
p, role:dso202-reviewer, projects,     get, dso202,   allow
p, role:dso202-reviewer, logs,         get, dso202/*, allow
g, dso202-reviewers, role:dso202-reviewer
```

plus `scopes: '[groups]'` in `argocd-rbac-cm`, so access is granted and
removed in the identity provider instead of by editing passwords in the
cluster.

### Q5 (Task 7): Why is `argocd app rollback` refused, what is the GitOps equivalent, and why `git revert`?

`tasktracker-dev` has an automated sync policy, and Argo CD refuses a
rollback for an Application with auto-sync enabled. A rollback would set the
cluster to an older revision while Git still says something else, and the
next reconciliation would immediately re-apply what Git says. A rollback
outside Git would also break the rule that Git is the single source of truth.

```text
<!-- PASTE: output of the refused `argocd app rollback tasktracker-dev <id>` -->
```

The GitOps equivalent is **`git revert`** of the faulty commit, merged
through a pull request. This creates a new commit whose content is the
previous desired state. Argo CD pulls it like any other change, so the
rollback is itself reviewed, versioned and visible in `argocd app history`.

`git revert` is preferred over deleting the bad commit (`git reset` + force
push) because:

- History stays append-only. The audit trail shows what was released, that
  it failed, and who reverted it and when.
- Shared history is not rewritten, so other clones, open branches, existing
  tags and the revisions recorded in `argocd app history` stay valid.
- It works with protected `main` branches, where force pushes are blocked.
- A fix-forward (`v1.2.0`) can be built on top cleanly.

Pull requests opened for Task 7:

| # | Title | Purpose |
| --- | --- | --- |
| <!-- #n --> | Release frontend 1.1 | healthy release to dev, becomes `v1.1.0` |
| <!-- #n --> | Promote staging to v1.1.0 | staging gate |
| <!-- #n --> | Release backend 1.1 | faulty release (dev Degraded) |
| <!-- #n --> | Revert "Release backend 1.1" | recovery through `git revert` |
| <!-- #n --> | Fix forward backend 1.1 | fix from the logs, becomes `v1.2.0` |
| <!-- #n --> | Promote staging to v1.2.0 | staging gate |

### Q6 (Task 9)

**(a) Chart and environment configuration in one repository**

The Argo CD best-practices guidance recommends keeping deployment
configuration in a repository separate from the application source.

Advantages of keeping them together here:

1. **Atomic releases.** One commit, and one tag, pins the chart *and* the
   values together. `tasktracker-staging` at `v1.2.0` is guaranteed to render
   exactly what dev ran at that commit; there is no chance of a new chart
   meeting old values.
2. **Simplicity.** One URL, one `sourceRepos` entry per project, one place to
   review and one history to read, which suits a small team and a
   single-environment-pair assignment.

Disadvantages, as the guidance points out:

1. **Coupled history and access.** Chart (template) changes and environment
   changes (image tags, replicas) are mixed in one log, and anyone who may
   change the chart may also promote to an environment. Separate repositories
   allow different reviewers and permissions for "how it is built" and
   "where it runs".
2. **Unnecessary reconciliation and CI loops.** Every commit to the repository
   (even a README or chart-only edit) is a new revision for every Application
   tracking `main`, so Argo CD re-renders them all. When CI writes image tags
   back into the same repository that triggers CI, it risks build loops.
   Separating config from source avoids both.

The multi-source Application in Task 10 shows the middle ground: chart and
values come from separately referenced sources.

**(b) What is not under GitOps control, and how production teams handle it**

| Not in Git | How a production team usually handles it |
| --- | --- |
| Bootstrap layer (Argo CD install, `bootstrap/argocd`, the `platform` project) | Installed by infrastructure-as-code (e.g. Terraform with the Helm or Argo CD provider) as part of cluster provisioning, after which Argo CD often manages its own installation from Git. |
| The `root` Application | Created by the same provisioning pipeline (or an ApplicationSet), so a new cluster starts reconciling with no manual step. |
| The sealing key | Stored in a managed secrets store (Vault, AWS Secrets Manager or KMS) with tightly limited access and rotation, or replaced with External Secrets Operator so no long-lived key needs backing up. |
| Database contents (PVC data) | Protected by scheduled backups or volume snapshots (e.g. Velero, `pg_dump` to object storage), or by a managed database with point-in-time recovery; GitOps restores the schema and app, not the data. |
| Argo CD local account passwords | Replaced by SSO groups, so access is managed in the identity provider and nothing needs recreating after a rebuild. |
