# Auditoría de Código — Módulos Content/Settings CRUD

**Fecha:** 2025-07-15  
**Autor:** agente-copilot  
**Alcance:** `apps/api/src/{banner,logo,faq,service,contact-info,social-links,seo,home,favorites,users,addresses,themes,legal,reviews,questions}`  
**Cantidad de archivos auditados:** ~50 (controllers, services, DTOs, registry)

---

## Índice

1. [Resumen Ejecutivo y Hallazgos Críticos](#1-resumen-ejecutivo)
2. [Banner](#2-banner)
3. [Logo](#3-logo)
4. [FAQ](#4-faq)
5. [Service](#5-service)
6. [Contact-Info](#6-contact-info)
7. [Social-Links](#7-social-links)
8. [SEO](#8-seo)
9. [Home (Aggregator + Sections + Settings + Identity)](#9-home)
10. [Favorites](#10-favorites)
11. [Users](#11-users)
12. [Addresses](#12-addresses)
13. [Themes](#13-themes)
14. [Legal](#14-legal)
15. [Reviews](#15-reviews)
16. [Questions](#16-questions)
17. [Matriz de Mismatches y Riesgos](#17-matriz)

---

## 1. Resumen Ejecutivo

### Hallazgos Críticos (🔴 P0)

| # | Módulo | Problema | Impacto |
|---|--------|----------|---------|
| 1 | **Users** | `PATCH /:id` acepta `body: any` sin DTO ni validación. Se puede escribir `role: 'super_admin'` u otros campos arbitrarios. | **Escalación de privilegios** |
| 2 | **Social-Links** | Controller tipea DTO como `any`; el CreateSocialLinksDto no tiene decoradores; se puede inyectar cualquier campo al DB. | **Inyección de datos arbitrarios** |
| 3 | **Themes** | `UpdateThemeDTO` es solo una interfaz TS (sin runtime validation). `overrides` acepta cualquier JSON. | **Inyección de datos arbitrarios en overrides** |

### Hallazgos Importantes (🟡 P1)

| # | Módulo | Problema |
|---|--------|----------|
| 4 | **Contact-Info** | Campo API `titleInfo` vs DB column `titleinfo` — funciona pero naming inconsistente |
| 5 | **FAQ** | Sin DTO de validación; body params crudos (`question`, `answer`, `number`) sin clase ni decoradores |
| 6 | **Banner** | Método `updateBannerLink` en service sin ruta de controller (código muerto) |
| 7 | **Home** | Dos endpoints duplicados para identity update: `PATCH /settings/identity` y `PATCH /settings/home/identity`, con lógica de merge distinta |
| 8 | **Themes** | Service consulta tabla `user` (singular) en vez de `users` (plural) |
| 9 | **Logo** | `getLogo` busca primero `show_logo=true`, luego fallback a `show_logo=false`; lógica confusa |
| 10 | **Home Settings** | `identity-settings.dto.ts` (class-validator) parece legacy/no acoplado al flow Zod actual |
| 11 | **Legal** | Withdrawal validations lanzan `throw new Error(...)` genéricos en vez de NestJS exceptions (400/403/409) — retorna 500 al cliente |

### Resumen de Cobertura por módulo

| Módulo | DTO Validation | client_id Filter | Guards | ETag/Cache |
|--------|:-:|:-:|:-:|:-:|
| Banner | ❌ parcial (solo type) | ✅ | ✅ RolesGuard+PlanLimits | ✅ |
| Logo | ❌ parcial (showLogo) | ✅ | ✅ RolesGuard | ❌ |
| FAQ | ❌ ninguno | ✅ | ✅ RolesGuard | ❌ |
| Service | ❌ parcial | ✅ | ✅ RolesGuard | ❌ |
| Contact-Info | ❌ ninguno | ✅ | ✅ RolesGuard | ❌ |
| Social-Links | ❌ `any` | ✅ | ✅ RolesGuard | ❌ |
| SEO | ✅ class-validator | ✅ | ✅ RolesGuard+PlanAccess | ❌ |
| Home Data | N/A (read) | ✅ | ❌ (público) | ✅ |
| Home Sections | ✅ Zod | ✅ | ✅ TenantContext | ❌ |
| Home Settings | ✅ Zod | ✅ | ✅ RolesGuard | ✅ |
| Identity | ✅ Zod (.strict) | ✅ | ✅ TenantContext+Roles | ✅ |
| Favorites | ❌ inline | ✅ | ✅ PlanAccess | ❌ |
| Users | ❌ `any` 🔴 | ✅ | ✅ ClientContext+PlanAccess | ❌ |
| Addresses | ✅ class-validator | ✅ | ✅ ClientContext | ❌ |
| Themes | ❌ TS interface 🔴 | ✅ | ✅ BuilderSession | ❌ |
| Legal | ❌ inline DTOs | ✅ / N/A (admin DB) | ✅ mixto | ❌ |
| Reviews | ✅ class-validator | ✅ | ✅ PlanAccess | ❌ |
| Questions | ✅ class-validator | ✅ | ✅ PlanAccess | ❌ |

---

## 2. Banner

**Archivos:** `src/banner/banner.controller.ts`, `src/banner/banner.service.ts`

### Endpoints

#### GET /settings/banner
| Aspecto | Detalle |
|---------|---------|
| Guards | Ninguno (público) |
| Request | Query: `type` (string) |
| Validación | Ninguna |
| DB | `banners` → `select('*').eq('client_id', clientId).eq('type', type).order('order')` |
| client_id filter | ✅ |
| Response | `{ banners: [...] }` |
| Cache | ✅ ETag via `buildEtagFromKey` + `applyCacheHeaders` |

#### GET /settings/banner/all
| Aspecto | Detalle |
|---------|---------|
| Guards | Ninguno (público) |
| Request | Ninguno |
| DB | `banners` → `select('*').eq('client_id', clientId).order('order')` |
| client_id filter | ✅ |
| Response | `{ desktop: Banner[], mobile: Banner[] }` agrupado por `type` |
| Cache | ✅ ETag |

#### POST /settings/banner
| Aspecto | Detalle |
|---------|---------|
| Guards | `RolesGuard(admin, super_admin)` + `PlanLimitsGuard` @PlanAction('create_banner') |
| Request | Body: `type` (string). Files: `files` (max 10, 5MB c/u) |
| Validación | Solo verifica que `files` existan y `type` no esté vacío |
| DB Write | `banners` → insert `{ url, type, file_path, order, client_id, image_variants }` |
| client_id filter | ✅ (inyectado en insert) |
| Side effects | Storage upload a `product-images/{clientId}/banners/`. Touch `client_completion_checklist.banner_uploaded`. Consulta `clients.nv_account_id` para account lookup |
| Response | `{ banners: [...created] }` |

#### PATCH /settings/banner
| Aspecto | Detalle |
|---------|---------|
| Guards | `RolesGuard(admin, super_admin)` |
| Request | Query: `id`. Body: `{ link?, order? }` |
| Validación | ❌ Sin DTO; campos crudos |
| DB Write | `banners` → `update({ link, order }).eq('id', id).eq('client_id', clientId)` |
| client_id filter | ✅ |
| Response | `{ banner: updated }` |

#### DELETE /settings/banner
| Aspecto | Detalle |
|---------|---------|
| Guards | `RolesGuard(admin, super_admin)` |
| Request | Query: `id` |
| DB | Fetch banner by id+client_id → delete from storage → delete from DB |
| client_id filter | ✅ |
| Response | `{ deleted: true }` |

### Mismatches & Notas
- 🟡 **Código muerto:** Existe `updateBannerLink(clientId, id, link)` en el service que no es invocado por ninguna ruta del controller. La ruta PATCH ya actualiza `link` inline.
- ⚠️ `order` en PATCH se pasa como body crudo sin validación numérica.

---

## 3. Logo

**Archivos:** `src/logo/logo.controller.ts`, `src/logo/logo.service.ts`

### Endpoints

#### GET /settings/logo
| Aspecto | Detalle |
|---------|---------|
| Guards | Ninguno (público) |
| DB | `logos` → primero busca `show_logo=true`, si no hay, busca `show_logo=false` |
| client_id filter | ✅ |
| Response | `{ logo: { id, url, show_logo, image_variants } }` o `{ logo: null }` |

#### POST /settings/logo
| Aspecto | Detalle |
|---------|---------|
| Guards | `RolesGuard(admin, super_admin)` |
| Request | File: `file` (max 2MB). Body: `showLogo` |
| Validación | Solo verifica que `file` exista |
| DB Write | Deletes all existing logos for tenant → inserts new `{ url, show_logo, file_path, client_id, image_variants }` |
| client_id filter | ✅ |
| Side effects | Storage upload + `client_completion_checklist.logo_uploaded` |
| Response | `{ logo: created }` |

#### DELETE /settings/logo
| Aspecto | Detalle |
|---------|---------|
| Guards | `RolesGuard(admin, super_admin)` |
| DB | Fetch existing → delete from storage → delete from DB |
| client_id filter | ✅ |
| Response | `{ message: 'Logo eliminado correctamente' }` |

### Mismatches & Notas
- 🟡 **Lógica confusa en getLogo:** Busca primero `show_logo=true`; si no lo encuentra, busca cualquier logo incluso con `show_logo=false`. Resultado: siempre retorna el logo aunque el admin lo haya "ocultado" (`show_logo=false`).
- El `showLogo` del body del POST se guarda como columna `show_logo`, pero el GET lo retorna siempre independientemente del valor.

---

## 4. FAQ

**Archivos:** `src/faq/faq.controller.ts`, `src/faq/faq.service.ts`

### Endpoints

#### GET /settings/faqs
| Aspecto | Detalle |
|---------|---------|
| Guards | Ninguno (público) |
| DB | `faqs` → `select('*').eq('client_id', clientId).order('number')` |
| client_id filter | ✅ |
| Response | `{ faqs: [...] }` |

#### POST /settings/faqs
| Aspecto | Detalle |
|---------|---------|
| Guards | `RolesGuard(admin, super_admin)` |
| Request | Body: `{ question, answer, number }` |
| Validación | ❌ Sin DTO; body crudo |
| DB Write | `faqs` → insert `{ question, answer, number, client_id }` |
| client_id filter | ✅ |
| Response | `{ faq: created }` |

#### PUT /settings/faqs
| Aspecto | Detalle |
|---------|---------|
| Guards | `RolesGuard(admin, super_admin)` |
| Request | Query: `id`. Body: `{ question, answer, number }` |
| Validación | ❌ Sin DTO |
| DB Write | `faqs` → `update({ question, answer, number }).eq('id', id).eq('client_id', clientId)` |
| client_id filter | ✅ |
| Response | `{ faq: updated }` |

#### DELETE /settings/faqs
| Aspecto | Detalle |
|---------|---------|
| Guards | `RolesGuard(admin, super_admin)` |
| Request | Query: `id` |
| DB | `faqs` → delete by id+client_id |
| client_id filter | ✅ |
| Response | `{ deleted: true }` |

### Mismatches & Notas
- 🟡 **Sin DTO:** `question`, `answer`, `number` se aceptan como body params crudos sin decoradores de validación. `number` podría recibir un string sin error hasta que DB lo rechace.

---

## 5. Service

**Archivos:** `src/service/service.controller.ts`, `src/service/service.service.ts`

### Endpoints

#### GET /settings/services
| Aspecto | Detalle |
|---------|---------|
| Guards | Ninguno (público) |
| DB | `services` → `select('*').eq('client_id', clientId).order('number')` |
| client_id filter | ✅ |
| Response | `{ services: [...] }` |

#### POST /settings/services
| Aspecto | Detalle |
|---------|---------|
| Guards | `RolesGuard(admin, super_admin)` |
| Request | File: `file` (max 5MB). Body: `{ title, description, number }` |
| Validación | Solo verifica que `file` exista |
| DB Write | `services` → insert `{ title, description, number, image_url, file_path, client_id, image_variants }` |
| client_id filter | ✅ |
| Side effects | Storage upload. `resolveNextNumber` auto-calcula `number` si no provisto |
| Response | `{ service: created }` |
| Error handling | Maneja error `23505` (duplicate key) |

#### PUT /settings/services/:id
| Aspecto | Detalle |
|---------|---------|
| Guards | `RolesGuard(admin, super_admin)` |
| Request | Path: `id`. File: `file` (opcional). Body: `{ title, description, number }` |
| Validación | Parcial; verifica existencia del service |
| DB Write | Updates campos provistos + reemplaza imagen si se sube nueva |
| client_id filter | ✅ (`.eq('id', id).eq('client_id', clientId)`) |
| Response | `{ service: updated }` |

#### DELETE /settings/services
| Aspecto | Detalle |
|---------|---------|
| Guards | `RolesGuard(admin, super_admin)` |
| Request | Query: `id` |
| DB | Fetch → delete from storage → delete from DB |
| client_id filter | ✅ |
| Response | `{ deleted: true }` |

### Mismatches & Notas
- ⚠️ `number` se pasa como body string sin parseo explícito a int; depende de Postgres para cast.

---

## 6. Contact-Info

**Archivos:** `src/contact-info/contact-info.controller.ts`, `src/contact-info/contact-info.service.ts`

### Endpoints

#### GET /contact-info
| Aspecto | Detalle |
|---------|---------|
| Guards | Ninguno (público) |
| DB | `contact_info` → `select('*').eq('client_id', clientId)` |
| client_id filter | ✅ |
| Response | `{ contactInfo: [...] }` |

#### POST /contact-info
| Aspecto | Detalle |
|---------|---------|
| Guards | `RolesGuard(admin, super_admin)` |
| Request | Body: `{ titleInfo, description, number }` |
| Validación | ❌ Sin DTO |
| DB Write | `contact_info` → insert `{ titleinfo: titleInfo, description, number, client_id }` |
| client_id filter | ✅ |
| Response | `{ contactInfo: created }` |

#### PUT /contact-info/:id
| Aspecto | Detalle |
|---------|---------|
| Guards | `RolesGuard(admin, super_admin)` |
| Request | Path: `id`. Body: `{ titleInfo, description, number }` |
| DB Write | `contact_info` → `update({ titleinfo: titleInfo, description, number }).eq('id', id).eq('client_id', clientId)` |
| client_id filter | ✅ |

#### DELETE /contact-info/:id
| Aspecto | Detalle |
|---------|---------|
| Guards | `RolesGuard(admin, super_admin)` |
| DB | `contact_info` → delete by id+client_id |
| client_id filter | ✅ |

### Mismatches & Notas
- 🟡 **Naming mismatch:** API acepta `titleInfo` (camelCase) → service escribe `titleinfo` (lowercase) al DB. Funciona pero inconsistente con la convención camelCase→snake_case usada en otros módulos.

---

## 7. Social-Links

**Archivos:** `src/social-links/social-links.controller.ts`, `src/social-links/social-links.service.ts`, `src/social-links/dto/create-social-links.dto.ts`, `src/social-links/dto/update-social-links.dto.ts`

### Endpoints

#### GET /social-links
| Aspecto | Detalle |
|---------|---------|
| Guards | Ninguno (público) |
| DB | `social_links` → `select('*').eq('client_id', clientId).single()` |
| client_id filter | ✅ |
| Response | `{ socialLinks: data }` — retorna `false` si no hay registro |

#### POST /social-links
| Aspecto | Detalle |
|---------|---------|
| Guards | `RolesGuard(admin, super_admin)` |
| Request | Body: `dto: any` 🔴 |
| Validación | ❌ **NINGUNA** — DTO tipado como `any` |
| DB Write | `social_links` → insert `{ ...dto, client_id }` — **spread directo de todo el body** |
| client_id filter | ✅ (inyectado) |
| Response | `{ socialLinks: created }` |

#### PUT /social-links/:id
| Aspecto | Detalle |
|---------|---------|
| Guards | `RolesGuard(admin, super_admin)` |
| Request | Path: `id`. Body: `dto: any` 🔴 |
| DB Write | `social_links` → `update({ ...dto }).eq('id', id).eq('client_id', clientId)` |
| client_id filter | ✅ |

#### DELETE /social-links/:id
| Aspecto | Detalle |
|---------|---------|
| Guards | `RolesGuard(admin, super_admin)` |
| DB | delete by id+client_id |
| client_id filter | ✅ |

### DTOs (no usados por controller)

```typescript
// create-social-links.dto.ts — SIN decoradores de validación
export class CreateSocialLinksDto {
  whatsApp: string;
  wspText: string;
  instagram: string;
  facebook: string;
}

// update-social-links.dto.ts — CON decoradores pero no referenciado
export class UpdateSocialLinksDto {
  @IsOptional() @IsString() whatsApp?: string;
  @IsOptional() @IsString() wspText?: string;
  @IsOptional() @IsString() instagram?: string;
  @IsOptional() @IsString() facebook?: string;
}
```

### Mismatches & Notas
- 🔴 **CRÍTICO:** Controller usa `any`. Existen DTOs pero **no están conectados**. El `CreateSocialLinksDto` no tiene decoradores. El `UpdateSocialLinksDto` tiene decoradores pero no se referencia. Resultado: cualquier campo se persiste directamente al DB vía spread.
- 🟡 `findOne` retorna `false` en vez de `null` cuando no hay registro — inconsistente con el patrón del resto del API.

---

## 8. SEO

**Archivos:** `src/seo/seo.controller.ts`, `src/seo/seo.service.ts`, `src/seo/dto/{update-seo-settings.dto.ts, update-entity-meta.dto.ts, redirect.dto.ts}`

### Endpoints

#### GET /seo/settings
| Aspecto | Detalle |
|---------|---------|
| Guards | Ninguno (público por tenant) |
| DB | `seo_settings` → `select('*').eq('client_id', clientId).single()` |
| client_id filter | ✅ |
| Response | Row o defaults vacíos |

#### PUT /seo/settings
| Aspecto | Detalle |
|---------|---------|
| Guards | `RolesGuard(admin, super_admin)` |
| Request | Body: `UpdateSeoSettingsDto` |
| Validación | ✅ class-validator: site_title (MaxLength 70), site_description (MaxLength 160), canonical_url, robots_txt, og_image, sitemap_enabled, sitemap_custom_urls, google_verification, bing_verification, default_noindex — todos opcionales |
| DB Write | `seo_settings` → upsert on `client_id` |
| client_id filter | ✅ |

#### GET /seo/meta/:entity/:id
| Aspecto | Detalle |
|---------|---------|
| Guards | `PlanAccessGuard` @PlanFeature('seo.entity_meta') |
| DB | Lee de `products` o `categories` según entity. Columnas: `meta_title, meta_description, slug, noindex, seo_source, seo_locked` |
| client_id filter | ✅ |

#### PUT /seo/meta/:entity/:id
| Aspecto | Detalle |
|---------|---------|
| Guards | `RolesGuard(admin, super_admin)` |
| Request | Body: `UpdateEntityMetaDto` |
| Validación | ✅ class-validator: meta_title, meta_description, slug, noindex (boolean), seo_source, seo_locked (boolean) |
| DB Write | `products` o `categories` → update meta columns by id+client_id |
| client_id filter | ✅ |

#### GET /seo/sitemap.xml
| Aspecto | Detalle |
|---------|---------|
| Guards | Ninguno (público) |
| DB | Lee `products` y `categories` activas del tenant |
| client_id filter | ✅ |
| Response | Content-Type: text/xml |

#### GET /seo/og
| Aspecto | Detalle |
|---------|---------|
| Guards | Ninguno (público) |
| Request | Query: `path` |
| DB | Lee `seo_settings`, `products`, `categories`, `clients` |
| client_id filter | ✅ |
| Response | OG metadata object |

#### GET/POST/PUT/DELETE /seo/redirects
| Aspecto | Detalle |
|---------|---------|
| Guards | `RolesGuard(admin, super_admin)` + `PlanAccessGuard` @PlanFeature('seo.redirects') |
| DTO | `CreateRedirectDto` (from_path, to_url requeridos; redirect_type default 301, active default true), `UpdateRedirectDto` (todo opcional) |
| DB | Table `seo_redirects` → columns: id, client_id, from_path, to_url, redirect_type, active, hit_count, created_at, updated_at |
| client_id filter | ✅ |

#### GET /seo/redirects/resolve
| Aspecto | Detalle |
|---------|---------|
| Guards | Ninguno (público) |
| Request | Query: `path` |
| DB | `seo_redirects` → match by from_path+client_id+active. Incrementa `hit_count` (fire-and-forget) |
| client_id filter | ✅ |

### Mismatches & Notas
- ✅ Módulo bien validado con DTOs de class-validator.
- ⚠️ `resolveRedirect` incrementa `hit_count` con race condition (read+write no atómico). En alto tráfico podría sub-contar.
- Entity meta solo soporta `products` y `categories`; entity param no está validado en controller pero sí en service con `ENTITY_TABLE_MAP` (lanza 400).

---

## 9. Home

**Archivos:**
- Controllers: `src/home/home.controller.ts`, `src/home/home-settings.controller.ts`, `src/home/settings.controller.ts`
- Services: `src/home/home.service.ts`, `src/home/home-settings.service.ts`, `src/home/home-sections.service.ts`
- DTOs: `src/home/dto/identity-config.dto.ts`, `src/home/dto/identity-settings.dto.ts`, `src/home/dto/section.dto.ts`
- Registry: `src/home/registry/sections.ts`

### Endpoints — home.controller.ts

#### GET /home/data
| Aspecto | Detalle |
|---------|---------|
| Guards | Ninguno (público) |
| DB | Agregador: `products` (60 random, shuffled, limit 20), `services`, `banners` (desktop+mobile), `faqs`, `logos`, `contact_info`, `social_links`, `client_home_settings`, `clients` (fiscal fields) |
| client_id filter | ✅ en cada sub-query |
| Response | `{ products, services, banners, faqs, logo, contactInfo, socialLinks, homeConfig, client }` |
| Cache | ✅ ETag |

#### GET /home/navigation
| Aspecto | Detalle |
|---------|---------|
| Guards | Ninguno (público) |
| DB | `logos`, `social_links`, `contact_info` |
| client_id filter | ✅ |
| Cache | ✅ ETag |

#### GET /home/sections
| Aspecto | Detalle |
|---------|---------|
| Guards | `TenantContextGuard` |
| DB | `home_sections` → `select('*').eq('client_id', clientId).order('sort_index')` |
| client_id filter | ✅ |

#### POST /home/sections
| Aspecto | Detalle |
|---------|---------|
| Guards | `TenantContextGuard` |
| Request | Body: validado con Zod `AddSectionDto` (`type`, `insert_after_id?`, `props?`) |
| Validación | ✅ Zod + plan limits (max_sections) + maxPerHome + type existence in REGISTRY + props schema validation |
| DB Write | `home_sections` → insert `{ client_id, type, props, sort_index, is_active: true }` |
| client_id filter | ✅ |

#### PATCH /home/sections/order
| Aspecto | Detalle |
|---------|---------|
| Guards | `TenantContextGuard` |
| Request | Body: Zod `UpdateOrderDto` (`ordered_ids: uuid[]`) |
| DB Write | Batch update `sort_index` para cada id en ordered_ids |
| client_id filter | ✅ (cada update filtrado por id+client_id) |

#### PATCH /home/sections/:id/replace
| Aspecto | Detalle |
|---------|---------|
| Guards | `TenantContextGuard` |
| Request | Body: Zod `ReplaceSectionDto` (`new_type`, `props?`) |
| Validación | ✅ Slot compatibility + plan check + props schema |
| DB Write | `home_sections` → update type+props |
| client_id filter | ✅ |

#### DELETE /home/sections/:id
| Aspecto | Detalle |
|---------|---------|
| Guards | `TenantContextGuard` |
| DB | `home_sections` → delete by id+client_id |
| client_id filter | ✅ |

### Endpoints — home-settings.controller.ts

#### GET /settings/home
| Aspecto | Detalle |
|---------|---------|
| Guards | Ninguno (público) |
| DB | `client_home_settings` → select by client_id. Fallback a `clients.template_id`. Lookup `palette_catalog`. Lookup `nv_accounts` en admin DB |
| client_id filter | ✅ |
| Cache | ✅ ETag |

#### PUT /settings/home
| Aspecto | Detalle |
|---------|---------|
| Guards | `RolesGuard(admin, super_admin)` |
| Request | Body: `{ templateKey?, paletteKey? }` |
| Validación | `templateKey` validado contra `VALID_TEMPLATE_KEYS_SET`; `paletteKey` no validado |
| DB Write | `client_home_settings` → upsert `{ template_key, palette_key, updated_at }` |
| client_id filter | ✅ |

#### PATCH /settings/home/identity
| Aspecto | Detalle |
|---------|---------|
| Guards | `RolesGuard(admin, super_admin)` |
| Request | Body: validado via Zod `identityConfigSchema.deepPartial()` |
| DB Write | Deep-merge con `identity_config` existente + increment `identity_version` |
| client_id filter | ✅ |

#### POST /settings/home/popup-image
| Aspecto | Detalle |
|---------|---------|
| Guards | `RolesGuard(admin, super_admin)` |
| Request | File: `file` (max 2MB) |
| Side effects | Upload to storage `{clientId}/popup/` → deep-merge URL into `identity_config.banners.popup.image` |
| client_id filter | ✅ |

#### DELETE /settings/home/popup-image
| Aspecto | Detalle |
|---------|---------|
| Guards | `RolesGuard(admin, super_admin)` |
| Side effects | Remove file from storage + null-out `identity_config.banners.popup.image` |
| client_id filter | ✅ |

### Endpoints — settings.controller.ts

#### GET /settings/identity
| Aspecto | Detalle |
|---------|---------|
| Guards | `TenantContextGuard` |
| DB | `client_home_settings` → `select('identity_config, identity_version')` |
| client_id filter | ✅ |
| Cache | ✅ ETag |

#### PATCH /settings/identity
| Aspecto | Detalle |
|---------|---------|
| Guards | `TenantContextGuard` + `RolesGuard(admin, super_admin)` |
| Request | Body: Zod `identityConfigSchema.deepPartial()` |
| DB Write | Deep-merge con existente + increment version |
| client_id filter | ✅ |

### Section Registry (`registry/sections.ts`)

Tipos definidos: `hero`, `video_banner`, `product_carousel`, `product_grid`, `testimonials`, `team_gallery`, `services_grid`, `contact_form`

Plan limits:
- `starter`: max 8 sections
- `growth`: max 12 sections
- `enterprise`: unlimited

Cada tipo define: slot, planMin, maxPerHome, Zod schema para props, defaultProps, migrate function (opcional).

### Mismatches & Notas
- 🟡 **Endpoint duplicado:** `PATCH /settings/identity` (settings.controller.ts) y `PATCH /settings/home/identity` (home-settings.controller.ts) ambos actualizan `client_home_settings.identity_config` con deep-merge. El de `settings.controller.ts` usa `TenantContextGuard + RolesGuard`; el de `home-settings.controller.ts` usa solo `RolesGuard`. Ambos llaman al mismo service method. Riesgo: confusión sobre cuál usar.
- 🟡 `identity-settings.dto.ts` existe con decoradores class-validator pero **no está conectado** a ningún controller; parece legacy del flujo pre-Zod.
- ⚠️ `paletteKey` en `PUT /settings/home` no se valida contra catálogo antes de persistirse.
- `home.service.ts` hace `shuffle` de productos cada request (no se cachea el orden).

---

## 10. Favorites

**Archivos:** `src/favorites/favorites.controller.ts`, `src/favorites/favorites.service.ts`

### Endpoints

#### GET /favorites
| Aspecto | Detalle |
|---------|---------|
| Guards | `PlanAccessGuard` (implicit); plan check inline (growth+ only) |
| Request | Query: `full` (0/1), `page`, `pageSize` |
| DB | `favorites` → `select('*, products(*)').eq('client_id', clientId).eq('user_id', userId)` con paginación |
| client_id filter | ✅ |
| Response | `{ data, total, page, pageSize }` |

#### POST /favorites/:productId
| Aspecto | Detalle |
|---------|---------|
| Guards | Plan check (growth+) |
| DB | Verifica producto existe → insert `{ client_id, user_id, product_id }` |
| client_id filter | ✅ |
| Duplicate handling | Ignora silenciosamente (409→rethrow o skip) |

#### DELETE /favorites/:productId
| Aspecto | Detalle |
|---------|---------|
| Guards | Plan check (growth+) |
| DB | `favorites` → delete by client_id+user_id+product_id |
| client_id filter | ✅ |

#### POST /favorites/merge
| Aspecto | Detalle |
|---------|---------|
| Guards | Auth required |
| Request | Body: `{ productIds: string[] }` |
| Validación | ❌ Sin DTO; inline check |
| DB | Llama RPC `merge_favorites(p_client_id, p_user_id, p_product_ids)`. Fallback: inserta uno a uno |
| client_id filter | ✅ |

### Mismatches & Notas
- ⚠️ Sin DTO formal para merge. `productIds` se asume array sin validación de tipo.
- Plan check usa `assertRemoteFavoritesAllowed` que lanza `ForbiddenException` para plan `starter`.

---

## 11. Users

**Archivos:** `src/users/users.controller.ts`, `src/users/users.service.ts`

### Endpoints

#### GET /users
| Aspecto | Detalle |
|---------|---------|
| Guards | `ClientContextGuard` + `PlanAccessGuard` @PlanFeature('dashboard.users_management') |
| DB | `users` → `select('*').eq('client_id', clientId).neq('role', 'super_admin').order('created_at')` |
| client_id filter | ✅ |
| Response | `{ users: [...] }` (excluye super_admin del listado) |

#### GET /users/:id
| Aspecto | Detalle |
|---------|---------|
| Guards | Mismos que clase |
| DB | `users` → select by id+client_id |
| client_id filter | ✅ |

#### PATCH /users/:id
| Aspecto | Detalle |
|---------|---------|
| Guards | Mismos que clase |
| Request | Body: `any` 🔴 |
| Validación | ❌ **NINGUNA** — solo valida `personal_info` subestructura si está presente |
| DB Write | `users` → `update(body).eq('id', id).eq('client_id', clientId)` |
| client_id filter | ✅ |
| Response | `{ user: updated }` |

#### PUT /users/:id/block
| Aspecto | Detalle |
|---------|---------|
| Guards | Mismos que clase |
| Request | Body: `{ blocked: boolean }` |
| DB Write | `users` → `update({ blocked }).eq('id', id).eq('client_id', clientId)` |
| client_id filter | ✅ |

#### POST /users/:id/accept-terms
| Aspecto | Detalle |
|---------|---------|
| Guards | Mismos que clase |
| DB Write | `users` → `update({ terms_accepted: true }).eq('id', id).eq('client_id', clientId)` |
| client_id filter | ✅ |

#### DELETE /users/:id
| Aspecto | Detalle |
|---------|---------|
| Guards | Mismos que clase |
| DB | Verifica `orders` count > 0 → rechaza si tiene pedidos. Luego delete from `users` |
| client_id filter | ✅ |

### Mismatches & Notas
- 🔴 **CRÍTICO — Escalación de privilegios:** `PATCH /users/:id` acepta `body: any` y lo pasa directo a `update(body)`. Un admin malintencionado podría enviar `{ "role": "super_admin" }` para elevar permisos de un usuario, o inyectar campos arbitrarios. **Se recomienda crear un `UpdateUserDto` con whitelist de campos permitidos (personal_info, blocked, terms_accepted) y excluir explícitamente `role`, `client_id`, `id`.**
- La validación de `personal_info` es parcial: verifica que `firstName`, `lastName`, `phoneNumber` sean strings, pero permite otros campos dentro del JSON.

---

## 12. Addresses

**Archivos:** `src/addresses/addresses.controller.ts`, `src/addresses/addresses.service.ts`, `src/addresses/dto/address.dto.ts`

### Endpoints

#### GET /addresses
| Aspecto | Detalle |
|---------|---------|
| Guards | `ClientContextGuard` |
| DB | `user_addresses` → select by client_id+user_id, order by is_default DESC, created_at DESC |
| client_id filter | ✅ |
| Response | Array mapeado snake→camel |

#### GET /addresses/:id
| Aspecto | Detalle |
|---------|---------|
| Guards | `ClientContextGuard` |
| DB | `user_addresses` → select by id+client_id+user_id |
| client_id filter | ✅ |

#### POST /addresses
| Aspecto | Detalle |
|---------|---------|
| Guards | `ClientContextGuard` |
| Request | Body: `CreateAddressDto` |
| Validación | ✅ class-validator: full_name, street, street_number, city, province, zip_code (requeridos); label, phone, floor_apt, country, notes, is_default (opcionales). MaxLength en todos |
| DB Write | `user_addresses` → insert. Si `is_default=true`, restablece is_default=false en todas las previas del user. Max 10 addresses por user |
| client_id filter | ✅ |

#### PUT /addresses/:id
| Aspecto | Detalle |
|---------|---------|
| Guards | `ClientContextGuard` |
| Request | Body: `UpdateAddressDto` (todo opcional) |
| DB Write | `user_addresses` → update by id+client_id+user_id |
| client_id filter | ✅ |

#### DELETE /addresses/:id
| Aspecto | Detalle |
|---------|---------|
| Guards | `ClientContextGuard` |
| DB | delete by id+client_id+user_id |
| client_id filter | ✅ |

### Mismatches & Notas
- ✅ Módulo bien validado con DTOs y límites claros.
- Response usa mapeo snake→camel (`full_name` → `fullName`, etc.) — documentado y consistente.
- `MAX_ADDRESSES_PER_USER = 10` aplicado en el service.

---

## 13. Themes

**Archivos:** `src/themes/themes.controller.ts`, `src/themes/themes.service.ts`, `src/themes/theme-validation.service.ts`

### Endpoints

#### GET /themes/:clientId
| Aspecto | Detalle |
|---------|---------|
| Guards | `BuilderSessionGuard` + auth check manual inline |
| Auth | Verifica token manualmente; consulta tabla `user` 🟡 (singular, no `users`) para obtener `client_id`. Si user.client_id ≠ param clientId y role ≠ super_admin → 403 |
| DB | `client_themes` → `select('*').eq('client_id', clientId).single()` (admin DB via `DbRouterService`) |
| client_id filter | ✅ (param) |
| Response | Theme row |

#### PATCH /themes/:clientId
| Aspecto | Detalle |
|---------|---------|
| Guards | `BuilderSessionGuard` + auth check manual inline |
| Request | Body: `UpdateThemeDTO` (TS interface: `template_key?, template_version?, overrides?`) |
| Validación | ❌ **Solo interfaz TS, sin runtime validation.** `template_key` se valida en service contra tabla `nv_templates`. `overrides` acepta cualquier JSON 🔴 |
| DB Write | `client_themes` → upsert on `client_id` |
| client_id filter | ✅ (param + auth check) |

### ThemeValidationService
- Valida `template_key` contra lista hardcoded `['minimal', 'classic', 'bold', 'elegant', 'modern']`.
- **Pero NO se usa en themes.service.ts** — el service valida contra tabla `nv_templates` en su lugar. Este service parece legacy/unused.

### Mismatches & Notas
- 🔴 **Sin runtime validation:** `UpdateThemeDTO` es interface TS. `overrides` (JSON libre) se persiste sin validación → riesgo de datos corruptos/maliciosos.
- 🟡 **Tabla `user` vs `users`:** En `themes.service.ts`, la query de autorización consulta `this.adminDb.from('user')` (singular). Si la tabla en admin DB se llama `users` (plural, como en multicliente), esto falla silenciosamente. Si la tabla admin se llama `user` por convención diferente, funciona pero requiere documentación clara.
- 🟡 `ThemeValidationService` no se usa en el flow de themes; `template_key` se valida contra `nv_templates` en el service directamente. Código muerto.

---

## 14. Legal

**Archivos:** `src/legal/legal.controller.ts`, `src/legal/legal.service.ts`, `src/legal/legal-notification.service.ts`

### Base de datos dual
- **Admin DB:** `nv_legal_documents`, `nv_merchant_consent_log`, `nv_cancellation_requests`
- **Multicliente DB:** `buyer_consent_log`, `withdrawal_requests`, `orders`

### Endpoints

#### GET /legal/documents
| Aspecto | Detalle |
|---------|---------|
| Guards | `@AllowNoTenant()` — no requiere tenant |
| DB | Admin DB: `nv_legal_documents` → `select('*').eq('is_current', true)` |
| client_id filter | N/A (cross-tenant, admin DB) |

#### GET /legal/documents/:type
| Aspecto | Detalle |
|---------|---------|
| Guards | `@AllowNoTenant()` |
| DB | Admin DB: `nv_legal_documents` → by document_type+is_current |
| client_id filter | N/A |

#### POST /legal/buyer-consent
| Aspecto | Detalle |
|---------|---------|
| Guards | Auth required (req.user) |
| Request | Body: `{ documentType, version, orderId? }` |
| Validación | ❌ Sin DTO formal; parámetros crudos |
| DB Write | Multicliente: `buyer_consent_log` → insert `{ client_id, user_id, order_id, document_type, version, ip_address, user_agent }` |
| client_id filter | ✅ |

#### POST /legal/withdrawal
| Aspecto | Detalle |
|---------|---------|
| Guards | Auth required |
| Request | Body: `{ orderId, reason, contactEmail, contactPhone? }` |
| Validación | Inline business rules: order exists + belongs to tenant/user, payment_status=approved, status not in cancelled/refunded/return_requested, 10-day window (Ley 24.240), no existing active withdrawal |
| DB Write | `withdrawal_requests` → insert. Also updates `orders.status` → 'return_requested' |
| client_id filter | ✅ |
| Side effects | Queues email notifications (buyer + merchant) via `LegalNotificationService` |

#### GET /legal/withdrawal/:trackingCode
| Aspecto | Detalle |
|---------|---------|
| Guards | Auth not strictly required (tracking code acts as auth token) |
| DB | `withdrawal_requests` → by tracking_code+client_id |
| client_id filter | ✅ |

#### GET /legal/withdrawals
| Aspecto | Detalle |
|---------|---------|
| Guards | Inline role check (`admin`/`super_admin`) |
| Request | Query: `status?`, `orderId?` |
| DB | `withdrawal_requests` → select by client_id + optional filters |
| client_id filter | ✅ |

#### PATCH /legal/withdrawal/:id
| Aspecto | Detalle |
|---------|---------|
| Guards | Inline role check (admin/super_admin) |
| Request | Body: `{ action: WithdrawalAction, adminNotes?, rejectionReason?, productCondition? }` |
| Validación | State machine validation: `WITHDRAWAL_VALID_TRANSITIONS` map. Reject requires `rejectionReason` |
| DB Write | `withdrawal_requests` → update status + metadata. Syncs `orders.status` (reject→approved, mark_refunded→refunded) |
| client_id filter | ✅ |

#### GET /legal/withdrawal/order/:orderId
| Aspecto | Detalle |
|---------|---------|
| Guards | Auth required |
| DB | `withdrawal_requests` → by order_id+client_id+user_id (user can only see own) |
| client_id filter | ✅ |

#### POST /legal/cancellation
| Aspecto | Detalle |
|---------|---------|
| Guards | `@AllowNoTenant()` + `SuperAdminGuard` |
| Request | Body: `{ accountId, reason }` |
| DB Write | Admin DB: `nv_cancellation_requests` → insert `{ account_id, tracking_code, reason, ip_address, user_agent, status: 'pending', effective_date }` |
| client_id filter | N/A (admin DB, accountId scope) |

#### GET /legal/cancellation/:trackingCode
| Aspecto | Detalle |
|---------|---------|
| Guards | `@AllowNoTenant()` |
| DB | Admin DB: `nv_cancellation_requests` → by tracking_code |
| client_id filter | N/A |

### Withdrawal Status Machine

```
pending → approve → approved
pending → reject → rejected
approved → mark_received → product_received
approved → reject → rejected
product_received → mark_refunded → refunded
rejected → (terminal)
refunded → (terminal)
cancelled → (terminal)
```

### Mismatches & Notas
- 🟡 **Error handling:** `createWithdrawalRequest` y `updateWithdrawalStatus` lanzan `throw new Error('...')` genéricos para validaciones de negocio. NestJS mapea estos a HTTP 500 (Internal Server Error) en vez de 400/403/409 como correspondería. **Se recomienda usar `BadRequestException`, `ForbiddenException`, `ConflictException`.**
- ⚠️ Sin DTOs formales para buyer-consent ni withdrawal creation; body params son crudos.
- Cancellation no filtra por client_id sino por account_id (admin DB) — correcto para ese contexto.
- Notification service (`LegalNotificationService`) es non-blocking: errores de email se logean pero no fallan el request. Usa deduplication key para idempotencia.

---

## 15. Reviews

**Archivos:** `src/reviews/reviews.controller.ts`, `src/reviews/reviews.service.ts`, `src/reviews/dto/index.ts`

### Endpoints

#### GET /products/:productId/reviews
| Aspecto | Detalle |
|---------|---------|
| Guards | `PlanAccessGuard` @PlanFeature('storefront.product_reviews') |
| Request | Query: `ListReviewsDto` (cursor, limit, sort, rating, verified_only) — class-validator |
| DB | `product_reviews` → filtrado por client_id + product_id + moderation_status='published'. Cursor pagination. También lee `product_review_aggregates` y user review info |
| client_id filter | ✅ |
| Response | `{ data: Review[], aggregates: { avg_rating, review_count, rating_distribution }, next_cursor, user_review? }` |

#### POST /products/:productId/reviews
| Aspecto | Detalle |
|---------|---------|
| Guards | PlanAccess; auth required |
| Request | Body: `CreateReviewDto` (rating 1-5 required, title? string, body? string) — class-validator |
| Validación | ✅ DTO + rating range + verified purchase required + HTML sanitization + unique constraint (23505) |
| DB Write | `product_reviews` → insert `{ client_id, product_id, user_id, rating, title, body, display_name, verified_purchase, moderation_status: 'published' }` |
| client_id filter | ✅ |
| RPC | `has_purchased_product(p_client_id, p_user_id, p_product_id)` para verificar compra |

#### PATCH /reviews/:reviewId
| Aspecto | Detalle |
|---------|---------|
| Guards | PlanAccess; auth required |
| Request | Body: `UpdateReviewDto` (rating?, title?, body? — all optional) — class-validator |
| Validación | ✅ Ownership check + must be 'published' status |
| DB Write | `product_reviews` → update by id+client_id |
| client_id filter | ✅ |

#### POST /reviews/:reviewId/reply
| Aspecto | Detalle |
|---------|---------|
| Guards | `RolesGuard(admin, super_admin)` |
| Request | Body: `AdminReplyDto` (body: string, required) |
| Validación | ✅ Length 5-2000 + HTML sanitization |
| DB Write | `product_reviews` → update `admin_reply, admin_reply_by, admin_reply_at` |
| client_id filter | ✅ |

#### PATCH /reviews/:reviewId/moderate
| Aspecto | Detalle |
|---------|---------|
| Guards | `RolesGuard(admin, super_admin)` |
| Request | Body: `ModerateReviewDto` (action: 'hide'|'restore', reason?) |
| Validación | ✅ Class-validator @IsIn |
| DB Write | `product_reviews` → update `moderation_status, moderated_by, moderated_at, moderation_reason` |
| client_id filter | ✅ |

#### GET /products/:productId/social-proof
| Aspecto | Detalle |
|---------|---------|
| Guards | PlanAccess |
| DB | `product_review_aggregates` → select by client_id+product_id |
| client_id filter | ✅ |
| Response | `{ avg_rating, review_count, question_count }` |

#### GET /admin/reviews
| Aspecto | Detalle |
|---------|---------|
| Guards | `RolesGuard(admin, super_admin)` |
| Request | Query: moderation_status, rating, cursor, limit |
| DB | `product_reviews` → join with `products(name, slug)` |
| client_id filter | ✅ |

### Mismatches & Notas
- ✅ Módulo bien implementado con DTOs, sanitización HTML, verified purchase, cursor pagination.
- El `displayName` se computa server-side ("FirstName L.") para privacidad.
- Reviews usan `product_review_aggregates` (tabla precalculada) para el social proof.

---

## 16. Questions

**Archivos:** `src/questions/questions.controller.ts`, `src/questions/questions.service.ts`, `src/questions/dto/index.ts`

### Endpoints

#### GET /products/:productId/questions
| Aspecto | Detalle |
|---------|---------|
| Guards | `PlanAccessGuard` @PlanFeature('storefront.product_qa') |
| Request | Query: `ListQuestionsDto` (cursor, limit, search) — class-validator |
| DB | `product_questions` → parent_id IS NULL + moderation_status='published'. Cursor pagination. Fetches child answers separately |
| client_id filter | ✅ |
| Response | `{ data: Question[], next_cursor, total_count? }` (total_count solo en primera página) |

#### POST /products/:productId/questions
| Aspecto | Detalle |
|---------|---------|
| Guards | PlanAccess; auth required |
| Request | Body: `CreateQuestionDto` (body: string, required) — class-validator |
| Validación | ✅ Tenant membership + product exists + HTML sanitization + length 10-2000 |
| DB Write | `product_questions` → insert `{ client_id, product_id, user_id, body, display_name, status: 'open', moderation_status: 'published' }` |
| client_id filter | ✅ |

#### POST /questions/:questionId/answers
| Aspecto | Detalle |
|---------|---------|
| Guards | `RolesGuard(admin, super_admin)` |
| Request | Body: `AnswerQuestionDto` (body: string, required) |
| Validación | ✅ Question exists + is root (parent_id=null) + length 10-2000 + HTML sanitization |
| DB Write | `product_questions` → insert answer as child (`parent_id=questionId`). Updates parent `status='answered'` |
| client_id filter | ✅ |
| Display name | Usa nombre de la tienda (`clients.name`) en vez del admin |

#### PATCH /questions/:questionId/moderate
| Aspecto | Detalle |
|---------|---------|
| Guards | `RolesGuard(admin, super_admin)` |
| Request | Body: `ModerateQuestionDto` (action: 'hide'|'restore'|'resolve', reason?) |
| Validación | ✅ @IsIn |
| DB Write | Updates `moderation_status` y/o `status`. Cascade: hide/restore children too |
| client_id filter | ✅ |

#### DELETE /questions/:questionId
| Aspecto | Detalle |
|---------|---------|
| Guards | Auth required (owner) |
| Validación | Ownership check (user_id match) |
| DB Write | `product_questions` → update `moderation_status='archived'` (soft delete) |
| client_id filter | ✅ |

#### GET /admin/questions
| Aspecto | Detalle |
|---------|---------|
| Guards | `RolesGuard(admin, super_admin)` |
| Request | Query: status, cursor, limit |
| DB | `product_questions` → join with `products(name, slug)`. Fetches answers as children |
| client_id filter | ✅ |

### Mismatches & Notas
- ✅ Módulo bien implementado con DTOs, sanitización, moderation cascade.
- Questions usa parent/child model en misma tabla (`product_questions`) con `parent_id` para Q&A.
- Soft delete via `moderation_status='archived'` en vez de hard delete.
- `search` usa `ILIKE` — potencial issue de rendimiento sin índice GIN.

---

## 17. Matriz de Mismatches y Riesgos

### 🔴 Críticos (requieren acción inmediata)

| ID | Módulo | Archivo | Problema | Remediación |
|----|--------|---------|----------|-------------|
| C1 | Users | `users.controller.ts` | `PATCH /:id` usa `body: any` sin DTO → se puede inyectar `role`, `client_id`, `id` | Crear `UpdateUserDto` con whitelist explícita. Excluir `role`, `client_id`, `id` |
| C2 | Social-Links | `social-links.controller.ts` | Body tipado como `any`; DTOs existen pero no están conectados | Conectar `UpdateSocialLinksDto` al controller; agregar decoradores al `CreateSocialLinksDto` |
| C3 | Themes | `themes.controller.ts` | `UpdateThemeDTO` es solo TS interface; `overrides` de JSON libre | Convertir a class-validator DTO o Zod. Validar estructura de overrides como mínimo |

### 🟡 Importantes (plan de mejora)

| ID | Módulo | Archivo | Problema | Remediación |
|----|--------|---------|----------|-------------|
| I1 | Contact-Info | `contact-info.service.ts` | `titleInfo` (API) → `titleinfo` (DB) naming inconsistente | Normalizar a snake_case (`title_info`) en ambos lados, o documentar |
| I2 | FAQ | `faq.controller.ts` | Sin DTO de validación en endpoints de escritura | Crear `CreateFaqDto`/`UpdateFaqDto` con decoradores |
| I3 | Banner | `banner.service.ts` | `updateBannerLink` es código muerto | Eliminar o conectar a ruta |
| I4 | Home | `home-settings.controller.ts` + `settings.controller.ts` | Dos endpoints para identity update con guards diferentes | Deprecar uno y consolidar |
| I5 | Themes | `themes.service.ts` | Consulta tabla `user` (singular) en admin DB | Verificar nombre correcto de tabla en admin DB; documentar diferencia si intencional |
| I6 | Legal | `legal.service.ts` | `throw new Error()` para validaciones de negocio → HTTP 500 | Usar NestJS exceptions (BadRequestException, ConflictException, etc.) |
| I7 | Logo | `logo.service.ts` | `getLogo` retorna logo incluso con `show_logo=false` | Revisar: ¿el front filtra? Si no, el flag no tiene efecto real |
| I8 | Home Settings | `identity-settings.dto.ts` | DTO legacy class-validator no usado (flujo migrado a Zod) | Eliminar archivo o marcar deprecated |
| I9 | Themes | `theme-validation.service.ts` | Service con preset keys hardcodeados, no usado por themes flow | Eliminar o integrar |
| I10 | Social-Links | `social-links.service.ts` | `findOne` retorna `false` en vez de `null` | Normalizar a `null` como el resto de módulos |

### 🟢 Info / Low Risk

| ID | Módulo | Notas |
|----|--------|-------|
| L1 | SEO | `hit_count` increment es no-atómico (race condition en alto tráfico) — bajo impacto |
| L2 | Home | `products` en home.data se shufflean en cada request — no cacheable |
| L3 | Home Settings | `paletteKey` no validado contra catálogo antes de persist |
| L4 | Questions | `search` con ILIKE sin índice GIN — potencial perf issue |
| L5 | Favorites | Sin DTO para `merge`; `productIds` no validado como array de UUID |
| L6 | Banner | `order` en PATCH no validado como número |

---

## Apéndice A — Tablas DB tocadas por módulo

| Módulo | Tabla(s) Principal(es) | DB |
|--------|----------------------|-----|
| Banner | `banners`, `clients`, `client_completion_checklist` | Multicliente |
| Logo | `logos`, `client_completion_checklist` | Multicliente |
| FAQ | `faqs` | Multicliente |
| Service | `services` | Multicliente |
| Contact-Info | `contact_info` | Multicliente |
| Social-Links | `social_links` | Multicliente |
| SEO | `seo_settings`, `seo_redirects`, `products`, `categories`, `clients` | Multicliente |
| Home | `products`, `services`, `banners`, `faqs`, `logos`, `contact_info`, `social_links`, `client_home_settings`, `clients`, `home_sections` | Multicliente |
| Home Settings | `client_home_settings`, `nv_accounts`, `palette_catalog` | Multicliente + Admin |
| Favorites | `favorites`, `products`, `clients` | Multicliente |
| Users | `users`, `orders` | Multicliente |
| Addresses | `user_addresses` | Multicliente |
| Themes | `client_themes`, `user`, `nv_templates` | Admin |
| Legal (docs/consent) | `nv_legal_documents`, `nv_merchant_consent_log`, `buyer_consent_log` | Admin + Multicliente |
| Legal (withdrawal) | `withdrawal_requests`, `orders` | Multicliente |
| Legal (cancellation) | `nv_cancellation_requests` | Admin |
| Reviews | `product_reviews`, `product_review_aggregates`, `users`, `products` | Multicliente |
| Questions | `product_questions`, `users`, `products`, `clients` | Multicliente |

## Apéndice B — Guards por endpoint

| Guard | Módulos que lo usan |
|-------|-------------------|
| `RolesGuard(admin, super_admin)` | Banner, Logo, FAQ, Service, Contact-Info, Social-Links, SEO, Home Settings, Reviews (reply/moderate), Questions (answer/moderate) |
| `TenantContextGuard` | Home Sections, Settings Identity |
| `ClientContextGuard` | Users, Addresses |
| `PlanAccessGuard` + `@PlanFeature` | SEO (entity_meta, redirects), Users (dashboard.users_management), Reviews (storefront.product_reviews), Questions (storefront.product_qa) |
| `PlanLimitsGuard` + `@PlanAction` | Banner (create_banner) |
| `BuilderSessionGuard` | Themes |
| `SuperAdminGuard` | Legal (cancellation) |
| `@AllowNoTenant()` | Legal (documents, cancellation) |
| Ninguno (público) | Banner GET, Logo GET, FAQ GET, Service GET, Contact-Info GET, Social-Links GET, SEO settings GET / sitemap / og, Home data / navigation |

---

*Fin de auditoría.*
