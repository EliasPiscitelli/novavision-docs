# Auditoría: Churn y Lifecycle Post-Cancelación — NovaVision 2026-03-25

## Resumen ejecutivo

NovaVision tiene **una sola suscripción activa en producción** (farma, plan Growth) y **cero cancelaciones históricas**. El sistema de cancelación está implementado a nivel de código con un nivel de sofisticación alto (cancel_scheduled con grace period, deuda pendiente, cancelación en MP, downgrade de entitlements, pause de tienda, audit trail). Sin embargo, **nunca ha sido ejecutado en producción**. El CRM (Customer360, health score, lifecycle stages) existe como estructura de datos y UI pero tiene **0 registros operativos**. Los cupones están configurados (10 activos) pero **ninguno fue canjeado**. No existe ningún flujo de win-back automático, ni secuencia de retención post-cancelación, ni mecanismo de pausa como alternativa a la baja. El riesgo principal es que cuando lleguen las primeras cancelaciones, el sistema no habrá sido probado end-to-end en producción y no hay automatizaciones de retención que mitiguen el churn.

---

## Flujo de cancelación actual

### Lo que está implementado en código (`subscriptions.service.ts`)

El flujo de cancelación se inicia desde dos endpoints:
- **Builder**: `POST /subscriptions/manage/cancel` (BuilderSessionGuard)
- **Client Dashboard**: `POST /subscriptions/client/manage/cancel` (ClientDashboardGuard)

**Paso a paso del método `requestCancel()`:**

1. **Validación de motivo**: El campo `reason` es obligatorio. Valores aceptados: `too_expensive`, `not_using`, `missing_features`, `technical_issues`, `moving_platform`, `other`. También acepta `reason_text` (texto libre) y `wants_contact` (booleano).

2. **Idempotencia**: Si se envía `idempotency_key`, verifica en `nv_cancellation_requests` para evitar doble cancelación. **Estado actual**: la tabla existe pero tiene 0 registros.

3. **Lock advisory**: Adquiere lock por `account_id` para prevenir race conditions.

4. **Verificación de deuda** (líneas 1290-1368): Si la cuenta tiene deuda por overages o comisiones:
   - Pausa la tienda inmediatamente
   - Crea preferencia de pago de deuda vía `billingService.createCancellationDebtPreference()`
   - Retorna estado `cancel_pending_payment` con link de pago
   - La cancelación se completa solo cuando la deuda se paga

5. **Lógica de fecha efectiva**:
   - Si `current_period_end > now` → **Cancelación programada** (`cancel_scheduled`): la tienda sigue activa hasta fin del período pagado. Data retention: 60 días después.
   - Si `current_period_end <= now` → **Cancelación inmediata** (`canceled`): se ejecuta todo de inmediato.

6. **Cancelación en MercadoPago**: Llama `platformMp.cancelSubscription(mp_preapproval_id)` que actualiza el preapproval a `status='cancelled'`. Es non-blocking (si falla, continúa).

7. **Actualizaciones en BD**:
   - **Cancel scheduled**: `subscriptions.status='cancel_scheduled'`, `cancel_at_period_end=true`, `deactivate_at=fecha`. `nv_accounts.subscription_status='cancel_scheduled'`. **La tienda sigue activa**.
   - **Cancel immediate**: `subscriptions.status='canceled'`, `cancelled_at=now`. `nv_accounts.subscription_status='canceled'`. Downgrade de entitlements a free tier. Pause de tienda.

8. **Audit trail**: `logSubAction()` con correlation ID, `lifecycle_events` con tipo `subscription_cancel_requested`, `nv_billing_events` con acción y motivo.

9. **Notificaciones** (non-blocking):
   - Email al super admin con detalle del motivo, texto libre y preferencia de contacto
   - Email de confirmación al tenant

### Lo que NO está implementado

