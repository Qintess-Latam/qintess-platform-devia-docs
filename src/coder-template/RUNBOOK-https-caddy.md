# RUNBOOK — HTTPS delante de Coder con Caddy (cert self-signed)

> **Vigencia (2026-10-15):** el mecanismo (Caddy + `tls internal` + CA confiada en
> los workspaces) sigue igual, pero **las IPs y el Caddyfile de abajo son
> históricos**. Hoy Caddy corre como stack de Portainer, sirve `:3000` (Coder),
> `:7007` (Backstage) y `:9443` (Portainer) con el cert de la IP pública
> `201.203.104.168`, y la plantilla del Caddyfile es
> `~/.config/caddy-coder/Caddyfile.tmpl` → ver
> [`RUNBOOK-vm-portainer-red.md`](RUNBOOK-vm-portainer-red.md) (FASES 1, 3 y 4).

> Paso a paso REAL (incluye los intentos que fallaron y por qué) para pasar
> Coder de `http://192.168.50.208:3000` a `https://192.168.50.208:3000`,
> sin dominio público ni Let's Encrypt — usando Caddy en Docker con su CA
> local, y haciendo que los workspaces confíen en ella.
>
> Disparador: code-server avisaba *"being accessed in an insecure context —
> clipboard/webviews may not work"*. Causa: los navegadores solo tratan como
> "contexto seguro" HTTPS o HTTP a `localhost`; una IP de LAN por HTTP no
> cuenta.

---

## Resultado final (qué queda corriendo)

```
Browser / agente del workspace
        │  HTTPS :3000 (cert self-signed, CA "Caddy Local Authority")
        ▼
  Caddy (docker, --network host)
        │  HTTP :3001 (interno, 127.0.0.1)
        ▼
  Coder (systemd --user, CODER_HTTP_ADDRESS=127.0.0.1:3001)
```

Los workspaces confían en la CA de Caddy vía un bind-mount + `update-ca-certificates`
corrido **en el entrypoint del container**, antes de que el agente intente
hablar con Coder.

> **Actualización 2026-10-09:** Caddy ahora corre como stack `caddy` de
> **Portainer** y el Caddyfile se **genera** desde `Caddyfile.tmpl` con las IPs
> actuales de la VM (timer `caddy-lan-ip.timer`). Ver
> [`RUNBOOK-vm-portainer-red.md`](RUNBOOK-vm-portainer-red.md). El `docker run`
> y el Caddyfile de abajo quedan como referencia histórica.

---

## FASE 1 — Mover Coder al puerto interno

Caddy necesita el puerto 3000 para sí mismo; Coder pasa a escuchar solo en
loopback, en otro puerto.

Editar `~/.config/coderv2/server.env`:
```bash
export CODER_ACCESS_URL="https://192.168.50.208:3000"   # antes: http://...:3000
export CODER_HTTP_ADDRESS="127.0.0.1:3001"               # antes: 0.0.0.0:3000
```
```bash
cp -f ~/.config/coderv2/server.env ~/.config/coderv2/server.env.bak.$(date +%s)
systemctl --user restart coder
sleep 6 && curl -fsS http://127.0.0.1:3001/healthz && echo "  ← Coder OK (interno)"
```

> ⚠️ Entre este paso y el FASE 2, el dashboard queda **inalcanzable** (Coder ya
> no escucha en :3000, Caddy todavía no). Es un corte corto y esperado — seguir
> a la Fase 2 sin pausas.

---

## FASE 2 — Caddy en Docker

No se instaló por `apt` (requiere sudo interactivo, no disponible en algunos
contextos) — se usó la imagen oficial de Docker.

`~/.config/caddy-coder/Caddyfile`:
```caddyfile
192.168.50.208:3000, localhost:3000, 127.0.0.1:3000 {
	tls internal
	reverse_proxy 127.0.0.1:3001
}
```
```bash
mkdir -p ~/.config/caddy-coder
docker run -d --name caddy-coder --network host --restart unless-stopped \
  -v caddy_coder_data:/data \
  -v caddy_coder_config:/config \
  -v ~/.config/caddy-coder/Caddyfile:/etc/caddy/Caddyfile:ro \
  caddy:2 caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
```

**GOTCHA 1 — `tlsv1 alert internal error` al conectar:**
Con el sitio declarado solo como `:3000` (sin hosts explícitos), Caddy no
sabe para qué nombres emitir el certificado interno → el handshake TLS
falla con "internal error". **Fix:** declarar los hosts explícitos en el
Caddyfile (`192.168.50.208:3000, localhost:3000, 127.0.0.1:3000`), como
arriba. Con eso, el log muestra `certificate obtained successfully` para
cada identifier y el handshake funciona.

