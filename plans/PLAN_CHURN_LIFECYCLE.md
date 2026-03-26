# Plan: Churn y Lifecycle Post-Cancelación — NovaVision

**Fecha**: 2026-03-25
**Base**: Auditoría `audits/churn-lifecycle-audit-2026-03-25.md`
**Ejes**: Infraestructura y datos · Producto y software · Marketing y retención

---

## Contexto

NovaVision tiene 1 suscripción activa y 0 cancelaciones históricas. El sistema de cancelación está codificado a alto nivel pero nunca probado en producción. El CRM existe como estructura vacía. No hay automatizaciones de retención. Este plan prioriza lo que debe estar listo **antes de tener más clientes**, porque corregir después es exponencialmente más caro.

---

## Fase 1 — Fundamentos críticos (pre-escala)

> Prioridad: **P0 — Debe estar listo antes de onboardear más clientes**

### 1.1 Test E2E del flujo completo de cancelación

**Problema del audit**: GAP #1 — El sistema nunca fue probado end-to-end en producción.

**Acciones**:
- Crear test E2E en `novavision-e2e/` que cubra: cancel_scheduled → period_end → canceled → pause → downgrade → cleanup
- Usar cuenta e2e-beta para simular cancelación completa en entorno de desarrollo
- Verificar: MP cancellation, store pause, entitlement downgrade, lifecycle events, emails
- Verificar: grace period expiration cron, tombstone save, slug release

**Impacto**: Elimina el riesgo de que la primera cancelación real falle.
**Esfuerzo**: 2-3 días (test-teammate)

### 1.2 Crear tabla `subscription_cancel_log`

**Problema del audit**: GAP #11 — El código referencia la tabla para idempotencia pero no existe.

**Acciones**:
- Crear migración en Admin DB:
  ```sql
  CREATE TABLE subscription_cancel_log (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id uuid NOT NULL REFERENCES nv_accounts(id),
    subscription_id uuid NOT NULL REFERENCES subscriptions(id),
    idempotency_key text UNIQUE,
    reason text NOT NULL,
    reason_text text,
    wants_contact boolean DEFAULT false,
    cancel_type text NOT NULL, -- 'scheduled' | 'immediate'
    effective_end_at timestamptz,
    data_retention_until timestamptz,
    response_snapshot jsonb,
    created_at timestamptz DEFAULT now()
  );
  ```

**Impacto**: Previene doble-cancelación y mantiene historial detallado.
**Esfuerzo**: 0.5 días (api-teammate)

### 1.3 Grace period diferenciado por plan

**Problema del audit**: GAP #9 — Valor fijo de 7 días para todos los planes.

**Acciones**:
- Agregar columna `grace_period_days` a `plan_definitions` en Admin DB (o usar `plan_catalog`)
- Valores: Starter=7, Growth=14, Enterprise=30
- Modificar `subscriptions.service.ts` para leer el grace period del plan en lugar de la env var
- Mantener env var como fallback default

**Impacto**: Los planes premium tienen más tiempo para resolver problemas de pago, reduciendo cancelaciones involuntarias.
**Esfuerzo**: 1 día (api-teammate)

### 1.4 Exit survey en UI del tenant

**Problema del audit**: GAP #8 — El motivo se captura por API pero no hay formulario amigable.

**Acciones**:
- Crear modal `CancelSurveyModal` en Admin dashboard (`BillingPage.tsx`)
- Campos: motivo (radio buttons), texto libre, checkbox "quiero que me contacten"
- Mostrar alternativas antes de confirmar: "¿Querés pausar tu tienda?" / "¿Querés cambiar de plan?"
- Enviar datos al endpoint existente `POST /subscriptions/client/manage/cancel`

**Impacto**: Captura datos cualitativos para entender por qué cancelan + ofrece alternativas que pueden evitar la baja.
**Esfuerzo**: 1-2 días (admin-teammate)

---

## Fase 2 — Producto y software (retención activa)

> Prioridad: **P1 — Implementar en las primeras semanas post-lanzamiento**

### 2.1 Reactivación desde estado `canceled`

**Problema del audit**: GAP #2 — Un tenant cancelado no puede volver sin crear cuenta nueva.

**Acciones**:
- Nuevo endpoint: `POST /subscriptions/manage/reactivate`
  - Verificar que la cuenta existe y no fue purgada
  - Crear nueva suscripción en MP (nuevo preapproval)
  - Restaurar entitlements del plan seleccionado
  - Unpause store si los datos aún existen
  - Emitir evento `subscription_reactivated`
