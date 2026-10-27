{{- define "task-tracker.fullname" -}}
{{- default .Release.Name .Values.nameOverride | trunc 40 | trimSuffix "-" -}}
{{- end -}}

{{- define "task-tracker.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/part-of: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end -}}

{{- define "task-tracker.selectorLabels" -}}
app: {{ include "task-tracker.fullname" .root }}-{{ .tier }}
tier: {{ .tier }}
{{- end -}}

{{- define "task-tracker.configName" -}}
{{ include "task-tracker.fullname" . }}-config
{{- end -}}

{{- define "task-tracker.secretName" -}}
{{ include "task-tracker.fullname" . }}-secret
{{- end -}}
