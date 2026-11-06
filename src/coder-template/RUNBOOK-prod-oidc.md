# RUNBOOK — AuthZ de producción (Nivel 3): OIDC + Group Sync

Guía de puesta en marcha del modelo de autorización a escala descrito en
`docs/TO-BE/13-authz-a-escala.md`. Reemplaza el modelo homelab
(GitHub OAuth + `resolve-role.sh` + PAT) por **SSO corporativo con group sync**.

> **Estado:** scaffold listo (`templates/prod-oidc/`, `deploy/prod/coder-oidc.env.example`).
> **Bloqueado en homelab** por dos dependencias externas: un **IdP real**
> (Okta/Entra/Keycloak) y **Coder Premium/Enterprise** para group sync avanzado
> (mapping por regex, auto-create de grupos, SCIM). El group sync básico por
> claim OIDC funciona también en OSS con menos granularidad.

---

## Diferencia con el homelab

| | Homelab (mvp-embedded) | Producción (prod-oidc) |
|---|---|---|
| Login | GitHub OAuth | OIDC / SSO corporativo (Okta, Entra…) |
| Resolución de rol | `resolve-role.sh` + PAT del servidor | Nativa: `data.coder_workspace_owner.me.groups` |
| Credencial de AuthZ | PAT `read:org` en `server.env` | **Ninguna** (el IdP emite el claim `groups`) |
| Alta/baja de usuarios | Manual | SCIM (automático) |
| Rol → template | Label + overlay en un template | Group → **template ACL** + overlay |

El usuario **nunca pega un token**: solo hace SSO.

---

## Pasos

### 1. Configurar el IdP (una vez)
1. Crear una **App OIDC** en tu IdP (Okta/Entra/Keycloak).
2. Callback: `https://coder.tu-banco.com/api/v2/users/oidc/callback`.
3. Emitir el claim de **grupos** en el token (Okta: "Groups" claim; Entra:
   habilitar "groups" en el token de la App registration).
4. Crear los grupos: `architects`, `platform-developers`, `qa-engineers`
   (y asignar usuarios). Anotar sus IDs para el mapping.

### 2. Configurar el server de Coder
1. `cp deploy/prod/coder-oidc.env.example` a tu secret/EnvironmentFile.
2. Rellenar `CODER_OIDC_*` (issuer, client id/secret, `GROUP_FIELD`,
   `GROUP_MAPPING`).
3. Reiniciar el server. Verificar: un usuario de prueba hace SSO y en
   **Settings → Groups** aparece en su grupo.

### 3. Subir el template de producción
```bash
coder templates push prod-oidc -d templates/prod-oidc --yes
```

### 4. Aplicar Template ACL (qué grupo usa qué template) — *Premium*
```bash
# Ejemplo: solo developers pueden usar el template de developer.
coder templates edit prod-oidc --group-acl platform-developers:use
# (Repetir por template/rol según tu catálogo.)
```
En OSS sin ACL granular: un template compartido que se auto-configura por el
grupo del usuario (el `prod-oidc/main.tf` ya deriva el overlay del grupo).

### 5. Publicar los overlays en la imagen base
El template monta `/opt/overlays/<rol>/`. Hornear `overlays/{architect,developer,qa}/`
en la imagen base (ver `docs/TO-BE/06-imagen-base-docker.md`) o montarlos por
volumen. `unknown` no monta overlay (fail-closed).

### 6. Validar RBAC end-to-end
- Usuario del grupo `platform-developers` → workspace con `coder.com/role=developer`.
- Usuario sin grupo mapeado → `unknown`, workspace en perfil mínimo (sin skills/egress).
- Quitar al usuario del grupo en el IdP → al re-loguear, pierde el rol (baja efectiva).

---

## Checklist "antes de producción"

- [x] **Prioridad de rol reconciliada (2026-07-09)** — política única =
      *least-privilege*: en multi-team gana el MENOS permisivo
      (`qa < developer < architect`). Ya aplicada en `resolve-role.sh`,
      `prod-oidc/main.tf` (`role_priority`) y `docs/TO-BE/02`.
- [ ] Fail-closed verificado: sin grupo → `unknown`, nunca a un rol permisivo.
- [ ] SCIM configurado para desprovisionar bajas (requisito regulatorio).
- [ ] `ANTHROPIC_API_KEY` y secretos por **secret manager**, no en claro
      (ver `docs/TO-BE/09-gestion-secretos.md`).
- [ ] NetworkPolicies por label `coder.com/role` (ver `05-network-isolation.md`).
- [ ] Auditoría: toda resolución de rol atribuible al IdP, no a una persona
      (ver `07-observabilidad-audit.md`).
