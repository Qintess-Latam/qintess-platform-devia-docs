# DEMO — de la idea a la prueba validada (architect → developer → QA)

Una sola historia atraviesa tres roles. Cada rol trabaja en **su** workspace, con **su**
persona, herramientas y permisos, y se pasan el trabajo por un repo de GitHub.

**Caso:** *Simulador de crédito* — dado monto, tasa anual y plazo en meses, calcular la
cuota mensual y la tabla de amortización. Es pequeño, tiene reglas de negocio claras
(validaciones, redondeo) y se puede probar de forma objetiva.

**Repo de traspaso:** `Qintess-Latam/qintess-developers-simulador-credito-service`. No lo crea quien lo pide:
lo pide el **architect** (o el developer) y lo crea y deja configurado el **actor de platform**
desde Backstage/mozart. Por la convención de mozart el nombre final es
`<team dueño>-<nombre>-<arquetipo>`: team `qintess-developers`, nombre `simulador-credito`,
arquetipo `service`. Hoy **no hay pipeline de DevSecOps** (ver "Alcance"). Estructura final:

```
docs/historia.md        ← architect
docs/arquitectura.puml  ← architect
app/                    ← developer (Python + FastAPI)
tests/                  ← developer (pytest)
qa/api.spec.ts          ← QA (Playwright)
qa/carga.js             ← QA (k6)
qa/informe.md           ← QA
```

## Reparto

| Rol | Persona | Workspace | Plantilla |
|---|---|---|---|
| Architect (PM/PO) | Boris (`BorisFRQintess`) y Luis (`LuisRZQintess`) | `BorisFRQintess/demo-architect` (Boris conduce; Luis de apoyo, con su propio workspace) | `qintess-architecture-template` |
| Platform (solo para crear el repo) | Juan (`JuanPDQintess`, el mismo que QA) | no necesita workspace: usa Backstage | `qintess-platform-template` (opcional) |
| Developer | Fabian (`FabianGAQintess`) | `FabianGAQintess/dev-fabian` | `qintess-developer-template` |
| QA | Juan (`JuanPDQintess`) | `salmon-cicada-81` | `qintess-qa-template` |

## Alcance

- Participan **architect, developer y QA**; **platform** interviene solo para crear y
  configurar el repo. Cyber no participa.
- **Sin pipeline de DevSecOps:** no hay CI ni escaneos automáticos. Las pruebas las corre
  cada rol a mano en su workspace y el informe de QA es manual.
- **Plan de GitHub: Free (confirmado por API el 2026-10-19) → decisión: seguir en Free.**
  Los Rulesets no se aplican a repos privados, así que ni las aprobaciones ni los checks
  bloquean el merge. El arquetipo `service` define los checks `build` y `test`; su skeleton
  crea `.github/workflows/ci.yml` con esos jobs, que **solo muestran un echo**. Ensayado el
  2026-10-19: repo creado por mozart con el workflow, PR hacia `integration` con ambos
  checks en verde y `CLEAN`. En la demo se dice tal cual: *"el flujo y los checks están
  definidos; la protección obligatoria se activa al subir de plan"*. Si algún día se sube a
  Team, no cambia código, pero hay que bajar las aprobaciones (2-3 es inviable con pocos
  usuarios).
- **Los checks pueden tardar** si GitHub Actions está degradado (el ensayo esperó ~25 min
  por un incidente). Abrir el PR con tiempo y no depender del check en vivo.
- Flujo de ramas simplificado para la demo: el developer abre el PR hacia `integration`,
  y QA prueba desde `integration`.

## Antes de la demo (checklist)

- [x] Backstage "Symphony" accesible y mozart probado por CLI (repo de ensayo creado y borrado, 2026-10-19).
- [x] Actor de platform definido: Juan.
- [x] Backstage redesplegado con los arquetipos nuevos; el repo de ensayo trajo `.github/workflows/ci.yml` y los checks pasaron.
- [ ] Imagen de architect reconstruida **con Graphviz** (sin él, PlantUML genera un PNG de error) y plantilla re-subida.
- [ ] Ensayar el formulario real de Backstage (los campos y el nombre final del repo).
- [ ] Richard hizo login en Coder al menos una vez (para la denegación del cierre).
- [ ] Boris y Luis hicieron login en Coder (`https://201.203.104.168:3000`, GitHub) al menos una vez: sin eso su usuario no existe y no se les puede crear workspace.
- [ ] Los 3 workspaces corriendo y con el panel en verde (Claude, GitHub, Atlassian).
- [ ] Cada usuario hizo `/login` en Claude Code una vez (queda en su home).
- [ ] `gh auth status` correcto en cada workspace (external-auth).
- [ ] Ensayo completo con la red real (el Wi-Fi de la VM es el riesgo principal).
- [ ] Plan B: salida de cada paso guardada en una rama `backup/paso-N`.
- [ ] Para la denegación: una cuenta que **no** sea owner (Richard) intentando usar la
      plantilla de otro rol.

## Secuencia

