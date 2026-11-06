# RUNBOOK — Coder en la VM, centralizado en GitHub `Qintess-Latam`

> Paso a paso COMPLETO para dejar Coder listo en la VM, con login + RBAC por
> GitHub (`Qintess-Latam`), Claude Code **y** GitHub Copilot CLI, capacidades por
> rol (MCP + skills + persona). Reutiliza plantilla/overlays/scripts del repo.
>
> **Datos del despliegue:** usuario `dev-ia`, VM `192.168.50.208`, Coder en `:3000`,
> org GitHub `Qintess-Latam`. Edición Coder = **OSS/Community** (gratis; el RBAC va
> por label+overlay, no por Coder Groups → no necesita licencia Premium).
>
> **Repo:** migrado de `JuanParraIV/coder-platform` (personal) a
> `Qintess-Latam/qintess-platform-coder-template` (org, privado). El remote
> viejo queda como `personal-old` en los checkouts que lo tenían.

---

## Pre-flujo — conceptos (para no perderse)
Hay **3 conexiones GitHub distintas**, cada una con su app:
1. **OAuth App (login)** → entrar a Coder (AuthN).
2. **GitHub App resolver** → saber el rol por Team (AuthZ). Firma JWT con un `.pem`.
3. **external-auth** → el workspace accede a los repos del usuario (token per-usuario).
Además: **Copilot Business** (ya contratado en Qintess-Latam) gobierna los modelos.

---

## FASE 0 — Binarios en la VM (una vez)
En la VM (usuario `dev-ia`, con sudo):
```bash
bash deploy/vm/install-binaries.sh     # docker, coder v2.37.4, gh, git, jq, curl, openssl
# cierra sesión y reentra si te agregó al grupo docker (o: newgrp docker)
```
> Si el repo no está en la VM: cópialo (tarball/worktree) a `~/coder-platform`.

---

## FASE 1 — Levantar el server Coder
```bash
cd ~/coder-platform
cp deploy/vm/vm-deploy.conf.example deploy/vm/vm-deploy.conf
nano deploy/vm/vm-deploy.conf          # CODER_ACCESS_URL="http://192.168.50.208:3000"
bash deploy/vm/bootstrap-vm.sh         # systemd --user + linger, siembra server.env
```
GOTCHAS conocidos:
- **BD de versión más nueva** (`migrate up: no migration found`): en una instalación **nueva** con Postgres embebido, `rm -rf ~/.config/coderv2/postgres` y reiniciar. **En la VM actual NO aplica** — la BD vive en el stack `coder-db` (ver [`RUNBOOK-vm-portainer-red.md`](RUNBOOK-vm-portainer-red.md)); ese `rm -rf` borraría el plan de rollback.
- **tar del release trae `./coder`**: el script ya extrae todo y lo ubica con `find`.

---

## FASE 2 — GitHub `Qintess-Latam` (web). Crear:

### 2a. Teams (RBAC) — `github.com/orgs/Qintess-Latam/teams`
Crea con nombre EXACTO: `platform-developers`, `qa-engineers`, `architects`.
Añade cada usuario a su team (tú a uno para probar).

### 2b. OAuth App de login — `github.com/organizations/Qintess-Latam/settings/applications/new`
- Name: `Coder VM`
- Homepage: `http://192.168.50.208:3000`
- **Authorization callback URL: `http://192.168.50.208:3000`** (la RAÍZ → cubre login y external-auth)
- Registrar → anota **Client ID** + **Generate client secret**.

### 2c. GitHub App resolver — `github.com/organizations/Qintess-Latam/settings/apps/new`
- Name: `qintess-latam-rbac-resolver`
- Webhook: **Active = off**
- Permisos: Organization → **Members: Read-only**
- Crear → **Install App** en `Qintess-Latam` → **Generate a private key** (descarga `.pem`)
- Anota **App ID** e **Installation ID** (número al final de la URL de la instalación:
  `.../settings/installations/<ID>`).
