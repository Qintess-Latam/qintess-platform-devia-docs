# Sección 4: Skills y MCP por Rol

## Estado: ✅ Actualizado (5 roles; platform y cyber con overlay pero sin skills propios todavía)

## Resumen de Roles

| Rol | GitHub Team | Prioridad | Función principal |
|-----|-------------|-----------|-------------------|
| Architect | tech-leads | 1 (más alta) | Lee Jira → genera specs |
| Developer | platform-developers | 2 | Implementa specs con TDD |
| QA | qa-engineers | 3 | Genera BDD tests, verifica cobertura |

## Skills por Rol

### Architect

skills/architect/                         (repo qintess-platform-agents-skills)
├── spec-from-jira/          ← Lee Jira story → genera spec técnico
│   ├── SKILL.md
│   ├── README.md
│   └── references/
│       ├── spec-template.md
│       └── jira-to-spec-mapping.md
└── architecture-review/     ← Revisa specs/código contra principios
    ├── SKILL.md
    └── README.md

### Developer

skills/developer/                         (repo qintess-platform-agents-skills)
├── spec-writer/             ← Genera specs manuales (sin Jira)
│   ├── SKILL.md
│   ├── README.md
│   └── references/
│       ├── spec-template.md
│       ├── spec-examples.md
│       └── spec-antipatterns.md
├── spec-implementer/        ← Implementa un spec con TDD
│   ├── SKILL.md
│   ├── README.md
│   └── references/
│       └── tdd-flow.md
└── claude-md-updater/       ← Actualiza CLAUDE.md post-implementación
    ├── SKILL.md
    ├── README.md
    └── references/
        └── claude-md-structure.md

### QA

skills/qa/                         (repo qintess-platform-agents-skills)
├── bdd-test-generation/     ← Genera .feature desde spec/story
│   ├── SKILL.md
│   ├── README.md
│   └── references/
│       └── gherkin-standards.md
├── coverage-gap-analysis/   ← Identifica gaps de cobertura
│   ├── SKILL.md
│   ├── README.md
│   └── references/
│       └── coverage-priorities.md
└── unit-test-generation/    ← Genera unit tests
    ├── SKILL.md
    ├── README.md
    └── references/
        └── test-design-patterns.md

## MCP por Rol

> **Estado de implementación (piloto, actualizado 2026-10-15):** los MCP se cargan solos al
> entrar, en Claude Code **y** en Copilot CLI (overlay del rol → `~/workspace/.mcp.json`,
> `~/.copilot/mcp-config.json` + `enableAllProjectMcpServers`). Hay overlays para los
> **5 roles** (architect, developer, platform, qa, cyber) en el repo
> `qintess-platform-agents-overlays`.
> Servers y auth REALES:
>
> | Server | Paquete real | Auth | Estado |
> |--------|--------------|------|--------|
> | **github** | `@modelcontextprotocol/server-github` | **external-auth OAuth per-usuario** (`${GITHUB_TOKEN}`) → solo repos del usuario | ✅ conecta |
> | **atlassian** (Jira+Confluence) | `uvx mcp-atlassian` (modo OAuth/BYOT) | **OAuth PER-USUARIO** (external-auth `atlassian`; `ATLASSIAN_OAUTH_*`) → cada user ve solo su Jira/Confluence | ✅ conecta con el token del usuario |
> | **sonarcloud** | — | — | ⏳ retirado de los overlays hasta tener cuenta (el rol cyber usa semgrep/gitleaks/trivy en el workspace) |
> | **playwright** | `@playwright/mcp@latest --headless --isolated` | browser local (sin grid) | ✅ conecta (requiere Node 20 + chromium, ambos en el startup) |
>
> Nota: `jira` y `confluence` separados (OAuth2) del diseño original se
> consolidaron en **un solo** server `atlassian` (mcp-atlassian cubre ambos).
> El auth "OAuth 2.0" de las tablas de abajo ya está implementado: OAuth per-usuario
> vía external-auth Atlassian, con token fresco por `coder external-auth access-token`
> (ver `09-gestion-secretos.md`).

### Architect (mcp-config.json)

| MCP Server | Permisos | Uso |
|-----------|---------|-----|
| GitHub | Read/Write | Leer repos, crear PRs con specs |
| Jira | Read (OAuth 2.0) | Leer stories para generar specs |
| Confluence | Read/Write (OAuth 2.0) | Documentar arquitectura |

### Developer (mcp-config.json)

| MCP Server | Permisos | Uso |
|-----------|---------|-----|
| GitHub | Read/Write | Push código, crear PRs |
| Jira | Read + transitions (OAuth 2.0) | Mover stories, comentar |
| SonarCloud | Read | Ver métricas de calidad |

### QA (mcp-config.json)

| MCP Server | Permisos | Uso |
|-----------|---------|-----|
| GitHub | Read-only | Leer código para testear |
| Jira | Read + create bugs (OAuth 2.0) | Crear bugs, ver stories |
| Playwright | Execute | Correr E2E tests |

## Governance Gates por Rol

| Gate | Architect | Developer | QA |
|------|:---------:|:---------:|:--:|
| Spec completo (no placeholders) | ✅ | — | — |
| BDD-first (.feature antes de código) | — | ✅ | ✅ (crea el .feature) |
| Scope limits (15 files, 500 lines) | — | ✅ | — |
| Coverage threshold (80%) | — | — | ✅ |
| Single story in progress | — | ✅ | — |
| No PII en tests | — | — | ✅ |