| # | Quién | Qué | Tiempo | Entrega |
|---|---|---|---|---|
| 0 | Presentador | Crear los 3 workspaces en vivo, mostrar el panel | 3 min | workspaces listos |
| 0b | Architect pide → Platform crea | Solicitud con nombre, descripción y arquetipo; platform crea y configura el repo en mozart | 4 min | repo listo |
| 1 | Architect | Historia + criterios + diagrama | 5 min | `docs/` en `integration` |
| 2 | Developer | Implementación + pruebas + PR | 8 min | PR abierto |
| 3 | QA | Pruebas de API y de carga + informe | 7 min | `qa/` + informe |
| 4 | Presentador | Cierre: gasto de IA por usuario, denegación por rol | 3 min | — |

## Prompts

> Cada prompt se pega tal cual en **Claude Code** del workspace (botón *Claude CLI*).
> Entre corchetes lo que cambia por persona.

### Paso 0 — Presentador (terminal de la VM)

Cada persona crea el suyo (10 s) o, para ir más rápido, el presentador (owner de la org)
los crea a nombre de ellos. Los de Fabian (`dev-fabian`) y Juan (`salmon-cicada-81`) ya existen;
si se quiere mostrar la creación en vivo, borrarlos antes y recrearlos:

```bash
coder create --yes -t qintess-architecture-template BorisFRQintess/demo-architect
coder create --yes -t qintess-developer-template    FabianGAQintess/dev-fabian
coder create --yes -t qintess-qa-template           JuanPDQintess/salmon-cicada-81
```

> Los usuarios deben haber entrado a Coder una vez (si no, su usuario no existe).

Mostrar el panel de cada uno: Rol, Claude CLI, GitHub OK, Atlassian OK, herramientas
del rol, *Estimated AI spend/month*. **Qué decir:** "Cada rol recibe su entorno en 10 segundos, con sus herramientas y su IA ya configuradas; antes tardaba casi una hora".

### Paso 0b — El architect pide el repo; platform lo crea (Backstage/mozart)

**Solicitud del architect** (por chat o ticket; también puede pedirla el developer). Debe
traer el nombre, la descripción y el arquetipo:

```
Platform: necesitamos un repositorio nuevo.
- Nombre: simulador-credito
- Descripción: Simulador de crédito (cuota mensual y tabla de amortización, sistema francés)
- Arquetipo: service
- Equipo dueño: qintess-developers
- Acceso: escritura para architect, developers y qa
```

**Platform** entra a `https://201.203.104.168:7007`, usa la plantilla de creación de repo con
esos datos (el formulario muestra el nombre final `qintess-developers-simulador-credito-service`), y lo deja configurado:
equipos con acceso (architect, developers, qa), rama por defecto y flujo de ramas del
arquetipo.

> **Ojo:** mozart da acceso de escritura **solo al team dueño** (`qintess-developers`). Boris y
> Luis (architect) no podrían subir al repo. Platform agrega los otros dos teams:
>
> ```bash
> for t in qintess-architect qintess-qa; do
>   gh api -X PUT orgs/Qintess-Latam/teams/$t/repos/Qintess-Latam/qintess-developers-simulador-credito-service -f permission=push
> done
> ```
> (Juan es owner de la org y ya tiene acceso.)

Confirma al architect con el enlace al repo. En el ensayo, anotar aquí los campos exactos del
formulario.

**Qué decir:** "El architect no crea repos: pide uno con nombre, descripción y arquetipo; platform
lo crea con la plantilla de la organización y ya queda con ramas, CODEOWNERS y CI base".

### Paso 1 — Architect (workspace `demo-architect`)

**Qué decir:** "El architect trabaja con una IA que ya sabe su rol: historias, criterios y diagramas, sin instalar nada".

**Prompt 1.1** — historia y criterios:

```
Eres el PO de un proyecto nuevo. Clona el repo Qintess-Latam/qintess-developers-simulador-credito-service
en ~/workspace y cambia a la rama integration. Necesitamos un "Simulador de crédito": el usuario ingresa monto,
tasa de interés anual (%) y plazo en meses, y recibe la cuota mensual y la tabla de
amortización (sistema francés). Escribe docs/historia.md con: historia de usuario
en formato "Como... quiero... para...", reglas de negocio (monto > 0, tasa entre 0 y
100, plazo entre 1 y 360, redondeo a 2 decimales) y criterios de aceptación en
Given/When/Then, numerados CA-1, CA-2... Incluye al menos un ejemplo numérico
verificable (monto 10000, tasa 12 %, 12 meses → cuota 888.49) y 3 casos de error.
```

**Prompt 1.2** — diagrama:

```
Con la historia anterior, crea docs/arquitectura.puml con un diagrama de componentes
PlantUML: cliente, API REST (POST /simulaciones), motor de cálculo y validaciones.
Genera también el PNG con plantuml y ábrelo para verificar que el diagrama se dibujó
(no un mensaje de error).
```

**Prompt 1.3** — publicar:

```
Haz commit de docs/ con el mensaje "docs: historia y arquitectura del simulador" y
haz push a la rama integration. Muéstrame el enlace del commit.
```