- Pon el `.pem` en la VM: `~/.config/coderv2/github-app.pem` (chmod 600). Truco si no
  pasa por transferencia: descárgalo desde el navegador **de la VM**.

### 2d. Copilot (modelos) — `github.com/organizations/Qintess-Latam/settings/copilot`
**Seats — por team de rol, no por usuario** (desde 2026-10-15). Tienen seat los
**5 teams padre**: `qintess-architect`, `qintess-developers`, `qintess-platform`,
`qintess-qa` y `qintess-cyber`. Quien entra a un team de rol recibe seat solo, y
quien sale (de todos) lo pierde. Un usuario en varios teams consume **un** seat
(USD 19/mes, Copilot Business): `seats_created` de la API cuenta asignaciones
persona×team, no seats facturados — verificar con `total_seats`.

| Usuario | Team de rol | Seat vía |
|---|---|---|
| BorisFRQintess, LuisRZQintess | `qintess-architect` (+ 4 subteams) | `qintess-architect` |
| FabianGAQintess, RichardASQintess | `qintess-developers` (+ 4 subteams) | `qintess-developers` |
| JuanPDQintess | todos (incl. platform y cyber) | uno de ellos |

**GOTCHA — los seats solo los asigna un owner (usuario), no una GitHub App.**
Con `qintess-mozart-bot` la API responde `422 "Inviting User is not an admin of
the Organization"`. Hacerlo desde la UI (*Copilot → Access → Add seats → Teams*)
o con `gh` logueado como owner. La primera asignación pidió los scopes
`manage_billing:copilot` + `admin:org`; agregar teams después funcionó solo con
`manage_billing:copilot`:

```bash
gh auth refresh -h github.com -s manage_billing:copilot,admin:org   # device flow
gh api -X POST orgs/Qintess-Latam/copilot/billing/selected_teams \
  -f 'selected_teams[]=qintess-architect' -f 'selected_teams[]=qintess-developers' \
  -f 'selected_teams[]=qintess-qa' -f 'selected_teams[]=qintess-platform' \
  -f 'selected_teams[]=qintess-cyber'
gh auth refresh -h github.com -r admin:org    # quitar admin:org al terminar

# verificar
gh api 'orgs/Qintess-Latam/copilot/billing/seats?per_page=100' \
  --jq '.seats[] | "\(.assignee.login)\tvia=\(.assigning_team.slug // "directo")"'
gh api orgs/Qintess-Latam/copilot/billing --jq '{seat_breakdown, cli}'
```

Un rol **nuevo** (un team que no esté en la lista) **no** tiene seat hasta
agregar su team padre con el mismo `POST .../selected_teams`.

**Policies** (solo por UI, no hay API para modelos; aplican a **toda la org**,
no por team):
- **Models** → solo **Claude Sonnet**, **Opus** y **Haiku** (decisión 2026-10-15).
  En el catálogo quedan `claude-sonnet-5.5`, `claude-opus-5.5`, `claude-haiku-5.5`,
  más `gpt-5-mini` y `gpt-5.3-codex` si GitHub no deja apagarlos. Costo relativo por
  token: Haiku 1× · Sonnet ~20× · Opus ~40× (2× Sonnet). Recomendación: Sonnet por
  defecto, Opus para arquitectura, Haiku para tareas mecánicas.
- **MCP servers in Copilot** → **Enabled** (si no, Copilot bloquea los MCP de los overlays: github, atlassian, playwright).
- **Copilot in the CLI** → **Enabled**. Si queda `unconfigured`
  (`gh api orgs/Qintess-Latam/copilot/billing --jq .cli`), la terminal Copilot
  del workspace no tiene acceso.

**Modelos de Claude Code por rol** (overlays, `<rol>/settings.json`): solo fijan
el **default** — `architect` → `opus`, `developer` y `qa` → `sonnet`. No hay
restricción (`availableModels`): cualquier rol puede elegir Opus/Sonnet/Haiku
con `/model` (decisión 2026-10-15).

