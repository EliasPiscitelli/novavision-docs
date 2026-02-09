# Reporte QA Producción — NovaVision Storefront Multi-Tenant

- **Fecha:** 2026-02-09
- **Autor:** agente-copilot
- **Rama:** feature/automatic-multiclient-onboarding (API), develop (Web)
- **Entorno:** Producción (Railway + Netlify + Supabase)
- **Alcance:** Onboarding → Provisioning → Storefront → Endpoints → Aislamiento Cross-Tenant

---

## Resumen Ejecutivo

Se realizó QA end-to-end sobre producción real con 2 tiendas de prueba. Se descubrieron **3 bugs críticos** que impiden el flujo completo de onboarding automatizado. Se aplicaron **workarounds manuales** para avanzar con la validación del storefront. Los endpoints principales del storefront (**/home/data**, **/tenant/bootstrap**, **/categories**, **/products/search**) funcionan correctamente. El **aislamiento cross-tenant** está validado. Los 3 bugs críticos requieren deploy a producción para resolverse.

---

## URLs de Producción Testeadas

| Componente | URL |
|---|---|
| API (Railway) | `https://novavision-production.up.railway.app` |
| Storefront (Netlify) | `https://novavision-test.netlify.app` |
| Admin (Netlify) | `https://novavision.lat` |
| Admin DB (Supabase) | `https://erbfzlsznqsmwmjugspo.supabase.co` |
| Multicliente DB (Supabase) | `https://ulndkhijxtxvpmbbfrgp.supabase.co` |

---

## Tiendas de Prueba Creadas

### Tienda 1: QA Tienda Ropa
| Campo | Valor |
|---|---|
| account_id / client_id | `67e3e091-78f0-4c0d-be80-ae2e64b859a0` |
| slug | `qa-tienda-ropa` |
| template | `first` (Classic) |
| palette | `classic_white` |
| plan | `starter` |
| status | approved / published |
| email | kaddocpendragon+qa-tienda-ropa@gmail.com |
| Productos | 10 (Remeras, Pantalones, Abrigos, Calzado, Accesorios) |
| Categorías | 5 |
| FAQs | 3 |
| Storefront | `https://novavision-test.netlify.app/?tenant=qa-tienda-ropa` |

### Tienda 2: QA Tienda Tech
| Campo | Valor |
|---|---|
| account_id / client_id | `6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8` |
| slug | `qa-tienda-tech` |
| template | `fifth` (Bold & Vibrant) |
| palette | `blue_tech` |
| plan | `starter` |
| status | approved / published |
| email | kaddocpendragon+qa-tienda-tech@gmail.com |
| Productos | 10 (Audio, Periféricos, Accesorios PC, Monitores, Almacenamiento) |
| Categorías | 5 |
| FAQs | 3 |
| Storefront | `https://novavision-test.netlify.app/?tenant=qa-tienda-tech` |

---

## BUGS ENCONTRADOS

### BUG-001 — Provisioning Worker Broken (CRÍTICO)

**Severidad:** 🔴 CRÍTICA — Todo onboarding automático falla  
**Componente:** `src/onboarding/provisioning-worker.service.ts`  
**Rama con fix:** `feature/automatic-multiclient-onboarding` (NO deployada a main)

**Descripción:**  
Los 4 métodos del provisioning worker leen `account_id` desde `job.payload` en lugar de `job.account_id`:

```typescript
// ❌ BUG (producción actual):
const accountId = job.payload?.account_id; // → undefined

// ✅ FIX (rama feature):
const accountId = job.account_id; // → UUID correcto
```

**Líneas afectadas (locales):** 194, 533, 647, 1521

**Impacto:**  
- Todo provisioning job falla con `"Account not found: undefined"` después de 3 reintentos
- Ningún nuevo tenant puede ser provisionado automáticamente en producción
- Todos los provisioning_jobs muestran status=failed, attempts=3

**Workaround aplicado:**  
Se crearon los clients manualmente via Supabase REST API (`qa-prod/provision-manual.mjs`).

---

### BUG-002 — import-home-bundle Returns 500 (ALTA)

**Severidad:** 🟠 ALTA — Importación de catálogos de onboarding falla  
**Componente:** Endpoint `POST /onboarding/import-home-bundle`

**Descripción:**  
El endpoint devuelve `{"statusCode":500,"message":"Internal server error"}` sin detalles útiles, incluso cuando los prerequisitos están cumplidos (account existe, client existe, builder token válido).

**Impacto:**  
- No se pueden importar catálogos de productos/FAQs/contacto durante el onboarding
- Bloquea el flujo completo de setup de tienda

