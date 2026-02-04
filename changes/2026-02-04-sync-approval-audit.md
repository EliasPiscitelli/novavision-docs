# 🔍 INFORME DE INCONSISTENCIAS - NovaVision Sync/Approval/Theme
> **Fecha:** 2026-02-04  
> **Autor:** Principal Engineer Audit  
> **Scope:** Onboarding → Approval → Provisioning → Storefront Render  
> **Estado:** AUDITORÍA COMPLETADA — SOLO INFORME, SIN CAMBIOS APLICADOS  
> **Ramas Analizadas:** `develop`, `feature/multitenant-storefront`, `feature/onboarding-preview-stable`

---

## 🎯 DECISIÓN ARQUITECTÓNICA: FUENTE ÚNICA DE VERDAD

### Tabla Elegida: `client_home_settings` (Backend DB)

**Justificación:**
1. Es la tabla que el storefront **ya intenta leer** (`HomeSettingsService`, `StorefrontAssembler`)
2. Tiene el schema correcto: `template_key`, `palette_key`, `identity_config`, `theme_config`
3. Permite separar config de render (storefront) de datos administrativos (`clients`)
4. El frontend espera `templateKey`/`paletteKey` en camelCase — esta tabla puede normalizar

**Contrato de Config Final (client_home_settings):**
```sql
-- Schema esperado (Backend DB: ulndkhijxtxvpmbbfrgp)
CREATE TABLE IF NOT EXISTS client_home_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID NOT NULL UNIQUE REFERENCES clients(id),
  template_key TEXT NOT NULL DEFAULT 'first',
  palette_key TEXT NOT NULL DEFAULT 'starter_default',
  identity_config JSONB DEFAULT '{}',
  theme_config JSONB DEFAULT '{}',
  identity_version INT DEFAULT 1,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
```

**Owner del dato:**
- **Escritura:** Provisioning Worker (`provisioning-worker.service.ts`) al aprobar/publicar
- **Lectura:** `HomeSettingsService` + `StorefrontAssembler` (endpoint `/home/data`, `/storefront/bootstrap`)
- **Sincronización:** Onboarding → Approval → `client_home_settings` (única dirección)

---

## 📋 RESUMEN EJECUTIVO

### Top 5 Hallazgos Críticos

1. **`client_home_settings` VACÍA** — El storefront lee de esta tabla para `templateKey/paletteKey`, pero está vacía en producción (0 rows). Los datos de tema están en `clients.template_id` y `clients.theme_config`.

2. **DUPLICACIÓN DE FUENTES DE VERDAD** — El tema se guarda en:
   - `clients.template_id` + `clients.theme_config` (Backend DB)
   - `nv_onboarding.selected_template_key` + `selected_palette_key` (Admin DB)
   - `client_home_settings` (Backend DB, vacía)
   - `client_themes` (Admin DB, vacía)
   
   Sin prioridad clara ni sincronización.

3. **`HomeSettingsService` USA CLIENTE INCORRECTO** — El fallback usa `SUPABASE_ADMIN_CLIENT` pero la tabla `client_home_settings` está en Backend DB (confirmado: no existe en Admin DB).

4. **ONBOARDING NO PROPAGA `paletteKey`** — El provisioning escribe `template_id` a `clients`, pero el código del storefront busca `templateKey` (case-sensitive) y `paletteKey` que no existen en `clients`.

5. **PREVIEW Y STOREFRONT DIVERGEN** — El preview de onboarding usa `selected_template_key/selected_palette_key` de `nv_onboarding`, pero el storefront renderiza desde `client_home_settings` (vacía) o `clients.template_id` (campo diferente).

### 🚨 Riesgos Inmediatos

| Riesgo | Impacto | Probabilidad |
|--------|---------|--------------|
| Storefront muestra tema incorrecto | ALTO - Afecta TODAS las tiendas | CONFIRMADO |
| Preview onboarding ≠ Tienda publicada | ALTO - Mala UX, tickets de soporte | CONFIRMADO |
| `HomeSettingsService` falla silenciosamente | MEDIO - Fallbacks ocultan el error | CONFIRMADO |

