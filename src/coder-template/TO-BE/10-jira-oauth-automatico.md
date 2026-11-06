# Jira OAuth 2.0 (3LO) — Tokens Automáticos por Usuario

## Resumen

Cada operador autoriza Jira **una sola vez** (un click). Después el sistema renueva tokens automáticamente.
Operador → "Conectar Jira" → Atlassian OAuth → access_token + refresh_token
                                                        │
                                               Secret Manager → ESO → Pod → MCP Jira
                                                        │
                                               Rotación automática cada hora (refresh_token)

---

## Setup (una vez — admin)

### 1. Crear OAuth App en Atlassian

1. Ir a: `https://developer.atlassian.com/console/myapps/`
2. Click **"Create"** → **"OAuth 2.0 integration"**
3. Configurar:
   - **Name:** Coder Workspace - Banco
   - **Grant type:** Account-level grant
   - **Callback URL:** `https://coder.banco-internal.com/auth/atlassian/callback`

4. En **Permissions**, agregar scopes:
   - read:jira-work — Leer issues, proyectos, boards
   - write:jira-work — Crear/editar issues, transiciones
   - read:jira-user — Leer info de usuarios

5. Guardar:
   - **Client ID** → Secret Manager: coder/shared/atlassian-oauth-client-id
   - **Client Secret** → Secret Manager: coder/shared/atlassian-oauth-client-secret

### 2. Guardar credenciales en Secret Manager
bash
aws secretsmanager create-secret \
  --name "coder/shared/atlassian-oauth-client-id" \
  --secret-string "<CLIENT_ID>"

aws secretsmanager create-secret \
  --name "coder/shared/atlassian-oauth-client-secret" \
  --secret-string "<CLIENT_SECRET>"

### 3. Desplegar el auth-callback service
bash
kubectl apply -f deploy/jira-oauth-callback.yaml

---

## Flujo del Operador (una vez)
┌─────────────────────────────────────────────────────────────┐
│  Coder Dashboard                                             │
│                                                              │
│  ⚠️ Jira no conectado                                        │
│                                                              │
│  [🔗 Conectar con Jira]  ← Un click                         │
│                                                              │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│  Atlassian OAuth Consent Screen                              │
│                                                              │
│  "Coder Workspace - Banco quiere acceder a:            │
│                                                              │
│   ✓ Leer tus issues y proyectos en Jira                     │
│   ✓ Crear y modificar issues                                │
│   ✓ Transicionar issues entre estados                       │
│                                                              │
│  [Permitir acceso]     [Denegar]                             │
│                                                              │
└──────────────────────────────┬──────────────────────────────┘
                               │ (click "Permitir")
                               ▼
┌─────────────────────────────────────────────────────────────┐
│  Callback Handler (coder auth service)                       │
│                                                              │
│  1. Recibe authorization_code                                │
│  2. Intercambia → access_token + refresh_token               │
│  3. Identifica usuario (from Coder session)                  │
│  4. Guarda en Secret Manager:                                │
│     coder/users/<username>/atlassian-access-token            │
│     coder/users/<username>/atlassian-refresh-token           │
│  5. Crea/actualiza ExternalSecret                            │
│  6. Redirect → "✅ Jira conectado!"                          │
│                                                              │
└─────────────────────────────────────────────────────────────┘

Después de esto, **el operador nunca más ve pantallas de auth.**

---

## Rotación Automática
┌──────────────────────────────────────────────────────────────┐
│  Token Refresh CronJob (cada 45 min)                          │
│                                                               │
│  Para cada usuario con refresh_token en Secret Manager:       │
│                                                               │
│  1. POST https://auth.atlassian.com/oauth/token               │
│     grant_type=refresh_token                                  │
│     refresh_token=<stored_refresh_token>                      │
│     client_id=<CLIENT_ID>                                     │
│     client_secret=<CLIENT_SECRET>                             │
│                                                               │
│  2. Respuesta: nuevo access_token (1h) + refresh_token        │
│                                                               │
│  3. Actualizar Secret Manager:                                │
│     coder/users/<username>/atlassian-access-token = nuevo     │
│     coder/users/<username>/atlassian-refresh-token = nuevo    │
│                                                               │
│  4. ESO sincroniza → Pod tiene token fresco                   │
│                                                               │
│  Resultado: token siempre válido, 0 intervención del usuario  │
└──────────────────────────────────────────────────────────────┘

