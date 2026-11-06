# RUNBOOK — Plantillas de Coder por rol (`qintess-<rol>-template`)

> Desde 2026-10-15 cada rol tiene su propia plantilla en Coder, con los binarios
> que necesita, su overlay de agentes (CLAUDE.md + MCP + permisos) y un panel de
> estado en el workspace. Reemplazan a `mvp-embedded`, que queda **obsoleta**
> (solo para los workspaces que ya existían, hasta que migren).

---

## Resultado

| Plantilla (Coder) | Nombre visible | Team requerido | Binarios del rol | Overlay |
|---|---|---|---|---|
| `qintess-architecture-template` | Qintess · Architecture (PM/PO) | `qintess-architect` | pandoc, PlantUML, Mermaid CLI (`mmdc`), yq | `architect/` (modelo `opus`) |
| `qintess-developer-template` | Qintess · Developer | `qintess-developers` | Java 21 + Maven, .NET LTS, Python 3 + uv | `developer/` (`sonnet`) |
| `qintess-platform-template` | Qintess · Platform | `qintess-platform` | Terraform, kubectl, Helm, AWS CLI, Azure CLI, yq | `platform/` (`sonnet`) |
| `qintess-qa-template` | Qintess · QA | `qintess-qa` | Playwright (Chromium), k6, Newman, Allure | `qa/` (`sonnet`) |
| `qintess-cyber-template` | Qintess · Cyber (AppSec) | `qintess-cyber` | Trivy, Gitleaks, Semgrep, OWASP ZAP | `cyber/` (`sonnet`) |

Base común a todas: VS Code Web (code-server) con la **extensión de Claude
Code**, Claude Code CLI, GitHub Copilot CLI, `git`, `gh`, `jq`, Node 20,
`uv`, Docker CLI (sin daemon).

"Architecture" es el rol de **producto (PM/PO)**: documentación y diagramas.
Lo de infraestructura/cloud es de **Platform**.

---

## Cómo está hecho (un solo código, cinco plantillas)

Todo vive en `templates/mvp-embedded/`. Las plantillas se diferencian **solo**
por la variable `template_role`:

| Archivo | Qué hace |
|---|---|
| `main.tf` | variable `template_role` (+ `ai_spend_host_dir`), panel (metadata), extensión de Claude, mount de gasto |
| `scripts/resolve-role.sh` | con `required_role`: deja crear el workspace **solo** si el usuario está en el team del rol (padre o sub-team); si no, el build falla con un mensaje claro |
| `scripts/role-tools.sh` | instala los binarios del rol, idempotente; resumen en `~/.cache/qintess/role-tools.txt` |
| `scripts/ai-spend.mjs` | "Estimated AI spend/month" del panel |
| `deploy/vm/push-role-templates.sh` | sube las 5 plantillas con las mismas variables |

Subir / actualizar:

```bash
bash deploy/vm/sync-agent-overlays.sh             # overlays + skills al host (si cambiaron)
bash deploy/vm/push-role-templates.sh             # las 5, versión activa
bash deploy/vm/push-role-templates.sh qa          # solo una
ACTIVATE=false bash deploy/vm/push-role-templates.sh   # probar sin activar
```

`mvp-embedded` (genérica, `template_role` vacío → rol automático por team) se
sigue pudiendo subir con el comando de `RUNBOOK-vm-qintess-latam.md` FASE 5.

### Control de acceso (sin Coder Premium)

Coder sin licencia **no** tiene ACL de plantillas por grupo: todos ven las cinco.
La barrera está en `resolve-role.sh`: si un developer elige
`qintess-platform-template`, el build falla con:

```
El usuario 'X' no pertenece al team 'qintess-platform' (ni a sus sub-teams) de
la org 'Qintess-Latam': no puede usar la plantilla del rol 'platform'. ...
```

Dar acceso a un rol = agregar al usuario al team de GitHub (o a un sub-team).

**GOTCHA — plan de importación con usuario `default`.** `coder templates push`
hace un plan con un dueño ficticio llamado `default`; sin la excepción en
`resolve-role.sh` el push falla con *"El usuario 'default' no pertenece…"*.

