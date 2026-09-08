{{/*
Expand the name of the chart.
*/}}
{{- define "spark-cluster.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "spark-cluster.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "spark-cluster.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "spark-cluster.labels" -}}
helm.sh/chart: {{ include "spark-cluster.chart" . }}
{{ include "spark-cluster.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Values.environment }}
app.kubernetes.io/environment: {{ .Values.environment | quote }}
{{- end }}
{{- end }}

{{- define "spark-cluster.selectorLabels" -}}
app.kubernetes.io/name: {{ include "spark-cluster.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "spark-cluster.masterService" -}}
{{- printf "%s-master" (include "spark-cluster.fullname" .) }}
{{- end }}

{{- define "spark-cluster.masterHeadless" -}}
{{- printf "%s-master-hs" (include "spark-cluster.fullname" .) }}
{{- end }}

{{- define "spark-cluster.masterStatefulSetName" -}}
{{- printf "%s-master" (include "spark-cluster.fullname" .) }}
{{- end }}

{{- define "spark-cluster.zookeeperName" -}}
{{- printf "%s-zookeeper" (include "spark-cluster.fullname" .) }}
{{- end }}

{{- define "spark-cluster.zookeeperHeadless" -}}
{{- printf "%s-zookeeper-hs" (include "spark-cluster.fullname" .) }}
{{- end }}

{{/*
ZooKeeper connection string for Spark recoveryMode.
*/}}
{{- define "spark-cluster.zookeeperUrl" -}}
{{- $replicas := int .Values.ha.zookeeper.replicaCount -}}
{{- $name := include "spark-cluster.zookeeperName" . -}}
{{- $hs := include "spark-cluster.zookeeperHeadless" . -}}
{{- $ns := .Release.Namespace -}}
{{- $port := int .Values.ha.zookeeper.clientPort -}}
{{- $parts := list -}}
{{- range $i := until $replicas -}}
{{- $parts = append $parts (printf "%s-%d.%s.%s.svc.cluster.local:%d" $name $i $hs $ns $port) -}}
{{- end -}}
{{- join "," $parts -}}
{{- end }}

{{/*
Spark master URL for workers / Zeppelin.
HA: spark://master-0.hs.ns:7077,master-1.hs.ns:7077
Single: spark://spark-master:7077 (same-ns) — NOTES use FQDN via values for cross-ns.
*/}}
{{- define "spark-cluster.masterUrl" -}}
{{- if .Values.ha.enabled -}}
{{- if lt (int .Values.ha.masters) 2 -}}
{{- fail "ha.masters must be >= 2 when ha.enabled is true" -}}
{{- end -}}
{{- $n := int .Values.ha.masters -}}
{{- $sts := include "spark-cluster.masterStatefulSetName" . -}}
{{- $hs := include "spark-cluster.masterHeadless" . -}}
{{- $ns := .Release.Namespace -}}
{{- $port := int .Values.master.rpcPort -}}
{{- $parts := list -}}
{{- range $i := until $n -}}
{{- $parts = append $parts (printf "%s-%d.%s.%s.svc.cluster.local:%d" $sts $i $hs $ns $port) -}}
{{- end -}}
{{- printf "spark://%s" (join "," $parts) -}}
{{- else -}}
{{- printf "spark://%s.%s.svc.cluster.local:%v" (include "spark-cluster.masterService" .) .Release.Namespace .Values.master.rpcPort -}}
{{- end -}}
{{- end }}

{{- define "spark-cluster.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "spark-cluster.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
