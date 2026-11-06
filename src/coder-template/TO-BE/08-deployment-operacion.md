# Sección 8: Deployment y Operación

## Estado: ✅ Aprobada

## Pre-requisitos

| Componente | Requisito |
|-----------|-----------|
| Kubernetes | v1.28+ con Cilium CNI |
| Helm | v3.x |
| Terraform | v1.5+ |
| GitHub Org | qintess con Teams |
| DNS | coder.banco-internal.com |
| TLS | Cert-manager + Let's Encrypt |
| Storage | PVC para workspaces |
| Secrets | External Secrets Operator |

## Despliegue

bash
helm repo add coder-v2 https://helm.coder.com/v2
helm install coder coder-v2/coder --namespace coder --values values.yaml

coder templates push workspace-rbac --directory ./coder-templates/ --yes

# Overlays: carpeta combinada que genera deploy/vm/sync-agent-overlays.sh a partir de los
# repos qintess-platform-agents-overlays + qintess-platform-agents-skills (un ConfigMap por rol)
for r in architect developer platform qa cyber; do
  kubectl create configmap overlay-$r --from-file=agents-overlays-synced/$r/ -n coder-workspaces
done

## Operación Day-2

| Tarea | Frecuencia |
|-------|-----------|
| Actualizar imagen | Mensual |
| Agregar nuevo rol | Bajo demanda |
| Rotar secrets | 90 días |
| Scale up/down | Automático (cluster autoscaler) |
| Backup PostgreSQL | Diario |
| Audit review | Semanal |

## Auto-stop: 2 horas de inactividad

## Rollout Plan (8 semanas)

| Semana | Actividad |
|--------|-----------|
| 1 | Deploy Coder + imagen base |
| 2 | GitHub OAuth + role resolution |
| 3 | Overlays + NetworkPolicies |
| 4 | 5 early adopters (3 dev + 2 QA) |
| 5-6 | Feedback y ajustes |
| 7 | Rollout squad completo (15-30) |
| 8 | Review métricas y KPIs |