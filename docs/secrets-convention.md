# Secrets convention

Zeppelin UI has **no Shiro** (`anonymousAllowed: true`). Secrets are for **app credentials**
(API keys, DB passwords, etc.), injected as environment variables.

| Environment | How secrets get into the cluster |
|-------------|----------------------------------|
| **Local** (Kind / Docker Desktop) | You create a Kubernetes Secret |
| **EKS** (dev / staging / prod) | AWS Secrets Manager → External Secrets Operator |

Platform pin (EKS): External Secrets Helm chart **2.10.0**, API `external-secrets.io/v1`.

## Local — Kubernetes Secret

```bash
# Creates/edits local-data/app.env, then builds Secret zeppelin-kind/zeppelin-app
./hack/create-local-app-secret.sh

# Or one-shot:
./hack/create-local-app-secret.sh MY_TOKEN=secret MY_DB_URL=jdbc:...
```

Then enable in `apps/zeppelin/values-kind.yaml` (or `--set`):

```yaml
appSecrets:
  enabled: true
  secretName: zeppelin-app
  source: existing
  envFrom: true
```

Re-install / upgrade Zeppelin so pods pick up `envFrom`.

## EKS — Secrets Manager + External Secrets

Create a secret in the **AWS Console** (or CLI). JSON keys become K8s Secret keys → env vars.

| SM secret name | K8s Secret | Namespace |
|----------------|------------|-----------|
| `zeppelin/dev/app` | `zeppelin-app` | `zeppelin-dev` |
| `zeppelin/staging/app` | `zeppelin-app` | `zeppelin-staging` |
| `zeppelin/prod/app` | `zeppelin-app` | `zeppelin-prod` |

Example payload:

```json
{
  "MY_API_TOKEN": "…",
  "JDBC_PASSWORD": "…"
}
```

```bash
aws secretsmanager create-secret \
  --name zeppelin/dev/app \
  --secret-string file://app-dev.json \
  --region REPLACE_ME_REGION
```

Helm (`apps/zeppelin/values-<env>.yaml`):

```yaml
appSecrets:
  enabled: true
  secretName: zeppelin-app
  source: externalSecrets
  envFrom: true
  externalSecrets:
    remoteKey: zeppelin/<env>/app
```

## Rules

1. Do not commit real secrets (`local-data/app.env` is gitignored).
2. Prefer IRSA for S3; no static AWS keys in Secrets Manager for that.
3. EKS: rotate in Console; ESO refreshes on `refreshInterval`.
4. Local: edit `local-data/app.env`, re-run `create-local-app-secret.sh`, restart Zeppelin.
5. ESO IRSA needs `secretsmanager:GetSecretValue` on `zeppelin/*` (Terraform).
