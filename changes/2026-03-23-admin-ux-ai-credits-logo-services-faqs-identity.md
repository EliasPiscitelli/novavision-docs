# Admin UX — Créditos AI, Logo, Servicios, FAQs, Identity

**Fecha:** 2026-03-23
**Rama:** develop → cherry-pick a ambas ramas prod
**Commit:** `498a98a`

## Cambios

### 1. AiButton muestra costo del tier (no balance global)
- **Archivo:** `_shared/AiButton.jsx` + todos los consumidores
- Nueva prop `cost`: cuando está disponible, el badge muestra el costo de la acción (ej: "2 cr") en vez del balance total ("60 cr")
- Se agregó `getCost()` a: ProductModal (5 botones), ReviewsDashboard, QADashboard, BannerSection, LogoSection, FaqSection, ServiceSection, IdentityConfigSection (2 botones)

### 2. LogoSection — simplificación y mejora UX
- **Archivos:** `LogoSection/index.jsx`, `LogoSection/style.jsx`
- Eliminada sección completa de storage quota (StatusRow, UsageGrid) — irrelevante para un archivo de 200KB
- "Generar con IA" movido arriba del preview (antes estaba debajo de todo)
- Contenedor ampliado: max-width 520→700px, preview min-height 120→200px, logo max-height 160→220px

### 3. ServiceSection — AI button en header
- **Archivo:** `ServiceSection/index.jsx`
- Nuevo botón "Crear con IA" visible a nivel del header (al lado de "Crear Servicio")
- Al clickear, abre el modal en modo creación con panel AI

### 4. FaqSection — AiTierToggle en header
- **Archivo:** `FaqSection/index.jsx`
- AiTierToggle agregado al header junto al botón "Generar FAQs con IA"
- El usuario puede seleccionar Normal/Pro antes de abrir el modal

### 5. IdentityConfigSection — diferenciación visual por tabs
- **Archivos:** `IdentityConfigSection/index.jsx`, `IdentityConfigSection/style.jsx`
- Cards con borde lateral de color por tab: Pie de Página (violeta), Contacto (verde), Anuncios (amarillo), Dominio (azul)
- CardTitle con color de acento matching
- Espaciado entre cards aumentado: margin-bottom 1.25→2rem, font-size del título 1→1.1rem

## Validación
- ensure-no-mocks: OK
- lint: 0 errores
- typecheck: OK
- build: OK (6.53s)
- Pre-push hooks: OK en las 3 ramas
