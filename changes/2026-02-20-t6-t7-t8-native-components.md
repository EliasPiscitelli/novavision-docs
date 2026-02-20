# Cambio: Registro de componentes nativos para Templates 6/7/8 (Drift, Vanguard, Lumina)

- **Autor:** agente-copilot
- **Fecha:** 2026-02-20
- **Ramas:**
  - Web (templatetwo): `develop` → cherry-pick a `feature/multitenant-storefront` y `feature/onboarding-preview-stable`
  - Admin (novavision): `develop`
  - API (templatetwobe): `feature/automatic-multiclient-onboarding`

---

## Resumen

Los templates 6 (Drift), 7 (Vanguard) y 8 (Lumina) tenían sus componentes propios en carpetas separadas pero **no estaban registrados en el sistema de secciones dinámicas** (section registry). El builder/preview usaba componentKeys de templates anteriores (T1–T5), causando que los 3 templates nuevos se renderizaran con componentes ajenos y se vieran idénticos.

### Cambios realizados

Se registraron **22 componentes nativos** únicos de T6/T7/T8 en el sistema de secciones:

| Template | Componentes registrados | componentKeys |
|----------|------------------------|---------------|
| **Sixth (Drift)** | 8 | `hero.sixth`, `catalog.showcase.sixth`, `features.sixth`, `content.faq.sixth`, `content.contact.sixth`, `footer.sixth`, `content.testimonials.sixth`, `content.marquee.sixth` |
| **Seventh (Vanguard)** | 6 | `hero.seventh`, `catalog.showcase.seventh`, `features.seventh`, `content.faq.seventh`, `content.contact.seventh`, `footer.seventh` |
| **Eighth (Lumina)** | 8 | `hero.eighth`, `catalog.showcase.eighth`, `features.eighth`, `content.faq.eighth`, `content.contact.eighth`, `footer.eighth`, `content.testimonials.eighth`, `content.newsletter.eighth` |

### Cambios adicionales incluidos

1. **sort_order en nv_templates**: Columna agregada para ordenar templates en UI (ya ejecutada en DB).
2. **PREVIEW_DEMO_SEED**: Datos demo para el preview del builder cuando no hay productos reales.
3. **SectionRenderer**: Soporte para tipo `testimonials`, inyección global de `storeName`/`logo`/`social`/`socialLinks`.
4. **SECTION_CONSTRAINTS**: `contact` max cambiado de 1→2 (Lumina usa newsletter + contact).

---

## Archivos modificados

### Web (templatetwo)

| Archivo | Cambio |
|---------|--------|
| `src/registry/sectionComponents.tsx` | +22 imports + 22 entradas en SECTION_COMPONENTS |
| `src/registry/sectionCatalog.ts` | +`testimonials` en SectionMetadata type, +24 entradas de metadata con thumbnails temáticos |
| `src/components/SectionRenderer.tsx` | +handler `testimonials`, inyección global de storeName/logo/social, mejoras en hero/contact/footer handlers |

### Admin (novavision)

| Archivo | Cambio |
|---------|--------|
| `src/registry/sectionCatalog.ts` | Espejo de web con `planTier: "pro"` |
| `src/services/builder/designSystem.ts` | PRESET_CONFIGS sixth/seventh/eighth usan componentKeys nativos, contact max 1→2 |
| `src/services/builder/previewDemoSeed.ts` | **NUEVO** — datos demo para builder preview |
| `src/pages/BuilderWizard/steps/Step4TemplateSelector.tsx` | Import de PREVIEW_DEMO_SEED como fallback |

### API (templatetwobe)

| Archivo | Cambio |
|---------|--------|
| `src/templates/templates.service.ts` | `.order('sort_order', { ascending: true })` |
| `migrations/admin/ADMIN_062_update_nv_templates_catalog.sql` | sort_order column + 8 template upserts con orden |

---

## Motivo

Los templates 6/7/8 fueron creados con componentes propios y estilo visual único (Drift=editorial oscuro, Vanguard=brutalist industrial, Lumina=luminoso fluido), pero el sistema de builder/preview no los reconocía y les asignaba componentes de T1–T5. El resultado era que los 3 templates nuevos se veían iguales a templates anteriores.

### Decisiones de diseño

- **componentKeys con sufijo de template** (`hero.sixth` en vez de reusar `hero.fifth`) para mantener identidad visual única de cada template.
- **Thumbnails temáticos** con colores de cada template en sectionCatalog (Drift=`0f172a`/`38bdf8`, Vanguard=`18181b`/`facc15`, Lumina=`faf5ff`/`7c3aed`).
- **Tipo `testimonials`** agregado como nuevo tipo de sección válido (usado por Drift y Lumina).
- **`content.newsletter.eighth`** es exclusivo de Lumina (newsletter CTA section).
- **Headers siguen usando HeaderFifth como fallback** (los templates 6/7/8 no tienen header propio aún — DynamicHeader.jsx ya tiene los TODOs).

---

## Cómo probar

### Preview en builder (admin)
1. Levantar admin + API en dev
2. Ir al wizard de onboarding → Step 4 (selector de templates)
3. Seleccionar template 6, 7, u 8
4. Verificar que el preview renderiza componentes únicos del template (no reutilizados de T1–T5)
5. Verificar que los datos demo aparecen correctamente (productos, FAQs, contacto)

### Tienda publicada (web)
1. Tener una cuenta con template_6, template_7 o template_8 asignado
2. Navegar a la tienda
3. Verificar que las secciones tienen el estilo propio del template

### Orden de templates (API)
1. `GET /templates` → verificar que vienen ordenados por sort_order (1=first → 8=eighth)

---

## Notas de seguridad

- Sin cambios en RLS, auth, ni endpoints.
- La migración ADMIN_062 ya fue ejecutada en Supabase Admin DB (solo agrega columna y actualiza registros existentes).
- Los componentes nuevos son de UI pura — no hacen llamadas a API directamente.

---

## Riesgos

- **Bajo:** Si un template se asigna con componentKeys que no existen en sectionComponents, el SectionRenderer tiene fallback por regex que busca el tipo base.
- **Bajo:** Los headers de T6/T7/T8 usan HeaderFifth como fallback. Se necesitará crear headers nativos en el futuro.