- Nuevo endpoint super admin: `POST /subscriptions/admin/reactivate/:accountId`
- Pantalla post-login para tenant cancelado: "Tu cuenta está cancelada. Tus datos están disponibles hasta [purge_at]. ¿Querés reactivar?"
- Pantalla en Admin dashboard con planes disponibles y cupón de win-back aplicable

**Impacto**: Permite recuperar clientes que se fueron, preservando su historial y reduciendo fricción de retorno.
**Esfuerzo**: 3-4 días (api-teammate + admin-teammate)

### 2.2 Pausa de suscripción como alternativa a cancelación

**Problema del audit**: GAP #6 — Solo se puede cancelar o seguir pagando.

**Acciones**:
- Nuevo estado: `paused` en subscriptions
- Lógica: pausar por 1-3 meses, tienda queda offline pero datos se conservan
- En MP: pausar preapproval (no cancelar)
- Al vencer la pausa: reactivar automáticamente o cancelar si no hay pago
- Máximo 2 pausas por año por cuenta
- Mostrar opción "Pausar" en el exit survey modal (Fase 1.4)

**Impacto**: Ofrece escape valve para tenants con problemas temporales (baja estacional, vacaciones, problemas financieros). Reduce cancelaciones definitivas.
**Esfuerzo**: 3 días (api-teammate + admin-teammate)

### 2.3 Downgrade como alternativa a cancelación

**Problema del audit**: No se ofrece cambio de plan como alternativa.

**Acciones**:
- En el exit survey modal, si el motivo es `too_expensive`, ofrecer downgrade a plan inferior
- Si el tenant está en Growth, ofrecer Starter con botón directo
- Usar el endpoint existente de upgrade (adaptarlo para downgrade)
- Ajustar entitlements y precio en MP

**Impacto**: Retiene clientes que solo tienen problema de precio, manteniendo MRR reducido en lugar de $0.
**Esfuerzo**: 2 días (api-teammate + admin-teammate)

### 2.4 Dashboard Super Admin — Gestión de churn mejorada

**Problema del audit**: GAPs #5, #6 del dashboard.

**Acciones**:
- Agregar filtro por `subscription_status` en `ClientsView.jsx`
- Mostrar métricas en `CancellationsView.jsx`: tiempo promedio de vida, motivo más frecuente, MRR perdido
- Agregar botón "Reactivar" en `SubscriptionDetailView.jsx` para super admin
- Mostrar datos de consumo (productos, órdenes, storage) por tenant en Customer360
- Agregar indicador "Días desde última orden" y "Días sin login" en la lista de clientes

**Impacto**: El operador de NovaVision puede tomar decisiones informadas sobre retención y gestionar cuentas problemáticas.
**Esfuerzo**: 2-3 días (admin-teammate)

### 2.5 Limpieza de storage para tenants eliminados

**Problema del audit**: GAP #3 — Los assets en Supabase Storage no se borran.

**Acciones**:
- Extender `lifecycle-cleanup.cron.ts` para incluir paso de cleanup de storage
- Antes del hard-delete de datos, listar y borrar objetos en Supabase Storage del bucket del tenant
- Patterns a borrar: `{clientId}/*` en buckets de productos, logos, banners
- Agregar log de bytes liberados para tracking de ahorro

**Impacto**: Evita acumulación de costo de storage por datos muertos. Crítico conforme escale la plataforma.
**Esfuerzo**: 1-2 días (api-teammate)

---

## Fase 3 — Marketing y retención (automatización)

> Prioridad: **P1-P2 — Implementar progresivamente conforme haya clientes**

### 3.1 Secuencia de retención post-cancelación

**Problema del audit**: GAP #4 — El único touchpoint es un email de confirmación.

**Acciones**:
- Workflow en n8n disparado por webhook `account.suspended` / lifecycle event `subscription_cancel_requested`:
  - **Día 0**: Email de confirmación con "¿Estás seguro?" + link a reactivar (ya existe, mejorar copy)
  - **Día 3**: Email con "¿Qué podemos mejorar?" + link a feedback form
  - **Día 7**: Email con cupón de win-back (ej: 30% off por 2 meses) + CTA "Volvé ahora"
  - **Día 14**: WhatsApp personal del founder si `wants_contact=true`
  - **Día 30**: Último email: "Tus datos se eliminarán en 30 días. Reactivá para conservarlos."
- Crear templates de email en Postmark para cada paso
- Conectar con `outreach_leads` creando lead tipo `churned_customer` al cancelar

**Impacto**: Cada touchpoint es una oportunidad de recuperar al cliente. Las mejores SaaS recuperan 5-15% de churned customers con secuencias de win-back.
**Esfuerzo**: 3-4 días (api-teammate + docs-teammate para templates)

