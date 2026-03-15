# Auditoría E2E: Onboarding → Publicación → Cambios Post-Publicación

**Fecha**: 2026-03-15
**Auditor**: Claude Opus 4.6 — investigación de código real sobre 3 repos
**Repos auditados**: API (`apps/api`), Admin (`apps/admin`), Web (`apps/web`)
**Método**: 3 agentes paralelos auditando flujo onboarding, schema BD + consumo, y cambios post-publicación
**Estado**: COMPLETA

---

## 1. Resumen Ejecutivo

### El flujo funciona pero tiene deuda técnica significativa

El pipeline onboarding → provisioning → publicación está **funcional** para el happy path. Los datos se migran correctamente de Admin DB a Backend DB con mappings verificados campo por campo. El storefront consume los datos correctos a través de una cadena de fallbacks bien diseñada.

Sin embargo, hay **10 columnas usadas en código sin migración SQL tracked**, **2 definiciones de schema conflictivas** (backend_clusters, subscriptions), **campos stale post-provisioning** (clients.template_id, clients.entitlements), y **2 sources of truth para logo** que no están sincronizados.

### Veredicto por área

| Área | Estado | Confianza |
|------|--------|-----------|
| Onboarding (12 pasos) | SANO | Alta — cada paso tiene endpoint y persistencia clara |
| Provisioning (22 pasos) | FUNCIONAL pero frágil | Media — sin transacción, fallo parcial posible |
| Migración Admin→Backend | CORRECTA | Alta — 30+ campos mapeados y verificados |
| Storefront consume datos | CORRECTO | Alta — fallback chain sólido en home-settings.service |
| Cambios post-publicación | FUNCIONAL | Media — fragmentado entre múltiples endpoints |
| Schema de BD | DEUDA TÉCNICA | Baja — columnas sin migración, schemas conflictivos |
| Preview vs Producción | DIVERGENTE por diseño | Aceptable — onboarding usa demo, admin usa real |

---

## 2. Flujo Real E2E

### Onboarding (Admin App → API → Admin DB)

```
Step 1: email + slug → POST /onboarding/builder/start → nv_accounts + nv_onboarding (Admin DB)
Step 2: logo → localStorage (TODO: upload real no implementado)
Step 3: catálogo CSV/AI → POST /onboarding/import-home-bundle → nv_onboarding.progress (Admin DB)
Step 4: template + palette + secciones → PATCH /onboarding/preferences → nv_onboarding (Admin DB)
Step 5: login Supabase → POST /onboarding/session/link-user → nv_accounts.user_id (Admin DB)
Step 6: checkout → POST /onboarding/checkout/start → slug_reservations + subscriptions (Admin DB)
Step 6b: webhook MP → nv_accounts.status='paid' + enqueue provisioning_jobs (Admin DB)
Step 7: MP OAuth → nv_accounts.mp_connected + mp_connections (Admin DB)
Step 8: datos fiscales → POST /onboarding/business-info → nv_accounts (Admin DB)
Step 9: verificar MP → (solo lectura)
Step 10: submit → POST /onboarding/submit-for-review → nv_onboarding.state='submitted' (Admin DB)
Step 11: terms → POST /onboarding/session/accept-terms → nv_accounts.terms_* + merchant_consents (Admin DB)
Step 12: success → (display)
```

### Provisioning (Worker → Admin DB → Backend DB)

```
Read: nv_accounts + nv_onboarding + slug_reservations + plans (Admin DB)
Write 1: UPSERT clients (Backend DB) — 30+ campos
Write 2: CREATE user en Supabase Auth (Backend Supabase)
Write 3: UPSERT users (Backend DB)
Write 4: UPDATE nv_accounts.status='provisioned' (Admin DB)
Write 5: SYNC MP credentials → clients (Backend DB)
Write 6: UPSERT client_home_settings (Backend DB) — template_key, palette_key, theme_config, design_config
Write 7: INSERT custom_palettes (Backend DB)
Write 8: UPSERT client_shipping_settings (Backend DB)
Write 9: COPY assets → Supabase Storage (Backend)
Write 10: INSERT logos + UPDATE clients.logo_url (Backend DB)
Write 11: UPSERT products + categories + faqs + services (Backend DB)
Write 12: UPSERT tenant_pages (Backend DB)
Cleanup: DELETE slug_reservations (Admin DB)
```

### Publicación

```
Trigger: Aprobación manual por super admin → nv_accounts.status='approved'
Publish: API endpoint → clients.publication_status='published' + clients.is_active=true (Backend DB)
Disponibilidad: Storefront accesible via {slug}.novavision.lat
Dashboard: Admin dashboard accesible via {slug}.novavision.lat/admin-dashboard
```

