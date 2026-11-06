# RUNBOOK — Portainer, PostgreSQL en Docker y cambios de IP de la VM

> Paso a paso REAL de lo que se hizo en la VM (`dev-ia`, una notebook HP
> Dragonfly que cambia de red) entre el 2026-10-05 y el 2026-10-15:
>
> 1. Orquestar Caddy, Backstage y la BD de Coder desde **Portainer**.
> 2. Mover la BD de Coder del **Postgres embebido** a un **PostgreSQL en Docker**.
> 3. Que Coder siga funcionando cuando **cambia la IP de la VM** (TLS de Caddy +
>    agentes de los workspaces).
> 4. Exponer Coder **públicamente por IP** (`https://201.203.104.168:3000`).
> 5. Backstage (Symphony) en la IP pública (`https://201.203.104.168:7007`).
> 6. Upgrade de Coder a v2.37.4 y CA de Caddy en el trust store del host.
>
> Complementa a [`RUNBOOK-https-caddy.md`](RUNBOOK-https-caddy.md) (cómo se armó
> Caddy) y [`RUNBOOK-vm-qintess-latam.md`](RUNBOOK-vm-qintess-latam.md) (deploy
> de la VM). Los archivos de esta guía están versionados en `deploy/vm/`.

---

## Resultado final (qué queda corriendo)

| Servicio | Cómo corre | Expuesto | Archivos |
|---|---|---|---|
| **Portainer** `portainer-ce:2.19.4-alpine` | `docker compose` (no se gestiona a sí mismo) | `127.0.0.1:9000` → Caddy `:9443` | `deploy/vm/stacks/portainer/` (en la VM: `~/stacks/portainer/`) |
| **Caddy** `caddy:2` | stack `caddy` en Portainer, `network_mode: host` | `:3000` Coder, `:7007` Backstage, `:9443` Portainer | `deploy/vm/stacks/caddy/` + `deploy/vm/caddy/` |
| **PostgreSQL de Coder** `postgres:17-alpine` | stack `coder-db` en Portainer | `127.0.0.1:5432` | `deploy/vm/stacks/coder-db/` |
| **Backstage** | stack `backstage` en Portainer | `127.0.0.1:7008` → Caddy `:7007` | repo `qintess-platform-backstage-mngr`, `deploy/docker-compose.yaml` |
| **Coder** | `systemd --user` `coder.service` (en el host) | `127.0.0.1:3001` → Caddy `:3000`; **`CODER_ACCESS_URL=https://201.203.104.168:3000`** | `~/.config/coderv2/server.env` |
| **Render del Caddyfile** | `systemd --user` `caddy-lan-ip.timer` (cada 1 min) | — | `deploy/vm/caddy/sync-lan-ip.sh`, `deploy/vm/systemd/caddy-lan-ip.*` — sin efecto desde FASE 4 (la plantilla ya no usa `__LAN__`) |
| **IP `192.168.50.208` en `lo`** | `systemd` (sistema) `coder-access-ip.service` | `192.168.50.208/32` en `lo` | `deploy/vm/systemd/coder-access-ip.service` — **desactivado 2026-10-15** (`disabled`/`inactive`); se conserva el unit file por si hace falta volver |
| **Backups de `coder-db`** | `systemd --user` `coder-db-backup.timer` (diario 03:00) | — | `deploy/vm/coder-db/backup-coder-db.sh`, `deploy/vm/systemd/coder-db-backup.*` |

Todos los servicios publican solo en `127.0.0.1`; el único que escucha hacia
afuera es Caddy. Red docker compartida: `backend` (external).

---

## FASE 1 — Portainer detrás de Caddy

