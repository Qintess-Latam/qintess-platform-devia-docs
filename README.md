# Dev-IA — Documentación del Proyecto (libro mdBook)

Documentación consolidada del proyecto Dev-IA (Coder + Claude Code + GitHub Copilot CLI por
rol, RBAC real, Symphony/Backstage) — compilada desde los 4 repos fuente del proyecto en
`Qintess-Latam`, más un documento nuevo de accesos/credenciales que no existía repartido en
ningún lado como inventario único.

**Fuente de verdad real = los 4 repos originales.** Este repo es una copia de lectura para
quien necesite el panorama completo sin tener que saltar entre repos, o para quien tome
continuidad del proyecto.

## Ver el libro

**Opción 1 — en el navegador, local:**
```bash
cargo install mdbook   # si no lo tenés
git clone https://github.com/Qintess-Latam/qintess-platform-devia-docs.git
cd qintess-platform-devia-docs
mdbook serve --open
```

**Opción 2 — Docker (incluye Nginx, sirve en el puerto 80):**
```bash
docker build -t devia-docs .
docker run -p 8080:80 devia-docs
# abrir http://localhost:8080
```

**Opción 3 — directo en GitHub**, navegando `src/` — el markdown se renderiza nativo, solo
que sin el índice/navegación del libro.

> **GitHub Pages:** el workflow en `.github/workflows/BuildAndDeploy.yml` publicaría el libro
> automático en cada push a `main`, pero hoy **no corre**: Pages en repo privado necesita plan
> GitHub Pro/Team/Enterprise (la org está en Free), y Actions en esta org está bloqueado por
> una verificación de cuenta pendiente (ver `ACCESOS-Y-CREDENCIALES.md` → sección de
> pendientes). Se activa solo el día que se resuelvan esas dos cosas, sin tocar nada más acá.

## Empezar a leer

- [`src/README.md`](src/README.md) — índice completo con qué hay y por dónde arrancar.
- [`src/ACCESOS-Y-CREDENCIALES.md`](src/ACCESOS-Y-CREDENCIALES.md) — **leer primero** si vas a tomar continuidad del proyecto.

## Mantener actualizado

Esto es una foto, no se sincroniza solo. Si algo cambia en los 4 repos fuente
(`qintess-platform-coder-template`, `-agents-overlays`, `-agents-skills`, `-backstage-mngr`),
hay que volver a traer los archivos actualizados a `src/` y hacer commit — no hay automatismo
hoy.