---

## FASE 3 — `server.env` en la VM
Edita `~/.config/coderv2/server.env` con los valores de la Fase 2:
```bash
# Login
export CODER_OAUTH2_GITHUB_CLIENT_ID="<Client ID 2b>"
export CODER_OAUTH2_GITHUB_CLIENT_SECRET="<Secret 2b>"
export CODER_OAUTH2_GITHUB_ALLOWED_ORGS="Qintess-Latam"
export CODER_OAUTH2_GITHUB_ALLOW_SIGNUPS="true"
# external-auth GitHub (reusa la app de login; callback raíz lo cubre)
export CODER_EXTERNAL_AUTH_0_ID="github"
export CODER_EXTERNAL_AUTH_0_TYPE="github"
export CODER_EXTERNAL_AUTH_0_CLIENT_ID="$CODER_OAUTH2_GITHUB_CLIENT_ID"
export CODER_EXTERNAL_AUTH_0_CLIENT_SECRET="$CODER_OAUTH2_GITHUB_CLIENT_SECRET"
# GitHub App resolver (rol)
export GITHUB_APP_ID="<App ID 2c>"
export GITHUB_APP_INSTALLATION_ID="<Installation ID 2c>"
export GITHUB_APP_PRIVATE_KEY_PATH="/home/dev-ia/.config/coderv2/github-app.pem"
```
```bash
chmod 600 ~/.config/coderv2/server.env ~/.config/coderv2/github-app.pem
sudo ufw allow 3000/tcp 2>/dev/null || true
systemctl --user restart coder
sleep 6 && curl -fsS http://localhost:3000/healthz && echo "  ← Coder OK"
```

---

## FASE 4 — Primer admin
- Navegador → `http://192.168.50.208:3000` → **Login with GitHub** (cuenta miembro de `Qintess-Latam`). El **primer** login = admin/owner.
- Recuperación de owner (si el CLI no puede subir plantillas por `rbac: forbidden` y no
  recuerdas el admin): el dueño del server puede darse `owner` directo en la BD
  (desde 2026-10-06 es el container `coder-db`):
  ```bash
  docker exec coder-db psql -U coder -d coder \
    -c "UPDATE users SET rbac_roles='{owner}' WHERE username='<tu-usuario>';"
  ```

---

## FASE 5 — Subir la plantilla (con la org correcta)
> **Desde 2026-10-15 se usan las plantillas por rol** (`qintess-<rol>-template`):
> `bash deploy/vm/push-role-templates.sh`. Ver
> [`RUNBOOK-plantillas-por-rol.md`](RUNBOOK-plantillas-por-rol.md). Lo de abajo
> sube `mvp-embedded` (genérica, **obsoleta**: solo workspaces existentes).

Antes: corre `bash deploy/vm/sync-agent-overlays.sh` (ver FASE 9 más abajo) —
genera `~/.config/coderv2/agents-overlays-synced`, la carpeta combinada que se
pasa abajo. **`overlays_host_path` ya NO tiene default** (ver gotcha de la
ruta muerta, corregido): hay que pasarla siempre explícita.

Login del CLI sin flujo interactivo (solo web): token desde `http://192.168.50.208:3000/cli-auth`:
```bash
coder login http://192.168.50.208:3000 --token <TOKEN_DE_cli-auth>
cd ~/coder-platform/templates/mvp-embedded
coder templates push mvp-embedded \
  --var overlays_host_path=$HOME/.config/coderv2/agents-overlays-synced \
  --var github_org=Qintess-Latam --yes
```
GOTCHAS:
- Si dice **"No configuration files"**: sube desde copia limpia (`mktemp -d`, solo
  `main.tf`+`scripts/`) con `--directory`.
- **500 de registry.terraform.io / github.com** (incidentes/red): reintentar en bucle.
- Si olvidas `overlays_host_path`, el default vacío NO monta overlays → los
  workspaces caen a rol `unknown` sin overlay (visible en logs, no falla en
  silencio contra una ruta inexistente).

