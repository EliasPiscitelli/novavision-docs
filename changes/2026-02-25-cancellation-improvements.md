# Mejoras al flujo de cancelación de suscripciones

- **Autor:** agente-copilot
- **Fecha:** 2026-02-25
- **Rama API:** feature/automatic-multiclient-onboarding
- **Rama Admin:** feature/automatic-multiclient-onboarding
- **Rama Web:** develop

---

## Resumen

Se implementaron 4 mejoras al flujo de cancelación de suscripciones para mejorar la retención, trazabilidad y gestión proactiva de churn:

1. **Motivo obligatorio** — Backend y frontend validan que el motivo no sea vacío.
2. **Email al super admin** — Notificación inmediata con datos del tenant, motivo y flag de contacto.
3. **Email de confirmación al tenant** — Confirmación con fechas, tipo de cancelación y cómo revertir.
4. **Dashboard dedicado de cancelaciones** — Vista en admin con filtros, stats y gestión de contacto.

---

## Archivos modificados

### API (templatetwobe)

| Archivo | Cambio |
|---------|--------|
| `src/subscriptions/subscriptions.service.ts` | Validación `reason` obligatorio + invocación 2 emails post-cancelación |
| `src/onboarding/onboarding-notification.service.ts` | 2 nuevos métodos: `sendCancellationSuperAdminNotification()` + `sendCancellationConfirmationEmail()` |
| `src/admin/admin.controller.ts` | 2 nuevos endpoints: `GET /admin/cancellations` + `PATCH /admin/cancellations/:accountId/contacted` |
| `src/admin/admin.service.ts` | 2 nuevos métodos: `getCancellations()` + `markCancellationContacted()` |

### Admin (novavision)

| Archivo | Cambio |
|---------|--------|
| `src/pages/AdminDashboard/CancellationsView.jsx` | **NUEVO** — Dashboard dedicado cancelaciones/churn |
| `src/App.jsx` | Import + ruta `/cancellations` |
| `src/pages/AdminDashboard/index.jsx` | Nav link + import `FaTimesCircle` |

### Web (templatetwo)

| Archivo | Cambio |
|---------|--------|
| `src/components/admin/SubscriptionManagement/SubscriptionManagement.jsx` | Validación frontend motivo obligatorio (step 1→2) |

---

## Detalle por mejora

### Mejora 1: Motivo obligatorio

**Backend:** Al inicio de `requestCancel()`, si `cancelDto.reason` está vacío o solo whitespace, se lanza `BadRequestException('El motivo de cancelación es obligatorio...')`.

**Frontend:** En el modal de cancelación (step 1), el botón "Continuar" valida que `cancelReason` esté seleccionado. Si no, muestra error inline "Seleccioná un motivo de cancelación para continuar." y no avanza al step 2. Texto actualizado a "(obligatorio)".

### Mejora 2: Email al super admin

**Nuevo método:** `sendCancellationSuperAdminNotification()` en `OnboardingNotificationService`.

- **Destinatario:** `ADMIN_NOTIFICATION_EMAIL` (env var)
- **Subject:** `🚨 Cancelación: {storeName} ({slug}) — {reasonLabel}` + flag `QUIERE SER CONTACTADO` si aplica
- **Contenido:** HTML con header rojo degradado, datos del cliente (tienda, plan, email), motivo con detalle libre, alert box si quiere contacto, CTA al dashboard
- **Tipo email_jobs:** `subscription_cancel_superadmin`
- **Invocación:** Después del persist de idempotencia en `requestCancel()`, envuelto en try/catch (no bloquea el flujo)

### Mejora 3: Email confirmación al tenant

**Nuevo método:** `sendCancellationConfirmationEmail()` en `OnboardingNotificationService`.

- **Destinatario:** Email del tenant (admin de la tienda)
- **Template:** Usa `renderLifecycleEmail()` (template lifecycle existente)
- **Contenido diferenciado:**
  - *Cancelación programada:* "Tu tienda seguirá activa hasta {fecha}. Podés revertir desde el panel."
  - *Cancelación inmediata:* "Tu tienda fue desactivada. Si cambias de opinión, contactanos."
- **Tipo email_jobs:** `subscription_cancel_confirmation`
- **Invocación:** Después del email al super admin, envuelto en try/catch

### Mejora 4: Dashboard de cancelaciones

**Backend (2 endpoints):**

1. `GET /admin/cancellations` — Query params: page, pageSize, reason, wants_contact, date_from, date_to, country, search
   - Consulta `lifecycle_events` con `event_type = 'subscription_cancel_requested'`
   - Join `nv_accounts!inner(slug, business_name, email, plan_key, country)`
   - Filtros server-side: reason, wants_contact, date range, country
   - Filtro client-side: search por slug/business_name/email
   - Stats: total, wants_contact, by_reason breakdown
   
2. `PATCH /admin/cancellations/:accountId/contacted` — Marca la última cancelación como contactada (metadata.contacted_at + nota)

**Frontend (CancellationsView.jsx):**
- Stats cards: total cancelaciones, quieren contacto, top motivos
- Filtros: búsqueda texto, motivo, contacto, rango fechas
- Tabla: fecha, tienda (nombre+slug+email), plan, motivo (badge color), detalle, contacto (badge estado), tipo cancelación, acción
- Botón "✓ Contactado" que llama al PATCH
- Paginación consistente con el resto del admin
- Dark theme matching SubscriptionEventsView

---

## Cómo probar

### Motivo obligatorio
1. Ir a Gestión de Suscripción en la web storefront
2. Intentar cancelar sin seleccionar motivo → error inline
3. Seleccionar motivo, avanzar → funciona

### Emails
1. Cancelar una suscripción (test con tienda de prueba)
2. Verificar en `email_jobs`:
   - Fila con `type = 'subscription_cancel_superadmin'` → destinatario: ADMIN_NOTIFICATION_EMAIL
   - Fila con `type = 'subscription_cancel_confirmation'` → destinatario: email del tenant

### Dashboard
1. Login como super admin en admin
2. Navegar a "Cancelaciones / Churn" en el menú lateral (categoría Operations)
3. Verificar que carga cancelaciones existentes (lifecycle_events de tipo subscription_cancel_requested)
4. Probar filtros por motivo, contacto, fechas
5. Probar "✓ Contactado" → verifica que el badge cambie a "Contactado"

---

## Notas de seguridad

- Endpoints de cancelaciones protegidos con `SuperAdminGuard`
- Emails no bloquean el flujo de cancelación (try/catch)
- `markCancellationContacted` solo modifica metadata, no cambia estado de suscripción
- Validación de reason server-side + client-side (defensa en profundidad)

---

## Riesgos

- **Bajo:** Si `ADMIN_NOTIFICATION_EMAIL` no está configurado, el email al super admin falla silenciosamente (ya logueado)
- **Bajo:** El search en `getCancellations` es client-side (post-fetch) — suficiente para volúmenes actuales, si escala habría que mover a server-side