---

## 🗺️ MAPA DEL FLUJO ACTUAL

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      ONBOARDING (Admin App)                              │
│                                                                          │
│  1. Usuario selecciona template/palette en Step5TemplateSelector         │
│     → Guarda en: nv_onboarding.selected_template_key                     │
│     → Guarda en: nv_onboarding.selected_palette_key                      │
│     → Guarda en: nv_onboarding.selected_theme_override (JSONB)           │
│                                                                          │
│  2. Preview muestra usando valores de nv_onboarding                       │
│     → Frontend Admin usa postMessage/URL params (NO lee de Backend DB)   │
└─────────────────────────────────────────┬────────────────────────────────┘
                                          │
                                          ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                       PROVISIONING (API Worker)                          │
│                                                                          │
│  3. provisionClient() / provisionClientFromOnboarding()                  │
│     → Lee: nv_onboarding.selected_template_key                           │
│     → Escribe a: clients.template_id (NO template_key!)                  │
│     → Escribe a: clients.theme_config (selected_theme_override)          │
│                                                                          │
│  4. También escribe a: client_home_settings (línea ~608)                 │
│     → PERO: client_home_settings está VACÍA en producción                │
│     → CAUSA PROBABLE: Error silencioso, constraint faltante, o          │
│       este código no se ejecuta para todos los flujos                   │
└─────────────────────────────────────────┬────────────────────────────────┘
                                          │
                                          ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                       STOREFRONT RENDER (Web App)                        │