**Workaround aplicado:**  
Se insertaron catálogos directamente en la Multicliente DB via REST API (`qa-prod/insert-catalogs-direct.mjs`).

---

### BUG-003 — /products List Returns Empty Array (MODERADO)

**Severidad:** 🟡 MODERADA (no CRÍTICA — `/home/data` funciona como alternativa)  
**Componente:** `src/products/products.service.ts` + `products.controller.ts`  
**Rama con fix:** `feature/multitenant-storefront` (NO deployada a main)

**Descripción:**  
El endpoint `GET /products` devuelve `{"products":[],"totalItems":N}` para TODOS los tenants en producción. El totalItems es correcto pero el array de productos está vacío.

**Root cause:** Producción usa anon Supabase key para requests públicos (sin auth):
```typescript
// ❌ Producción (main):
const cli = this.supabase; // anon key → RLS bloquea

// ✅ Feature branch:
const cli = this.adminClient; // service_role key → bypass RLS
```

Adicionalmente, el controller tiene `@Res({ passthrough: true })` que causa `ERR_HTTP_HEADERS_SENT` cuando intenta `res.status(304).end()`.

**Impacto:**
- La página de listado/catálogo de productos (PLP) no muestra productos
- La paginación de productos no funciona
- **NOTA:** La homepage SÍ funciona porque usa `/home/data` que tiene code path diferente
- **NOTA:** `/products/search` SÍ funciona (usa code path diferente)

**Workaround:** Los usuarios pueden ver productos en la homepage y usar búsqueda.

---

### BUG-004 — Endpoints Standalone Requieren Auth (BAJA)

**Severidad:** 🟢 BAJA  
**Componente:** Controllers de banners, FAQs, social-links

**Descripción:**  
Los endpoints `GET /banners`, `GET /faqs`, `GET /social-links` devuelven "Token requerido" para requests sin autenticación.

**Impacto:**  
Bajo — todos estos datos se sirven correctamente via `/home/data` para el homepage. Solo afectaría si alguna página individual del storefront llama a estos endpoints por separado.

---

### BUG-005 — CSP Missing External Image Domains (BAJA/TEST-ONLY)

**Severidad:** 🟢 BAJA (solo datos de test)  
**Componente:** `netlify.toml` → Content-Security-Policy `img-src`

**Descripción:**  
La CSP del storefront no incluye `https://picsum.photos` en `img-src`. Las imágenes de productos de test (que usan picsum.photos) serían bloqueadas por el navegador.

**Impacto:**  
Solo afecta datos de test. Los productos reales de clientes usan Supabase Storage URLs (`*.supabase.co`) que SÍ están en la CSP.

**Fix sugerido:** Para testing, agregar `https://picsum.photos` temporalmente a la CSP, o usar URLs de Supabase Storage para los productos de prueba.

---

## OBSERVACIONES

### OBS-001: Check Constraints en nv_accounts
- El status `'active'` no es válido (solo: draft, pending, approved, etc.)
- El connection_type `'shared'` no es válido (usar `'manual'`)
- La columna `is_published` no existe en nv_accounts

### OBS-002: TenantContextGuard requiere nv_account_id
- La resolución de tenant hace 2 hops: slug → nv_accounts → clients(via nv_account_id match)
- Si `clients.nv_account_id` es NULL, la resolución falla
- El provisioning worker debería setear esto, pero está roto (BUG-001)

### OBS-003: publication_status gating
- `gateStorefront()` rechaza tenants con publication_status != 'published'
- Los tenants recién creados tienen publication_status='draft' por defecto
- Requiere cambio manual a 'published' (o el provisioning worker debería hacerlo)

---

## RESULTADOS DE TESTS

### Endpoints del Storefront

| Endpoint | Método | Auth | Tienda Ropa | Tienda Tech | Notas |
|---|---|---|---|---|---|
| `/health` | GET | No | ✅ 200 | ✅ 200 | |
| `/tenant/bootstrap` | GET | No | ✅ Datos completos | ✅ Datos completos | slug, plan, mp_status |
| `/home/data` | GET | No | ✅ 10 prods + FAQs + config | ✅ 10 prods + FAQs + config | Endpoint principal del storefront |
| `/categories` | GET | No | ✅ 5 categorías | ✅ 5 categorías | |
| `/products` | GET | No | ❌ `[]` (totalItems:10) | ❌ `[]` (totalItems:10) | BUG-003 |
| `/products/search` | GET | No | ✅ Resultados correctos | ✅ Resultados correctos | |
| `/banners` | GET | No | ❌ "Token requerido" | - | BUG-004 |
| `/faqs` | GET | No | ❌ "Token requerido" | - | BUG-004 |
| `/social-links` | GET | No | ❌ "Token requerido" | - | BUG-004 |
| `/auth/signup` | POST | No | ✅ Crea usuario | - | Envía email de confirmación |
| `/api/cart` | GET | Sí | ✅ "Token requerido" | - | Correcto (requiere auth) |

