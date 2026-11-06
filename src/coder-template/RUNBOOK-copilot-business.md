# Runbook — Activar GitHub Copilot Business en Qintess-Latam

Pasos para activar Copilot Business cuando se resuelva la verificación de
identidad/pago de la organización (ítem 1 de "Qué falta de verdad" en
[`docs/MVP.md`](./MVP.md) — es la misma verificación la que bloquea Actions
y Copilot, no son dos problemas separados).

## Por qué Business y no Pro individual

Decisión ya tomada (ver la sesión que generó este doc): **Copilot Business
por organización**, no licencias individuales de Copilot Pro pagadas por
cada persona. Pro individual ($10/mes) es más barato por asiento que
Business ($19/asiento/mes), pero la org pierde todo control — sin
revocación centralizada al salir alguien, sin políticas de contenido/modelo,
sin auditoría agregada, sin integración con los GitHub Teams (RBAC por
disciplina) que ya están armados. En un contexto bancario, ese control vale
más que los $9/asiento/mes de diferencia.

## ⚠️ Importante: self-service pausado para planes Free/Team (desde 2026-04-22)

GitHub [pausó las altas de autoservicio de Copilot Business](https://github.blog/changelog/2026-04-22-pausing-new-self-serve-signups-for-github-copilot-business/)
para organizaciones en plan **Free o Team** — que es el plan actual de
`Qintess-Latam` (confirmado: `plan.name: "free"`). Los clientes que ya
tenían Copilot Business activo antes de esa fecha no se ven afectados y
pueden seguir agregando asientos normalmente — el problema es específico
para **altas nuevas**.

No hay fecha anunciada de reapertura. Esto significa que el flujo estándar
de self-service (Settings → Copilot → Access → "Start adding seats") puede
no estar disponible incluso después de resolver la verificación de la org.
**Verificar primero cuál de los dos caminos aplica** (paso 0 abajo) antes
de asumir cualquiera de los dos.

## Paso 0 — Confirmar si el self-service ya reabrió

Antes de seguir cualquiera de los dos caminos:

1. Entrar a `github.com/organizations/Qintess-Latam/settings/copilot/access`
   con una cuenta de **owner** de la org.
2. Si aparece el botón **"Allow this organization to assign seats"** o
   **"Start adding seats"** → self-service disponible, seguir el
   **Camino A**.
3. Si la página dice que la compra de nuevos asientos Business está
   restringida para organizaciones en plan Free/Team → seguir el
   **Camino B** (vía Sales).

## Camino A — Self-service (si está disponible)

1. `github.com` → foto de perfil (arriba a la derecha) → **Organizations**.
2. Seleccionar **Qintess-Latam**.
3. **Settings** → en la barra lateral, bajo "Code, planning, and
   automation" → **Copilot** → **Access**.
4. Si aparece el botón **"Allow this organization to assign seats"**,
   hacer click.
5. Click en **"Start adding seats"**.
6. Elegir **"Purchase for selected members"** (NO "Purchase for all
   members" — ver sección "Cómo asignar los asientos" abajo, por qué
   seleccionado y no todos).
7. En el diálogo "Enable Copilot access for users and teams", pestaña
   **Users and teams** → buscar y agregar los 5 teams de disciplina
   (`qintess-architect`, `qintess-cyber`, `qintess-developers`,
   `qintess-platform`, `qintess-qa`) o los sub-teams puntuales que
   correspondan (ver abajo).
8. **Continue to purchase** → **Purchase seats**.

## Camino B — Vía GitHub Sales (ruta actual mientras dure la pausa)

Mientras el self-service esté pausado, el camino soportado por GitHub es
pedir una **"dedicated enterprise for GitHub Copilot Business"** — una
Enterprise Account separada que existe solo para alojar las licencias de
Copilot, sin migrar ni tocar el org/repos actuales de `Qintess-Latam`.

1. Ir a [`github.com/enterprise/contact`](https://github.com/enterprise/contact)
   (o contactar al account rep si ya hay uno) y pedir explícitamente:

   > "Somos una organización en GitHub Team/Free (`Qintess-Latam`) y
   > queremos comprar N asientos de GitHub Copilot Business a través de
   > una dedicated enterprise for GitHub Copilot Business, mientras el
   > self-serve está pausado para planes Free/Team."

2. Confirmar con Sales estos 3 puntos (ya los tienen documentados como
   parte de ese flujo, pero confirmar por escrito):
   - El org `Qintess-Latam` **se queda en su plan actual** (Free/Team) —
     no se migra ni se absorbe en la Enterprise Account nueva.
   - Los usuarios se agregan **directamente a la Enterprise Account** como
     miembros "unaffiliated" (no se tocan sus membresías en
     `Qintess-Latam`), solo para asignarles la licencia de Copilot.
   - La factura es **solo** por los asientos de Copilot Business
     ($19/usuario/mes) — vincular la org a la Enterprise Account de esta
     forma **no** dispara el cobro de GitHub Enterprise Cloud
     ($21/usuario/mes) sobre nadie. Pedir que esto quede explícito antes
     de confirmar.
3. Una vez aprobado y los asientos comprados, la asignación a usuarios se
   hace desde el panel de la Enterprise Account (no desde
   `Qintess-Latam/settings`) — Sales da el link exacto al cerrar el trato.

## Cómo asignar los asientos (cualquiera de los 2 caminos)

**No comprar "para todos los miembros".** Asignar por team, empezando por
quien ya lo necesita, no por default a todo el roster — más fácil de
auditar gasto y de ajustar si alguien no lo usa. Dado que `overlays_host_path`
ya separa personas por rol, lo natural es asignar Copilot por los mismos
5 teams de disciplina que ya existen en la org:

```
qintess-architect
qintess-cyber
qintess-developers
qintess-platform
qintess-qa
```

(Ver `qintess-platform-agents-overlays` para el `CLAUDE.md`/`mcp-config.json`/
`settings.json` que cada rol ya tiene — Copilot CLI en el workspace de Coder
lee los mismos overlays que Claude Code, así que en cuanto el asiento esté
asignado, la terminal "GitHub Copilot" del `coder_app` (`templates/mvp-embedded/main.tf`)
va a tener modelos disponibles sin ningún cambio de código de este repo.)

## Verificación post-activación

1. En un workspace de Coder cualquiera (`CODER_ROLE` = cualquiera de los 5),
   abrir la pestaña **"GitHub Copilot"**.
2. Confirmar que ya no aparece el error de "no hay modelos disponibles" —
   eso era por falta de asiento, no por configuración del template.
3. Actualizar el ítem 3 y 5 de "Qué falta de verdad" en
   [`docs/MVP.md`](./MVP.md) a resuelto.
