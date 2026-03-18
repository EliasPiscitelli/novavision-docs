# Admin Dashboard — UX Fixes + Guards + Traducciones + Layout Switch

**Fecha:** 2026-03-17
**Alcance:** API (NestJS), Admin Dashboard
**Branch:** feature/automatic-multiclient-onboarding (submodules), feature/multitenant-storefront (parent)
**Estado:** Implementado y pusheado

---

## Contexto

Post-deploy del Marketing OS (8 fases) quedaron problemas de acceso (401), textos en ingles, falta de guia contextual, y tablas sin filtros. Este changelog cubre los 5 bloques de fix/UX aplicados.

---

## Bloque 1 — Fix 401: Guards en controllers API

**Problema:** Los 5 controllers nuevos del Marketing OS no tenian `@UseGuards(SuperAdminGuard)`, causando 401 en produccion pese a que los JSDoc decian "protegido".

**Impacto:** Critico — el dashboard de marketing estaba completamente roto para super-admins. Sin el guard, el middleware global rechazaba las peticiones a los endpoints `/admin/marketing/*` y `/admin/growth-hq/*`.

| Archivo | Cambio |
|---------|--------|
| `api/src/growth-hq/growth-hq.controller.ts` | +`@UseGuards(SuperAdminGuard)` +`@AllowNoTenant()` |
| `api/src/marketing/marketing-config.controller.ts` | +`@UseGuards(SuperAdminGuard)` |
| `api/src/marketing/creative-studio.controller.ts` | +`@UseGuards(SuperAdminGuard)` |
| `api/src/marketing/audience-intel.controller.ts` | +`@UseGuards(SuperAdminGuard)` |
| `api/src/marketing/campaign-advisor.controller.ts` | +`@UseGuards(SuperAdminGuard)` |

---

## Bloque 2 — Traduccion a español argentino

### 2A — Prompts de IA (backend)

**Problema:** Aunque los system prompts estaban escritos en español, GPT-4o a veces respondia en ingles cuando los datos del contexto (JSON) eran en ingles.

**Impacto:** Las recomendaciones de campañas, analisis de audiencias y copy de creativos ahora siempre salen en español argentino, mejorando la experiencia del super-admin que opera el dashboard.

| Archivo | Cambio |
|---------|--------|
| `api/src/marketing/campaign-advisor.service.ts` | +`"Respondé SIEMPRE en español argentino."` en 2 system prompts |
| `api/src/marketing/audience-intel.service.ts` | +`"Respondé SIEMPRE en español argentino."` en 1 system prompt |
| `api/src/marketing/creative-studio.service.ts` | +`"Respondé SIEMPRE en español argentino."` en 2 system prompts |

### 2B — Textos hardcodeados en frontend

**Impacto:** Coherencia visual — todo el dashboard ahora esta en español, eliminando la mezcla de idiomas que confundia al usuario.

| Texto anterior | Texto nuevo | Archivo |
|---------------|-------------|---------|
| "Campaign Control Center" | "Centro de Control de Campañas" | CampaignControlView.jsx |
| "Audience Intelligence" | "Inteligencia de Audiencias" | AudienceIntelView.jsx |
| "Spend" / "Trend" | "Gasto" / "Tendencia" | AudienceIntelView.jsx (headers tabla) |
| "Creatives" | "Creatividades" | index.jsx (NAV_ITEMS) |
| "Campaigns" | "Campañas" | index.jsx |
| "Audience Intel" | "Inteligencia de Audiencias" | index.jsx |
| "Marketing Config" | "Config. Marketing" | index.jsx |
| "Ad Performance" | "Rendimiento Publicitario" | index.jsx |
| "Addon Store Ops" | "Ops. Addon Store" | index.jsx |
| "Creatives Library" | "Creatividades" | AdAssetsView.jsx |

---

## Bloque 3 — Tutorial contextual para secciones nuevas

**Impacto:** Los super-admins que entran por primera vez a una seccion nueva ven un banner explicativo de 1-2 oraciones que les dice que hace la seccion y como usarla. Se cierra con "Entendido" y no vuelve a aparecer (localStorage).

| View | Key localStorage | Texto tutorial |
|------|-----------------|----------------|
| GrowthHqView | `nv_tutorial_growth_hq` | Metricas de adquisicion: MRR, CAC, CPL, ROAS, filtros de periodo |
| AudienceIntelView | `nv_tutorial_audience_intel` | Analisis de rendimiento por segmento + score ICP |
| CampaignControlView | `nv_tutorial_campaigns` | Ciclo de vida de campañas + recomendaciones IA |
| MarketingConfigView | `nv_tutorial_marketing_config` | Parametros de workflows n8n en tiempo real |
| AdAssetsView | `nv_tutorial_ad_assets` | Biblioteca de creativos + sugerencia IA |

---

## Bloque 4 — Layout Switch (Cards vs Sidebar)

**Impacto:** El super-admin puede elegir entre la vista actual de categorias colapsables con grid de tarjetas, o una vista con sidebar lateral fijo que ahorra espacio vertical y permite navegar mas rapido entre modulos. Ideal para quienes usan el dashboard diariamente.

| Componente | Descripcion |
|-----------|-------------|
| `LayoutSwitchButton` | Toggle en header (icono Cards/Sidebar) |
| `DashboardLayout` | Flex container para sidebar + content |
| `SidebarContainer` | Barra lateral 260px (expandida) / 60px (minimizada) |
| `SidebarItem` | NavLink vertical con icono + label |
| `SidebarToggle` | Boton para colapsar/expandir sidebar |
| `SidebarCategoryLabel` | Separador de categoria en sidebar |

**Persistencia:** `localStorage` keys `nv_layout_mode` y `nv_sidebar_collapsed`.

---

## Bloque 5 — Filtros, ordenamiento y paginacion

**Impacto:** Las tablas de datos que antes mostraban todo sin control ahora permiten filtrar, ordenar y paginar, mejorando la usabilidad cuando hay muchos datos.

### GrowthHqView (Top Ads)
- Filtro por plataforma: All / Meta / Google / TikTok
- Ordenamiento clickeable en headers: Gasto, Clicks, Conversiones, CTR, CPC, ROAS
- Paginacion: 20 filas por pagina con Anterior/Siguiente

### AudienceIntelView (Performance por Audiencia)
- Filtro por tendencia: Todas / Mejorando / Estable / Declinando
- Ordenamiento: Gasto, Conversiones, CPA (clickeable en headers)

### CampaignControlView (Lista de campañas)
- Filtro por status: Todas / Borrador / Activa / Pausada / Completada
- Ordenamiento: Nombre o Budget

### MarketingConfigView
- Busqueda por key con preview de resultados (key, descripcion, valor actual)

---

## Validacion

- `tsc --noEmit` (API): 0 errores
- `npx eslint` (API): 0 errores (16 warnings preexistentes de `@typescript-eslint/no-explicit-any`)
- `npx vite build` (Admin): build exitoso (4.92s)
- Pre-push hooks (API): 7/7 validaciones pasaron
