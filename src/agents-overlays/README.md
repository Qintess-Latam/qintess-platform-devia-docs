# qintess-platform-agents-overlays

Persona (`CLAUDE.md`) y configuración de MCP (`mcp-config.json`) por equipo,
para los agentes de IA (Claude Code y GitHub Copilot CLI) usados en los
workspaces de Coder.

Los **skills** NO viven aquí — están en
[`qintess-platform-agents-skills`](https://github.com/Qintess-Latam/qintess-platform-agents-skills),
agrupados por equipo bajo `skills/<equipo>/`. Al aplicar un overlay, el
template busca los skills del equipo correspondiente en ese otro repo.

## Estructura

```
<equipo>/
  CLAUDE.md           # persona del equipo — fuente única para Claude Code y Copilot CLI
  mcp-config.json      # servidores MCP del equipo (github, atlassian, playwright...)
  settings.json        # modelo por defecto + permisos allow/ask/deny del agente
```

Equipos actuales: `developer`, `qa`, `architect`, `platform`, `cyber` (uno por plantilla de Coder `qintess-<rol>-template`).

## Consumo

Un solo `CLAUDE.md` por rol alimenta a los dos agentes:

| Agente | Destino en el workspace | Alcance |
|---|---|---|
| Claude Code | `~/.claude/CLAUDE.md` | global (todos los repos) |
| GitHub Copilot CLI | `~/.copilot/copilot-instructions.md` (rutas `~/.claude/` reescritas a `~/.copilot/`) | global (todos los repos) |

Escribe el `CLAUDE.md` neutral respecto del agente: no nombres "Claude" ni
"Copilot", y referencia los skills como `~/.claude/skills/` (el template lo
traduce para Copilot).

El template `templates/mvp-embedded/main.tf` en
[`qintess-platform-coder-template`](https://github.com/Qintess-Latam/qintess-platform-coder-template)
combina este repo (persona + MCP) con `qintess-platform-agents-skills`
(skills) al construir `~/.claude` y `~/.copilot` de cada workspace —
ver `docs/RUNBOOK-vm-qintess-latam.md` de ese repo para el mecanismo
exacto de sincronización.
