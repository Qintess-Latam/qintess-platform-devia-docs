# Contribuir con un skill

Reglas de gobernanza de Qintess para este repo, además de la
[spec oficial de Agent Skills](https://agentskills.io/specification)
(que sigue siendo la base — esto la complementa, no la reemplaza).

Validado automáticamente por `scripts/validate_skill.py` en CI
(`.github/workflows/validate-skills.yml`). **Los errores bloquean el
merge; los warnings no.**

## Estructura de carpetas

```
skills/<equipo>/<skill-name>/
├── SKILL.md         # obligatorio — spec oficial + metadata Qintess
├── README.md        # recomendado — doc para humanos (invocación, salida esperada)
├── references/      # opcional — material de apoyo
├── scripts/         # opcional — código ejecutable
└── assets/          # opcional — templates, recursos
```

`<equipo>` es uno de: `architect`, `developer`, `qa` (ver `catalog.yaml`
para el mapeo equipo → `domain`).

## Frontmatter — spec oficial (obligatorio, bloquea CI)

Ver [la spec completa](https://agentskills.io/specification). Resumen de
lo que valida `validate_skill.py`:

- `name`: 1-64 chars, `[a-z0-9]` + guiones, sin guion inicial/final ni
  dobles, **debe coincidir con el nombre de la carpeta del skill**.
- `description`: 1-1024 chars, no vacía.
- `compatibility` (si está presente): máx 500 chars.
- `metadata` (si está presente): mapa string→string (todos los valores
  citados como string, ej. `version: "1.0"`, no `version: 1.0`).

## Metadata Qintess — gobernanza (obligatorio para skills propios)

Un skill es **propio de Qintess** si su `metadata` NO tiene la clave
`author` (los skills de terceros/vendored, ej. traídos de un marketplace,
sí la tienen — ver sección siguiente). Para un skill propio, además de lo
anterior, `metadata` debe incluir:

| Clave | Valores válidos | Obligatorio |
|---|---|---|
| `type` | `skill` | Sí |
| `tier` | `T1`, `T2`, `T3` (criticidad/madurez — T1 = alto impacto) | Sí |
| `domain` | el `domain` del equipo en `catalog.yaml` (ej. `qa`, `engineering`, `architecture`) | Sí |
| `owner` | fijo: `qintess-platform` (ownership es del equipo, no individual) | Sí |

Falta cualquiera de estas claves, o un valor fuera de lo permitido →
**error** (bloquea CI).

`README.md` es **recomendado** para todo skill propio — si falta, es
**warning**, no bloquea (hay skills existentes sin él; se van completando).

## Skills vendored/terceros (ej. `metadata.author` presente)

Un skill con `metadata.author` (ej. traído de un marketplace de skills)
**no** necesita `type`/`tier`/`domain`/`owner` — se exime de la gobernanza
Qintess, pero igual debe cumplir la spec oficial (nombre, descripción,
estructura). No se le exige `README.md`.

## `catalog.yaml` — fuente de verdad del catálogo

Cada skill debe tener **exactamente una** entrada en `catalog.yaml`, bajo
su equipo, y viceversa (sin huérfanos en ningún lado). El `tier`/`owner`
del catálogo debe coincidir con el `metadata` real del `SKILL.md`. Al
agregar/quitar/renombrar un skill, **actualizá `catalog.yaml` en el mismo PR**
— si no, el validador falla con "huérfano" o "falta en disco".

`compatible` en el catálogo lista qué agentes lo usan (`claude`, `copilot`,
o ambos). Hoy todos los skills son compatibles con ambos salvo que el
`compatibility` del frontmatter diga explícitamente lo contrario.

## Calidad de contenido (recomendado, no bloquea CI)

El validador solo chequea estructura/metadata. La calidad del *contenido* la
rige la guía oficial — [Best practices for skill creators](https://agentskills.io/skill-creation/best-practices).
Tres reglas de ahí que aplicamos consistentemente en este repo:

- **Referencias con trigger, no con descripción.** En "📚 Reference material",
  decí *cuándo* cargar cada archivo (ej. "carga en el paso 4, al generar el
  reporte"), no solo qué es. Un archivo en `references/` que ningún paso de
  "Operating instructions" menciona es un **reference muerto** — nunca se
  carga. Revisalo con `grep <nombre-de-archivo> SKILL.md`.
- **Templates literales para output estructurado.** Si el skill produce un
  reporte Markdown, poné el esqueleto literal en ```` ```markdown ```` dentro
  de "📋 Output" — un agente sigue mejor una estructura concreta que una
  descripción en prosa de las secciones.
- **Gotchas, no solo guardrails.** "Hardening & guardrails" son reglas
  generales (válidas, mantenelas). Un **gotcha** es distinto: un hecho
  concreto y no obvio de *este* proyecto/stack que el agente va a asumir mal
  si no se lo decís (ej. un campo que se llama distinto en dos sistemas, un
  endpoint que miente sobre su propio healthcheck). Si corregís al agente en
  una sesión real por algo así, esa corrección va a un `## Gotchas` en el
  `SKILL.md` — no la fabriques de antemano, extraela de una ejecución real
  (ver "Refine with real execution" en la guía).

## Validar localmente antes de abrir el PR

```bash
pip install pyyaml
python scripts/validate_skill.py                      # todo el repo
python scripts/validate_skill.py skills/qa/mi-skill    # un skill puntual
```
