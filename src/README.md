# Dev-IA — Índice de documentación del proyecto

Plataforma de workspaces de desarrollo (Coder + Claude Code + GitHub Copilot CLI) por rol,
con RBAC real contra GitHub, y portal interno Symphony (Backstage) para crear repos
gobernados (mozart). Para el banco, vía Qintess.

**Repos fuente (GitHub, org `Qintess-Latam`, todos privados):**
- [`qintess-platform-coder-template`](https://github.com/Qintess-Latam/qintess-platform-coder-template) — el template de Terraform/Coder, runbooks, arquitectura.
- [`qintess-platform-agents-overlays`](https://github.com/Qintess-Latam/qintess-platform-agents-overlays) — persona + MCP config + permisos por rol (5 roles).
- [`qintess-platform-agents-skills`](https://github.com/Qintess-Latam/qintess-platform-agents-skills) — skills de Claude Code/Copilot por rol.
- [`qintess-platform-backstage-mngr`](https://github.com/Qintess-Latam/qintess-platform-backstage-mngr) — Symphony (Backstage) + mozart (crear repos gobernados).

**Esta carpeta es una copia de trabajo** de la documentación que ya vive en esos 4 repos
(fuente de verdad real = git, esto es para quien no tenga acceso a GitHub). Si algo cambia,
el repo manda — esta copia puede quedar desactualizada.

## Empezar por acá

1. **`ACCESOS-Y-CREDENCIALES.md`** (en esta carpeta) — qué credenciales existen, para qué,
   dónde viven de verdad, y quién las tiene. **Léelo primero** si vas a tomar continuidad del
   proyecto.
2. **`coder-template/MVP.md`** — estado real del proyecto, qué está hecho y qué falta.
3. **`coder-template/MANUAL-TECNICO.md`** — el documento técnico completo (24 secciones):
   arquitectura, RBAC, MCP, secretos, troubleshooting real.
4. **`coder-template/DEMO-guion.md`** — la demo que ya se hizo (caso de negocio, roles,
   prompts exactos), útil para entender el flujo end-to-end sin leer código.

## Estructura de esta carpeta

```
Dev-IA/
├── 00-INDICE.md                    ← este archivo
├── ACCESOS-Y-CREDENCIALES.md       ← el doc nuevo, consolidado (ver arriba)
├── coder-template/                 ← docs de qintess-platform-coder-template
│   ├── MANUAL-TECNICO.md           ← EL documento técnico maestro
│   ├── MVP.md                      ← estado real / qué falta
│   ├── DEMO-guion.md
│   ├── RUNBOOK-*.md                ← 8 runbooks operativos (deploy, HTTPS, Copilot, etc.)
│   └── TO-BE/                      ← arquitectura a futuro (Kubernetes, diferido por decisión)
├── agents-overlays/                ← persona + MCP + permisos de cada uno de los 5 roles
│   └── <architect|cyber|developer|platform|qa>/{CLAUDE.md, mcp-config.json, settings.json}
├── agents-skills/                  ← catálogo de skills (ver catalog.yaml) + gobernanza
└── backstage-mngr/                 ← README de Symphony/mozart (ver el repo para el código)
```

## Qué NO está en esta carpeta (a propósito)

- **Los valores reales de ningún secreto** — están marcados como `[PENDIENTE — ver
  ACCESOS-Y-CREDENCIALES.md]` donde corresponde. Los valores reales los agrega quien tenga
  acceso, directo en el archivo final, no por chat ni por este índice.
- El código fuente de mozart/Backstage/los templates — está en los repos, no se duplica acá
  (se desactualizaría de inmediato).