---

## FASE 6 — Crear workspace + verificar
- En la web → **Templates → mvp-embedded → Create workspace** → conecta GitHub
  (botón "Login with GitHub") → Create.
- Verifica rol (se estampa en el build):
  ```bash
  docker inspect coder-<usuario>-<ws> -f '{{ index .Config.Labels "coder.com/role" }}'
  ```
- Dentro del workspace verás **3 apps**: VS Code, **Claude Code (CLI)**, **GitHub Copilot (CLI)**.
- Capacidades por rol (ambos asistentes cargan los mismos overlays):
  ```bash
  claude mcp list                 # github + atlassian (+ playwright en qa)
  copilot mcp list                # idem (Copilot)
  copilot skill list              # skills del rol
  copilot --model claude-sonnet-5 # requiere seat Copilot + modelo habilitado (Fase 2d)
  ```

---

## FASE 7 — HTTPS delante de Coder (Caddy + CA self-signed)

Para quitar el aviso de code-server *"insecure context"* (clipboard/webviews
rotos por HTTP a una IP de LAN) se puso Caddy delante de Coder con un
certificado self-signed, y los workspaces se configuraron para confiar en
esa CA. Procedimiento completo, con los gotchas reales que salieron en el
camino: **[docs/RUNBOOK-https-caddy.md](./RUNBOOK-https-caddy.md)**.

Tras esa fase, `CODER_ACCESS_URL` pasa a ser `https://192.168.50.208:3000` —
hay que actualizar la *Authorization callback URL* de la OAuth App (Fase 2b)
a `https://` o el login se rompe.

---

## FASE 8 — Solo acceso web (ocultar SSH/VS Code Desktop)

