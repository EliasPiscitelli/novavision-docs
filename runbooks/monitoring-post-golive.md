# Monitoreo Post Go-Live — Protocolo de Alertas y Hotfixes

**Fecha:** 2025-07-15  
**Autor:** agente-copilot  
**Aplica a:** Go-Live Argentina (AR) y futuras expansiones LATAM  

---

## 1. Dashboards y Fuentes de Datos

| Fuente | URL/Acceso | Qué monitorear |
|---|---|---|
| Railway Logs | Dashboard Railway → project → logs | Errores 5xx, warnings, cron execution |
| Railway Metrics | Dashboard Railway → project → metrics | CPU, memory, P95 latency, request rate |
| Supabase Dashboard (Admin) | Supabase → Admin project → Table Editor | `quota_state`, `billing_adjustments`, `fx_rates_config` |
| Supabase Dashboard (Backend) | Supabase → Backend project → Table Editor | `orders`, `payments`, `clients` |
| Mercado Pago Dashboard | MP → developers → webhooks | Webhook delivery status, retries |
| Redis (Upstash/Railway) | Dashboard del provider | Memory usage, connections, key count |

---

## 2. Alertas Críticas (Primeras 48h)

### Nivel 1 — Responder en < 15 min

| Alerta | Condición | Acción inmediata |
|---|---|---|
| **Error rate > 5%** | > 5% de requests devuelven 5xx en 5 min | Revisar logs → si es DB: verificar conexión Supabase. Si es MP: verificar access token. Rollback si > 10%. |
| **All webhooks failing** | 0 webhooks procesados en 30 min (habiendo órdenes pending) | Verificar endpoint accesible desde MP, verificar firma, revisar logs `[Webhook]` |
| **FX rate = 0 o null** | `getRate('AR')` retorna 0 o error | Cambiar `fx_rates_config.source` a `manual`, setear `manual_rate` con valor actual |
| **HARD_LIMIT masivo** | > 3 tenants pasan a HARD_LIMIT en < 1h sin correspondencia real de uso alto | Posible bug en evaluate(). Setear `ENABLE_QUOTA_ENFORCEMENT=false`. Investigar. |

### Nivel 2 — Responder en < 2h

| Alerta | Condición | Acción |
|---|---|---|
| **429 rate > 10%** | > 10% de requests son 429 para un tenant específico | Verificar plan limits correctos. Si son bajos: ajustar `rps_sustained`/`rps_burst` en DB. |
| **Quota state stuck** | Tenant con uso alto (>90%) pero state = ACTIVE por > 24h | Verificar que cron corrió. Si no: ejecutar `evaluateTenant()` manual vía admin endpoint. |
| **Cron no ejecutó** | Log `[QuotaEnforcementCron]` o `[GmvCommissionCron]` no aparece en horario esperado | Verificar que NestJS schedule está activo. Re-deploy si necesario. |
| **Latency P95 > 3s** | Medido en Railway metrics | Investigar slow queries en Supabase → verificar índices. Load test si sospecha de rate limit. |

### Nivel 3 — Resolver en < 24h

| Alerta | Condición | Acción |
|---|---|---|
| **Billing adjustment incorrecto** | Overage o GMV commission con monto claramente erróneo | Verificar datos de uso vs fórmula. Ajustar manualmente via admin endpoint. |
| **FX rate stale > 24h** | `last_auto_fetch_at` no se actualiza | Verificar que el endpoint externo sigue online. Cambiar a manual temporalmente. |
| **Cross-tenant data** | Log muestra query sin `client_id` filter | P0 security fix. Patch inmediato. |

---

## 3. Queries de Diagnóstico

### Quota state de un tenant
```sql
SELECT qs.*, na.business_name, p.name as plan_name
FROM quota_state qs
JOIN nv_accounts na ON na.id = qs.nv_account_id
JOIN plans p ON p.id = na.plan_id
WHERE qs.nv_account_id = '<ACCOUNT_UUID>';
```

