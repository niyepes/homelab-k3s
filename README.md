# Homelab K3s + Flux + Immich

Base GitOps para un homelab de un solo nodo K3s en Ubuntu x86_64, diseñado para poder adaptar después a Raspberry Pi 5 ARM64.

## Alcance de esta versión

Incluye:

- K3s como Kubernetes local.
- Flux CD con bootstrap desde GitHub.
- Tailscale Kubernetes Operator.
- StorageClass `local-path` de K3s y PVC locales.
- Immich v3 + Valkey + PostgreSQL 18 con VectorChord, administrado por CloudNativePG.
- Ingress privado de Immich hacia el tailnet de Tailscale.
- Prometheus + Grafana mediante `kube-prometheus-stack`.

Queda explícitamente fuera: ingesta del smartwatch, PostgreSQL de sueño, backups, recuperación ante desastres y migración a Raspberry Pi.

> **Advertencia de datos:** el almacenamiento `local-path` persiste en el disco del nodo, pero no es alta disponibilidad ni backup. Usa fotografías de prueba hasta implementar y probar una estrategia de copias de seguridad.

## Arquitectura y decisiones

- K3s conserva sus componentes empaquetados por defecto. No instalamos otro CNI ni otro Ingress Controller.
- El provisionador `local-path` incluido en K3s crea PVC locales. Un PV queda ligado al nodo que lo aprovisionó.
- Immich se instala desde el chart OCI publicado en `ghcr.io/immich-app/immich-charts`.
- Valkey (compatible con el protocolo Redis) se habilita desde el chart de Immich.
- PostgreSQL se administra con CloudNativePG y la imagen oficial PostgreSQL 18 + extensión VectorChord como image volume extension, siguiendo el ejemplo actual del chart de Immich.
- Tailscale Operator publica únicamente Immich en tu tailnet. PostgreSQL, Valkey y Grafana no se exponen a Internet ni al tailnet.
- Grafana y Prometheus se consultan inicialmente mediante `kubectl port-forward`.
- Las versiones de charts e imágenes están fijadas en los manifiestos. No se habilita actualización automática de versiones mayores.

## Requisitos recomendados

| Recurso | Recomendación para este conjunto |
|---|---|
| SO | Ubuntu 22.04/24.04 o compatible con systemd |
| Arquitectura inicial | amd64 / x86_64 |
| CPU | 4 cores o más |
| RAM | 16 GB recomendados; con 8 GB puede haber presión de memoria |
| Disco | SSD con al menos 100 GB libres para comenzar |
| Red | Acceso a Internet para descargar imágenes y charts |
| Git | Repositorio GitHub vacío o existente |
| Tailscale | Cuenta/tailnet y OAuth client para Kubernetes Operator |

Immich por sí solo recomienda 8 GB de RAM; Prometheus, Grafana, PostgreSQL y K3s también necesitan recursos. Ajusta los límites y la retención si tu host tiene menos memoria.

## 1. Descargar y preparar el repositorio

Descomprime el ZIP y entra en la carpeta:

```bash
unzip homelab-k3s-gitops.zip
cd homelab-k3s-gitops
```

Crea un repositorio vacío en GitHub, por ejemplo `homelab-k3s-gitops`. Luego conecta y publica este proyecto:

```bash
git init
git branch -M main
git add .
git commit -m "chore: initial homelab GitOps layout"
git remote add origin https://github.com/TU_USUARIO/homelab-k3s-gitops.git
git push -u origin main
```

No subas tokens, contraseñas ni archivos `.env`. Los secretos se crean localmente en Kubernetes antes de activar Flux.

## 2. Instalar K3s en Ubuntu

Desde la raíz del proyecto:

```bash
chmod +x scripts/*.sh
sudo ./scripts/install-k3s.sh
```

El script:
- crea `/srv/homelab/k3s-storage`;
- configura el path del provisionador local;
- instala K3s desde el canal `stable`;
- no desactiva Traefik ni los componentes estándar de K3s.

Comprueba el nodo:

```bash
sudo k3s kubectl get nodes -o wide
sudo k3s kubectl get storageclass
```

Debes ver el nodo `Ready` y una StorageClass `local-path` marcada como `(default)`.

### Configurar kubectl para tu usuario

Para administrar el clúster desde la misma máquina:

```bash
./scripts/configure-kubeconfig.sh 127.0.0.1
```

Si vas a usar kubectl desde otro equipo de tu LAN, pasa la IP LAN del host Ubuntu en lugar de `127.0.0.1`. No expongas el puerto 6443 a Internet.

```bash
kubectl get nodes
kubectl get pods -A
```

El script crea `~/.kube/config-k3s-homelab`; no sobrescribe el kubeconfig de Minikube. Para alternar contextos:

```bash
export KUBECONFIG="$HOME/.kube/config-k3s-homelab"
kubectl config get-contexts
```

