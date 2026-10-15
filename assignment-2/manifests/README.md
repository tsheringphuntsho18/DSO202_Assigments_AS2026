# Supplemental Assignment 2 Manifests

- `database-statefulset.yaml`: PostgreSQL StatefulSet with `volumeClaimTemplates`.
- `ingress.yaml`: host-based Ingress route to the frontend Service.
- `rbac.yaml`: dedicated ServiceAccounts, namespace-scoped Role, and RoleBinding.

## Before applying

Compare the ConfigMap and Secret names/keys in `database-statefulset.yaml` with your actual Assignment 1 manifests. This example assumes `task-tracker-config`, `task-tracker-secret`, and keys `POSTGRES_DB`, `POSTGRES_USER`, and `POSTGRES_PASSWORD`. Update them if your files use different names.

The StatefulSet creates a new PVC. It does not migrate data from the Assignment 1 PVC. Do not switch the database workload until you have planned and verified backup/restore and preserved the old PVC for rollback.
