# MVP incremental — de "Hola workspace" al TO-BE

Este documento define **cómo llegar al diseño de `docs/TO-BE/` por niveles**, empezando
por lo más básico posible y añadiendo una capa a la vez. Cada nivel es funcional y
reutilizable: nada se tira al pasar al siguiente.

> Principio: **el modelo `coder_agent` + `coder_app`/módulos es idéntico en Docker y en
> Kubernetes.** Solo cambia el recurso de compute. Por eso un MVP en Docker es la rampa
> real al TO-BE, no un prototipo desechable.

Referencias base: [`README.md`](../README.md) (estado deseado) y
[`docs/TO-BE/`](./TO-BE/) (diseño completo aprobado).

**Docs operativos (para colaboradores):**
- [`docs/RUNBOOK-vm-qintess-latam.md`](./RUNBOOK-vm-qintess-latam.md) — **runbook activo**:
  despliegue completo en la VM, centralizado en GitHub `Qintess-Latam` (RBAC, HTTPS, Copilot).
- [`docs/RUNBOOK-plantillas-por-rol.md`](./RUNBOOK-plantillas-por-rol.md) — las 5
  plantillas `qintess-<rol>-template` (binarios, overlays, panel, gasto de IA).
- [`docs/RUNBOOK-vm-portainer-red.md`](./RUNBOOK-vm-portainer-red.md) — Portainer,
  PostgreSQL en Docker, cambios de IP, acceso público, Backstage y upgrade de Coder.
- [`docs/rbac-setup.md`](./rbac-setup.md) — GitHub OAuth + resolución de rol por Team (Nivel 3).

> **Nota (2026-10-19):** las 5 plantillas por rol usan **imágenes Docker pre-armadas**
> (`images/workspace/`, escaneadas con Trivy: 0 HIGH/CRITICAL estrictos, excepciones con
> vencimiento) y crean un workspace en ~10-20 s (antes ~54 min). Autostop por inactividad
> activo (2 h + 1 h de actividad). Detalle en `RUNBOOK-plantillas-por-rol.md`.