**GOTCHA — deprecación de plantillas es Premium.** `coder templates edit
--deprecated` responde OK pero **no se aplica** (`deprecated: false`). Por eso
`mvp-embedded` se marcó como obsoleta en el nombre visible y la descripción.

### Binarios del rol (`role-tools.sh`)

- Se ejecuta **después** de levantar code-server/ttyd: las apps son usables
  mientras se instalan las herramientas.
- Instala en `~/.local` cuando puede (volumen de home **persistente**: sobrevive
  a recrear el contenedor); apt/`npm -g` van a la capa del contenedor y se
  reinstalan si se recrea.
- "Instalado" = el binario **imprime una versión**. Se mira la salida, no el
  exit code: `plantuml -version` imprime la versión y sale con 250; Helm 4 solo
  acepta `helm version`; con `pipefail` el exit≠0 taparía el `grep` (por eso se
  captura primero).
- Un fallo no aborta el resto: queda en el resumen (`5/6 OK (falta: k6)`) y el
  detalle en `/tmp/role-tools.log`.
- `.NET` necesita `libicu<N>` (el nombre lleva la versión: se detecta con
  `apt-cache pkgnames`).

---

## Imágenes por rol — crear un workspace en ~20 s (2026-10-16)

Antes, cada workspace **nuevo** (o recreado) bajaba todo en el arranque por el
Wi-Fi de la VM (~320 KB/s): ~600 MB → **20-54 min**. Se midió y había **tres**
cuellos de botella:

| Tramo | Antes | Ahora | Fix |
|---|---|---|---|
| Build de Coder (2× `terraform init`) | ~5,5 min | 12 s | `.terraform.lock.hcl` versionado en la plantilla (init 101 s → 1,7 s) |
| Agente de Coder conecta (baja su binario de 59 MB) | 1,5-4 min | 1 s | el agente usa `host.docker.internal` (red interna de Docker → Caddy) en vez de la IP pública (hairpin NAT por el router: 229 s → 0,4 s) |
| `startup_script` (code-server, Claude, Copilot, Node, Chromium, binarios del rol, extensión) | 20-50 min | 5 s | imagen pre-armada por rol |
| **Total (QA, medido)** | **~54 min** | **19 s** | |

### La imagen — `images/workspace/Dockerfile`

Patrones de imagen segura (multi-stage, no-root, sin caches, gate de Trivy, labels
OCI). **No distroless**: un workspace necesita shell (init del agente de Coder,
Claude/Copilot ejecutan comandos, terminal), apt y glibc.

| Etapa | Qué hace |
|---|---|
| `fetch` | descarga y verifica: code-server 4.141.0, Node 22 (SHASUMS256; `shell-quote` actualizado), ttyd, gh, uv, `.vsix` de Claude |
| `base` | **común a los 5 roles** (se baja una vez): Ubuntu 24.04 + lo anterior + **npm 11** + Claude Code + Copilot CLI (validados por `--version`, 3 reintentos) |
| `gitleaks` | `golang:1.27`: recompila gitleaks 8.30.1 con Go 1.27.2 y deps al día (la release oficial trae ~40 CVE de Go; quitar cuando salga una nueva) |
| `role` | `ARG ROLE` → `templates/mvp-embedded/scripts/role-tools.sh` (el MISMO script de la plantilla); **falla el build** si falta una herramienta y muestra su log |

El gate de seguridad ya **no** es una etapa del Dockerfile (copiaba el rootfs y llenó el disco): es `images/workspace/scan.sh`, que escanea la imagen ya construida por el socket de Docker.

```bash
cd ~/coder-platform
export GH_TOKEN=$(gh auth token)      # opcional: API de GitHub 60/h → 5000/h (secreto, no queda en la imagen)
docker build --secret id=gh_token,env=GH_TOKEN -f images/workspace/Dockerfile \
  --target role --build-arg ROLE=qa --build-arg REFRESH=$(date +%F) -t qintess-workspace:qa .
images/workspace/scan.sh qintess-workspace:qa                # gate de seguridad (Trivy; sale 1 si hay HIGH/CRITICAL con fix)
bash deploy/vm/push-role-templates.sh qa                     # usa qintess-workspace:qa
```

