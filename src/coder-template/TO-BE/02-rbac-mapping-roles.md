# Sección 2: RBAC y Mapping de Roles

## Estado: ✅ Aprobada · implementada en el piloto (actualizada 2026-10-15)

## Modelo de Roles

Org de GitHub `Qintess-Latam` — cada rol es un **team padre** con sub-teams
(`-senior-dev`, `-repo-admin`, `-release-eng`, `-appsec`) que también otorgan el rol:

```
Qintess-Latam
├── qintess-architect   →  rol architect  (Producto: PM/PO)   →  qintess-architecture-template
├── qintess-developers  →  rol developer                       →  qintess-developer-template
├── qintess-platform    →  rol platform   (infra / cloud)      →  qintess-platform-template
├── qintess-qa          →  rol qa                              →  qintess-qa-template
└── qintess-cyber       →  rol cyber      (AppSec)             →  qintess-cyber-template
```

## Una plantilla por rol (2026-10-15)

El usuario **elige la plantilla de su rol**; el rol lo fija la plantilla
(`template_role`) y `resolve-role.sh` (`required_role`) **valida en cada build**
que el usuario pertenece al team del rol (padre o sub-team). Si no, el build falla
con un mensaje claro. Coder OSS no tiene ACL de plantillas por grupo: esta
validación es la barrera de acceso. Un usuario con varios roles puede tener un
workspace de cada uno.

## Plantilla genérica (rol automático) — LEAST-PRIVILEGE

La plantilla genérica (`mvp-embedded`, obsoleta) no fija el rol: lo resuelve por
team y, en multi-team, gana el **MENOS permisivo** (anti-escalada, deny-by-default
para banca). Orden de selección (primer match):
**qa → developer → cyber → platform → architect**. Fail-closed: sin team válido →
`unknown` (sin overlay).

## Norma: ONE-ROLE-PER-USER (2026-07-09)

Con la plantilla genérica, cada persona debía pertenecer a **un solo** team de rol.
Con plantillas por rol esa norma se relaja: el multi-team es válido y cada
workspace tiene un único rol explícito.

## Flujo de Resolución del Rol

```
GitHub OAuth login ─▶ usuario elige qintess-<rol>-template
                         │
   Terraform (provisioner)  data.external → resolve-role.sh
                         │   {github_username, github_org, required_role}
                         ▼
   GitHub App (installation token) → orgs/<org>/teams/<team>[-sub]/memberships/<user>
                         │
              miembro ───┴─── no miembro → el build FALLA (mensaje al usuario)
                 │
   local.role = rol de la plantilla → label coder.com/role
                 │                    + overlay /opt/overlays/<rol> → ~/.claude, ~/.copilot
                 │                    + role-tools.sh <rol> (binarios)
                 ▼
          workspace del rol
```

## Implementación en Coder Template (Terraform)

```hcl
variable "template_role" { default = "" }   # architect | developer | platform | qa | cyber | "" (genérica)

data "external" "user_role" {
  program = ["bash", "${path.module}/scripts/resolve-role.sh"]
  query = {
    github_username = data.coder_workspace_owner.me.name
    github_org      = var.github_org                     # Qintess-Latam
    role_override   = var.github_org == "" ? var.default_role : ""
    required_role   = var.template_role                  # plantilla por rol
  }
}

locals {
  role = data.external.user_role.result.role
}
```

Fuente real: `templates/mvp-embedded/main.tf` y `scripts/resolve-role.sh`
(lookup con `curl` + token de la GitHub App; `gh` como fallback). Los overlays
viven en el repo `qintess-platform-agents-overlays` (`<rol>/CLAUDE.md`,
`mcp-config.json`, `settings.json`) y los skills en `qintess-platform-agents-skills`
(`skills/<rol>/`); el host los combina con `deploy/vm/sync-agent-overlays.sh`.

**Excepción del plan de importación:** `coder templates push` hace un plan con un
dueño ficticio `default`; `resolve-role.sh` lo deja pasar sin chequeo.

## Matriz de Permisos por Rol

| Recurso | Architecture (PM/PO) | Developer | Platform | QA | Cyber |
|---------|----------------------|-----------|----------|-----|-------|
| **Skills** | spec-from-jira, architecture-review | spec-implementer, claude-md-updater, code-review-security, frontend/UX | (por definir) | bdd-test-generation, coverage-gap-analysis, unit-test-generation, mutation-testing | (por definir) |
| **Binarios** | pandoc, PlantUML, Mermaid, yq | Java 21 + Maven, .NET, Python + uv | Terraform, kubectl, Helm, AWS/Azure CLI, yq | Playwright, k6, Newman, Allure | Trivy, Gitleaks, Semgrep, ZAP |
| **MCP Servers** | GitHub, Atlassian | GitHub, Atlassian | GitHub, Atlassian | GitHub, Atlassian, Playwright | GitHub, Atlassian |
| **Repos accesibles** | Los del usuario (token propio) | Los del usuario | Los del usuario | Los del usuario | Los del usuario |
| **Permisos del agente** (`settings.json`) | sin apply/deploy | `.tf`/helm/k8s en *ask* | plan/lint/diff; apply/destroy/install en *deny* | `src/` en *deny* | escaneo estático; `zap`/`curl` en *ask*; nmap/sqlmap/hydra en *deny* |
| **Egress network (TO-BE)** | GitHub, Atlassian, Anthropic | + npm, PyPI, Docker Hub | + APIs de cloud | + Selenium Grid | + feeds de vulnerabilidades |
| **IDE extensions** | Claude Code (oficial) | Claude Code (oficial) | Claude Code (oficial) | Claude Code (oficial) | Claude Code (oficial) |
| **Governance gates** | Spec completo | BDD-first, scope limits | plan antes de apply, prod vía pipeline | Coverage threshold, sin PII | DAST solo autorizado |