*(Opcional si Atlassian está listo: "Crea una página en Confluence con el resumen de
docs/historia.md y un ticket en Jira por cada criterio de aceptación".)*

### Paso 2 — Developer (workspace `dev-fabian`)

**Qué decir:** "El developer parte de lo que dejó el architect: la IA lee la historia y trabaja con pruebas primero".

**Prompt 2.1** — leer y planear:

```
Clona Qintess-Latam/qintess-developers-simulador-credito-service en ~/workspace y cambia a la
rama integration. Lee docs/historia.md y docs/arquitectura.puml. Antes de escribir código, dame un plan corto: archivos a
crear, endpoints y cómo cubrirás cada criterio CA-n con una prueba.
```

**Prompt 2.2** — pruebas primero:

```
Crea un proyecto Python con uv y FastAPI. Escribe primero las pruebas pytest en
tests/ que cubran TODOS los criterios de aceptación de docs/historia.md (usa el
ejemplo 10000 / 12 % / 12 meses → 888.49) y los casos de error. Ejecútalas y
confirma que fallan.
```

**Prompt 2.3** — implementar:

```
Implementa app/ para que todas las pruebas pasen: POST /simulaciones con validación
(422 en entradas inválidas), cálculo de cuota y tabla de amortización con redondeo a
2 decimales; la última cuota ajusta el saldo a 0.00. Corre pytest y muestra el
resultado. Documenta en README.md cómo instalar y levantar la API
(por ejemplo `uv run uvicorn app.main:app --port 8000`). No cambies las pruebas para que pasen.
```

**Prompt 2.4** — PR:

```
Crea la rama feature/simulador, haz commit y push, y abre un Pull Request hacia integration
con una descripción que liste cada CA-n y la prueba que lo cubre. No hagas merge.
```

*(Presentador, al terminar: hacer merge del PR a `integration` a mano. No hay pipeline que lo valide.)*

### Paso 3 — QA (workspace `salmon-cicada-81`)

**Qué decir:** "QA no depende de que desarrollo le explique nada: lee los mismos criterios y los convierte en pruebas".

**Prompt 3.1** — entender y levantar:

```
Clona Qintess-Latam/qintess-developers-simulador-credito-service en ~/workspace (rama integration, ya con el
merge del PR). Lee docs/historia.md. Instala las dependencias y levanta la API en el puerto 8000
en segundo plano siguiendo el README, y confirma que responde. No modifiques app/.
```

**Prompt 3.2** — pruebas de API con Playwright:

```
En qa/ instala @playwright/test con npm (solo pruebas de API, no hacen falta navegadores).
Crea qa/api.spec.ts con Playwright (request API testing) que cubra cada CA-n de
docs/historia.md contra http://localhost:8000. Incluye valores límite (plazo 1 y
360, tasa 0 y 100) además de los ejemplos. Ejecútalas y muestra el resultado.
```

**Prompt 3.3** — carga con k6:

```
Crea qa/carga.js con k6: 20 usuarios virtuales durante 30 segundos contra
POST /simulaciones con un cuerpo válido. Umbrales: p95 < 300 ms y errores < 1 %.
Ejecútalo y resume si pasa o falla.
```

**Prompt 3.4** — informe y defectos:

```
Escribe qa/informe.md con: criterios cubiertos (tabla CA-n → prueba → resultado),
resultados de carga, y defectos encontrados con pasos para reproducir y severidad.
Si encontraste un defecto, NO lo arregles: descríbelo para devolverlo a desarrollo.
Haz commit y push de qa/.
```

*(Si se quiere mostrar el valor de QA: pedirle al developer que deje a propósito un defecto
sutil —p. ej. redondeo de la última cuota— y que QA lo encuentre y lo reporte. Ensayarlo antes.)*

### Paso 4 — Cierre (presentador)

1. En cada workspace, mostrar `qintess-ai-spend` / el panel: gasto de IA por usuario.
2. **Gobierno por rol:** con la cuenta de Richard (developer, ya con login en Coder) crear un
   workspace con `qintess-platform-template` → el build falla a los pocos segundos con el
   mensaje de que no pertenece al team del rol. Que sea una cuenta que no sea owner.
3. Mostrar el historial del repo: tres personas, tres roles, una historia completa.

## Tiempos

Los 26 min son una **estimación**: aún no se ha cronometrado a Claude generando cada paso. El
ensayo completo debe medirlos; si un paso pasa de lo previsto, recortar prompts (por ejemplo,
omitir k6 o el diagrama) en vez de acelerar en vivo.

## Riesgos y plan B

| Riesgo | Mitigación |
|---|---|
| Red lenta (instalar FastAPI/pytest) | Ensayar antes: la caché de uv queda en el home del workspace |
| Claude genera algo distinto | Ramas `backup/paso-N` con cada entrega ya hecha |
| Login de Claude/GitHub caduca | Verificar `/login` y `gh auth status` el día anterior |
| mozart falla o tarda | Tener un repo `qintess-developers-simulador-credito-service-respaldo` ya creado del ensayo |
| Un paso tarda de más | Cada prompt es independiente: se puede saltar al `backup/paso-N` siguiente |