- **No existe tabla `subscription_cancel_log`** — el código la referencia para idempotencia pero la tabla no está creada en la BD.
- **No hay exit survey en UI** — el motivo se envía como parámetro del endpoint, pero no se encontró un modal/formulario dedicado en el Admin dashboard que lo capture de forma amigable (solo el botón de baja de Disposición 954).
- **No hay alerta interna al equipo vía Slack/WhatsApp** cuando un tenant cancela — solo email al super admin.
- **No hay secuencia automatizada post-cancelación** — el email de confirmación es el único touchpoint.

### Estado real en producción

| Dato | Valor |
|------|-------|
| Cancelaciones ejecutadas | **0** |
| Registros en `nv_cancellation_requests` | **0** |
| Registros en `cancellation_debt_log` | **0** |
| Registros en `client_tombstones` | **0** |
| Registros en `compliance_events` | **0** |
| Última cancelación | **Nunca** |

---

## Estado de la tienda post-cancelación

### Mecanismo implementado

**Pause automático** (`pauseStoreIfNeeded()`):
- Actualiza `nv_accounts.store_paused=true` + `store_pause_reason='subscription_<status>'`
- Propaga a Backend DB: `clients.publication_status='paused'` + `clients.is_active=false`(implícito por el status mapping)
- Se ejecuta en cancelación inmediata, suspensión, y deactivación

**Verificación en storefront** (`TenantProvider.jsx` + `StorefrontAdminGuard.jsx`):
- Bootstrap vía `GET /tenant/bootstrap` → verifica `is_active` y `status`
- Si `is_active=false` o `status='suspended'` → renderiza modal "Tienda Suspendida" con contacto a soporte
- El storefront público queda completamente bloqueado para tiendas con `is_active=false`

**Verificación en SubscriptionGuard** (`subscription.guard.ts`):
- Solo permite acceso con status `active` o `past_due` dentro del grace period
- Todo lo demás → `ForbiddenException`

### Grace period

| Configuración | Valor |
|--------------|-------|
| Variable de entorno | `GRACE_PERIOD_DAYS` |
| Default | **7 días** |
| Diferenciación por plan | **No existe** — mismo período para todos |
| Cron de expiración | Daily 3:00 AM (`processGracePeriodExpirations()`) |
| Warning 48h | Sí, envía notificación `grace_warning_48h` |

**Nota**: La documentación de planes menciona grace periods diferenciados (Growth: 14d, Enterprise: 30d) pero el código usa un valor único configurable por env var.

### Datos del tenant post-cancelación

| Fase | Datos | Tienda | Entitlements |
|------|-------|--------|-------------|
| Cancel scheduled | Conservados | Activa | Activos |
| Cancel immediate | Conservados | Pausada | Downgrade a free |
| Suspended >30 días | Conservados → soft delete | Pausada | Removidos |
| Tombstone (domingo 2:55 AM) | Snapshot guardado en `client_tombstones` | Hard delete en Backend DB | N/A |
| Slug release (domingo 4:00 AM) | Slug liberado en `slug_reservations` | N/A | N/A |

**Campo `purge_at`**: Existe en la tabla `subscriptions` — se calcula como `effective_end_at + 60 días`. El método `purgeAccountData()` anonimiza PII (email→`purged+<id>@novavision.lat`, borra nombre, fiscal ID, dirección, teléfono) y marca `subscription_status='purged'`.

### Estado real

- **0 tiendas canceladas** en Backend DB
- **3 clientes activos**, todos con `is_active=true`, `publication_status='published'`
- **0 tombstones** guardados
- El lifecycle-cleanup cron existe pero nunca ha ejecutado acciones reales de cleanup

---

## Consumo de infraestructura en cuentas inactivas

### Datos reales actuales

| Métrica | Valor |
|---------|-------|
| Total cuentas en Admin DB | 5 (1 activa, 2 e2e test, 2 draft/test) |
| Total clientes en Backend DB | 3 (1 productivo, 2 e2e test) |
| Productos totales | 58 (38 farma + 10+10 e2e) |
| Órdenes totales | 8 (todas de farma) |
| Usuarios totales | 5 |
| Banners | 14 |
| FAQs | 12 |
| Categorías | 29 |
| Media files (tenant_media) | **0** |
| Cart items | 3 |

### Cuentas que consumen sin ser productivas