### 3.2 Detección pre-churn automatizada

**Problema del audit**: GAP #5 — El health score existe pero no genera acciones.

**Acciones**:
- Cron semanal que computa health score con factores concretos:
  - Días desde última orden (peso 30%)
  - Días desde último login admin (peso 25%)
  - Productos activos / límite del plan (peso 15%)
  - Tendencia de órdenes (últimos 30d vs 30d anteriores) (peso 20%)
  - Uso de features premium (peso 10%)
- Si health_score < 30 → asignar `lifecycle_stage='at_risk'` + crear crm_task automática
- Si health_score < 30 por 2 semanas consecutivas → enviar email proactivo: "¿Necesitás ayuda con tu tienda?"
- Si 0 órdenes en 14 días → alerta CRM + email motivacional (pendiente de PENDING_LAUNCH_ITEMS)

**Impacto**: Detectar churn antes de que suceda permite intervenir cuando el cliente aún está activo.
**Esfuerzo**: 2-3 días (api-teammate)

### 3.3 Cupones de win-back dedicados

**Problema del audit**: Los cupones existentes son de onboarding, no de recuperación.

**Acciones**:
- Crear cupones con `scope: 'win_back'`:
  - `COMEBACK30`: 30% off por 2 meses, solo para cuentas con `subscription_status IN ('canceled', 'suspended')`
  - `COMEBACK50`: 50% off primer mes de vuelta, máximo 1 uso por cuenta
  - `FREERETURN`: 1 mes gratis para enterprise, máximo 10 usos
- Agregar validación en backend: cupones win_back solo aplicables a cuentas con historial de cancelación
- Conectar con la secuencia de retención (Fase 3.1) — el email del día 7 incluye el cupón

**Impacto**: El incentivo económico es el factor más efectivo para recuperar ex-clientes que cancelaron por precio.
**Esfuerzo**: 1 día (api-teammate)

### 3.4 Lifecycle stage automático `churned`

**Problema del audit**: El stage existe en la definición pero no se asigna automáticamente.

**Acciones**:
- En el flujo de cancelación, agregar: `UPDATE nv_accounts SET lifecycle_stage='churned' WHERE id=:accountId`
- En reactivación: restaurar a `active`
- En la secuencia de win-back: si el lead responde → mover a `at_risk` (en proceso de recuperación)
- Agregar filtro `churned` en CRM dashboard

**Impacto**: Visibilidad inmediata del funnel de churn en el CRM existente.
**Esfuerzo**: 0.5 días (api-teammate)

### 3.5 Activación de onboarding (primeros 7 días)

**Problema del audit**: No hay diferenciación en experiencia de primer mes vs veterano.

**Acciones**:
- Checklist de activación post-signup:
  1. Configurar logo y paleta ✓/✗
  2. Subir al menos 5 productos ✓/✗
  3. Configurar MercadoPago ✓/✗
  4. Recibir primera orden ✓/✗
  5. Configurar dominio personalizado ✓/✗
- Mostrar progreso en header del admin dashboard durante los primeros 30 días
- Email automático día 3 si completeness < 50%: "Tu tienda está al X% — completá estos pasos"
- Email celebratorio en primera orden (PENDING_LAUNCH_ITEMS)

**Impacto**: Tenants que completan el onboarding en la primera semana tienen 3x más retención que los que no.
**Esfuerzo**: 3 días (api-teammate + admin-teammate + web-teammate)

---

## Fase 4 — Optimización continua

> Prioridad: **P2-P3 — Implementar cuando haya datos de churn reales**

### 4.1 Archivado frío de datos

**Acciones**:
- Después de tombstone, comprimir snapshot y mover a bucket de archivo en Supabase Storage (tier económico)
- Retener archivos por 1 año para compliance, luego borrar definitivamente
- Dashboard de costos: mostrar ahorro mensual por archivado vs retención activa

**Impacto**: Reduce costo de storage manteniendo acceso a datos históricos para compliance.
**Esfuerzo**: 2 días

### 4.2 Money-back guarantee (primeros 30 días)

**Acciones**:
- Endpoint de refund que llama a MP para reembolso
- Solo aplicable en los primeros 30 días de suscripción
- Requiere motivo y confirmación
- Emitir billing event de tipo `refund`

**Impacto**: Reduce la barrera de entrada para nuevos clientes. "Si no te sirve, te devolvemos la plata."
**Esfuerzo**: 2-3 días

### 4.3 Free tier funcional

