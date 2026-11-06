# Sección 6: Imagen Base Docker

## Estado: ✅ Aprobada

## Dockerfile Multi-stage

dockerfile
FROM ubuntu:24.04 AS builder

RUN apt-get update && apt-get install -y curl wget git unzip jq && rm -rf /var/lib/apt/lists/*

ARG CODE_SERVER_VERSION=4.96.4
RUN curl -fsSL https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server-${CODE_SERVER_VERSION}-linux-amd64.tar.gz \
    | tar -xz -C /opt && mv /opt/code-server-* /opt/code-server

RUN npm install -g @anthropic-ai/claude-code

RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y gh

FROM ubuntu:24.04

RUN useradd -m -s /bin/bash -u 1000 coder
ENV HOME=/home/coder

RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl wget jq ca-certificates openssh-client \
    python3 python3-pip python3-venv \
    nodejs npm docker.io \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/code-server /opt/code-server
COPY --from=builder /usr/local/lib/node_modules/@anthropic-ai /usr/local/lib/node_modules/@anthropic-ai
COPY --from=builder /usr/bin/gh /usr/bin/gh

RUN ln -s /opt/code-server/bin/code-server /usr/local/bin/code-server \
    && ln -s /usr/local/lib/node_modules/@anthropic-ai/claude-code/bin/claude /usr/local/bin/claude

RUN mkdir -p /home/coder/workspace && chown -R coder:coder /home/coder

USER coder
WORKDIR /home/coder

HEALTHCHECK --interval=30s --timeout=5s CMD curl -f http://localhost:8080/healthz || exit 1
EXPOSE 8080

## Herramientas Incluidas

| Categoría | Herramientas |
|-----------|-------------|
| IDE | code-server (VS Code Web) |
| AI | Claude Code CLI |
| VCS | git, gh (GitHub CLI) |
| Runtime | Node.js, Python 3, pip, venv |
| Containers | Docker CLI |
| Utilities | curl, wget, jq, openssh-client |

## Tamaño: ~450 MB comprimido

## CI/CD: GitHub Actions → ghcr.io/qintess/coder-workspace:latest