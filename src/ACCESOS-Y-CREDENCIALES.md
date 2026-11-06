# Accesos y Credenciales — Dev-IA

> **Los valores reales de los secretos NO están en este documento.** Cada fila marcada
> `[PENDIENTE]` la completa quien tenga acceso real, directo en el archivo final — nunca
> pegando el valor en un chat (ni acá, ni en Claude, ni en ningún otro canal sin cifrar).
> Esto es un **inventario**: qué existe, para qué, y dónde vive — no el secreto en sí.

## 1 · Infraestructura física

| Ítem | Valor |
|---|---|
| VM / laptop que corre todo | `192.168.50.208` (IP interna, puede cambiar — ver RUNBOOK-vm-qintess-latam.md) |
| IP pública (port forwarding, sin dominio) | `201.203.104.168` (puertos 3000 → Coder, 7007 → Symphony) |
| Acceso SSH a la VM | `[PENDIENTE: usuario, método de auth (key/password), quién tiene acceso hoy]` |
| Sudo en la VM | `[PENDIENTE: quién tiene, cómo se gestiona]` |
| Orquestación de contenedores | Portainer (Coder, Caddy, Backstage, PostgreSQL) — `[PENDIENTE: URL del panel, quién tiene login]` |
| Backups | Diarios, de la BD de Coder (ver RUNBOOK-vm-qintess-latam.md) — `[PENDIENTE: destino exacto, retención, quién los puede restaurar]` |

## 2 · GitHub — organización `Qintess-Latam`

**Cuatro credenciales distintas, no intercambiables** (ver sección 03 y 17 de `MANUAL-TECNICO.md` para el detalle de por qué están separadas):

| Credencial | Tipo | Para qué | Dónde vive el secreto | Vence |
|---|---|---|---|---|
| OAuth App **"Coder VM"** | GitHub OAuth App | Login de usuarios a Coder (AuthN) | Client Secret: `[PENDIENTE]` — Settings → Developer settings → OAuth Apps → Coder VM | No vence (revocable a mano) |
| OAuth App **"Qintess Backstage"** | GitHub OAuth App | Login de usuarios a Symphony (AuthN) | Client Secret: `[PENDIENTE]` | No vence |
| GitHub App **`qintess-latam-rbac-resolver`** | GitHub App | AuthZ: resuelve el rol del usuario por membresía de team (`Members: read`, token auto-rotado ~1h) | Private key `.pem`: `[PENDIENTE: ruta exacta en la VM]` | Private key no vence (se puede rotar) |
| GitHub App **`qintess-mozart-bot`** | GitHub App | Backstage/mozart: crea repos, equipos, lee billing de Copilot | App ID `5202581`, Installation ID `168285622`. Private key: `~/.config/backstage/secrets/mozart-app.pem` en la VM. Client Secret: `~/.config/backstage/secrets/mozart-app-client-secret` en la VM | Private key no vence; Client Secret regenerable a mano |
| external-auth OAuth (GitHub) | Token por usuario | Que el workspace actúe como ESE usuario (`git push`, GitHub MCP) | Lo gestiona Coder automáticamente, no hay secreto estático que guardar | Coder lo auto-refresca |
| PAT personal (uso de desarrollo, legado) | Personal Access Token | Fallback de `gh auth token` si no hay GitHub App configurada | `[PENDIENTE: a quién pertenece hoy]` | **Vence el 2026-12-31** — plan es no depender de él (ya migrado a GitHub Apps en mozart) |

**Teams de la org** (5 disciplinas, cada una con sub-teams `-senior-dev`, `-repo-admin`,
`-release-eng`, y `-appsec`): `qintess-architect`, `qintess-cyber`, `qintess-developers`,
`qintess-platform`, `qintess-qa`. Otorgar/quitar rol = agregar/quitar de estos teams en
GitHub, nada más.

## 3 · Atlassian (Jira/Confluence)

| Ítem | Valor |
|---|---|
| OAuth App de Atlassian (external-auth) | Client ID/Secret: `[PENDIENTE]` — developer.atlassian.com/console |
| Modo de distribución | **Debe estar en "Sharing/Distributed"**, no "Development" — si está en Development, solo el dueño puede autorizarla y el resto ve error. Ver gotcha en sección 17 de `MANUAL-TECNICO.md`. |
| Gotcha de token de 1h | El MCP de Atlassian pide el token fresco a Coder en cada arranque (`coder external-auth access-token atlassian`) — NO usa una copia horneada en build time. Ya resuelto, documentado en `MANUAL-TECNICO.md` sección 17. |

## 4 · Backend LLM (Claude / Copilot)

| Ítem | Valor |
|---|---|
| Autenticación de Claude Code | Login por usuario (`/login` en cada workspace) — no hay API key compartida hoy |
| Backend de producción (Vertex/Bedrock vs. suscripción) | Sin decidir — ver `MVP.md` ítem de decisiones abiertas |
| GitHub Copilot Business | **Activado** — seats asignados por team de rol (ver `RUNBOOK-copilot-business.md` y commit `6cf2fcf`) |

## 5 · Checklist para dar de alta a una persona nueva

1. Agregarla al team de GitHub de su disciplina (`qintess-<rol>` o un sub-team).
2. Que haga login una vez en Coder (`https://201.203.104.168:3000`) con su cuenta de GitHub — sin esto su usuario no existe en Coder y no se le puede crear workspace.
3. Que conecte GitHub y Atlassian desde la UI de Coder (external-auth, 1 clic cada uno).
4. Crear su workspace con la plantilla del rol correspondiente.
5. Que haga `/login` en Claude Code dentro del workspace (queda guardado en su home, persiste).

## 6 · Pendientes reales (no es que falte documentar, es que falta resolver)

Ver `coder-template/MVP.md` para la lista completa y actualizada. Resumen al momento de armar
este documento:
- Dominio propio + Cloudflare Tunnel (hoy se accede por IP pública pelada, sin dominio).
- Decisión de backend LLM de producción (Vertex/Bedrock vs. token compartido).
- Decisión de external-auth único (Coder OSS solo permite 1 proveedor externo con licencia libre; hoy hay 2 — banner de "Enterprise feature").
- Kubernetes / network isolation / secretos por usuario vía Vault — diferido por decisión, no empezado.