Tu configuración de Minikube sigue independiente.

## 3. Instalar Flux CLI

```bash
./scripts/install-flux-cli.sh
flux --version
```

Comprueba los prerequisitos:

```bash
flux check --pre
```

## 4. Crear credenciales de Tailscale y Grafana

Antes de iniciar Flux, crea un OAuth client en la consola de administración de Tailscale.

### Tailscale OAuth client

En la consola de Tailscale:

1. Crea los tags `tag:k8s-operator` y `tag:k8s`.
2. En `tagOwners`, permite que `autogroup:admin` gestione `tag:k8s-operator` y que `tag:k8s-operator` gestione `tag:k8s`.
3. Crea un OAuth client con permisos de escritura necesarios para administrar dispositivos y auth keys. Sigue la matriz de permisos vigente en la documentación oficial.
4. Guarda el Client ID y Client Secret.

La documentación oficial del Operator es la referencia para los scopes y tags exactos:
https://tailscale.com/docs/kubernetes-operator/install-operator

### Crear secretos locales

Ejecuta:

```bash
./scripts/create-bootstrap-secrets.sh
```

El script te pedirá:
- Tailscale OAuth Client ID.
- Tailscale OAuth Client Secret.
- Contraseña inicial de Grafana.

Crea los namespaces `tailscale` y `monitoring` y los secretos:
- `tailscale/tailscale-oauth`, con la clave `values.yaml` que consume HelmRelease.
- `monitoring/grafana-admin`, con `admin-user` y `admin-password`.

**No añadas esos secretos al repositorio.** El script crea los recursos directamente en el clúster. En una siguiente iteración podemos migrarlos a SOPS + Age para cifrarlos y gestionarlos desde Git.

## 5. Activar Flux GitOps

Asegúrate de estar en la raíz del repositorio y tener el kubeconfig de K3s activo:

```bash
export KUBECONFIG="$HOME/.kube/config-k3s-homelab"
```

Crea un GitHub Personal Access Token con permisos administrativos suficientes para que Flux configure el repositorio y el deploy key. Exporta las variables:

```bash
export GITHUB_TOKEN="TU_TOKEN"
export GITHUB_OWNER="TU_USUARIO"
export GITHUB_REPOSITORY="homelab-k3s-gitops"
```

Ejecuta el bootstrap:

```bash
flux bootstrap github \
  --owner="$GITHUB_OWNER" \
  --repository="$GITHUB_REPOSITORY" \
  --branch=main \
  --path=clusters/local \
  --personal
```

El bootstrap instala los controladores Flux y configura la sincronización desde GitHub. Es normal que Flux cree/actualice archivos dentro de `clusters/local/flux-system`.

Ahora incorpora la configuración raíz de este proyecto, que añade las Kustomizations de infraestructura y aplicaciones:

```bash
git pull --rebase origin main
cp clusters/local/kustomization.yaml.template clusters/local/kustomization.yaml
git add clusters/local/kustomization.yaml
git commit -m "chore(flux): reconcile homelab components"
git push origin main
```

A partir de aquí, Flux sincroniza:
1. Controladores y fuentes Helm.
2. Base de datos de Immich.
3. Immich.
4. Ingress privado de Immich.
5. Prometheus y Grafana.

Los secretos OAuth y Grafana ya deben existir antes de que Helm instale los charts.

## 6. Verificar reconciliación

```bash
flux get all -A
kubectl get kustomizations -A
kubectl get helmreleases -A
kubectl get pods -A -o wide
```

Verifica CloudNativePG:

```bash
kubectl get clusters.postgresql.cnpg.io -n immich
kubectl get pods -n immich
kubectl get pvc -n immich
```

Espera a que:
- el Cluster `immich-database` esté `Cluster in healthy state`;
- los pods de Immich estén `Running` y listos;
- el Ingress de Tailscale tenga dirección/estado reconciliado.

Para revisar eventos:

```bash
kubectl get events -A --sort-by=.lastTimestamp
kubectl describe helmrelease immich -n immich
kubectl logs -n cnpg-system deploy/cnpg-cloudnative-pg
```

El nombre del Deployment de CNPG puede variar con la versión del chart. Descúbrelo con `kubectl get deploy -n cnpg-system`.

## 7. Acceder a Immich desde el teléfono

1. Espera a que `tailscale-operator` aparezca como dispositivo en el panel de Tailscale.
2. Instala Tailscale en tu Android o iPhone e inicia sesión en el mismo tailnet.
3. En el panel Tailscale, confirma el nombre DNS asignado al Ingress `immich`.
4. Habilita HTTPS certificates en el tailnet si todavía no está habilitado.
5. Abre en el navegador `https://immich.<TU_TAILNET>.ts.net` (sustituye el dominio por el que Tailscale muestre para el dispositivo/Ingress).
6. Instala Immich desde Google Play o App Store y configura esa misma URL como Server URL.

