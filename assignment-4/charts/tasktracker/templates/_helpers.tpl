{{/*
=============================================================================
File        : charts/tasktracker/templates/_helpers.tpl
Assignment  : DSO202 Assignment 4 (carried over from Assignment 3)
Purpose     : Naming helpers shared by every template. "task-tracker.secretName"
              now resolves to .Values.existingSecret (chart contract C3): the
              chart never renders a Secret, it only reads the name of one that
              Sealed Secrets has already decrypted into the namespace.
=============================================================================
*/}}
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
{{ required "Values.existingSecret must name the SealedSecret-decrypted Secret (tasktracker-credentials)" .Values.existingSecret }}
{{- end -}}
