# Patrón reutilizable — MCP/servicio per-usuario vía Coder external-auth (OAuth)

Guía general para dar a cada usuario acceso **con su propia identidad** a un
servicio (GitHub, Atlassian, GitLab, etc.) desde su workspace, con **un solo clic**
("Login with X") y **sin URLs manuales**. Aplicable a cualquier proveedor OAuth 2.0.

> Ejemplos ya implementados: **GitHub** (repos per-usuario) y **Atlassian**
> (Jira/Confluence per-usuario). Ver `docs/RUNBOOK-github-app.md` y la sección
> Atlassian de abajo.

---

## Concepto: 3 piezas

```
┌ 1. OAuth App (en el proveedor) ┐   ┌ 2. Coder external-auth ┐   ┌ 3. Template + MCP ┐
│  client_id + secret            │──▶│  hace el OAuth por      │──▶│ data.coder_external│
│  callback a Coder              │   │  usuario (1 clic)       │   │ _auth.<id>.access_ │
│  scopes                        │   │  guarda/refresca token  │   │ token → env → MCP  │
└────────────────────────────────┘   └─────────────────────────┘   └────────────────────┘
```

- El **usuario** solo pulsa un botón que Coder muestra (form de creación de
  workspace, página del workspace, o Account → External Authentication).
- El **token es de cada usuario** → el servicio aplica SU acceso (aislamiento real).
- No es "cero pasos": OAuth per-usuario exige **1 consentimiento único** por usuario
  (no por login). Cero-pasos solo se logra con token de plataforma (compartido),
  que pierde el per-usuario — ver trade-off en `docs/TO-BE/09-gestion-secretos.md`.

---

## Pieza 1 — OAuth App (en el proveedor)

- **Callback URL** (crítico, exacto): `${CODER_ACCESS_URL}/external-auth/<ID>/callback`
  (ej. `http://localhost:3000/external-auth/atlassian/callback`). `<ID>` = el id
  que le des al provider en Coder.
- **Scopes**: los mínimos para lo que el MCP hará (least-privilege).
- Guarda **Client ID** (no secreto) y **Client Secret** (secreto → va a server.env).

> GOTCHA callback: algunos proveedores (GitHub OAuth App) exigen que el callback
> registrado **cubra** la ruta. Si la app se reusa para login + external-auth,
> pon el callback en la **raíz** (`http://host:3000/`) para cubrir ambos.

## Pieza 2 — Coder external-auth (en `server.env`)

Bloque por proveedor (índice `N` = 0,1,2…). Client ID no es secreto; **el secret
lo pega el dueño del server, nunca en git/chat**:

```bash
export CODER_EXTERNAL_AUTH_N_ID="<id>"                 # = el <ID> del callback
export CODER_EXTERNAL_AUTH_N_TYPE="<id-o-tipo>"        # github/gitlab/... o custom
export CODER_EXTERNAL_AUTH_N_DISPLAY_NAME="Etiqueta del botón"
export CODER_EXTERNAL_AUTH_N_CLIENT_ID="<client-id>"
export CODER_EXTERNAL_AUTH_N_CLIENT_SECRET="<secret>"  # ← lo pega el usuario
export CODER_EXTERNAL_AUTH_N_AUTH_URL="https://.../authorize"     # custom: requerido
export CODER_EXTERNAL_AUTH_N_TOKEN_URL="https://.../oauth/token"  # custom: requerido
export CODER_EXTERNAL_AUTH_N_SCOPES="scope1 scope2 offline_access"  # separados por espacio
```
Recargar: `systemctl --user restart coder.service`. Verificar:
`curl -s -H "Coder-Session-Token: $TOK" $CODER_URL/api/v2/external-auth` (aparece el provider).

- **Tipos built-in** (github, gitlab, azure-devops, bitbucket-*, gitea): no hace
  falta AUTH_URL/TOKEN_URL. **Custom** (Atlassian, etc.): sí, obligatorios.
- **`offline_access`** (refresh token) va en `SCOPES`, **NO** en la OAuth App.

## Pieza 3 — Template Terraform + MCP

