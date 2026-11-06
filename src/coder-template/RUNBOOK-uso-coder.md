# Runbook — Usar Coder (para cualquier rol)

Guía de uso diario, no de despliegue — para eso ver `RUNBOOK-vm-qintess-latam.md` y
`RUNBOOK-plantillas-por-rol.md`. Esto es "ya está instalado, ¿cómo lo uso?".

**URL:** https://201.203.104.168:3000

## 1 · Primer login (obligatorio antes de que exista tu usuario)

1. Entrar a la URL de arriba → **Sign in with GitHub**.
2. Autorizar con tu cuenta de GitHub — tiene que ser miembro de la organización
   `Qintess-Latam` y estar en al menos uno de los 5 teams de disciplina
   (`qintess-architect`, `qintess-cyber`, `qintess-developers`, `qintess-platform`,
   `qintess-qa`) o un sub-team suyo. Si no estás en ninguno, el login funciona pero
   no vas a poder crear workspace (ver sección 4, gobierno por rol).
3. El cert es self-signed (no hay dominio todavía) — el navegador va a avisar
   "conexión no segura" la primera vez. Aceptar para continuar.

> Sin este paso tu usuario **no existe** en Coder — nadie te puede crear un
> workspace a tu nombre hasta que hayas entrado una vez.

## 2 · Conectar GitHub y Atlassian (external-auth, una vez)

En el dashboard, botón de tu usuario (arriba a la derecha) → **Account** →
**External Authentication**:
- **GitHub**: Connect → autorizar. Esto es un token **tuyo**, distinto del login —
  hace que `git push` y el MCP de GitHub actúen con tu identidad, no la de la
  plataforma.
- **Atlassian**: Connect → autorizar. Si ves *"you don't have access to this
  app"*, avisa a platform — la OAuth App de Atlassian tiene que estar en modo
  *Sharing/Distributed*, no *Development* (gotcha conocido, ver
  `MANUAL-TECNICO.md` §17).

Ambos quedan guardados — no hay que repetir esto en cada workspace nuevo.

## 3 · Crear un workspace

1. **Templates** → elegir la plantilla de tu rol (`qintess-architect-template`,
   `qintess-developer-template`, `qintess-qa-template`, etc.).
2. **Create Workspace** → nombre a elección → **Create**.
3. Esperar ~10-20s (instala binarios + aplica tu overlay de persona/skills/MCP).
4. Abrir el workspace → vas a ver un panel con: tu rol, estado de GitHub/Atlassian,
   botón **Claude CLI**, botón **GitHub Copilot** (si tenés seat asignado), y el
   *Estimated AI spend/month*.

## 4 · Gobierno por rol (qué pasa si no tenés el team correcto)

Cada plantilla valida en el `startup_script` que tu usuario pertenezca al team de
ese rol. Si intentás crear un workspace de un rol que no es el tuyo, el build
**falla a los pocos segundos** con un mensaje explícito de que no pertenecés al
team — no es un bug, es la gobernanza funcionando. Pedile a alguien de
`qintess-platform` que te agregue al team/sub-team correcto si creés que
debería dejarte.

## 5 · Dentro del workspace

- **`/login`** en Claude Code una vez por workspace — queda guardado en tu home,
  persiste entre reinicios del workspace.
- `gh auth status` debería mostrar tu identidad de GitHub ya autenticada (viene
  del external-auth, no hay que hacer `gh auth login` a mano).
- Cada rol trae sus propias **skills** ya cargadas (ver
  `qintess-platform-agents-skills` — `catalog.yaml` por equipo) y su propio
  **`settings.json`** con permisos (qué comandos puede correr sin preguntar, qué
  queda bloqueado) — esto no se configura, ya viene aplicado por tu rol.

## 6 · Problemas comunes

| Síntoma | Causa | Qué hacer |
|---|---|---|
| `HEALTHY=false` en `coder list` pero el contenedor corre | El agente no puede alcanzar `CODER_ACCESS_URL` (ej. cambió la IP de la VM) | Avisar a platform — no es algo que un usuario final pueda arreglar |
| Build de workspace falla a los segundos | No pertenecés al team del rol de esa plantilla | Ver sección 4 |
| Copilot sin modelos disponibles | No tenés seat de Copilot Business asignado | Pedir seat a platform (ver `RUNBOOK-copilot-business.md`) |
| Jira MCP da 401 tras una sesión larga (>1h) | Gotcha conocido del token de Atlassian | Reconectar el MCP (no hace falta recrear el workspace) — ver `MANUAL-TECNICO.md` §17 |
