# E2E: Subscription Pause/Downgrade + Country Configs Detail

**Fecha**: 2026-03-26
**Tipo**: Feature (end-to-end)
**Apps**: API, Admin, Web

## Resumen

Implementación end-to-end de 3 features que ya tenían backend (API) pero les faltaba la capa de servicio y UI en Admin y Web.

## Cambios por app

### Web (Storefront)

**`src/services/subscriptionManagement.js`**
- `pauseSubscription(body)` — Pausa la suscripción (detiene cobro MP + pausa tienda)
- `resumeSubscription()` — Reanuda suscripción pausada
- `checkDowngrade(targetPlanKey)` — Verifica elegibilidad para downgrade
- `requestDowngrade(targetPlanKey)` — Solicita downgrade de plan

**`src/components/admin/SubscriptionManagement/SubscriptionManagement.jsx`**
- Botones "Pausar suscripción" y "Reactivar suscripción" (nivel billing, no solo tienda)
- Modal de pausa con selector de duración (1-3 meses)
- Sección de planes de downgrade con verificación de elegibilidad
- Modal de confirmación de downgrade con chequeo async de compatibilidad
- Separación de `upgradePlans` vs `downgradePlans` en la grilla de planes

### Admin (Dashboard)

**`src/services/adminApi.js`**
- 4 métodos CRUD para subdivisiones (`getSubdivisions`, `createSubdivision`, `updateSubdivision`, `deleteSubdivision`)
- 4 métodos CRUD para categorías fiscales (`getFiscalCategories`, `createFiscalCategory`, `updateFiscalCategory`, `deleteFiscalCategory`)
- 3 métodos para gestión de suscripciones (`pauseSubscription`, `resumeSubscription`, `downgradeSubscription`)

**`src/pages/AdminDashboard/CountryConfigsView.jsx`**
- Panel de detalle expandible al hacer click en un país
- Tab "Subdivisiones" con CRUD completo (crear, editar inline, eliminar)
- Tab "Categorías Fiscales" con CRUD completo
- Styled components: TabBar, Tab, DetailPanel, SmallTable, MiniForm

**`src/pages/AdminDashboard/SubscriptionDetailView.jsx`**
- Botón "Pausar suscripción" (amarillo, visible si status=active)
- Botón "Reanudar suscripción" (verde, visible si status=paused)
- Botón "Downgrade" (naranja, visible si active/trialing)
- Modal de pausa con selector 1-3 meses
- Modal de downgrade con selector de plan destino
- Campos `paused_at` y `pause_expires_at` en la sección de detalle
- Badge variant para status 'paused'

## Endpoints API consumidos

| Endpoint | Método | Consumido por |
|----------|--------|---------------|
| `/subscriptions/client/manage/pause-subscription` | POST | Web |
| `/subscriptions/client/manage/resume-subscription` | POST | Web |
| `/subscriptions/client/manage/downgrade-check` | GET | Web |
| `/subscriptions/client/manage/downgrade` | POST | Web |
| `/subscriptions/admin/pause/:accountId` | POST | Admin |
| `/subscriptions/admin/resume/:accountId` | POST | Admin |
| `/subscriptions/admin/downgrade/:accountId` | POST | Admin |
| `/admin/country-configs/:countryId/subdivisions` | GET/POST | Admin |
| `/admin/country-configs/subdivisions/:id` | PATCH/DELETE | Admin |
| `/admin/country-configs/:countryId/fiscal-categories` | GET/POST | Admin |
| `/admin/country-configs/fiscal-categories/:id` | PATCH/DELETE | Admin |

## Notas

- Pause subscription != Pause store. El primero suspende billing en MP y auto-pausa la tienda. El segundo solo oculta la tienda.
- Downgrade verifica elegibilidad antes de confirmar (uso actual vs límites del plan destino).
- Los endpoints de API ya existían, esta implementación conecta las capas de UI y servicio.
