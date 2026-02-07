# Runbook: Tienda Pausada Incorrectamente (Emergency Unpause)

> Creado: 2026-02-07 | Fase 1.5.1 del LIFECYCLE_FIX_PLAN
> Autor: agente-copilot
> Tiempo estimado de resolución: 5-10 minutos

---

## Sintoma

El cliente reporta que su tienda "no está visible" o "no carga", pero su suscripción está activa en Mercado Pago.

**Posibles causas:**
1. El webhook de MP con status `authorized`/`active` no llegó o falló silenciosamente
2. `unpauseStoreIfReactivated()` no se ejecutó o falló
3. El cron de reconciliación no está corriendo
4. Race condition: admin pausó manualmente mientras el webhook intentaba despausar

---

## Paso 1: Verificar estado en Admin DB

Ejecutar contra la Admin DB (Supabase `erbfzlsznqsmwmjugspo`):

```sql
SELECT
  id,
  slug,
  email,
  status,
  subscription_status,
  store_paused,
  store_paused_at,
  store_pause_reason,
  store_resumed_at,
  backend_cluster_id,
  backend_client_id
FROM nv_accounts
WHERE slug = '<SLUG_DE_LA_TIENDA>';
```

**Interpretar:**
- `subscription_status = 'active'` + `store_paused = true` = **BUG CONFIRMADO** (la tienda debería estar visible)
- `subscription_status != 'active'` = el problema es la suscripción, no el unpause
- `store_pause_reason` que NO empiece con `subscription_` = pausa manual de admin (NO es bug)

---

## Paso 2: Verificar estado en Multicliente DB

Ejecutar contra la Multicliente DB (Supabase `ulndkhijxtxvpmbbfrgp`):

```sql
SELECT
  id,
  name,
  slug,
  publication_status,
  paused_reason,
  paused_at,
  is_active,
  nv_account_id
FROM clients
WHERE slug = '<SLUG_DE_LA_TIENDA>';
```

**Interpretar:**
- `publication_status = 'paused'` + `paused_reason LIKE 'subscription_%'` = pausa por subscription que no se revirtió
- `publication_status = 'published'` = la tienda ya está publicada, el problema es otro (DNS, Netlify, etc.)
- `is_active = false` = la tienda fue desactivada, no es lo mismo que pausada

---

## Paso 3: Fix manual (si se confirma el bug)

**Solo ejecutar si Paso 1 muestra `subscription_status = 'active'` Y Paso 2 muestra `publication_status = 'paused'` con `paused_reason LIKE 'subscription_%'`.**

### 3a. Despausar en Multicliente DB

```sql
UPDATE clients
SET
  publication_status = 'published',
  paused_reason = NULL,
  paused_at = NULL
WHERE slug = '<SLUG_DE_LA_TIENDA>'
  AND publication_status = 'paused'
  AND paused_reason LIKE 'subscription_%';
```

### 3b. Limpiar metadata de pausa en Admin DB

```sql
UPDATE nv_accounts
SET
  store_paused = false,
  store_resumed_at = now(),
  store_pause_reason = NULL
WHERE slug = '<SLUG_DE_LA_TIENDA>'
  AND store_paused = true;
```

---

## Paso 4: Verificar que la tienda vuelve a cargar

1. Acceder a la URL de la tienda como usuario final
2. Verificar que carga productos y se ve el home
3. Si no carga: verificar DNS / Netlify / estado del deploy

---

## Paso 5: Post-mortem (documentar)

Responder estas preguntas en un comment del ticket o issue:

1. **Por qué no se disparó `unpauseStoreIfReactivated()`?**
   - Revisar logs de Railway buscando: `[Subscription] Store unpause for account`
   - Si no hay log: el webhook de MP con status `active`/`authorized` no llegó o no procesó

2. **El cron de reconciliación corrió?**
   - Buscar en Railway logs: `[Cron]` o `reconcil` en las últimas 24h
   - Si no hay logs de cron: el cron podría no estar ejecutándose (ver Fase 1.5.2)

3. **Hay error en el health check?**
   - Buscar en Railway logs: `HEALTH-CHECK: Failed to unpause`
   - Si hay: el UPDATE falló por algún motivo (constraint, permisos, dato corrupto)

---

## Notas de seguridad

- Este runbook solo debe ejecutarlo un **super_admin** con acceso a ambas DBs
- NO despausar si `paused_reason` no comienza con `subscription_` (podría ser pausa intencional)
- Registrar quién ejecutó el fix manual y cuándo
- Después del fix, verificar que el cron de reconciliación esté activo para prevenir recurrencia

---

## Queries útiles adicionales

### Ver todas las tiendas pausadas por razón de subscription

```sql
-- Admin DB
SELECT slug, email, subscription_status, store_paused, store_pause_reason, store_paused_at
FROM nv_accounts
WHERE store_paused = true
  AND store_pause_reason LIKE 'subscription_%'
ORDER BY store_paused_at DESC;
```

### Ver tiendas con desync (sub activa pero store pausada)

```sql
-- Admin DB
SELECT slug, email, subscription_status, store_paused, store_pause_reason
FROM nv_accounts
WHERE subscription_status = 'active'
  AND store_paused = true;
```

### Ver últimos webhooks procesados (si existe la tabla de logs)

```sql
-- Buscar en logs de Railway:
-- grep "[SubAction]" | grep "webhook" | tail -20
```