> **Nota (2026-10-05):** el **objetivo inmediato original** de este doc ("llegar al
> Nivel 1") **ya se superó**. Hoy el repo está en producción piloto sobre
> `Qintess-Latam`, con capas que no existían cuando se escribió la escalera (ver
> sección *"Más allá de la escalera original"*). Niveles 0–3 se dan por cerrados;
> lo que falta de verdad para TO-BE son los Niveles 4–6 (Kubernetes, network
> isolation/secretos, operación Day-2).

> **Nota (2026-10-07) — decisión de scope del MVP:** se decide quedar en **Docker,
> en esta VM**, por ahora — los Niveles 4–6 (Kubernetes) quedan **diferidos
> deliberadamente**, no son un gap activo del MVP (ver sección reestructurada
> abajo). El MVP real pendiente son 2 ítems operativos: **gobernanza de la
> organización de GitHub** (bloquea Actions y Copilot Business) y **exponer
> Coder a internet con Cloudflare Tunnel + dominio propio**.

---

## La escalera

| Nivel | Objetivo | Provisioner | Entregable |
|------:|----------|-------------|------------|
| **0** | Coder corriendo + 1 workspace Docker de arranque | Docker | Coder server + template base |
| **1** | **VS Code + Claude Code embebidos** | Docker | `templates/mvp-embedded/` |
| **2** | Overlay de rol (CLAUDE.md + skills + MCP) | Docker | repos `qintess-platform-agents-overlays` + `-skills` |
| **3** | RBAC: GitHub OAuth + rol por Team | Docker | `resolve-role.sh` + GitHub App |
| **4** | Salto a Kubernetes | **K8s** | template K8s + imagen propia |
| **5** | Network isolation + secretos | K8s | Cilium + ESO + Jira OAuth |
| **6** | Operación Day-2 | K8s | auto-create + observabilidad + CI/CD |

---

## Estado (actualizado 2026-10-15)

| Nivel | Estado | Notas |
|------:|--------|-------|
| **0** | ✅ cerrado | Coder **v2.37.4** como servicio (systemd `--user` + linger) en la VM de `Qintess-Latam`, con PostgreSQL en Docker (stack `coder-db` en Portainer, backups diarios) y acceso público `https://201.203.104.168:3000` vía Caddy. |
| **1** | ✅ **superado** | `templates/mvp-embedded/` (sin módulos del registry: todo en el `startup_script`) reemplazó al scaffold original bloqueado por Terraform <1.9. Workspace con **3 apps**: VS Code (con la extensión de Claude), Claude Code (CLI) y **GitHub Copilot (CLI)**. Backend LLM swappable (subscription/vertex/bedrock/api_key) ya resuelto en el template — lo que falta es la *decisión de producción*, no el mecanismo (ver sección de decisiones abajo). |
| **2** | ✅ **superado** | Overlay por rol (CLAUDE.md + skills + MCP) funcionando para **ambos** asistentes (Claude y Copilot cargan los mismos overlays — verificado en vivo). Delivery cambió de bind-mount fijo a **repos centralizados** `qintess-platform-agents-overlays` + `qintess-platform-agents-skills`, combinados en el host por `deploy/vm/sync-agent-overlays.sh`. MCP: github ✔, atlassian ✔ (pendiente confirmar en vivo credenciales reales post-HTTPS), playwright ✔ (rol qa). Sonar sigue sin cuenta. |
| **3** | ✅ **superado** | **Una plantilla por rol** desde 2026-10-15 (`qintess-architecture/developer/platform/qa/cyber-template`, ver [`RUNBOOK-plantillas-por-rol.md`](./RUNBOOK-plantillas-por-rol.md)): cada una exige el team de su rol e instala sus binarios. RBAC migrado de la org de pruebas (`juanparra-coder`) a **`Qintess-Latam`**. Resolución por **5 disciplinas** (`qintess-developers`, `qintess-qa`, `qintess-architect`, `qintess-platform`, `qintess-cyber`), cada una con sub-teams (`senior-dev`, `repo-admin`, `release-eng`, `appsec` en platform) que también otorgan el rol del padre. GitHub App `qintess-latam-rbac-resolver` (no PAT personal). Least-privilege + one-role-per-user intactos. |
| **4–6** | ⏸️ **diferido por decisión** | Kubernetes queda fuera del scope de este MVP — se sigue en Docker en esta VM. No es "0% por descuido", es "0% a propósito". Ver "Qué falta de verdad" abajo para lo que SÍ es gap activo. |

---

## Más allá de la escalera original (no estaba planeado, se hizo igual)

Estas capas no existían cuando se escribió la escalera 0–6, y hoy son parte del MVP real:

- **Migración de org a `Qintess-Latam`**: repo movido de personal a
  `Qintess-Latam/qintess-platform-coder-template` (privado), gobernado por el team
  `qintess-platform`. Apps de GitHub (OAuth login + GitHub App resolver) recreadas
  en la org real.
- **HTTPS delante de Coder** (Caddy + CA self-signed) — ver
  [`RUNBOOK-https-caddy.md`](./RUNBOOK-https-caddy.md). Quita el "insecure context"
  del navegador y habilita que Atlassian acepte el callback OAuth (exige https).
- **Solo acceso web**: `display_apps` oculta los botones que dependen de SSH/túnel
  (VS Code Desktop, SSH helper, port-forwarding) — queda únicamente lo servido por HTTP.
- **GitHub Copilot CLI como tercer asistente**: convive con Claude Code en el mismo
  workspace, autenticado con la identidad GitHub del usuario, cargando **las mismas**
  capacidades por rol (MCP + skills + persona) que Claude.
- **3 variantes de plataforma en ramas separadas**: `main` (GitHub+Claude+Copilot),
  `gitlab-claude` (GitLab OIDC + grupos + Claude), `github-copilot` (GitHub + solo
  Copilot). ⚠️ Las dos últimas están **14 commits detrás de `main`** — no tienen nada
  de lo de esta sección (ver "Qué falta de verdad").
- **Backstage/Symphony** (repo aparte `qintess-platform-backstage-mngr`, en
  `https://201.203.104.168:7007`): portal interno con branding Qintess, template
  de scaffolder para crear repos (mozart, GitHub App `qintess-mozart-bot`) con RBAC
  por disciplina. Ecosistema relacionado, no parte de este repo.
- **Plantillas por rol + panel del workspace** (2026-10-15): binarios por rol,
  overlays para los 5 roles, estado de Claude/extensión/GitHub/Atlassian y
  *Estimated AI spend/month* (Claude estimado + Copilot seat/premium requests).
- **Operación de la VM**: Portainer orquesta Caddy, `coder-db` y Backstage; CA de
  Caddy en el trust store del host; timers de backups y de gasto de Copilot.

---

## Qué falta de verdad (el roadmap real hoy)

No es "llegar a Nivel 1" — eso quedó atrás. Con la decisión de quedarse en Docker
en esta VM (nota 2026-10-07 arriba), esto se divide en **MVP activo** (lo que sí
bloquea hoy) y **diferido** (Kubernetes, fuera de scope por decisión, no por gap).

### MVP activo — en orden de impacto

1. ~~**Gobernanza de la organización de GitHub**~~ ✅ **resuelto (2026-10-15)** —
   con el método de pago/Copilot Business activo, GitHub Actions ya ejecuta
   runners en `Qintess-Latam` (antes: `startup_failure` a 0 s en toda la org).
2. **Nombre DNS + certificado real** — hoy el acceso público es por **IP**
   (`https://201.203.104.168:3000` Coder, `:7007` Backstage, `:9443` Portainer)
   con `tls internal` de Caddy, y depende de que el ISP no cambie la IP. Falta un
   dominio (subdominio → IP pública o Cloudflare Tunnel; `cloudflared` ya está
   instalado) para tener cert de Let's Encrypt y una URL estable.
3. **Decisión de external-auth** — Coder OSS solo permite **1** proveedor de
   external-auth; tenemos 2 (github + atlassian) y Coder muestra un banner de
   *"Enterprise feature"* (sigue funcionando, pero sin resolver formalmente:
   ¿vivir con el banner, reducir a 1, o licencia Premium?).
4. **Backend LLM de producción** — el mecanismo ya existe (swappable), pero la
   elección real (Vertex/Bedrock con IAM del banco vs. token compartido) sigue sin
   decidirse. Mismo ítem que ya marcaba el doc original como bloqueante antes del
   Nivel 5.
5. ~~**Copilot Business**~~ ✅ **activo (2026-10-15)** — 5 seats asignados por
   team de rol, *Copilot in the CLI* y *MCP servers* habilitados, modelos
   restringidos a Claude Sonnet/Opus/Haiku. Los 5 teams de rol tienen seat
   (platform y cyber desde 2026-10-15). Ver `RUNBOOK-vm-qintess-latam.md` Fase 2d.
6. **Ramas `gitlab-claude` y `github-copilot` desactualizadas** — 14 commits detrás
   de `main`, sin la migración a Qintess-Latam, HTTPS, ni overlays centralizados.
7. **`prod-oidc` sin mantenimiento** — referencia para producción con IdP
   corporativo; no tiene Caddy/HTTPS, `display_apps`, Copilot ni plantillas por
   rol. Si se despliega hoy, va sin esas mejoras.
8. **Migrar a las plantillas por rol** — los workspaces existentes siguen en
   `mvp-embedded` (obsoleta); cada usuario crea el suyo con la plantilla de su
   rol y borra el viejo (ver `RUNBOOK-plantillas-por-rol.md` → Migración).

### Diferido — fuera del scope de este MVP (decisión 2026-10-07, no gap)

9. **Nivel 4 — Kubernetes**: cambiar `docker_container`/`docker_volume` por
   `kubernetes_pod` + PVC; imagen base propia (`docker/workspace/Dockerfile`,
   `docs/TO-BE/06-imagen-base-docker.md`). Overlays vía ConfigMap.
10. **Nivel 5 — Network isolation + secretos**: CiliumNetworkPolicy FQDN por rol
   (egress default-deny), External Secrets Operator per-user.
   (Jira OAuth 3LO de este nivel ya se adelantó, fuera de orden, en el Nivel 2/3.)
11. **Nivel 6 — Operación Day-2**: CronJob de auto-create al primer login,
    observabilidad (Prometheus/Grafana/Loki), CI/CD de la plantilla (no hay
    pipeline: se sube con `deploy/vm/push-role-templates.sh`), auto-stop.
    (Backups de la BD de Coder ya existen en la VM: timer diario.)

---

## Historia — Notas de entorno del Nivel 0 original (homelab, superseded)

> Contexto histórico: así se validó el Nivel 0 la primera vez, en una máquina
> local (no la VM de `Qintess-Latam` actual). Se conserva por el detalle técnico
> (bloqueo de Terraform), útil si alguien repite el ejercicio en otra máquina.

Ejecución local del Nivel 0 (máquina Linux x86_64, Docker operativo):

- Coder instalado **sin sudo** en `~/.local/bin` (modo standalone), versión **v2.35.1**.
- Server: `coder server` con PostgreSQL **embebido** (`~/.config/coderv2/postgres`).
- **Bind a `0.0.0.0:3000` (no `127.0.0.1`)**: el agente corre *dentro* del contenedor y
  alcanza el host por `host.docker.internal`; un listener en loopback **no** es alcanzable
  y el workspace queda `HEALTHY=false`. Con `CODER_HTTP_ADDRESS=0.0.0.0:3000` conecta al
  instante. `CODER_ACCESS_URL=http://localhost:3000` (se reescribe a `host.docker.internal`
  para el agente).
- Admin creado no-interactivo (`--first-user-*`). Credenciales locales entregadas aparte.
- Template `starter-docker` (imagen `codercom/enterprise-base:ubuntu`) + workspace
  `smoke-test` en `HEALTHY=true`, exec verificado.

### ⚠️ Bloqueo original para el Nivel 1 — versión de Terraform

El provisioner de Coder usa el `terraform` del **PATH**, que en esa máquina era **1.5.7**
(linuxbrew). Los módulos oficiales del registry (`code-server`, `jetbrains`,
**`claude-code`**) exigen **Terraform >= 1.9**, así que el `push` fallaba con
*"Unsupported Terraform Core version"*.

Por eso se subió el starter **sin** esos módulos (solo agente + Terminal), y luego
**`templates/mvp-embedded/`** (sin módulos del registry, instala todo en el
`startup_script`) reemplazó permanentemente a ese scaffold (ya eliminado del
repo) — es el código del que salen hoy las plantillas por rol.

---

## Decisiones que hay que cerrar (siguen abiertas)

1. **Egress al modelo:** `api.anthropic.com` en el allowlist FQDN vs. Bedrock/Vertex por
   endpoint privado. (Nivel 5.)
2. **Auth de Claude en prod:** API key per-user (ESO) vs. clave compartida por rol.
   Mismo tema que el ítem 4 de "Qué falta de verdad" arriba.
3. **External-auth con licencia:** ver ítem 3 de "Qué falta de verdad".
