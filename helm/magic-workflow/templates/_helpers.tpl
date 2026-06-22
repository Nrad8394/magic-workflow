{{/* ============================ Naming ============================ */}}
{{- define "mw.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "mw.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "mw.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Common labels applied to every object. */}}
{{- define "mw.labels" -}}
helm.sh/chart: {{ include "mw.chart" . }}
app.kubernetes.io/name: {{ include "mw.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{- end -}}

{{/* Per-component selector labels. Usage: include "mw.componentLabels" (dict "root" $ "component" "postgres") */}}
{{- define "mw.componentLabels" -}}
app.kubernetes.io/name: {{ include "mw.name" .root }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{/* ============================ Images ============================ */}}
{{/* Usage: include "mw.image" (dict "root" $ "image" .Values.postgres.image) */}}
{{- define "mw.image" -}}
{{- $reg := .root.Values.global.imageRegistry | default "" -}}
{{- printf "%s%s:%s" $reg .image.repository (.image.tag | toString) -}}
{{- end -}}

{{- define "mw.imagePullPolicy" -}}
{{- .root.Values.global.imagePullPolicy | default "IfNotPresent" -}}
{{- end -}}

{{/* ============================ Secrets ============================ */}}
{{/* Name of the Secret holding all credentials. */}}
{{- define "mw.secretName" -}}
{{- if .Values.existingSecret -}}
{{- .Values.existingSecret -}}
{{- else -}}
{{- printf "%s-secrets" (include "mw.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/* ============================ Platform ============================ */}}
{{- define "mw.isOpenShift" -}}
{{- eq (.Values.platform | default "kubernetes") "openshift" -}}
{{- end -}}

{{/* Pod-level securityContext. Empty on OpenShift so the SCC assigns the UID range. */}}
{{- define "mw.podSecurityContext" -}}
{{- if not (eq (.Values.platform | default "kubernetes") "openshift") -}}
{{- with .Values.podSecurityContext }}
{{ toYaml . }}
{{- end -}}
{{- end -}}
{{- end -}}

{{/* ServiceAccount name. */}}
{{- define "mw.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "mw.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}
