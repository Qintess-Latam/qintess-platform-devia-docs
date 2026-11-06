# Gestión de Secretos — Onboarding Automático

## Dos ejes que NO hay que confundir

- **QUÉ** MCP servers aparecen (github, jira, sonar…) lo decide el **ROL** (el overlay).
- **DE QUIÉN** son las credenciales que los llenan lo decide el **USUARIO** (su identidad).

El rol ya *scoping* los secretos: el `.mcp.json` de qa no incluye sonar → su workspace
nunca necesita `SONAR_TOKEN`. Cada rol solo pide los secretos de SUS servers.

## ⚠️ Corrección clave: hay DOS credenciales de GitHub distintas

| Credencial | Qué es | Para qué | ¿Per-usuario? |
|---|---|---|---|
| **GitHub App** (installation token) | Token de la **organización** | **AuthZ**: el *servidor* resuelve el rol (team lookup) | ❌ no (igual para todos) |
| **external-auth OAuth** (user token) | Token del **usuario** | Que el workspace actúe COMO él: `git push`, github MCP | ✅ sí |

La GitHub App **NO** sirve para dar identidad de usuario dentro del workspace (su
installation token es org-level). Para eso se usa **Coder external-auth** (OAuth por
usuario, 1 clic). Ver `docs/RUNBOOK-github-app.md` (App = AuthZ) vs esta guía (identidad).

## Visión General

Cada operador usa **sus propias credenciales**, sin pegar tokens a mano:

1. Detecta usuario nuevo en Coder
2. Credenciales **OAuth per-usuario** (GitHub, Jira) via **Coder external-auth** (1 clic, auto-refresh)
3. Credenciales **token-only** (Sonar, Selenium) desde Secret Manager
4. Se sincronizan al workspace (external-auth en runtime + External Secrets Operator en K8s)

---

## Arquitectura de Secretos

┌─────────────────────────────────────────────────────────────────┐
│                     SECRET MANAGER                                │
│                (AWS / Vault / Azure Key Vault)                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  (GitHub y Jira NO viven aquí: son OAuth per-usuario via          │
│   Coder external-auth. Aquí solo van los token-only y compartidos)│
│  coder/users/juan/sonar-token          = sonar_xxxxx (si per-user)│
│  coder/shared/sonar-token              = sonar_org (dev-only)     │
│  ...                                                             │
│                                                                  │
│  coder/shared/atlassian-base-url       = https://banco...  │
│  coder/shared/selenium-grid-url        = http://selenium:4444   │
│                                                                  │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼  External Secrets Operator (cada 1h)
┌──────────────────────────────────────────────────────────────────┐
│                     K8S SECRETS (auto-generados)                   │
├──────────────────────────────────────────────────────────────────┤
│  workspace-secrets-juan   → GITHUB_TOKEN, ATLASSIAN_API_TOKEN... │
│  workspace-secrets-maria  → GITHUB_TOKEN, ATLASSIAN_API_TOKEN... │
└──────────────────────────────┬───────────────────────────────────┘
                               │
                               ▼  main.tf → env_from { secret_ref }
┌──────────────────────────────────────────────────────────────────┐
│                     POD (env vars)                                 │
├──────────────────────────────────────────────────────────────────┤
│  $GITHUB_TOKEN          → Claude MCP: GitHub                     │
│  $ATLASSIAN_API_TOKEN   → Claude MCP: Jira                       │
│  $ATLASSIAN_BASE_URL    → Claude MCP: Jira                       │
│  $ATLASSIAN_EMAIL       → Claude MCP: Jira                       │
│  $SONAR_TOKEN           → Claude MCP: SonarCloud (dev only)      │
│  $SELENIUM_GRID_URL     → Claude MCP: Playwright (qa only)       │
└──────────────────────────────────────────────────────────────────┘

---

## Fuentes de Tokens

### GitHub (identidad de usuario) — via Coder external-auth (OAuth)

Para que `git push` y el github MCP actúen **COMO el usuario real**, se usa
**Coder external-auth** (OAuth), NO la GitHub App.