```hcl
data "coder_external_auth" "<id>" { id = "<id>" }

resource "coder_agent" "main" {
  env = {
    # el token per-usuario se inyecta como la env var que el MCP espera
    SERVICE_TOKEN = data.coder_external_auth.<id>.access_token
  }
}
```
El overlay `.mcp.json` referencia `${SERVICE_TOKEN}`. Como el `coder_agent.env`
llega al proceso del agente, el `claude` lanzado por él (ttyd) hereda la env → el
MCP conecta con el token del usuario.

---

## Ejemplo A — GitHub (implementado)

- OAuth App "coder local" (reusa la de login; callback en raíz).
- `CODER_EXTERNAL_AUTH_0_{ID=github,TYPE=github,CLIENT_ID,CLIENT_SECRET}` (built-in → sin AUTH/TOKEN_URL).
- Template: `GITHUB_TOKEN = data.coder_external_auth.github.access_token`; overlay usa `${GITHUB_TOKEN}`.
- Resultado: cada user ve SOLO sus repos (validado: Juan 90 repos, susanacarolina 0).
- La **GitHub App** `qintess-latam-rbac-resolver` es OTRA cosa (AuthZ/rol, org-level) — no confundir.

## Ejemplo B — Atlassian Jira/Confluence (en curso)

**OAuth App** (developer.atlassian.com/console/myapps → OAuth 2.0 integration):
- **Access type: Resource-level** (least-privilege; 1 sitio).
- Scopes: Jira (`read:jira-work write:jira-work read:jira-user`) + Confluence
  (`read:confluence-content.all write:confluence-content read:confluence-space.summary`).
- `offline_access` NO se marca aquí (va en Coder SCOPES).
- Callback: `http://localhost:3000/external-auth/atlassian/callback`.

**Coder external-auth** (custom OAuth2, en server.env):
```bash
export CODER_EXTERNAL_AUTH_1_ID="atlassian"
export CODER_EXTERNAL_AUTH_1_TYPE="atlassian"
export CODER_EXTERNAL_AUTH_1_DISPLAY_NAME="Atlassian (Jira/Confluence)"
export CODER_EXTERNAL_AUTH_1_CLIENT_ID="<client-id>"
export CODER_EXTERNAL_AUTH_1_CLIENT_SECRET="<secret>"   # lo pega el usuario
export CODER_EXTERNAL_AUTH_1_AUTH_URL="https://auth.atlassian.com/authorize?audience=api.atlassian.com&prompt=consent"
export CODER_EXTERNAL_AUTH_1_TOKEN_URL="https://auth.atlassian.com/oauth/token"
export CODER_EXTERNAL_AUTH_1_SCOPES="read:jira-work write:jira-work read:jira-user read:confluence-content.all write:confluence-content read:confluence-space.summary offline_access"
```
- **Quirk Atlassian 3LO**: el authorize necesita `audience=api.atlassian.com`
  (y `prompt=consent` para forzar refresh) → van como query en `AUTH_URL`.

**mcp-atlassian en modo OAuth (BYOT — bring your own token):**
- El servidor consume el token OAuth inyectado en vez del API token.
- Env: `ATLASSIAN_OAUTH_ACCESS_TOKEN` (= `data.coder_external_auth.atlassian.access_token`)
  + `ATLASSIAN_OAUTH_CLOUD_ID`. El **cloud id** (UUID) se obtiene de
  `https://api.atlassian.com/oauth/token/accessible-resources` con el token
  (con basic auth da 401; es OAuth-only). Sitio: `jotamario.atlassian.net`.
- Overlays `atlassian`: cambiar de `JIRA_URL/JIRA_USERNAME/JIRA_API_TOKEN` (API token
  compartido) a las env `ATLASSIAN_OAUTH_*` (per-usuario).

---

## Distribución de la OAuth App de Atlassian — habilitar para TODOS los usuarios

**Problema:** una OAuth App recién creada en `developer.atlassian.com` nace en modo
**Development**. En ese modo **solo el dueño de la app** (quien la creó) puede
autorizarla. Cualquier otro usuario que pulse "Login with Atlassian" ve:

> *"You don't have access to this app. This application is in development — only the
> owner of this application may grant it access to their account."*

**Esto es independiente del acceso a los datos.** Invitar al usuario a Jira/Confluence
o a un team le da acceso a los **recursos**, pero NO le permite **autorizar la app**.
Son dos gates separados:

| Gate | Qué habilita | Dónde se concede |
|---|---|---|
| Acceso a Jira/Confluence | Que el usuario **vea datos** | admin.atlassian.com (invitar al sitio/producto) |
| **Distribución de la OAuth App** | Que el usuario **pueda autorizar** la app (hacer el Login) | developer.atlassian.com → app → Distribution |

### Pasos para distribuir (habilitar sharing)

1. Entra a **developer.atlassian.com** → **Console** → selecciona tu app OAuth 2.0.
2. En el menú lateral, abre **Distribution** (Distribución).
3. Pulsa **Edit** y cambia el estado de **Development** a **Sharing** (distribuida).
4. Atlassian exige completar unos campos para poder compartir:
   - **Vendor / nombre** del proveedor.
   - **Privacy policy URL** (obligatoria).
   - Opcional: términos, security/contact.
   - **Does your app store personal data?** — responde según corresponda.
5. **Guarda.** El cambio es inmediato: a partir de ahí **cualquier usuario** puede
   pulsar "Login with Atlassian" y autorizar con **su** cuenta.

> No cambia scopes, client_id ni secret — solo **quién puede autorizar**. No hay que
> tocar `server.env` ni el template.

### Verificación

- El **owner** ya podía conectar aun en Development (por eso funcionaba con JuanParraIV).
- Prueba real: un usuario **no-owner** (p.ej. `susanarojas665@gmail.com`) →
  Account → External Authentication → **Login with Atlassian** → debe llegar a la
  pantalla de consentimiento de Atlassian (elegir sitio) **sin** el mensaje de
  "app in development". Tras autorizar, su token queda en Coder y el MCP de Jira
  usa SU identidad.

> Recordatorio: además de distribuir la app, el usuario no-owner debe tener acceso
> al **sitio Atlassian** (invitado en admin.atlassian.com); si no, autoriza la app
> pero no ve proyectos (aislamiento correcto por identidad).

---

## Gotchas transversales (aprendidos)

1. **El dueño debe iniciar el build**: `coder restart <owner>/<ws>` como ADMIN NO
   inyecta el token de otro usuario (protección). El owner reinicia desde la UI.
2. **Workspaces existentes** creados antes de añadir el external-auth no pasan por
   el botón del form → el usuario conecta en **Account → External Authentication**.
3. **`docker exec` NO hereda el env del agente** (donde vive el token). Verificar
   por efectos (`~/.git-credentials`) o leyendo `/proc/<agentpid>/environ`.
4. **Token compartido vs per-usuario**: si inyectas una credencial de plataforma
   (App token, service account) tienes cero-pasos pero identidad compartida; el
   per-usuario (external-auth) cuesta 1 clic único. Elegir según auditoría requerida.
5. **No hornear el access token si expira corto (Atlassian ~1h)**: dos capas —
   Coder↔proveedor **auto-refresca** (con `offline_access`), pero
   `data.coder_external_auth.<id>.access_token` se resuelve en **build-time** y queda
   como **foto** en el env; un workspace con >1h de uptime sirve un token muerto → 401
   aunque la UI diga "conectado". **Fix:** que el MCP pida el token **fresco en runtime**
   con `coder external-auth access-token <id>` (wrapper `bash -lc` en el `.mcp.json`),
   no la env horneada. GitHub no sufre esto (sus `gho_` no caducan por defecto). Límite:
   `mcp-atlassian` BYOT no refresca dentro de una sesión >1h → reconectar el MCP.
6. **OAuth App en modo Development bloquea a los no-owner**: ver sección
   "Distribución de la OAuth App" arriba. Habilitar **Sharing/Distributed** para que
   usuarios distintos al dueño puedan autorizar.