---

## Implementación: Auth Callback Service

Microservicio mínimo (Node.js/Python) que maneja el OAuth callback:
python
# deploy/jira-oauth-service/app.py (ejemplo conceptual)
from flask import Flask, redirect, request, session
import requests
import boto3  # o hashicorp-vault

app = Flask(__name__)
secrets_client = boto3.client('secretsmanager')

ATLASSIAN_AUTH_URL = "https://auth.atlassian.com/authorize"
ATLASSIAN_TOKEN_URL = "https://auth.atlassian.com/oauth/token"
CLIENT_ID = get_secret("coder/shared/atlassian-oauth-client-id")
CLIENT_SECRET = get_secret("coder/shared/atlassian-oauth-client-secret")
CALLBACK_URL = "https://coder.banco-internal.com/auth/atlassian/callback"

@app.route("/auth/atlassian/start")
def start_oauth():
    """Redirect user to Atlassian consent screen."""
    username = get_coder_username(request)  # From Coder session/JWT
    
    params = {
        "audience": "api.atlassian.com",
        "client_id": CLIENT_ID,
        "scope": "read:jira-work write:jira-work read:jira-user offline_access",
        "redirect_uri": CALLBACK_URL,
        "state": username,  # Pass username through state
        "response_type": "code",
        "prompt": "consent",
    }
    return redirect(f"{ATLASSIAN_AUTH_URL}?{urlencode(params)}")

@app.route("/auth/atlassian/callback")
def oauth_callback():
    """Exchange code for tokens, store in Secret Manager."""
    code = request.args.get("code")
    username = request.args.get("state")
    
    # Exchange code for tokens
    resp = requests.post(ATLASSIAN_TOKEN_URL, json={
        "grant_type": "authorization_code",
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
        "code": code,
        "redirect_uri": CALLBACK_URL,
    })
    tokens = resp.json()
    
    # Store in Secret Manager
    store_secret(f"coder/users/{username}/atlassian-access-token", tokens["access_token"])
    store_secret(f"coder/users/{username}/atlassian-refresh-token", tokens["refresh_token"])
    
    # Trigger ESO sync (or wait for next refresh interval)
    return redirect("https://coder.banco-internal.com?jira=connected")

---

## MCP Config (cómo Claude usa el token)

El mcp-config.json se mantiene igual — usa env vars:
json
{
  "mcpServers": {
    "jira": {
      "command": "npx",
      "args": ["-y", "@mcp/jira-server"],
      "env": {
        "JIRA_BASE_URL": "${ATLASSIAN_BASE_URL}",
        "JIRA_ACCESS_TOKEN": "${ATLASSIAN_ACCESS_TOKEN}",
        "JIRA_AUTH_TYPE": "oauth2"
      }
    }
  }
}

El ExternalSecret mapea:
yaml
- secretKey: ATLASSIAN_ACCESS_TOKEN
  remoteRef:
    key: coder/users/<username>/atlassian-access-token

---

## Revocación
bash
# Revocar acceso Jira de un usuario
curl -X POST "https://auth.atlassian.com/oauth/revoke" \
  -H "Content-Type: application/json" \
  -d '{
    "client_id": "'$CLIENT_ID'",
    "token": "'$(get_refresh_token $USERNAME)'"
  }'

# Eliminar secrets
aws secretsmanager delete-secret --secret-id "coder/users/$USERNAME/atlassian-access-token"
aws secretsmanager delete-secret --secret-id "coder/users/$USERNAME/atlassian-refresh-token"

---

## Resumen de Tiempos

| Evento | Tiempo |
|--------|--------|
| Operador hace click "Conectar Jira" | 5 segundos |
| OAuth consent + callback + store | 3 segundos |
| ESO sincroniza al pod | ≤ 60 segundos |
| **Total primera vez** | **~1 minuto** |
| Rotación automática | Cada 45 min (invisible) |
| Intervención manual futura | **Nunca** |