│                                                                          │
│  5. useFetchHomeData() → GET /home/data                                  │
│     → HomeService.getHomeData() → HomeSettingsService.getSettings()      │
│     → Lee de: client_home_settings (VACÍA!)                              │
│     → Fallback: templateKey='template_1', paletteKey='starter_default'   │
│                                                                          │
│  6. App.jsx usa: homeData?.config?.templateKey                           │
│     → Pasa a useEffectiveTheme()                                         │
│     → Resultado: SIEMPRE usa defaults, ignora config real del cliente   │
│                                                                          │
│  ALTERNATIVA (storefront/bootstrap):                                     │
│  7. StorefrontAssembler.buildBootstrap()                                 │
│     → También lee client_home_settings (vacía)                           │
│     → buildConfig() tiene fallback a settings?.template_key              │
│     → PERO nunca hay settings porque la tabla está vacía                │
└─────────────────────────────────────────────────────────────────────────┘
```

### Dónde se Pierde la Config

| Paso | Fuente | Destino | Estado |
|------|--------|---------|--------|
| Onboarding → nv_onboarding | UI Form | nv_onboarding.selected_* | ✅ Funciona |
| Provisioning → clients | nv_onboarding | clients.template_id | ✅ Funciona (pero usa template_id, no template_key) |
| Provisioning → client_home_settings | nv_onboarding | client_home_settings | ❌ FALLA (tabla vacía) |
| Storefront ← client_home_settings | client_home_settings | Frontend | ❌ Lee tabla vacía |

---

## 📊 TABLA DE INCONSISTENCIAS

| ID | Severidad | Área | Síntoma | Causa Raíz | Evidencia | Impacto | Fix Sugerido |
|----|-----------|------|---------|------------|-----------|---------|--------------|
| **INC-001** | 🔴 CRITICAL | DB/Provisioning | `client_home_settings` tiene 0 rows | El upsert en provisioning (L608) puede no estar ejecutándose o fallando silenciosamente | Query: `SELECT count(*) FROM client_home_settings` → 0 rows | Storefront SIEMPRE usa tema default | Agregar logs/validación al upsert, verificar que se llame en TODOS los flujos |
| **INC-002** | 🔴 CRITICAL | DB Schema | Campo `template_id` vs `template_key` | Provisioning escribe a `clients.template_id`, pero HomeSettingsService lee `template_key` de otra tabla | `clients` tiene `template_id`, `client_home_settings` tiene `template_key` | Mapeo incorrecto | Unificar naming: decidir UNA fuente de verdad |
| **INC-003** | 🟠 HIGH | Storefront | `paletteKey` nunca llega al frontend | `clients` no tiene columna `palette_key`; solo existe en `nv_onboarding` y `client_home_settings` (vacía) | Query: `SELECT column_name FROM information_schema.columns WHERE table_name='clients'` → no hay palette_key | Paleta siempre es default | Agregar `palette_key` a `clients` o asegurar escritura a `client_home_settings` |
| **INC-004** | 🟠 HIGH | HomeSettingsService | Usa cliente de DB incorrecto como fallback | `HomeSettingsService` inyecta `SUPABASE_ADMIN_CLIENT` pero `client_home_settings` está en Backend DB | [home-settings.service.ts#L7](apps/api/src/home/home-settings.service.ts#L7) | Fallback falla silenciosamente | Cambiar a `SUPABASE_CLIENT` (Backend) o siempre pasar `cli` |
| **INC-005** | 🟠 HIGH | Preview/Render | Preview onboarding usa fuente diferente a storefront | Admin preview lee `nv_onboarding.selected_*`, storefront lee `client_home_settings` | Comparación de flujos en docs | Cliente ve una cosa en preview, otra en producción | Unificar fuente o sincronizar al publicar |
| **INC-006** | 🟡 MEDIUM | client_themes | Tabla `client_themes` (Admin DB) vacía | El flujo de provisioning debería escribir aquí pero no lo hace | Query: `SELECT count(*) FROM client_themes` → 0 rows | Theme overrides no persisten | Agregar paso en provisioning para sincronizar |
| **INC-007** | 🟡 MEDIUM | Naming | `templateKey` vs `template_key` vs `template_id` | Inconsistencia de naming entre frontend (camelCase) y backend (snake_case) | Múltiples archivos | Confusión, bugs potenciales | Definir convención y normalizar en mapper |
| **INC-008** | 🟡 MEDIUM | Fallbacks | Fallbacks ocultan errores | Cuando falla lectura, se usa default sin logging | `homeSettingsService.ts L37-40` | Bugs difíciles de debuggear | Agregar logs de WARNING cuando se usa fallback |

---

## 🔄 CHECKLIST DE REPRODUCCIÓN (Top 3 Issues)

### Reproducir INC-001 (client_home_settings vacía)

```bash
# 1. Conectar a Backend DB
export BACKEND_DB_URL="postgresql://postgres:***@db.ulndkhijxtxvpmbbfrgp.supabase.co:5432/postgres"
psql "$BACKEND_DB_URL"

# 2. Verificar que está vacía
SELECT count(*) FROM client_home_settings;
-- Resultado esperado: 0

# 3. Verificar que clients SÍ tiene datos
SELECT slug, template_id, theme_config IS NOT NULL FROM clients LIMIT 5;
-- Resultado: Hay datos

# 4. Verificar que el storefront lee de la tabla vacía
# En browser: Abrir DevTools → Network → Buscar /home/data
# Ver respuesta → config.templateKey será 'template_1' (default)
```

### Reproducir INC-002 (template_id vs template_key)

```bash
# 1. Ver schema de clients
psql "$BACKEND_DB_URL" -c "SELECT column_name FROM information_schema.columns WHERE table_name='clients' AND column_name LIKE 'template%';"
-- Resultado: template_id (NO template_key)

# 2. Ver código que lee
grep -n "template_key" apps/api/src/home/home-settings.service.ts
-- Línea 15: .select('template_key, palette_key, ...')

