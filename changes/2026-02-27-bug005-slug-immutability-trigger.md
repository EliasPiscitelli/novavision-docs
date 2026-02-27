# BUG-005: Slug Immutability Trigger — Corrección y Blindaje

- **Autor:** agente-copilot
- **Fecha:** 2026-02-27
- **Rama API:** feature/automatic-multiclient-onboarding
- **Archivos modificados:**
  - `migrations/admin/ADMIN_060_slug_immutability_trigger.sql`
  - `src/worker/provisioning-worker.service.ts`
  - `src/admin/admin.service.ts`

---

## Resumen

Se corrigió el trigger de inmutabilidad de slug (`ADMIN_060`) que tenía un **bug crítico**: bloqueaba cambios de slug para TODOS los estados excepto `draft`/`awaiting_payment`, pero el sistema legítimamente modifica el slug en estados posteriores:

| Punto del código | Estado al momento | ¿Bloqueado por v1? |
|---|---|---|
| `finalizeSlugClaim()` (webhook MP) | `paid` (status ya cambió L1125) | ❌ **SÍ — BUG** |
| Provisioning worker (L808) | `paid` | ❌ **SÍ — BUG** |
| `approveClient()` (L1778) | `provisioned`/`pending_approval` | ❌ **SÍ — BUG** |
| `submitForReview()` slug promotion (L2343) | Varía | ❌ **SÍ — BUG** |

## Cambios

### 1. Trigger ADMIN_060 — Rediseño de estados bloqueados

**Antes (v1):** Bloqueaba en todos los estados excepto `draft`, `awaiting_payment`
**Ahora (v2):** Bloquea SOLO en estados donde la tienda está publicada/accesible:

```sql
-- v2: Bloquea solo estados post-publicación
AND OLD.status IN ('approved', 'live', 'suspended')
```

**Rationale:** En `approved`/`live`/`suspended` el DNS, storage paths y URLs externas dependen del slug. En estados pre-lanzamiento (`draft` → `paid` → `provisioned` → `pending_approval`) el sistema necesita flexibilidad.

### 2. Provisioning Worker — Slug condicional

Solo incluye `slug` en el UPDATE si realmente difiere del actual. En el flujo normal, `claim_slug_final` ya resolvió el slug durante el webhook de pago, así que son iguales.

### 3. Admin Service — approveClient slug condicional

Solo incluye `slug` en el UPDATE de aprobación si difiere del slug actual. Evita activar el trigger innecesariamente.

## Cómo probar

### Pre-requisito: Aplicar la migración
```sql
-- En Supabase Admin DB → SQL Editor
-- Copiar contenido de migrations/admin/ADMIN_060_slug_immutability_trigger.sql
```

### Caso 1: Slug bloqueado en estado `approved`
```sql
-- Simular un cambio manual en estado approved
UPDATE nv_accounts SET slug = 'otro-slug' WHERE status = 'approved';
-- Esperado: ERROR P0001 "Cannot change slug for published store..."
```

### Caso 2: Slug permitido en estado `paid`
```sql
-- Simular claim_slug_final en estado paid (flow normal)
UPDATE nv_accounts SET slug = 'mi-slug-final' WHERE status = 'paid' AND slug LIKE 'draft-%';
-- Esperado: UPDATE 1 (éxito)
```

### Caso 3: Slug sin cambio no dispara trigger
```sql
-- Mismo slug = trigger no interviene
UPDATE nv_accounts SET status = 'provisioned', slug = slug WHERE status = 'paid';
-- Esperado: UPDATE 1 (éxito, slug no cambió)
```

## Riesgos

- **Bajo:** La migración es idempotente (`CREATE OR REPLACE` + `DROP TRIGGER IF EXISTS`).
- **Ninguno en producción:** No hay tiendas en estado `approved`/`live`/`suspended` aún (pre-lanzamiento).
- **Protección real:** Una vez que una tienda está live, el slug queda inmutable. Si se requiere cambio post-publicación, el error guía al admin a suspender primero y coordinar migración DNS/storage.

## Notas de seguridad

- El trigger opera a nivel DB, protegiendocontra edits directos en Supabase Dashboard o via cualquier cliente.
- La protección es "defense in depth" — complementa validaciones a nivel de aplicación.