Base: [`JuanParraIV/docker-tools/portainer/docker-compose.yaml`](https://github.com/JuanParraIV/docker-tools/blob/master/portainer/docker-compose.yaml),
adaptado a esta VM:

- **Sin labels de Traefik** — acá el proxy es Caddy.
- **Solo `127.0.0.1:9000`** publicado (HTTP). No se publican `9443` (lo usa
  Caddy) ni `8000` (Edge agent, no se usa).
- Imagen `2.19.4-alpine` (la del compose original). Funciona con Docker 29
  (API mínima 1.40), pero es de 2023: conviene actualizarla.

```bash
docker network create backend
docker compose -f ~/stacks/portainer/docker-compose.yaml -p portainer up -d
```

Caddyfile (ahora vía plantilla, ver FASE 3):
```caddyfile
192.168.50.208:9443, __LAN__:9443, localhost:9443, 127.0.0.1:9443 {
	tls internal
	reverse_proxy 127.0.0.1:9000
}
```

**GOTCHA — Portainer se bloquea si no se crea el admin en 5 minutos.** Por eso
se inicializó en el mismo paso por API (`POST /api/users/admin/init`) con una
password aleatoria guardada en `~/.config/portainer/admin-password` (600).
Usuario `admin`. **Cambiarla** desde la UI (*admin → My account*) y después
borrar ese archivo.

Luego, por API: environment local (`POST /api/endpoints`, `EndpointCreationType=1`)
y los stacks (`POST /api/stacks/create/standalone/string?endpointId=1`).

### Migrar un container existente a stack de Portainer

Para Caddy y Backstage (ya corrían con `docker run`):

1. `docker rm -f <container>` (unos segundos de corte).
2. Crear el stack en Portainer con el **mismo `container_name`** y los mismos
   volúmenes/puertos.
3. Para Caddy se preparó **rollback en el mismo comando**: si la creación del
   stack fallaba, se relanzaba el `docker run` original (Caddy expone Coder;
   no puede quedar caído).

**Caddy conserva sus volúmenes** (`caddy_coder_data`, `caddy_coder_config`,
declarados `external`): ahí vive la CA interna. Perderlos = CA nueva = los
navegadores y workspaces dejan de confiar en el cert.

**Contenedores levantados con `docker compose` fuera de Portainer** aparecen en
Portainer como *limited* (no editables). Para que se puedan editar desde la UI,
el stack se tiene que crear desde Portainer.

---

## FASE 2 — Base de datos de Coder: del Postgres embebido a Docker

### Situación inicial

`coder server` levantaba su **Postgres embebido** (PG 13.21) como proceso hijo:
binario en `~/.config/coderv2/postgres/bin/`, datos en `.../postgres/data`
(~84 MB), puerto 44969. Sin `CODER_PG_CONNECTION_URL`.

### Preparación (sin tocar Coder)

1. Credenciales:
   - `~/.config/coder-db/pg-password` — dueño **uid 70**, modo `400`.
   - `~/.config/coder-db/connection-url` — URL completa para Coder (600).

   **GOTCHA — `POSTGRES_PASSWORD_FILE` y permisos.** El entrypoint de la imagen
   oficial lee el archivo **ya como usuario `postgres`** (uid 70 en alpine), no
   como root. Un archivo `600` de `dev-ia` da *permission denied*. Fix sin sudo:
   ```bash
   docker run --rm -v ~/.config/coder-db:/d alpine \
     sh -c 'chown 70:70 /d/pg-password && chmod 400 /d/pg-password'
   ```
2. Stack `coder-db` en Portainer (`deploy/vm/stacks/coder-db/docker-compose.yaml`):
   `postgres:17-alpine`, volumen `coder-db-data`, `127.0.0.1:5432`, healthcheck
   `pg_isready`.
3. **Restore de prueba** con un dump de la BD viva → conteos idénticos en
   `users`, `workspaces`, `template_versions`, `workspace_builds`,
   `workspace_agents`, y misma migración (`schema_migrations` = 535).

**GOTCHA — el Postgres embebido NO trae `pg_dump`** (solo `initdb`, `pg_ctl`,
`postgres`). Se usa el de la imagen (pg_dump 17 lee un server 13):
```bash
SRC=$(coder server postgres-builtin-url | grep -o 'postgres://[^" ]*')
docker run --rm -i --network host postgres:17-alpine \
  pg_dump -Fc --no-owner --no-acl -d "$SRC" > coder.dump
```

### Cutover (~2-3 min sin acceso a Coder; los containers de workspace siguen vivos)

1. Vaciar `coder-db` (tenía los datos de la prueba):
   `DROP DATABASE coder WITH (FORCE); CREATE DATABASE coder OWNER coder`.
2. `systemctl --user stop coder` — **esto también apaga el Postgres embebido**.
3. Levantar el embebido a mano solo para el dump final:
   ```bash
   P=~/.config/coderv2/postgres
   $P/bin/bin/pg_ctl -D $P/data -o "-p 44969" -l /tmp/embedded-pg.log -w start
   # dump con postgres:17-alpine (ver arriba), usando la password de $P/password
   $P/bin/bin/pg_ctl -D $P/data stop -m fast -w
   ```
4. `pg_restore` en `coder-db` y comparar conteos origen/destino.
5. Agregar a `~/.config/coderv2/server.env` (con backup previo):
   ```bash
   export CODER_PG_CONNECTION_URL="postgres://coder:<pass>@127.0.0.1:5432/coder?sslmode=disable"
   ```
6. `systemctl --user start coder` y esperar `/healthz` = 200.

Todo en un script con `trap ERR` → **rollback automático**: restaura el
`server.env` original y arranca Coder sobre el embebido (que nunca se modifica).

Resultado (2026-10-06): conteos idénticos (3 users, 2 workspaces, 13 template
versions, 48 builds, 38 agents), Coder healthy en ~4 s, workspaces reconectados.

### Rollback (si hiciera falta)

```bash
cp ~/.config/coderv2/server.env.bak.<timestamp> ~/.config/coderv2/server.env
systemctl --user restart coder     # vuelve al Postgres embebido
```
El embebido tiene los datos **al momento del cutover** — no borrar
`~/.config/coderv2/postgres/` hasta estar seguros.

### Backups automáticos

`coder-db-backup.timer` (`systemd --user`) corre todos los días a las **03:00**
(`Persistent=true`: si la notebook estaba apagada, corre al prender) el script
`~/.config/coder-db/backup-coder-db.sh` (`deploy/vm/coder-db/backup-coder-db.sh`):

1. `pg_dump -Fc` dentro del container → `~/.config/coder-db/backups/coder-YYYYmmdd-HHMMSS.dump` (700/600).
2. **Verifica** el dump con `pg_restore --list` antes de darlo por bueno (se escribe a `.tmp` y recién ahí se renombra).
3. **Rotación:** últimos **14 días** + los de **domingo** hasta **8 semanas**
   (`KEEP_DAYS`/`KEEP_WEEKS`). Solo toca archivos `coder-<fecha>-<hora>.dump`;
   el dump del cutover (`coder-embedded-20261006-192357.dump`) no se rota.

Tamaño: ~2 MB por dump (2026-10-09).

```bash
# instalación en una VM nueva
install -m 755 deploy/vm/coder-db/backup-coder-db.sh ~/.config/coder-db/
cp deploy/vm/systemd/coder-db-backup.{service,timer} ~/.config/systemd/user/
systemctl --user daemon-reload && systemctl --user enable --now coder-db-backup.timer

# estado / backup a mano / último resultado
systemctl --user list-timers coder-db-backup.timer
systemctl --user start coder-db-backup.service
journalctl --user -u coder-db-backup.service -n 5 --no-pager -o cat
```

**Restaurar un backup** (con Coder parado):
```bash
systemctl --user stop coder
docker exec coder-db psql -U coder -d postgres \
  -c 'DROP DATABASE coder WITH (FORCE)' -c 'CREATE DATABASE coder OWNER coder'
docker exec -i coder-db pg_restore -U coder -d coder --no-owner --exit-on-error \
  < ~/.config/coder-db/backups/coder-<fecha>-<hora>.dump
systemctl --user start coder
```
Probado el 2026-10-09 sobre una BD temporal (`restore_test`): conteos idénticos a producción.

**Los backups quedan en el mismo disco que la VM.** Protegen contra borrar el
volumen o corromper la BD, no contra perder la notebook. Pendiente: copia
fuera de la VM.

### Owner de emergencia (reemplaza la receta con `postgres-builtin-url`)

```bash
docker exec coder-db psql -U coder -d coder \
  -c "UPDATE users SET rbac_roles='{owner}' WHERE username='<tu-usuario>';"
```

---

## FASE 3 — La VM cambia de IP

### Incidente (2026-10-09)

La VM es una notebook: pasó de la red `192.168.50.x` a la `192.168.100.x`
(Wi-Fi `wlp0s20f3`, IP `192.168.100.100`). Dos problemas distintos:

| Hora (UTC) | Evento |
|---|---|
| 16:32 | Coder pierde la conexión con los 2 agentes (`connection to agent timed out`): la VM deja la red `.50.x` |
| 18:35 | Reboot de la notebook; todos los containers arrancan solos |
| desde ahí | Los workspaces quedan `Started` pero `HEALTHY false`: el init intenta bajar el agente de `https://192.168.50.208:3000/bin/coder-linux-amd64` — **esa IP ya no existe** — y reintenta para siempre |
| — | Desde afuera (port forwarding del router al `:3000`), el handshake TLS falla: `TLS alert, internal error (592)` / `0A000438` |

### Problema 1 — TLS: Caddy sin certificado para la IP nueva

**GOTCHA 1 (variante "sin SNI").** Un navegador o `curl` que se conecta a una
**IP** **no manda SNI** (el SNI solo admite nombres DNS). En ese caso Caddy
elige el certificado por **la IP local por la que entró la conexión**. Con port
forwarding, esa es la IP de la VM en la LAN — no la pública. Si no está en el
Caddyfile → `internal error`.

Consecuencias:
- Agregar la **IP pública** (`201.203.104.168:3000`) solo sirve a clientes que
  la mandan como SNI a propósito (`openssl -servername`). Se dejó, pero **no
  arregla** a los visitantes reales.
- **Esta prueba NO sirve**, da 200 aunque el problema exista (curl no manda SNI
  y entra por `127.0.0.1`, que ya está listada):
  ```bash
  curl -sk --resolve 201.203.104.168:3000:127.0.0.1 https://201.203.104.168:3000/healthz
  ```
  **Pruebas correctas:**
  ```bash
  # visitante real: sin SNI, entrando por la IP LAN actual de la VM
  curl -sk -o /dev/null -w '%{http_code}\n' https://<IP-LAN-actual>:3000/healthz
  # cliente que manda una IP como SNI
  echo | openssl s_client -connect 127.0.0.1:3000 -servername 201.203.104.168 2>&1 | grep -E 'alert|issuer='
  ```

**Fix permanente: el Caddyfile se genera solo con las IPs actuales.**

- `~/.config/caddy-coder/Caddyfile.tmpl` (`deploy/vm/caddy/Caddyfile.tmpl`) —
  **se edita ESTE archivo**. `__LAN__:<puerto>` se reemplaza por las IPv4
  actuales de la VM (sin `docker*`, `br-*`, `veth*`, `virbr*`).
  `192.168.50.208` queda fija (es la de `CODER_ACCESS_URL`).
- `~/.config/caddy-coder/sync-lan-ip.sh` — renderiza; si cambió algo, valida
  con `caddy validate`, guarda `Caddyfile.prev` y hace `caddy reload` (sin
  reiniciar el container). Si no cambió nada, no hace nada.
- `caddy-lan-ip.timer` (`systemd --user`, linger activo) — lo corre cada minuto.

**`Caddyfile` ya no se edita a mano**: se sobreescribe.

**GOTCHA — escribir el Caddyfile in-place, nunca con `mv`.** El Caddyfile está
bind-montado **como archivo** en el container. Reemplazarlo con `mv` (inodo
nuevo) deja al container viendo el archivo viejo. El script escribe con
`printf > Caddyfile` (mismo inodo).

Instalación en una VM nueva:
```bash
cp deploy/vm/caddy/{Caddyfile.tmpl,sync-lan-ip.sh} ~/.config/caddy-coder/
chmod 755 ~/.config/caddy-coder/sync-lan-ip.sh
cp deploy/vm/systemd/caddy-lan-ip.{service,timer} ~/.config/systemd/user/
systemctl --user daemon-reload && systemctl --user enable --now caddy-lan-ip.timer
```

### Problema 2 — agentes: `CODER_ACCESS_URL` apunta a una IP que ya no existe

`CODER_ACCESS_URL=https://192.168.50.208:3000`. Los agentes de los workspaces
se conectan (y bajan su binario) desde esa URL. Fuera de la red `.50.x` no
existe → agentes caídos.

**Workaround: la IP `192.168.50.208/32` siempre presente en `lo`.** Los
containers llegan al host por `docker0` y el host acepta tráfico a cualquier IP
local, así que `https://192.168.50.208:3000` vuelve a responder desde los
workspaces, en cualquier red. Los agentes se recuperan solos en el siguiente
reintento — **no hace falta `coder update`**.

Contra: en una red donde otro equipo tenga de verdad `192.168.50.208`, la VM no
podría llegar a ese equipo.

Persistente con un servicio de sistema (`deploy/vm/systemd/coder-access-ip.service`):
```bash
sudo install -m 644 deploy/vm/systemd/coder-access-ip.service /etc/systemd/system/coder-access-ip.service
sudo systemctl daemon-reload
sudo systemctl enable --now coder-access-ip.service
```
Verificación:
```bash
systemctl is-enabled coder-access-ip.service   # enabled
systemctl is-active coder-access-ip.service    # active
ip -4 addr show lo | grep 192.168.50.208
coder list -a                                  # HEALTHY true
```

**GOTCHA — `sudo` encadenado desde la terminal de Claude Code (`! cmd`).** Con
varios `sudo` unidos por `&&`, **solo corrió el primero** (el journal muestra un
solo `sudo[...]: COMMAND=...` por intento). Correr cada `sudo` en una línea
separada.

**GOTCHA — no copiar comandos abreviados.** Una línea con `printf … | sudo tee`
(con `…` literal) dejó el unit file con solo ese carácter → `LoadState=bad-setting`,
`UnitFileState=static`. Mejor dejar el unit file listo en disco y copiarlo con
`sudo install`.

Este workaround dejó de ser necesario con la FASE 4 (los agentes ya usan la
IP pública). **Desactivado el 2026-10-15:**

```bash
sudo systemctl disable --now coder-access-ip.service
systemctl is-enabled coder-access-ip.service   # disabled
systemctl is-active coder-access-ip.service    # inactive
ip -4 addr show lo                             # solo 127.0.0.1/8
coder list -a                                  # los 2 workspaces HEALTHY true
```

El unit file queda en `/etc/systemd/system/` (sin enlace en
`multi-user.target.wants`); para volver: `sudo systemctl enable --now
coder-access-ip.service`.

**GOTCHA — `sudo` desde el prefijo `!` de Claude Code** falla con `sudo: A
terminal is required to authenticate` si no hay credenciales cacheadas: correr
el comando en una terminal propia de la VM.

---

## FASE 4 — Acceso público por IP (`https://201.203.104.168:3000`)

**Decisión (2026-10-09):** IP pública "pelada", sin dominio por ahora,
asumiendo el riesgo de NAT loopback para quien esté en la misma LAN. El port
forwarding del router (puerto público `3000` → VM `:3000`) lo configuró otra
persona, fuera de este repo.

### Paso 1 — Caddy: que todo lo que entra por el router reciba el cert de la IP pública

Agregar `201.203.104.168:3000` a la lista de hosts **no alcanzaba**. Prueba que
lo mostró (desde los containers de workspace, por NAT loopback):
```
curl https://201.203.104.168:3000/healthz
→ SSL: no alternative certificate subject name matches target ipv4 address '201.203.104.168'
```
Sin SNI, Caddy elige el cert por **la IP local** de la conexión (la IP LAN de
la VM, tanto para visitantes externos como para el hairpin) y recién **si no
tiene cert para esa IP** usa `default_sni`. Probado con un Caddy temporal en
otro puerto:

| Config | Cert servido sin SNI por la IP LAN |
|---|---|
| solo `default_sni 201.203.104.168` | `192.168.100.100` ❌ (gana la IP local) |
| `default_sni` + sacar la IP LAN del bloque `:3000` | `192.168.100.100` ❌ (el **cache de certs es global**: otro bloque todavía la lista) |
| `default_sni` + sacar la IP LAN de **todos** los bloques | `201.203.104.168` ✅ |

Plantilla final (`deploy/vm/caddy/Caddyfile.tmpl`):
```caddyfile
{
	default_sni 201.203.104.168
}

192.168.50.208:3000, localhost:3000, 127.0.0.1:3000, 201.203.104.168:3000 {
	tls internal
	reverse_proxy 127.0.0.1:3001
}
# ídem :7007 (Backstage) y :9443 (Portainer), con 201.203.104.168 agregada
```
`127.0.0.1`, `localhost` y `192.168.50.208` (en `lo`) siguen listadas: son
IPs locales y conservan su propio cert.

Consecuencia: quien entre **por la IP LAN** (`192.168.100.x`) recibe el cert de
la IP pública → advertencia de nombre en el navegador. Desde la LAN también se
usa la IP pública (NAT loopback).

### Paso 2 — GitHub OAuth App: callback nuevo ANTES de tocar Coder

Login y external-auth de GitHub usan la **misma OAuth App** (`Ov23…`), y una
OAuth App acepta **un solo** callback. GitHub → Developer settings → OAuth
Apps → la app de Coder → *Authorization callback URL*:
```
https://201.203.104.168:3000
```
Solo la raíz: GitHub acepta cualquier subpath, así que cubre
`/api/v2/users/oauth2/github/callback` y `/external-auth/github/callback`.

Entre este paso y el 3, el login falla con `redirect_uri` no válido: Coder sigue
mandando el callback viejo. Hacer los pasos 2 y 3 juntos.

### Paso 3 — `CODER_ACCESS_URL` y restart

```bash
cp ~/.config/coderv2/server.env ~/.config/coderv2/server.env.bak.$(date +%s)
sed -i 's#^export CODER_ACCESS_URL=.*#export CODER_ACCESS_URL="https://201.203.104.168:3000"#' ~/.config/coderv2/server.env
systemctl --user restart coder
```
Verificar que **tomó el valor nuevo** (no asumirlo):
```bash
systemctl --user show coder -p ActiveEnterTimestamp     # hora del restart
journalctl --user -u coder -n 50 --no-pager | grep 201.203.104.168   # banner de arranque
curl -sk -o /dev/null -w '%{redirect_url}\n' https://127.0.0.1:3000/api/v2/users/oauth2/github/callback \
  | grep -o 'redirect_uri=[^&]*'                          # debe tener 201.203.104.168
```

### Paso 4 — Workspaces: que el agente tome la URL nueva

La URL del agente (`CODER_AGENT_URL`) se fija **en cada build**. Hace falta un
build nuevo de cada workspace:

- workspace **desactualizado** → `coder update <owner>/<ws>` (build con la versión activa).
- workspace **ya en la versión activa** → `coder update` **no hace nada** (no
  crea build, no imprime nada) y el agente se queda con la URL vieja. Usar
  `coder restart <owner>/<ws> --yes` (stop + start = build nuevo).

Verificación por workspace:
```bash
docker exec coder-<owner>-<ws> sh -c \
  'tr "\0" "\n" < /proc/$(pgrep -f "coder agent" | head -1)/environ | grep ^CODER_AGENT_URL'
# → CODER_AGENT_URL=https://201.203.104.168:3000/
coder list -a      # HEALTHY true
```

Resultado (2026-10-09 14:10): los 2 workspaces `HEALTHY true` con
`CODER_AGENT_URL=https://201.203.104.168:3000/`.

### Si cambia la IP pública

Todo lo anterior depende de `201.203.104.168`: si el ISP la cambia, hay que
repetir los pasos 1-4 con la IP nueva. La solución estable es un **nombre DNS**
(subdominio apuntando a la IP pública), que además permite un cert real de
Let's Encrypt en vez de `tls internal`.

---

## FASE 5 — Backstage (Symphony) en la IP pública (`https://201.203.104.168:7007`)

### Síntoma (2026-10-15)

Caddy ya servía `:7007` con el cert de la IP pública (FASE 4, paso 1), pero al
entrar por `https://201.203.104.168:7007` el backend respondía:

```
403 Origin 'https://201.203.104.168:7007' is not allowed
```

Causa: `app.baseUrl`, `backend.baseUrl` y `backend.cors.origin` de
`backstage/app-config.yaml` seguían en `https://192.168.50.208:7007`. El
contenedor corría una imagen del 2026-10-05.

**GOTCHA — la config va DENTRO de la imagen.** `app-config.yaml` se resuelve en
`yarn build:backend` y se copia a la imagen (`packages/backend/Dockerfile`).
Editar el archivo y reiniciar el stack no cambia nada: hay que **rebuild +
redeploy**. Verificar siempre lo que corre, no lo que hay en el repo:

```bash
docker inspect qintess-backstage:latest --format '{{.Id}} {{.Created}}'
docker ps --filter name=qintess-backstage --format 'table {{.Names}}\t{{.Image}}\t{{.CreatedAt}}\t{{.Status}}'
docker exec qintess-backstage cat /app/app-config.yaml | grep -A1 -E 'cors:|baseUrl:'
```

### Paso 1 — `app-config.yaml` (repo `qintess-platform-backstage-mngr`)

Las 3 URLs a `https://201.203.104.168:7007` (commit `6fdd0bb`). Se edita solo
en el clon de la VM (`~/repos/qintess-platform-backstage-mngr`).

### Paso 2 — Secrets que el build necesita

**GOTCHA — todo `$file:` de `app-config.yaml` tiene que existir en el build**
(se monta `~/.config/backstage/secrets` en `/secrets`), no solo en runtime. Si
falta uno, `yarn build:backend` falla.

`integrations.github` usa la GitHub App `qintess-mozart-bot` (App ID
`5202581`, Client ID `Iv23lixQLqbBQelmkflg`), y el schema de Backstage exige
`clientSecret` además del `.pem`, aunque para tokens de instalación solo se
usen `appId` + `privateKey`. El client secret no estaba en la VM; se generó uno
nuevo en GitHub (App → *Generate a new client secret*).

| Archivo en `~/.config/backstage/secrets/` (600, **NO va a git**) | Qué es |
|---|---|
| `backend-secret` | `backend.auth.keys` |
| `github-oauth-client-id` / `github-oauth-client-secret` | OAuth App **de login** de Backstage (`Ov23li6pmECDSrWdcn6d`) |
| `mozart-app.pem` | clave privada de `qintess-mozart-bot` (Backstage + mozart) |
| `mozart-app-client-secret` | client secret de `qintess-mozart-bot` (solo para el schema) |
| `github-token` | PAT fine-grained de la org (vence 2026-12-31). **Fallback**: hoy sin uso |

Validar el client secret sin exponerlo (con credenciales correctas GitHub
responde `404` porque el token de prueba no existe; con incorrectas, `401`):

```bash
curl -s -o /dev/null -w '%{http_code}\n' \
  -u "Iv23lixQLqbBQelmkflg:$(cat ~/.config/backstage/secrets/mozart-app-client-secret)" \
  -X POST https://api.github.com/applications/Iv23lixQLqbBQelmkflg/token \
  -d '{"access_token":"ghu_invalido000000000000000000000000000"}'
```

**Plan B si la App falla:** en `integrations.github` reemplazar el bloque
`apps:` por `token: { $file: /secrets/github-token }`. `custom-github-auth.ts`
toma las credenciales de la integración, así que funciona con cualquiera de
los dos sin tocar código.

**Otros `.pem` en la VM (no confundir):**
`~/.config/coderv2/github-app.pem` es de **otra** App
(`qintess-latam-rbac-resolver`, ID 5154850). En `~/Descargas/` hay dos claves
de mozart-bot: la que sirve es `…private-key(1).pem` (= `mozart-app.pem`); la
otra GitHub la rechaza (401) y hay que borrarla en la App.

### Paso 3 — Build (desde `~/repos/qintess-platform-backstage-mngr/backstage`)

```bash
docker run --rm -i -v "$(pwd)":/work -w /work \
  -v ~/.config/backstage/secrets:/secrets:ro node:22-bookworm \
  bash -c "corepack enable && yarn install && yarn tsc && yarn build:backend"
docker build -f packages/backend/Dockerfile -t qintess-backstage:latest .
```

### Paso 4 — Redeploy desde Portainer (no `docker compose` por CLI)

UI: *Stacks → backstage → Editor → Update the stack* (sin *Re-pull image*: la
imagen es local, `pull_policy: never`). O por API, con el mismo compose:

```bash
P=http://127.0.0.1:9000
JWT=$(curl -s -X POST $P/api/auth -H 'Content-Type: application/json' \
  -d "$(jq -n --arg p "$(cat ~/.config/portainer/admin-password)" '{username:"admin",password:$p}')" | jq -r .jwt)
COMPOSE=$(curl -s -H "Authorization: Bearer $JWT" "$P/api/stacks/1/file" | jq -r .StackFileContent)
curl -s -X PUT -H "Authorization: Bearer $JWT" -H 'Content-Type: application/json' \
  "$P/api/stacks/1?endpointId=1" \
  -d "$(jq -n --arg c "$COMPOSE" '{stackFileContent:$c, env:[], prune:false, pullImage:false}')"
```

Después, repetir los 3 comandos de verificación del síntoma: el ID de la imagen
del contenedor tiene que coincidir con el de `qintess-backstage:latest` y
`cors.origin` tiene que ser la IP pública. En los logs, el catálogo debe leer la
org: `Committed 5 GitHub users and 25 GitHub groups`.

### Paso 5 — Callback de la OAuth App de login

Sin esto GitHub responde *"The redirect_uri is not associated with this
application"*. **Hay dos OAuth Apps parecidas**: la de Backstage es
`Ov23li6pmECDSrWdcn6d` (la de Coder es `Ov23li16XNUEsskKUnC7`). Callback:

```
https://201.203.104.168:7007/api/auth/github/handler/frame
```

Comprobar qué `redirect_uri` manda Backstage:

```bash
curl -sk -o /dev/null -w '%{redirect_url}\n' \
  'https://201.203.104.168:7007/api/auth/github/start?env=development&scope=read:user'
```

Login OK en logs: `GET /api/auth/github/handler/frame?code=…` → `200`, seguido
de `/api/auth/v1/userinfo` → `200`.

Resultado (2026-10-15 08:51 CST): login de `user:default/juanpdqintess` OK,
imagen `sha256:a67dbbd7298e…`.

---

## FASE 6 — Upgrade de Coder v2.35.1 → v2.37.4 y CA de Caddy en el sistema

### Antes de actualizar: breaking changes (v2.36 / v2.37)

Revisados contra esta instalación (2026-10-15), ninguno aplica:

| Cambio | Chequeo | Resultado |
|---|---|---|
| Coder Tasks deprecado: `--hide-ai-tasks` / `CODER_HIDE_AI_TASKS` rompe el arranque | `grep -i tasks ~/.config/coderv2/server.env` | no se usa |
| `login_type=none` → `password` (migración `000554`) | `coder users list -o json \| jq -r '.[].login_type'` | todos `github` |
| External auth resuelto por lo declarado en el template | `data "coder_external_auth"` en `mvp-embedded` vs `CODER_EXTERNAL_AUTH_*` | `github` y `atlassian`, hosts distintos |
| Dynamic Client Registration OAuth2 apagado por default | — | no se usa |
| Chats API `/api/experimental` → `/api/v2` | — | no se usa |

### Upgrade (~1 min sin Coder; los workspaces siguen vivos)

```bash
# 1. backup a mano (además del diario)
systemctl --user start coder-db-backup.service
systemctl --user show coder-db-backup.service -p Result   # Result=success

# 2. descargar + verificar checksum
V=2.37.4; cd "$(mktemp -d)"
base=https://github.com/coder/coder/releases/download/v$V
curl -sSfLO $base/coder_${V}_linux_amd64.tar.gz
curl -sSfLO $base/coder_${V}_checksums.txt
grep " coder_${V}_linux_amd64.tar.gz$" coder_${V}_checksums.txt | sha256sum -c -
mkdir x && tar xzf coder_${V}_linux_amd64.tar.gz -C x   # el binario es ./coder

# 3. reemplazar dejando el anterior para rollback
cp -p ~/.local/bin/coder ~/.local/bin/coder-v2.35.1
install -m 755 x/coder ~/.local/bin/coder.new && mv -f ~/.local/bin/coder.new ~/.local/bin/coder

# 4. restart (las migraciones de BD corren al arrancar)
systemctl --user restart coder.service
curl -s https://201.203.104.168:3000/api/v2/buildinfo | jq -r .version   # v2.37.4+1d24629
coder list -a                                                          # HEALTHY true
```

**Rollback:** las migraciones de BD **no** tienen vuelta atrás con el binario
viejo. Volver = parar Coder, restaurar el dump previo (ver FASE 2) y
`cp -p ~/.local/bin/coder-v2.35.1 ~/.local/bin/coder`.

**GOTCHA — hay dos binarios de Coder en la VM.** El servicio usa
`~/.local/bin/coder` (vía `start-server.sh`), pero también hay un paquete
`.deb` en `/usr/bin/coder` (v2.37.1) que no se usa. Verificar siempre con
`readlink -f "$(which coder)"` y `/api/v2/buildinfo`.

### Healthcheck en rojo: el server no confiaba en la CA de Caddy

Después del upgrade, `/api/v2/debug/health` (y el dashboard *Deployment →
Health*) daba `healthy=false`, aunque los workspaces estaban `HEALTHY true`:

```
access_url: EACS03 get healthz endpoint: ... x509: certificate signed by unknown authority
websocket:  EWS01  websocket dial: ...      x509: certificate signed by unknown authority
```

**No era del upgrade:** el server se autoconsulta en `CODER_ACCESS_URL`
(`https://201.203.104.168:3000`, cert `tls internal` de Caddy) y la CA de
Caddy nunca se había instalado en el trust store **del host** (los
workspaces y los navegadores la confían por su cuenta). Fix:

```bash
sudo install -m 644 ~/.config/coderv2/caddy-ca/root.crt \
  /usr/local/share/ca-certificates/caddy-local-root.crt
sudo update-ca-certificates            # 1 added, 0 removed
curl -s -o /dev/null -w '%{http_code}\n' https://201.203.104.168:3000/healthz   # 200 sin -k
systemctl --user restart coder.service
curl -sk -H "Coder-Session-Token: $(cat ~/.config/coderv2/session)" \
  https://127.0.0.1:3000/api/v2/debug/health | jq '.healthy'           # true
```

`~/.config/coderv2/caddy-ca/root.crt` tiene que ser la misma CA que la de Caddy
(comparar `openssl x509 -noout -fingerprint -sha256` con
`docker exec caddy-coder cat /data/caddy/pki/authorities/local/root.crt`).
Si se pierden los volúmenes de Caddy hay CA nueva → repetir este paso.

Tras el restart los workspaces pasan unos segundos por `HEALTHY false`
mientras los agentes se reconectan; es normal.

Resultado (2026-10-15): Coder `v2.37.4+1d24629`, health `ok` en
todos los checks, los 2 workspaces `HEALTHY true`.

---

## Pendientes

- **Copia de los backups fuera de la VM** — los backups diarios de `coder-db`
  ya existen (ver FASE 2), pero viven en el mismo disco.
- **Nombre DNS para Coder** en vez de la IP pública pelada (ver FASE 4).
- **Atlassian external-auth:** su callback también depende de
  `CODER_ACCESS_URL`; actualizarlo en la app de Atlassian si se usa.
- **Rotar el PAT `github-token` y el client secret de `qintess-mozart-bot`**
  (se compartieron por chat el 2026-10-15) y borrar en la App la clave privada
  vieja que da 401.
- **Actualizar la imagen de Portainer** (`2.19.4` es de 2023).
- **Desinstalar el `.deb` de Coder** (`/usr/bin/coder` v2.37.1, sin uso) y borrar
  `~/.local/bin/coder-v2.35.1` cuando v2.37.4 esté estable.
- **Cambiar la password de `admin` de Portainer** y borrar
  `~/.config/portainer/admin-password`.
- Borrar `~/.config/coderv2/postgres/` cuando se confirme que `coder-db` es
  estable (hoy es el plan de rollback).
- Si se para el stack `caddy` desde Portainer, se cae también la UI de Portainer
  (y Coder y Backstage). Recuperación: `docker start caddy-coder`, o un túnel SSH
  a `127.0.0.1:9000`.

---

## Resumen de archivos

| Archivo (en la VM) | En el repo | Qué es |
|---|---|---|
| `~/stacks/portainer/docker-compose.yaml` | `deploy/vm/stacks/portainer/` | Portainer |
| `~/stacks/caddy/docker-compose.yaml` | `deploy/vm/stacks/caddy/` | stack `caddy` |
| `~/stacks/coder-db/docker-compose.yaml` | `deploy/vm/stacks/coder-db/` | stack `coder-db` |
| `~/.config/caddy-coder/Caddyfile.tmpl` | `deploy/vm/caddy/` | plantilla del Caddyfile (**se edita esta**) |
| `~/.config/caddy-coder/sync-lan-ip.sh` | `deploy/vm/caddy/` | render + reload de Caddy |
| `~/.config/systemd/user/caddy-lan-ip.{service,timer}` | `deploy/vm/systemd/` | timer cada 1 min |
| `/usr/local/share/ca-certificates/caddy-local-root.crt` | — | CA de Caddy en el trust store del host (FASE 6) |
| `~/.local/bin/coder-v2.35.1` | — | binario anterior, rollback del upgrade (FASE 6) |
| `/etc/systemd/system/coder-access-ip.service` | `deploy/vm/systemd/` | `192.168.50.208/32` en `lo` — **desactivado** |
| `~/.config/coder-db/backup-coder-db.sh` | `deploy/vm/coder-db/` | backup + verificación + rotación |
| `~/.config/systemd/user/coder-db-backup.{service,timer}` | `deploy/vm/systemd/` | backup diario 03:00 |
| `~/.config/coder-db/backups/` | — | dumps, **NO van a git** |
| `~/.config/caddy-coder/Caddyfile` | — | **generado**, no editar |
| `~/.config/coder-db/{pg-password,connection-url}` | — | secretos, **NO van a git** |
| `~/.config/portainer/admin-password` | — | secreto, **NO va a git** |
| `~/.config/coderv2/server.env` | — | `CODER_PG_CONNECTION_URL` + `CODER_ACCESS_URL` pública (**NO va a git**) |
| `~/.config/backstage/secrets/` | — | secretos de Backstage (ver FASE 5), **NO van a git** |