**GOTCHA 1b — el mismo error, pero sin SNI (visitantes por IP / port forwarding):**
un navegador o `curl` que se conecta a una **IP** no manda SNI; Caddy elige
entonces el certificado por **la IP local por la que entró la conexión**. Si la
VM cambia de IP (es una notebook que cambia de red) y la IP nueva no está en el
Caddyfile → `internal error`, aunque la IP pública sí esté listada. Ojo: la
prueba `curl --resolve <ip-pública>:3000:127.0.0.1` **da 200 igual** (no manda
SNI y entra por `127.0.0.1`), no sirve para validar. Fix permanente (Caddyfile
generado con las IPs actuales) y pruebas correctas en
[`RUNBOOK-vm-portainer-red.md`](RUNBOOK-vm-portainer-red.md) → FASE 3.

**GOTCHA 2 — `tls internal { on_demand }` también daba el mismo error:**
`on_demand` es para emitir certs sobre la marcha según el SNI que llega;
redundante (y conflictivo) si ya se declaran los hosts de forma estática.
Se sacó del bloque `tls internal`.

Verificación:
```bash
curl -sk https://192.168.50.208:3000/healthz   # → OK
```

---

## FASE 3 — Confiar la CA en los workspaces (la parte no obvia)

### Intento 1 (fallido): confiar la CA en `startup_script`

Primer intento: escribir el cert e instalar `update-ca-certificates` dentro
del `startup_script` del `coder_agent`. **No funciona**, porque el propio
*bootstrap* del agente (el `init_script` que corre el `entrypoint` del
container) hace `curl` a `https://<CODER_ACCESS_URL>/bin/coder-linux-amd64`
para bajar el binario del agente — y eso pasa **antes** de que exista
siquiera el agente que ejecutaría `startup_script`. Error visto en
`docker logs <container>`:
```
curl: (60) SSL certificate OpenSSL verify result: unable to get local issuer certificate (20)
error: failed to download coder agent
```
Lección: para un proxy TLS self-signed delante de Coder, la CA tiene que
estar confiable **antes** de que el container arranque — no alcanza con el
`startup_script`.

### Intento 2 (correcto): CA vía bind-mount + `entrypoint`

1. **Sacar la CA root de Caddy** (vive en el volumen Docker `caddy_coder_data`):
   ```bash
   mkdir -p ~/.config/coderv2/caddy-ca
   docker cp caddy-coder:/data/caddy/pki/authorities/local/root.crt \
     ~/.config/coderv2/caddy-ca/root.crt
   ```
   (Solo el **root** — Caddy rota el intermedio cada ~7 días, pero el
   intermedio lo manda el propio servidor durante el handshake; el cliente
   solo necesita confiar en el root, que dura ~10 años.)

2. **Nueva variable en `templates/mvp-embedded/main.tf`**:
   ```hcl
   variable "caddy_ca_cert_host_path" {
     type        = string
     default     = ""
     description = "Ruta en el HOST al cert .crt de la CA local de Caddy..."
   }
   ```

3. **Bind-mount condicional** en `docker_container.workspace` (mismo patrón
   que `overlays_host_path`):
   ```hcl
   dynamic "volumes" {
     for_each = var.caddy_ca_cert_host_path != "" ? [1] : []
     content {
       host_path      = var.caddy_ca_cert_host_path
       container_path = "/usr/local/share/ca-certificates/caddy-coder-local-ca.crt"
       read_only      = true
     }
   }
   ```

4. **`entrypoint` corre `update-ca-certificates` ANTES del `init_script`**:
   ```hcl
   entrypoint = ["sh", "-c", "sudo update-ca-certificates >/dev/null 2>&1 || true\n${replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")}"]
   ```

**GOTCHA 3 — faltaba el `sudo`:** primera versión sin `sudo`; el `entrypoint`
corre como usuario `coder` (no root), y `update-ca-certificates` necesita
escribir `/etc/ssl/certs/ca-certificates.crt` → fallaba con *"Permission
denied"*, pero el `|| true` lo escondía por completo (parecía que corría
bien). Se detectó comparando `docker exec ... update-ca-certificates`
(falla sin sudo) vs `docker exec ... sudo update-ca-certificates` (1 added,
0 removed, éxito) — y confirmando después con un `curl` directo al
`CODER_ACCESS_URL` desde dentro del container.

5. **Push + verificación**:
   ```bash
   cd templates/mvp-embedded
   TMP=$(mktemp -d); cp main.tf "$TMP"/; cp -r scripts "$TMP"/
   coder templates push mvp-embedded --directory "$TMP" \
     --var overlays_host_path=/home/dev-ia/coder-platform/overlays \
     --var github_org=Qintess-Latam \
     --var caddy_ca_cert_host_path=/home/dev-ia/.config/coderv2/caddy-ca/root.crt \
     --yes
   rm -rf "$TMP"
   ```