# 3. Ver código que escribe
grep -n "template_id" apps/api/src/worker/provisioning-worker.service.ts
-- Línea 599: template_id: onboarding.selected_template_key
```

### Reproducir INC-005 (Preview ≠ Storefront)

```bash
# 1. En Admin Dashboard, ir a onboarding de un cliente
# 2. Verificar datos guardados
export ADMIN_DB_URL="postgresql://postgres:***@db.erbfzlsznqsmwmjugspo.supabase.co:5432/postgres"
psql "$ADMIN_DB_URL" -c "SELECT selected_template_key, selected_palette_key FROM nv_onboarding WHERE account_id = '<UUID>';"
-- Resultado: 'fourth', 'starter_elegant' (ejemplo)

# 3. Ver qué recibe el storefront
curl -H "x-tenant-slug: <slug>" http://localhost:3000/home/data | jq '.data.config'
-- Resultado: templateKey='template_1' (default, no lo guardado)
```

---

## 🔒 NOTAS DE SEGURIDAD

| Item | Estado | Observación |
|------|--------|-------------|
| Service Role Keys en código | ✅ OK | No se encontraron hardcodeados |
| Secrets en commits | ✅ OK | `.env` está en `.gitignore` |
| `HomeSettingsService` fallback | ⚠️ REVISAR | El fallback a Admin Client podría leer datos incorrectos si existieran |
| DSN en logs | ✅ OK | No se detectaron connection strings en outputs |

---

## 📝 CONCLUSIÓN DEL INFORME

El sistema tiene **fragmentación de la fuente de verdad** para la configuración de tema:
- Onboarding guarda en `nv_onboarding` (Admin DB)
- Provisioning escribe parcialmente a `clients.template_id` (Backend DB) y falla/omite `client_home_settings`
- Storefront lee de `client_home_settings` (vacía) y usa fallbacks silenciosos

**Resultado:** Todas las tiendas muestran el tema default, independientemente de lo que el cliente configuró en onboarding.

**Decisión tomada:** `client_home_settings` será la **única fuente de verdad** para render del storefront.

---

---

# 📋 PLAN EN FASES (con DoD)

> **Fuente de verdad elegida:** `client_home_settings` (Backend DB)  
> **Principio:** El storefront SOLO lee de `client_home_settings`. Cualquier otra tabla es upstream.

---

## Fase 0: Documentar Contrato y Ownership

### Objetivo
Formalizar el contrato de `client_home_settings` como fuente única.

### Cambios Previstos
| Área | Cambio |
|------|--------|
| Docs | Crear `novavision-docs/architecture/config-source-of-truth.md` |
| DB | Ninguno (solo documentación) |

### DoD (Definition of Done)
- [ ] Documento `config-source-of-truth.md` creado con schema, owner, flujo
- [ ] README de `apps/api/src/home/` actualizado indicando que lee de `client_home_settings`
- [ ] Diagrama de flujo agregado a docs

### Query de Verificación
```sql
-- N/A para esta fase (solo docs)
```

### Riesgos + Mitigación
- Ningún riesgo técnico (solo documentación)

### Rollback
- N/A

---

## Fase 1: Corregir DB Client Ownership

### Objetivo
`HomeSettingsService` debe usar `SUPABASE_CLIENT` (Backend), no `SUPABASE_ADMIN_CLIENT`.

### Cambios Previstos
| Área | Archivo | Cambio |
|------|---------|--------|
| API | `src/home/home-settings.service.ts` | Cambiar inyección a `SUPABASE_CLIENT` |
| API | `src/home/home-settings.service.ts` | Agregar logs cuando se usa fallback |

### DoD
- [ ] `HomeSettingsService` inyecta `@Inject('SUPABASE_CLIENT')` en constructor
- [ ] Si fallback se activa, loggea `WARN: Using default settings for client ${clientId}`
- [ ] Test unitario: mock de `client_home_settings` vacío → verifica log de warning
- [ ] `npm run typecheck` pasa sin errores

### Query de Verificación
```bash
# Verificar que no hay imports de ADMIN_CLIENT en home-settings
grep -n "SUPABASE_ADMIN" apps/api/src/home/home-settings.service.ts
# Esperado: 0 resultados
```

### Riesgos + Mitigación
- **Riesgo:** Si hay otros métodos usando Admin client correctamente, se rompen
- **Mitigación:** Revisar todos los métodos del servicio antes de cambiar

### Rollback
```bash
git revert <commit-hash>
```

---

## Fase 2: Provisioning Escribe a client_home_settings

### Objetivo
El upsert a `client_home_settings` debe ejecutarse y completarse exitosamente.

### Cambios Previstos
| Área | Archivo | Cambio |
|------|---------|--------|
| API | `src/worker/provisioning-worker.service.ts` | Agregar logs antes/después del upsert |
| API | `src/worker/provisioning-worker.service.ts` | Validar que el upsert no tiene error silencioso |
| API | `src/worker/provisioning-worker.service.ts` | Agregar paso en `provisionClientFromOnboarding` |

### DoD
- [ ] Después de provisioning, `client_home_settings` tiene 1 row para el client
- [ ] Log muestra: `INFO: Upserted client_home_settings for client ${clientId}`
- [ ] Si error, log muestra: `ERROR: Failed to upsert client_home_settings: ${error}`
- [ ] Test de integración: crear cliente → provisioning → query `client_home_settings` → row existe

### Query de Verificación
```sql
-- Después de provisioning de un cliente nuevo
SELECT * FROM client_home_settings WHERE client_id = '<NEW_CLIENT_UUID>';
-- Esperado: 1 row con template_key, palette_key, etc.
```

### Riesgos + Mitigación
- **Riesgo:** Error silencioso en upsert por constraint faltante
- **Mitigación:** Agregar `RETURNING *` y validar resultado en código

### Rollback
```sql
-- Si hay datos incorrectos
DELETE FROM client_home_settings WHERE client_id = '<CLIENT_UUID>';
```

---

## Fase 3: Backfill de Clientes Existentes

### Objetivo
Poblar `client_home_settings` para todos los clientes que ya existen en `clients` pero no tienen row en `client_home_settings`.

### Cambios Previstos
| Área | Archivo | Cambio |
|------|---------|--------|
| Migrations | `migrations/backend/003_backfill_home_settings.sql` | Script idempotente |
| Scripts | `scripts/backfill-home-settings.ts` | Script ejecutable con dry-run |

### DoD
- [ ] Script de backfill ejecutado en dry-run → muestra N clientes a migrar
- [ ] Script ejecutado en modo real → 0 clientes sin config
- [ ] Query de verificación muestra 0 huérfanos
- [ ] Storefront de cliente backfilled muestra tema correcto

### Query de Verificación
```sql
-- Clientes sin config (debe ser 0 después de backfill)
SELECT c.id, c.slug 
FROM clients c 
LEFT JOIN client_home_settings chs ON c.id = chs.client_id
WHERE chs.id IS NULL AND c.publication_status = 'published';
-- Esperado: 0 rows
```

### Script de Backfill (idempotente)
```sql
INSERT INTO client_home_settings (client_id, template_key, palette_key, theme_config)
SELECT 
  c.id,
  COALESCE(c.template_id, 'first'),
  'starter_default',  -- No existe palette en clients, usar default
  COALESCE(c.theme_config, '{}'::jsonb)
