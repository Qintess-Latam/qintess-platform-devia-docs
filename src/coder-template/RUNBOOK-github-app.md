# RUNBOOK — GitHub App para AuthZ (Nivel 2, Camino A)

**GitHub App de la organización** como credencial que usa `resolve-role.sh` para
consultar membresías de team (reemplazó al PAT personal del prototipo inicial).
En `Qintess-Latam` es **`qintess-latam-rbac-resolver`** (App ID `5154850`),
con la private key en `~/.config/coderv2/github-app.pem`.
Token de instalación **auto-rotado (~1 h)**, **no atado a ninguna persona**,
auditable. Sigues en GitHub como IdP (Decisión #2) y `resolve-role.sh` se queda.

> Ver también: `docs/TO-BE/13-authz-a-escala.md` (Camino A / Nivel 2),
> `deploy/prod/github-app.env.example`, `templates/mvp-embedded/scripts/gh-app-token.sh`.

---

## Por qué una App y no un PAT

| | PAT personal (prototipo, superado) | GitHub App (actual) |
|---|---|---|
| Dueño | La cuenta de una persona | La **organización** |
| Si te vas de la org | se cae el AuthZ de todos | sigue funcionando |
| Rotación | manual | **automática (~1 h)** |
| Auditoría | acción de un humano | acción de la App |
| Permiso | scope amplio del usuario | **solo** `Members: read` |

El usuario final **nunca** ve esto: es una credencial de plataforma, una para todos.

---

## Pasos

### 1. Crear la GitHub App (una vez)
`Org → Settings → Developer settings → GitHub Apps → New GitHub App`
- **Homepage URL:** cualquiera (ej. la URL de Coder).
- **Webhook:** desmarcar "Active" (no lo necesitamos).
- **Permissions → Organization → Members: `Read-only`** (es el ÚNICO permiso).
- **Where can this be installed:** "Only on this account".
- Crear → anota el **App ID**.
- En la página de la App: **Generate a private key** → descarga el `.pem`.

### 2. Instalar la App en la org
- En la App → **Install App** → elige `Qintess-Latam` → instalar (All repos da igual;
  el permiso es a nivel de org, no de repos).
- Tras instalar, la URL queda como `.../installations/<INSTALLATION_ID>` →
  ese número es el **Installation ID**. (Alternativa por API más abajo.)

### 3. Colocar la private key y las envs en el server
```bash
# private key con permisos estrictos, fuera de git
mv ~/Descargas/tu-app.*.private-key.pem ~/.config/coderv2/github-app.pem
chmod 600 ~/.config/coderv2/github-app.pem

# variables de la App en el entorno del server (append; NO el PAT personal)
cat >> ~/.config/coderv2/server.env <<'EOF'
export GITHUB_APP_ID="<APP_ID>"
export GITHUB_APP_INSTALLATION_ID="<INSTALLATION_ID>"
export GITHUB_APP_PRIVATE_KEY_PATH="$HOME/.config/coderv2/github-app.pem"
EOF

systemctl --user restart coder.service
```
(Plantilla completa en `deploy/prod/github-app.env.example`.)

### 4. Probar el mint del token (sin tocar Coder)
```bash
cd templates/mvp-embedded/scripts
set -a; source ~/.config/coderv2/server.env; set +a
./gh-app-token.sh | head -c 12 ; echo '...'      # debe imprimir un token ghs_...
# y que resuelve el rol con ESE token:
echo '{"github_username":"<user>","github_org":"Qintess-Latam"}' | ./resolve-role.sh
# → {"role":"<rol>"}
echo '{"github_username":"<user>","github_org":"Qintess-Latam","required_role":"qa"}' | ./resolve-role.sh
# → {"role":"qa"}  ó  error si <user> no está en qintess-qa (plantilla por rol)
```

### 5. Reconstruir el workspace para re-estampar el label
```bash
coder update <owner>/<workspace> --yes    # o `coder restart` si el template no está OUTDATED
docker inspect coder-<owner>-<ws> --format '{{index .Config.Labels "coder.com/role"}}'
# → el rol de la plantilla (ya no unknown)
```

---

## Obtener el Installation ID por API (si no lo viste en la URL)
Necesitas un JWT de la App primero; lo más fácil es reusar el minter en dos pasos,
o con `gh` autenticado como owner:
```bash
gh api "/orgs/Qintess-Latam/installation" --jq '.id'    # requiere permisos de owner
```

---

## Notas
- `gh-app-token.sh` genera el token **on-demand** por invocación de
  `resolve-role.sh` (no queda token en disco; solo la private key).
- Precedencia en `resolve-role.sh`: **PAT en entorno > GitHub App > gh ambiente**
  (un `GH_TOKEN`/`GITHUB_TOKEN` en el entorno del server pisa a la App).
- **No confundir** con la GitHub App `qintess-mozart-bot` (Backstage/mozart y lectura
  de billing de Copilot): otra App, otros permisos.
- Rate limits de installation token escalan con la org (mejor que un PAT personal).
- Rota la private key desde la App si se compromete; no hay token largo que revocar.
