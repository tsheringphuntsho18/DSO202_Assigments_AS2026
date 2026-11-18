# DSO202 Assignment 4 — GitOps Delivery of the Task Tracker with Argo CD

## Purpose

This directory delivers the Task Tracker application (frontend, backend, PostgreSQL —
built in Assignments 1–3) to two Kubernetes namespaces, `dso202-dev` and
`dso202-staging`, using Argo CD as a GitOps controller. After the one-time
bootstrap in Task 2/3, nothing in the cluster is created, edited or deleted
with `kubectl`; every change is a commit to this repository, and Argo CD
reconciles the live cluster to match it.

Note on repository layout: the assignment brief names a dedicated repository
`dso202-gitops`. This submission instead lives at `assignment-4/` inside the
combined repository `DSO202_Assigments_AS2026`, alongside Assignments 1–3.
Every path referenced by an Argo CD `Application` or `AppProject` is
therefore prefixed with `assignment-4/`; the repository URL
(`https://github.com/tsheringphuntsho18/DSO202_Assigments_AS2026.git`) is
written identically in every file that needs it.

## Pinned versions (section 3.1)

| Component | Version |
| --- | --- |
| Argo CD | v3.5.6 |
| `argocd` CLI | v3.5.6 |
| Sealed Secrets Helm chart | 2.20.0 |
| Sealed Secrets controller | 0.40.0 |
| `kubeseal` CLI | v0.40.0 |
| kind | v0.32.0 |
| kind node image | `kindest/node:v1.36.1` (Practical 1 pin) |
| kubectl (client) | v1.34.1 |
| Helm | v3.22.1 |

Task Tracker images are the tutor-issued ones published under the module
account, not a student account: `sarojsanyasi/dso202-frontend`,
`sarojsanyasi/dso202-backend`, `sarojsanyasi/dso202-db`. Baseline tag `1.0`
for all three; `1.1` is the Task 7 release tag for frontend and backend only.

## Repository layout

See `assignment-4/` for the structure (section 7 of the brief): `cluster/`,
`bootstrap/`, `argocd/`, `platform/`, `charts/`, `environments/`, `docs/`.

## End-to-end build commands (Task 9)

<!-- Filled in after Task 9 is executed; see docs/evidence.md Task 9 for the
     full transcript. -->

```bash
# 1. Sealing key must already be backed up outside the repo (see "Credential
#    management" below) before this sequence is run.
kind create cluster --name dso202-gitops --config cluster/kind-cluster.yaml
kubectl create namespace sealed-secrets
kubectl apply -f <path-to-backed-up-sealing-key>
kubectl apply -k bootstrap/argocd --server-side --force-conflicts
kubectl wait --for=condition=Available deployment --all -n argocd --timeout=300s
kubectl rollout status statefulset/argocd-application-controller -n argocd --timeout=300s
kubectl apply -f bootstrap/root
# wait for Applications to reach Healthy, then:
argocd admin initial-password -n argocd
argocd login localhost:8080 --username admin --insecure
argocd app sync tasktracker-staging
```

## Cleanup

```bash
kind delete cluster --name dso202-gitops
```

## Credential management

Database and backend credentials (`DB_USER`, `DB_PASSWORD`, `POSTGRES_USER`,
`POSTGRES_PASSWORD`) are never committed in plaintext or as a Kubernetes
`Secret`. They are sealed with `kubeseal` against the cluster's Sealed
Secrets controller and committed only as `SealedSecret` objects
(`platform/dev/tasktracker-credentials.sealed.yaml`,
`platform/staging/tasktracker-credentials.sealed.yaml`), which only that
cluster's controller can decrypt. The controller's private sealing key is
backed up outside this repository (see Task 4 in `docs/evidence.md` for the
exact location and permissions) immediately after the controller is
installed and again after every rebuild (Task 9); it is never pasted, logged
or committed.

## Written answers

### Q1 — Task 3

<!-- TODO -->

### Q2 — Task 4

<!-- TODO -->

### Q3 — Task 5

<!-- TODO -->

### Q4 — Task 6

<!-- TODO -->

### Q5 — Task 7

<!-- TODO -->

Pull requests opened for Task 7:

<!-- TODO: list of PR titles/numbers -->

### Q6 — Task 9

**(a)**

<!-- TODO -->

**(b)**

<!-- TODO -->
