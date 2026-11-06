# Política de Privacidad — Integración OAuth "coder-atlassian"

**Última actualización:** 30 de julio de 2026
**Responsable:** Qintess — equipo DevSecOps
**Contacto:** jmparra1993@gmail.com

---

## 1. Qué es esta aplicación

`coder-atlassian` es una **integración OAuth 2.0 (3LO)** que permite a un usuario
conectar su cuenta de Atlassian (Jira / Confluence) con su entorno de desarrollo
en la plataforma interna basada en **Coder + Claude Code**. Su único propósito es
que las herramientas del entorno del usuario puedan **leer y escribir en Jira /
Confluence en nombre del propio usuario**, con su misma identidad y permisos.

La aplicación **no** es un producto público de consumo: se usa dentro de un contexto
corporativo/piloto controlado.

## 2. Qué datos accede

Con la autorización explícita del usuario (el clic de "Login with Atlassian"), la
integración obtiene un **token de acceso OAuth** que le permite invocar la API de
Atlassian **con los permisos que el usuario ya tiene**. A través de ese token puede
acceder a:

- Contenido de **Jira** (incidencias, proyectos, transiciones) según los scopes autorizados.
- Contenido de **Confluence** (páginas, espacios) según los scopes autorizados.
- Datos básicos de identificación del usuario expuestos por la API (p. ej. su AccountID)
  **solo durante la sesión**, para dirigir las llamadas a su instancia.

La integración **solo puede ver lo que el usuario ya puede ver**. No amplía accesos.

## 3. Qué datos almacena

- **Token OAuth (credencial):** el token de acceso y el token de refresco se
  custodian en el servidor de la plataforma (Coder) **asociados a la cuenta del
  usuario**, con el único fin de mantener la conexión activa y renovarla
  automáticamente. Es una credencial, no contenido personal.
- **Contenido de Jira/Confluence:** **no se almacena ni se cachea**. La información
  se consulta bajo demanda y se usa en el momento; no se copia a sistemas propios ni
  se retiene más de 24 horas.
- **Datos personales:** la aplicación **no** copia ni conserva perfiles ni datos
  personales de los usuarios en sistemas propios.

## 4. Cómo se usan los datos

Exclusivamente para **ejecutar las acciones que el usuario solicita** desde su
entorno (consultar/crear incidencias, leer documentación, etc.). No se usan para
publicidad, perfilado, ni ningún fin distinto al descrito.

## 5. Compartición con terceros

**No** se venden, alquilan ni comparten datos con terceros. La comunicación ocurre
únicamente entre el entorno del usuario y las APIs de Atlassian.

## 6. Retención y eliminación

- El token OAuth se conserva mientras la conexión esté activa.
- El usuario puede **revocar el acceso en cualquier momento**:
  - Desde Atlassian: *id.atlassian.com* → *Connected apps* → revocar `coder-atlassian`.
  - Desde la plataforma: *Account → External Authentication* → desconectar Atlassian.
- Al revocar, el token deja de ser válido y no se conserva.

## 7. Seguridad

Las credenciales se transmiten por canales cifrados (HTTPS/TLS) y se almacenan con
acceso restringido en el servidor de la plataforma. Se aplica el principio de mínimo
privilegio en los scopes solicitados.

## 8. Cambios a esta política

Cualquier cambio material se reflejará en esta página, actualizando la fecha de
"Última actualización".

## 9. Contacto

Para dudas sobre privacidad relacionadas con esta integración:
**jmparra1993@gmail.com**