El Ingress usa `ingressClassName: tailscale`; el tráfico permanece dentro del tailnet. No se crea un LoadBalancer público ni se expone PostgreSQL.

Documentación:
- https://tailscale.com/docs/kubernetes-operator/ingress
- https://immich.app/download

## 8. Acceder a Prometheus y Grafana

Grafana:

```bash
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
```

Abre http://localhost:3000. Usuario `admin`; usa la contraseña que introdujiste al ejecutar `create-bootstrap-secrets.sh`.

Prometheus:

```bash
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-stack-prometheus 9090:9090
```

Abre http://localhost:9090.

El stack incluye Prometheus Operator, Prometheus, Alertmanager, Grafana, kube-state-metrics y node-exporter. Se deshabilitan los scrape targets de componentes de control plane que no suelen estar expuestos como servicios estándar en K3s (etcd, scheduler, controller-manager y kube-proxy).

## 9. Operación diaria

Ver estado:

```bash
flux get all -A
kubectl get pods -A
kubectl get pvc -A
```

Forzar reconciliación:

```bash
flux reconcile source git flux-system -n flux-system
flux reconcile kustomization flux-system -n flux-system --with-source
```

Ver logs de Immich:

```bash
kubectl logs -n immich deploy/immich-server
kubectl logs -n immich deploy/immich-machine-learning
```

Ver servicios y endpoints:

```bash
kubectl get svc,endpoints -n immich
kubectl get ingress -n immich
```

Los nombres de Deployment pueden variar según la versión del chart. Si un `kubectl logs deploy/...` no encuentra el nombre, consulta `kubectl get deploy -n immich`.

## 10. Personalización antes de desplegar

Revisa estos archivos:

| Archivo | Qué puedes cambiar |
|---|---|
| `infrastructure/k3s/config.yaml.example` | Configuración base de K3s; el script la instala en `/etc/rancher/k3s/config.yaml` |
| `apps/immich/database/cluster.yaml` | CPU/RAM, tamaño de PostgreSQL y StorageClass |
| `apps/immich/database/library-pvc.yaml` | Capacidad de biblioteca multimedia |
| `apps/immich/app/helmrelease.yaml` | Versiones del chart y de Immich, Valkey y variables de DB |
| `apps/monitoring/helmrelease.yaml` | Retención y almacenamiento de Prometheus/Grafana |
| `apps/immich/access/ingress.yaml` | Hostname interno de Tailscale |

No cambies la versión mayor de Immich sin leer sus notas de migración y preparar un backup de PostgreSQL y de la biblioteca. En este proyecto los backups quedan para una fase posterior; por eso no recomendamos almacenar todavía la única copia de fotos importantes.

## 11. Solución de problemas frecuentes

### `HelmRelease` no encuentra el Secret

Comprueba que los secretos existen en el namespace correcto:

```bash
kubectl get secret -n tailscale tailscale-oauth
kubectl get secret -n monitoring grafana-admin
```

Los `valuesFrom` de HelmRelease buscan el Secret en el namespace del HelmRelease.

### Immich no inicia por PostgreSQL

```bash
kubectl get clusters.postgresql.cnpg.io -n immich
kubectl describe cluster immich-database -n immich
kubectl get pods -n immich
kubectl logs -n immich immich-database-1
```

El nombre del pod de PostgreSQL lo determina CloudNativePG; consulta `kubectl get pods -n immich`.

### Tailscale no publica Immich

```bash
kubectl get pods -n tailscale
kubectl get ingress -n immich
kubectl describe ingress immich -n immich
kubectl logs -n tailscale deploy/operator
```

Revisa tags, scopes del OAuth client, HTTPS en el tailnet y el nombre DNS asignado.

### PVC en `Pending`

```bash
kubectl describe pvc -n immich immich-library
kubectl get storageclass
kubectl get pods -n kube-system | grep local-path
```

Comprueba que `local-path` existe y que el provisionador de K3s está sano.

### Flux no sincroniza

```bash
flux get sources git -A
flux get kustomizations -A
kubectl logs -n flux-system deploy/source-controller
kubectl logs -n flux-system deploy/kustomize-controller
```

## Referencias oficiales

- K3s: https://docs.k3s.io/quick-start
- K3s storage: https://docs.k3s.io/add-ons/storage
- Flux bootstrap: https://fluxcd.io/flux/installation/bootstrap/github/
- Tailscale Operator: https://tailscale.com/docs/kubernetes-operator
- Immich Kubernetes: https://docs.immich.app/install/kubernetes/
- Immich Helm chart: https://github.com/immich-app/immich-charts
- CloudNativePG: https://cloudnative-pg.io/
- kube-prometheus-stack: https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack
