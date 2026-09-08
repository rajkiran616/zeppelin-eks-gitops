# NetworkPolicies (Zeppelin + Spark)

The chart renders **generic** NetworkPolicies. You manage rules entirely in values as
native Kubernetes `ingress` / `egress` rule lists — append items to add rules;
no template edits required.

| Policy | Namespace | Default pod select |
|--------|-----------|--------------------|
| `zeppelin` (or `networkPolicy.zeppelin.name`) | release ns | chart selector labels |
| `zeppelin-spark` (or `networkPolicy.spark.name`) | `spark-jobs-<env>` | `{}` = all pods |

## Shape

```yaml
networkPolicy:
  enabled: true
  zeppelin:
    enabled: true
    policyTypes: [Ingress, Egress]
    # Optional: name, labels, annotations, podSelector
    ingress: []   # list of NetworkPolicyIngressRule
    egress: []    # list of NetworkPolicyEgressRule
  spark:
    enabled: true
    policyTypes: [Ingress, Egress]
    podSelector: {}
    ingress: []
    egress: []
```

Templates only do:

```yaml
ingress:
  {{- tpl (toYaml .Values.networkPolicy.zeppelin.ingress) $ | nindent 4 }}
```

So every field Kubernetes supports (`from`, `to`, `ports`, `ipBlock`, `namespaceSelector`, `podSelector`, …) works as-is.

## Dynamic namespaces via `tpl`

String values may contain Helm expressions. Useful for cross-namespace peers:

```yaml
ingress:
  - from:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: "{{ .Release.Namespace }}"
egress:
  - to:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: "{{ .Values.rbac.sparkJobNamespace }}"
```

## Adding rules (examples)

### Extra Zeppelin ingress (CIDR + second namespace)

```yaml
networkPolicy:
  zeppelin:
    ingress:
      - from:
          - namespaceSelector:
              matchLabels:
                kubernetes.io/metadata.name: kube-system
        ports:
          - protocol: TCP
            port: 8080
      - from:
          - namespaceSelector:
              matchLabels:
                kubernetes.io/metadata.name: monitoring
        ports:
          - protocol: TCP
            port: 8080
      - from:
          - ipBlock:
              cidr: 10.10.0.0/16
              except:
                - 10.10.99.0/24
        ports:
          - protocol: TCP
            port: 8080
```

### Extra Spark egress (VPC / S3 endpoint)

```yaml
networkPolicy:
  spark:
    egress:
      # …keep DNS / API / intra-ns rules from values.yaml…
      - to:
          - ipBlock:
              cidr: 10.0.0.0/8
        ports:
          - protocol: TCP
            port: 443
```

In env overlays, **replace** the whole `ingress` or `egress` list (Helm deep-merge replaces lists), or copy the base list and append.

## Defaults

- **Dev/staging:** inherit lists from `charts/zeppelin/values.yaml` (UI from any namespace; Spark intra-ns + from Zeppelin).
- **Prod:** `apps/zeppelin/values-prod.yaml` replaces Zeppelin ingress with `kube-system` only; egress still includes Spark ns via `tpl`.

## Verify

```bash
kubectl get networkpolicy -A | grep zeppelin
kubectl get networkpolicy zeppelin -n zeppelin-dev -o yaml
kubectl get networkpolicy zeppelin-spark -n spark-jobs-dev -o yaml
```

## CNI

Policies only enforce if your CNI supports NetworkPolicy (VPC CNI network policy, Calico, Cilium, …).
