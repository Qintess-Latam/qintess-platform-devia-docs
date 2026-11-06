# Sección 13: AuthZ a Escala (piloto → producción, miles de usuarios)

## Estado: 🟩 Camino A (GitHub App / N2) ELEGIDO e **implementado** en el piloto (`qintess-latam-rbac-resolver`, org `Qintess-Latam`) · N3 (OIDC) scaffoldeado como futuro

> **Decisión (2026-07-09):** se mantiene **GitHub como IdP** (Decisión #2) → ruta
> de producción = **Camino A / Nivel 2: GitHub App**. `resolve-role.sh` se queda;
> la credencial del server pasa de PAT personal a **App de la organización**
> (token auto-rotado). El **Camino B / N3 (OIDC + group sync)** queda scaffoldeado
> como evolución si en el futuro se adopta un IdP OIDC (Okta/Entra) — implicaría
> cambiar la Decisión #2. Ambos coexisten en el repo.

## Problema que resuelve

En el prototipo inicial la resolución de rol dependía de un **PAT personal** pegado
en `~/.config/coderv2/server.env` (hoy ya reemplazado por la GitHub App de la org).
La duda que motivó esta sección al pensar en producción:

> "Cualquier persona con la URL inicia sesión con GitHub. Con miles de usuarios,
> ¿cada uno tiene que pegar un token?"

**No.** Los usuarios **nunca** pegan un token. Hay que separar dos capas que hoy
están mezcladas: *autenticación* (quién eres) y *autorización* (qué rol tienes).
El token del que hablamos es **uno solo, del servidor/plataforma**, sin importar
si hay 1 o 10.000 usuarios.

---

## Las dos capas

```
┌───────────────────────────── AuthN: "¿quién eres?" ─────────────────────────────┐
│  Usuario ──▶ GitHub OAuth / OIDC (Okta, Entra, Azure AD) ──▶ sesión en Coder     │
│  Escala sola. El usuario solo hace SSO. No provisiona nada, no pega nada.        │
│  CODER_OAUTH2_GITHUB_ALLOWED_ORGS restringe a miembros de la org.               │
└─────────────────────────────────────────────────────────────────────────────────┘
                                     │
                                     ▼
┌──────────────────────────── AuthZ: "¿qué rol tienes?" ──────────────────────────┐
│  Coder/plataforma ──▶ consulta membresía de team/grupo ──▶ role = developer|... │
│  UNA credencial de servicio responde para TODOS los usuarios.                    │
│  Aquí (y SOLO aquí) vive el token del que hablamos.                              │
└─────────────────────────────────────────────────────────────────────────────────┘
```

`resolve-role.sh` pregunta *"¿de qué team es este usuario?"* usando el **token del
servidor** (credencial de servicio), NUNCA el token del usuario. Ese mismo token
responde para todos → 1 token por plataforma, no 1 por usuario.

---

## Ruta de migración (prototipo → producción)

| Nivel | Credencial AuthZ | Atada a | Rotación | Escala | Cuándo |
|-------|------------------|---------|----------|--------|--------|
| **0. PAT personal** | PAT classic/fine-grained en `server.env` | Tu cuenta personal | Manual (1 vez, o al expirar) | 1 usuario | Superado |
| **1. Bot/service account + PAT** | Fine-grained PAT `read:org` de cuenta máquina | Cuenta bot dedicada (no persona) | Manual anual | Piloto / squad | Producción simple |
| **2. GitHub App** ✅ (hoy) | Installation token derivado de private key | La App instalada en la org | **Auto-rotado (~1 h)** | Org-wide | Producción real con GitHub — **implementado** |
| **3. IdP + group sync (OIDC/SCIM)** ✅✅ | Ninguna credencial custom; el IdP emite claims | El IdP corporativo | N/A (el IdP gestiona) | Miles, multi-org | Empresa / banco |

> Referencia cruzada: la Decisión #16 (`00-desiciones.md`) ya fija
> **Onboarding tokens = Automático (GitHub App + onboard-controller)**, y la #11
> **Secretos MCP = per-user vía External Secrets Operator + OAuth**. Esta sección
> desarrolla el eslabón de **AuthZ de plataforma**, complementario a esos.

### Por qué el PAT personal no sirve a escala

- Atado a una **persona**: si sale de la org o rota la clave, se cae la
  resolución de roles de **todos**.
- No auditable como identidad de plataforma (aparece como acción de un humano).
- Rate limit de PAT (5.000 req/h) compartido con el uso personal de esa cuenta.

---

## Nivel 2 — GitHub App (recomendado si se mantiene GitHub como IdP)

Reemplaza el PAT personal por una **GitHub App** instalada en la org:

- Permiso mínimo: **Organization → Members: Read-only**.
- Autentica con **installation token** generado desde una *private key* (JWT →
  token de instalación de vida corta, auto-rotado cada ~1 h).
- No está atada a ninguna persona; sobrevive a bajas de empleados.
- Rate limits por instalación mucho mayores (escalan con el tamaño de la org).
- Auditable: las llamadas aparecen como la App, no como un humano.

```
┌──────────────┐   private key    ┌──────────────────┐   installation   ┌───────────┐
│ Coder server │ ───(JWT sign)──▶ │  GitHub App auth │ ───token(~1h)──▶ │ orgs/.../ │
│ (provisioner)│                  │  (org install)   │                  │ teams/... │
└──────────────┘                  └──────────────────┘                  └───────────┘
```

`resolve-role.sh` casi no cambia: en vez de `GITHUB_TOKEN=<PAT>` usa un token de
instalación (obtenido por un sidecar/refresher que renueva antes de expirar y lo
deja en `server.env` o en un secret montado). La lógica de prioridad de teams
(least-privilege `qa < developer < cyber < platform < architect`) es idéntica.

---

## Nivel 3 — IdP + group sync nativo (la respuesta "producción de verdad")

Para miles de usuarios, lo idiomático es **eliminar `resolve-role.sh`** y usar el
**group sync nativo de Coder**. Coder mapea grupos del IdP a **Groups/Roles** en el
propio login, sin script ni token custom:

```
Usuario ─SSO─▶ IdP (Okta/Entra/GitHub) ─claims(groups)─▶ Coder
                                                           │
                          ┌────────────────────────────────┘
                          ▼
         CODER_OIDC_GROUP_MAPPING / GitHub team sync
                          │
                          ▼
        Coder Group: platform-developers ─▶ template ACL: mvp-embedded (developer overlay)
        Coder Group: qa-engineers        ─▶ template ACL: qa-template
        Coder Group: architects          ─▶ template ACL: architect-template
```

- El usuario hace **SSO** (GitHub OAuth u OIDC con Okta/Entra/Azure AD).
- Coder lee los **grupos/teams** del claim y **auto-asigna Groups y Roles al
  login** (`CODER_OIDC_GROUP_FIELD`, `CODER_OIDC_GROUP_MAPPING`, o el sync de
  GitHub teams).
- Esos Groups controlan qué **templates** puede usar cada quien vía **template
  ACL** → developer/qa/architect sin tocar contenedores ni labels a mano.
- **SCIM** (si el IdP lo soporta) provisiona/desprovisiona usuarios
  automáticamente: alta y baja sin intervención de admin.
- **Cero tokens que pegar, cero script custom, cero PAT.**

### Equivalencia con lo que hoy hace `resolve-role.sh`

| Hoy (piloto) | Producción (group sync nativo) |
|---------------|-------------------------------|
| `data.external` → `resolve-role.sh` | Coder resuelve el grupo en el login (OIDC/GitHub) |
| GitHub App del servidor consulta `orgs/.../teams/.../memberships` | El IdP emite el claim `groups` firmado |
| Plantilla por rol + `required_role` valida el team en cada build (Coder OSS no tiene ACL de plantillas) | Coder Group → template ACL (qué template ve el usuario) |
| Prioridad multi-team en bash | Reglas de mapping declarativas en el IdP/Coder |

> Group sync avanzado y template ACL granular son features de **Coder
> Premium/Enterprise**. En OSS se puede aproximar con OIDC group claims +
> asignación por grupo, con menos granularidad.

---

## Consideraciones a escala

- **Rate limits:** `resolve-role.sh` corre **por build de workspace** (no por
  login ni por request), así que el volumen está acotado; aun así, GitHub App >
  PAT en límites. El group sync nativo elimina el problema (no llama a la API en
  caliente).
- **Cacheo:** si se mantiene la lógica custom, cachear la membresía de team
  (TTL corto) evita golpear la API en cada rebuild.
- **Fail-closed:** a escala, ante fallo de la API el rol debe caer a `unknown`
  (mínimos privilegios), nunca a un rol. Y en multi-team gana el rol MENOS
  permisivo (least-privilege: `qa < developer < cyber < platform < architect`; ver `02-rbac-mapping-roles.md`).
- **Auditoría:** con GitHub App / IdP, cada resolución de rol es atribuible a una
  identidad de plataforma, no a una persona → cumple el requisito regulatorio de
  trazabilidad (alineado con `07-observabilidad-audit.md`).

---

## Scaffold N2 en el repo — Camino A / GitHub App (ELEGIDO)

Ruta de producción activa: sigue GitHub como IdP, `resolve-role.sh` se mantiene,
la credencial del server pasa de PAT personal a **GitHub App de la org**.

| Artefacto | Qué aporta |
|-----------|------------|
| `templates/mvp-embedded/scripts/gh-app-token.sh` | Mintéa un **installation token** (JWT RS256 → 1 h) desde la private key de la App. On-demand, sin token en disco. |
| `templates/mvp-embedded/scripts/resolve-role.sh` | Actualizado: precedencia **PAT env > GitHub App > gh ambiente**. Fail-closed a `unknown`. Backward-compat total. |
| `deploy/prod/github-app.env.example` | Vars de la App: `GITHUB_APP_ID`, `GITHUB_APP_INSTALLATION_ID`, `GITHUB_APP_PRIVATE_KEY_PATH`. |
| `docs/RUNBOOK-github-app.md` | Crear App (`Members: read`), instalar en la org, cablear al server, validar, re-estampar el label. |

Migración sin downtime: se puede dejar el PAT y la App a la vez (el PAT gana);
verificas la App y luego quitas el PAT.

## Scaffold N3 en el repo (futuro, si se adopta IdP OIDC)

El camino N3 está **scaffoldeado y commit-eable**; solo faltan las dependencias
externas (IdP real + Coder Premium) para ejecutarlo:

| Artefacto | Qué aporta |
|-----------|------------|
| `templates/prod-oidc/main.tf` | Template de prod con **rol nativo por grupo** (`data.coder_workspace_owner.me.groups`) — sin `resolve-role.sh`, sin PAT. Fail-closed a `unknown`. |
| `deploy/prod/coder-oidc.env.example` | Config del server: `CODER_OIDC_*`, group sync, group/role mapping, SCIM, external-auth. |
| `docs/RUNBOOK-prod-oidc.md` | Setup paso a paso (IdP → server → template → ACL → validación E2E) + checklist "antes de prod". |

El corazón del reemplazo de `resolve-role.sh` es puro HCL, sin credenciales:

```hcl
locals {
  group_to_role = {
    "architects"          = "architect"
    "platform-developers" = "developer"
    "qa-engineers"        = "qa"
  }
  role_priority = ["qa", "developer", "architect"]   # least-privilege: gana el menos permisivo
  owner_groups  = data.coder_workspace_owner.me.groups
  matched_roles = [for g in local.owner_groups : local.group_to_role[g] if contains(keys(local.group_to_role), g)]
  role = try([for r in local.role_priority : r if contains(local.matched_roles, r)][0], "unknown")
}
```

**Bloqueadores para ejecutar en el piloto:** (1) IdP OIDC real (Okta/Entra/Keycloak);
(2) group sync avanzado (mapping regex, auto-create, SCIM) = **Coder Premium**. El
group sync básico por claim OIDC corre también en OSS con menos granularidad.

## Recomendación

1. ~~**Corto plazo:** PAT / cuenta bot (Nivel 0/1).~~ Superado.
2. **Producción con GitHub:** **GitHub App** (Nivel 2) — sin PAT personal, token
   auto-rotado, auditable. ✅ **Implementado** en el piloto.
3. **Empresa / banco (miles de usuarios):** **IdP + group sync (OIDC/SCIM)**
   (Nivel 3) — eliminar `resolve-role.sh`, roles asignados en el login, alta/baja
   automática. Es la ruta natural del proyecto bancario ([[ai-agents-framework]]).

En ninguno de los tres el usuario final pega un token: solo hace SSO.