| Cuenta | Tipo | Productos | Órdenes | Estado |
|--------|------|-----------|---------|--------|
| e2e-alpha | Test E2E | 10 | 0 | Activa |
| e2e-beta | Test E2E | 10 | 0 | Activa |
| draft-* (x2) | Draft/test en Admin DB | 0 | 0 | Sin backend client |

Las cuentas e2e-alpha y e2e-beta tienen `subscription_status=NULL` en `nv_accounts` y `lifecycle_stage='lead'`, lo que indica que son cuentas provisionadas para testing sin suscripción real.

### Outreach leads

| Status | Cantidad |
|--------|----------|
| NEW | 46,837 |
| DISCARDED | 460 |
| CONTACTED | 3 |
| IN_CONVERSATION | 3 |
| **Total** | **47,303** |

La gran mayoría (47,299) provienen de un import masivo (`EXCEL_2025_11`). **Ninguno corresponde a ex-clientes** porque no hay ex-clientes.

### Costo de infraestructura

- **Supabase** (ambas instancias): Plan Free tier permite hasta 500MB de BD y 1GB de storage. Con el volumen actual (<1MB de datos), no hay costo marginal por datos "muertos".
- **Railway**: Factura por uso de CPU/RAM del servicio API, no por datos almacenados en Supabase.
- **Riesgo futuro**: Cuando haya decenas de tenants cancelados con catálogos de cientos de productos e imágenes en storage, el costo de mantener datos muertos será significativo en Supabase (storage es el factor más costoso).

### Mecanismos de limpieza existentes

| Mecanismo | Estado | Descripción |
|-----------|--------|-------------|
| Soft delete (30d post-suspensión) | ✅ Implementado | `lifecycle-cleanup.cron.ts` líneas 109-160 |
| Tombstone save (domingo 2:55 AM) | ✅ Implementado | Guarda snapshot antes de hard delete |
| Hard delete en Backend DB | ✅ Implementado | Borra orders, products, users, clients |
| Release de slugs (domingo 4:00 AM) | ✅ Implementado | Libera `slug_reservations` |
| PII purge (`purgeAccountData()`) | ✅ Implementado | Anonimiza email, nombre, datos fiscales |
| Zombie detection (90d sin login) | ✅ Implementado | Alerta al founder, no auto-acción |
| Storage cleanup (Supabase buckets) | ❌ **NO implementado** | **GAP**: No se borran imágenes/assets de tenants eliminados |
| Archivado frío / compresión | ❌ **NO implementado** | No hay tier de almacenamiento diferenciado |

---

## Sistema de reactivación

### Lo que existe

**Revert cancel** (`revertCancel()`):
- Solo funciona cuando `status='cancel_scheduled'` y `deactivate_at` no ha pasado
- Restaura `status='active'` en subscriptions y nv_accounts
- Reactiva preapproval en MP vía `resumeSubscription()`
- Emite evento `subscription_cancel_reverted`

**Endpoints disponibles**:
- `POST /subscriptions/manage/revert-cancel` (builder)
- `POST /subscriptions/client/manage/revert-cancel` (client dashboard)

### Lo que NO existe

| Gap | Descripción |
|-----|-------------|
| Reactivación desde `canceled` | No hay flujo para que un tenant que ya canceló definitivamente reactive su cuenta |
| Reactivación desde `suspended` | No hay endpoint — requiere intervención manual o esperar a que el cron lo detecte |
| Pantalla de reactivación post-login | Si un tenant cancelado intenta loguearse, ve "Tienda Suspendida" con contacto a soporte — no hay botón "Reactivar" |
| Preservación de datos para reactivación | Después de 30 días de suspensión → soft delete. Después de tombstone → datos irrecuperables |
| Historial de cancelaciones/reactivaciones | `lifecycle_events` registra eventos pero no hay vista dedicada para este historial |
| Super Admin reactivación manual | No hay botón en el dashboard para forzar reactivación de una cuenta cancelada |

### Datos reales

- **0 reactivaciones** ejecutadas (nunca hubo cancelación)
- `nv_billing_events`: sin eventos de tipo cancel/reactivate
- `lifecycle_events`: solo 2 registros (1 aprobación + 1 creación de suscripción de farma)