`push-role-templates.sh` pasa `workspace_image=${IMAGE_REPO}:<rol>` (default
`IMAGE_REPO=qintess-workspace`, imagen local; `IMAGE_REPO=""` = imagen genérica).
Si falta la imagen local de un rol, omite esa plantilla con un aviso.

`REFRESH` fuerza a re-bajar las versiones "latest" de las herramientas (si no, Docker
reutiliza la capa en caché). Los 5 builds seguidos tardan ~2 h con el Wi-Fi de la VM;
`docker builder prune -af` al terminar (la caché llegó a ocupar 40 GB).

**Seguridad (resultado 2026-10-19: los 5 roles con 0 HIGH/CRITICAL estrictos).**
`scan.sh` bloquea todo HIGH/CRITICAL con fix. Excepciones, todas con vencimiento
(`images/workspace/.trivyignore.yaml`, `expired_at: 2026-11-15`; pasada la fecha el
hallazgo vuelve a bloquear) y documentadas en `images/workspace/SECURITY-EXCEPTIONS.md`:
CVE de Go de `gh`, `k6`, `yq`, `kubectl` y `terraform` (sin release upstream con Go
parcheado) y `basic-ftp` de code-server (el fix es un salto mayor). Newman y Allure
se escanean en modo informativo.

**Actualizar versiones** (Claude, Copilot, herramientas): reconstruir la imagen y
volver a subir la plantilla; los workspaces la toman al recrearse.

**GOTCHAS del Dockerfile (todos salieron en los builds):**
- `/home/coder` es un **volumen** en el workspace (tapa la imagen): todo se instala
  en `/usr/local` y `/opt/qintess` (`HOME=/opt/qintess` al correr `role-tools.sh`;
  `PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright`).
- `sudo npm` no encuentra npm si Node está en `/usr/local/node/bin` (sudo usa
  `secure_path`) → Node enlazado en `/usr/local/bin` y prefijo global de npm `/usr/local`.
- **No borrar `/usr/share/man`**: el post-install de Java (`update-alternatives`)
  necesita `/usr/share/man/man1` (ubuntu:24.04 ya excluye man/docs al instalar).
- `copilot --version` copia su paquete a `~/.cache/copilot` (204 MB): se borra en la capa.
- Con red inestable cada build fallaba en una herramienta **distinta**: reintentos
  (3) en `role-tools.sh` + token de GitHub como secreto de BuildKit.
- Trivy con todos los scanners se cortaba a los 15 min (`context deadline exceeded`)
  sobre 4,5 GB: `--scanners vuln --timeout`. Para binarios de Go hay que usar
  `rootfs` (`fs` no los ve). Una sola instancia de Trivy a la vez (bloquea la caché);
  la primera vez que ve JARs (ZAP) baja la base de Java: lento con este Wi-Fi.
- **npm 12 rompe Claude/Copilot**: bloquea por defecto los `postinstall` de las
  dependencias y el binario nativo no se instala. Se fija `npm@11` (trae las deps
  corregidas); además sus usuarios mantienen los `postinstall` de sus proyectos.
- `/root/.ZAP` (JARs que ZAP deja al verificar la versión) se borra: el usuario del
  workspace no lo usa y Trivy lo marcaba con 3 CRITICAL.
- Autostop: las plantillas llevan `--default-ttl 2h --activity-bump 1h
  --autostop-reminder 15m` (aplicado por `push-role-templates.sh`; `DEFAULT_TTL`,
  `ACTIVITY_BUMP`, `AUTOSTOP_REMINDER` lo cambian). Pendiente verificar si una pestaña
  de ttyd abierta cuenta como actividad.

**Tamaños (sin comprimir):** base común 1,97 GB; QA 4,54 GB (Chromium + deps, Java,
`.vsix`). Lo grueso es intrínseco: code-server 429 MB (trae su Node), Claude 256 MB,
Copilot 178 MB, Node 203 MB.