FROM clients c
LEFT JOIN client_home_settings chs ON c.id = chs.client_id
WHERE chs.id IS NULL
ON CONFLICT (client_id) DO NOTHING;
```

### Riesgos + Mitigación
- **Riesgo:** Backfill pone valores incorrectos (palette default cuando debería ser otro)
- **Mitigación:** Primero hacer dry-run, revisar manualmente, luego ejecutar

### Rollback
```sql
-- Revertir backfill (solo si es necesario)
DELETE FROM client_home_settings 
WHERE created_at > '2026-02-04T00:00:00Z';
```

---

## Fase 4: Unificar Preview con Storefront

### Objetivo
El preview en Admin usa el mismo endpoint/config que el storefront publicado.

### Cambios Previstos
| Área | Archivo | Cambio |
|------|---------|--------|
| API | `src/storefront/storefront.controller.ts` | Agregar query param `?preview_token=X` |
| API | `src/storefront/storefront.assembler.ts` | Permitir leer tiendas draft si token válido |
| Admin | `src/components/OnboardingPreview.jsx` | Llamar a `/storefront/bootstrap?preview_token=X` |

### DoD
- [ ] Preview de tienda draft muestra template/palette de `nv_onboarding` (temporal)
- [ ] Preview de tienda publicada muestra template/palette de `client_home_settings`
- [ ] Token de preview tiene TTL de 1 hora
- [ ] Sin token válido, tiendas draft retornan 403

### Query de Verificación
```bash
# Tienda draft con token válido
curl -H "Authorization: Bearer <TOKEN>" \
  "http://localhost:3000/storefront/bootstrap?slug=test-store&preview_token=VALID"