---

## Dashboard Super Admin

### Lo que existe

**Vista de cancelaciones** (`CancellationsView.jsx`):
- Dashboard dedicado con filtrado por motivo de cancelación
- Métricas: total cancelaciones, clientes que quieren contacto, razones principales
- Sistema de contacto: marcar como "contactado" para follow-up
- Tabla paginada con deuda pendiente y tipo de cancelación

**Vista de detalle de suscripción** (`SubscriptionDetailView.jsx`):
- Botón de cancelación forzada (super admin)
- Modal de confirmación con validación de deuda
- Historial de lifecycle events y billing events
- Info de cupón/descuento aplicado

**Customer 360** (`Customer360View.jsx`):
- Lifecycle stages: `lead → trial → onboarding → onboarding_blocked → active → at_risk → expansion → enterprise → churned`
- Health score con semáforo (verde >70%, amarillo 40-70%, rojo <40%)
- Tags, notas, tareas, timeline de eventos

**CRM Dashboard** (`CrmDashboardView.jsx`):
- Visualización por etapa de ciclo de vida
- Filtrado por health score
- Estadísticas agregadas

**GrowthHQ** (`GrowthHqView.jsx`):
- MRR tracking
- Métricas de crecimiento y churn

### Estado real del CRM

| Tabla | Registros |
|-------|-----------|
| `crm_notes` | **0** |
| `crm_tasks` | **0** |
| `crm_activity_log` | **0** |
| Health scores computados | 5 (auto-calculado, no manual) |
| Lifecycle stages asignados | Defaults automáticos (`lead`, `trial`) |

### Lo que falta

| Gap | Descripción |
|-----|-------------|
| Filtro por subscription_status | La lista de clientes (`ClientsView.jsx`) muestra clientes activos pero no permite filtrar por `canceled`, `suspended`, etc. |
| Métricas de tiempo de vida | No se muestra cuánto tiempo estuvo activo un tenant antes de cancelar |
| Consumo de recursos por tenant cancelado | No se muestra espacio en storage, productos, órdenes de un tenant cancelado |
| Indicadores pre-churn automatizados | El health score existe pero se computa con una fórmula genérica — no hay detección activa de señales (0 órdenes, 0 logins, uso en baja) |
| Botón de reactivación manual | No existe en ninguna vista del super admin |
| Vista de tenants purgados/eliminados | `ClientsView.jsx` tiene historial de eliminados via `client_tombstones`, pero la tabla está vacía |

---

## Sistema de retención y win-back

### Lo que existe

**Infraestructura de outreach** (Admin DB):
- `outreach_leads`: 47,303 leads (casi todos de import masivo, no de churn)
- `outreach_logs`: registro de interacciones
- `outreach_coupons` / `outreach_coupon_offers`: cupones de outreach
- `outreach_config`: configuración
- Pipeline de estados: NEW → CONTACTED → IN_CONVERSATION → QUALIFIED → WON/LOST/COLD

**Outreach UI** (`OutreachView.jsx`):
- Pipeline completo con métricas de conversión
- Scoring de leads
- Re-engagement de leads COLD después de 2-3 semanas

**Cupones configurados** (10 activos):
- `FUNDADORES2026`: 40% Growth primer mes (max 50 usos)
- `WELCOME20`: 20% bienvenida (max 100 usos)
- `FIRST5`: $50 USD para primeros 5 usuarios
- `NVLANZ`: 50% lanzamiento
- `NVTEST`: 100% prueba con 3 meses gratis
- Otros: `STARTER15`, `ARS500OFF`, `MINUS10USD`, `ANNUAL15`, `EXPIRED_TEST`
- **Canjes totales: 0** (excepto NVTEST usado para farma en el onboarding)

**N8N/CRM webhooks configurados**:
- `N8N_CRM_ALERT_WEBHOOK_URL`: webhook para alertas CRM
- WhatsApp Business API configurada (phone ID, token)

### Lo que NO existe