**GOTCHA 4 — `coder restart` NO toma la plantilla nueva:** reconstruye con
la versión que el workspace ya tenía asignada (queda `Outdated=true`
después de cada push). Hace falta `coder update <owner>/<ws>` para que
adopte la versión activa más reciente.

```bash
coder update JuanPDQintess/coffee-flyingfish-59
```

**Ojo, el caso inverso:** si el workspace **ya está** en la versión activa,
`coder update` no crea build (no hace nada). Para que tome un cambio del
server (p. ej. un `CODER_ACCESS_URL` nuevo) hace falta `coder restart --yes`.
Ver [`RUNBOOK-vm-portainer-red.md`](RUNBOOK-vm-portainer-red.md) → FASE 4.

Verificación final (todo en verde):
```bash
coder list
# STATUS=Started  HEALTHY=true  OUTDATED=false

docker exec coder-<owner>-<ws> curl -s -o /dev/null -w "%{http_code}\n" \
  https://192.168.50.208:3000/healthz   # → 200
```

---

## FASE 4 — Confiar la CA en el navegador de cada usuario (lado cliente)

Aceptar el warning de "conexión no segura" en la página alcanza para
navegar, pero **no siempre para Service Workers** — VS Code Web (code-server)
registra uno para los webviews, y Chrome lo rechaza con:
```
Error loading webview: Error: Could not register service worker:
SecurityError: ... An SSL certificate error occurred when fetching the script.
```
aunque el usuario ya haya "aceptado" el certificado para la página. Fix real:
instalar `~/.config/coderv2/caddy-ca/root.crt` como CA de confianza en el
**sistema u navegador** de cada máquina cliente (no en el workspace — eso ya
lo cubre la Fase 3; esto es del lado de quien USA el navegador):

- **Windows**: doble clic en `root.crt` → Instalar certificado → Equipo local
  → "Colocar todos los certificados en..." → **Entidades de certificación
  raíz de confianza**.
- **macOS**: doble clic → Keychain Access → ubicar "Caddy Local Authority" →
  Confiar → "Usar este certificado siempre que se use SSL" → Confiar siempre.
- **Linux (Chrome/Edge)**: `chrome://settings/certificates` → Autoridades →
  Importar → marcar "Confiar para identificar sitios web".
- **Firefox**: `about:preferences#privacy` → Ver certificados → Autoridades →
  Importar → marcar "Confiar para identificar sitios web".

Reiniciar el navegador después de importar. Repetir por cada máquina/perfil
de navegador que use el dashboard (no hay forma de evitarlo sin una CA
pública real).

---

## Pendientes para quien toque esto después

- **GitHub OAuth App ("Coder VM")**: la *Authorization callback URL* se
  actualizó manualmente (fuera de este repo) de `http://` a `https://`.
  Si se recrea la OAuth App, hay que repetir ese cambio o el login se rompe.
- **Cada navegador** debe aceptar el cert self-signed una vez (warning de
  "conexión no segura" la primera vez que entra a `https://192.168.50.208:3000`).
- **Workspaces creados ANTES de este cambio** necesitan `coder update` (no
  `restart`) para heredar el mount de la CA — ver Gotcha 4.
- **Desde 2026-10-09 `CODER_ACCESS_URL=https://201.203.104.168:3000`** (IP
  pública, con `default_sni` en Caddy y el callback de la OAuth App de GitHub
  actualizado) — ver [`RUNBOOK-vm-portainer-red.md`](RUNBOOK-vm-portainer-red.md)
  → FASE 4. Si cambia la IP pública, se repite ese procedimiento.
- El intermedio de Caddy rota cada ~7 días; si en el futuro se cambia a
  confiar el intermedio en vez del root, habría que automatizar la
  rotación. Con el root alcanza y no hace falta tocar nada.

---

## Resumen de archivos tocados

| Archivo | Cambio |
|---|---|
| `~/.config/coderv2/server.env` | `CODER_ACCESS_URL` → https, `CODER_HTTP_ADDRESS` → `127.0.0.1:3001` |
| `~/.config/caddy-coder/Caddyfile` | nuevo — sitio con hosts explícitos + `tls internal` (desde 2026-10-09: **generado** desde `Caddyfile.tmpl`, no editar) |
| `~/.config/coderv2/caddy-ca/root.crt` | nuevo — CA root exportada del volumen de Caddy |
| `templates/mvp-embedded/main.tf` | variable `caddy_ca_cert_host_path`, mount dinámico, `entrypoint` con `sudo update-ca-certificates` |
