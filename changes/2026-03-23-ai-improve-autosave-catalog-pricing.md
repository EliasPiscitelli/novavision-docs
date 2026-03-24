# AI Improve Auto-Save + Recalibrar Pricing Catálogo

**Fecha:** 2026-03-23
**Apps afectadas:** Web, API (migración admin)

## Cambios

### 1. Auto-save después de aceptar mejoras AI (Web)

- **Archivo:** `apps/web/src/components/ProductModal/index.jsx`
- **Problema:** Al aceptar mejoras AI en modo edición, los cambios se aplicaban al formulario pero no se guardaban en BD. La imagen AI temporal tampoco se confirmaba.
- **Solución:** `handleAcceptAiImprove` ahora invoca `handleSubmit(onSubmit)()` automáticamente en modo edición, lo que persiste datos e imágenes en una sola acción.
- En modo creación, el toast se actualizó para indicar claramente que el usuario debe hacer clic en "Crear".

### 2. Recalibrar pricing de catálogo AI (Admin DB)

- **Archivo:** `apps/api/migrations/admin/ADMIN_094_update_catalog_pricing.sql`
- **Problema:** `ai_catalog_generation` costaba 0.8-1.5 cr/producto vs `ai_product_full` a 2-5 cr/producto (2.5-3.3x más barato sin justificación).
- **Solución:** Nuevos precios con descuento bulk razonable:
  - normal: 8 → 15 créditos (1.5 cr/prod, 25% descuento vs individual)
  - pro: 15 → 40 créditos (4 cr/prod, 20% descuento vs individual)
- Migración ejecutada directamente en Admin DB. Cache de 60s del servicio se refresca solo.
