# Casos de Prueba — Component Catalog + Token Pricing Variable
> NovaVision · Fecha: 2026-03-18 · Estado: Post-implementación

---

## Convenciones

| Símbolo | Significado |
|---------|-------------|
| ✅ | Happy path — resultado esperado exitoso |
| ❌ | Resultado esperado de error/rechazo |
| ⚠️ | Edge case — comportamiento sutil o crítico |
| 🔒 | Aislamiento multi-tenant |
| 🔁 | Concurrencia / race condition |
| 💸 | Impacto económico / billing |
| 🔄 | Sincronización entre repos / fuente de verdad |

---

## SECCIÓN 1 — Tabla `component_catalog`: Integridad de Datos

### TC-01 · Seed inicial cubre todas las variantes del VARIANT_REGISTRY ✅
**Acción:** `SELECT COUNT(*) FROM component_catalog`.
**Esperado:** ≥ 70 rows (equivalente a las variantes del `VARIANT_REGISTRY` anterior).
**Validar también:** Ningún `component_key` del antiguo `VARIANT_REGISTRY` está ausente en la tabla.

---

### TC-02 · `component_key` es único y actúa como PK ❌
**Acción:** Intentar insertar un segundo row con `component_key = 'hero.first'`.
**Esperado:** Violación de PK — error de BD. No se inserta el duplicado.

---

### TC-03 · `updated_at` se actualiza automáticamente por trigger ✅
**Acción:** `UPDATE component_catalog SET token_cost = 2 WHERE component_key = 'hero.first'`.
**Esperado:** `updated_at` cambia al timestamp del UPDATE. `created_at` permanece intacto.

---

### TC-04 · `token_cost` no puede ser negativo ni cero ❌
**Acción:** `UPDATE component_catalog SET token_cost = 0 WHERE component_key = 'hero.first'`.
**Esperado:** Error de constraint (CHECK `token_cost > 0`) o validación en el service antes de persistir. Token cost de 0 permitiría uso gratuito ilimitado, quebrando el modelo de negocio.

---

### TC-05 · `min_plan` solo acepta valores válidos ❌
**Acción:** `UPDATE component_catalog SET min_plan = 'ultra' WHERE component_key = 'hero.first'`.
**Esperado:** Error de constraint (CHECK `min_plan IN ('starter', 'growth', 'enterprise')`) o validación en `PATCH /admin/components/:key`.

---

### TC-06 · RLS: lectura pública solo retorna `is_active = true` ✅
**Precondición:** Setear `is_active = false` en `component_key = 'hero.video.background'`.
**Acción:** `GET /components/catalog` (sin auth de super-admin).
**Esperado:** El response NO incluye `hero.video.background`. Solo componentes activos.

---

### TC-07 · RLS: endpoint admin retorna activos e inactivos ✅
**Acción:** `GET /admin/components/catalog` (con JWT super-admin).
**Esperado:** El response incluye `hero.video.background` con `is_active: false`.

---

## SECCIÓN 2 — Endpoints: `/components/catalog` y `/admin/components/catalog`

### TC-08 · Endpoint público no requiere tenant ni auth ✅
**Acción:** `GET /components/catalog` sin headers `x-tenant-slug` ni `Authorization`.
**Esperado:** HTTP 200 con el catálogo. No aplica `TenantContextGuard`. El endpoint está excluido de `AuthMiddleware`.

---

### TC-09 · Response incluye todos los campos necesarios ✅
**Acción:** `GET /components/catalog`.
**Esperado:** Cada item del array contiene al menos: `component_key`, `label`, `type`, `category`, `min_plan`, `token_cost`, `is_active`, `sort_order`.

---

### TC-10 · Endpoint público respeta `sort_order` ✅
**Precondición:** Setear `sort_order = 10` para `hero.first`, `sort_order = 1` para `banner.simple`.
**Acción:** `GET /components/catalog`.
**Esperado:** `banner.simple` aparece antes que `hero.first` en el array.

---

### TC-11 · `PATCH /admin/components/:key` rechaza keys inexistentes ❌
**Acción:** `PATCH /admin/components/hero.inexistente` con `{ token_cost: 5 }`.
**Esperado:** HTTP 404. No se crea un nuevo registro.

