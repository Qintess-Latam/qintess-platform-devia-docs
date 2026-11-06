# Análisis de Specs — Waitly (ebar0n/waitly)

## Cómo fueron creados estos specs

### Patrón Estructural

Cada spec sigue una **estructura consistente** con estas secciones:

| Sección | Propósito | Presente en todos |
|---------|-----------|:-:|
| # Spec NN — Título | Identifica el spec | ✅ |
| ## Objetivo | Una oración que dice QUÉ se va a hacer y POR QUÉ | ✅ |
| ## [Concepto técnico] | Explica el modelo de datos, schema, flujo | ✅ |
| ## Archivos a crear / modificar | Lista exacta de paths + qué hacer en cada uno | ✅ |
| ## Conceptos destacados | Bullets educativos del "por qué" detrás de cada decisión | ✅ |
| ## Al finalizar | Qué docs actualizar post-implementación | 5/7 |
| ## TODO producción | Limitaciones actuales y qué falta para prod | 2/7 |

### Principios de Diseño Observados

1. **Incremental y acumulativo** — Cada spec construye sobre los anteriores:
   - 01: Secrets Store → 02: D1 Database → 03: KV → 04: R2 → 05: DO → 06: Workflows → 07: Rate Limiting
   - Nunca rompen lo anterior, siempre extienden

2. **Un concepto por spec** — Cada spec introduce exactamente UN servicio/binding de Cloudflare:
   - 01 = Secrets Store
   - 02 = D1 (SQLite)
   - 03 = KV
   - 04 = R2
   - 05 = Durable Objects
   - 06 = Workflows
   - 07 = Rate Limiting API

3. **Orientado a la implementación, no a la teoría** — Incluyen:
   - Código real (SQL schemas, TypeScript snippets, bash commands)
   - Paths exactos de archivos
   - Configuración literal de wrangler.jsonc
   - Comandos CLI para crear recursos

4. **Contexto suficiente para actuar sin preguntar** — El agente/developer puede implementar sin preguntas porque el spec incluye:
   - Schema completo (no "diseña un schema apropiado")
   - Endpoints con método, path, auth y body
   - Decisiones ya tomadas con justificación
   - Edge cases resueltos (ej: "qué pasa si el email ya existe")

5. **Decisiones explícitas con razonamiento** — No solo dice "usa waitUntil" sino POR QUÉ:
   > "El insert debe ir en ctx.waitUntil(): la respuesta 201 se envía al cliente inmediatamente, el insert ocurre en background. **Límite**: 30 segundos."

6. **Límites claros** — Cada spec dice qué NO hacer:
   - "Solo crear el archivo; no ejecutar la migración"
   - "Sin base de datos real aún"
   - "Hardcoded recipient until domain verified"

7. **Prompt inicial (waitly-prompt.md)** — Define el proyecto base ANTES de los specs incrementales. Es el "génesis" que establece la estructura, stack, y convenciones.

8. **CLAUDE.md como fuente de verdad** — Se actualiza con cada spec. Es el documento vivo que el agente lee para entender el estado actual del proyecto.

---

## Aspectos Técnicos del Formato

### Nivel de Detalle por Sección

| Aspecto | Nivel de detalle |
|---------|-----------------|
| **Objetivo** | 1-2 oraciones. Conciso. |
| **Schema/Modelo** | Código completo (SQL, TypeScript interfaces) |
| **Flujo** | Diagrama ASCII o lista numerada de pasos |
| **Archivos** | Path exacto + descripción de 1 línea de qué hacer |
| **Config** | Bloques literales de JSON/YAML para copiar |
| **Conceptos** | Bullets cortos, comparativos ("X vs Y: usa X cuando...") |
| **Código** | Snippets funcionales, no pseudocódigo |

### Lo que NO incluyen

❌ Tareas paso a paso tipo "checklist" (eso lo resuelve el agente)
❌ Tests (el agente los escribe siguiendo TDD)
❌ Explicaciones teóricas largas (solo bullets de "conceptos destacados")
❌ Alternativas descartadas (la decisión ya está tomada)
❌ Timeline o estimaciones de esfuerzo

---

## Cómo se relaciona con CLAUDE.md

waitly-prompt.md       → Define el proyecto inicial (génesis)
specs/01..07           → Cada uno añade una feature incremental
CLAUDE.md              → Se actualiza después de CADA spec implementado
                         Es la "memoria" del proyecto — el agente lo lee
                         para saber qué ya existe

El CLAUDE.md de waitly es ENORME (14KB) porque acumula:
Arquitectura actual completa
Todos los bindings y sus configuraciones
Patrones de código (auth, RPC, DO, WebSocket)
Constraints y gotchas descubiertas durante la implementación

---

## Skill para coder-platform: spec-writer

Para que el sub-agent developer pueda crear specs similares dentro de coder-platform, necesitas un skill que:

1. **Reciba inputs del Product/Tech Lead:**
   - Qué feature/servicio implementar
   - Qué concepto técnico introduce
   - En qué specs anteriores se basa

2. **Genere un spec con la estructura de Waitly:**
   - Objetivo (1-2 oraciones)
   - Modelo de datos / Schema
   - Flujo (diagrama o lista)
   - Archivos a crear/modificar (paths exactos)
   - Config necesaria (literal)
   - Conceptos destacados
   - Al finalizar (qué docs actualizar)

3. **Mantenga la cadena incremental:**
   - Lea CLAUDE.md para saber qué ya existe
   - No repita lo que ya está implementado
   - Extienda sin romper

---

## Skills Recomendados para coder-platform

| Skill | Rol que lo usa | Qué hace |
|-------|---------------|----------|
| spec-writer | Developer / Tech Lead | Genera specs incrementales estilo Waitly |
| spec-implementer | Developer | Lee un spec + CLAUDE.md → implementa con TDD |
| claude-md-updater | Developer | Actualiza CLAUDE.md después de implementar un spec |
| spec-reviewer | QA / Tech Lead | Valida que un spec es completo y consistente |

### Spec Writer — Estructura del Skill

markdown
# Skill: spec-writer

## Inputs
- feature_name: nombre corto de la feature
- concept: qué servicio/patrón introduce
- depends_on: lista de specs anteriores
- context: CLAUDE.md actual del proyecto

## Output
Un archivo specs/NN-<feature-name>.md con:
1. ## Objetivo — QUÉ y POR QUÉ en 1-2 oraciones
2. ## [Modelo/Schema/Flujo] — datos técnicos con código real
3. ## Archivos a crear / modificar — paths exactos
4. ## Conceptos destacados — bullets educativos
5. ## Al finalizar — qué actualizar en CLAUDE.md

## Rules
- Un solo concepto por spec
- Código real, no pseudocódigo
- Decisiones ya tomadas (no "considerar opciones")
- Paths exactos de archivos
- Suficiente info para implementar sin preguntar