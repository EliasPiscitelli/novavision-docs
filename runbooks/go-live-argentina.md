# Go-Live Argentina (AR) — Runbook

**Fecha planificada:** TBD  
**Autor:** agente-copilot  
**Rama:** feature/automatic-multiclient-onboarding  
**Pre-requisitos:** Auditoría de seguridad (7.6) completada, tests (7.1-7.5) verdes

---

## 1. Pre-requisitos Obligatorios

### 1.1 Hallazgos de Seguridad P0 resueltos
- [ ] **IDOR-1 corregido**: `/v1/tenants/:id/quotas` tiene ownership check o SuperAdminGuard
- [ ] **AUTH-1 corregido**: `BillingController` usa `SuperAdminGuard` (no PlatformAuthGuard)
- [ ] **GUARD-1 activo**: `QuotaCheckGuard` registrado como APP_GUARD
- [ ] **GUARD-2 activo**: `TenantRateLimitGuard` registrado como APP_GUARD

### 1.2 Base de datos
- [ ] Tabla `country_configs` tiene fila para `AR`:
  ```sql
  INSERT INTO country_configs (country_id, country_name, currency_code, locale, mp_site_id, tax_label, tax_rate, is_active)
  VALUES ('AR', 'Argentina', 'ARS', 'es-AR', 'MLA', 'IVA', 21, true)
  ON CONFLICT (country_id) DO UPDATE SET is_active = true;
  ```
- [ ] Tabla `fx_rates_config` tiene fila para `AR`:
  ```sql
  INSERT INTO fx_rates_config (country_id, source, auto_endpoint, auto_field_path, fallback_rate, cache_ttl_minutes)
  VALUES ('AR', 'auto', 'https://dolarapi.com/v1/dolares/blue', 'venta', 1200, 15)
  ON CONFLICT (country_id) DO UPDATE SET source = 'auto', auto_endpoint = 'https://dolarapi.com/v1/dolares/blue';
  ```
- [ ] Tabla `plans` tiene límites RPS correctos:
  - Starter: `rps_sustained=5`, `rps_burst=15`
  - Growth: `rps_sustained=15`, `rps_burst=45`
  - Enterprise: `rps_sustained=60`, `rps_burst=180`
- [ ] Tabla `fee_schedules` tiene schedule activo para Growth AR:
  - `order_overage_rate = 0.015`
  - `egress_overage_rate_gb = 0.08`
  - `gmv_commission_pct = 0.02`
  - `gmv_threshold = 40000`

### 1.3 Feature Flags
- [ ] `ENABLE_QUOTA_ENFORCEMENT=true` en Railway env vars
- [ ] `ENABLE_BILLING_V2=true` en Railway env vars (si aplica)
- [ ] Verificar que `REDIS_URL` está configurado en Railway (para rate limiting y FX cache)

### 1.4 Crons activos
- [ ] `QuotaEnforcementCron` → `0 3 * * *` (evalúa quotas diariamente)
- [ ] `GmvCommissionCron` → `0 6 2 * *` (comisión GMV mensual)
- [ ] `OverageCron` → `30 6 2 * *` (calcula overages mensual)

### 1.5 Mercado Pago
- [ ] Access token de MP configurado por tenant en `clients.mp_access_token`
- [ ] Webhook URL apunta al backend de producción: `POST /v1/payments/webhook`
- [ ] Firma de webhook habilitada y validada

### 1.6 Tests
- [ ] `npx jest test/quota-enforcement.spec.ts` → verde
- [ ] `npx jest test/gmv-commission-overage.spec.ts` → verde
- [ ] `npx jest test/fx-rates.spec.ts` → verde
- [ ] `npx jest test/tenant-rate-limit.spec.ts` → verde
- [ ] `npx jest test/checkout-multi-currency.spec.ts` → verde
- [ ] `npm run ci` (lint + typecheck + build) → verde
- [ ] Web: `npm run ci:storefront` → verde

