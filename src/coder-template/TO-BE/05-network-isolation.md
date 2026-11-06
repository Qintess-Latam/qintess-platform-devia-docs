# Sección 5: Network Isolation

## Estado: ✅ Aprobada

## Modelo de Segmentación

                    ┌─────────────────────────────┐
                    │      INTERNET / APIs         │
                    └──────────────┬──────────────┘
                                   │
                    ┌──────────────▼──────────────┐
                    │   Cilium / Calico (CNI)      │
                    │   FQDN-based Egress Policies │
                    └──────────────┬──────────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              │                    │                    │
    ┌─────────▼─────────┐ ┌───────▼────────┐ ┌────────▼────────┐
    │  developer pods    │ │   qa pods      │ │ coder control   │
    │  label: role=dev   │ │  label: role=qa│ │ plane           │
    └───────────────────┘ └────────────────┘ └─────────────────┘
    
    ❌ Inter-pod blocked (dev no habla con qa, qa no habla con dev)

## Reglas de Aislamiento

| Regla | Descripción |
|-------|-------------|
| No inter-pod | Workspaces de diferentes roles NO se comunican |
| No ingress externo | Solo Coder control plane inicia conexión al pod |
| DNS restringido | Solo kube-dns del cluster |
| Egress FQDN-only | Solo dominios explícitamente permitidos por rol |
| Default deny | Todo tráfico no permitido es bloqueado |

## Dominios Permitidos por Rol

| Dominio | Developer | QA |
|---------|-----------|-----|
| api.github.com | ✅ | ✅ |
| api.anthropic.com | ✅ | ✅ |
| registry.npmjs.org | ✅ | ❌ |
| pypi.org | ✅ | ❌ |
| docker.io / ghcr.io | ✅ | ❌ |
| *.sonarcloud.io | ✅ | ❌ |
| *.atlassian.net | ❌ | ✅ |
| selenium-grid (internal) | ❌ | ✅ |

## Tecnología: Cilium CiliumNetworkPolicy (FQDN filtering)

Se usa Cilium como CNI para poder filtrar por FQDN en lugar de IPs estáticas.