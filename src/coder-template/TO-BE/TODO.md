# TODO List — Coder + Claude RBAC Platform

## Estado General

| # | Fase | Estado |
|---|------|--------|
| 1 | Brainstorming + Diseño | ✅ done |
| 2 | Spec consolidado | ✅ done |
| 3 | Plan de implementación | ✅ done |
| 4 | Implementación (8 tasks) | ✅ done |
| 5 | Roles y Skills (Architect, Developer, QA; + Platform y Cyber 2026-10-15) | ✅ done |
| 6 | Gestión de Secretos (ESO + OAuth) | ✅ done |
| 7 | Jira OAuth automático | ✅ done |
| 8 | Análisis specs Waitly | ✅ done |
| 9 | Rediseño spec template (contrato comportamental) | ✅ done |

---

## Documentación

| # | Archivo | Contenido | Estado |
|---|---------|-----------|--------|
| 0 | 00-decisiones.md | Registro de decisiones | ✅ |
| 1 | 01-arquitectura-general.md | Diagrama y componentes | ✅ |
| 2 | 02-rbac-mapping-roles.md | RBAC, GitHub Teams, matriz | ✅ |
| 3 | 03-template-terraform.md | Template HCL completo | ✅ |
| 4 | 04-skills-mcp-por-rol.md | Skills y MCP configs | ✅ 5 roles (platform y cyber sin skills todavía) |
| 5 | 05-network-isolation.md | Cilium policies | ✅ |
| 6 | 06-imagen-base-docker.md | Dockerfile multi-stage | ✅ |
| 7 | 07-observabilidad-audit.md | Prometheus + Grafana | ✅ |
| 8 | 08-deployment-operacion.md | Helm, rollout, Day-2 | ✅ |
| 9 | 09-gestion-secretos.md | ESO + per-user tokens | ✅ |
| 10 | 10-jira-oauth-automatico.md | OAuth 3LO para Jira | ✅ |
| 11 | 11-analisis-specs-waitly.md | Análisis de specs Waitly | ✅ |
| 12 | 12-roles-y-skills.md | roles, skills, flujo specs | ✅ |
| 13 | 13-authz-a-escala.md | AuthZ a escala: PAT → GitHub App → IdP group sync | ✅ NEW |

---

## Decisiones clave desde el inicio

1. Cloud: Agnostic
2. IdP: GitHub OAuth
3. Mapping: GitHub Teams → Coder Roles (automático)
4. Roles: Architect (PM/PO) + Developer + Platform + QA + Cyber (5 roles desde 2026-10-15; el piloto empezó con 3)
5. LLM: Claude ahora, model-agnostic
6. Interfaz: code-server (con extensión de Claude) + Claude Code CLI + Copilot CLI (3 apps)
7. Template: Híbrido (base + overlay por rol)
8. Network: Cilium FQDN isolation
9. Secretos: External Secrets Operator, per-user, OAuth para Jira
10. Specs: Un solo spec unificado (contrato de comportamiento), 3 consumidores
11. Skills: Arquitectura SKILL.md + README.md + references/

---

## Progreso de implementación (piloto en VM) — actualizado 2026-10-15

| Área | Estado | Notas / docs |
|------|--------|--------------|
| RBAC por GitHub Team (5 roles + sub-teams) | ✅ E2E | GitHub App `qintess-latam-rbac-resolver` = AuthZ. `docs/rbac-setup.md`, `docs/RUNBOOK-github-app.md` |
| Plantillas por rol | ✅ | 5 plantillas `qintess-<rol>-template`, acceso validado por team en cada build, binarios por rol. `docs/RUNBOOK-plantillas-por-rol.md` |
| Prioridad de rol (plantilla genérica) | ✅ | Least-privilege (qa<developer<cyber<platform<architect). `02-rbac-mapping-roles.md` |
| Persistencia (reboot) | ✅ | systemd+linger + `unless-stopped`; BD en PostgreSQL Docker con backup diario. `docs/RUNBOOK-vm-portainer-red.md` |
| Overlays por rol | ✅ E2E | 5 roles, para Claude **y** Copilot; repos `qintess-platform-agents-overlays` + `-skills` → `deploy/vm/sync-agent-overlays.sh` |
| MCP **github** | ✅ | external-auth OAuth per-usuario (solo repos del user) |
| MCP **atlassian** (Jira + Confluence) | ✅ | OAuth 3LO per-usuario con token fresco (`coder external-auth access-token`) |
| MCP **playwright** | ✅ | rol qa; startup instala Node 20 + chromium |
| MCP sonar / SAST | ⏳ fase DevSecOps | retirado de la plantilla y los overlays; el rol cyber escanea con semgrep/gitleaks/trivy. Evaluar Sonar en CI vs MCP. |
| GitHub Copilot | ✅ | seats por team, modelos Claude, CLI + MCP habilitados. `RUNBOOK-vm-qintess-latam.md` Fase 2d |
| Panel del workspace + gasto de IA | ✅ | Claude/extensión/GitHub/Atlassian/herramientas + Estimated AI spend/month |
| Template prod-oidc (N3 OIDC) | 🟨 referencia | sin mantenimiento; bloqueado por IdP real + Coder Premium. `13-authz-a-escala.md` |

Runbooks fuera de TO-BE: `docs/RUNBOOK-vm-deploy.md`, `docs/RUNBOOK-vm-qintess-latam.md`,
`docs/RUNBOOK-plantillas-por-rol.md`, `docs/RUNBOOK-vm-portainer-red.md`,
`docs/RUNBOOK-https-caddy.md`, `docs/RUNBOOK-github-app.md`, `docs/RUNBOOK-prod-oidc.md`,
`docs/RUNBOOK-llm-backend.md` y **`docs/external-auth-oauth-pattern.md`** (patrón
reutilizable MCP per-usuario vía external-auth: GitHub + Atlassian).