---

## 2. Pasos de Deploy

### 2.1 Backend (Railway)
```bash
# 1. Merge feature branch a develop
git checkout develop
git pull origin develop
git merge feature/automatic-multiclient-onboarding --no-ff
git push origin develop

# 2. Verificar CI pass en GitHub Actions

# 3. Railway auto-deploy desde develop (o trigger manual)
```

### 2.2 Verificación post-deploy
```bash
# Health check
curl https://<api-url>/health

# Verificar FX rate para AR
curl -H "Authorization: Bearer <internal-token>" \
     -H "x-internal-key: <INTERNAL_ACCESS_KEY>" \
     https://<api-url>/admin/fx-rates

# Verificar country config
curl https://<api-url>/v1/tenant/countries

# Verificar plans catalog
curl https://<api-url>/v1/plans/catalog
```

### 2.3 Frontend (Netlify)
- Web y Admin se despliegan automáticamente al pushear a sus ramas respectivas
- Verificar que las páginas de pricing muestran precios en ARS
- Verificar que QuotaDashboard renderiza correctamente en admin de tenant

---

## 3. Smoke Tests Post-Deploy

### 3.1 Flujo de checkout (ARS)
1. Abrir tienda AR de prueba
2. Agregar producto al carrito
3. Ir a checkout → verificar que `currency_id: 'ARS'` en items de MP
4. Verificar que el total es correcto en pesos
5. Completar pago en sandbox → verificar webhook procesa

### 3.2 Quota enforcement
1. Crear un tenant Growth con quota state inicial ACTIVE
2. Simular uso >50% → verificar transición a WARN_50
3. Verificar que el dashboard muestra el estado correcto

### 3.3 FX rate
1. `GET /admin/fx-rates` → verificar que AR tiene rate > 0
2. Verificar que `convertUsdToLocal(60, 'AR')` retorna valor razonable

### 3.4 Rate limiting
1. Hacer >5 requests/segundo a un tenant Starter
2. Verificar que llega 429 con `Retry-After` header

---

## 4. Rollback Plan

### Si algo falla criticamente:
1. **Railway**: Revert al deploy anterior vía dashboard (1 clic)
2. **Feature flags**: Setear `ENABLE_QUOTA_ENFORCEMENT=false` para desactivar enforcement
3. **FX manual**: Cambiar `source` a `manual` y setear `manual_rate` en `fx_rates_config`
4. **Rate limiting**: Si causa 429 incorrectos, remover TenantRateLimitGuard del APP_GUARD array

### Contactos de escalación:
- Backend/Infra: @eliaspiscitelli
- Base de datos: Supabase dashboard (admin project)
- Pagos: Mercado Pago dashboard del tenant

---

## 5. Métricas a Monitorear (primeras 48h)

| Métrica | Alerta si... | Dónde ver |
|---|---|---|
| Error rate 5xx | > 1% en 5 min | Railway logs |
| P95 latency | > 2s | Railway metrics |
| 429 rate | > 5% de requests | Railway logs (buscar `RATE_LIMITED`) |
| Webhook failures | > 3 consecutivos sin procesar | Logs (`[Webhook]` + Supabase `payments` table) |
| FX rate fetch errors | 3+ fallos consecutivos | Logs (`[FxService]` errors) |
| Quota state anomalies | HARD_LIMIT sin correspondencia de uso | `quota_state` table |
| Order stuck pending | > 30 min en pending | `orders` table + expiration cron logs |

---

## 6. Post Go-Live (Semana 1)

- [ ] Verificar primer ciclo de cron GMV (día 2 del mes)
- [ ] Verificar primer ciclo de cron Overage (día 2 del mes)
- [ ] Revisar billing_adjustments generados
- [ ] Validar que no hay cross-tenant data leak en logs
- [ ] Revisar dashboards de uso de Redis (rate limit + FX cache)
- [ ] Documentar cualquier hotfix aplicado
