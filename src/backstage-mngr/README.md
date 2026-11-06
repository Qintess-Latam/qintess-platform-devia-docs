# qintess-platform-backstage-mngr

**mozart**: motor Python (PyGithub + futuro Atlassian SDK) para crear/borrar
repos, crear/borrar teams, y crear secretos de organización en
`Qintess-Latam` — pensado para ser disparado desde **Backstage Software
Templates** (ver `templates/`), no para que cada usuario llame a la API de
GitHub directo.

## Estado actual (qué funciona de verdad, probado contra GitHub real)

| Acción | Estado |
|---|---|
| `create_repo` (con arquetipo: reglas + scaffold) | ✅ Implementado y probado end-to-end |
| `create_team` (con `parent_team` opcional, anidado) | ✅ Implementado y probado end-to-end |
| `delete_repo` (confirmación por nombre exacto) | ⚠️ Implementado, **no probado en vivo** — firma de `Repository.delete()` verificada contra el código fuente de PyGithub, pero no se ejecutó un delete real (requiere scope `delete_repo` que no se pudo autorizar en esta sesión) |
| `delete_team` | ⏳ Pendiente |
| `create_org_secret` | ⏳ Pendiente |
| `reconfigure_repo` (renombrar + reaplicar arquetipo) | ⏳ Pendiente |
| Backstage corriendo con catálogo mínimo (mozart + template create-repo) | ✅ Corriendo en la VM (`https://201.203.104.168:7007`, Caddy+Docker), login GitHub restringido a Qintess-Latam |
| Custom Scaffolder action `mozart:create-repo` (Backstage → mozart) | ✅ Implementada y probada end-to-end desde Backstage con la GitHub App (repo `qintess-platform-cloudflare-reusable-pipeline`, 2026-10-05) |
| Nombre final `<team>-<nombre>-<arquetipo>` con preview en vivo en el form | ✅ 2026-10-05 |
| `branch_flow` + **Rulesets** por rama, reviewers por sub-team (PR #1) | ✅ Implementado (validado offline); en la imagen desplegada desde 2026-10-15. En repos **privados** no aplica por plan Free (ver limitación abajo) |
| Catálogo + login con la GitHub App (sin PAT) | ✅ 2026-10-15 (con el client secret de la App) |

## Arquitectura

```
mozart/                  # Motor Python
├── actions/              create_repo.py (resto: pendiente)
├── archetypes.py         carga archetype.yaml + skeleton de cada arquetipo
├── policy.py             guardrails (nombres válidos, confirmación en deletes)
├── audit.py              log JSONL de cada acción (quién/qué/cuándo/resultado)
├── github_auth.py        GitHub App dedicada > GH_TOKEN > `gh auth token`
└── cli.py                CLI que invoca las acciones (lo llama el action de Backstage)

archetypes/<nombre>/
├── archetype.yaml        topics, branch protection, team permission, required_files
└── skeleton/              archivos iniciales a pushear (soporta {{repo_name}}/{{description}}/{{team}})

templates/<nombre>/template.yaml   # Backstage Software Template (el form que ve el usuario)
```

## Convención de nombre de repo

El nombre final en GitHub es **`<team dueño>-<nombre>-<arquetipo>`**. Ej.:
team `qintess-platform`, nombre `cloudflare-reusable`, arquetipo Pipeline →
`qintess-platform-cloudflare-reusable-pipeline`.

- Lo compone la action `mozart:create-repo`
  (`backstage/packages/backend/src/actions/createRepoAction.ts`) antes de
  llamar a `mozart.cli` — mozart recibe el nombre ya armado.
- El formulario lo muestra en vivo (y en la pantalla de revisión) con el
  campo custom `RepoNamePreview`
  (`backstage/packages/app/src/modules/scaffolder/RepoNamePreview.tsx`).
  Si cambia la regla, cambiarla en los dos lados.

## Arquetipos definidos

Cada `archetype.yaml` define un **`branch_flow`**: la lista de ramas con su
regla, aplicada con la API de **Rulesets** (una por rama). Las ramas que no son
`main` se crean **después** de pushear el skeleton, así nacen con el contenido.

| Arquetipo | Flujo de ramas | Reviews | Checks |
|---|---|---|---|
| **pipeline** (CI/CD) | trunk-based: solo `main` | `main` 1 | `validate-pipeline` |
| **service** (backend/API) | `feature/*` → `integration` → `laboratory` → `main` | 2 → 2 → 3 (CODEOWNERS), `main` solo squash | `build` + `test` |
| **library** (paquete compartido) | ídem service | ídem, más estricto que service: romper una librería afecta a todos sus consumidores | `build` + `test` |

**CODEOWNERS** (service/library) apunta a los sub-teams reales del team dueño:
`@<team>-senior-dev` (global) y `@<team>-repo-admin` (`/.github/`).
`policy.check_subteams_exist()` falla explícito si falta un sub-team (en vez de
dejar una línea de CODEOWNERS que GitHub ignora en silencio). Sin `bypass_actors`:
nadie se salta el ruleset, ni repo-admin.

**Copia vendorizada:** `backstage/mozart/` y `backstage/archetypes/` son copia
de `mozart/` y `archetypes/` (el build de Docker del backend no puede salir de
`backstage/`). Al cambiar uno, copiar al otro y comprobar con
`diff -rq mozart backstage/mozart && diff -rq archetypes backstage/archetypes`.

## ⚠️ Limitación de plan conocida — branch protection en repos privados

`Qintess-Latam` está en **GitHub Free** (con Copilot Business, que no cambia
el plan del org). Tanto el branch protection clásico como los **Rulesets** del
`branch_flow` requieren GitHub **Team/Enterprise** para aplicarse a repos
**privados** (investigado y confirmado — no hay atajo). `create_repo` no falla por esto: crea el repo igual, y devuelve un
`warning` explicando que la protección no se pudo aplicar. Si se necesita
de verdad, hay que subir el plan del org.

## Correr mozart localmente (sin Backstage)

```bash
pip install -r requirements.txt
export GH_TOKEN=$(gh auth token)   # o MOZART_GITHUB_APP_* para la GitHub App real
python -m mozart.cli create-repo \
  --team qintess-platform --name mi-repo-nuevo \
  --description "..." --archetype service

python -m mozart.cli create-team \
  --name mi-team-nuevo --description "..." \
  --privacy closed [--parent-team team-padre]

# delete_repo requiere el scope `delete_repo` en el token (gh auth refresh -s delete_repo),
# distinto de ser admin/owner de la org. La confirmación debe ser EXACTA al nombre.
python -m mozart.cli delete-repo --name mi-repo --confirm mi-repo
```

## Backstage (`backstage/`) — deploy real, con los gotchas que salieron

La app está en `backstage/` (scaffold de `@backstage/create-app`, con nuestros
cambios). Corre en Docker en la VM como stack de **Portainer**, detrás de
Caddy (mismo patrón que Coder: `https://201.203.104.168:7007` → Caddy TLS
self-signed → `127.0.0.1:7008` interno → container).

Orquestación en la VM:

| Qué | Cómo corre | Archivo |
|---|---|---|
| Portainer (`https://201.203.104.168:9443`) | `docker compose` (no se gestiona a sí mismo) | `~/stacks/portainer/docker-compose.yaml` |
| Caddy (`:3000` Coder, `:7007` Backstage, `:9443` Portainer) | stack `caddy` en Portainer, `network_mode: host` | `~/stacks/caddy/docker-compose.yaml` + `~/.config/caddy-coder/Caddyfile` |
| Backstage | stack `backstage` en Portainer | `deploy/docker-compose.yaml` (este repo) |

Todos los servicios publican solo en `127.0.0.1`; el único que escucha
hacia afuera es Caddy. Red docker compartida: `backend` (external,
`docker network create backend`).

**Requiere Node 22/24 y Yarn 4.4.1** — no Node 20. Se construye/corre todo
dentro de contenedores `node:22-bookworm`, nunca se tocó el Node del host.

### Gotchas reales (por si hay que repetir esto)

1. **`yarn install` falla con `got-npm-...patch ENOENT`** — bug conocido de
   `@yarnpkg/core@4.9.2` (publica una dependencia a un patch que no existe
   fuera del propio repo de Yarn). Fix: `"got": "npm:11.8.5"` en
   `resolutions` del `package.json` raíz.
2. **`app-config.production.yaml` pisa todo** — el `Dockerfile` generado por
   el scaffold carga `app-config.yaml` + `app-config.production.yaml`, y
   este último fuerza Postgres, otro puerto, y las ubicaciones de catálogo
   de EJEMPLO (no las nuestras). Para este deploy de un solo proceso/sqlite,
   el `CMD` del Dockerfile se simplificó a cargar solo `app-config.yaml`.
3. **Bind a `0.0.0.0` adentro del container, no `127.0.0.1`** — a diferencia
   de Caddy (que usa `--network host`), el container de Backstage tiene su
   propia red aislada. Bindear `backend.listen.host: 127.0.0.1` ahí adentro
   hace que el `-p 127.0.0.1:7008:7008` de Docker nunca llegue a la app
   (conexión aceptada y reseteada al instante). Docker ya restringe el lado
   del HOST con el `-p`; adentro hay que usar `0.0.0.0`.
4. **Secretos vía `$file:`, no env vars** — para un container con
   `--restart unless-stopped` (persistente), un token en `-e` queda
   consultable para siempre vía `docker inspect`. Se usa el soporte nativo
   de Backstage (`$file: /secrets/archivo`) + un bind-mount de solo lectura
   de `~/.config/backstage/secrets/` (fuera del repo, nunca commiteado).
   Importante: esos archivos tienen que existir también durante
   `yarn build:backend` (se resuelve el config en build-time), no solo en
   runtime.
5. **Guest auth no sirve para esto** — `auth.providers.guest` requiere
   `dangerouslyAllowOutsideDevelopment: true` fuera de dev, y aunque se
   habilite, cualquiera en la red que llegue al puerto opera mozart (crear/
   borrar repos, teams, secretos) sin login ni auditoría real. Se armó un
   **resolver custom de GitHub** (`backstage/packages/backend/src/plugins/custom-github-auth.ts`)
   que solo deja entrar a miembros **activos** de Qintess-Latam — chequeado
   server-side con un token de la GitHub App (no con el scope OAuth del
   usuario, que por default es solo `read:user`, sin `read:org`).
6. **Sin tocar `App.tsx`, el frontend sigue intentando `guest`** — Backstage
   usa el *nuevo* sistema de frontend (`createApp` de
   `@backstage/frontend-defaults`), donde la página de login se configura
   con `SignInPageBlueprint` (no el prop `components.SignInPage` de la docs
   "clásica"). Sin esto, el shell llama a `/api/auth/guest/refresh` (404,
   ya que sacamos ese provider del backend) y todo el resto da 401.

### Correr/reconstruir

```bash
cd backstage
# build (necesita los secretos montados aunque sea solo para resolver el config)
docker run --rm -i -v "$(pwd)":/work -w /work -v ~/.config/backstage/secrets:/secrets:ro \
  node:22-bookworm bash -c "corepack enable && yarn install && yarn tsc && yarn build:backend"
docker build -f packages/backend/Dockerfile -t qintess-backstage:latest .
```

El container corre como stack **`backstage`** de Portainer
(`https://201.203.104.168:9443`), definido en
[`deploy/docker-compose.yaml`](deploy/docker-compose.yaml). Después de un
`docker build`, en Portainer: *Stacks → backstage → Editor → Update the
stack* (sin "pull latest image": la imagen es local). Si se cambia el
compose en el repo, pegarlo en ese mismo editor.

Sin Portainer (equivalente):
`docker compose -f deploy/docker-compose.yaml -p backstage up -d --force-recreate`
— ojo: un stack creado así fuera de Portainer aparece en Portainer como
*limited* (no editable).

Las 3 `MOZART_GITHUB_APP_*` del compose son para mozart (`github_auth.py`);
no son secretas (IDs + una ruta). **No** pasar `GH_TOKEN`/`GITHUB_TOKEN` al
container: `github_auth.py` cae a esos si están, y mozart actuaría con el
token de esa persona en vez de la App.

Secretos esperados en `~/.config/backstage/secrets/` (600, fuera del repo):

| Archivo | Qué es | Lo usa |
|---|---|---|
| `mozart-app.pem` | Private key de la GitHub App `qintess-mozart-bot` | mozart + `integrations.github` (catálogo, login) |
| `mozart-app-client-secret` | Client secret de la misma App (requerido por el schema de Backstage) | `integrations.github` |
| `github-oauth-client-id` / `github-oauth-client-secret` | OAuth App "Qintess Backstage" | login de usuarios |
| `backend-secret` | Random, auth service-to-service | backend |

Ya **no** se usa ningún PAT. `github-token` (PAT fine-grained de la org,
vence 2026-12-31) queda en la VM solo como **plan B**: si la App falla, en
`integrations.github` reemplazar `apps:` por `token: { $file: /secrets/github-token }`
(`custom-github-auth.ts` funciona con cualquiera de los dos) y rebuild.

**Tras cambiar `app-config.yaml` o un secret: rebuild + update del stack en
Portainer.** La config va dentro de la imagen; reiniciar el stack no alcanza.
El callback de la OAuth App de login (`Ov23li6pmECDSrWdcn6d`) es
`https://201.203.104.168:7007/api/auth/github/handler/frame`.

### Verificar lo que corre de verdad (no lo que hay en el repo)

```bash
docker inspect qintess-backstage:latest --format '{{.Id}} {{.Created}}'
docker ps --filter name=qintess-backstage --format 'table {{.Names}}\t{{.Image}}\t{{.CreatedAt}}\t{{.Status}}'
docker inspect qintess-backstage --format '{{.Image}}'          # = Id de la imagen nueva
docker exec qintess-backstage cat /app/app-config.yaml | grep -A1 -E 'cors:|baseUrl:'
docker logs qintess-backstage 2>&1 | grep -E 'Committed .* GitHub users|"level":"error"'
```

### Update del stack por la API de Portainer (equivalente a la UI)

```bash
P=http://127.0.0.1:9000
JWT=$(curl -s -X POST $P/api/auth -H 'Content-Type: application/json' \
  -d "$(jq -n --arg p "$(cat ~/.config/portainer/admin-password)" '{username:"admin",password:$p}')" | jq -r .jwt)
COMPOSE=$(curl -s -H "Authorization: Bearer $JWT" "$P/api/stacks/1/file" | jq -r .StackFileContent)
curl -s -X PUT -H "Authorization: Bearer $JWT" -H 'Content-Type: application/json' \
  "$P/api/stacks/1?endpointId=1" \
  -d "$(jq -n --arg c "$COMPOSE" '{stackFileContent:$c, env:[], prune:false, pullImage:false}')"
```

### Incidente 2026-10-15 — 403 de CORS al pasar a la IP pública

Al entrar por `https://201.203.104.168:7007` el backend respondía
`403 Origin 'https://201.203.104.168:7007' is not allowed`: `app.baseUrl`,
`backend.baseUrl` y `backend.cors.origin` seguían en la IP LAN vieja
(`192.168.50.208`) **dentro de la imagen** (del 2026-10-05). Fix: las 3 URLs a la
IP pública (`6fdd0bb`) → rebuild → update del stack → verificar con los comandos
de arriba. En el mismo rebuild entró a producción el PR #1 de mozart.

Lo que hubo que resolver en el camino:

1. **El build fallaba por un secreto faltante.** `integrations.github.apps`
   exige `clientSecret` aunque para tokens de instalación solo use `appId` +
   `privateKey`; `/secrets/mozart-app-client-secret` no existía. Se generó en la
   App (*Generate a new client secret*; GitHub lo muestra **una sola vez**).
   Validarlo sin exponerlo (correcto → `404` porque el token de prueba no
   existe; incorrecto → `401`):
   ```bash
   curl -s -o /dev/null -w '%{http_code}\n' \
     -u "Iv23lixQLqbBQelmkflg:$(cat ~/.config/backstage/secrets/mozart-app-client-secret)" \
     -X POST https://api.github.com/applications/Iv23lixQLqbBQelmkflg/token \
     -d '{"access_token":"ghu_invalido000000000000000000000000000"}'
   ```
2. **"The redirect_uri is not associated with this application"** en el
   login: el callback se había cambiado en la OAuth App **de Coder**. Hay dos
   OAuth Apps parecidas:

   | OAuth App | Client ID | Callback |
   |---|---|---|
   | **Backstage** (login) | `Ov23li6pmECDSrWdcn6d` | `https://201.203.104.168:7007/api/auth/github/handler/frame` |
   | Coder (login + external-auth) | `Ov23li16XNUEsskKUnC7` | `https://201.203.104.168:3000/` |

   Ver qué `redirect_uri` manda Backstage:
   `curl -sk -o /dev/null -w '%{redirect_url}\n' 'https://201.203.104.168:7007/api/auth/github/start?env=development&scope=read:user'`.
   Login OK en logs: `GET /api/auth/github/handler/frame?code=…` → `200`.
3. **No confundir los `.pem`:** `~/.config/backstage/secrets/mozart-app.pem` es el
   de `qintess-mozart-bot`; `~/.config/coderv2/github-app.pem` es de **otra** App
   (`qintess-latam-rbac-resolver`, la de Coder). De las dos claves de mozart-bot
   descargadas el 2026-10-05, una devolvía `401`: borrarla en la App.

## GitHub App `qintess-mozart-bot`

App dedicada de la org (no reusa `qintess-latam-rbac-resolver`, que es de
solo-lectura). Es la **única** credencial de GitHub del backend: la usan
mozart (crear repos/teams/secretos) y Backstage (catálogo + chequeo de
membership en el login). Fuera de este repo también la usan, en la misma VM:
la administración de teams (altas en teams de rol) y el timer de **gasto de
Copilot** de Coder (`copilot-spend.sh`, lee la API de billing de premium
requests por usuario — ver `qintess-platform-coder-template`,
`docs/RUNBOOK-plantillas-por-rol.md`). Todo lo que hace aparece en GitHub como
`qintess-mozart-bot[bot]`, con tokens de instalación de 1h.

| Dato | Valor |
|---|---|
| App ID | `5202581` |
| Client ID | `Iv23lixQLqbBQelmkflg` |
| Installation ID (Qintess-Latam, all repos) | `168285622` |

Permisos de la instalación:

| Permiso | Nivel | Para qué |
|---|---|---|
| Administration (repo) | RW | crear repos, branch protection, permisos de team |
| Contents | RW | pushear el skeleton del arquetipo; leer `catalog-info`/`template.yaml` |
| **Workflows** | RW | pushear `.github/workflows/*` del skeleton — sin esto: `403 Resource not accessible by integration` |
| Secrets / Organization secrets | RW | `create_org_secret` |
| Members | RW | teams + ingesta `githubOrg` + chequeo de login |
| Organization administration | RW | — |

Agregar un permiso en la App no aplica hasta que un owner de la org acepte
el cambio (Org Settings → GitHub Apps → qintess-mozart-bot → Review request).

**Límite:** la App **no** puede asignar seats de Copilot (`422 "Inviting User is
not an admin of the Organization"`): eso lo hace un owner (UI o `gh` con
`manage_billing:copilot`).

**Rotar la private key:** generar una nueva en la App, reemplazar
`~/.config/backstage/secrets/mozart-app.pem` (600), recrear el container,
y recién ahí borrar la key vieja en GitHub.
