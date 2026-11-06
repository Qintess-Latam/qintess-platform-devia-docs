# RBAC setup — GitHub OAuth + rol por Team

> Cómo Coder decide el rol de cada workspace a partir de la membresía del usuario
> en los teams de GitHub de `Qintess-Latam`.
> Diseño de referencia: [`docs/TO-BE/02-rbac-mapping-roles.md`](./TO-BE/02-rbac-mapping-roles.md).
> Plantillas por rol: [`docs/RUNBOOK-plantillas-por-rol.md`](./RUNBOOK-plantillas-por-rol.md).

## Arquitectura de la resolución

```
GitHub OAuth login ─▶ Coder (owner = github username)
                              │
     Terraform (provisioner)  ▼
        data.external.user_role  ──▶ scripts/resolve-role.sh
              query: {github_username, github_org, role_override, required_role}
                              │  curl + token de la GitHub App
                              │  → orgs/<org>/teams/<team>[-<sub>]/memberships/<u>
                              ▼
              {"role": "<rol>"}   ó   error (build falla) si no es miembro
                              │
              local.role ─────┴─▶ label coder.com/role + overlay + binarios + metadata "Rol"
```

Implementado en [`templates/mvp-embedded/main.tf`](../templates/mvp-embedded/main.tf) y
[`templates/mvp-embedded/scripts/resolve-role.sh`](../templates/mvp-embedded/scripts/resolve-role.sh).

## Mapping de teams → rol

| Team de GitHub (`Qintess-Latam`) | Rol | Plantilla |
|---|---|---|
| `qintess-architect` | `architect` (Producto: PM/PO) | `qintess-architecture-template` |
| `qintess-developers` | `developer` | `qintess-developer-template` |
| `qintess-platform` | `platform` | `qintess-platform-template` |
| `qintess-qa` | `qa` | `qintess-qa-template` |
| `qintess-cyber` | `cyber` | `qintess-cyber-template` |

Los sub-teams `<team>-senior-dev`, `-repo-admin`, `-release-eng` y `-appsec`
también otorgan el rol del padre (GitHub **no** hace al miembro de un sub-team
miembro del padre, así que el script los consulta explícitamente).

## Modos de operación del template

| Variables | Modo | Efecto |
|---|---|---|
| `template_role=<rol>` + `github_org=Qintess-Latam` | **Plantilla por rol** (actual) | Solo crea el workspace si el usuario está en el team del rol; si no, el build falla con mensaje claro. |
| `template_role=""` + `github_org=Qintess-Latam` | Genérica (`mvp-embedded`, obsoleta) | Rol automático; multi-team → gana el **menos** permisivo (`qa < developer < cyber < platform < architect`); sin team → `unknown`. |
| `github_org=""` | Override (sin GitHub) | Usa `default_role`. Solo para pruebas locales. |

> ✅ **Política única least-privilege** para la genérica: alineados `resolve-role.sh`,
> `prod-oidc/main.tf` y `docs/TO-BE/02`.

Subir las plantillas por rol: `bash deploy/vm/push-role-templates.sh`.

## GitHub OAuth App (login en Coder)

Hace que el **owner del workspace** sea el usuario de GitHub, así `resolve-role.sh`
recibe un `github_username` real.

1. `https://github.com/organizations/Qintess-Latam/settings/applications` → **New OAuth App**.
2. **Homepage URL** = `CODER_ACCESS_URL` (hoy `https://201.203.104.168:3000`);
   **Authorization callback URL** = la misma URL (la raíz cubre el login y
   `/external-auth/github/callback`). Una OAuth App acepta **un solo** callback.
3. **Client ID** + **client secret** a `~/.config/coderv2/server.env` (perm `600`, fuera de git):
   ```bash
   export CODER_OAUTH2_GITHUB_CLIENT_ID=<client_id>
   export CODER_OAUTH2_GITHUB_CLIENT_SECRET=<client_secret>
   export CODER_OAUTH2_GITHUB_ALLOWED_ORGS=Qintess-Latam
   export CODER_OAUTH2_GITHUB_ALLOW_SIGNUPS=true
   ```
4. `systemctl --user restart coder.service` y verificar:
   ```bash
   curl -s https://201.203.104.168:3000/api/v2/users/authmethods | jq .github   # enabled: true
   ```

## Credencial del provisioner (leer los teams)

`resolve-role.sh` usa, en este orden: `GH_TOKEN`/`GITHUB_TOKEN` del entorno →
**GitHub App** (`GITHUB_APP_ID`, `GITHUB_APP_INSTALLATION_ID`,
`GITHUB_APP_PRIVATE_KEY_PATH` en `server.env`; token de instalación de ~1 h) →
`gh` ambiente. En la VM se usa la **GitHub App `qintess-latam-rbac-resolver`**
(permiso único *Organization → Members: read*). Detalle:
[`RUNBOOK-github-app.md`](./RUNBOOK-github-app.md).

Para **administrar teams** por API hace falta un owner (o la GitHub App
`qintess-mozart-bot`, que tiene *members: write*):

```bash
gh api -X PUT orgs/Qintess-Latam/teams/qintess-qa/memberships/<user> -f role=member
```

## Pruebas

**Unitaria del script (sin Coder), con la credencial del provisioner:**

```bash
set -a; . ~/.config/coderv2/server.env; set +a
S=templates/mvp-embedded/scripts/resolve-role.sh
echo '{"github_username":"<user>","github_org":"Qintess-Latam","required_role":"qa"}' | bash "$S"   # {"role":"qa"} o error
echo '{"github_username":"<user>","github_org":"Qintess-Latam"}'                       | bash "$S"   # rol automático
echo '{"github_username":"x","role_override":"qa"}'                                    | bash "$S"   # {"role":"qa"} (override)
```

**Del workspace:**

```bash
docker inspect coder-<owner>-<ws> --format '{{ index .Config.Labels "coder.com/role" }}'
```

## Gotchas conocidos

1. **Owner = todos los teams.** Un owner de la org es maintainer *implícito* de
   todos los teams: en la plantilla genérica siempre resuelve el rol menos
   permisivo de la lista, y en las plantillas por rol pasa en todas. Para probar
   una denegación hace falta una cuenta **no-owner** (p. ej. un developer contra
   `qintess-platform-template`).
2. **Plan de importación con usuario `default`.** `coder templates push` corre un
   plan con un dueño ficticio `default`; el script lo deja pasar sin chequeo.
3. **Agregar a un owner a un team** lo deja como *maintainer* aunque se pida
   `member` (GitHub lo fuerza para owners).

## Estado actual (2026-10-15)

- ✅ Login GitHub OAuth en `Qintess-Latam`.
- ✅ 5 teams de rol con sub-teams; GitHub App `qintess-latam-rbac-resolver`.
- ✅ 5 plantillas por rol con validación de team; denegación probada con una cuenta no-owner.
- ✅ Mismo rol aplicado a Claude Code y Copilot CLI (overlay del rol).
