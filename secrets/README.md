# Secretos

No guardes secretos en Git.

Para la primera instalación se crean localmente mediante:

```bash
./scripts/create-bootstrap-secrets.sh
```

Esto crea:
- `tailscale/tailscale-oauth`: contiene un documento YAML como valor de `values.yaml` para el HelmRelease.
- `monitoring/grafana-admin`: credenciales iniciales de Grafana.

En una siguiente fase se recomienda adoptar SOPS + Age con Flux para cifrar secretos en Git. Hasta entonces, los secretos se gestionan fuera del repositorio y deben recrearse si el clúster se reinstala.
