# Runbook: Incidentes SEO AI

> Última actualización: 2025-07-15

## Clasificación de severidad

| Sev | Descripción | Ejemplo | SLA |
|-----|-------------|---------|-----|
| P1 | Pérdida de datos / exposición de credenciales | API key leakeada | Inmediato |
| P2 | Feature completamente caída | Worker no procesa jobs | 4h |
| P3 | Degradación parcial | Timeout de OpenAI intermitente | 24h |
| P4 | Cosmético / no-impacto | Score de audit impreciso | Sprint siguiente |

---

## Escenario 1: Worker no procesa jobs (P2)

### Síntomas
- Jobs quedan en `pending` indefinidamente
- Dashboard muestra "Procesando…" sin avanzar
- No hay errores en logs del worker

### Diagnóstico

```sql
-- Jobs pendientes
SELECT id, client_id, job_type, status, created_at
FROM seo_ai_jobs
WHERE status IN ('pending', 'processing')
ORDER BY created_at;
```

```bash
# Logs del worker en Railway
railway logs --filter "SeoAiWorker"
```

### Acciones

1. **Verificar que el worker está corriendo:**
   - Confirmar que la API está levantada (health check OK)
   - El worker usa `@Interval(10000)` — se ejecuta automáticamente si NestJS está vivo

2. **Verificar OpenAI:**
   ```bash
   curl https://api.openai.com/v1/models \
     -H "Authorization: Bearer $OPENAI_API_KEY" | head -5
   ```

3. **Verificar flag `processing`:**
   - Si el server crasheó con flag en true, el worker no tomará nuevos jobs
   - **Fix:** restart del servicio en Railway

4. **Job atascado en `processing`:**
   ```sql
   -- Forzar fail del job atascado (> 30 min sin progreso)
   UPDATE seo_ai_jobs
   SET status = 'failed',
       error = 'Timeout manual - runbook Step 4'
   WHERE status = 'processing'
     AND updated_at < NOW() - INTERVAL '30 minutes';
   ```

### Prevención
- Considerar agregar auto-timeout al worker (ticket futuro)
- Monitorear con alertas de Railway por error rate

---

## Escenario 2: OpenAI devuelve errores 429 (Rate Limit) (P3)

### Síntomas
- Jobs fallan con error "429 Too Many Requests"
- Log muestra retries exhaustos

### Diagnóstico

```sql
SELECT id, error, updated_at
FROM seo_ai_jobs
WHERE status = 'failed'
  AND error LIKE '%429%'
ORDER BY updated_at DESC
LIMIT 10;
```

### Acciones

1. **Esperar:** Los rate limits de OpenAI se resetean por minuto
2. **Verificar tier de API:**
   - Free tier: 3 RPM, 200 RPD
   - Tier 1+: 500 RPM, 10K RPD
3. **Ajustar chunk size si necesario:**
   - En `seo-ai-worker.service.ts`: reducir `CHUNK_SIZE`
   - Agregar delay entre chunks
4. **Re-lanzar jobs fallidos:**
   ```sql
   UPDATE seo_ai_jobs
   SET status = 'pending', error = NULL
   WHERE status = 'failed'
     AND error LIKE '%429%'
     AND created_at > NOW() - INTERVAL '24 hours';
   ```

---

## Escenario 3: Webhook de compra no llega / doble procesamiento (P2)

### Síntomas
- Cliente pagó pero no recibió créditos
- O recibió créditos duplicados

### Diagnóstico

```sql
-- Verificar pagos del tenant
SELECT * FROM seo_ai_purchases
WHERE account_id = '<ACCOUNT_ID>'
ORDER BY created_at DESC;

-- Verificar idempotencia
SELECT * FROM seo_ai_purchases
WHERE mp_payment_id = '<MP_PAYMENT_ID>';

-- Balance actual
SELECT * FROM seo_ai_credits
WHERE account_id = '<ACCOUNT_ID>'
ORDER BY created_at DESC
LIMIT 1;
```

### Acciones