---

### TC-12 · `PATCH` actualiza solo los campos enviados (partial update) ✅
**Precondición:** `component_key = 'hero.first'` con `token_cost = 1`, `min_plan = 'starter'`, `is_active = true`.
**Acción:** `PATCH /admin/components/hero.first` con `{ token_cost: 2 }`.
**Esperado:** `token_cost = 2`, `min_plan` y `is_active` sin cambios.

---

### TC-13 · `PATCH` requiere autenticación super-admin ❌
**Acción:** `PATCH /admin/components/hero.first` con JWT de tenant (no super-admin).
**Esperado:** HTTP 401 o 403.

---

### TC-14 · `GET /components/catalog` es cacheable / sin variación por tenant 🔄
**Validar:** El endpoint devuelve el mismo catálogo para cualquier `x-tenant-slug`. El catálogo es global, no por tenant.

---

## SECCIÓN 3 — Token Cost Variable: consumo en `replaceSection`

### TC-15 · `replaceSection` lee `token_cost` del componente destino ✅
**Precondición:** `token_cost = 3` para `hero.video.background`.
**Acción:** Tenant llama `replaceSection` para reemplazar su hero con `hero.video.background`.
**Esperado:** Se debitan 3 créditos. Row en ledger: `credits_delta = -3`.

---

### TC-16 · `replaceSection` con componente de 1 token débita 1 ✅
**Precondición:** `token_cost = 1` para `hero.first`.
**Acción:** `replaceSection` con `hero.first`.
**Esperado:** `credits_delta = -1`.

---

### TC-17 · Cambio de `token_cost` en admin impacta el próximo `replaceSection` ⚠️
**Precondición:** `token_cost = 1` para `banner.simple`. Tenant tiene balance = 1.
**Acción 1:** Super-admin cambia `token_cost = 2` vía `PATCH /admin/components/banner.simple`.
**Acción 2:** Tenant intenta `replaceSection` con `banner.simple`.
**Esperado:** HTTP 402 — requiere 2 créditos, disponibles 1. Confirma que `home.controller` lee `token_cost` en runtime desde BD, no desde caché stale.

---

### TC-18 · `replaceSection` con componente inexistente en catálogo ⚠️
**Precondición:** `component_key = 'hero.fantasma'` no existe en `component_catalog`.
**Acción:** `replaceSection` con `target_key = 'hero.fantasma'`.
**Esperado:** HTTP 400 o 422 — clave desconocida. No se debita crédito. No se modifica la configuración de la tienda.

---

### TC-19 · `replaceSection` con componente inactivo ❌
**Precondición:** `is_active = false` para `hero.video.background`.
**Acción:** `replaceSection` con `hero.video.background`.
**Esperado:** HTTP 403 o 422 — componente no disponible. No se debita crédito.

---

### TC-20 · Sin créditos suficientes para el token_cost → 402 con payload completo ❌
**Precondición:** Balance `component_change` = 1, `token_cost` del componente destino = 3.
**Acción:** `replaceSection`.
**Esperado HTTP 402:**
```json
{
  "error": "insufficient_storefront_credits",
  "required": 3,
  "available": 1
}
```
Balance intacto. Sección de la tienda sin cambios.

---

### TC-21 · Reemplazar componente por el mismo no consume créditos ⚠️
**Escenario:** La sección ya usa `hero.first` y el usuario aplica `hero.first` nuevamente.
**Esperado:** El sistema detecta que no hay cambio real → no llama a `replaceSection` o no débita crédito. Depende del diseño: si el frontend filtra esto, el backend tampoco debe cobrar.

---

### TC-22 · `addSection` usa `token_cost` del nuevo componente ✅
**Precondición:** Agregar `banner.simple` (token_cost = 1).
**Esperado:** `credits_delta = -1`. Análogo a `replaceSection`.

---

### TC-23 · Múltiples cambios en un mismo `buildStructureActionPlan` suman token costs ✅
**Escenario:** Plan con 3 acciones: add `hero.video.background` (3 tokens) + replace `banner.simple` (1 token) + add `features.grid` (2 tokens).
**Esperado:** `totalTokenCost = 6`. Si balance = 5 → bloqueado. Si balance = 6 → permitido.

