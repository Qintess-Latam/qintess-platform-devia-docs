# Sección 1: Arquitectura General

## Diagrama de Componentes

┌─────────────────────────────────────────────────────────┐
│                    OPERADOR (Browser)                     │
│         code-server (VS Code) │ Terminal (Claude Code)   │
└──────────────────────┬──────────────────────────────────┘
                       │ HTTPS / WSS
┌──────────────────────▼──────────────────────────────────┐
│              CODER CONTROL PLANE (K8s Pod)               │
│  ┌──────────┐  ┌───────────┐  ┌─────────────────────┐  │
│  │ Auth     │  │ Template  │  │ Workspace Lifecycle  │  │
│  │ (GitHub  │  │ Engine    │  │ Manager              │  │
│  │  OAuth)  │  │ (Terraform)│ │                      │  │
│  └────┬─────┘  └─────┬─────┘  └──────────┬──────────┘  │
└───────┼───────────────┼───────────────────┼─────────────┘
        │               │                   │
        ▼               ▼                   ▼
┌─────────────────────────────────────────────────────────┐
│              WORKSPACE POD (por operador)                 │
│                                                          │
│  ┌─────────────────────────────────────────────────┐    │
│  │ Container Principal                              │    │
│  │  • code-server (VS Code Web)                     │    │
│  │  • Claude Code CLI                               │    │
│  │  • Git, Docker, herramientas base                │    │
│  │                                                  │    │
│  │  📁 /home/coder/.claude/                         │    │
│  │     ├── CLAUDE.md          (rol-specific)        │    │
│  │     ├── mcp-config.json    (rol-specific)        │    │
│  │     └── skills/            (rol-specific)        │    │
│  └─────────────────────────────────────────────────┘    │
│                                                          │
│  🔒 NetworkPolicy: egress solo a APIs del rol           │
│  🏷️ Labels: role=developer | role=qa                    │
└─────────────────────────────────────────────────────────┘

## Flujo de Provisión

1. Operador se autentica en Coder con GitHub OAuth
2. Coder consulta GitHub Teams del usuario → determina var.role
3. Terraform template provisiona el workspace pod con el overlay correcto
4. El pod arranca con CLAUDE.md, skills y MCP configs del rol montados
5. NetworkPolicy se aplica según el label role

## Componentes Clave

| Componente | Responsabilidad | Tecnología |
|------------|----------------|------------|
| Coder Control Plane | Auth, templates, lifecycle | Coder OSS v2.x |
| Template Engine | Provisión declarativa de workspaces | Terraform + Coder provider |
| Workspace Pod | Entorno aislado del operador | K8s Pod con labels |
| code-server | IDE web embebido | code-server (VS Code) |
| Claude Code CLI | Agente AI en terminal | Anthropic Claude Code |
| Overlay por Rol | Skills, MCP, CLAUDE.md específicos | ConfigMaps / mounted volumes |
| NetworkPolicy | Isolation de red por rol | K8s NetworkPolicy (Cilium/Calico) |

## Estado

✅ **Aprobado por el usuario**