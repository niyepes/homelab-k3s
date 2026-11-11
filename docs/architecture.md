# Arquitectura y dependencias de reconciliación

```mermaid
flowchart TD
  Git[GitHub repository] --> Flux[Flux controllers]
  Flux --> Infra[Infrastructure Kustomization]
  Infra --> CNPG[CloudNativePG operator]
  Infra --> TSO[Tailscale Operator]
  Infra --> Sources[Helm repositories]
  Infra --> DB[Immich database Kustomization]
  DB --> PVC[Library PVC]
  DB --> PG[PostgreSQL 18 + VectorChord]
  PG --> App[Immich HelmRelease]
  App --> Server[Immich Server]
  App --> ML[Machine Learning]
  App --> Valkey[Valkey]
  App --> Access[Tailscale Ingress]
  Infra --> Monitoring[Prometheus + Grafana]
  Phone[Phone + Tailscale client] --> Access
```

## Dependencias

- `infrastructure` instala operadores y HelmRepositories.
- `immich-database` espera a `infrastructure` y espera a que CloudNativePG declare saludable el Cluster.
- `immich-app` espera a `immich-database`.
- `immich-access` espera a `immich-app`.
- `monitoring` espera a `infrastructure`.

## Límites de persistencia

Los volúmenes `local-path` viven en el nodo local y se aprovisionan bajo `/srv/homelab/k3s-storage`. No hay replicación. Los volúmenes de PostgreSQL y la biblioteca deben tratarse como datos críticos. No borres PVC/PV para “arreglar” un despliegue sin entender el impacto.