# Esperado: 200 con config

# Tienda draft sin token
curl "http://localhost:3000/storefront/bootstrap?slug=test-store"
# Esperado: 403 o redirect a "Coming Soon"
```

### Riesgos + Mitigación
- **Riesgo:** Preview token filtrado permite ver tiendas privadas
- **Mitigación:** Tokens con scope por tienda, TTL corto, audit log

### Rollback
```bash
# Deshabilitar preview feature
export ENABLE_PREVIEW_TOKEN=false
```

---

## Fase 5: Guardrails y Observabilidad

### Objetivo
Detectar y bloquear inconsistencias antes de que lleguen a producción.

### Cambios Previstos
| Área | Archivo | Cambio |
|------|---------|--------|
| API | `src/health/health.controller.ts` | Agregar check de config consistency |
| API | `src/admin/approval.service.ts` | Validar que config existe antes de aprobar |
| Docs | `novavision-docs/runbooks/config-inconsistency.md` | Runbook de resolución |

### DoD
- [ ] Health check `/health/config` retorna lista de tiendas sin config
- [ ] Intento de publicar tienda sin `client_home_settings` row → error 400
- [ ] Log estructurado: `{"event": "publish_blocked", "reason": "missing_config", "clientId": "X"}`
- [ ] Runbook documentado

### Query de Verificación
```bash
# Health check
curl http://localhost:3000/health/config | jq '.orphanedStores'
# Esperado: []
```

### Riesgos + Mitigación
- **Riesgo:** Bloquear publicación de tiendas que funcionaban antes
- **Mitigación:** Primero solo WARN, luego cambiar a bloqueo

### Rollback
```bash
# Deshabilitar guardrail
export BLOCK_PUBLISH_WITHOUT_CONFIG=false
```

---

## 🧪 CASOS DE VALIDACIÓN OBLIGATORIOS

### Caso A: Tienda en Onboarding (Draft) → Preview

**Precondiciones:**
- Cliente creado en `nv_accounts` con estado `pending`
- `nv_onboarding` tiene `selected_template_key='fourth'`, `selected_palette_key='starter_elegant'`
- `client_home_settings` NO tiene row para este cliente (aún no aprobado)

**Acción:**
- Super admin abre preview en Admin Dashboard

**Resultado Esperado:**
- Preview muestra template `fourth` con palette `starter_elegant`
- Preview usa valores de `nv_onboarding` (fuente temporal para drafts)

**Query de Verificación:**
```sql
SELECT selected_template_key, selected_palette_key 
FROM nv_onboarding WHERE account_id = '<ACCOUNT_UUID>';
```

---

### Caso B: Aprobar/Publicar → Storefront Renderiza

**Precondiciones:**
- Cliente aprobado, `publication_status='published'`
- Provisioning completado

**Acción:**
- Usuario final visita `https://<slug>.novavision.com`

**Resultado Esperado:**
- Storefront muestra template `fourth` con palette `starter_elegant`
- Datos vienen de `client_home_settings` (no de `nv_onboarding`)

