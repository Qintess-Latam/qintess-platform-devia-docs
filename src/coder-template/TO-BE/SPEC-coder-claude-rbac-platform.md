# Spec: Coder + Claude RBAC Platform

**Fecha:** 2026-07-07  
**Autor:** Juan Parra / Copilot  
**Estado:** Draft — pendiente revisión  
**Alcance:** Piloto para squad de 15-30 personas (Developer + QA)

---

## 1. Problema

Los operadores del equipo DevSecOps necesitan entornos AI-augmented con Claude que:
Estén gobernados por rol (cada persona solo ve lo que le corresponde)
Tengan network isolation (no pueden acceder a servicios no autorizados)
Sean reproducibles y efímeros (no "works on my machine")
Incluyan IDE web + CLI para máxima flexibilidad
Sean auditables (quién hizo qué, cuántos tokens, qué tools usó)

## 2. Solución

Plataforma basada en **Coder OSS** desplegada en Kubernetes que:
1. Autentica usuarios via GitHub OAuth
2. Resuelve automáticamente el rol por GitHub Team membership
3. Provisiona workspaces con overlay específico del rol (CLAUDE.md, skills, MCP, network)
4. Ofrece code-server (VS Code web) + Claude Code CLI pre-configurados
5. Aplica NetworkPolicies (Cilium FQDN) por rol
6. Registra audit trail completo de uso

## 3. Arquitectura

### 3.1 Componentes

Operador (Browser) → Coder Control Plane (Auth + Templates + Lifecycle)
                          ↓
                   Workspace Pod (por operador)
                   ├── code-server (VS Code Web)
                   ├── Claude Code CLI
                   ├── /home/coder/.claude/ (overlay del rol)
                   └── NetworkPolicy (Cilium FQDN)

### 3.2 Flujo de Provisión

1. GitHub OAuth login → Coder extrae team membership
2. resolve-role.sh determina rol por prioridad: developer > qa > product
3. Terraform template provisiona pod con overlay correcto via ConfigMap
4. NetworkPolicy aplicada por label `coder.com/role`
5. Workspace listo con IDE + Claude pre-configurados para el rol

### 3.3 Template Strategy

**Base:** imagen Docker común (code-server, Claude Code, git, gh, Node, Python, Docker)
**Overlay:** ConfigMap por rol montado en /home/coder/.claude/
  - CLAUDE.md — system prompt con skills, governance gates y prohibiciones
  - mcp-config.json — MCP servers permitidos
  - skills/ — directorio de skills habilitados

## 4. RBAC

### 4.1 Mapping

| GitHub Team | Coder Role | Resolución |
|-------------|-----------|------------|
| platform-developers | developer | Automática (prioridad 1) |
| qa-engineers | qa | Automática (prioridad 2) |
| product-managers | product | Futuro |

### 4.2 Conflictos Multi-Team

Regla: asignar el rol más permisivo automáticamente. Sin selección manual.

### 4.3 Matriz de Permisos

| Recurso | Developer | QA |
|---------|-----------|-----|
| Skills | code-review-security, feature-implementation, jira-dev-sync | bdd-test-generation, coverage-gap-analysis, unit-test-generation |
| MCP: GitHub | Read/Write | Read-only |
| MCP: Jira | Read + transitions | Read + create bugs |
| MCP: SonarCloud | ✅ | ❌ |
| MCP: Playwright | ❌ | ✅ |
| Egress: npm/PyPI/Docker | ✅ | ❌ |
| Egress: Selenium Grid | ❌ | ✅ |
| Governance | BDD-first, scope limits | Coverage threshold, test quality |

## 5. Network Isolation

**CNI:** Cilium (FQDN-based egress filtering)
**Default deny:** todo tráfico no explícito es bloqueado
**Inter-pod blocked:** dev no habla con qa, qa no habla con dev
**Ingress:** solo Coder control plane
**Egress:** solo dominios listados por rol

## 6. Imagen Base Docker

Ubuntu 24.04, multi-stage build (~450 MB)
Incluye: code-server, Claude Code CLI, git, gh, Node.js, Python 3, Docker CLI
Non-root user (coder, UID 1000)
CI/CD: GitHub Actions → ghcr.io/qintess/coder-workspace:latest

## 7. Observabilidad

| Capa | Qué Monitorea |
|------|---------------|
| Coder Audit | Logins, workspace lifecycle, template changes |
| Claude Usage | Tokens, tool calls, skills, MCP calls, duración |
| K8s Metrics | CPU/RAM, egress bytes, pod events, policy denies |
| Governance | Gate violations, blocked egress, unauthorized access |

**Stack:** Prometheus + Grafana + Loki  
**KPIs:** adoption rate, tokens/user/day, governance violations → 0, cost/user/day

## 8. Deployment

### Pre-requisitos
K8s v1.28+ con Cilium, Helm v3, Terraform v1.5+
GitHub OAuth App configurada
DNS + TLS para coder.banco-internal.com

### Rollout (8 semanas)
1. Deploy Coder + imagen base
2. GitHub OAuth + role resolution
3. Overlays + NetworkPolicies
4. 5 early adopters
5-6. Feedback y ajustes
7. Rollout squad completo
8. Review métricas

### Operación
Auto-stop workspaces idle (2h)
Cluster autoscaler para compute
External Secrets Operator para rotación de credenciales
Imagen rebuild mensual

## 9. Decisiones de No-Hacer (YAGNI)

❌ Sidecar de governance dinámico (complejidad innecesaria para MVP)
❌ Orchestrator centralizado (SPOF, latencia)
❌ Multi-cloud simultáneo (diseñar agnostic, implementar en uno)
❌ Más de 2 roles en MVP (developer + qa son suficientes para validar)
❌ Custom IDE extensions (usar Claude Code CLI estándar)

## 10. Riesgos y Mitigaciones

| Riesgo | Impacto | Mitigación |
|--------|---------|-----------|
| GitHub OAuth down | No login | Fallback: admin local de emergencia |
| Claude API quota | Degraded AI | Token budget alerts + graceful degradation |
| Overlay desactualizado | Wrong permissions | CI/CD: rebuild ConfigMaps on merge to main |
| Cilium misconfiguration | Egress leak | Integration tests + periodic policy audit |
| Cost overrun | Budget | Auto-stop + compute alerts en Grafana |

---

## Apéndice: Archivos del Diseño

| Archivo | Contenido |
|---------|-----------|
| 00-decisiones.md | Registro de decisiones |
| 01-arquitectura-general.md | Diagrama y componentes |
| 02-rbac-mapping-roles.md | RBAC, Terraform, matriz de permisos |
| 03-template-terraform.md | Template HCL completo |
| 04-skills-mcp-por-rol.md | CLAUDE.md y MCP configs |
| 05-network-isolation.md | Cilium policies |
| 06-imagen-base-docker.md | Dockerfile multi-stage |
| 07-observabilidad-audit.md | Stack de monitoreo |
| 08-deployment-operacion.md | Helm, rollout, Day-2 ops |