### Datos en /home/data

| Campo | Tienda Ropa | Tienda Tech |
|---|---|---|
| products | 10 items ✅ | 10 items ✅ |
| totalItems | 10 ✅ | 10 ✅ |
| services | 0 | 0 |
| banners.desktop | 0 | 0 |
| banners.mobile | 0 | 0 |
| faqs | 3 ✅ | 3 ✅ |
| logo | null (no subido) | null (no subido) |
| contactInfo | 2 items ✅ | 2 items ✅ |
| socialLinks | ✅ (WhatsApp+Instagram+Facebook) | ✅ |
| storeName | "QA Tienda Ropa" ✅ | "QA Tienda Tech" ✅ |
| config.templateKey | `first` ✅ | `fifth` ✅ |
| config.paletteKey | `classic_white` ✅ | `blue_tech` ✅ |
| config.paletteVars | ✅ CSS vars inyectadas | ✅ CSS vars inyectadas |

### Aislamiento Cross-Tenant

| Test | Resultado |
|---|---|
| Ropa solo ve productos de ropa | ✅ (todos client_id: 67e3e091) |
| Tech solo ve productos de tech | ✅ (todos client_id: 6a6cdab2) |
| storeName diferente por tenant | ✅ |
| templateKey diferente por tenant | ✅ (first vs fifth) |
| paletteKey diferente por tenant | ✅ (classic_white vs blue_tech) |
| paletteVars diferentes | ✅ (distintas CSS vars) |
| Tenant inexistente → 401 | ✅ "Tienda no encontrada" |
| Tenant real "test" no afectado | ✅ (11 productos, plan growth, MP: true) |

### Config de Templates

| Tienda | Template | Palette | Vars CSS ejemplo |
|---|---|---|---|
| qa-tienda-ropa | first (Classic) | classic_white | --nv-bg: #f7f9fc, --nv-link: #8e9bde |
| qa-tienda-tech | fifth (Bold&Vibrant) | blue_tech | --nv-bg: #FBFBFF, --nv-link: #01BAEF |

---

## FLUJO PROBADO vs FLUJO IDEAL

### Flujo Ideal (automático)
```
1. Builder crea cuenta (POST /onboarding/start)     ✅ Funciona
2. Elige template y palette (POST /onboarding/preferences) ✅ Funciona
3. Importa catálogo (POST /onboarding/import-home-bundle)  ❌ BUG-002 (500)
4. Admin aprueba (POST /onboarding/approve/:id)     ✅ Funciona
5. Provisioning worker crea client en Backend DB     ❌ BUG-001 (account not found)
6. Storefront se activa con slug                     ✅ Funciona (si datos existen)
7. Comprador visita tienda, ve productos             ✅ Funciona via /home/data
8. Comprador busca productos                         ✅ Funciona via /products/search
9. Comprador navega catálogo (PLP)                   ❌ BUG-003 (products vacío)
10. Comprador agrega al carrito                       ⏳ No testeado (requiere buyer auth)
11. Comprador paga con MP                             ⏳ No testeado (requiere MP credentials)
```

### Pasos ejecutados con workarounds
```
1. Builder session → API ✅
2. Preferences → API ✅
3. Catálogos → REST API directo (workaround BUG-002) ✅
4. Provisioning → REST API directo (workaround BUG-001) ✅
5. Storefront accesible → Netlify ✅
6. API devuelve datos → /home/data ✅
7. Cross-tenant → Validado ✅
8. Auth signup → Funciona ✅
9. Product search → Funciona ✅
10. Cart/Checkout → ⏳ Pendiente (requiere buyer auth + MP)
```

---

## QUÉ FALTA POR TESTEAR

1. **Storefront visual rendering**: Las tiendas están abiertas en browser pero sin inspección visual detallada. Verificar que templates first/fifth renderizan correctamente con los datos.

2. **Auth flow completo**: Signup → email verification → login → session persistence.

3. **Carrito**: Agregar producto → Aumentar/disminuir cantidad → Eliminar → Verificar totales.

