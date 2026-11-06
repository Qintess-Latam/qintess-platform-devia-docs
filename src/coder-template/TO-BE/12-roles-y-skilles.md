# Sección 12: Roles y Skills

## Estado: ✅ Implementado

## Roles Disponibles

| Rol | GitHub Team | Función | Skills |
|-----|-------------|---------|--------|
| **Architect** | tech-leads | Lee Jira stories → genera specs técnicos | spec-from-jira, architecture-review |
| **Developer** | platform-developers | Implementa specs con TDD | spec-writer, spec-implementer, claude-md-updater |
| **QA** | qa-engineers | Genera BDD tests, verifica cobertura | bdd-test-generation, coverage-gap-analysis, unit-test-generation |

## Prioridad de resolución (multi-team) — least-privilege

Con plantillas por rol el rol lo fija la plantilla (validado contra el team). En la plantilla genérica: qa < developer < cyber < platform < architect (gana el MENOS permisivo; ver `02-rbac-mapping-roles.md`)

## Arquitectura de Skills (todas siguen el mismo patrón)

skill-name/
├── SKILL.md          ← Instrucciones del agente (frontmatter YAML + role + operating instructions)
├── README.md         ← Documentación para humanos (invocación, salida esperada)
└── references/       ← Material de referencia (templates, standards, examples)

Cada SKILL.md tiene:
**Frontmatter YAML**: name, description, metadata (type, tier, domain, owner)
**Role definition**: quién eres, qué haces
**Hardening & guardrails**: qué NO puedes hacer
**Mission**: criterios de completitud
**Operating instructions**: pasos ordenados
**Pre-flight checklist**: verificación antes de actuar
**References**: material de apoyo en references/

## Skills por Rol

### Architect

| Skill | Propósito | Input | Output |
|-------|-----------|-------|--------|
| spec-from-jira | Lee Jira story → genera spec | Jira key + CLAUDE.md | specs/NN-feature.md |
| architecture-review | Revisa specs/código contra principios | Spec o source code | Reporte de findings |

### Developer

| Skill | Propósito | Input | Output |
|-------|-----------|-------|--------|
| spec-writer | Genera specs manuales (sin Jira) | Descripción + CLAUDE.md | specs/NN-feature.md |
| spec-implementer | Implementa un spec con TDD | Spec file + CLAUDE.md | Código + tests + commits |
| claude-md-updater | Actualiza CLAUDE.md post-spec | Spec "Al finalizar" | CLAUDE.md actualizado |

### QA

| Skill | Propósito | Input | Output |
|-------|-----------|-------|--------|
| bdd-test-generation | Genera .feature desde spec/story | Spec o Jira story | features/<KEY>-<slug>.feature |
| coverage-gap-analysis | Identifica gaps de cobertura | Coverage report | Reporte priorizado |
| unit-test-generation | Genera unit tests | Source file | __tests__/<module>.test.ts |

## Flujo Completo de Specs

PM crea Jira Story
       │
       ▼
┌─────────────────────────────────────────────┐
│  ARCHITECT: spec-from-jira                   │
│  Lee Jira → Lee CLAUDE.md → Genera spec     │
│  Output: specs/NN-feature.md                 │
└─────────────────┬───────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────┐
│  QA: bdd-test-generation                     │
│  Lee spec (Comportamiento + Restricciones)   │
│  Output: features/<KEY>-<slug>.feature       │
└─────────────────┬───────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────┐
│  DEVELOPER: spec-implementer                 │
│  Lee spec (Contratos + Schema + Archivos)    │
│  Verifica .feature existe (BDD-first gate)   │
│  Implementa con TDD                          │
│  Output: código + tests + commits            │
└─────────────────┬───────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────┐
│  DEVELOPER: claude-md-updater                │
│  Lee spec "Al finalizar"                     │
│  Actualiza CLAUDE.md del proyecto            │
└─────────────────────────────────────────────┘

## El Spec como Contrato Único

Un solo spec sirve para los 3 roles de producto (Architect, QA, Developer). Cada rol lee las secciones que le corresponden:

| Sección del Spec | Architect | QA | Developer |
|------------------|:---------:|:--:|:---------:|
| Objetivo | ✍️ escribe | 📖 contexto | 📖 contexto |
| Comportamiento esperado | ✍️ escribe | 🎯 genera .feature | 📖 entiende |
| Modelo de datos | ✍️ escribe | 📖 valida | 🎯 crea schema |
| Contratos de API | ✍️ escribe | 🎯 valida responses | 🎯 implementa |
| Restricciones | ✍️ escribe | 🎯 boundary tests | 🎯 validaciones |
| Integraciones | ✍️ escribe | 📖 mock setup | 🎯 conecta |
| Archivos | ✍️ escribe | ❌ no usa | 🎯 crea/modifica |
| Conceptos destacados | ✍️ escribe | 📖 entiende | 📖 entiende |
| Criterios de aceptación | ✍️ escribe | 🎯 valida cada uno | 📖 sabe cuándo terminó |
| Al finalizar | ✍️ escribe | ❌ no usa | 🎯 actualiza CLAUDE.md |

## MCP por Rol

| MCP Server | Architect | Developer | QA |
|-----------|:---------:|:---------:|:--:|
| GitHub | ✅ Read/Write | ✅ Read/Write | ✅ Read-only |
| Jira | ✅ Read | ✅ Read + transitions | ✅ Read + create bugs |
| Confluence | ✅ Read/Write | ❌ | ❌ |
| SonarCloud | ❌ | ✅ | ❌ |
| Playwright | ❌ | ❌ | ✅ |