| Aspecto | Detalle |
|---------|---------|
| **Mecanismo** | Coder external-auth (GitHub OAuth) → token del usuario, 1 clic "Authorize" |
| **Scope** | repo, read:org (según lo que declare la OAuth App) |
| **Duración** | Token OAuth de usuario; Coder lo gestiona/renueva |
| **Auditoría** | Los commits/acciones quedan a nombre de **cada persona** |
| **Setup** | GitHub OAuth App + `CODER_EXTERNAL_AUTH_0_*` en el server |

**En el workspace** (startup_script), el token del usuario se obtiene así:
```bash
export GITHUB_TOKEN="$(coder external-auth access-token github)"
# el github MCP (${GITHUB_TOKEN} en .mcp.json) conecta como ESE usuario
```

> **No confundir con la GitHub App** (`qintess-latam-rbac-resolver`, ver
> `docs/RUNBOOK-github-app.md`): esa es **AuthZ del servidor** (resolver rol por team) y su
> installation token es de la org, no de un usuario. Son dos cosas separadas.

**Configurar external-auth (una vez):** GitHub OAuth App con callback
`${CODER_ACCESS_URL}/external-auth/github/callback`; luego en el server:
```bash
CODER_EXTERNAL_AUTH_0_ID="github"
CODER_EXTERNAL_AUTH_0_TYPE="github"
CODER_EXTERNAL_AUTH_0_CLIENT_ID="<oauth-app-client-id>"
CODER_EXTERNAL_AUTH_0_CLIENT_SECRET="<oauth-app-client-secret>"
```

### Jira/Confluence — MCP `mcp-atlassian` (IMPLEMENTADO ✅ — OAuth per-usuario)

Server real = **`uvx mcp-atlassian`** (cubre Jira **y** Confluence; reemplaza los
placeholders `@mcp/jira-server`/`@mcp/confluence-server`).