| Gap | Descripción |
|-----|-------------|
| Secuencia de retención post-cancelación | No hay workflow en n8n que se dispare al cancelar |
| Emails de win-back | No hay templates de "te extrañamos" o "volvé con descuento" |
| Cupones específicos para win-back | Los cupones existentes son para onboarding, no para recuperación |
| Detección pre-churn automatizada | No hay trigger por 0 órdenes en 14 días (mencionado en PENDING_LAUNCH_ITEMS pero no implementado) |
| Pausa en lugar de cancelación | No existe opción "pausar suscripción" — solo cancelar o pausar tienda manualmente |
| Downgrade como alternativa | No se ofrece bajar de plan en lugar de cancelar |
| Secuencia de onboarding completeness | No hay seguimiento de si el tenant configuró su tienda completamente |
| Estado CRM para ex-clientes | El stage `churned` existe en la definición pero no hay workflow que lo asigne automáticamente |
| WhatsApp automatizado para retención | La API está configurada pero no hay flujos de retención conectados |

---

## Incentivos para clientes nuevos

### Lo que existe

| Feature | Estado | Detalle |
|---------|--------|---------|
| Cupones de descuento | ✅ Configurados | 10 cupones activos, 0 canjeados |
| Free months via cupón | ✅ Implementado | `promo_config.free_months` soportado (NVTEST tiene 3 meses) |
| Trial via MP | ✅ Parcial | Campo `trial_days` en subscriptions (farma tiene 90 días trial) |
| Cupones en onboarding | ✅ Scoped | `promo_config.scopes: ["onboarding"]` para aplicar en signup |
| Restricción por plan | ✅ Implementado | `allowed_plans` permite limitar cupones a planes específicos |

### Lo que NO existe

| Gap | Descripción |
|-----|-------------|
| Free tier / plan gratis | No hay plan de $0 que permita probar sin pagar |
| Money-back guarantee | No está implementado ni mencionado en ningún lugar |
| Onboarding gamificado | No hay diferenciación en UX para primer mes vs veterano |
| Welcome email sequence | No hay secuencia de emails post-signup para activar al tenant |
| First-purchase celebration | Mencionado en PENDING_LAUNCH_ITEMS.md como pendiente, no implementado |
| Churn detection email (0 órdenes 14d) | Mencionado en PENDING_LAUNCH_ITEMS.md como pendiente, no implementado |

---

## GAPs críticos

1. **Sin testing E2E del flujo de cancelación en producción** — El sistema nunca ha sido ejecutado con datos reales. Existe riesgo de bugs no detectados en la interacción entre cancel → MP → pause → downgrade → cleanup.

2. **Sin reactivación desde estado `canceled`** — Un tenant que canceló definitivamente no tiene camino de vuelta. Debe crear una cuenta nueva, perdiendo todo su historial.

3. **Sin limpieza de storage (Supabase buckets)** — El lifecycle-cleanup borra datos de BD pero no los assets (imágenes de productos, logos, banners) almacenados en Supabase Storage. Con escala, esto genera costo innecesario.

4. **Sin secuencia de retención automatizada** — Cuando un tenant cancela, el único touchpoint es un email de confirmación. No hay follow-up, oferta de descuento, ni intento de recuperación.

5. **Sin detección pre-churn** — El health score existe como estructura pero no hay workflows que lo utilicen para disparar alertas o intervenciones antes de que el tenant cancele.

6. **Sin opción de pausa o downgrade como alternativa** — El tenant solo puede cancelar o seguir pagando lo mismo. No hay escape valve (pausar 1 mes, bajar de plan) que reduzca la fricción.

7. **CRM completamente vacío** — Las tablas y UI de Customer360, notas, tareas y timeline existen pero tienen 0 datos operativos. El sistema no está siendo usado.

8. **Sin exit survey en UI** — El motivo de cancelación se captura vía API pero no hay formulario/modal amigable en el dashboard del tenant.

9. **Grace period no diferenciado por plan** — El código usa un valor fijo (`GRACE_PERIOD_DAYS=7`) para todos los planes, contradiciendo la documentación que propone 14d para Growth y 30d para Enterprise.

