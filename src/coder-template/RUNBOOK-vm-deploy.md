# RUNBOOK — Despliegue de Coder en una VM (servidor expuesto, multi-usuario)

> Objetivo: montar Coder en una VM Ubuntu como **servidor**, exponer su URL y
> que los usuarios entren, creen sus workspaces y trabajen (roles RBAC por
> GitHub Teams, una plantilla por rol). Instalación **nueva y limpia**.
>
> La parte mecánica la hace `deploy/vm/bootstrap-vm.sh`; aquí están los pasos
> manuales y las decisiones. El estado real de la VM de `Qintess-Latam` (Caddy,
> Portainer, PostgreSQL en Docker, IP pública) está en
> [`RUNBOOK-vm-qintess-latam.md`](RUNBOOK-vm-qintess-latam.md) y
> [`RUNBOOK-vm-portainer-red.md`](RUNBOOK-vm-portainer-red.md).

---

## 0. Requisitos de la VM

| Requisito | Valor recomendado |
|---|---|
| SO | Ubuntu 22.04/24.04 (server o desktop) |
| CPU / RAM | ≥ 4 vCPU / ≥ 8 GB (cada workspace es un contenedor) |
| Disco | ≥ 60 GB (imágenes Docker + datos de workspaces) |
| Red | IP fija en LAN/VPN; puerto 3000/tcp alcanzable por los usuarios |
| Usuario | uno dedicado, **no root**, con sudo (será dueño de Coder) |

---

## 1. Estrategia de exposición (FASES)

Aún no hay dominio, así que arrancamos por **IP** y migramos a **dominio+TLS** sin reinstalar.

### Fase 1 — IP en LAN/VPN (arranca ya)
- `CODER_ACCESS_URL="http://<IP-de-la-VM>:3000"`
- `CODER_WILDCARD_ACCESS_URL=""` (vacío → apps en modo *path*, funcional para probar)
- Sin TLS. Válido para piloto interno. **No** para producción bancaria.

### Fase 2 — Dominio + TLS (cuando tengas dominio)
- DNS: `A  coder.tu-empresa.com → IP-VM`  y  `A  *.coder.tu-empresa.com → IP-VM` (wildcard, para las apps).
- Reverse proxy con TLS (recomendado **Caddy**, auto-HTTPS):
  ```
  coder.tu-empresa.com, *.coder.tu-empresa.com {
      reverse_proxy 127.0.0.1:3000
  }
  ```
  y en `server.env`: `CODER_HTTP_ADDRESS="127.0.0.1:3000"` (solo local; Caddy expone 443).
- `CODER_ACCESS_URL="https://coder.tu-empresa.com"` + `CODER_WILDCARD_ACCESS_URL="*.coder.tu-empresa.com"`.

> **Alternativa sin infra (demo):** túnel integrado de Coder → URL `*.try.coder.app`.
> No apto para prod; útil para enseñarlo rápido.

---

## 2. Instalación mecánica (script)

En la VM, como el usuario dueño de Coder (no root):

```bash
gh repo clone Qintess-Latam/qintess-platform-coder-template ~/coder-platform
cd ~/coder-platform
cp deploy/vm/vm-deploy.conf.example deploy/vm/vm-deploy.conf
# edita vm-deploy.conf: CODER_ACCESS_URL, REPO_PATH, etc.
bash deploy/vm/bootstrap-vm.sh
```

El script instala **todos los binarios del host** (Docker, Coder v2.37.4, `gh`,
`git`, `jq`, `curl`, `openssl`, `gnupg`/`ca-certificates`), crea `start-server.sh`,
la unit `systemd --user`, habilita **linger** (arranque en boot), siembra un
`server.env` desde la plantilla y verifica que cada binario quedó presente.
**No arranca Coder** hasta que rellenes los secretos.

> Binarios y para qué: `coder` (server/CLI), `docker` (workspaces), `gh` +
> `openssl` + `jq` + `curl` (resolución de rol RBAC — firman el JWT del GitHub
> App), `git` (repo). `base64`/`sed`/`awk` ya vienen en el sistema base.

> Si te añadió al grupo `docker`, **cierra sesión y vuelve a entrar** antes de seguir.

---

## 3. Credenciales (rellenar `~/.config/coderv2/server.env`)

Los redirect URIs dependen del `CODER_ACCESS_URL`. Con `<URL>` = tu access URL:

