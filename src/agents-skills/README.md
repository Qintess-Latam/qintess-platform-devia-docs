# qintess-platform-agents-skills

Overlays por rol (persona + MCP config + skills) para los agentes de IA
(Claude Code y GitHub Copilot CLI) usados en los workspaces de Coder.

Migrado desde `overlays/` del repo
[`qintess-platform-coder-template`](https://github.com/Qintess-Latam/qintess-platform-coder-template),
para centralizar el contenido de agentes/skills fuera del repo de
infraestructura — mantenido por el team `qintess-platform`.

## Estructura

```
<equipo>/
  CLAUDE.md             # persona del equipo (también usado como copilot-instructions.md)
  mcp-config.json       # servidores MCP del equipo (github, atlassian, playwright...)

skills/
  <equipo>/
    <skill-name>/
      SKILL.md          # definición del skill (formato Claude Code / Copilot CLI)
      references/
      ...
```

Los skills viven todos bajo `/skills`, agrupados por equipo — separados de
la persona/MCP config de cada `<equipo>/`.

Equipos actuales: `developer`, `qa`, `architect`.

## Consumo

El template `templates/mvp-embedded/main.tf` en `qintess-platform-coder-template`
copia `<rol>/` al `~/.claude` y `~/.copilot` de cada workspace en el
`startup_script`, para que Claude Code y Copilot CLI tengan las mismas
capacidades (ver `docs/RUNBOOK-vm-qintess-latam.md` de ese repo).