10. **Outreach desconectado del churn** — El sistema de outreach tiene 47K leads pero no incluye ex-clientes ni tiene workflows de win-back conectados a eventos de cancelación.

11. **Sin tabla `subscription_cancel_log`** — El código referencia esta tabla para idempotencia de cancelaciones pero no existe en la BD.

12. **Sin compliance Disposición 954 probado** — La tabla `compliance_events` existe pero tiene 0 registros. El botón de baja existe en `BillingPage.tsx` pero nunca fue usado.

---

## Score de madurez — Churn Management

| Área | Implementado | Funcional | Automatizado | Score |
|------|:---:|:---:|:---:|:---:|
| Flujo de cancelación | ✅ | ⚠️ Sin test prod | ❌ | 4/10 |
| Cancelación en MercadoPago | ✅ | ⚠️ Sin test prod | ✅ | 6/10 |
| Grace period | ✅ | ✅ Cron activo | ⚠️ No diferenciado | 5/10 |
| Pause de tienda | ✅ | ✅ | ✅ | 8/10 |
| Downgrade de entitlements | ✅ | ⚠️ Sin test prod | ✅ | 6/10 |
| Audit trail (lifecycle_events) | ✅ | ✅ | ✅ | 8/10 |
| Notificación al super admin | ✅ | ⚠️ Sin test prod | ✅ | 6/10 |
| Email al tenant | ✅ | ⚠️ Sin test prod | ✅ | 6/10 |
| Exit survey / motivo de baja | ✅ API | ❌ Sin UI | ❌ | 3/10 |
| Reactivación (revert cancel) | ✅ | ⚠️ Solo cancel_scheduled | ❌ | 3/10 |
| Reactivación desde canceled | ❌ | ❌ | ❌ | 0/10 |
| Purga de datos (BD) | ✅ | ✅ Cron activo | ✅ | 7/10 |
| Purga de storage | ❌ | ❌ | ❌ | 0/10 |
| Dashboard Super Admin churn | ✅ UI | ⚠️ Sin datos | ❌ | 3/10 |
| Customer 360 / CRM | ✅ UI + tablas | ❌ 0 registros | ❌ | 2/10 |
| Health score / pre-churn | ✅ Estructura | ⚠️ Fórmula genérica | ❌ | 2/10 |
| Retención post-cancelación | ❌ | ❌ | ❌ | 0/10 |
| Win-back automatizado | ❌ | ❌ | ❌ | 0/10 |
| Cupones de retención | ❌ Específicos | ✅ Sistema de cupones | ❌ | 2/10 |
| Pausa como alternativa | ❌ | ❌ | ❌ | 0/10 |
| Free tier / trial | ⚠️ Trial via MP | ⚠️ Solo con cupón | ❌ | 2/10 |
| Onboarding activation | ❌ | ❌ | ❌ | 0/10 |
| **Score global** | | | | **3.2/10** |

---

## Anexo: Datos crudos de BD consultados

### Admin DB (`nv-admin-db`)

```
nv_accounts (5 registros):
- farma: active, growth, health_score=55, lifecycle=lead
- e2e-alpha: NULL status, starter, health_score=31, lifecycle=lead
- e2e-beta: NULL status, growth, health_score=31, lifecycle=lead
- draft-*: NULL status, starter, health_score=15, lifecycle=trial (x2)

subscriptions (1 registro):
- farma: active, growth, period_end=2026-03-28, trial_days=90, coupon=NVTEST

lifecycle_events (2 registros):
- client_approved (farma, 2026-02-26)
- subscription_created (farma, 2026-02-26)

Tablas vacías: nv_cancellation_requests, cancellation_debt_log,
  client_tombstones, compliance_events, subscription_events,
  crm_notes, crm_tasks, crm_activity_log, coupon_redemptions
```

### Backend DB (`nv-backend-db`)

```
clients (3 registros): farma, e2e-alpha, e2e-beta — todos activos
products: 58 (38 farma + 10+10 e2e)
orders: 8 (todas farma)
users: 5
banners: 14, faqs: 12, categories: 29
tenant_media: 0, cart_items: 3
```
