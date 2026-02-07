# Plan paso a paso — Refactor Dashboard Detalle de Cliente

> **Fecha**: 2026-02-07  
> **Rama**: feature/automatic-multiclient-onboarding  
> **Referencia**: [client-dashboard-audit.md](../audit/client-dashboard-audit.md)

---

## Fase 1 — PR1: Fix críticos e higiene (INMEDIATA)

### Pasos:

1. **Agregar imports faltantes** en `src/pages/ClientDetails/index.jsx`:
   - `UsageChart` desde `../../components/UsageChart`
   - `AddClientModal` desde `../../components/AddClientModal`
   - `CorsOriginsManager` desde `../../components/CorsOriginsManager`
   - `ConfirmDialog` desde `../../components/ConfirmDialog`

2. **Corregir tooltip** del botón "Pago Anual" (~L707-711):
   - Cambiar `title` de "Enviar un email de recordatorio..." a "Registrar pago anual para este cliente"

3. **Eliminar styled components muertos** en `src/pages/ClientDetails/style.jsx`:
   - Borrar `EditCard`, `EditForm`, `FormRow`, `DangerZone`

4. **Validar**:
   - `npm run lint` en terminal admin
   - `npm run typecheck` en terminal admin
   - Abrir la pantalla y verificar que modales y chart renderizan

5. **Commit**: `[CELULA-3][NV-AUDIT] [FIX] Fix missing imports, tooltip, dead code in ClientDetails`

### Criterio de Aceptación:
- 0 componentes usados sin import
- Tooltip de "Pago Anual" correcto
- 0 styled components sin uso

---

## Fase 2 — PR2: Extraer custom hooks (refactor puro)

### Pasos:

1. Crear `src/pages/ClientDetails/hooks/useClientData.js`:
   - Mover lógica de fetch client + account details + resolvedAccountId
   - Mover `useState`: client, account, accountDetails, error, loading

2. Crear `src/pages/ClientDetails/hooks/useClientPayments.js`:
   - Mover `handleRegisterPayment`, `handleSendReminder`
   - Mover `useState`: payments, paymentLoading

3. Crear `src/pages/ClientDetails/hooks/useCompletionRequirements.js`:
   - Mover fetch + save + reset de completion requirements
   - Mover `useState`: completionReqs, effectiveReqs, overrideSource, saving

4. Crear `src/pages/ClientDetails/hooks/useClientUsageMetrics.js`:
   - Mover `useUsageSummary` + `fetchClientUsage` + `triggerSyncUsage`
   - Mover `useState`: usage, invoices, usageSummary, syncLoading

5. Actualizar `index.jsx` para consumir los 4 hooks

6. **Validar**: lint, typecheck, todas las acciones manuales funcionan

### Criterio de Aceptación:
- Componente principal < 600 líneas
- 0 useState directos (excepto UI local como modals open/close)

---

## Fase 3 — PR3: Normalizer de estados + badges

### Pasos:

1. Crear `src/utils/normalizeAccountHealth.ts` (o `.js`):
   - Input: `{ accountStatus, subscriptionStatus, onboardingState, catalogSource }`
   - Output: `{ badges: [...], overall: 'healthy'|'warning'|'critical'|'unknown' }`

2. Crear `src/components/HealthBadge/index.jsx`:
   - Chip MUI o styled-component con fondo por color
   - Props: `{ label, color, tooltip }`

3. Reemplazar L926-933 (texto plano) por badges contextuales

4. Agregar tooltips en cada badge con texto descriptivo

5. **Validar**: cada combinación de estados renderiza el badge correcto

### Criterio de Aceptación:
- 0 texto plano para estados
- Tooltip en cada badge

---

## Fase 4 — PR4: Eliminar queries directas a Supabase

### Pasos:

1. **`handleRegisterPayment`** (~L503-600):
   - Eliminar L539-542 (write directo a `clients.plan_paid_until`)
   - Confiar en response del POST `/admin/clients/:id/payments`
   - Usar `response.data.plan_paid_until` para actualizar estado local

2. **`loadInvoices`** (~L311-317):
   - Crear endpoint en NestJS: `GET /admin/clients/:id/invoices`
   - O migrar a `adminApi.getClientInvoices(clientId)`
   - Eliminar import de `supabase` directo

3. **`loadUsageFromSupabase`** (~L280-310):
   - Reemplazar por `useUsageSummary` (ya existe)
   - Eliminar `fetchClientUsage` import

4. **Validar**: 0 imports de `supabase`/`backendSupabase` en ClientDetails

### Criterio de Aceptación:
- 0 queries directas a Supabase desde la página
- Pagos actualizan vencimiento correctamente

---

## Fase 5 — PR5: Agrupar acciones + unificar secciones

### Pasos:

1. Reorganizar ActionsBar en 3 columnas: Operativas / Billing / Diagnóstico
2. Unificar "Analítica y facturación" (L1312-1394) con sección de métricas
3. Reemplazar emojis/unicode por iconos react-icons consistentes
4. Mover "Editar datos" a la barra de acciones

### Criterio de Aceptación:
- 0 duplicación de datos entre secciones
- Iconos consistentes (solo react-icons)

---

## Fase 6 — PR6: Loading/empty/error states

### Pasos:

1. Crear `SectionSkeleton` genérico (MUI Skeleton o custom)
2. Crear `EmptyState` (ícono + texto + CTA)
3. Crear `ErrorState` (alerta roja + botón reintentar)
4. Reemplazar `<p>Cargando cliente...</p>` y similares
5. Agregar Suspense boundaries si aplica

### Criterio de Aceptación:
- 0 texto plano para loading
- Cada sección maneja su estado de error

---

## Fase 7 — PR7: Confirmación fuerte para borrar

### Pasos:

1. Extender `ConfirmDialog` con prop `typeToConfirm`:
   - Input que requiere escribir el slug del cliente
   - Botón "Borrar" deshabilitado hasta match

2. Eliminar `createRoot` imperativo de `deleteClientEverywhere.jsx`

3. Mover lógica de borrado a `useClientData` o handler dedicado

### Criterio de Aceptación:
- Borrar requiere escribir slug completo
- 0 uso de `createRoot` imperativo

---

## Resumen de dependencias

```
Fase 1 (PR1) ← sin deps
  └→ Fase 2 (PR2) ← depende de PR1
       └→ Fase 3 (PR3) ← depende de PR2
       └→ Fase 4 (PR4) ← depende de PR2
       └→ Fase 5 (PR5) ← depende de PR2
       └→ Fase 6 (PR6) ← depende de PR2
       └→ Fase 7 (PR7) ← depende de PR2
```

## Estimaciones

| Fase | Complejidad | Estimación |
|---|---|---|
| PR1 | Baja | 30 min |
| PR2 | Media-Alta | 3-4 hs |
| PR3 | Baja-Media | 2 hs |
| PR4 | Media | 2-3 hs (incluye endpoint BE si falta) |
| PR5 | Baja | 1-2 hs |
| PR6 | Baja | 1-2 hs |
| PR7 | Media | 2 hs |