---

### TC-24 · Débito atómico — si una acción del plan falla, no se cobra parcialmente ⚠️
**Escenario:** Plan de 3 acciones. La tercera acción falla por error interno.
**Esperado:** Las 3 acciones se revierten (rollback). Ningún crédito debitado. Sección de la tienda sin cambios.
**Alternativa aceptable:** Transacción por acción individual con compensación (saga), pero documentado.

---

## SECCIÓN 4 — Onboarding: Exploración Libre y Validación en Checkout

### TC-25 · Step4 muestra todos los componentes sin bloqueo de plan ✅
**Precondición:** Usuario en onboarding con plan `starter`.
**Acción:** Cargar Step4TemplateSelector.
**Esperado:** Componentes de plan `growth` y `enterprise` son visibles y arrastrables. NO hay bloqueo de inserción. Solo se muestra aviso informativo: "Requiere plan Growth. Se validará al pagar."

---

### TC-26 · Aviso informativo en Step4 es no bloqueante ✅
**Acción:** Arrastrar componente `enterprise` al canvas en Step4 (cuenta `starter`).
**Esperado:** El componente se inserta en `design_config`. No aparece modal de error ni bloqueo. Solo badge/tooltip informativo.

---

### TC-27 · `startCheckout` con design_config compatible → OK ✅
**Precondición:** Cuenta `starter`. `design_config.sections` contiene solo componentes `min_plan = 'starter'`.
**Acción:** `startCheckout` en onboarding.
**Esperado:** Pasa validación. `minRequiredPlan` no se incrementa. Checkout continúa normalmente.

---

### TC-28 · `startCheckout` con componente `growth` en cuenta `starter` → PLAN_INCOMPATIBLE ❌
**Precondición:** Cuenta `starter`. `design_config.sections` contiene `hero.video.background` (`min_plan = 'growth'`).
**Acción:** `startCheckout`.
**Esperado:** HTTP 400 con `error: 'PLAN_INCOMPATIBLE'`. Mensaje indica qué componente requiere qué plan.
**Validar:** El error incluye suficiente info para que el frontend muestre el prompt de upgrade.

---

### TC-29 · `startCheckout` con componente `enterprise` en cuenta `growth` → PLAN_INCOMPATIBLE ❌
**Precondición:** Cuenta `growth`. `design_config.sections` contiene componente `min_plan = 'enterprise'`.
**Esperado:** HTTP 400 con `PLAN_INCOMPATIBLE`. El seller debe hacer upgrade a enterprise o reemplazar el componente.

---

### TC-30 · `startCheckout` con componente `growth` en cuenta `growth` → OK ✅
**Precondición:** Cuenta `growth`. Todos los componentes tienen `min_plan` ≤ `growth`.
**Esperado:** Validación pasa. Sin error.

---

### TC-31 · `startCheckout` valida contra BD, no contra SECTION_CATALOG hardcodeado 🔄
**Precondición:** Cambiar `min_plan` de `hero.video.background` de `growth` a `starter` vía `PATCH /admin/components`.
**Acción:** `startCheckout` de una cuenta `starter` con ese componente.
**Esperado:** Validación pasa (el componente ya no requiere growth). Confirma que `onboarding.service` consulta `component_catalog` en BD, no el enum local.

---

### TC-32 · `startCheckout` con `design_config.sections` vacío → OK ✅
**Escenario:** Usuario completó onboarding sin customizar el diseño.
**Esperado:** Validación pasa. No hay componentes que evaluar.

---

### TC-33 · `startCheckout` con component_key desconocido en design_config ⚠️
**Escenario:** `design_config.sections` contiene una key que no existe en `component_catalog`.
**Esperado:** El servicio ignora la key desconocida (comportamiento permisivo) O lanza error de validación. Documentar cuál es la decisión de diseño y verificar que se cumpla consistentemente.

---