---

## 3. Matriz de migración Admin DB → Backend DB

### nv_accounts → clients (30 campos)

| Admin DB (nv_accounts) | Backend DB (clients) | Transformación | Evidencia | Estado |
|------------------------|---------------------|----------------|-----------|--------|
| id | nv_account_id | Directo | worker L582 | VERIFICADO |
| email | email_admin | Directo | worker L583 | VERIFICADO |
| slug / slug_reservations.slug | slug | Prioridad: reservación > account | worker L569 | VERIFICADO |
| business_name | name | Fallback a slug | worker L570 | VERIFICADO |
| plan_key / onboarding.plan_key_selected | plan + plan_key | Onboarding prioridad | worker L571-572 | VERIFICADO |
| (calculado) | entitlements | plans + account_addons | worker L577 | VERIFICADO |
| (calculado) | monthly_fee | plans.monthly_fee | worker L573 | VERIFICADO |
| onboarding.selected_template_key | template_id | normalizeTemplateKey() | worker L578 | VERIFICADO — STALE post-cambio |
| onboarding.selected_theme_override | theme_config | Fallback {} | worker L579 | VERIFICADO |
| country | country, locale, timezone | Map + fallback 'AR' | worker L584-597 | VERIFICADO |
| persona_type → phone_full | 10 campos fiscales | Directo | worker L587-596 | VERIFICADO |

### nv_onboarding → client_home_settings (4 campos)

| Admin DB | Backend DB | Prioridad | Evidencia | Estado |
|----------|-----------|-----------|-----------|--------|
| progress.wizard_template_key OR selected_template_key | template_key | progress primero | worker L919-937 | VERIFICADO |
| progress.wizard_palette_key OR selected_palette_key | palette_key | progress primero | worker L923/933 | VERIFICADO |
| progress.wizard_theme_override OR selected_theme_override | theme_config | progress primero | worker L924/934 | PARCIAL — columna sin migración |
| progress.wizard_design_config OR design_config | design_config | progress primero | worker L925-936 | PARCIAL — columna sin migración |

### nv_onboarding.progress → Backend DB (catálogo)

| Origen | Destino | Evidencia | Estado |
|--------|---------|-----------|--------|
| catalog_data.categories | categories (Backend DB) | worker L1814-1843 | VERIFICADO |
| catalog_data.products | products (Backend DB) | worker L1845-1912 | VERIFICADO |
| catalog_data.faqs | faqs (Backend DB) | worker L1914-1938 | VERIFICADO |
| catalog_data.services | services (Backend DB) | worker L1940-1964 | VERIFICADO |
| wizard_assets.logo_url | logos + clients.logo_url (Backend DB) | worker L1014-1037, L1137-1293 | VERIFICADO |
| wizard_custom_palettes | custom_palettes (Backend DB) | worker L956-980 | VERIFICADO |

---

## 4. Source of Truth por concepto

| Concepto | Source of Truth | Tabla.columna | Base | Alternativa stale/legacy |
|----------|----------------|---------------|------|--------------------------|
| Template | client_home_settings.template_key | Backend | clients.template_id (STALE) |
| Palette | client_home_settings.palette_key | Backend | — |
| Secciones | home_sections rows | Backend | design_config.sections (fallback) |
| Logo (producción) | logos (show_logo=true) | Backend | — |
| Logo (identity) | client_home_settings.identity_config.logo | Backend | NO SINCRONIZADO con logos |
| Store name | clients.name | Backend | — |
| Plan | clients.plan_key | Backend | nv_accounts.plan_key (Admin) |
| Entitlements | clients.entitlements | Backend | SNAPSHOT — no se re-calcula |
| Palette CSS vars | palette_catalog.preview | Admin | Resuelto via cross-DB query |
| Template catalog | nv_templates | Admin | — |

---

## 5. Problemas detectados — por severidad

### P0 — Críticos (afectan integridad de datos)

| # | Problema | Impacto | Evidencia | Fix sugerido |
|---|----------|---------|-----------|-------------|
| 1 | **Provisioning sin transacción** — 22 pasos secuenciales, fallo en paso N deja tenant parcialmente creado | Tenant zombie que no puede re-provisionarse sin intervención manual | worker.service.ts — no hay try/catch global con rollback | Wrap en saga pattern con compensación |
| 2 | **10 columnas usadas en código sin migración tracked** | Producción funciona (creadas manualmente) pero no reproducible en nuevo cluster | home_sections.component_key, client_home_settings.theme_config/design_config, nv_accounts.phone/fiscal_*, client_usage.storage_bytes_used, etc. | Crear migraciones retroactivas |
| 3 | **2 schemas conflictivos** — backend_clusters (uuid PK vs text PK), subscriptions (2 definiciones) | Deploy en nuevo cluster falla o tiene schema impredecible | ADMIN_010 vs 20250101000002, 20260102000001 vs 20260111 | Consolidar en 1 migración canónica |

