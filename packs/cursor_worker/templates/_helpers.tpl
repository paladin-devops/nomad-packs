[[- /*

Helpers for the cursor_worker pack. Text outside a define is not part of a
job. Call each helper with the pack context (.), except constraints and
resources, which take the value they render.

*/ -]]

[[- define "job_name" -]]
[[- coalesce (var "job_name" .) (meta "pack.name" .) | quote -]]
[[- end -]]

[[- define "job_id" -]]
[[- coalesce (var "job_name" .) (meta "pack.name" .) -]]
[[- end -]]

[[- define "service_name" -]]
[[- if ne (var "service_name" .) "" -]]
[[- var "service_name" . -]]
[[- else -]]
[[- replace "_" "-" (coalesce (var "job_name" .) (meta "pack.name" .)) -]]
[[- end -]]
[[- end -]]

[[- define "region" -]]
[[- if var "region" . -]]
region = [[ var "region" . | quote ]]
[[- end -]]
[[- end -]]

[[- define "namespace" -]]
[[- if var "namespace" . -]]
namespace = [[ var "namespace" . | quote ]]
[[- end -]]
[[- end -]]

[[- define "constraints" -]]
[[- range $constraint := . ]]
  constraint {
    attribute = [[ $constraint.attribute | quote ]]
    [[- if ne $constraint.operator "" ]]
    operator  = [[ $constraint.operator | quote ]]
    [[- end ]]
    value     = [[ $constraint.value | quote ]]
  }
[[- end -]]
[[- end -]]

[[- define "resources" -]]
[[- $resources := . ]]
      resources {
        cpu    = [[ $resources.cpu ]]
        memory = [[ $resources.memory ]]
      }
[[- end -]]

[[- define "api_key_path" -]]
[[- if ne (var "api_key_path" .) "" -]]
[[- var "api_key_path" . -]]
[[- else -]]
[[- printf "nomad/jobs/%s" (coalesce (var "job_name" .) (meta "pack.name" .)) -]]
[[- end -]]
[[- end -]]
