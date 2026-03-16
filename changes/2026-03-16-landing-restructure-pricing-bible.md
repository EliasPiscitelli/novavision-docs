# Landing Restructure + Pricing Bible + FAQs Alineadas

**Fecha:** 2026-03-16
**Rama:** develop
**Alcance:** Admin (landing), Docs (marketing)

---

## Resumen

Reestructuración completa de la landing de NovaVision (admin homepage) siguiendo el embudo de 6 preguntas, actualización del hero con Opción A, creación del Pricing Bible como source of truth, y alineación de FAQs, servicios y pricing con la estrategia de lanzamiento.

---

## Cambios implementados

### Pricing Bible (nuevo)

- **Archivo:** `novavision-docs/marketing/PRICING_BIBLE.md`
- Source of truth para precios, entitlements, overages, cupones y add-ons
- Flag de discrepancia Enterprise: DB $250/mo vs marketing $390/mo vs es.json $120/mo
- Incluye tabla de 12 cupones pre-seeded con cupos limitados

### Hero — Opción A implementada

- **Archivos:** `admin/src/i18n/es.json`, `Banner/index.jsx`, `Banner/style.jsx`
- Título: "Dejá de perder ventas por WhatsApp e Instagram."
- Subtítulo: "Creá tu tienda online profesional con Mercado Pago, envíos integrados y SEO listo para crecer..."
- CTA primario: "Armá tu tienda gratis" → `/builder`
- CTA secundario: "Ver cómo funciona" → scroll a `#prices`
- Microcopy: "Pagás recién cuando quieras publicarla."
- Nuevo styled component `Microcopy` en Banner

### Landing — Reestructura embudo 6 preguntas

- **Archivo:** `admin/src/pages/HomePage/index.jsx`
- Nuevo orden: Banner → Services → Pricing → Hero CTA → Testimonials → LogoCarousel → FAQs → Blog → Contact → Footer
- Eliminadas secciones irrelevantes: BannerTeamSection, JoinToOurTeamCard, CloudSection, LogoCarousel duplicado
- Cada sección comentada con su función en el embudo

### Servicios — 5 pilares reales

- Título: "¿POR QUÉ NOVAVISION?" / "Todo lo que necesitás para vender online, incluido"
- 6 diferenciadores: tienda rápida, MP integrado, envíos resueltos, 0% comisión, SEO AI, revisión de calidad

### FAQs — Alineadas a objeciones de conversión

- 11 preguntas reescritas para responder objeciones reales
- Incluye: "¿Puedo probar gratis?", "¿NovaVision cobra comisión?", "¿Qué soporte incluye cada plan?" (SLA), "¿En qué se diferencia de Tiendanube?" (comparativa honesta)

### Pricing cards — Datos reales de la DB

- Features actualizadas a entitlements reales (300/2000/50000 productos, storage, órdenes)
- Setup fees removidos ($0 en la DB)
- Enterprise: $250/mo (dato DB, pendiente resolución de discrepancia)
- CTA: "Empezar gratis"

### Testimoniales — Copy ajustado

- Removido "500+ empresas" (pre-lanzamiento)
- Nuevo: "Emprendedores y pymes que ya venden con NovaVision."

### Cupones de lanzamiento — Verificados

- 12 cupones pre-seeded en Admin DB (migración ADMIN_063)
- Campo de cupón en onboarding Step 6 (PaywallPlans) ya funcional
- Cupones clave para "cupos limitados": FREEMONTH (150), STARTER50 (200), GROWTH20 (100), LAUNCH2026 (500), TRIAL3M (100)

---

## Validación

- Build admin: 4.74s OK

---

## Pendientes (decisiones de negocio)

1. **Resolver precio Enterprise:** DB $250 vs marketing $390 — actualizar DB o docs
2. **Crear propiedad GA4 + Pixel** para novavision.lat (config manual)
3. **Grabar demo** del onboarding (contenido, no desarrollo)
4. **Demo stores** de rubros distintos (contenido)
5. **Founder video** (contenido)