**Estado (piloto, 2026-10-15):** implementada la opción **B — OAuth 3LO per-usuario
vía external-auth `atlassian`** (Decisión #12), validada contra
`qintess-latam.atlassian.net`. Cada usuario hace "Login with Atlassian" una vez; el
MCP pide un token **fresco** en cada arranque con `coder external-auth access-token
atlassian` y deriva el `cloud_id` de `accessible-resources` (el token del env del
build vence a la hora). El API token compartido (variables `jira_*`) **se retiró**.
La OAuth App de Atlassian tiene que estar en *Distribution: Sharing* para que
usuarios distintos del dueño puedan autorizarla.

| Aspecto | Detalle |
|---------|---------|
| **Mecanismo hoy** | OAuth 3LO per-usuario (external-auth Atlassian) |
| **Scope** | Lo que **cada usuario** puede ver/hacer en Jira/Confluence |
| **Auditoría** | Acciones a nombre del usuario real (trazabilidad completa) |
| **Límite conocido** | `mcp-atlassian` en modo BYOT no refresca dentro de una sesión >1 h: reconectar el MCP |

Las opciones A/C de abajo quedan como **alternativas de diseño** (service account
compartido) por si se necesitara un bot sin identidad de usuario.

**Opción A: Token por service account (simple, recomendado para piloto)**

Un solo API token de un service account (coder-bot@banco.com) con permisos en Jira.
Todos los usuarios lo comparten para Jira (las acciones en Jira se registran como "coder-bot").

Secret Manager:
  coder/shared/atlassian-api-token = ATATT3xxxx (del service account)
  coder/shared/atlassian-base-url  = https://banco-jira.atlassian.net
  coder/shared/atlassian-email     = coder-bot@banco.com

**Opción B: Token por usuario (mejor auditoría)**

Cada operador genera su propio Atlassian API token una sola vez:
1. Ir a: `https://id.atlassian.com/manage-profile/security/api-tokens`
2. Create API token → copiar
3. El onboard-controller lo guarda en Secret Manager

Para automatizar esto completamente, se usa **Atlassian Admin API (SCIM/org)**:
bash
# Generar token programáticamente via Atlassian Admin API
curl -X POST "https://api.atlassian.com/admin/v1/orgs/{orgId}/apiTokens" \
  -H "Authorization: Bearer ${ATLASSIAN_ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"label": "coder-workspace-'$USERNAME'", "scopes": ["read:jira-work", "write:jira-work"]}'

**Recomendación:** Opción A para piloto (service account), migrar a Opción B si compliance lo exige.

### SonarCloud — Token compartido por org

| Aspecto | Detalle |
|---------|---------|
| **Mecanismo** | SonarCloud org-level token |
| **Scope** | Read analysis results, project metrics |
| **Duración** | Sin expiración (rotar manualmente cada 90 días) |
| **Quién lo usa** | Solo developers |

Secret Manager:
  coder/shared/sonar-token = 85baf0b87df... (org token)

---

## Onboarding Automático — Flujo Completo

Operador se agrega al GitHub Team
       │
       ▼
Operador abre Coder URL → Login GitHub
       │
       ▼
onboard-controller.sh (CronJob cada 2 min):
       │
       ├── 1. Detecta: "juan" no tiene workspace
       │
       ├── 2. Resuelve rol: GitHub Teams → "developer"
       │
       ├── 3. GitHub token del USUARIO:
       │       Coder external-auth (OAuth) → token de Juan (1 clic la 1ª vez)
       │       → en runtime: coder external-auth access-token github
       │
       ├── 4. Configura Jira token:
       │       Copia shared: coder/shared/atlassian-api-token
       │       (o genera per-user si Opción B)
       │
       ├── 5. Crea ExternalSecret en K8s:
       │       "workspace-secrets-juan" → sincroniza todo
       │
       ├── 6. Espera sync (≤60s)
       │
       └── 7. Crea workspace: coder workspaces create juan/workspace
       │
       ▼
Operador refresca → workspace listo con todos los tokens ✅

---

## Rotación Automática

| Token | Cómo se rota | Frecuencia |
|-------|-------------|-----------|
| **GitHub (usuario)** | Coder external-auth (OAuth) refresca el token del usuario | Automático (Coder) |
| **Jira (usuario)** | Coder external-auth OAuth 3LO refresca (Decisión #12) | Automático (Coder) |
| **SonarCloud** | Admin rota en Secret Manager → ESO sincroniza | Manual cada 90 días |

---

## Revocación (offboarding)

Cuando un operador sale del equipo:

bash
# 1. Remover del GitHub Team (automático: pierde acceso OAuth a Coder)

# 2. Eliminar secretos
bash deploy/offboard-user.sh juan

# Internamente:
#   kubectl delete externalsecret workspace-secrets-juan -n coder-workspaces
#   aws secretsmanager delete-secret --secret-id coder/users/juan/github-token
#   coder workspaces delete juan/workspace --yes

---

## Setup Inicial (una vez)

### 1. Instalar External Secrets Operator

bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace

### 2. Crear SecretStore

bash
kubectl apply -f secrets/secret-store.yaml

### 3. Crear GitHub App

Ver sección "GitHub — via GitHub App" arriba.

### 4. Configurar secretos compartidos en Secret Manager

bash
# Atlassian (service account)
aws secretsmanager create-secret \
  --name "coder/shared/atlassian-api-token" \
  --secret-string "ATATT3xFfGF09..."

aws secretsmanager create-secret \
  --name "coder/shared/atlassian-base-url" \
  --secret-string "https://banco-jira.atlassian.net"

aws secretsmanager create-secret \
  --name "coder/shared/atlassian-email" \
  --secret-string "coder-bot@banco.com"

# SonarCloud
aws secretsmanager create-secret \
  --name "coder/shared/sonar-token" \
  --secret-string "85baf0b87df..."

# Selenium Grid (QA)
aws secretsmanager create-secret \
  --name "coder/shared/selenium-grid-url" \
  --secret-string "http://selenium-grid.testing.svc:4444"

### 5. Desplegar onboard-controller

bash
kubectl apply -f deploy/cronjob-onboard-controller.yaml

---

## Estructura en Secret Manager

coder/
├── shared/                          ← Compartidos (token-only, todos)
│   ├── atlassian-base-url
│   ├── sonar-token                  ← dev-only
│   └── selenium-grid-url            ← qa-only
└── users/                           ← Per-user token-only (si aplica)
    ├── juan/  └── sonar-token        (opcional, si Sonar per-user)
    └── ...

# GitHub y Jira NO están aquí: son OAuth per-usuario via Coder external-auth
# (el token se obtiene en runtime con `coder external-auth access-token <id>`).