### Cambios en la plantilla y en Caddy

- `main.tf`: variable `workspace_image`, `docker_image` (keep_locally), el `entrypoint`
  reemplaza `data.coder_workspace.me.access_url` por `https://host.docker.internal:<puerto>`
  en el `init_script`; `mkdir -p ~/.local/bin` (un home NUEVO no lo tiene); la
  extensión de Claude se instala **después** de levantar los apps y desde el `.vsix`
  local si existe; el chequeo de Chromium respeta `PLAYWRIGHT_BROWSERS_PATH`.
- `.terraform.lock.hcl` versionado (excepción en `.gitignore`).
- Caddy (`deploy/vm/caddy/Caddyfile.tmpl`): `host.docker.internal:3000` en el bloque
  de Coder → cert de la CA interna para ese nombre (los workspaces mandan SNI).
  Efecto extra: los agentes ya **no dependen** de la IP pública ni de la LAN.

## Panel del workspace (Coder → recurso `docker_container.workspace`)

| Ítem | Fuente | Refresco |
|---|---|---|
| Rol | `local.role` | 10 min |
| Claude CLI | `claude --version` | 10 min |
| Claude (VS Code) | `code-server --list-extensions --show-versions` (`anthropic.claude-code`) | 10 min |
| GitHub | `coder external-auth access-token github` + `GET /user` → `OK (@login)` | 5 min |
| Atlassian | `coder external-auth access-token atlassian` + `accessible-resources` → `OK (<sitio>)` | 5 min |
| Herramientas del rol | `~/.cache/qintess/role-tools.txt` | 2 min |
| Estimated AI spend/month | `node ~/.local/bin/qintess-ai-spend` | 5 min |

Los scripts de metadata los corre el agente **con su entorno**
(`CODER_AGENT_URL`), así que `coder external-auth access-token` devuelve un
token **fresco**. El `ATLASSIAN_OAUTH_ACCESS_TOKEN` del env es del build y vence
a la hora: no usarlo para el chequeo.

### Estimated AI spend/month

```
~$19.00/mes (Claude ~$0.00 · Copilot $19.00 seat + $0.00)
```

- **Claude Code:** el backend es suscripción (sin factura por usuario) → se
  estima el **equivalente por token**: `message.usage` de
  `~/.claude/projects/**/*.jsonl` del mes (deduplicado por `message.id`) ×
  tarifa por familia (`PRICES` en `ai-spend.mjs`, USD/millón: tarifas del
  catálogo de Copilot, AI credit = USD 0.01).
- **Copilot:** seat + premium requests **del usuario**, que escribe el host:

```bash
# deploy/vm/ai-spend/copilot-spend.sh → ~/.config/coderv2/ai-spend-bin/
# timer systemd --user copilot-spend.timer (cada hora)
mkdir -p ~/.config/coderv2/ai-spend-bin
install -m 755 deploy/vm/ai-spend/copilot-spend.sh ~/.config/coderv2/ai-spend-bin/
install -m 644 deploy/vm/systemd/copilot-spend.{service,timer} ~/.config/systemd/user/
systemctl --user daemon-reload && systemctl --user enable --now copilot-spend.timer
journalctl --user -u copilot-spend.service -n 10 -o cat
# → ~/.config/coderv2/ai-spend/<login>/copilot.json
```

  Cada workspace monta **solo** la carpeta de su dueño en `/opt/ai-spend` (RO).
  Credencial: GitHub App `qintess-mozart-bot` (no hace falta token de owner).

**GOTCHAS de la API de billing:**
- `settings/billing/usage/summary?user=X` **ignora** el filtro de usuario
  (devuelve los totales de la org). El que sí filtra es
  `settings/billing/premium_request/usage?user=X`.
- Los *AI Credits* (`copilot_ai_unit`) solo se informan a nivel org.
- La API de métricas por usuario exige la policy *Copilot usage metrics*.

---