### P1 — Importantes (afectan consistencia)

| # | Problema | Impacto | Evidencia |
|---|----------|---------|-----------|
| 4 | **Logo dual source of truth** — `logos` tabla vs `identity_config.logo` | Admin puede setear logo en un lugar y producción leer de otro | home-settings.service.ts vs logo.service.ts |
| 5 | **clients.template_id STALE** — nunca se actualiza post-provisioning | Dato incorrecto en BD, confunde queries directas | home-settings.service.ts L63-89 |
| 6 | **clients.entitlements es snapshot** — no se re-calcula si cambia plan o addons | Tenant con upgrade sigue con entitlements viejos | worker.service.ts L577 |
| 7 | **Step2 logo upload es TODO** — logo se guarda como base64 en localStorage | Funciona pero frágil — base64 de imagen en localStorage | Step2Logo.tsx TODO comment |
| 8 | **nv_onboarding.progress es mega JSONB** — acumula todo sin schema | Difícil de auditar, migrar y validar | onboarding.service.ts updateProgress() |

### P2 — Deuda técnica

| # | Problema | Impacto |
|---|----------|---------|
| 9 | 15 campos WRITE-ONLY en clients (nunca leídos por storefront) | Datos almacenados sin consumidor |
| 10 | `home_settings` tabla legacy duplica `client_home_settings` | Confusión, tabla zombie |
| 11 | `coupons` existe en ambas DBs con schemas distintos | Duplicación de concepto |
| 12 | Onboarding preview usa demo seed, no datos reales | Decisiones visuales basadas en data falsa |

---

## 6. Campos WRITE-ONLY (provisionados pero nunca leídos por storefront)

| Campo en clients | Escrito por | Leído por storefront | Leído por admin dashboard |
|-----------------|-------------|---------------------|--------------------------|
| monthly_fee | provisioning | NO | NO |
| billing_period | provisioning | NO | NO |
| connection_type | provisioning | NO | NO |
| base_url | provisioning | NO | NO |
| legal_name | provisioning | NO | NO |
| billing_email | provisioning | NO | NO |
| phone / phone_full | provisioning | NO | NO |
| page_layout | BACKEND_010 migration | NO | NO |
| has_demo_data | BACKEND_013 migration | NO | NO |
| maintenance_mode | migration | NO | NO |
| deleted_at | migration | NO | NO |
| entitlements_snapshot | ADMIN_025 migration | NO | NO |
| dni / dni_*_url | migration | NO | NO |

---

## 7. Campos CONTRADICTED (usados en código sin migración)