### TC-34 · Cambiar `min_plan` de un componente en BD afecta el próximo checkout ⚠️
**Precondición:** Cuenta `starter` con `hero.video.background` (`min_plan = 'growth'`) → checkout falla con PLAN_INCOMPATIBLE.
**Acción:** Super-admin cambia `min_plan = 'starter'` para ese componente.
**Acción:** Retry `startCheckout`.
**Esperado:** Checkout pasa. Confirma que no hay caché de `min_plan` en el servicio de onboarding.

---

## SECCIÓN 5 — Provisioning: Créditos Iniciales por Plan

### TC-35 · Grant inicial `component_change` post-provisioning ✅
**Acción:** Correr provisioning completo para cuenta nueva.
**Esperado:** Balance `component_change`:
- Starter → 2 créditos
- Growth → 5 créditos
- Enterprise → 15 créditos

**Validar en ledger:** Row con `credits_delta > 0`, `action_code = 'component_change'` (o el action code equivalente).

---

### TC-36 · Step de grant aparece en `provisioning_job_steps` con status `completed` ✅
**Validar:**
```sql
SELECT step_name, status FROM provisioning_job_steps
WHERE job_id = :jobId ORDER BY created_at;
```
El step de créditos iniciales existe y tiene `status = 'completed'`.

---

### TC-37 · Re-ejecución del step no duplica el grant 🔁
**Escenario:** El step de grant de créditos iniciales se ejecuta dos veces (retry por fallo upstream).
**Esperado:** Balance final = créditos de 1 sola ejecución. Idempotencia garantizada.

---

### TC-38 · Grant inicial no bloquea si `component_change` ya tiene créditos previos ✅
**Escenario:** Por algún motivo el tenant ya tiene 1 crédito de `component_change` antes del step.
**Esperado:** El grant acumula (balance = 1 + grant_amount). No reemplaza ni revoca los existentes.

---

## SECCIÓN 6 — Admin DesignSystemView

### TC-39 · ComponentManager carga desde `GET /admin/components/catalog` ✅
**Acción:** Navegar a Admin Dashboard > Sistema de Diseño > Componentes.
**Esperado:** La tabla se puebla desde la API. No hay referencias a `DEFAULT_COMPONENTS` ni `localStorage`.
**Verificar en Network:** Request a `/admin/components/catalog` exitoso.

---

### TC-40 · localStorage `DEFAULT_COMPONENTS` eliminado ✅
**Acción:** Abrir DevTools > Application > localStorage tras cargar DesignSystemView.
**Esperado:** Ninguna key relacionada con `DEFAULT_COMPONENTS` en localStorage.

---

### TC-41 · Edición de `min_plan` desde DesignSystemView persiste en BD ✅
**Acción:** Cambiar `min_plan` de `hero.first` de `starter` a `growth` en el UI.
**Esperado:** `PATCH /admin/components/hero.first` enviado. Recargar la vista → `min_plan` muestra `growth`. Verificar en BD.

---

### TC-42 · Edición de `token_cost` persiste y actualiza badge visual ✅
**Acción:** Cambiar `token_cost` de `hero.video.background` de `3` a `5`.
**Esperado:** `PATCH` exitoso. Badge en la UI muestra "5tk". Próxima consulta a `GET /components/catalog` retorna `token_cost: 5`.

---

### TC-43 · Input de `token_cost` solo acepta enteros positivos ❌
**Acción:** Intentar ingresar `0`, `-1`, `1.5` o texto en el input de token_cost.
**Esperado:** Validación en frontend rechaza el valor antes de enviar el PATCH. O el backend retorna 400.

---

### TC-44 · Stats del DesignSystemView son consistentes con BD ✅
**Esperado:** Los contadores "total", "por plan" y "token cost promedio" calculados desde los datos de la API, no hardcodeados.
**Validar:** Cambiar `min_plan` de un componente → stats se actualizan en el próximo fetch.

---

### TC-45 · Toggle `is_active` desde DesignSystemView persiste ✅
**Acción:** Desactivar `hero.video.background` desde el UI.
**Esperado:** `PATCH` enviado con `{ is_active: false }`. Refrescar → componente aparece con indicador de inactivo. `GET /components/catalog` (público) ya no lo incluye.

---

## SECCIÓN 7 — Web DesignStudio: Token Display y Cálculo

