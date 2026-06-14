{{/*
Base name for resources.
*/}}
{{- define "argo-cicd-app.name" -}}
{{- .Chart.Name -}}
{{- end -}}

{{/*
Fully qualified app name, used as the base for Rollout/Service/Ingress names.
*/}}
{{- define "argo-cicd-app.fullname" -}}
{{- if eq .Release.Name (include "argo-cicd-app.name" .) -}}
{{- .Release.Name -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "argo-cicd-app.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Common labels.
*/}}
{{- define "argo-cicd-app.labels" -}}
app.kubernetes.io/name: {{ include "argo-cicd-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Selector labels — used by Service/Rollout/Deployment selectors.
*/}}
{{- define "argo-cicd-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "argo-cicd-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Service account name.
*/}}
{{- define "argo-cicd-app.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "argo-cicd-app.name" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}
