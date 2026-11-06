# Sección 3: Template Terraform (Base + Overlay)

## Estado: ✅ Aprobada

## Estructura de Archivos

coder-templates/
├── main.tf                    # Template principal
├── variables.tf               # Variables (role, compute size)
├── scripts/
│   └── resolve-role.sh        # Resolución automática de rol
├── base/
│   ├── Dockerfile             # Imagen base (code-server + claude-code + tools)
│   └── startup.sh             # Script de inicialización
└── overlays/
    ├── developer/
    │   ├── CLAUDE.md          # System prompt + skills habilitados
    │   ├── mcp-config.json    # MCP servers permitidos
    │   ├── skills/            # Skills del rol
    │   │   ├── code-review-security/
    │   │   ├── feature-implementation/
    │   │   └── jira-dev-sync/
    │   └── network-policy.yaml
    └── qa/
        ├── CLAUDE.md
        ├── mcp-config.json
        ├── skills/
        │   ├── bdd-test-generation/
        │   ├── coverage-gap-analysis/
        │   └── unit-test-generation/
        └── network-policy.yaml

## Template Principal (main.tf)

hcl
terraform {
  required_providers {
    coder = { source = "coder/coder" }
    kubernetes = { source = "hashicorp/kubernetes" }
  }
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

data "external" "user_role" {
  program = ["bash", "${path.module}/scripts/resolve-role.sh"]
  query = {
    github_username = data.coder_workspace_owner.me.name
    github_org      = "qintess"
  }
}

locals {
  role = data.external.user_role.result.role
}

resource "kubernetes_pod" "workspace" {
  metadata {
    name      = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}"
    namespace = "coder-workspaces"
    labels = {
      "app.kubernetes.io/name" = "coder-workspace"
      "coder.com/role"         = local.role
      "coder.com/owner"        = data.coder_workspace_owner.me.name
    }
  }

  spec {
    container {
      name  = "workspace"
      image = "ghcr.io/qintess/coder-workspace:latest"

      volume_mount {
        name       = "role-overlay"
        mount_path = "/home/coder/.claude"
        read_only  = true
      }

      resources {
        requests = { cpu = "2", memory = "4Gi" }
        limits   = { cpu = "4", memory = "8Gi" }
      }
    }

    volume {
      name = "role-overlay"
      config_map {
        name = "overlay-${local.role}"
      }
    }
  }
}

resource "kubernetes_network_policy" "workspace_egress" {
  metadata {
    name      = "egress-${local.role}-${data.coder_workspace_owner.me.name}"
    namespace = "coder-workspaces"
  }

  spec {
    pod_selector {
      match_labels = {
        "coder.com/owner" = data.coder_workspace_owner.me.name
        "coder.com/role"  = local.role
      }
    }
    policy_types = ["Egress"]

    egress {
      ports { port = 53; protocol = "UDP" }
      ports { port = 53; protocol = "TCP" }
    }
    egress {
      ports { port = 443; protocol = "TCP" }
    }
  }
}

resource "coder_agent" "main" {
  os   = "linux"
  arch = "amd64"
  dir  = "/home/coder"
  startup_script = file("${path.module}/base/startup.sh")

  metadata {
    key          = "role"
    display_name = "Rol"
    script       = "echo ${local.role}"
  }
}

resource "coder_app" "code_server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "VS Code"
  url          = "http://localhost:8080?folder=/home/coder/workspace"
  icon         = "/icon/code.svg"
  subdomain    = true
}

## Startup Script (base/startup.sh)

bash
#!/bin/bash
set -e

cp -r /home/coder/.claude /home/coder/.claude-config
ln -sf /home/coder/.claude-config/CLAUDE.md /home/coder/workspace/CLAUDE.md

code-server --bind-addr 0.0.0.0:8080 --auth none &

echo "🎯 Workspace iniciado con rol: $(cat /home/coder/.claude-config/CLAUDE.md | head -1)"
echo "📋 Skills disponibles:"
ls /home/coder/.claude-config/skills/ 2>/dev/null || echo "  (ninguno)"