| Campo | Usado en | Operación | Migración | Riesgo |
|-------|---------|-----------|-----------|--------|
| client_home_settings.theme_config | home-settings.service L39, worker L949 | SELECT + UPSERT | **NO HAY** | P0 — falla en nuevo cluster |
| client_home_settings.design_config | home-settings.service L39, worker L950 | SELECT + UPSERT | **NO HAY** | P0 |
| home_sections.component_key | home-sections.service L198-202 | SELECT + INSERT | **NO HAY** | P0 |
| nv_accounts.custom_domain | home-settings.service L52 | SELECT | **NO HAY** | P1 |
| nv_accounts.custom_domain_status | home-settings.service L53 | SELECT | **NO HAY** | P1 |
| clients.entitlement_overrides | home-settings.service L194 | SELECT | **NO HAY** | P1 |
| clients.publish_requested_at | clients.service L88 | UPDATE | **NO HAY** | P2 |
| client_usage.storage_bytes_used | triggers 20260315 | UPDATE | **NO HAY** | P1 |
| nv_accounts.phone/phone_full/business_name/legal_name/fiscal_* | provisioning worker L448 | SELECT | **NO HAY en admin/** | P1 |
| nv_onboarding.progress | provisioning worker L471 | SELECT | **NO HAY** (puede ser `data` jsonb) | P1 |

---

## 8. Casos de prueba E2E críticos

### Happy path: Alta completa

| Precondición | Steps | Writes esperados | Resultado |
|-------------|-------|-----------------|-----------|
| Email nuevo, slug disponible | Steps 1-12 completos | nv_accounts + nv_onboarding + slug_reservations + subscriptions + merchant_consents (Admin), clients + users + client_home_settings + logos + products + categories + faqs + services + tenant_pages (Backend) | Tienda publicada, admin dashboard accesible |

### Retry con mismo email
| Precondición | Steps | Resultado esperado |
|-------------|-------|--------------------|
| Email ya existe en nv_accounts | Step 1 | Devuelve builder_token existente, no crea duplicado |

### Retry con mismo slug
| Precondición | Steps | Resultado esperado |
|-------------|-------|--------------------|
| Slug reservado por otra cuenta | Step 1 | Error de slug duplicado, pide otro slug |

### Pago rechazado
| Precondición | Steps | Resultado esperado |
|-------------|-------|--------------------|
| Checkout iniciado, MP rechaza | Webhook con status != approved | nv_accounts.status queda 'awaiting_payment', no se enqueue provisioning |

### Provisioning reintentado
| Precondición | Steps | Resultado esperado |
|-------------|-------|--------------------|
| Provisioning falló en paso 15 | Re-enqueue mismo job | UPSERT (onConflict: nv_account_id) no duplica client, idempotente para pasos ya ejecutados |

### Cambio de template después de publicada
| Precondición | Steps | Writes esperados |
|-------------|-------|-----------------|
| Tienda publicada con template_5 | Admin cambia a template_8 via PUT /settings/home | client_home_settings.template_key='template_8', clients.template_id queda stale como 'template_5' |

### Preview onboarding vs admin vs storefront
| Sistema | Source de secciones | Source de productos | Source de template |
|---------|--------------------|--------------------|-------------------|
| Onboarding preview | PRESET_CONFIGS (admin app) | PREVIEW_DEMO_SEED | WizardContext state |
| Admin Store Design preview | home_sections (Backend DB) | fetchHomeData() real | client_home_settings.template_key |
| Storefront producción | home_sections (Backend DB) | products tabla real | client_home_settings.template_key |

---

## 9. Plan de corrección por fases

### Phase 0: Bugs P0 (inmediato)

| Fix | Archivos | Migración SQL | Riesgo regresión |
|-----|----------|---------------|-----------------|
| Crear migraciones retroactivas para las 10 columnas sin migración | `migrations/backend/` y `migrations/admin/` | SÍ — ALTER TABLE ADD COLUMN IF NOT EXISTS | Bajo — columnas ya existen en prod |
| Consolidar schemas conflictivos de backend_clusters y subscriptions | `migrations/admin/` | SÍ — DROP + CREATE canónico | Alto — necesita backup previo |

### Phase 1: Inconsistencias de modelo (1-2 semanas)

| Fix | Archivos | Impacto |
|-----|----------|---------|
| Sincronizar logo: que LogoService actualice identity_config.logo | logo.service.ts + home-settings.service.ts | Medio |
| Actualizar clients.template_id cuando admin cambia template | home-settings.service.ts | Bajo |
| Re-calcular entitlements en upgrade/addon change | plans.service.ts + addons.service.ts | Medio |
| Implementar upload real de logo en Step 2 | apps/admin Step2Logo.tsx | Bajo |

### Phase 2: Unificación de source of truth (2-4 semanas)

| Fix | Archivos | Impacto |
|-----|----------|---------|
| Mover nv_onboarding.progress a columnas tipadas | migraciones Admin + onboarding.service.ts | Alto |
| Eliminar home_settings tabla legacy | migración Backend | Bajo |
| Unificar coupons schema entre Admin y Backend | migraciones ambas DBs | Medio |
| Eliminar campos WRITE-ONLY de clients o crear consumidores | home.service.ts | Bajo |

### Phase 3: Hardening y observabilidad (4-6 semanas)

| Fix | Archivos | Impacto |
|-----|----------|---------|
| Wrap provisioning en saga pattern con compensación | provisioning-worker.service.ts | Alto |
| Agregar health-check de provisioning parcial | worker + API endpoint | Medio |
| Agregar Zod validation a nv_onboarding.progress writes | onboarding.service.ts | Medio |
| Logging estructurado en cada paso del provisioning | worker.service.ts | Bajo |

### Phase 4: QA automatizada (ongoing)

| Fix | Archivos | Impacto |
|-----|----------|---------|
| E2E test: onboarding completo → storefront render | novavision-e2e | Alto |
| E2E test: cambio de template post-publicación | novavision-e2e | Medio |
| Integration test: provisioning worker idempotencia | apps/api tests | Alto |
| Schema validation: comparar migraciones vs columns reales | script SQL | Medio |