## Overlays `platform/` y `cyber/`

En `qintess-platform-agents-overlays` (mismo formato que los demás:
`CLAUDE.md`, `mcp-config.json`, `settings.json`; MCP github + atlassian).

- **platform:** planifica/valida (`terraform plan`, `helm lint|template`,
  `kubectl get|describe|diff`) pero **nunca aplica**: `terraform apply|destroy`,
  `kubectl apply|delete`, `helm install|upgrade|uninstall` en `deny`; `aws`/`az`
  y `terraform state|import` en `ask`.
- **cyber:** SAST/secretos/dependencias permitidos (`semgrep scan`, `gitleaks`,
  `trivy fs|config|image`); `zap` y `curl` en `ask` (DAST solo contra objetivos
  autorizados); `nmap`, `sqlmap`, `hydra` en `deny`.

Tras cambiar overlays: `bash deploy/vm/sync-agent-overlays.sh` y reiniciar el
workspace (el startup reaplica el overlay).

---

## Migración desde `mvp-embedded`

No hay forma de cambiar la plantilla de un workspace existente en Coder. Cada
usuario:

1. Se asegura de tener todo **pusheado** a GitHub (el home del workspace viejo
   no se copia).
2. Crea un workspace nuevo con la plantilla de su rol
   (*Workspaces → New → Qintess · <rol>*).
3. Vuelve a autorizar GitHub/Atlassian si se lo pide y clona sus repos.
4. Cuando confirma que todo funciona, borra el workspace viejo
   (*Settings → Delete*).

Cuando no quede ningún workspace en `mvp-embedded`, se puede borrar la
plantilla (`coder templates delete mvp-embedded`).

---

## Verificación con imágenes (2026-10-19)

Plantillas `img-1019-0907` activas. Un workspace por rol creado en paralelo con
`coder create`: **8-16 s** (QA 8, architect 11, cyber 11, platform 12, developer 16),
agente `connected/ready`, code-server 200, Claude 2.1.302, Copilot 1.0.98,
`qintess-ai-spend` OK, herramientas 4/4, 5/5, 6/6, 4/4 y 4/4. Borrados al terminar.

## Verificación (2026-10-15, sin imágenes)

Instalación de binarios probada por rol en contenedores descartables con la
imagen base (`codercom/enterprise-base:ubuntu`, Ubuntu 26.04): 5/5 roles OK.
Workspaces de prueba de punta a punta (versión `v3-1527`, usuario
JuanPDQintess, presente en todos los teams):

| Workspace | Plantilla | Herramientas | Overlay aplicado | Panel |
|---|---|---|---|---|
| `prueba-qa` | qintess-qa-template | 4/4 OK | `qa` | Claude CLI 2.1.197 · ext. v2.1.300 · GitHub OK · Atlassian OK · ~$19/mes |
| `prueba-platform` | qintess-platform-template | 6/6 OK | `platform` (sonnet, 24 allow / 7 ask / 23 deny) | ídem, ext. v2.1.301 |
| `prueba-cyber` | qintess-cyber-template | 4/4 OK | `cyber` (sonnet, 16 allow / 6 ask / 18 deny) | ídem, ext. v2.1.301 |

Denegación por team: `RichardASQintess` (developers) contra `required_role=platform`
→ falla con el mensaje de arriba (probado con `resolve-role.sh` y la GitHub App
del provisioner).

**GOTCHA — panel "Claude CLI: no instalado" al recrear el contenedor.** El
primer chequeo corre apenas conecta el agente, mientras el startup todavía
reinstala `claude` (la capa del contenedor se pierde al recrear). Por eso el
intervalo de ese ítem es de 60 s (y 120 s el de la extensión).

(Histórico, antes de las imágenes.) Un workspace **nuevo** tardaba ~15-20 min con el Wi-Fi de la VM (~330 KB/s):
code-server (104 MB), paquetes nativos de Claude/Copilot (~100 MB c/u),
Chromium y los binarios del rol (ZAP 232 MB). Las apps quedan usables antes de
que terminen los binarios del rol.