| Credencial | Dónde se crea | Callback / Redirect URI |
|---|---|---|
| **GitHub OAuth (login)** | github.com/settings/developers (o de la Org) | `<URL>/api/v2/users/oauth2/github/callback` |
| **external-auth github** | otra OAuth App (o la misma) | `<URL>/external-auth/github/callback` |
| **external-auth atlassian** | developer.atlassian.com/console/myapps | `<URL>/external-auth/atlassian/callback` |
| **GitHub App (rol RBAC)** | Org → Settings → GitHub Apps (en `Qintess-Latam`: `qintess-latam-rbac-resolver`) | permiso *Members: read*; copia el `.pem` a `~/.config/coderv2/github-app.pem` |

Ver plantilla comentada: `deploy/vm/server.env.example`.
Para el detalle del GitHub App: `docs/RUNBOOK-github-app.md`.
Para Atlassian (incl. Distribution): `docs/external-auth-oauth-pattern.md`.

```bash
chmod 600 ~/.config/coderv2/server.env ~/.config/coderv2/github-app.pem
systemctl --user restart coder
curl -fsS "$CODER_ACCESS_URL/healthz" && echo "  ← OK"   # o http://127.0.0.1:<puerto> si aún no hay proxy
```

---

## 4. Firewall

```bash
# Fase 1 (IP directa):
sudo ufw allow 3000/tcp
# Fase 2 (detrás de Caddy): abre 80 y 443, cierra 3000 al exterior.
sudo ufw allow 80,443/tcp
```

---

## 5. Primer admin + plantilla

```bash
# Primer usuario = admin (por el navegador en <URL>, o por CLI):
coder login "<URL>"

# Overlays + skills desde los repos de la org → ~/.config/coderv2/agents-overlays-synced
bash ~/coder-platform/deploy/vm/sync-agent-overlays.sh
# Las 5 plantillas por rol (qintess-<rol>-template) con las variables de la VM
bash ~/coder-platform/deploy/vm/push-role-templates.sh
```

---

## 6. RBAC (GitHub Teams → roles)

1. En la Org de GitHub crea los teams de rol: `qintess-developers`, `qintess-qa`,
   `qintess-architect`, `qintess-platform`, `qintess-cyber` (y sus sub-teams).
2. Añade a cada usuario a su team.
3. Instala el GitHub App de resolución de rol en la Org (Members: read).
4. Sube las plantillas por rol: `bash deploy/vm/push-role-templates.sh`
   (ver `docs/RUNBOOK-plantillas-por-rol.md`).

Detalle: `docs/rbac-setup.md`.

---

## 7. Verificación E2E

```bash
coder templates list          # aparece mvp-embedded
coder list                    # workspaces (vacío al inicio)
```
Desde otra máquina: abre `<URL>`, entra con GitHub (miembro de la org), crea un
workspace, abre la terminal/VS Code, ejecuta `claude` y `claude mcp list`
(atlassian ✔ Connected, github ✔ Connected). Verifica que el rol aplicado
corresponde al team del usuario.

---

## 8. Cambiar de fase (IP → dominio+TLS) SIN reinstalar

1. Monta DNS (A + wildcard) y el reverse proxy (Caddy) → Fase 2 arriba.
2. Edita `vm-deploy.conf` y `~/.config/coderv2/server.env`:
   - `CODER_ACCESS_URL` = `https://coder.tu-empresa.com`
   - añade `CODER_WILDCARD_ACCESS_URL`
   - `CODER_HTTP_ADDRESS` = `127.0.0.1:3000`
3. **Actualiza los redirect URIs** de las 3 OAuth apps + GitHub App al nuevo dominio
   (este es el paso que más se olvida → login roto si no se hace).
4. `systemctl --user restart coder`.
5. Re-push de la plantilla no hace falta salvo que cambien vars.

---

## 9. Troubleshooting

| Síntoma | Causa probable | Fix |
|---|---|---|
| Coder no arranca | server.env con CHANGE_ME / falta .pem | `journalctl --user -u coder -n 50` |
| Login GitHub falla | callback URL ≠ ACCESS_URL | corrige redirect URI de la OAuth App |
| Workspace no crea | usuario no en grupo docker / Docker parado | `newgrp docker`; `systemctl status docker` |
| Rol siempre "unknown" | GitHub App sin Members:read o sin GITHUB_TOKEN | revisa App + PAT en server.env |
| MCP atlassian 401 | (ya resuelto por overlay: token fresco en runtime) | `coder external-auth access-token atlassian` |
| Apps (terminal) no abren en Fase 1 | sin wildcard | normal por IP; usa modo path o pasa a Fase 2 |
| No arranca tras reboot | linger off | `sudo loginctl enable-linger $USER` |