**Acciones**:
- Plan `free` con límites mínimos: 10 productos, 0 custom domain, watermark NovaVision
- Sin cobro en MP — suscripción sin preapproval
- Upgrade directo a cualquier plan pagado
- Objetivo: que el tenant pruebe antes de pagar

**Impacto**: Reduce churn del tipo "cancelé porque no me convenció" — pueden seguir gratis y convertir después.
**Esfuerzo**: 3-5 días

### 4.4 Analytics de churn

**Acciones**:
- Dashboard en GrowthHQ con:
  - Churn rate mensual (% de suscripciones canceladas / total activas)
  - MRR perdido por churn
  - Distribución de motivos de cancelación
  - Tiempo promedio de vida por plan
  - Win-back rate (% de cancelados que reactivaron)
  - Cohortes: retención por mes de onboarding

**Impacto**: Datos para tomar decisiones informadas sobre pricing, features y retención.
**Esfuerzo**: 2-3 días

---

## Resumen de priorización

| # | Mejora | Fase | GAPs que resuelve | Impacto principal | Esfuerzo |
|---|--------|------|-------------------|-------------------|----------|
| 1.1 | Test E2E de cancelación | F1 | #1 | Confiabilidad | 2-3d |
| 1.2 | Tabla subscription_cancel_log | F1 | #11 | Idempotencia | 0.5d |
| 1.3 | Grace period por plan | F1 | #9 | Retención involuntaria | 1d |
| 1.4 | Exit survey en UI | F1 | #8 | Datos cualitativos + alternativas | 1-2d |
| 2.1 | Reactivación desde canceled | F2 | #2 | Recuperación de clientes | 3-4d |
| 2.2 | Pausa de suscripción | F2 | #6 | Reducción de churn | 3d |
| 2.3 | Downgrade como alternativa | F2 | #6 | Retención de MRR | 2d |
| 2.4 | Dashboard churn mejorado | F2 | #5, #6 dashboard | Visibilidad operativa | 2-3d |
| 2.5 | Limpieza de storage | F2 | #3 | Reducción de costos | 1-2d |
| 3.1 | Secuencia retención post-cancel | F3 | #4 | Win-back 5-15% | 3-4d |
| 3.2 | Detección pre-churn | F3 | #5 | Intervención proactiva | 2-3d |
| 3.3 | Cupones win-back | F3 | #10 | Incentivo económico | 1d |
| 3.4 | Lifecycle stage churned | F3 | #7, #10 | Visibilidad CRM | 0.5d |
| 3.5 | Activación de onboarding | F3 | Retención temprana | 3x retención | 3d |
| 4.1 | Archivado frío | F4 | #3 | Costo storage | 2d |
| 4.2 | Money-back guarantee | F4 | Conversión | Barrera de entrada | 2-3d |
| 4.3 | Free tier | F4 | Conversión | Funnel de prueba | 3-5d |
| 4.4 | Analytics de churn | F4 | Todos | Decisiones informadas | 2-3d |

**Esfuerzo total estimado**: ~35-45 días de desarrollo distribuidos entre teammates.

---

## Dependencias entre mejoras

```
Fase 1 (fundamentos):
  1.2 subscription_cancel_log ──→ 1.1 Test E2E
  1.4 Exit survey ──→ 2.2 Pausa (opción en survey)
                  ──→ 2.3 Downgrade (opción en survey)

Fase 2 (producto):
  2.1 Reactivación ──→ 3.1 Secuencia retención (link a reactivar en emails)
  2.1 Reactivación ──→ 3.3 Cupones win-back (aplicar en reactivación)

Fase 3 (marketing):
  3.1 Secuencia retención ──→ 3.3 Cupones win-back (incluir en secuencia)
  3.2 Detección pre-churn ──→ 3.4 Lifecycle churned (usar stages)

Independientes:
  1.3 Grace period por plan (sin dependencias)
  2.4 Dashboard churn (sin dependencias)
  2.5 Limpieza storage (sin dependencias)
  3.5 Activación onboarding (sin dependencias)
```

---

## Métricas de éxito

| Métrica | Baseline actual | Objetivo post-implementación |
|---------|----------------|------------------------------|
| Churn rate mensual | N/A (0 clientes suficientes) | < 5% |
| Win-back rate | 0% | > 10% |
| Exit survey completion | 0% | > 80% |
| Tiempo medio de vida | N/A | > 6 meses |
| Onboarding completeness (7d) | No medido | > 70% |
| Health score promedio | 55 (único cliente) | > 65 |
| Storage de cuentas muertas | 0 bytes | < 5% del total |
| Reactivaciones exitosas | 0 | > 15% de cancelados |
