# RUNBOOK — Backend LLM de Claude Code en los workspaces

Cómo queda autenticado `claude` dentro de los workspaces. El backend es
**swappable** por variables de la plantilla. Precedencia en el template
(`templates/mvp-embedded/main.tf` → `local.llm_env`):
**vertex > bedrock > subscription (token) > api_key**.

- Variables: `llm_backend`, `claude_code_oauth_token`, `anthropic_api_key`,
  `vertex_project`, `vertex_region`.
- Se aplican al subir las plantillas por rol con
  [`deploy/vm/push-role-templates.sh`](../deploy/vm/push-role-templates.sh)
  (ver [`RUNBOOK-plantillas-por-rol.md`](RUNBOOK-plantillas-por-rol.md)), que las
  toma de **variables de entorno** y solo pasa las que estén definidas. Los
  secretos nunca se escriben a disco ni van a git.

> El template arma solo las env vars del backend elegido (`local.llm_env`),
> evitando un `ANTHROPIC_API_KEY` vacío que dejaba a `claude` sin autenticar.

---

## Estado actual (2026-10-15) — login por usuario

`llm_backend=subscription` **sin** token en la plantilla: no llega ningún
`CLAUDE_CODE_OAUTH_TOKEN`/`ANTHROPIC_API_KEY` al workspace. Cada usuario se
autentica una vez dentro de Claude Code con `/login` (su propia cuenta); la
credencial queda en su home (volumen persistente), así que sobrevive a
reinicios y recreaciones del contenedor.

El panel del workspace muestra un **gasto estimado** de Claude por tokens (ver
"Estimated AI spend/month" en `RUNBOOK-plantillas-por-rol.md`), no una factura.

---

## Opción A — Token de suscripción Claude Pro/Max compartido

### A1. Generar el token (una vez, interactivo)
```bash
claude setup-token
```
- **No lo interrumpas.** Abre la URL que imprime, inicia sesión con la cuenta
  Claude Pro/Max y **autoriza**.
- Al terminar imprime el token en **una sola línea**, empieza por **`sk-ant-oat01-`**.
- **Copia el token COMPLETO** (~100+ caracteres; si se corta, da 401).

### A2. VERIFICAR que autentica (antes de subirlo)
```bash
read -rs CLAUDE_CODE_OAUTH_TOKEN && export CLAUDE_CODE_OAUTH_TOKEN   # pegar, Enter (no se ve)
echo "len=${#CLAUDE_CODE_OAUTH_TOKEN} prefijo=${CLAUDE_CODE_OAUTH_TOKEN:0:12}"
W=coder-<owner>-<workspace>      # cualquier workspace corriendo
docker exec -e CLAUDE_CODE_OAUTH_TOKEN "$W" bash -lc 'HOME=/tmp/h timeout 45 claude -p "di: AUTH_OK"' 2>&1 | head -4
```
- **OK** = responde (p. ej. `AUTH_OK`). **Falla** = `401 Invalid bearer token` → Troubleshooting.

### A3. Aplicar
```bash
LLM_BACKEND=subscription bash deploy/vm/push-role-templates.sh   # usa el CLAUDE_CODE_OAUTH_TOKEN exportado
unset CLAUDE_CODE_OAUTH_TOKEN
```
Cada usuario **reinicia su workspace** desde la UI → `claude` ya usa ese token.

> **Ojo:** al dejar de pasar el token en un push posterior, la nueva versión de
> la plantilla queda **sin** token (vuelve al login por usuario).

---

## Opción B — API key (pago por token)

1. console.anthropic.com → **API Keys** → crear una (`sk-ant-api03-...`).
2. Aplicar:
   ```bash
   read -rs ANTHROPIC_API_KEY && export ANTHROPIC_API_KEY
   LLM_BACKEND=api_key bash deploy/vm/push-role-templates.sh
   unset ANTHROPIC_API_KEY
   ```
3. Restart de los workspaces.

---

## Opción C — Vertex AI / Bedrock (multi-usuario real, billing central)

```bash
LLM_BACKEND=vertex VERTEX_PROJECT=mi-proyecto-gcp VERTEX_REGION=us-east5 \
  bash deploy/vm/push-role-templates.sh
```
- El workspace necesita **credenciales GCP (ADC)** — service account con acceso a
  Vertex AI (montar la key o Workload Identity en K8s).
- El template setea solo `CLAUDE_CODE_USE_VERTEX=1` + `ANTHROPIC_VERTEX_PROJECT_ID`
  + `CLOUD_ML_REGION`. Bedrock = `LLM_BACKEND=bedrock` + credenciales AWS.

---

## Troubleshooting

| Síntoma | Causa | Fix |
|---|---|---|
| Valor no empieza por `sk-ant-oat01-` | Se pegó algo que NO es el token (flujo interrumpido / clipboard) | Re-correr `claude setup-token` completo |
| Formato correcto pero **401 Invalid bearer token** | Token **incompleto** o flujo no completado | Regenerar y copiar COMPLETO (una línea) |
| 401 aún con token correcto | Credencial guardada en `~/.claude.json` pisando | Probar con HOME limpio (`HOME=/tmp/h`, como en A2) |
| La API de Coder muestra el valor con `len=10` | Es el **enmascarado** de secretos de Coder (`*redacted*`) | Ignorar; validar con el auth test, no por la API |

---

## Notas

- **Multi-usuario:** un token/suscripción compartido es **una sola cuenta** para
  todos. Para multi-usuario real → Vertex/Bedrock (billing central) o login por
  usuario (lo actual).
- **Dónde vive el secreto:** en la plantilla de Coder (variable sensible). En
  producción → secret manager (ver `docs/TO-BE/09-gestion-secretos.md`).
