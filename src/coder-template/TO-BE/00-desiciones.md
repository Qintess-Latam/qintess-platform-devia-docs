# Decisiones de Diseño — Coder + Claude RBAC Platform

## Fecha: 2026-07-07

## Objetivo

Crear una plataforma Coder donde operadores con diferentes roles (PM, QA, Developer, DevOps, Cybersecurity) puedan usar Claude con recursos habilitados exclusivamente por rol (sub-agentes, Skills, MCP, etc.) para sus tareas diarias dentro del dominio de la empresa.

---

## Decisiones Tomadas

| # | Decisión | Elección | Alternativas Descartadas |
|---|----------|----------|--------------------------|
| 1 | Cloud Provider | Agnostic (cualquier cloud en el futuro) | AWS-only, Azure-only |
| 2 | Identity Provider | GitHub OAuth | Azure AD, Okta, Keycloak |
| 3 | Rol Mapping | GitHub Teams → Coder Roles | Claims custom, mapping manual, detección por repos |
| 4 | Roles | Architect + Developer + QA (3 roles) → **ampliado a 5** (+ Platform, Cyber) con una plantilla por rol (2026-10-15) | Solo 2 MVP |
| 5 | LLM | Claude ahora, diseño model-agnostic | Claude-only, multi-model |
| 6 | Interfaz Operador | code-server (VS Code web) + Claude Code CLI | Solo CLI, solo IDE desktop remoto |
| 7 | Template Strategy | Híbrido: template base + overlay por rol | Templates separados, template único dinámico |
| 8 | Network Isolation | Sí — egress restringido por rol | Sin isolation, solo egress |
| 9 | Alcance Primera Entrega | Piloto para squad completo (15-30 personas) | POC 5-10, producción org-wide |
| 10 | Enfoque Arquitectónico | A: Coder Nativo + CLAUDE.md por Rol | B: Sidecar dinámico, C: Orchestrator centralizado |
| 11 | Secretos MCP | Per-user via External Secrets Operator + OAuth | Shared per-rol, manual PATs |
| 12 | Jira Auth | OAuth 2.0 3LO (1 click por usuario, rotación auto) | Service account compartido, API tokens manuales |
| 13 | Specs | Un spec unificado (contrato de comportamiento) | Specs separados por rol (QA spec + Dev spec) |
| 14 | Skill Architecture | SKILL.md + README.md + references/ (igual que ElevenLabs) | Skills como archivos sueltos markdown |
| 15 | Workspace provisión | Auto-create via CronJob al primer login | Manual "Create Workspace" click |
| 16 | Onboarding tokens | Automático (GitHub App + onboard-controller) | Manual por admin |
| 17 | Credencial AuthZ del servidor (resolución de rol) | GitHub App de la org (installation token auto-rotado) — Camino A / N2 | PAT personal (homelab), OIDC group sync N3 (futuro, requiere cambiar #2) |
| 18 | Aplicación de cambios de rol / revocación | **Build-time con política asimétrica**: grant (promoción) en el próximo rebuild; deny (degradación/offboarding) inmediato vía `coder stop`/`delete` | Resolución dinámica en vivo (Enfoque B, ya descartado), relabel en caliente |

---

## Decisión #18 — Aplicación de cambios de rol (build-time, asimétrica)

**Contexto.** El rol se resuelve en **tiempo de build** (`resolve-role.sh` → `data.external.user_role` → `local.role` → label `coder.com/role` + overlay en el `startup_script`). Un contenedor ya creado **conserva su rol** aunque cambie la membresía de teams en GitHub; solo se re-resuelve al reconstruir (`coder restart`/`update`). Un reboot con `unless-stopped` (Nivel 6) **no** re-resuelve: revive el mismo contenedor. Esto es consecuencia directa de haber elegido el Enfoque A (overlay estático) y descartado el Enfoque B (governance dinámico en vivo) por complejidad, latencia y superficie de ataque.

**Problema.** Sin acción, un cambio de rol no surte efecto hasta el próximo rebuild. Para promociones es inofensivo; para **degradaciones y offboarding es un hallazgo de auditoría** (el usuario conserva permisos revocados).

**Decisión.** Tratar los dos sentidos del cambio de forma **asimétrica**:

| Cambio | Riesgo | Aplicación |
|---|---|---|
| **Promoción** (p.ej. qa → architect) | Bajo (solo "no ve" capacidades nuevas) | En el **próximo rebuild natural**. No se fuerza nada. |
| **Degradación / offboarding** (architect → qa, salida de la org) | **Alto** (conserva permisos que ya no le tocan) | **Inmediato y fail-closed**: `coder stop`/`delete` del workspace — **no** relabel en caliente. |

**Racional.** Lo único que exige inmediatez es *quitar* acceso, y quitar acceso se resuelve mejor **terminando el workspace** que reetiquetándolo. Reintroducir resolución en vivo (Enfoque B) para cubrir esto no compensa.

**Estado por nivel.**
- **Piloto actual (VM, ~5 usuarios):** mitigación **operativa por runbook**: quitar a la persona del team y borrar su workspace. Desde 2026-10-15 las **plantillas por rol** validan el team en **cada build** (`resolve-role.sh` con `required_role`), así que quien sale del team no puede volver a arrancar/reconstruir el workspace de ese rol. El reconciliador periódico por labels (`reconcile-roles.sh`) se retiró: con plantillas por rol comparaba contra el rol automático y daba falsos positivos.
- **Producción / multi-usuario:** automatizar vía **webhook de la org GitHub** (evento `membership`/`organization`) → API de Coder: removido de la org → `stop`+`delete`; cambio de team → `restart`. Reutiliza la GitHub App de resolución de rol (`qintess-latam-rbac-resolver`; solo amplía el webhook, no la credencial).
- **N3 OIDC (`prod-oidc`):** ⚠️ el rol vendría del claim de grupos al login, pero un contenedor de larga vida **sigue conservando el rol viejo hasta reconstruirse** → la regla "deny = terminar workspace" (disparada por SCIM/deprovisioning del IdP) **sigue siendo necesaria**. OIDC no elimina esta decisión.

## Enfoques Evaluados

### Enfoque A: Coder Nativo + CLAUDE.md por Rol ✅ (Elegido)

Coder OSS en K8s
GitHub OAuth → team membership → var.role
Terraform template base + overlay por rol
CLAUDE.md, mcp-config.json, skills/ montados según rol
NetworkPolicies de K8s por label de rol

**Pros:** Usa framework existente. Mínimo código custom. Coder maneja lifecycle.
**Contras:** Requiere K8s. Overlay estático.

### Enfoque B: Coder + Sidecar de Governance Dinámico ❌

Sidecar consulta GitHub Teams en tiempo real
Inyecta skills/MCP dinámicamente sin restart
Proxy para tool calls con OPA

**Pros:** Cambios en tiempo real. Governance granular.
**Contras:** Complejidad operativa. Latencia. Mayor superficie de ataque.

### Enfoque C: Coder + ai-agents-framework Orchestrator ❌

Coder = compute + IDE
Orchestrator central resuelve rol → permisos
Claude se conecta al orchestrator vía MCP

**Pros:** Máxima reutilización del framework. Control centralizado.
**Contras:** SPOF. Complejidad de networking. Latencia.