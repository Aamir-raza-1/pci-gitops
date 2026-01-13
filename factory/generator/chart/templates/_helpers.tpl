{{/*
Returns the standard namespace name for all tenant resources.
*/}}
{{- define "tenant.namespace" -}}
t-{{ .Values.tenant_code }}-{{ .Values.environment }}
{{- end -}}

{{/*
Returns a standardized, unique name for a given resource kind.
*/}}
{{- define "tenant.resourceName" -}}
{{ .kind | lower }}-{{ .Values.tenant_code }}-{{ .Values.environment }}
{{- end -}}

{{/*
Returns a standardized, unique name for a subnet.
*/}}
{{- define "tenant.subnetName" -}}
subnet-{{ .Values.tenant_code }}-{{ .Values.environment }}-{{ .subnet.name }}
{{- end -}}