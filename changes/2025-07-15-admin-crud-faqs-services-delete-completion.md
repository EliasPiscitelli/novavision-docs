# Cambio: CRUD completo para FAQs, Servicios + fix delete productos + completion_percentage

- **Autor:** agente-copilot
- **Fecha:** 2025-07-15
- **Rama:** feature/automatic-multiclient-onboarding
- **Repos afectados:** templatetwobe (API), novavision (Admin)

## Archivos modificados

### Backend (API)
- `src/admin/admin.service.ts` — 5 bloques modificados
- `src/admin/admin.controller.ts` — 1 bloque agregado (rutas Services)

### Frontend (Admin)
- `src/services/adminApi.js` — 3 métodos agregados (Services)
- `src/pages/AdminDashboard/ClientApprovalDetail.jsx` — 7 bloques modificados

## Resumen de cambios

### 1. Delete de productos desbloqueado (FE + BE)
- **Problema:** El botón de borrar estaba deshabilitado para productos de onboarding (sin UUID).
- **Fix FE:** Se eliminó la condición `!p.id` del `disabled`. Ahora usa `pid` (que es `idx-N` para productos sin ID).
- **Fix BE:** `deleteAccountProduct` ahora es **híbrido**:
  - Provisioned → DELETE de tabla `products` por UUID.
  - No provisioned → parsea `idx-N` para encontrar el índice en `nv_onboarding.progress.catalog_data.products` y lo remueve del array.

### 2. FAQs CRUD híbrido (BE + FE)
- **Problema:** Los handlers `_addFaq`/`_removeFaq` existían pero estaban muertos (prefijo `_`), y la UI era read-only.
- **Fix BE:** `getAccountFaqs`, `createAccountFaq`, `deleteAccountFaq` ahora son **híbridos**:
  - Provisioned → opera sobre tabla `completion_faqs` (admin DB).
  - No provisioned → lee/escribe en `nv_onboarding.progress.catalog_data.faqs`.
- **Fix FE:** Handlers activados (`addFaq`/`removeFaq`), UI inline con tarjetas + botón X + formulario para agregar.

### 3. Services CRUD nuevo (BE + FE)
- **Problema:** No existían endpoints ni CRUD para servicios.
- **Fix BE:** Nuevos métodos `getAccountServices`, `createAccountService`, `deleteAccountService` que operan sobre `nv_onboarding.progress.catalog_data.services`. Rutas GET/POST/DELETE en controller.
- **Fix FE:** Nuevos métodos en `adminApi.js`, estado + handlers en el componente, UI inline con tarjetas y formulario.

### 4. Completion percentage recalculado (BE)
- **Problema:** `completion_percentage` devolvía valor stale (ej: 66%) porque nunca se recalculaba en `getApprovalDetail`.
- **Fix:** Después de normalizar el checklist, se llama `computeCompletionPercentage(missingItems, minimums)` y se persiste el valor actualizado en `client_completion_checklist`.

### 5. Categorías auto-load (FE)
- **Problema:** Las categorías estaban detrás de un botón "Cargar categorías" que el usuario no veía.
- **Fix:** Nuevo `useEffect` que carga categorías, FAQs y servicios automáticamente cuando `data.account.id` está disponible. Se removió el botón lazy-load.

### 6. FAQs count en checklist (FE + BE)
- **Problema:** El checklist mostraba `FAQs ✓/✗` sin conteo.
- **Fix FE:** Muestra `FAQs count/min`.
- **Fix BE:** `refreshCompletionChecklist` ahora es híbrido para FAQs: si no hay registros en `completion_faqs`, cuenta desde `progress.catalog_data.faqs`. Lo mismo en `getApprovalDetail` para `completionFaqsCount`.

## Por qué se hizo

El super admin necesita poder gestionar completamente la información de cada tienda antes de publicarla — productos, categorías, FAQs y servicios — especialmente para cuentas en onboarding que aún no están provisionadas en el backend multicliente.

## Cómo probar

1. Levantar API: `npm run start:dev` (terminal back)
2. Levantar Admin: `npm run dev` (terminal admin)
3. Ir a Super Admin Dashboard → Pending Approvals → seleccionar una cuenta
4. **Categorías:** deben cargarse automáticamente al abrir (sin botón)
5. **Productos:** el botón de borrar (🗑️) debe funcionar incluso para productos sin UUID
6. **FAQs:** debe verse un editor inline con tarjetas + formulario para agregar y botón X para eliminar
7. **Servicios:** ídem FAQs, con título y descripción
8. **Porcentaje:** debe actualizarse correctamente al agregar/eliminar ítems

## Notas de seguridad
- Todas las rutas nuevas están protegidas con `@UseGuards(SuperAdminGuard)`
- Los servicios no exponen datos cross-tenant: siempre se resuelve `accountId` → `clientId` con validación
- El patrón híbrido (onboarding progress vs DB) es consistente con categorías ya existentes