### TC-46 · DesignStudio fetches `/components/catalog` al montar ✅
**Acción:** Navegar al DesignStudio.
**Esperado:** Request a `GET /components/catalog` en Network tab. `componentCatalogMap` construido como índice por `component_key`.

---

### TC-47 · Badges de token cost muestran valor correcto por componente ✅
**Precondición:** `token_cost = 1` para `hero.first`, `token_cost = 3` para `hero.video.background`.
**Esperado:** `hero.first` muestra badge "1tk" (verde), `hero.video.background` muestra "3tk" (rojo).

---

### TC-48 · Colores semafóricos de badges según token_cost ✅
**Esquema esperado:**
- `token_cost = 1` → verde
- `token_cost = 2` → amarillo
- `token_cost = 3+` → rojo

**Validar:** Cambiar `token_cost` vía admin → recargar DesignStudio → color del badge refleja el nuevo valor.

---

### TC-49 · `totalTokenCost` calcula correctamente para múltiples acciones ✅
**Escenario:** Plan de acción: reemplazar hero (2tk) + agregar banner (1tk) + agregar features (2tk).
**Esperado:** `totalTokenCost = 5`. El UI muestra "5 tokens necesarios".

---

### TC-50 · `missingStructureCredits` usa `totalTokenCost`, no `totalActions` ✅
**Precondición:** Balance `component_change` = 3. Plan de acción: 2 cambios con `totalTokenCost = 5`.
**Esperado:** `missingStructureCredits = 2` (5 - 3). NO `missingStructureCredits = -1` (2 acciones - 3 balance). El cálculo es por tokens, no por cantidad de acciones.

---

### TC-51 · Bloqueo correcto cuando `totalTokenCost > availableCredits` ❌
**Precondición:** Balance = 2, `totalTokenCost = 5`.
**Esperado:** Botón "Aplicar" bloqueado. Mensaje "Necesitás 5 tokens, tenés 2. Comprar créditos →".

---

### TC-52 · Sin bloqueo cuando `totalTokenCost ≤ availableCredits` ✅
**Precondición:** Balance = 5, `totalTokenCost = 5`.
**Esperado:** Botón "Aplicar" habilitado. Aplicar → balance = 0.

---

### TC-53 · Cambio de `token_cost` en admin se refleja en DesignStudio sin deploy ⚠️
**Precondición:** DesignStudio mostrando badge "1tk" para `banner.simple`.
**Acción:** Super-admin cambia `token_cost = 3`.
**Acción:** Tenant recarga DesignStudio.
**Esperado:** Badge muestra "3tk". `totalTokenCost` recalculado. Si el tenant tenía suficientes créditos antes pero no ahora, el botón se bloquea.

---

### TC-54 · Componente inactivo no aparece en el picker del DesignStudio ✅
**Precondición:** `is_active = false` para `hero.video.background`.
**Acción:** Navegar al DesignStudio.
**Esperado:** `hero.video.background` no aparece en las opciones de selección.

---

### TC-55 · Componente que requiere plan superior muestra aviso en DesignStudio ⚠️
**Precondición:** Tenant con plan `starter`. `hero.video.background` tiene `min_plan = 'growth'`.
**Esperado:** El componente aparece en el picker pero con indicador visual de "Requiere Growth". Si el usuario intenta seleccionarlo, el backend retornará 402 o 403 al aplicar.
**Decisión de diseño a verificar:** ¿El frontend bloquea la selección o solo lo advierte? Ambos comportamientos son válidos, pero deben ser consistentes con el comportamiento de onboarding (exploración libre).

---

## SECCIÓN 8 — Sincronización: BD como Única Fuente de Verdad

### TC-56 · `SECTION_CATALOG` de admin y web no se usa en lógica de negocio 🔄
**Acción:** Buscar en el código de `admin` y `web` referencias a `SECTION_CATALOG` que tomen decisiones de `planTier` o `planMin`.
**Esperado:** Las referencias a los archivos hardcodeados son solo para UI fallback (si el fetch falla) o ya han sido removidas. La lógica de validación siempre viene del response de la API.

---