### Billing adjustments del mes
```sql
SELECT ba.*, na.business_name
FROM billing_adjustments ba
JOIN nv_accounts na ON na.id = ba.nv_account_id
WHERE ba.period_start >= date_trunc('month', now())
ORDER BY ba.created_at DESC;
```

### FX rates status
```sql
SELECT country_id, source, manual_rate, last_auto_rate, 
       last_auto_fetch_at, last_error, fallback_rate
FROM fx_rates_config
ORDER BY country_id;
```

### Webhooks recientes
```sql
SELECT id, client_id, status, provider_payment_id, 
       created_at, processed_at
FROM payments 
WHERE created_at > now() - interval '2 hours'
ORDER BY created_at DESC
LIMIT 20;
```

### Rate limiting impact
```bash
# En Railway logs, buscar:
grep "RATE_LIMITED\|exceeded sustained\|exceeded burst" railway.log | tail -50
```

---

## 4. Hotfix Protocol

### Flujo para hotfixes
```
1. Identificar el bug (logs, query, reporte)
2. Branch: fix/billing/<descripcion-corta>
3. Fix minimal (solo el bug, nada más)
4. Validar: npm run ci 
5. PREGUNTAR al TL antes de commit/push
6. Deploy: merge a develop → Railway auto-deploy
7. Verificar fix en producción (smoke test)
8. Documentar en novavision-docs/changes/
```

### Template para hotfix log
```markdown
# Hotfix: <breve descripción>

- **Fecha:** YYYY-MM-DD HH:MM
- **Severidad:** P0/P1/P2
- **Síntoma:** <qué reportó el usuario o qué se vio en logs>
- **Causa raíz:** <qué estaba mal>
- **Fix:** <qué se cambió, archivos>
- **Verificación:** <cómo se verificó que funciona>
- **Impacto:** <qué tenants/flujos afectó>
- **Preventivo:** <qué se haría para evitar recurrencia>
```

---

## 5. Métricas de Éxito (Semana 1)

| Métrica | Target | Cómo medir |
|---|---|---|
| Uptime | > 99.5% | Railway metrics |
| Error rate | < 0.5% | Railway logs (5xx / total) |
| Webhook success rate | > 99% | MP dashboard + payments table |
| FX rate freshness | < 30 min stale | `last_auto_fetch_at` vs now() |
| Quota transitions correctas | 100% coherentes con uso real | Comparar `quota_state.state` vs `usage_rollups_monthly` |
| Checkout completion (AR) | > 60% de intents | `orders.status = paid` / `orders total` |
| P95 latency | < 1.5s | Railway metrics |

---

## 6. Escalación

| Nivel | Quién | Cuándo |
|---|---|---|
| L1 — Operador | Team dev | Alertas Nivel 2-3, monitoreo rutinario |
| L2 — Lead | @eliaspiscitelli | Alertas Nivel 1, hotfixes P0 |
| L3 — Infra | Supabase support / Railway support | DB down, infra failures |
| L4 — Pagos | Mercado Pago soporte developers | Webhook failures masivos, credenciales |

---

## 7. Checklist Semanal (Post Go-Live)

### Semana 1
- [ ] Revisar todos los crons ejecutados correctamente
- [ ] Verificar billing_adjustments del primer ciclo
- [ ] Revisar FX rate history (no gaps)
- [ ] Confirmar 0 cross-tenant data issues
- [ ] Documentar cualquier hotfix

### Semana 2
- [ ] Revisar métricas de éxito vs targets
- [ ] Evaluar si rate limits necesitan ajuste
- [ ] Verificar que quota enforcement es correcta para todos los estados
- [ ] Preparar report de go-live para stakeholders

### Semana 4
- [ ] Cerrar hallazgos P1 de auditoría de seguridad
- [ ] Evaluar readiness para siguiente país (CL/MX)
- [ ] Retrospectiva de go-live
