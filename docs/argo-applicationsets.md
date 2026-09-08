# Argo CD ApplicationSets (team guide)

This repo uses **ApplicationSets** with **Go templates** (`goTemplate: true`).
If you are new to Argo CD, read this before editing files under `argocd/applicationsets/`.

## Mental model

```text
ApplicationSet  ──generates──►  Application  ──syncs──►  Kubernetes objects
     (1 YAML)                      (N apps)              (pods, Helm, CRDs…)
```

| Object | Who creates it? | What does it do? |
|--------|-----------------|------------------|
| **ApplicationSet** | You (`kubectl apply`) | Template + generator; stamps out Applications |
| **Application** | The ApplicationSet controller | Points at Git/Helm and keeps a namespace in sync |
| **AppProject** | You (`argocd/projects/zeppelin.yaml`) | Allow-list of repos and destination namespaces |

## Files in this repo

| File | ApplicationSet name | Creates Applications |
|------|---------------------|----------------------|
| `shared-platform-appset.yaml` | `zeppelin-shared-platform` | `shared-external-secrets`, `shared-cluster-secret-store` |
| `env-dev-appset.yaml` | `zeppelin-env-dev` | `dev-karpenter`, `dev-spark`, `dev-zeppelin` |
| `env-staging-appset.yaml` | `zeppelin-env-staging` | `staging-spark`, `staging-zeppelin` |
| `env-prod-appset.yaml` | `zeppelin-env-prod` | `prod-karpenter`, `prod-spark`, `prod-zeppelin` |

Each **environment** has its own ApplicationSet so you can sync/pause prod without touching dev.

## Go templates (`goTemplate: true`)

We use Go's `text/template` (same family of syntax as Helm), **not** the older `{{name}}` fasttemplate.

```yaml
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]   # typo in {{.field}} = hard fail
```

### Placeholders

Generator list fields become the template context:

```yaml
generators:
  - list:
      elements:
        - name: zeppelin
          namespace: zeppelin-dev
```

Then in the template:

```yaml
metadata:
  name: 'dev-{{.name}}'          # → dev-zeppelin
spec:
  destination:
    namespace: '{{.namespace}}'   # → zeppelin-dev
```

### Useful Go template pieces we use

| Syntax | Meaning |
|--------|---------|
| `{{.name}}` | Field `name` from the current list element |
| `{{.path}}` | Chart or directory path |
| `{{- if eq .kind "helm" }}` | Branch when `kind` equals `helm` |
| `{{- else }}` / `{{- end }}` | Rest of the if-block |
| `'$values/{{.valueFile}}'` | Multi-source Helm values path |

Always quote placeholders in YAML string fields: `'{{.path}}'`.

## Anatomy of one ApplicationSet

### 1. `generators`

Produces one parameter map per Application.

We use **`list`** (explicit, beginner-friendly). Other options you may see later: `git`, `clusters`, `matrix`, `pullRequest`.

### 2. `template`

Shared shape of every generated Application: name, project, destination, syncPolicy.

### 3. `templatePatch` (optional)

Extra YAML **merged** into the template, also rendered with Go templates. We use it when some apps are Helm and others are plain directories:

```yaml
templatePatch: |
  {{- if eq .kind "helm" }}
  spec:
    sources: ...
  {{- else }}
  spec:
    source: ...
  {{- end }}
```

## Multi-source Helm + `$values`

When values files live **outside** the chart (`apps/zeppelin/values-dev.yaml`):

```yaml
sources:
  - repoURL: https://git.example.com/org/zeppelin-eks-gitops.git
    targetRevision: main
    ref: values                    # does not deploy; only exposes the repo
  - repoURL: https://git.example.com/org/zeppelin-eks-gitops.git
    targetRevision: main
    path: charts/zeppelin
    helm:
      valueFiles:
        - $values/apps/zeppelin/values-dev.yaml
```

`$values/...` means “path relative to the source marked `ref: values`”.

## Sync waves

Annotation `argocd.argoproj.io/sync-wave` on the **Application** (set from `{{.syncWave}}`):

| Wave | Typical content |
|------|-----------------|
| `-1` | Karpenter NodePools / EC2NodeClass |
| `0` | External Secrets Operator |
| `1` | ClusterSecretStore |
| `2` | Spark Standalone (`charts/spark-cluster`) |
| `3` | Zeppelin |

Lower numbers sync first.

## Sync policy cheat sheet

| Field | Effect |
|-------|--------|
| `automated.prune` | Delete cluster objects removed from Git |
| `automated.selfHeal` | Revert manual `kubectl` drift |
| `CreateNamespace=true` | Create destination namespace automatically |
| `ServerSideApply=true` | Prefer SSA (friendlier to CRDs) |

## How to verify

```bash
# ApplicationSets
kubectl get applicationsets -n argocd

# Applications they created
kubectl get applications -n argocd -l app.kubernetes.io/part-of=zeppelin-platform

# Describe one ApplicationSet (status shows generated apps / errors)
kubectl describe applicationset zeppelin-env-dev -n argocd
```

## Common mistakes

1. **Forgetting `goTemplate: true`** but writing `{{.name}}` — placeholders won't expand correctly.
2. **Typo in a field** without `missingkey=error` — silent empty strings.
3. **Two ApplicationSets managing the same Karpenter YAML** (e.g. adding Karpenter to staging) — constant thrash / ownership fights.
4. **Leaving `REPLACE_ME_GITOPS_REPO_URL`** — Applications can't clone.
5. **Using `{{name}}` (no dot)** while `goTemplate: true` — wrong engine syntax.

## Official docs

- [ApplicationSet](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/)
- [Go template support](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/GoTemplate/)
- [Generators](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators/)
- [Multiple sources](https://argo-cd.readthedocs.io/en/stable/user-guide/multiple_sources/)