**Query de Verificación:**
```sql
SELECT template_key, palette_key 
FROM client_home_settings WHERE client_id = '<CLIENT_UUID>';
-- Debe coincidir con lo que ve el storefront
```

---

### Caso C: Falta Config → Sistema NO Falla Silencioso

**Precondiciones:**
- Cliente publicado PERO `client_home_settings` no tiene row (edge case/bug)

**Acción:**
- Usuario final visita storefront
- Admin intenta publicar otro cliente sin config

**Resultado Esperado:**
- Storefront: Muestra página de error o "Maintenance" (NO tema default sin aviso)
- API Log: `ERROR: Missing client_home_settings for published client ${clientId}`
- Admin: Publicación bloqueada con mensaje "Complete la configuración de tema primero"

**Query de Verificación:**
```sql
-- Esto NO debe existir después de Fase 5
SELECT c.slug 
FROM clients c 
LEFT JOIN client_home_settings chs ON c.id = chs.client_id
WHERE chs.id IS NULL AND c.publication_status = 'published';
```

---

---

# ✅ EXECUTION CHECKLIST (SIN EJECUTAR AÚN)

> **Estado:** Pendiente de aprobación del plan

## Pre-Ejecución
- [ ] Revisar y aprobar este informe
- [ ] Confirmar decisión: `client_home_settings` como fuente única
- [ ] Crear rama: `fix/theme-source-of-truth`
- [ ] Backup de DB de producción (si aplica)

## Fase 0 (Docs)
- [ ] Crear `novavision-docs/architecture/config-source-of-truth.md`
- [ ] Actualizar README de `apps/api/src/home/`
- [ ] Commit: `docs: define client_home_settings as single source of truth`

## Fase 1 (DB Client Fix)
- [ ] Modificar `home-settings.service.ts`: cambiar a `SUPABASE_CLIENT`
- [ ] Agregar logs de warning en fallback
- [ ] `npm run typecheck && npm run lint`
- [ ] Test unitario
- [ ] Commit: `fix(api): use backend client in HomeSettingsService`

## Fase 2 (Provisioning)
- [ ] Agregar logs al upsert de `client_home_settings`
- [ ] Agregar validación de resultado
- [ ] Test de integración
- [ ] Commit: `fix(api): ensure provisioning writes to client_home_settings`

## Fase 3 (Backfill)
- [ ] Crear script `backfill-home-settings.ts`
- [ ] Ejecutar en dry-run
- [ ] Revisar output
- [ ] Ejecutar en modo real
- [ ] Verificar query de huérfanos = 0
- [ ] Commit: `chore(migrations): backfill client_home_settings`

## Fase 4 (Preview)
- [ ] Implementar `preview_token` en storefront controller
- [ ] Actualizar Admin preview component
- [ ] Test visual preview vs producción
- [ ] Commit: `feat(api): add preview token for draft stores`

## Fase 5 (Guardrails)
- [ ] Implementar health check `/health/config`
- [ ] Agregar validación pre-publicación
- [ ] Crear runbook
- [ ] Commit: `feat(api): add config consistency guardrails`

## Post-Ejecución
- [ ] Verificar los 3 casos de validación (A, B, C)
- [ ] Monitorear logs por 24h
- [ ] Actualizar documentación de onboarding
- [ ] Cerrar tickets relacionados

---

## ⏭️ PRÓXIMOS PASOS INMEDIATOS

1. **Revisar este informe** y confirmar hallazgos
2. **Aprobar la decisión:** `client_home_settings` como fuente única
3. **Aprobar el plan** de 5 fases
4. **Dar OK** para comenzar con Fase 0 (solo docs)

---

**Este documento es solo INFORME y PLAN. Ningún cambio ha sido aplicado al repo ni a la DB.**
3. **Crear ticket** para Fase 1 (normalización)
4. **NO aplicar cambios** hasta tener plan aprobado

---

**Este documento es solo INFORME. Ningún cambio ha sido aplicado al repo ni a la DB.**