En `coder_agent.main` (`templates/mvp-embedded/main.tf`) se agregó un bloque
`display_apps` para ocultar los botones nativos del dashboard que dependen
del túnel SSH:
```hcl
display_apps {
  vscode                 = false  # VS Code Desktop (app local vía SSH)
  vscode_insiders        = false
  web_terminal           = false  # "Terminal" genérico del dashboard
  ssh_helper             = false  # instrucciones de `coder config-ssh`
  port_forwarding_helper = false
}
```
Quedan solo: **VS Code Web** (code-server, `coder_app.vscode`) y las
terminales propias **Claude Code**/**Copilot CLI** (ttyd, HTTP).

⚠️ **Esto es solo UI.** No existe un flag de Coder OSS para bloquear
`coder ssh <workspace>` a nivel servidor — el mismo túnel del agente es la
base de VS Code Web, así que no se puede "apagar SSH" sin romper todo lo
demás. Si se necesita un bloqueo real, es un tema de RBAC/red, no de template.

---

## GOTCHAS que ya resolvimos (referencia rápida)
| Síntoma | Causa | Fix |
|---|---|---|
| `rbac: forbidden` al push | usuario sin rol admin | dar `owner` en BD (Fase 4) |
| workspace no crea: `docker.sock permission denied` | server --user arrancó antes del grupo docker | `sudo reboot` (linger lo revive con el grupo) |
| `mkdir: Permission denied` en el home | home quedó de UID 700 (lo tocó un contenedor) | `sudo chown -R dev-ia:dev-ia /home/dev-ia` |
| Coder no arranca: `migration 585` | BD creada por versión más nueva | instalación nueva con embebido: `rm -rf ~/.config/coderv2/postgres`; **en la VM actual la BD es `coder-db`**, no borrar nada |
| workspaces `Started` pero `HEALTHY false` tras cambiar de red | `CODER_ACCESS_URL` apunta a una IP que la VM ya no tiene; el agente no puede bajar su binario | `CODER_ACCESS_URL` en la IP pública + `coder restart` de los workspaces (FASE 4); el workaround `coder-access-ip.service` quedó desactivado — ver [`RUNBOOK-vm-portainer-red.md`](RUNBOOK-vm-portainer-red.md) |
| desde afuera: `TLS alert, internal error (592)` | visitante sin SNI llega por una IP LAN que no está en el Caddyfile | `caddy-lan-ip.timer` regenera el Caddyfile con la IP actual — mismo runbook |
| rol = `unknown` | incidente GitHub (API 500) o falta GitHub App | reintentar con GitHub estable; revisar GITHUB_APP_* |
| rol = `unknown` aunque el GitHub App esté bien | el usuario **renombró su cuenta de GitHub** y Coder sigue con el username viejo cacheado (no se auto-sincroniza) | `PUT /api/v2/users/{id}/profile {"username": "<nuevo>"}` + `coder update` del workspace |
| Atlassian external-auth no acepta callback | Atlassian exige **https** (no http/IP) | dejar Jira para Fase 2 (dominio+TLS); está `optional` |
| Atlassian external-auth "funciona" en logs pero el login real falla | `CODER_EXTERNAL_AUTH_1_CLIENT_ID/SECRET` quedaron en `CHANGE_ME` (nunca se configuró la OAuth App real) | crear la OAuth App de Atlassian y poner credenciales reales |
| banner "External Auth Providers... Enterprise feature" | Coder OSS solo permite **1** external-auth provider; tenemos 2 (github+atlassian) | ignorar si sigue funcionando, o reducir a 1, o licencia Enterprise |
| Logo/banner/nombre de app custom no se guardan (`PUT /api/v2/appearance` responde 200 pero el `GET` sigue vacío) | Branding/Appearance es feature **Enterprise**; se aplica el no-op silencioso sin avisar | requiere licencia Enterprise; no hay workaround limpio en OSS |
| `GH_TOKEN`/`GITHUB_TOKEN` presentes pero `copilot` dice "no autenticado" | GitHub Copilot CLI solo acepta tokens de 3 orígenes (fine-grained PAT con "Copilot Requests", OAuth de la app oficial Copilot CLI, u OAuth de `gh`) — un token de una OAuth App custom no cuenta | `/login` manual una vez dentro de `copilot` (persiste en `~/.copilot/`, volumen home), o PAT fine-grained como `COPILOT_GITHUB_TOKEN` para auto-login |
| `docker exec`/`/proc/1/environ` no muestran las env vars de `coder_agent.env` | esas vars las inyecta el **agente** a sus procesos hijos (ttyd, SSH), no al proceso PID1 original del entrypoint | chequear en el proceso real (ej. `/proc/<pid-de-ttyd>/environ`), no en una shell fría de `docker exec` |
| `coder restart` no aplica cambios de una plantilla nueva | reconstruye con la versión YA asignada al workspace, no la última activa | usar `coder update <owner>/<ws>` |
| no sale Sonnet 5 / Copilot CLI sin acceso | el usuario no está en un team de rol con seat / modelo no habilitado / *Copilot in the CLI* sin habilitar | agregarlo al team de rol, habilitar modelo y CLI (Fase 2d) |
| app *Claude Code (CLI)* / *GitHub Copilot (CLI)* abre solo una terminal bash; `claude --version` → *"native binary not installed"*, `copilot --version` → *"no platform package found"* | al (re)crear el contenedor, `npm install -g` no bajó el paquete nativo opcional (`…-linux-x64`, ~100 MB; corte de red) y salió con exit 0; ttyd hace `(claude \|\| bash)` | en el workspace: `sudo npm install -g @anthropic-ai/claude-code @github/copilot`. Desde `npm-cli-guard-1318` el template valida `--version` y reinstala hasta 3 veces (log en `/tmp/<bin>-install.log`) |
| Copilot CLI: *"Third-party MCP servers are disabled by your organization's Copilot policy"* | policy *MCP servers in Copilot* deshabilitada (o recién habilitada: el CLI tarda ~30 min en tomarla) | habilitarla (Fase 2d); verificar con `gh api` a `copilot_internal/user` → `is_mcp_enabled: true`; si sigue, `copilot logout && copilot login` en el workspace |

---

## FASE 9 — Overlays/skills centralizados (repos separados)

El contenido de `overlays/` (persona + MCP config + skills, por equipo) ya
**no vive solo en este repo** — se centralizó en 2 repos propios de la org,
mantenidos por el team `qintess-platform`:

- **[`qintess-platform-agents-overlays`](https://github.com/Qintess-Latam/qintess-platform-agents-overlays)**
  → `<equipo>/{CLAUDE.md, mcp-config.json}`.
- **[`qintess-platform-agents-skills`](https://github.com/Qintess-Latam/qintess-platform-agents-skills)**
  → `skills/<equipo>/...`.

El `main.tf`/`startup_script` **no cambia** — sigue esperando
`<equipo>/{CLAUDE.md,mcp-config.json,skills/}` en una sola carpeta
(`overlays_host_path`). Lo que cambia es **de dónde sale** esa carpeta: en
vez de ser `overlays/` de este repo, ahora es el resultado de combinar los
2 repos de arriba, generado por:

```bash
bash deploy/vm/sync-agent-overlays.sh
```

Este script (en la VM):
1. Clona/actualiza (`git pull`) los 2 repos en `~/.config/coderv2/agents-sources/`.
2. Combina `<equipo>/{CLAUDE.md,mcp-config.json}` (del repo overlays) +
   `skills/<equipo>/` (del repo skills) en `~/.config/coderv2/agents-overlays-synced/`.
3. `overlays_host_path` (var del template) apunta a esa carpeta combinada.

**Por qué sync en el host y no `git clone` dentro de cada workspace:**
reutiliza el patrón ya probado de `overlays_host_path` (bind-mount, sin
credenciales extra dentro de cada workspace), es instantáneo en cada build
(sin el costo de 2 clones de red por arranque), y es resiliente a que
GitHub esté lento/caído justo cuando alguien crea un workspace.

**Flujo para actualizar overlays/skills** (ej. agregar un skill nuevo):
1. Push al repo correspondiente (`agents-overlays` o `agents-skills`).
2. En la VM: `bash deploy/vm/sync-agent-overlays.sh`.
3. `coder update <owner>/<ws>` en los workspaces que deban tomar el cambio
   (no hace falta `coder templates push` — la plantilla no cambió, solo el
   contenido que monta).

> Pendiente a futuro: automatizar el paso 2 con un webhook/Action que
> dispare el sync al hacer push a cualquiera de los 2 repos (mismo concepto
> que el runner self-hosted mencionado para `coder templates push`).

---

## Edición / Licencias (contexto)
- **Coder** corre en **OSS/Community** (gratis). El RBAC por label+overlay NO usa Coder
  Groups (eso sería Premium). Premium solo se necesita para Groups/OIDC-sync, multi-org,
  template ACL, audit, HA.
- **Confirmado Enterprise-gated en OSS** (no alcanza con configurarlo, Coder lo bloquea o
  lo ignora en silencio):
  - **Más de 1 external-auth provider** (tenemos github+atlassian) → banner de aviso,
    pero sigue funcionando. Ver gotcha arriba.
  - **Appearance/branding** (logo, nombre de app, banner de anuncio vía
    `PUT /api/v2/appearance`) → el `PUT` devuelve 200 pero **no persiste** (no-op
    silencioso). No hay workaround limpio sin licencia.
- **GitHub**: `Qintess-Latam` está en **Free** (suficiente para login OAuth + Teams + GitHub
  App). SSO/SAML + SCIM requerirían **GitHub Enterprise** (futuro).
- **Copilot Business** (ya contratado) gobierna modelos; **no es IA ilimitada** (bolsa de
  créditos/mes por usuario). Uso agéntico pesado de Claude → considerar Vertex/Bedrock.