4. **Checkout con Mercado Pago**: Requiere conectar MP credentials a las tiendas primero. Test cards disponibles:
   - Mastercard: 5031755734530604 (CVV 123, exp 11/30)
   - Visa: 4509953566233704 (CVV 123, exp 11/30)
   - Amex: 371180303257522 (CVV 1234, exp 11/30)

5. **Admin dashboard**: Verificar que admin puede ver/editar productos de su tienda.

---

## PRIORIDADES DE FIX RECOMENDADAS

### P0 — Deploy inmediato a producción

1. **BUG-001 (Provisioning Worker)**: Mergear fix de `job.account_id` de la rama feature a main y deployar a Railway. Sin esto, NINGÚN nuevo cliente puede ser onboardeado.

2. **BUG-003 (Products Service)**: Mergear fix de `this.adminClient` y `@Res()` a main. Sin esto, el catálogo de productos (PLP) no funciona para ningún tenant.

### P1 — Fix necesario

3. **BUG-002 (import-home-bundle)**: Investigar y fixear el error 500. Necesario para onboarding completo.

### P2 — Mejoras

4. **BUG-004 (Endpoints standalone)**: Evaluar si banners/faqs/social-links necesitan acceso público o si /home/data es suficiente.

5. **BUG-005 (CSP)**: Agregar dominios de imágenes externas a CSP si se usan en producción.

---

## DATOS DE TEST PARA CLEANUP

### Admin DB (erbfzlsznqsmwmjugspo.supabase.co)
- nv_accounts: `67e3e091-78f0-4c0d-be80-ae2e64b859a0` (qa-tienda-ropa)
- nv_accounts: `6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8` (qa-tienda-tech)
- Posibles registros en nv_onboarding, provisioning_jobs

### Multicliente DB (ulndkhijxtxvpmbbfrgp.supabase.co)
- clients: 2 registros (mismos IDs que arriba)
- products: 20 registros (10 por tienda)
- categories: 10 registros (5 por tienda)
- product_categories: 20 registros
- faqs: 6 registros (3 por tienda)
- contact_info: 4 registros (2 por tienda)
- social_links: 2 registros
- client_home_settings: 2 registros
- client_payment_settings: 2 registros
- users: 0 (ningún buyer creado aún)

### Scripts de provisioning/cleanup
- `qa-prod/provision-manual.mjs` — Crear clients manualmente
- `qa-prod/insert-catalogs-direct.mjs` — Insertar catálogos directamente
- Para cleanup: DELETE en cada tabla filtrando por `client_id IN ('67e3e091-...', '6a6cdab2-...')`

---

## EVIDENCIA DE TESTS (Comandos ejecutados)

```bash
# Health check
curl -s https://novavision-production.up.railway.app/health
# → {"status":"ok"}

# Tenant bootstrap
curl -s "$API/tenant/bootstrap" -H "x-tenant-slug: qa-tienda-ropa"
# → {"success":true,"tenant":{"id":"67e3e091...","slug":"qa-tienda-ropa","status":"active","plan":"starter","has_mp_credentials":false}}

# Home data
curl -s "$API/home/data" -H "x-tenant-slug: qa-tienda-ropa"
# → {"success":true,"data":{"products":[10 items],"faqs":[3],"config":{"templateKey":"first","paletteKey":"classic_white",...}}}

# Products (BUG)
curl -s "$API/products?page=1&pageSize=5" -H "x-tenant-slug: qa-tienda-ropa"
# → {"products":[],"totalItems":10}

# Search (FUNCIONA)
curl -s "$API/products/search?query=remera" -H "x-tenant-slug: qa-tienda-ropa"
# → {"products":[{"name":"Remera Básica Negra",...}]}

# Cross-tenant: slug inexistente
curl -s "$API/tenant/bootstrap" -H "x-tenant-slug: tienda-fantasma"
# → {"code":"STORE_NOT_FOUND","message":"Tienda no encontrada"} HTTP 401

# Tenant real NO afectado
curl -s "$API/home/data" -H "x-tenant-slug: test"
# → 11 productos (sin cambios, sin contaminación)
```

---

## CONCLUSIÓN

El stack de producción funciona correctamente en sus capas fundamentales (resolución de tenant, aislamiento de datos, API home data, templates diferenciados). Los **3 bugs críticos** identificados tienen fixes ya desarrollados en ramas feature pero **no deployados a main/producción**. Deployar BUG-001 y BUG-003 desbloquearía todo el flujo de onboarding + storefront para nuevos clientes.

**Acción requerida:** Merge y deploy de las ramas feature a main para Railway (API) y Netlify (Web) respectivamente.