### TC-57 · `VARIANT_REGISTRY` de la API no dicta el `planMin` ⚠️
**Acción:** Buscar en `api/src/home/registry/sections.ts` si el `planMin` hardcodeado todavía se usa en alguna validación de negocio.
**Esperado:** `home.controller.ts` y `onboarding.service.ts` consultan `component_catalog` en BD. El registry local es solo referencia o está deprecado.

---

### TC-58 · Sin BD disponible, el endpoint `/components/catalog` falla gracefully ⚠️
**Escenario:** Admin DB no disponible (timeout de conexión).
**Esperado:** HTTP 503 con mensaje claro. No crash. El DesignStudio muestra estado de error, no pantalla en blanco.

---

### TC-59 · Componente en BD que no existe en el código del storefront ⚠️
**Escenario:** Se agrega `hero.nuevo` a `component_catalog` pero el componente React aún no existe en `@nv/web`.
**Esperado al seleccionarlo:** Error controlado en el DesignStudio (componente no renderizable). No crash. El crédito NO se cobra si la operación falla.

---

## SECCIÓN 9 — Aislamiento y Seguridad

### TC-60 · `PATCH /admin/components/:key` no accesible desde tenant JWT 🔒
**Acción:** Tenant con JWT válido llama `PATCH /admin/components/hero.first`.
**Esperado:** HTTP 401 o 403. No se modifica nada.

---

### TC-61 · Cambio de `token_cost` en admin no afecta créditos ya consumidos 💸
**Escenario:** Tenant consumió 3 créditos para `hero.video.background` (token_cost = 3). Super-admin cambia a `token_cost = 1`.
**Esperado:** Los 3 créditos ya consumidos no se reembolsan. El ledger histórico refleja `credits_delta = -3`. Solo los próximos usos cobran 1 crédito.

---

### TC-62 · Endpoint `/components/catalog` no expone datos de tenants 🔒
**Acción:** `GET /components/catalog`.
**Esperado:** El response contiene solo datos del catálogo global (`component_key`, `label`, `token_cost`, etc.). Ningún dato específico de ningún tenant (`client_id`, `account_id`, configuraciones de tienda).

---

## SECCIÓN 10 — Concurrencia y Race Conditions

### TC-63 · Dos tabs aplican el mismo plan de acciones simultáneamente 🔁
**Precondición:** Balance = 5, `totalTokenCost = 5`.
**Escenario:** Usuario abre 2 tabs del DesignStudio y aplica el mismo plan en ambas casi simultáneamente.
**Esperado:** Solo uno de los requests consume los 5 créditos. El segundo recibe 402. Balance final = 0, no -5.
**Mecanismo:** Lock o transacción serializable en `assertComponentChangeAvailable`.

---

### TC-64 · Super-admin cambia `token_cost` mientras un tenant está en mid-checkout 🔁
**Escenario:** Tenant visualiza `totalTokenCost = 3` en UI (balance = 3). Super-admin cambia `token_cost` a `5`. Tenant hace click en "Aplicar".
**Esperado:** El backend evalúa el costo en el momento del request (token_cost = 5). Retorna 402. El tenant ve el error y debe recargar para ver el nuevo costo.
**Anti-patrón:** No honrar el token_cost que el tenant "vio" al momento de iniciar la acción — siempre se usa el valor actual de BD.

---

## SECCIÓN 11 — Edge Cases de Datos

### TC-65 · Catálogo con 0 componentes activos ⚠️
**Escenario:** Todos los componentes tienen `is_active = false` (situación de emergencia).
**Acción:** `GET /components/catalog`.
**Esperado:** HTTP 200 con array vacío `[]`. No 404 ni 500.

---

### TC-66 · `thumbnail_url` nulo no rompe el frontend ✅
**Precondición:** Componente con `thumbnail_url = NULL`.
**Acción:** Renderizar card del componente en DesignSystemView o DesignStudio.
**Esperado:** Placeholder visual. No error de JS por `null.src`.

---

### TC-67 · `description` nula en componente ✅
**Precondición:** Componente con `description = NULL`.
**Esperado:** UI renderiza sin descripción (o con "-"). No crash.

---

