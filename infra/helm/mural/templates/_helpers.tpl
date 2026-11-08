{{- define "mural.fullname" -}}
{{- .Release.Name | trunc 40 | trimSuffix "-" -}}
{{- end -}}

{{- define "mural.labels" -}}
app.kubernetes.io/name: mural
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "mural.migrationsHash" -}}
{{- .Files.Glob "files/migrations/*.sql" | toJson | sha256sum | trunc 12 -}}
{{- end -}}

{{- define "mural.migrationPodSpec" -}}
restartPolicy: Never
automountServiceAccountToken: false
containers:
  - name: migrate
    image: "{{ .Values.postgres.image.repository }}:{{ .Values.postgres.image.tag }}"
    imagePullPolicy: {{ .Values.postgres.image.pullPolicy }}
    command: ["/bin/sh", "-ec"]
    args:
      - |
        attempts=0
        until psql --no-psqlrc "$DATABASE_URL" -c 'SELECT 1' >/dev/null 2>&1; do
          attempts=$((attempts + 1))
          if [ "$attempts" -ge 60 ]; then
            echo 'Banco indisponível após espera limitada' >&2
            exit 1
          fi
          sleep 2
        done
        set --
        for migration in /migrations/*.sql; do
          set -- "$@" -f "$migration"
        done
        exec psql --no-psqlrc "$DATABASE_URL" --single-transaction -v ON_ERROR_STOP=1 "$@"
    env:
      - name: DATABASE_URL
        valueFrom:
          secretKeyRef:
            name: {{ include "mural.fullname" . }}-database
            key: DATABASE_URL
      - name: PGCONNECT_TIMEOUT
        value: "3"
    resources:
      {{- toYaml .Values.migration.resources | nindent 6 }}
    volumeMounts:
      - name: migrations
        mountPath: /migrations
        readOnly: true
volumes:
  - name: migrations
    configMap:
      name: {{ include "mural.fullname" . }}-migrations-{{ include "mural.migrationsHash" . }}
{{- end -}}
