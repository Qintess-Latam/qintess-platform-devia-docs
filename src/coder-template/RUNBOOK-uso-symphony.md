# Runbook — Usar Symphony (Backstage + mozart)

Guía de uso diario — para despliegue/rebuild del backend ver `backstage-mngr/README.md` y
`RUNBOOK-vm-portainer-red.md`. Esto es "ya está instalado, ¿cómo lo uso?".

**URL:** https://201.203.104.168:7007

## 1 · Login

**Sign in with GitHub** — misma cuenta/org que Coder (`Qintess-Latam`), pero es una
**OAuth App distinta** ("Qintess Backstage", no "Coder VM") — loguearte en Coder no te
loguea automáticamente en Symphony, hay que hacerlo en los dos.

## 2 · Pedir un repo nuevo (cualquier rol puede pedirlo)

El flujo real: **quien necesita el repo NO lo crea él mismo** — lo pide, y alguien de
`qintess-platform` lo crea desde Symphony con la plantilla "Crear repositorio". Esto
mantiene un solo punto de creación gobernado, en vez de que cada equipo cree repos a
su manera.

**La solicitud debe traer 4 datos:**
1. **Nombre** — sin el prefijo del team, mozart lo agrega solo (ver sección 3).
2. **Descripción** — una línea, qué hace el repo.
3. **Arquetipo** — `service`, `library`, o `pipeline` (ver sección 4, importa mucho cuál
   elegís: cambia el flujo de ramas y quién tiene que aprobar).
4. **Equipo dueño** — una de las 5 disciplinas (`qintess-architect`, `qintess-cyber`,
   `qintess-developers`, `qintess-platform`, `qintess-qa`).

## 3 · Quien crea el repo (platform): usar la plantilla

1. Symphony → **Create** → template **"Crear repositorio"**.
2. Completar los 4 campos de la solicitud. El selector de **Team dueño** hace fetch en
   vivo de los 5 teams reales de la org — no hay que escribirlo a mano.
3. El formulario muestra el **nombre final** antes de confirmar:
   `<team>-<nombre>-<arquetipo>` (ej. `qintess-developers-simulador-credito-service`) —
   excepto si el arquetipo es `pipeline`, que agrega `-pipeline` al final en vez de
   `-service`/`-library`.
4. Confirmar. mozart crea el repo, aplica el arquetipo, y queda listo en segundos.

> **Si quien pidió el repo no es del team dueño** (ej. architect pide un repo para
> `qintess-developers`), mozart solo le da acceso de escritura al team dueño por
> default — hay que agregar los otros teams a mano:
> ```bash
> gh api -X PUT orgs/Qintess-Latam/teams/<otro-team>/repos/Qintess-Latam/<repo> -f permission=push
> ```

## 4 · Qué trae cada arquetipo (esto decide cómo se trabaja después)

| Arquetipo | Flujo de ramas | Quién aprueba | Para qué |
|---|---|---|---|
| **`service`** | `feature/* → integration → laboratory → main` | integration: 2 (senior-dev) · laboratory: 2 (repo-admin + senior-dev) · main: 3, merge solo squash | Backend/servicio desplegable |
| **`library`** | igual que `service` | igual que `service` | Paquete compartido — mismo rigor, porque romperlo afecta a TODOS sus consumidores |
| **`pipeline`** | trunk-based, solo `main` | main: 2 (release-eng + appsec del team dueño) | CI/CD, automatización — sin ramas intermedias |

Esto no es configuración manual — queda aplicado automático al crear el repo (CODEOWNERS
+ rulesets de GitHub por rama). Ver `qintess-platform-backstage-mngr/archetypes/*/archetype.yaml`
si necesitás el detalle exacto.

**Limitación real a tener en cuenta:** GitHub no puede exigir "una aprobación del team A
Y otra del team B" como regla dura — solo "N aprobaciones, al menos una de un codeowner".
El número de revisores sí queda forzado; que sean exactamente los roles de la tabla de
arriba es, en parte, proceso del equipo, no un bloqueo 100% mecánico.

## 5 · Trabajar sobre el repo ya creado

El flujo normal de ahí en adelante es el mismo para cualquier repo con arquetipo
`service`/`library`:
1. Clonar, rama `feature/<lo-que-sea>` desde `integration`.
2. PR hacia `integration` — necesita las aprobaciones de la tabla de arriba.
3. De `integration` a `laboratory`, y de `laboratory` a `main` — mismo patrón, cada vez
   más exigente.

(Ver `DEMO-guion.md` para un ejemplo completo punta a punta con prompts reales de Claude
Code en cada paso — architect → developer → QA sobre un repo creado así.)

## 6 · Problemas comunes

| Síntoma | Causa | Qué hacer |
|---|---|---|
| Error de CORS al loguear (`Origin ... is not allowed`) | `app-config.yaml` de Symphony desactualizado respecto a la URL real | Avisar a platform — no es algo que se arregle del lado del usuario |
| "No puedo aprobar/mergear" aunque tengo el rol correcto | Puede ser que falte el sub-team exacto (ej. `<team>-senior-dev`) en vez de solo el team padre | Confirmar membresía exacta del sub-team con platform |
| El repo nuevo no tiene CODEOWNERS funcionando | Los sub-teams `<team>-senior-dev`/`-repo-admin`/etc. no existen para esa disciplina | `policy.check_subteams_exist()` de mozart debería haber bloqueado la creación antes — si pasó, avisar a platform como bug |