**Si no llegó el webhook:**
1. Verificar URL del webhook en MP dashboard
2. Verificar logs: `grep "seo-ai/purchase/webhook"` en Railway logs
3. **Acreditar manualmente:**
   ```sql
   INSERT INTO seo_ai_credits (account_id, delta, balance_after, reason, metadata)
   VALUES (
     '<ACCOUNT_ID>',
     100,
     (SELECT COALESCE(balance_after, 0) FROM seo_ai_credits
      WHERE account_id = '<ACCOUNT_ID>' ORDER BY created_at DESC LIMIT 1) + 100,
     'manual_credit',
     '{"reason": "webhook_lost", "mp_payment_id": "<ID>", "operator": "<TU_NOMBRE>"}'
   );
   ```

**Si se procesó doble:**
- La lógica de idempotencia usa `mp_payment_id` como UNIQUE
- Si de todos modos ocurrió, revertir el excedente:
   ```sql
   INSERT INTO seo_ai_credits (account_id, delta, balance_after, reason, metadata)
   VALUES (
     '<ACCOUNT_ID>',
     -100,  -- negativo = reverso
     <balance_actual> - 100,
     'manual_reversal',
     '{"reason": "double_webhook", "operator": "<TU_NOMBRE>"}'
   );
   ```

---

## Escenario 4: Créditos insuficientes a mitad de job (P3)

### Síntomas
- Job completa parcialmente
- Log muestra "insufficient credits" o progreso < total

### Diagnóstico

```sql
-- Progreso del job
SELECT id, progress, cost_actual, cost_estimated, status
FROM seo_ai_jobs WHERE id = '<JOB_ID>';

-- Créditos del tenant
SELECT balance_after FROM seo_ai_credits
WHERE account_id = '<ACCOUNT_ID>'
ORDER BY created_at DESC LIMIT 1;
```

### Acciones

1. El worker para al quedarse sin créditos (by design)
2. El job queda en `completed` con `progress.done < progress.total`
3. El cliente debe comprar más créditos y lanzar un nuevo job con `mode: update_missing`

**Si el cliente se queja:**
- Verificar que `cost_estimated` fue correcto antes de iniciar
- Verificar que no hubo consumo de créditos por otro job concurrente (no debería — max concurrent = 1)

---

## Escenario 5: Entidades con `seo_locked = true` no se procesan (P4)

### Contexto
Esto es **comportamiento esperado**. Las entidades marcadas como locked fueron editadas manualmente por el cliente.

### Si el cliente quiere re-generar:
1. Desmarcar lock desde la UI de productos
2. O actualizar en DB:
   ```sql
   UPDATE products SET seo_locked = false
   WHERE client_id = '<CLIENT_ID>' AND id = '<PRODUCT_ID>';
   ```
3. Lanzar nuevo job con `mode: refresh`

---

## Escenario 6: API key de OpenAI comprometida (P1)

### Acciones inmediatas

1. **Revocar la key** en [platform.openai.com/api-keys](https://platform.openai.com/api-keys)
2. **Generar nueva key** y actualizar en Railway:
   ```bash
   railway variables set OPENAI_API_KEY=sk-new-key...
   ```
3. **Verificar logs** de uso en OpenAI dashboard (actividad sospechosa)
4. **Redeploy** el servicio
5. **Documentar** el incidente en `novavision-docs/audit/`

### Prevención
- La key NUNCA aparece en logs ni responses (verificado en auditoría PR7)
- Única referencia: constructor de `SeoAiService` (lectura de env)
- No commitear en código ni `.env`

---

## Contactos de escalación

| Rol | Contacto | Cuándo |
|-----|----------|--------|
| TL Backend | (definir) | P1-P2 |
| DevOps/Infra | (definir) | Worker caído, Railway issues |
| Billing/Finanzas | (definir) | Discrepancias de créditos/pagos |

---

## Queries útiles de monitoreo

```sql
-- Jobs fallidos en las últimas 24h
SELECT client_id, job_type, error, created_at
FROM seo_ai_jobs
WHERE status = 'failed'
  AND created_at > NOW() - INTERVAL '24 hours';

-- Top tenants por consumo de créditos (mes actual)
SELECT account_id, SUM(ABS(delta)) as total_consumed
FROM seo_ai_credits
WHERE delta < 0
  AND created_at > DATE_TRUNC('month', NOW())
GROUP BY account_id
ORDER BY total_consumed DESC;

-- Entidades procesadas por día
SELECT DATE(created_at), COUNT(*)
FROM seo_ai_log
GROUP BY DATE(created_at)
ORDER BY 1 DESC;
```
