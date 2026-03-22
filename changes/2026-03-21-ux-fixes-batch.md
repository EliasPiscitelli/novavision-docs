# 2026-03-21 — UX Fixes Batch: CreditBadge, Banner, FAQ context, Media Library, FAQ width, ServiceSection AI, Addon Store, Footer AI Links

## Resumen

Batch de correcciones UX y mejoras en el admin dashboard + storefront.

## Cambios aplicados

### Bug fixes

1. **CreditBadge transparencia** (`web/AiButton.jsx`)
   - Alpha de fondo: `0.12` → `0.22`
   - Alpha en estado $zero: `0.12` → `0.18`
   - Agregado `border: 1px solid` con alpha sutil para contraste

2. **getBalance retorna null para action_codes desconocidas** (`web/hooks/useAiCredits.js`)
   - `return 0` → `return null` cuando la action_code no existe en el mapa
   - Ajustadas comparaciones `=== 0` en `BannerSection` y `ProductModal` para manejar `null`
   - Impacto: botones de IA ya no se bloquean cuando el backend no tiene pricing row para esa action

3. **Media Library bloqueada para Growth** (`api/plans/featureCatalog.ts`)
   - Agregada feature `content.media_library` al catalogo con `starter: false, growth: true, enterprise: true`

4. **FAQ width en storefront** (`web/storefront/FAQSection/variants/Cards.tsx`, `Masonry.tsx`)
   - `maxWidth: 'var(--nv-content-max-width)'` (1280px) → `'48rem'` (768px)
   - Consistente con variante Accordion que ya usaba 48rem

### Nuevas features

5. **FAQ modo contexto** (frontend + backend)
   - Frontend: toggle "Por productos" / "Por contexto de marca" en modal de generacion AI
   - Backend: nuevo metodo `generateFaqsFromContext()` en `ai-generation.service.ts`
   - Nuevos prompts: `FAQ_CONTEXT_SYSTEM_PROMPT` + `buildFaqContextPrompt()` en `prompts/index.ts`
   - Controller: acepta `source: 'context'` en body del POST

6. **AI Service Create** (`web/ServiceSection/index.jsx`)
   - Seccion AI movida ARRIBA del formulario (antes estaba al fondo, solo en modo editar)
   - Modo crear: textarea para describir la idea + boton "Generar servicio" (endpoint `POST /services/ai-create` ya existia)
   - Modo editar: boton "Mejorar con IA" (sin cambios funcionales)

7. **Addon Store tematizado por categoria** (`web/AddonStoreDashboard/index.jsx`)
   - Nuevo mapa `FAMILY_THEME` con color, gradient, glow e icono por familia
   - CardOrb: gradiente y color dinamicos por categoria
   - CardGlow: color de categoria en vez de azul/violeta fijo
   - FilterPill: icono de categoria + color activo tematizado
   - MetaPill de familia: icono + color de fondo tematizado

8. **AI Footer Links** (frontend + backend + storefront pipeline)
   - Backend: nuevo endpoint `POST /footer/ai-generate` que genera ~5 links de navegacion sugeridos
   - Nuevos prompts: `FOOTER_LINKS_SYSTEM_PROMPT` + `buildFooterLinksPrompt()` en `prompts/index.ts`
   - Service: `generateFooterLinks()` que recolecta servicios, categorias, contacto, FAQs, tenant_pages
   - Frontend: boton "Sugerir con IA" + AiTierToggle en card de "Enlaces personalizados" de IdentityConfigSection
   - SectionRenderer: conectado pipeline `identity_config.footer.links` → Footer component via prop `footerLinks`
   - Los links legales (Terminos, Privacidad, Arrepentimiento) siguen siendo estaticos y obligatorios

### Documentacion

9. **Plan Dynamic Footer** (`novavision-docs/plans/PLAN_DYNAMIC_FOOTER_GENERATION.md`)
   - Documentado plan completo: nueva tabla, modulo API, componente admin, integracion storefront

## Archivos modificados

| Archivo | Tipo |
|---------|------|
| `web/src/components/admin/_shared/AiButton.jsx` | Edit |
| `web/src/hooks/useAiCredits.js` | Edit |
| `web/src/components/admin/BannerSection/index.jsx` | Edit |
| `web/src/components/ProductModal/index.jsx` | Edit |
| `web/src/components/admin/FaqSection/index.jsx` | Edit |
| `web/src/components/admin/ServiceSection/index.jsx` | Edit |
| `web/src/components/admin/AddonStoreDashboard/index.jsx` | Edit |
| `web/src/components/storefront/FAQSection/variants/Cards.tsx` | Edit |
| `web/src/components/storefront/FAQSection/variants/Masonry.tsx` | Edit |
| `api/src/ai-generation/ai-generation.controller.ts` | Edit |
| `api/src/ai-generation/ai-generation.service.ts` | Edit |
| `api/src/ai-generation/prompts/index.ts` | Edit |
| `api/src/plans/featureCatalog.ts` | Edit |
| `web/src/components/admin/IdentityConfigSection/index.jsx` | Edit |
| `web/src/components/SectionRenderer.tsx` | Edit |
| `novavision-docs/plans/PLAN_DYNAMIC_FOOTER_GENERATION.md` | New |

## Verificacion

- Build web: OK
- Build API: OK