### TC-68 · `token_cost` muy alto en componente (ej: 999) ⚠️
**Escenario:** Super-admin setea `token_cost = 999` por error.
**Esperado:** El endpoint de catálogo retorna el valor real. El DesignStudio muestra el badge "999tk" en rojo. El tenant no puede usarlo hasta comprar créditos. No hay overflow ni error matemático.

---

### TC-69 · Componente con `sort_order` igual en varios registros ⚠️
**Escenario:** 5 componentes con `sort_order = 0`.
**Esperado:** Se aplica un orden secundario determinístico (por `component_key` alfabético o por `created_at`). El orden no varía entre requests.

---

### TC-70 · `design_config.sections` con keys nulas o vacías en checkout ⚠️
**Escenario:** `design_config.sections` contiene `[null, "", "hero.first"]`.
**Esperado:** El servicio de onboarding ignora los valores nulos/vacíos sin crashear. Solo evalúa las keys válidas.

---

## SECCIÓN 12 — Smoke Tests E2E

### TC-71 · Flujo completo onboarding: starter con componentes starter → checkout OK ✅
```
1. Usuario inicia onboarding (plan starter)
2. Step4: selecciona solo componentes min_plan = 'starter'
3. startCheckout → OK, sin PLAN_INCOMPATIBLE
4. Provisioning: balance component_change = 2
5. DesignStudio: badge muestra token costs correctos
6. Aplica 1 cambio de 1 token → balance = 1
```

---

### TC-72 · Flujo completo onboarding: starter con componente growth → upgrade prompt ✅
```
1. Usuario inicia onboarding (plan starter)
2. Step4: arrastra hero.video.background (growth)
3. Aviso informativo visible, no bloqueante
4. startCheckout → 400 PLAN_INCOMPATIBLE
5. UI muestra prompt de upgrade
6. Usuario upgradea a growth
7. Retry startCheckout → OK
```

---

### TC-73 · Flujo completo DesignStudio: cambio con token cost variable ✅
```
1. Super-admin: token_cost de hero.video.background = 3
2. Tenant growth (balance component_change = 5)
3. DesignStudio: badge muestra "3tk"
4. Usuario aplica replace a hero.video.background
5. Backend: token_cost leído de BD = 3, débita 3
6. Balance = 2
7. Ledger: credits_delta = -3
```

---

### TC-74 · Flujo completo: cambio de token_cost en admin → reflejo inmediato en DesignStudio ✅
```
1. token_cost de banner.simple = 1 → badge verde "1tk"
2. Super-admin PATCH → token_cost = 3
3. Tenant recarga DesignStudio
4. badge muestra "3tk" (rojo)
5. totalTokenCost recalculado
6. Si balance < nuevo total → botón bloqueado
```

---

### TC-75 · Flujo completo: sin créditos → compra pack → apply ✅
```
1. Balance component_change = 0
2. Intentar apply en DesignStudio → 402
3. UI muestra "Comprar créditos →"
4. Comprar pack via addon store
5. Webhook → grant créditos
6. Recargar DesignStudio → balance actualizado
7. Apply exitoso
```

---

## Resumen de Cobertura

| Área | TCs | Críticos |
|------|-----|----------|
| Integridad de BD | TC-01 a TC-07 | TC-04, TC-05, TC-06 |
| Endpoints catalog | TC-08 a TC-14 | TC-08, TC-11, TC-14 |
| Token cost en replaceSection | TC-15 a TC-24 | TC-17, TC-18, TC-24 |
| Onboarding + checkout | TC-25 a TC-34 | TC-28, TC-31, TC-34 |
| Provisioning créditos iniciales | TC-35 a TC-38 | TC-37 |
| Admin DesignSystemView | TC-39 a TC-45 | TC-40, TC-43 |
| Web DesignStudio | TC-46 a TC-55 | TC-50, TC-53, TC-55 |
| Sincronización y SoT | TC-56 a TC-59 | TC-56, TC-57, TC-59 |
| Aislamiento y seguridad | TC-60 a TC-62 | TC-60, TC-61 |
| Concurrencia | TC-63 a TC-64 | TC-63, TC-64 |
| Edge cases de datos | TC-65 a TC-70 | TC-68, TC-70 |
| E2E Smoke | TC-71 a TC-75 | Todos |
| **Total** | **75** | **~25 críticos** |