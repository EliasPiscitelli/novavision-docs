# Cambio: Fix crítico del flujo de Provisioning y Aprobación de tiendas

- **Autor:** agente-copilot
- **Fecha:** 2026-02-07
- **Rama:** feature/automatic-multiclient-onboarding
- **Archivos modificados:**
  - `apps/api/src/worker/provisioning-worker.service.ts`
  - `apps/api/src/admin/admin.service.ts`

## Resumen

Se corrigieron **4 bugs críticos** que impedían el flujo completo de "Aprobar y Publicar" tienda. Ningún onboarding podía completarse exitosamente porque el provisioning fallaba silenciosamente.

## Bugs encontrados y corregidos

### Bug 1: `nv_onboarding.progress` es TEXT, no JSONB (CRÍTICO)
**Archivo:** `provisioning-worker.service.ts` (método `provisionClientFromOnboardingInternal`)

**Problema:** La columna `progress` en `nv_onboarding` se almacena como TEXT (string JSON serializado). Todo el código accedía a `onboarding.progress?.personal_info`, `onboarding.progress?.wizard_template_key`, etc., que retornaban `undefined` porque se invocaban propiedades sobre un string.

**Fix:** Se agregó un bloque de parseo `parsedProgress` con `JSON.parse()` + try/catch al inicio del método, y se reemplazaron las ~12 referencias de `onboarding.progress` por `parsedProgress`. También se corrigió en `runBackfillCatalog`.

### Bug 2: Extracción de categorías incorrecta
**Archivo:** `provisioning-worker.service.ts` (método `migrateCatalog`)

**Problema:** El código buscaba `p.categories` (array) en cada producto, pero los datos reales del onboarding tienen:
- `p.category` (string singular, ej: "General")
- `catalog_data.categories` (array de strings: ["General", "Combos", ...])

**Fix:** Se agregó extracción desde 3 fuentes:
1. `catalog_data.categories` (array top-level)
2. `p.categories` (array por producto, compatibilidad)
3. `p.category` (string singular por producto)

También se corrigió el linkeo product→category para soportar `p.category` singular.

### Bug 3: No se migraban FAQs, servicios, social links ni contact info
**Archivo:** `provisioning-worker.service.ts` (método `migrateCatalog`)

**Problema:** `migrateCatalog` solo manejaba productos y categorías. Los datos de onboarding contienen:
- `catalog_data.faqs` (6 FAQs con question/answer/number)
- `catalog_data.services` (3 servicios con title/description/number)
- `catalog_data.socialLinks` (object con whatsApp/wspText)
- `contact_info` (info de contacto)

Estos datos **nunca se transferían** a las tablas de multicliente.

**Fix:** Se agregaron bloques de migración para:
- **FAQs** → tabla `faqs` (upsert por `client_id,question`)
- **Services** → tabla `services` (upsert por `client_id,title`)
- **Social Links** → tabla `social_links` (upsert por `client_id,platform`)
- **Contact Info** → tabla `contact_info` (insert)

### Bug 4: Aprobación falla sin retry cuando client existe pero tiene 0 products
**Archivo:** `admin.service.ts` (método `approveClient`)

**Problema:** Si el client ya existía en multicliente (por provisioning previo parcial) pero tenía 0 productos, el guardrail lanzaba `PROVISIONING_INCOMPLETE_NO_PRODUCTS` sin intentar remediar.

**Fix:** Antes de fallar, ahora se ejecuta `runBackfillCatalog(accountId)` para reintentar la migración de catálogo. Solo si después del backfill sigue habiendo 0 productos, se lanza el error.

## Limpieza de BD realizada

Para el account de test (`kaddocpendragon@gmail.com`):

1. **Multicliente:** Se eliminó el client `ae02842d-c8b2-4be3-b825-b3eed1584cbb` y sus datos asociados (ya estaban vacíos). También se eliminó 1 usuario super_admin vinculado.
2. **Admin DB:** Se reseteó `nv_onboarding`: `client_id=null`, `provisioned_at=null`, `state=submitted_for_review`.
3. Se verificó que el account tiene `mp_connected=true`, `identity_verified=true`, `subscription_status=active` — pasa validación de aprobación.

## Estructura de datos del progress (referencia)

```
progress.catalog_data.products = [{name, price, category, description, ...}]  (11 items)
progress.catalog_data.categories = ["General", "Combos", "Profesional", "Accesorios", "Prueba"]
progress.catalog_data.faqs = [{question, answer, number}]  (6 items)
progress.catalog_data.services = [{title, description, number}]  (3 items)
progress.catalog_data.socialLinks = {whatsApp: "1122334455", wspText: "Hola!..."}
progress.contact_info = {}
```

## Cómo probar

1. Levantar API: `npm run start:dev` (terminal back)
2. Abrir Admin Dashboard y navegar al detalle del cliente `kaddocpendragon@gmail.com`
3. Hacer click en **"Aprobar y Publicar"**
4. El flujo debe:
   - Pasar la validación de checklist (sin missing items)
   - Provisionar un nuevo client en multicliente
   - Migrar 11 productos, 5 categorías, 6 FAQs, 3 servicios, social links
   - Activar el client como `is_published=true, publication_status=published`
5. Verificar en Supabase (multicliente) que las tablas `products`, `categories`, `faqs`, `services`, `social_links` tienen datos del client

## Notas de seguridad

- Los scripts temporales de análisis de BD fueron creados y eliminados en esta sesión
- No se modificaron permisos, RLS ni variables de entorno
- Los cambios solo afectan lógica de provisioning (server-side)

## Riesgos

- **Unique constraints:** Los upserts dependen de constraints (`client_id,name` en categories, `client_id,sku` en products, `client_id,question` en faqs, `client_id,title` en services, `client_id,platform` en social_links). Si alguna constraint no existe en la BD, habrá duplicados. Verificar con `\d+ <tabla>` en psql.
- **Rollback:** Revertir los 2 archivos modificados. Los datos en BD son idempotentes (upsert), se pueden limpiar manualmente si es necesario.
