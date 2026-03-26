# Runbook: Activación Quota Enforcement + AI Pro n8n

**Fecha**: 2026-03-26
**Tipo**: Operaciones — no requieren cambios de código

---

## 1. Quota Enforcement

### Variable de entorno
```
ENABLE_QUOTA_ENFORCEMENT=true
```

### Dónde se lee
- `apps/api/src/billing/quota-enforcement.service.ts` — getter `enforcementEnabled`
- Acepta `'true'` o `'1'`. Default: `false`.

### Qué controla
1. **QuotaCheckGuard** (APP_GUARD global): Bloquea escrituras (POST/PUT/PATCH/DELETE) cuando tenant está en `HARD_LIMIT`. Retorna HTTP 403 `code: 'QUOTA_EXCEEDED'`. En `SOFT_LIMIT`/`GRACE` permite pero agrega headers `X-Quota-Warning`.
2. **Cron evaluateAll** (03:00 UTC diario): Persiste transiciones de estado en `quota_state` y encola notificaciones. Con flag OFF funciona como dry-run (evalúa pero no escribe).

### Máquina de estados
```
ACTIVE → WARN_50 → WARN_75 → WARN_90 → SOFT_LIMIT → GRACE → HARD_LIMIT
```

### Prerequisitos (verificar con psql)
```sql
-- 1. Tabla quota_state existe
SELECT column_name FROM information_schema.columns WHERE table_name = 'quota_state';

-- 2. Tabla usage_rollups_monthly con datos
SELECT COUNT(*) FROM usage_rollups_monthly WHERE period_start >= date_trunc('month', NOW());

-- 3. Planes con límites poblados
SELECT plan_key, included_orders, included_requests, grace_days FROM plans LIMIT 10;
```

### Activación
1. Railway → API service → Variables → `ENABLE_QUOTA_ENFORCEMENT=true`
2. Redeploy
3. Monitorear logs: buscar `QuotaEnforcementService` y `Blocked write for tenant`

---

## 2. AI Pro M10 — Weekly Report con guardrails

### Qué activar
- Workflow: `wf-weekly-report-v2.json` en n8n
- Trigger: Lunes 12:00 UTC (09:00 ART)

### Pasos
1. Abrir workflow en n8n
2. Agregar nodo Code post-IA: validar regex (precios inventados, claims absolutos)
3. Agregar nodo IF + fallback: "Reporte no disponible esta semana"
4. Verificar credenciales OpenAI en n8n (Settings > Credentials)
5. Activar workflow (toggle ON)
6. Monitorear primer lunes

---

## 3. AI Pro M12 — AI Closer (WhatsApp inbound)

### Qué activar
- Workflow: `wf-inbound-v2.json` en n8n (35 nodos)
- Playbook: verificar `SELECT COUNT(*) FROM nv_playbook WHERE is_active = true;` (>= 33 entries)

### Variables de entorno n8n
- `WHATSAPP_APP_SECRET` — HMAC verification
- `WHATSAPP_PHONE_NUMBER_ID` — ID del número WA Business
- `WHATSAPP_ACCESS_TOKEN` — Token Meta
- Credenciales OpenAI (o Anthropic si se decide test A/B)
- PostgreSQL → Admin DB (outreach_leads, outreach_logs, nv_playbook)

### Pasos
1. Importar `wf-inbound-v2.json` en n8n
2. Configurar webhook URL en Meta Developer Console → `/wa-inbound`
3. Agregar nodo validación JSON post-respuesta IA
4. Activar con `bot_enabled = false` globalmente
5. Habilitar `bot_enabled = true` para subset de prueba
6. Monitorear: reply rate, engagement delta, conversion to demo

### Decisión pendiente
- D7: Test A/B entre `gpt-4.1-mini` vs `claude-haiku-4-5` para AI Closer
