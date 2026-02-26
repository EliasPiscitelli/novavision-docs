# Inventario Completo de Endpoints — NovaVision API

> **Generado:** 2025-07-17  
> **Fuente:** Inspección directa de 76 controllers y 34+ DTOs en `apps/api/src/`  
> **Formato:** MODULE | HTTP | RUTA COMPLETA | BODY DTO | QUERY DTO | GUARDS | NOTAS

---

## Índice de Módulos

1. [accounts](#1-accounts)
2. [addresses](#2-addresses)
3. [admin (main)](#3-admin-main)
4. [admin/accounts](#4-adminaccounts)
5. [admin/adjustments](#5-adminadjustments)
6. [admin/clients](#6-adminclients)
7. [admin/country-configs](#7-admincountry-configs)
8. [admin/coupons](#8-admincoupons)
9. [admin/fee-schedules](#9-adminfee-schedules)
10. [admin/finance](#10-adminfinance)
11. [admin/fx](#11-adminfx)
12. [admin/managed-domains](#12-adminmanaged-domains)
13. [admin/media](#13-adminmedia)
14. [admin/metering](#14-adminmetering)
15. [admin/option-sets](#15-adminoption-sets)
16. [admin/plans](#16-adminplans)
17. [admin/quotas](#17-adminquotas)
18. [admin/renewals](#18-adminrenewals)
19. [admin/seo-ai-billing](#19-adminseo-ai-billing)
20. [admin/shipping](#20-adminshipping)
21. [admin/store-coupons](#21-adminstore-coupons)
22. [admin/super-emails](#22-adminsuper-emails)
23. [admin/support](#23-adminsupport)
24. [admin/system](#24-adminsystem)
25. [analytics](#25-analytics)
26. [auth](#26-auth)
27. [banner](#27-banner)
28. [billing](#28-billing)
29. [cart](#29-cart)
30. [categories](#30-categories)
31. [client-dashboard](#31-client-dashboard)
32. [client/managed-domains](#32-clientmanaged-domains)
33. [clients](#33-clients)
34. [contact-info](#34-contact-info)
35. [cors-origins](#35-cors-origins)
36. [coupons](#36-coupons)
37. [debug](#37-debug)
38. [demo](#38-demo)
39. [dev/portal](#39-devportal)
40. [dev (seeding)](#40-dev-seeding)
41. [faq](#41-faq)
42. [favorites](#42-favorites)
43. [health](#43-health)
44. [home](#44-home)
45. [home-settings](#45-home-settings)
46. [legal](#46-legal)
47. [logo](#47-logo)
48. [mercadopago (tenant-payments)](#48-mercadopago)
49. [mp/oauth](#49-mpoauth)
50. [oauth-relay](#50-oauth-relay)
51. [onboarding](#51-onboarding)
52. [option-sets](#52-option-sets)
53. [orders](#53-orders)
54. [palettes](#54-palettes)
55. [payments (admin)](#55-payments-admin)
56. [payments (storefront)](#56-payments-storefront)
57. [plans](#57-plans)
58. [products](#58-products)
59. [questions](#59-questions)
60. [quota](#60-quota)
61. [reviews](#61-reviews)
62. [seo](#62-seo)
63. [seo-ai](#63-seo-ai)
64. [seo-ai (purchase)](#64-seo-ai-purchase)
65. [service](#65-service)
66. [settings (identity)](#66-settings-identity)
67. [shipping](#67-shipping)
68. [social-links](#68-social-links)
69. [store-coupons](#69-store-coupons)
70. [subscriptions](#70-subscriptions)
71. [support (client)](#71-support-client)
72. [templates](#72-templates)
73. [tenant](#73-tenant)
74. [themes](#74-themes)
75. [users](#75-users)
76. [webhooks/mp (router)](#76-webhooksmp-router)

---

## Resumen Cuantitativo

| Métrica | Valor |
|---------|-------|
| Controllers | 76 |
| DTOs (archivos dedicados) | 34 |
| DTOs inline en controllers | ~15 |
| Endpoints totales (aprox.) | ~450+ |
| Guards únicos | 11 |
| Decoradores custom | 4 (@AllowNoTenant, @Roles, @PlanFeature, @PlanAction) |

### Guards Utilizados

| Guard | Propósito |
|-------|-----------|
| `SuperAdminGuard` | Acceso exclusivo super_admin (plataforma NovaVision) |
| `TenantContextGuard` | Resuelve y valida tenant (client_id) desde headers |
| `ClientContextGuard` | Valida contexto de cliente (tenant) en rutas de tienda |
| `ClientDashboardGuard` | Acceso al dashboard del cliente (admin de tienda) |
| `RolesGuard` | Valida roles (admin, super_admin) vía @Roles() |
| `PlanAccessGuard` | Verifica que el plan del tenant tenga acceso al feature |
| `PlanLimitsGuard` | Verifica límites del plan (ej: max productos) |
| `BuilderSessionGuard` | Valida JWT de sesión builder (onboarding) |
| `BuilderOrSupabaseGuard` | Acepta builder session O JWT Supabase |
| `PlatformAuthGuard` | Auth a nivel plataforma (billing) |
| `SubscriptionGuard` | Valida suscripción activa para upgrades |

---

## 1. accounts

**Controller:** `accounts/accounts.controller.ts` — Prefix: `accounts`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/accounts/me` | — | — | @AllowNoTenant | Perfil del usuario actual |
| POST | `/accounts/identity` | `IdentityDTO` (inline: session_id, dni) | — | @AllowNoTenant | Registrar identidad |
| POST | `/accounts/verify-identity` | inline: session_id | — | @AllowNoTenant | Verificar identidad |
| POST | `/accounts/dni/upload` | FormData (file) | — | @AllowNoTenant | Upload DNI foto |

---

## 2. addresses

**Controller:** `addresses/addresses.controller.ts` — Prefix: `addresses`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/addresses` | — | — | ClientContextGuard | Lista direcciones del usuario |
| GET | `/addresses/:id` | — | — | ClientContextGuard | Detalle dirección |
| POST | `/addresses` | `CreateAddressDto` | — | ClientContextGuard | Crear dirección |
| PUT | `/addresses/:id` | `UpdateAddressDto` | — | ClientContextGuard | Actualizar dirección |
| DELETE | `/addresses/:id` | — | — | ClientContextGuard | Eliminar dirección |

**CreateAddressDto:** label, full_name, phone (regex `^\+?\d{8,15}$`), street, street_number, floor_apt, city, province, zip_code, country, notes, is_default  
**UpdateAddressDto:** Todos opcionales, mismos campos

---

## 3. admin (main)

**Controller:** `admin/admin.controller.ts` — Prefix: `admin` (1099 líneas)  
**Guard global:** SuperAdminGuard (por método), @AllowNoTenant implícito

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/admin/dashboard-meta` | — | — | SuperAdminGuard | Meta del dashboard |
| GET | `/admin/pending-approvals` | — | — | SuperAdminGuard | Aprobaciones pendientes |
| GET | `/admin/pending-approvals/:id` | — | — | SuperAdminGuard | Detalle aprobación |
| GET | `/admin/pending-completions` | — | ?country | SuperAdminGuard | Completions pendientes |
| GET | `/admin/backend-clusters` | — | — | SuperAdminGuard | Lista clusters |
| POST | `/admin/backend-clusters` | inline: { name, db_url } | — | SuperAdminGuard | Crear cluster |
| POST | `/admin/backend-clusters/:clusterId/db-url` | inline: { db_url } | — | SuperAdminGuard | Actualizar DB URL |
| POST | `/admin/backend-clusters/:targetClusterId/clone-schema` | inline: { source_cluster_id } | — | SuperAdminGuard | Clonar schema |
| GET | `/admin/accounts/:id/details` | — | — | SuperAdminGuard | Detalle cuenta |
| GET | `/admin/accounts/:id/subscription-status` | — | — | SuperAdminGuard | Estado suscripción |
| GET | `/admin/accounts/:id/360` | — | — | SuperAdminGuard | Vista 360 cuenta |
| GET | `/admin/accounts/:id/completion-checklist` | — | — | SuperAdminGuard | Checklist completitud |
| GET | `/admin/completion-requirements/defaults` | — | — | SuperAdminGuard | Requisitos por defecto |
| PATCH | `/admin/completion-requirements/defaults` | inline: JSON | — | SuperAdminGuard | Actualizar requisitos |
| GET | `/admin/accounts/:id/completion-requirements` | — | — | SuperAdminGuard | Requisitos de cuenta |
| PATCH | `/admin/accounts/:id/completion-requirements` | inline: JSON | — | SuperAdminGuard | Actualizar req. cuenta |
| DELETE | `/admin/accounts/:id/completion-requirements` | — | — | SuperAdminGuard | Reset a defaults |
| POST | `/admin/clients/:id/backfill-catalog` | — | — | SuperAdminGuard | Backfill catálogo |
| POST | `/admin/clients/:id/sync-mp` | — | — | SuperAdminGuard | Sync MercadoPago |
| POST | `/admin/clients/:id/approve` | inline: { reviewed_by? } | — | SuperAdminGuard | Aprobar cliente |
| POST | `/admin/clients/:id/backfill-nv-account-id` | — | — | SuperAdminGuard | Backfill account ID |
| POST | `/admin/clients/:id/validate-and-cleanup` | — | — | SuperAdminGuard | Validar y limpiar |
| POST | `/admin/accounts/:id/custom-domain` | inline: { domain } | — | SuperAdminGuard | Asignar dominio |
| POST | `/admin/accounts/:id/custom-domain/verify` | — | — | SuperAdminGuard | Verificar DNS |
| PATCH | `/admin/accounts/:accountId/products/:productId` | inline: JSON parcial | — | SuperAdminGuard | Editar producto |
| DELETE | `/admin/accounts/:accountId/products/:productId` | — | — | SuperAdminGuard | Eliminar producto |
| POST | `/admin/clients/:id/request-changes` | inline: { message, items?, reviewed_by? } | — | SuperAdminGuard | Solicitar cambios |
| POST | `/admin/clients/:id/reject-final` | inline: { reason, reviewed_by? } | — | SuperAdminGuard | Rechazo definitivo |
| POST | `/admin/clients/:id/review-email/preview` | inline: { type, message?, items?, reason? } | — | SuperAdminGuard | Preview email review |
| POST | `/admin/clients/:id/pause` | inline: { reason } | — | SuperAdminGuard | Pausar tienda |
| POST | `/admin/stats` | — | — | SuperAdminGuard | Stats generales |
| GET | `/admin/clients` | — | — | SuperAdminGuard | Listar todos los clientes |
| GET | `/admin/clients/:id` | — | — | SuperAdminGuard | Detalle cliente |
| GET | `/admin/finance/clients` | — | — | SuperAdminGuard | Clientes para finanzas |
| GET | `/admin/metrics/summary` | — | ?from, ?to, ?timezone, ?granularity, ?plan_key, ?status | SuperAdminGuard | Métricas resumen |
| GET | `/admin/metrics/tops` | — | ?from, ?to, ?limit | SuperAdminGuard | Top métricas |
| GET | `/admin/clients/:id/metrics` | — | ?from, ?to | SuperAdminGuard | Métricas de cliente |
| GET | `/admin/subscriptions/health` | — | — | SuperAdminGuard | Salud suscripciones |
| GET | `/admin/subscription-events` | — | ?page, ?pageSize, ?event_type, ?account_id, ?country | SuperAdminGuard | Eventos suscripción |
| GET | `/admin/check-invariants` | — | — | SuperAdminGuard | Verificar invariantes |
| GET | `/admin/accounts/:id/categories` | — | — | SuperAdminGuard | Categorías de cuenta |
| POST | `/admin/accounts/:id/categories` | inline: { name, description? } | — | SuperAdminGuard | Crear categoría |
| DELETE | `/admin/accounts/:accountId/categories/:categoryId` | — | — | SuperAdminGuard | Eliminar categoría |
| PATCH | `/admin/accounts/:accountId/categories/:categoryId` | inline: { name } | — | SuperAdminGuard | Editar categoría |
| GET | `/admin/accounts/:id/faqs` | — | — | SuperAdminGuard | FAQs de cuenta |
| POST | `/admin/accounts/:id/faqs` | inline: { question, answer } | — | SuperAdminGuard | Crear FAQ |
| DELETE | `/admin/accounts/:accountId/faqs/:faqId` | — | — | SuperAdminGuard | Eliminar FAQ |
| PATCH | `/admin/accounts/:accountId/faqs/:faqId` | inline: { question?, answer? } | — | SuperAdminGuard | Editar FAQ |
| GET | `/admin/accounts/:id/services` | — | — | SuperAdminGuard | Servicios de cuenta |
| POST | `/admin/accounts/:id/services` | inline: { title, description?, price? } | — | SuperAdminGuard | Crear servicio |
| DELETE | `/admin/accounts/:accountId/services/:serviceId` | — | — | SuperAdminGuard | Eliminar servicio |
| PATCH | `/admin/accounts/:accountId/services/:serviceId` | inline: { title?, description?, price? } | — | SuperAdminGuard | Editar servicio |
| GET | `/admin/accounts/:id/contact-social` | — | — | SuperAdminGuard | Contacto y social |
| PATCH | `/admin/accounts/:id/contact-social` | inline: { contact?, social? } | — | SuperAdminGuard | Actualizar contacto/social |

---

## 4. admin/accounts

**Controller:** `admin/admin-accounts.controller.ts` — Prefix: `admin/accounts`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| POST | `/admin/accounts/draft` | `CreateDraftAccountDto` (inline: email, name, planId?) | — | SuperAdminGuard, @AllowNoTenant | Crear cuenta draft - **⚠️ Sin validadores class-validator** |
| POST | `/admin/accounts/:accountId/onboarding-link` | — | — | SuperAdminGuard, @AllowNoTenant | Generar link onboarding |

---

## 5. admin/adjustments

**Controller:** `admin/admin-adjustments.controller.ts` — Prefix: `admin/adjustments`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/admin/adjustments` | — | — | SuperAdminGuard, @AllowNoTenant | Listar ajustes |
| GET | `/admin/adjustments/:id` | — | — | SuperAdminGuard, @AllowNoTenant | Detalle ajuste |
| POST | `/admin/adjustments/:id/charge` | inline | — | SuperAdminGuard, @AllowNoTenant | Cobrar ajuste |
| POST | `/admin/adjustments/:id/waive` | inline | — | SuperAdminGuard, @AllowNoTenant | Condonar ajuste |
| POST | `/admin/adjustments/bulk-charge` | inline | — | SuperAdminGuard, @AllowNoTenant | Cobro masivo |
| POST | `/admin/adjustments/recalculate` | inline | — | SuperAdminGuard, @AllowNoTenant | Recalcular |

---

## 6. admin/clients

**Controller:** `admin/admin-client.controller.ts` — Prefix: `admin/clients` (773 líneas)

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| DELETE | `/admin/clients/:clientId` | — | — | SuperAdminGuard, @AllowNoTenant | Eliminar cliente |
| POST | `/admin/clients/:clientId/payment-reminder` | `SendReminderDto` (inline: type, subject?, body?) | — | SuperAdminGuard, @AllowNoTenant | Enviar recordatorio - **⚠️ Sin validators** |
| POST | `/admin/clients/:clientId/payments` | `RegisterPaymentDto` (inline: amount, method?, type?, note?, paid_at?) | — | SuperAdminGuard, @AllowNoTenant | Registrar pago - **⚠️ Sin validators** |
| PATCH | `/admin/clients/:clientId/status` | `ToggleStatusDto` (inline: is_active, suspension_reason?) | — | SuperAdminGuard, @AllowNoTenant | Toggle active - **⚠️ Sin validators** |
| GET | `/admin/clients/:clientId/payments` | — | — | SuperAdminGuard, @AllowNoTenant | Listar pagos |
| GET | `/admin/clients/:clientId/invoices` | — | — | SuperAdminGuard, @AllowNoTenant | Listar facturas |
| POST | `/admin/clients/:clientId/sync-invoices` | — | — | SuperAdminGuard, @AllowNoTenant | Sync facturas |
| POST | `/admin/clients/:clientId/sync-to-backend` | — | — | SuperAdminGuard, @AllowNoTenant | Sync a backend DB |

---

## 7. admin/country-configs

**Controller:** `admin/admin-country-configs.controller.ts` — Prefix: `admin/country-configs`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/admin/country-configs` | — | — | SuperAdminGuard, @AllowNoTenant | Listar configs |
| PATCH | `/admin/country-configs/:siteId` | `UpdateCountryConfigDto` | — | SuperAdminGuard, @AllowNoTenant | Actualizar config |
| POST | `/admin/country-configs` | `CreateCountryConfigDto` | — | SuperAdminGuard, @AllowNoTenant | Crear config |

**CreateCountryConfigDto:** site_id (Length 3), country_id (Length 2), currency_id (Length 3), locale, timezone, decimals (Min 0, Max 4), arca_cuit_pais?, vat_digital_rate (Min 0, Max 1), active?, country_name?  
**UpdateCountryConfigDto:** Todos opcionales: country_name, locale, timezone, decimals, arca_cuit_pais, vat_digital_rate, active, fiscal_id_label/regex/mask/check_digit, personal_id_label/regex, phone_prefix/regex, subdivision_label, persona_natural_label, persona_juridica_label

---

## 8. admin/coupons

**Controller:** `coupons/admin-coupons.controller.ts` — Prefix: `admin/coupons`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| POST | `/admin/coupons` | inline | — | SuperAdminGuard, @AllowNoTenant | Crear cupón plataforma |
| GET | `/admin/coupons` | — | — | SuperAdminGuard, @AllowNoTenant | Listar cupones |
| PATCH | `/admin/coupons/:id/toggle` | — | — | SuperAdminGuard, @AllowNoTenant | Toggle activo |
| DELETE | `/admin/coupons/:id` | — | — | SuperAdminGuard, @AllowNoTenant | Eliminar cupón |

---

## 9. admin/fee-schedules

**Controller:** `admin/admin-fee-schedules.controller.ts` — Prefix: `admin/fee-schedules`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/admin/fee-schedules` | — | — | SuperAdminGuard, @AllowNoTenant | Listar fee schedules |
| POST | `/admin/fee-schedules` | inline | — | SuperAdminGuard, @AllowNoTenant | Crear fee schedule |
| PATCH | `/admin/fee-schedules/:id` | inline | — | SuperAdminGuard, @AllowNoTenant | Actualizar |
| DELETE | `/admin/fee-schedules/:id` | — | — | SuperAdminGuard, @AllowNoTenant | Eliminar |
| POST | `/admin/fee-schedules/:id/lines` | inline | — | SuperAdminGuard, @AllowNoTenant | Agregar línea |
| PATCH | `/admin/fee-schedules/:id/lines/:lineId` | inline | — | SuperAdminGuard, @AllowNoTenant | Editar línea |
| DELETE | `/admin/fee-schedules/:id/lines/:lineId` | — | — | SuperAdminGuard, @AllowNoTenant | Eliminar línea |

---

## 10. admin/finance

**Controller:** `finance/finance.controller.ts` — Prefix: `admin/finance`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/admin/finance/summary` | — | — | SuperAdminGuard, @AllowNoTenant | Resumen financiero |

---

## 11. admin/fx

**Controller:** `admin/admin-fx-rates.controller.ts` — Prefix: `admin/fx`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/admin/fx/rates` | — | — | SuperAdminGuard, @AllowNoTenant | Listar tasas FX |
| PATCH | `/admin/fx/rates/:countryId` | `UpdateFxConfigDto` | — | SuperAdminGuard, @AllowNoTenant | Actualizar config FX |
| POST | `/admin/fx/rates/:countryId/refresh` | — | — | SuperAdminGuard, @AllowNoTenant | Refrescar tasa |

**UpdateFxConfigDto:** source? (IsIn ['auto','manual']), manual_rate?, manual_rate_date?, cache_ttl_minutes? (Min 1, Max 1440), auto_endpoint?, auto_field_path?, fallback_rate?

---

## 12. admin/managed-domains

**Controller:** `admin/admin-managed-domain.controller.ts` — Prefix: `admin/managed-domains` (429 líneas)

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/admin/managed-domains` | — | — | SuperAdminGuard, @AllowNoTenant | Listar dominios |
| POST | `/admin/managed-domains/provision` | inline: { accountId, domain, registrar?, years? } | — | SuperAdminGuard, @AllowNoTenant | Provisionar dominio |
| POST | `/admin/managed-domains/trigger-expirations` | — | — | SuperAdminGuard, @AllowNoTenant | Trigger expirations |
| GET | `/admin/managed-domains/account/:accountId` | — | — | SuperAdminGuard, @AllowNoTenant | Dominios por cuenta |
| GET | `/admin/managed-domains/:id` | — | — | SuperAdminGuard, @AllowNoTenant | Detalle dominio |
| POST | `/admin/managed-domains/:id/quote` | — | — | SuperAdminGuard, @AllowNoTenant | Cotizar renovación |
| POST | `/admin/managed-domains/:id/mark-renewed` | inline: { paid_amount, period_years, renewed_until } | — | SuperAdminGuard, @AllowNoTenant | Marcar renovado |
| POST | `/admin/managed-domains/:id/manual-renewal` | inline: { period_years? } | — | SuperAdminGuard, @AllowNoTenant | Renovación manual |
| POST | `/admin/managed-domains/:id/mark-failed` | inline: { reason } | — | SuperAdminGuard, @AllowNoTenant | Marcar fallido |
| POST | `/admin/managed-domains/:id/verify-dns` | — | — | SuperAdminGuard, @AllowNoTenant | Verificar DNS |
| POST | `/admin/managed-domains/account/:accountId/verify-dns` | — | — | SuperAdminGuard, @AllowNoTenant | Verificar DNS por cuenta |

---

## 13. admin/media

**Controller:** `admin/media-admin.controller.ts` — Prefix: `admin/media`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| DELETE | `/admin/media/clients/:clientId` | — | — | SuperAdminGuard, @AllowNoTenant | Eliminar media de cliente |
| DELETE | `/admin/media/clients/:clientId/stats` | — | — | SuperAdminGuard, @AllowNoTenant | **⚠️ AUDIT: @Delete en endpoint /stats — prob. debería ser GET** |

---

## 14. admin/metering

**Controller:** `metrics/metrics.controller.ts` — Prefix: `admin/metering`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| POST | `/admin/metering/sync` | — | — | SuperAdminGuard, @AllowNoTenant | Sincronizar métricas |
| GET | `/admin/metering/summary` | — | — | SuperAdminGuard, @AllowNoTenant | Resumen metering |

---

## 15. admin/option-sets

**Controller:** `admin/admin-option-sets.controller.ts` — Prefix: `admin/option-sets`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/admin/option-sets` | — | — | SuperAdminGuard, @AllowNoTenant | Listar globales |
| GET | `/admin/option-sets/stats` | — | — | SuperAdminGuard, @AllowNoTenant | Estadísticas |
| GET | `/admin/option-sets/:id` | — | — | SuperAdminGuard, @AllowNoTenant | Detalle |
| POST | `/admin/option-sets` | `CreateOptionSetDto` | — | SuperAdminGuard, @AllowNoTenant | Crear |
| PUT | `/admin/option-sets/:id` | `UpdateOptionSetDto` | — | SuperAdminGuard, @AllowNoTenant | Actualizar |
| DELETE | `/admin/option-sets/:id` | — | — | SuperAdminGuard, @AllowNoTenant | Eliminar |
| POST | `/admin/option-sets/:id/duplicate` | — | — | SuperAdminGuard, @AllowNoTenant | Duplicar |

---

## 16. admin/plans

**Controller:** `plans/plans-admin.controller.ts` — Prefix: `admin/plans`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/admin/plans` | — | — | SuperAdminGuard, @AllowNoTenant | Listar planes |
| GET | `/admin/plans/:planKey` | — | — | SuperAdminGuard, @AllowNoTenant | Detalle plan |
| PATCH | `/admin/plans/:planKey` | inline | — | SuperAdminGuard, @AllowNoTenant | Editar plan |
| GET | `/admin/plans/clients/usage` | — | — | SuperAdminGuard, @AllowNoTenant | Uso todos clientes |
| GET | `/admin/plans/clients/:clientId/usage` | — | — | SuperAdminGuard, @AllowNoTenant | Uso cliente |
| GET | `/admin/plans/clients/:clientId/features` | — | — | SuperAdminGuard, @AllowNoTenant | Features cliente |
| PATCH | `/admin/plans/clients/:clientId/features` | inline | — | SuperAdminGuard, @AllowNoTenant | Override features |
| GET | `/admin/plans/clients/:clientId/entitlements` | — | — | SuperAdminGuard, @AllowNoTenant | Entitlements |
| PATCH | `/admin/plans/clients/:clientId/entitlements` | inline | — | SuperAdminGuard, @AllowNoTenant | Override entitlements |

---

## 17. admin/quotas

**Controller:** `admin/admin-quotas.controller.ts` — Prefix: `admin/quotas`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/admin/quotas` | — | — | SuperAdminGuard, @AllowNoTenant | Listar todas las cuotas |
| GET | `/admin/quotas/:tenantId` | — | — | SuperAdminGuard, @AllowNoTenant | Cuota de tenant |
| PATCH | `/admin/quotas/:tenantId` | `UpdateQuotaStateDto` | — | SuperAdminGuard, @AllowNoTenant | Override estado |
| POST | `/admin/quotas/:tenantId/reset` | — | — | SuperAdminGuard, @AllowNoTenant | Reset cuotas |

**UpdateQuotaStateDto:** state (IsIn QUOTA_STATES), grace_until? (string)

---

## 18. admin/renewals

**Controller:** `admin/admin-renewals.controller.ts` — Prefix: `admin/renewals`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| POST | `/admin/renewals/:id/checkout` | inline | — | SuperAdminGuard, @AllowNoTenant | Checkout renovación |
| POST | `/admin/renewals/:id/send-email` | inline | — | SuperAdminGuard, @AllowNoTenant | Enviar email |

---

## 19. admin/seo-ai-billing

**Controller:** `seo-ai-billing/seo-ai-billing-admin.controller.ts` — Prefix: `admin/seo-ai-billing`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/admin/seo-ai-billing/packs` | — | — | SuperAdminGuard, @AllowNoTenant | Listar packs |
| PATCH | `/admin/seo-ai-billing/packs/:addonKey` | inline | — | SuperAdminGuard, @AllowNoTenant | Editar pack |
| GET | `/admin/seo-ai-billing/credits/:accountId/balance` | — | — | SuperAdminGuard, @AllowNoTenant | Balance créditos |
| GET | `/admin/seo-ai-billing/credits/:accountId` | — | — | SuperAdminGuard, @AllowNoTenant | Detalle créditos |
| PATCH | `/admin/seo-ai-billing/credits/:accountId` | inline | — | SuperAdminGuard, @AllowNoTenant | Ajustar créditos |
| GET | `/admin/seo-ai-billing/pricing` | — | — | SuperAdminGuard, @AllowNoTenant | Pricing |
| PATCH | `/admin/seo-ai-billing/pricing/:entityType` | inline | — | SuperAdminGuard, @AllowNoTenant | Editar pricing |

---

## 20. admin/shipping

**Controller:** `admin/admin-shipping.controller.ts` — Prefix: `admin/shipping`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/admin/shipping/overview` | — | — | SuperAdminGuard, @AllowNoTenant | Resumen shipping |
| GET | `/admin/shipping/shipments` | — | — | SuperAdminGuard, @AllowNoTenant | Listar envíos |
| GET | `/admin/shipping/integrations` | — | — | SuperAdminGuard, @AllowNoTenant | Integraciones |
| GET | `/admin/shipping/webhook-failures` | — | — | SuperAdminGuard, @AllowNoTenant | Fallos webhook |
| POST | `/admin/shipping/webhook-failures/:failureId/retry` | — | — | SuperAdminGuard, @AllowNoTenant | Reintentar |

---

## 21. admin/store-coupons

**Controller:** `store-coupons/admin-store-coupons.controller.ts` — Prefix: `admin/store-coupons`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/admin/store-coupons` | — | — | SuperAdminGuard, @AllowNoTenant | Listar |
| GET | `/admin/store-coupons/stats` | — | — | SuperAdminGuard, @AllowNoTenant | Estadísticas |
| GET | `/admin/store-coupons/access` | — | — | SuperAdminGuard, @AllowNoTenant | Acceso por plan |
| PATCH | `/admin/store-coupons/plan-defaults` | inline | — | SuperAdminGuard, @AllowNoTenant | Defaults por plan |
| PATCH | `/admin/store-coupons/access/:clientId` | inline | — | SuperAdminGuard, @AllowNoTenant | Override acceso |

---

## 22. admin/super-emails

**Controller:** `superadmin/super-admin-email-jobs.controller.ts` — Prefix: `admin/super-emails`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/admin/super-emails` | — | — | SuperAdminGuard, @AllowNoTenant | Listar jobs |
| POST | `/admin/super-emails/:id/retry` | — | — | SuperAdminGuard, @AllowNoTenant | Reintentar |
| POST | `/admin/super-emails/:id/resend` | — | — | SuperAdminGuard, @AllowNoTenant | Reenviar |

---

## 23. admin/support

**Controller:** `support/support-admin.controller.ts` — Prefix: `admin/support`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/admin/support/metrics` | — | — | SuperAdminGuard, @AllowNoTenant | Métricas soporte |
| GET | `/admin/support/tickets` | — | `TicketFiltersDto` (query) | SuperAdminGuard, @AllowNoTenant | Listar tickets |
| GET | `/admin/support/tickets/:ticketId` | — | — | SuperAdminGuard, @AllowNoTenant | Detalle ticket |
| GET | `/admin/support/tickets/:ticketId/messages` | — | — | SuperAdminGuard, @AllowNoTenant | Mensajes |
| GET | `/admin/support/tickets/:ticketId/events` | — | — | SuperAdminGuard, @AllowNoTenant | Eventos |
| PATCH | `/admin/support/tickets/:ticketId` | `UpdateTicketDto` | — | SuperAdminGuard, @AllowNoTenant | Actualizar ticket |
| POST | `/admin/support/tickets/:ticketId/messages` | `CreateMessageDto` | — | SuperAdminGuard, @AllowNoTenant | Enviar mensaje |
| PATCH | `/admin/support/tickets/:ticketId/assign` | inline: { agent_id } | — | SuperAdminGuard, @AllowNoTenant | Asignar agente |
| GET | `/admin/support/accounts/:accountId/ticket-limit` | — | — | SuperAdminGuard, @AllowNoTenant | Límite tickets |
| PATCH | `/admin/support/accounts/:accountId/ticket-limit` | inline | — | SuperAdminGuard, @AllowNoTenant | Editar límite |

**TicketFiltersDto (Query):** status?, priority?, category?, account_id?, assigned_agent_id?, search?, plan?, sla_breached?, page (0-based), page_size (default 20), sort_by (default updated_at), sort_order (default desc)  
**UpdateTicketDto:** status? (IsIn 6 estados), priority? (IsIn 4 niveles), assigned_agent_id? (UUID), tags? (IsArray IsString)  
**CreateMessageDto:** body (MaxLength 10000), attachments? (AttachmentDto[]: name, url, size?, type?), is_internal? (solo super admin)

---

## 24. admin/system

**Controller:** `observability/system.controller.ts` — Prefix: `admin/system`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/admin/system/health` | — | — | SuperAdminGuard, @AllowNoTenant | Health check sistema |
| GET | `/admin/system/audit/recent` | — | — | SuperAdminGuard, @AllowNoTenant | Eventos recientes |

---

## 25. analytics

**Controller:** `analytics/analytics.controller.ts` — Prefix: `api/analytics`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/api/analytics/summary` | — | — | ClientContextGuard, PlanAccessGuard | @PlanFeature('dashboard.analytics') |

---

## 26. auth

**Controller:** `auth/auth.controller.ts` — Prefix: `auth` (568 líneas)

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| POST | `/auth/internal-key/verify` | inline | — | — | Verificar key interna |
| POST | `/auth/internal-key/revoke` | inline | — | — | Revocar key |
| POST | `/auth/bridge/generate` | inline | — | — | Generar bridge token |
| POST | `/auth/bridge/exchange` | inline | — | — | Exchange bridge token |
| POST | `/auth/signup` | inline: { email, password, firstName, lastName, clientId } | — | @AllowNoTenant | Registro usuario |
| POST | `/auth/login` | inline: { email, password } | — | @AllowNoTenant | Login |
| POST | `/auth/google/start` | inline: { clientId, returnUrl? } | — | @AllowNoTenant | Iniciar Google OAuth |
| POST | `/auth/tenant/google/callback` | inline | — | @AllowNoTenant | Callback Google |
| GET | `/auth/validate-token` | — | — | — | Headers: Authorization, x-client-id |
| GET | `/auth/confirm-email` | — | ?access_token, ?token, ?type | @AllowNoTenant | Confirmar email |
| POST | `/auth/resend-confirmation` | inline: { email, redirectBase? } | — | @AllowNoTenant | Reenviar confirmación |
| GET | `/auth/email-callback` | — | ?cid | @AllowNoTenant | Gateway callback email → storefront |
| POST | `/auth/forgot-password` | inline: { email } | — | @AllowNoTenant | Solicitar reset |
| POST | `/auth/reset-password` | inline: { token, password } | — | @AllowNoTenant | Reset password |
| POST | `/auth/change-password` | inline: { newPassword } | — | @AllowNoTenant | Cambiar password |
| GET | `/auth/session` | — | — | @AllowNoTenant | Sesión multi-tenant |
| POST | `/auth/switch-client` | inline: { client_id } | — | @AllowNoTenant | Cambiar tenant |
| GET | `/auth/hub-context` | — | — | @AllowNoTenant | Contexto hub |
| POST | `/auth/session/sync` | — | — | TenantContextGuard | Sync sesión multi-tenant |

---

## 27. banner

**Controller:** `banner/banner.controller.ts` — Prefix: `settings/banner`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/settings/banner` | — | — | — | Banner activo |
| GET | `/settings/banner/all` | — | — | — | Todos los banners |
| POST | `/settings/banner` | FormData | — | RolesGuard (admin/super_admin), PlanLimitsGuard | @PlanAction('create_banner') |
| PATCH | `/settings/banner` | FormData | — | RolesGuard (admin/super_admin) | Actualizar banner |
| DELETE | `/settings/banner` | — | — | RolesGuard (admin/super_admin) | Eliminar banner |

---

## 28. billing

**Controller:** `billing/billing.controller.ts` — Prefix: `billing`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/billing/admin/all` | — | — | PlatformAuthGuard | @AllowNoTenant — Listar todos los billing |
| POST | `/billing/admin/:id/mark-paid` | inline | — | PlatformAuthGuard | @AllowNoTenant — Marcar pagado |
| POST | `/billing/admin/:id/sync` | inline | — | PlatformAuthGuard | @AllowNoTenant — Sincronizar |
| GET | `/billing/me` | — | — | @AllowNoTenant | Mi billing |

---

## 29. cart

**Controller:** `cart/cart.controller.ts` — Prefix: `api/cart`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| POST | `/api/cart` | `AddCartItemDto` | — | ClientContextGuard | Agregar al carrito |
| GET | `/api/cart` | — | — | ClientContextGuard | Ver carrito |
| PUT | `/api/cart/:id` | inline: { quantity } | — | ClientContextGuard | Actualizar cantidad |
| DELETE | `/api/cart/:id` | — | — | ClientContextGuard | Eliminar item |

**AddCartItemDto:** productId (UUID), quantity (Int, Min 1), expectedPrice? (Number), selectedOptions? (SelectedOptionDto[]: key, label, value, system?)

---

## 30. categories

**Controller:** `categories/categories.controller.ts` — Prefix: `categories`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| POST | `/categories` | inline | — | RolesGuard (admin/super_admin) | Crear categoría |
| GET | `/categories` | — | — | — | Listar |
| GET | `/categories/:id` | — | — | — | Detalle |
| PUT | `/categories/:id` | inline | — | RolesGuard (admin/super_admin) | Actualizar |
| DELETE | `/categories/:id` | — | — | RolesGuard (admin/super_admin) | Eliminar |

---

## 31. client-dashboard

**Controller:** `client-dashboard/client-dashboard.controller.ts` — Prefix: `client-dashboard`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/client-dashboard/completion-checklist` | — | — | ClientDashboardGuard, @AllowNoTenant | Checklist |
| POST | `/client-dashboard/completion-checklist/update` | inline | — | ClientDashboardGuard, @AllowNoTenant | Actualizar |
| POST | `/client-dashboard/completion-checklist/resubmit` | inline | — | ClientDashboardGuard, @AllowNoTenant | Reenviar |
| POST | `/client-dashboard/products` | inline | — | ClientDashboardGuard, @AllowNoTenant | Crear producto |
| POST | `/client-dashboard/categories` | inline | — | ClientDashboardGuard, @AllowNoTenant | Crear categoría |
| POST | `/client-dashboard/faqs` | inline | — | ClientDashboardGuard, @AllowNoTenant | Crear FAQ |
| POST | `/client-dashboard/contact-info` | inline | — | ClientDashboardGuard, @AllowNoTenant | Crear contacto |
| POST | `/client-dashboard/social-links` | inline | — | ClientDashboardGuard, @AllowNoTenant | Crear social link |
| POST | `/client-dashboard/import-json` | inline | — | ClientDashboardGuard, @AllowNoTenant | Import JSON |
| GET | `/client-dashboard/products/list` | — | — | ClientDashboardGuard, @AllowNoTenant | Lista productos |
| GET | `/client-dashboard/categories/list` | — | — | ClientDashboardGuard, @AllowNoTenant | Lista categorías |
| GET | `/client-dashboard/faqs/list` | — | — | ClientDashboardGuard, @AllowNoTenant | Lista FAQs |
| GET | `/client-dashboard/contact-info` | — | — | ClientDashboardGuard, @AllowNoTenant | Info contacto |
| GET | `/client-dashboard/social-links` | — | — | ClientDashboardGuard, @AllowNoTenant | Social links |
| GET | `/client-dashboard/domain` | — | — | ClientDashboardGuard, @AllowNoTenant | Info dominio |
| POST | `/client-dashboard/domain/renew` | inline | — | ClientDashboardGuard, @AllowNoTenant | Renovar dominio |

---

## 32. client/managed-domains

**Controller:** `client-dashboard/client-managed-domain.controller.ts` — Prefix: `client/managed-domains`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/client/managed-domains` | — | — | TenantContextGuard | Dominios del tenant |

---

## 33. clients

**Controller:** `clients/clients.controller.ts` — Prefix: `clients`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/clients/me/requirements` | — | — | — | Requisitos del cliente |
| POST | `/clients/me/request-publish` | inline | — | — | Solicitar publicación |

---

## 34. contact-info

**Controller:** `contact-info/contact-info.controller.ts` — Prefix: `contact-info`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/contact-info` | — | — | — | Listar |
| POST | `/contact-info` | inline | — | RolesGuard (admin/super_admin) | Crear |
| PUT | `/contact-info/:id` | inline | — | RolesGuard (admin/super_admin) | Actualizar |
| DELETE | `/contact-info/:id` | — | — | RolesGuard (admin/super_admin) | Eliminar |

---

## 35. cors-origins

**Controller:** `cors-origins/cors-origins.controller.ts` — Prefix: `cors-origins`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/cors-origins` | — | — | SuperAdminGuard, @AllowNoTenant | Listar |
| POST | `/cors-origins` | inline | — | SuperAdminGuard, @AllowNoTenant | Crear |
| PATCH | `/cors-origins/:id` | inline | — | SuperAdminGuard, @AllowNoTenant | Actualizar |
| DELETE | `/cors-origins/:id` | — | — | SuperAdminGuard, @AllowNoTenant | Eliminar |

---

## 36. coupons

**Controller:** `coupons/coupons.controller.ts` — Prefix: `coupons`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| POST | `/coupons/validate` | `ValidateCouponDto` | — | BuilderOrSupabaseGuard, @AllowNoTenant | Validar cupón plataforma |

**ValidateCouponDto:** code (IsNotEmpty IsString), planKey (IsNotEmpty IsString), accountId (IsNotEmpty IsUUID)

---

## 37. debug

**Controller:** `debug/debug.controller.ts` — Prefix: `debug`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/debug/whoami` | — | — | SuperAdminGuard, @AllowNoTenant | Identity debug |

---

## 38. demo

**Controller:** `demo/demo.controller.ts` — Prefix: `demo`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| POST | `/demo/seed` | inline | — | BuilderSessionGuard | Seed datos demo |

---

## 39. dev/portal

**Controller:** `dev/dev-portal.controller.ts` — Prefix: `dev/portal`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/dev/portal/verify-access` | — | — | — | Verificar acceso portal dev |
| GET | `/dev/portal/health` | — | — | — | Health check |
| GET | `/dev/portal/whitelist` | — | — | SuperAdminGuard | Listar whitelist |
| POST | `/dev/portal/whitelist` | inline | — | — | Agregar a whitelist |
| PATCH | `/dev/portal/whitelist/:email` | inline | — | — | Editar whitelist |
| DELETE | `/dev/portal/whitelist/:email` | — | — | — | Eliminar de whitelist |

---

## 40. dev (seeding)

**Controller:** `dev/dev-seeding.controller.ts` — Prefix: `dev`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| POST | `/dev/seed-tenant` | inline | — | SuperAdminGuard, @AllowNoTenant | Seed tenant de prueba |
| GET | `/dev/tenants` | — | — | SuperAdminGuard, @AllowNoTenant | Listar tenants dev |
| DELETE | `/dev/tenants/:slug` | — | — | SuperAdminGuard, @AllowNoTenant | Eliminar tenant dev |

---

## 41. faq

**Controller:** `faq/faq.controller.ts` — Prefix: `settings/faqs`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/settings/faqs` | — | — | — | Listar FAQs |
| POST | `/settings/faqs` | inline | — | RolesGuard (admin/super_admin) | Crear |
| PUT | `/settings/faqs` | inline | — | RolesGuard (admin/super_admin) | Actualizar |
| DELETE | `/settings/faqs` | — | — | RolesGuard (admin/super_admin) | Eliminar |

---

## 42. favorites

**Controller:** `favorites/favorites.controller.ts` — Prefix: `favorites`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/favorites` | — | — | — | Listar favoritos |
| POST | `/favorites/merge` | inline: { productIds[] } | — | — | Merge guest→user |
| POST | `/favorites/:productId` | — | — | — | Agregar favorito |
| DELETE | `/favorites/:productId` | — | — | — | Eliminar favorito |

---

## 43. health

**Controller:** `health/health.controller.ts` — Prefix: `health`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/health` | — | — | @AllowNoTenant | Health check básico |
| GET | `/health/live` | — | — | @AllowNoTenant | Liveness probe |
| GET | `/health/ready` | — | — | @AllowNoTenant | Readiness probe |

---

## 44. home

**Controller:** `home/home.controller.ts` — Prefix: `home`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/home/data` | — | — | — | Datos home completos |
| GET | `/home/navigation` | — | — | — | Navegación |
| GET | `/home/sections` | — | — | TenantContextGuard | Secciones home |
| POST | `/home/sections` | `AddSectionDto` (Zod) | — | — | Agregar sección |
| PATCH | `/home/sections/order` | `UpdateOrderDto` (Zod) | — | — | Reordenar secciones |
| PATCH | `/home/sections/:id/replace` | `ReplaceSectionDto` (Zod) | — | — | Reemplazar sección |
| DELETE | `/home/sections/:id` | — | — | — | Eliminar sección |

**AddSectionDto (Zod):** type (string), insert_after_id? (uuid), props? (Record)  
**UpdateOrderDto (Zod):** ordered_ids (array uuid, min 1)  
**ReplaceSectionDto (Zod):** new_type (string), props? (Record)

---

## 45. home-settings

**Controller:** `home/home-settings.controller.ts` — Prefix: `settings/home`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/settings/home` | — | — | — | Config home |
| PUT | `/settings/home` | inline | — | RolesGuard (admin/super_admin) | Actualizar config |
| PATCH | `/settings/home/identity` | `IdentitySettingsDto` | — | RolesGuard (admin/super_admin) | Actualizar identidad |
| POST | `/settings/home/popup-image` | FormData | — | RolesGuard (admin/super_admin) | Upload popup image |
| DELETE | `/settings/home/popup-image` | — | — | RolesGuard (admin/super_admin) | Eliminar popup image |

**IdentitySettingsDto:** socials? (SocialLinkDto[]: network, url, active), banners? (BannerDto[]: id, text, link?, active), footer? (FooterConfigDto: links[], copyright?, showBrand?), version?

---

## 46. legal

**Controller:** `legal/legal.controller.ts` — Prefix: `legal`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/legal/documents` | — | — | @AllowNoTenant | Listar documentos legales |
| GET | `/legal/documents/:type` | — | — | — | Documento por tipo |
| POST | `/legal/buyer-consent` | inline | — | — | Registrar consentimiento |
| POST | `/legal/withdrawal` | inline | — | — | Solicitar retractación |
| GET | `/legal/withdrawal/:trackingCode` | — | — | — | Estado retractación |
| GET | `/legal/withdrawals` | — | — | — | Listar retractaciones |
| PATCH | `/legal/withdrawal/:id` | inline | — | — | Actualizar retractación |
| GET | `/legal/withdrawal/order/:orderId` | — | — | — | Retractación por orden |
| POST | `/legal/cancellation` | inline | — | SuperAdminGuard | Cancelar (admin) |
| GET | `/legal/cancellation/:trackingCode` | — | — | — | Estado cancelación |

---

## 47. logo

**Controller:** `logo/logo.controller.ts` — Prefix: `settings/logo`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/settings/logo` | — | — | — | Obtener logo |
| POST | `/settings/logo` | FormData | — | RolesGuard (admin/super_admin) | Upload logo |
| DELETE | `/settings/logo` | — | — | RolesGuard (admin/super_admin) | Eliminar logo |

---

## 48. mercadopago

**Controller:** `tenant-payments/mercadopago.controller.ts` — Prefix: `mercadopago` (1561 líneas)  
**Pipe global:** ValidationPipe (transform, whitelist)

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| POST | `/mercadopago/quote` | `QuoteDto` | — | — | Cotizar pago |
| PUT | `/mercadopago/preferences/:id/payment-methods` | `UpdatePaymentMethodsDto` | — | — | Actualizar métodos pago |
| POST | `/mercadopago/create-preference-for-plan` | `CreatePrefForPlanDto` | — | — | Preferencia para plan (idempotente) |
| POST | `/mercadopago/create-preference-advanced` | `CreatePrefAdvancedDto` | — | — | Preferencia avanzada (idempotente) |
| POST | `/mercadopago/validate-cart` | `ValidateCartDto` | — | — | Validar carrito vs stock/precios |
| POST | `/mercadopago/create-preference` | `CreatePreferenceDto` | — | — | Preferencia simple |
| POST | `/mercadopago/confirm-payment` | `ConfirmPaymentDto` | — | — | Confirmar pago |
| POST | `/mercadopago/notification` | raw body | — | @AllowNoTenant | **Webhook MP (IPN)** |
| POST | `/mercadopago/webhook` | raw body | — | @AllowNoTenant | **Webhook MP v2** |
| GET | `/mercadopago/payment-details` | — | `PaymentDetailsQueryDto` | — | Detalles pago |
| GET | `/mercadopago/payment-details/:paymentId` | — | — | — | Detalles pago por ID |
| POST | `/mercadopago/confirm-by-reference` | `ConfirmByReferenceDto` | — | — | Confirmar por referencia |
| POST | `/mercadopago/confirm-by-preference` | `ConfirmByPreferenceDto` | — | — | Confirmar por preferencia |
| POST | `/mercadopago/subscriptions/reconcile` | inline | — | — | Reconciliar suscripciones |
| GET | `/mercadopago/debug/email` | — | — | — | Debug email |

**DTOs principales:**
- **QuoteDto:** subtotal, method? (debit_card/credit_card/other), installments? (Min 1), settlementDays? (Min 0), partial?
- **CreatePrefForPlanDto:** baseAmount (Positive), selection (SelectionDto: method, installmentsSeed, settlementDays?, planKey?), cartItems? (ItemAdvancedDto[]), delivery? (DeliveryPayloadDto), couponCode?
- **CreatePrefAdvancedDto:** items (ItemAdvancedDto[]), totals (TotalsDto: total, currency?), paymentMode (total/partial), partialPercent?, partialAmount?, selection?, metadata?, couponCode?, userId?
- **ValidateCartDto:** cartItems (CartItemDto[]: product_id, product (CartProductDto), quantity Min 1)
- **CreatePreferenceDto:** cartItems (CartItemDto[]), paymentType?, paymentMode?, selection?, metadata?
- **DeliveryPayloadDto:** method (delivery/pickup/arrange), quote_id?, address? (ShippingAddressInputDto), address_id?, save_address?, shipping_cost?

---

## 49. mp/oauth

**Controller:** `mp-oauth/mp-oauth.controller.ts` — Prefix: `mp/oauth`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/mp/oauth/start` | — | — | @AllowNoTenant | Iniciar OAuth MP |
| GET | `/mp/oauth/callback` | — | ?code, ?state | @AllowNoTenant | Callback OAuth |
| GET | `/mp/oauth/start-url` | — | — | RolesGuard (admin/super_admin) | URL para iniciar |
| GET | `/mp/oauth/status/:clientId` | — | — | RolesGuard | Estado conexión MP |
| POST | `/mp/oauth/disconnect/:clientId` | — | — | RolesGuard | Desconectar MP |
| POST | `/mp/oauth/refresh/:accountId` | — | — | @Roles('super_admin') | Refrescar token |

---

## 50. oauth-relay

**Controller:** `auth/oauth-relay.controller.ts` — Prefix: `oauth`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/oauth/callback` | — | query params | @AllowNoTenant | OAuth relay callback |
| GET | `/oauth/callback.js` | — | — | @AllowNoTenant | JS relay script |
| POST | `/oauth/diagnose` | inline | — | @AllowNoTenant | Diagnóstico OAuth |

---

## 51. onboarding

**Controller:** `onboarding/onboarding.controller.ts` — Prefix: `onboarding` (1247 líneas)

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/onboarding/active-countries` | — | — | @AllowNoTenant | Países activos |
| GET | `/onboarding/country-config/:countryId` | — | — | @AllowNoTenant | Config país |
| POST | `/onboarding/builder/start` | inline: { email, slug } | — | @AllowNoTenant | Iniciar builder gratis |
| POST | `/onboarding/resolve-link` | inline: { token } | — | @AllowNoTenant | Resolver link onboarding |
| POST | `/onboarding/complete-owner` | inline: { token, password, firstName, lastName, phone? } | — | BuilderSessionGuard, @AllowNoTenant | Completar owner |
| POST | `/onboarding/import-home-bundle` | inline: { bundle } (validado con Zod → HomeDataLite) | — | BuilderSessionGuard, @AllowNoTenant | Import bundle completo |
| GET | `/onboarding/status` | — | — | BuilderSessionGuard, @AllowNoTenant | Estado onboarding |
| GET | `/onboarding/public/status` | — | ?slug | @AllowNoTenant | Estado público |
| PATCH | `/onboarding/progress` | inline: any (filtrado) | — | BuilderSessionGuard, @AllowNoTenant | Actualizar progreso |
| PATCH | `/onboarding/preferences` | inline: { templateKey?, paletteKey?, themeOverride? } | — | BuilderSessionGuard, @AllowNoTenant | Actualizar preferencias |
| PATCH | `/onboarding/custom-domain` | inline: { domain?, mode?, details? } | — | BuilderSessionGuard, @AllowNoTenant | Dominio personalizado |
| GET | `/onboarding/plans` | — | — | @AllowNoTenant | Planes publicados |
| GET | `/onboarding/palettes` | — | — | @AllowNoTenant | Paletas (auth opcional) |
| POST | `/onboarding/preview-token` | — | — | BuilderSessionGuard, @AllowNoTenant | Token preview (1h) |
| POST | `/onboarding/checkout/start` | inline: { planId, cycle?, couponCode? } | — | BuilderSessionGuard, @AllowNoTenant | Iniciar checkout |
| GET | `/onboarding/checkout/status` | — | — | BuilderSessionGuard, @AllowNoTenant | Estado checkout |
| POST | `/onboarding/checkout/confirm` | inline: { status?, external_reference?, preapproval_id? } | — | BuilderSessionGuard, @AllowNoTenant | Confirmar checkout |
| POST | `/onboarding/link-google` | inline: { email } | — | BuilderSessionGuard, @AllowNoTenant | Vincular Google |
| POST | `/onboarding/checkout/webhook` | raw body | — | @AllowNoTenant | **Webhook MP onboarding** |
| POST | `/onboarding/business-info` | inline (business_name, fiscal_id, fiscal_address, phone, billing_email, persona_type?, legal_name?, fiscal_category?, subdivision_code?) | — | BuilderSessionGuard, @AllowNoTenant | Info negocio |
| POST | `/onboarding/mp-credentials` | inline: { access_token, public_key } | — | BuilderSessionGuard, @AllowNoTenant | Credenciales MP |
| POST | `/onboarding/submit-for-review` | inline: { templateKey?, paletteKey?, themeOverride?, customPalettes?, designConfig?, catalog?, assets? } | — | BuilderSessionGuard, @AllowNoTenant | Enviar a revisión |
| POST | `/onboarding/submit` | inline (mismo schema que submit-for-review) | — | BuilderSessionGuard, @AllowNoTenant | Guardar wizard data |
| POST | `/onboarding/publish` | — | — | BuilderSessionGuard, @AllowNoTenant | Publicar tienda |
| POST | `/onboarding/logo/upload-url` | — | — | BuilderSessionGuard, @AllowNoTenant | URL upload logo |
| POST | `/onboarding/clients/:clientId/mp-secrets` | inline: { mp_access_token, mp_public_key } | — | BuilderSessionGuard, @AllowNoTenant | Guardar MP secrets |
| POST | `/onboarding/session/save` | inline: { templateKey?, paletteKey?, themeOverride?, designConfig?, catalogData?, assets? } | — | BuilderSessionGuard, @AllowNoTenant | Auto-save sesión |
| POST | `/onboarding/session/upload` | FormData (file + type) | — | BuilderSessionGuard, @AllowNoTenant | Upload asset sesión |
| POST | `/onboarding/session/link-user` | inline: { user_id } | — | BuilderSessionGuard, @AllowNoTenant | Vincular usuario |
| GET | `/onboarding/mp-status` | — | — | BuilderSessionGuard, @AllowNoTenant | Estado conexión MP |
| POST | `/onboarding/session/accept-terms` | inline: { version } | — | BuilderSessionGuard, @AllowNoTenant | Aceptar términos |
| GET | `/onboarding/resume` | — | ?user_id | BuilderOrSupabaseGuard, @AllowNoTenant | Reanudar sesión |
| POST | `/onboarding/approve/:accountId` | — | — | SuperAdminGuard, @AllowNoTenant | Aprobar onboarding |

---

## 52. option-sets

**Controller:** `option-sets/option-sets.controller.ts` — Prefix: `option-sets`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/option-sets` | — | — | PlanAccessGuard | @PlanFeature('commerce.option_sets') |
| GET | `/option-sets/:id` | — | — | PlanAccessGuard | Detalle |
| POST | `/option-sets` | `CreateOptionSetDto` | — | RolesGuard, PlanAccessGuard | @PlanFeature('commerce.option_sets') |
| PUT | `/option-sets/:id` | `UpdateOptionSetDto` | — | RolesGuard | Actualizar |
| DELETE | `/option-sets/:id` | — | — | RolesGuard | Eliminar |
| POST | `/option-sets/:id/duplicate` | — | — | RolesGuard | Duplicar |
| GET | `/option-sets/size-guides/list` | — | — | PlanAccessGuard | Lista size guides |
| GET | `/option-sets/size-guides/by-context` | — | query params | PlanAccessGuard | Size guide por contexto |
| GET | `/option-sets/size-guides/:id` | — | — | PlanAccessGuard | Detalle size guide |
| POST | `/option-sets/size-guides` | `CreateSizeGuideDto` | — | RolesGuard | Crear size guide |
| PUT | `/option-sets/size-guides/:id` | `UpdateSizeGuideDto` | — | RolesGuard | Actualizar |
| DELETE | `/option-sets/size-guides/:id` | — | — | RolesGuard | Eliminar |

**CreateOptionSetDto:** code, name, type? (apparel/footwear/accessory/generic), system?, metadata?, items? (OptionSetItemDto[]: value, label, position?, metadata?, is_active?)  
**CreateSizeGuideDto:** option_set_id? (UUID), product_id? (UUID), name?, columns[], rows[] ({label, values[]}), notes?

---

## 53. orders

**Controller:** `orders/orders.controller.ts` — Prefix: `orders`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/orders` | — | query params | ClientContextGuard | Listar órdenes |
| GET | `/orders/search` | — | query params | ClientContextGuard | Buscar |
| GET | `/orders/track/:publicCode` | — | — | ClientContextGuard | Tracking público |
| GET | `/orders/external/ref/:externalReference` | — | — | ClientContextGuard | Por referencia externa |
| GET | `/orders/user/:userId` | — | — | ClientContextGuard | Órdenes de usuario |
| GET | `/orders/status/:externalReference` | — | — | ClientContextGuard | Estado por referencia |
| GET | `/orders/:orderId` | — | — | ClientContextGuard | Detalle orden |
| PATCH | `/orders/:orderId/status` | inline: { status } | — | ClientContextGuard, RolesGuard | Cambiar estado |
| PATCH | `/orders/:orderId/tracking` | inline: { tracking_number, carrier? } | — | ClientContextGuard, RolesGuard | Actualizar tracking |
| POST | `/orders/:orderId/send-confirmation` | — | — | ClientContextGuard | Reenviar confirmación |

---

## 54. palettes

**Controller:** `palettes/palettes.controller.ts` — Prefix: `palettes`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/palettes/catalog` | — | — | @AllowNoTenant | Catálogo público |
| GET | `/palettes/admin/catalog` | — | — | SuperAdminGuard | Catálogo admin |
| GET | `/palettes` | — | — | BuilderSessionGuard | Paletas del builder |
| POST | `/palettes/custom` | inline | — | BuilderSessionGuard | Crear custom |
| PUT | `/palettes/custom/:id` | inline | — | BuilderSessionGuard | Editar custom |
| DELETE | `/palettes/custom/:id` | — | — | BuilderSessionGuard | Eliminar custom |
| POST | `/palettes/admin` | inline | — | SuperAdminGuard | Crear paleta admin |
| PUT | `/palettes/admin/:key` | inline | — | SuperAdminGuard | Editar paleta admin |
| DELETE | `/palettes/admin/:key` | — | — | SuperAdminGuard | Eliminar paleta admin |

---

## 55. payments (admin)

**Controller:** `payments/admin-payments.controller.ts` — Prefix: `api/admin/payments`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/api/admin/payments/mp-fees` | — | — | TenantContextGuard, RolesGuard, PlanAccessGuard | @PlanFeature('dashboard.payments'), @Roles('admin','super_admin') |
| PUT | `/api/admin/payments/config` | `UpdateSettingsDto` | — | TenantContextGuard, RolesGuard, PlanAccessGuard | Actualizar config pagos |
| GET | `/api/admin/payments/config` | — | — | TenantContextGuard, RolesGuard, PlanAccessGuard | Config actual |

**UpdateSettingsDto:** allowPartial?, partialPercent?, allowInstallments?, maxInstallments?, surchargeMode? (none/seller_absorbs/buyer_pays/split), surchargePercent?, defaultSettlementDays?, allowedSettlementDays?[], roundingStep? — **⚠️ Sin decoradores class-validator**

---

## 56. payments (storefront)

**Controller:** `payments/payments.controller.ts` — Prefix: `api/payments`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/api/payments/config` | — | — | ClientContextGuard | Config pagos para storefront |
| POST | `/api/payments/quote` | `QuoteDto` (payments) | — | ClientContextGuard | Cotizar |
| POST | `/api/payments/quote-matrix` | inline | — | ClientContextGuard | Matriz de cotización |
| POST | `/api/payments/preference` | inline | — | ClientContextGuard | Crear preferencia |

**QuoteDto (payments):** subtotal, installments, method (debit_card/credit_card/account_money/bank_transfer/ticket/other), settlementDays?, partial? — **⚠️ Sin decoradores class-validator**

---

## 57. plans

**Controller:** `plans/plans.controller.ts` — Prefix: `plans`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/plans/catalog` | — | — | @AllowNoTenant | Catálogo de planes público |
| GET | `/plans/pricing` | — | — | @AllowNoTenant | Pricing |
| GET | `/plans/my-limits` | — | — | — | Límites del plan actual |

---

## 58. products

**Controller:** `products/products.controller.ts` — Prefix: `products`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/products` | — | query params | — | Listar productos |
| POST | `/products` | inline | — | RolesGuard, PlanLimitsGuard | @PlanAction('create_product') |
| PUT | `/products/:id` | inline | — | RolesGuard | Actualizar |
| DELETE | `/products/:id` | — | — | RolesGuard | Eliminar |
| POST | `/products/upload/excel` | FormData | — | RolesGuard | Import Excel |
| GET | `/products/download` | — | — | RolesGuard | Export |
| POST | `/products/remove-image` | inline | — | RolesGuard | Eliminar imagen |
| GET | `/products/search` | — | `SearchProductsDto` | — | Búsqueda pública |
| GET | `/products/search/filters` | — | query params | — | Filtros disponibles |
| GET | `/products/:id` | — | — | — | Detalle producto |
| POST | `/products/:id/image` | FormData | — | RolesGuard, PlanLimitsGuard | @PlanAction('upload_image') |

**SearchProductsDto (Query):** clientId? (UUID), q?, sort (relevance/price_asc/price_desc/best_selling), priceMin?, priceMax?, page (default 1, **1-based**), pageSize (default 24), optionValues? (comma-separated), optionSetId? (UUID), onSale? (BooleanString)

---

## 59. questions

**Controller:** `questions/questions.controller.ts` — Prefix: `` (vacío)

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/products/:productId/questions` | — | — | PlanAccessGuard | @PlanFeature('storefront.product_qa') |
| POST | `/products/:productId/questions` | inline | — | PlanAccessGuard | Crear pregunta |
| POST | `/questions/:questionId/answers` | inline | — | RolesGuard | Responder |
| PATCH | `/questions/:questionId/moderate` | inline | — | RolesGuard | Moderar |
| DELETE | `/questions/:questionId` | — | — | — | Eliminar |
| GET | `/admin/questions` | — | — | RolesGuard | Listar para admin |

---

## 60. quota

**Controller:** `billing/quota.controller.ts` — Prefix: `` (vacío)

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/quotas/me` | — | — | — | Mi cuota |
| GET | `/v1/tenants/:id/quotas` | — | — | SuperAdminGuard | Cuota de tenant |
| POST | `/v1/quota/check` | `QuotaCheckDto` (inline) | — | — | Verificar cuota |

**QuotaCheckDto (inline):** resource (IsString, IsIn ['order','api_call','storage','egress'])

---

## 61. reviews

**Controller:** `reviews/reviews.controller.ts` — Prefix: `` (vacío)

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/products/:productId/reviews` | — | — | PlanAccessGuard | @PlanFeature('storefront.product_reviews') |
| POST | `/products/:productId/reviews` | inline | — | PlanAccessGuard | Crear review |
| PATCH | `/reviews/:reviewId` | inline | — | — | Editar review |
| POST | `/reviews/:reviewId/reply` | inline | — | RolesGuard | Responder |
| PATCH | `/reviews/:reviewId/moderate` | inline | — | RolesGuard | Moderar |
| GET | `/products/:productId/social-proof` | — | — | PlanAccessGuard | Social proof |
| GET | `/admin/reviews` | — | — | RolesGuard | Listar para admin |

---

## 62. seo

**Controller:** `seo/seo.controller.ts` — Prefix: `seo`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/seo/settings` | — | — | — | Config SEO |
| PUT | `/seo/settings` | `UpdateSeoSettingsDto` | — | RolesGuard | Actualizar settings |
| GET | `/seo/meta/:entity/:id` | — | — | PlanAccessGuard | @PlanFeature('seo.entity_meta') |
| PUT | `/seo/meta/:entity/:id` | `UpdateEntityMetaDto` | — | RolesGuard | Actualizar meta |
| GET | `/seo/sitemap.xml` | — | — | — | Sitemap XML |
| GET | `/seo/og` | — | — | — | Open Graph data |
| GET | `/seo/redirects` | — | — | RolesGuard, PlanAccessGuard | @PlanFeature('seo.redirects') |
| POST | `/seo/redirects` | `CreateRedirectDto` | — | RolesGuard | Crear redirect |
| PUT | `/seo/redirects/:id` | `UpdateRedirectDto` | — | RolesGuard | Editar redirect |
| DELETE | `/seo/redirects/:id` | — | — | RolesGuard | Eliminar redirect |
| GET | `/seo/redirects/resolve` | — | ?path | — | Resolver redirect |

**UpdateSeoSettingsDto:** site_title, site_description, brand_name, og_image_default, favicon_url, ga4_measurement_id, gtm_container_id, search_console_token, product_url_pattern, robots_txt, custom_meta  
**UpdateEntityMetaDto:** meta_title (MaxLength 70), meta_description (MaxLength 160), slug, noindex, seo_source (IsIn manual/ai/template), seo_locked  
**CreateRedirectDto:** source (IsString), target (IsString), status_code (IsInt, IsIn [301,302]), is_regex? (IsBoolean), notes? (MaxLength 500)

---

## 63. seo-ai

**Controller:** `seo-ai/seo-ai.controller.ts` — Prefix: `seo-ai`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| POST | `/seo-ai/jobs` | inline | — | ClientDashboardGuard, @AllowNoTenant | Crear job AI |
| GET | `/seo-ai/jobs` | — | — | ClientDashboardGuard, @AllowNoTenant | Listar jobs |
| GET | `/seo-ai/jobs/:id` | — | — | ClientDashboardGuard, @AllowNoTenant | Detalle job |
| GET | `/seo-ai/jobs/:id/log` | — | — | ClientDashboardGuard, @AllowNoTenant | Log del job |
| GET | `/seo-ai/estimate` | — | query params | ClientDashboardGuard, @AllowNoTenant | Estimación |
| GET | `/seo-ai/entities-preview` | — | query params | ClientDashboardGuard, @AllowNoTenant | Preview de entidades |
| GET | `/seo-ai/status` | — | — | ClientDashboardGuard, @AllowNoTenant | Estado general |
| GET | `/seo-ai/audit` | — | — | ClientDashboardGuard, @AllowNoTenant | Auditoría SEO |
| GET | `/seo-ai/prompt` | — | — | ClientDashboardGuard, @AllowNoTenant | Prompt config |

---

## 64. seo-ai (purchase)

**Controller:** `seo-ai-billing/seo-ai-purchase.controller.ts` — Prefix: `seo-ai`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/seo-ai/packs` | — | — | @AllowNoTenant | Packs disponibles |
| POST | `/seo-ai/purchase` | inline | — | ClientDashboardGuard, @AllowNoTenant | Comprar créditos |
| GET | `/seo-ai/my-credits` | — | — | ClientDashboardGuard, @AllowNoTenant | Mis créditos |
| POST | `/seo-ai/webhook` | raw body | — | @AllowNoTenant | **Webhook pago SEO AI** |

---

## 65. service

**Controller:** `service/service.controller.ts` — Prefix: `settings/services`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/settings/services` | — | — | — | Listar servicios |
| POST | `/settings/services` | inline | — | RolesGuard (admin/super_admin) | Crear |
| PUT | `/settings/services/:id` | inline | — | RolesGuard (admin/super_admin) | Actualizar |
| DELETE | `/settings/services` | — | — | RolesGuard (admin/super_admin) | Eliminar |

---

## 66. settings (identity)

**Controller:** `home/settings.controller.ts` — Prefix: `settings`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/settings/identity` | — | — | TenantContextGuard | Config identidad |
| PATCH | `/settings/identity` | `IdentityConfigSchema` (Zod) | — | TenantContextGuard, RolesGuard | Actualizar identidad |

---

## 67. shipping

**Controller:** `shipping/shipping.controller.ts` — Prefix: `shipping`  
**Guard base:** ClientContextGuard, PlanAccessGuard — @PlanFeature('commerce.shipping')

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/shipping/integrations/available-providers` | — | — | base guards | Providers disponibles |
| GET | `/shipping/integrations` | — | — | base guards | Integraciones activas |
| GET | `/shipping/integrations/:id` | — | — | base guards | Detalle integración |
| POST | `/shipping/integrations` | inline | — | base guards | Crear integración |
| PUT | `/shipping/integrations/:id` | inline | — | base guards | Actualizar |
| DELETE | `/shipping/integrations/:id` | — | — | base guards | Eliminar |
| POST | `/shipping/integrations/:id/test` | — | — | base guards | Probar integración |
| GET | `/shipping/orders/:orderId` | — | — | base guards | Envío de orden |
| POST | `/shipping/orders/:orderId` | inline | — | base guards | Crear envío |
| PATCH | `/shipping/orders/:orderId` | inline | — | base guards | Actualizar envío |
| POST | `/shipping/orders/:orderId/sync-tracking` | — | — | base guards | Sync tracking |
| GET | `/shipping/settings` | — | — | base guards | Config shipping |
| PUT | `/shipping/settings` | `UpdateShippingSettingsDto` | — | base guards | Actualizar config |
| GET | `/shipping/zones` | — | — | base guards | Listar zonas |
| GET | `/shipping/zones/:id` | — | — | base guards | Detalle zona |
| POST | `/shipping/zones` | `CreateShippingZoneDto` | — | base guards | Crear zona |
| PUT | `/shipping/zones/:id` | `UpdateShippingZoneDto` | — | base guards | Actualizar zona |
| DELETE | `/shipping/zones/:id` | — | — | base guards | Eliminar zona |
| POST | `/shipping/quote` | `ShippingQuoteDto` | — | base guards | Cotizar envío |
| POST | `/shipping/quote/revalidate` | `RevalidateQuoteDto` | — | base guards | Revalidar cotización |
| GET | `/shipping/quote/:quoteId` | — | — | base guards | Detalle cotización |
| POST | `/shipping/webhooks/:provider` | raw body | — | @AllowNoTenant | **Webhook provider** |
| GET | `/shipping/webhook-failures` | — | — | base guards | Fallos webhook |
| POST | `/shipping/webhook-failures/:failureId/retry` | — | — | base guards | Reintentar |
| GET | `/shipping/health` | — | — | @AllowNoTenant | Health check |

**UpdateShippingSettingsDto:** delivery_enabled, pickup_enabled, arrange_enabled, shipping_pricing_mode (zone/flat/provider_api), flat_shipping_cost, free_shipping_enabled/threshold, pickup_address/instructions/hours, arrange_message/whatsapp, labels, estimated_delivery_text  
**ShippingQuoteDto:** delivery_method (delivery/pickup/arrange), zip_code, province, subtotal (Min 0), items (QuoteItemDto[]: product_id UUID, quantity Min 1)

---

## 68. social-links

**Controller:** `social-links/social-links.controller.ts` — Prefix: `social-links`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/social-links` | — | — | — | Listar |
| POST | `/social-links` | `CreateSocialLinksDto` | — | RolesGuard (admin/super_admin) | Crear — **⚠️ Sin validators** |
| PUT | `/social-links/:id` | `UpdateSocialLinksDto` | — | RolesGuard (admin/super_admin) | Actualizar |
| DELETE | `/social-links/:id` | — | — | RolesGuard (admin/super_admin) | Eliminar |

---

## 69. store-coupons

**Controller:** `store-coupons/store-coupons.controller.ts` — Prefix: `store-coupons`  
**Guard base:** PlanAccessGuard — @PlanFeature('commerce.coupons')

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/store-coupons` | — | — | RolesGuard, PlanAccessGuard | Listar cupones tienda |
| GET | `/store-coupons/:id` | — | — | PlanAccessGuard | Detalle |
| POST | `/store-coupons` | `CreateStoreCouponDto` | — | RolesGuard, PlanLimitsGuard | @PlanAction('create_coupon') |
| PUT | `/store-coupons/:id` | `UpdateStoreCouponDto` | — | PlanAccessGuard | Actualizar |
| DELETE | `/store-coupons/:id` | — | — | PlanAccessGuard | Eliminar |
| GET | `/store-coupons/:id/redemptions` | — | — | PlanAccessGuard | Redenciones |
| POST | `/store-coupons/validate` | `ValidateStoreCouponDto` | — | PlanAccessGuard | Validar cupón |
| POST | `/store-coupons/:id/reverse-redemption` | inline | — | PlanAccessGuard | Reversar redención |

**CreateStoreCouponDto:** code, description, discount_type (percentage/fixed_amount/free_shipping), discount_value (Min 0.01), max_discount?, min_subtotal?, target_type?, target_ids? (UUID[]), starts_at?, ends_at?, max_redemptions?, max_per_user?, stackable?  
**ValidateStoreCouponDto:** code, cart_items, subtotal, shipping_cost

---

## 70. subscriptions

**Controller:** `subscriptions/subscriptions.controller.ts` — Prefix: `subscriptions`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/subscriptions/me` | — | — | BuilderSessionGuard | Mi suscripción |
| POST | `/subscriptions/webhook` | raw body | — | @AllowNoTenant | **Webhook MP suscripciones** |
| POST | `/subscriptions/reconcile` | inline | — | SuperAdminGuard | Reconciliar |
| GET | `/subscriptions/:accountId/status` | — | — | SuperAdminGuard | Estado por cuenta |
| GET | `/subscriptions/manage/status` | — | — | BuilderSessionGuard | Estado gestión (builder) |
| POST | `/subscriptions/manage/cancel` | — | — | BuilderSessionGuard | Cancelar |
| POST | `/subscriptions/manage/revert-cancel` | — | — | BuilderSessionGuard | Revertir cancel |
| POST | `/subscriptions/manage/pause-store` | — | — | BuilderSessionGuard | Pausar tienda |
| POST | `/subscriptions/manage/resume-store` | — | — | BuilderSessionGuard | Reanudar tienda |
| GET | `/subscriptions/manage/plans` | — | — | BuilderSessionGuard | Planes disponibles |
| POST | `/subscriptions/manage/upgrade` | inline | — | BuilderSessionGuard, SubscriptionGuard | Upgrade plan |
| GET | `/subscriptions/client/manage/status` | — | — | ClientDashboardGuard | Estado (client dashboard) |
| POST | `/subscriptions/client/manage/cancel` | — | — | ClientDashboardGuard | Cancelar (client) |
| POST | `/subscriptions/client/manage/revert-cancel` | — | — | ClientDashboardGuard | Revertir (client) |
| POST | `/subscriptions/client/manage/pause-store` | — | — | ClientDashboardGuard | Pausar (client) |
| POST | `/subscriptions/client/manage/resume-store` | — | — | ClientDashboardGuard | Reanudar (client) |
| GET | `/subscriptions/client/manage/plans` | — | — | ClientDashboardGuard | Planes (client) |
| POST | `/subscriptions/client/manage/upgrade` | inline | — | ClientDashboardGuard, SubscriptionGuard | Upgrade (client) |
| POST | `/subscriptions/client/manage/validate-coupon` | inline | — | ClientDashboardGuard | Validar cupón |

---

## 71. support (client)

**Controller:** `support/support.controller.ts` — Prefix: `client-dashboard/support`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/client-dashboard/support/tickets` | — | — | ClientDashboardGuard, @AllowNoTenant | @PlanFeature('support.tickets') |
| POST | `/client-dashboard/support/tickets` | `CreateTicketDto` | — | ClientDashboardGuard, @AllowNoTenant | Crear ticket |
| GET | `/client-dashboard/support/tickets/:ticketId` | — | — | ClientDashboardGuard, @AllowNoTenant | Detalle |
| GET | `/client-dashboard/support/tickets/:ticketId/messages` | — | — | ClientDashboardGuard, @AllowNoTenant | Mensajes |
| POST | `/client-dashboard/support/tickets/:ticketId/messages` | `CreateMessageDto` | — | ClientDashboardGuard, @AllowNoTenant | Enviar mensaje |
| PATCH | `/client-dashboard/support/tickets/:ticketId/close` | `CloseTicketDto` | — | ClientDashboardGuard, @AllowNoTenant | Cerrar ticket |
| PATCH | `/client-dashboard/support/tickets/:ticketId/reopen` | — | — | ClientDashboardGuard, @AllowNoTenant | Reabrir ticket |

**CreateTicketDto:** subject (MaxLength 500), category (billing/tech/onboarding/bugs/feature_request/other), priority? (low/normal/high/urgent, default normal), body (MaxLength 10000), order_id?, attachments? (AttachmentDto[]), meta?  
**CloseTicketDto:** csat_rating (Int, Min 1, Max 5), csat_comment?

---

## 72. templates

**Controller:** `templates/templates.controller.ts` — Prefix: `templates`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/templates` | — | — | @AllowNoTenant | Listar templates públicos |
| GET | `/templates/admin/all` | — | — | SuperAdminGuard | Listar todos (admin) |
| POST | `/templates/admin` | inline | — | SuperAdminGuard | Crear template |
| PUT | `/templates/admin/:key` | inline | — | SuperAdminGuard | Editar template |
| DELETE | `/templates/admin/:key` | — | — | SuperAdminGuard | Eliminar template |

---

## 73. tenant

**Controller:** `tenant/tenant.controller.ts` — Prefix: `tenant`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/tenant/bootstrap` | — | — | TenantContextGuard | Bootstrap completo del tenant |
| GET | `/tenant/status` | — | — | TenantContextGuard | Estado del tenant |
| GET | `/tenant/resolve-host` | — | ?host | @AllowNoTenant | Resolver host → tenant |
| GET | `/tenant/countries` | — | — | @AllowNoTenant | Países disponibles |

---

## 74. themes

**Controller:** `themes/themes.controller.ts` — Prefix: `themes`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/themes/:clientId` | — | — | BuilderSessionGuard | Obtener theme |
| PATCH | `/themes/:clientId` | inline | — | BuilderSessionGuard | Actualizar theme |

---

## 75. users

**Controller:** `users/users.controller.ts` — Prefix: `users`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| GET | `/users` | — | — | ClientContextGuard, PlanAccessGuard | @PlanFeature('dashboard.users_management') |
| GET | `/users/:id` | — | — | ClientContextGuard, PlanAccessGuard | Detalle usuario |
| PATCH | `/users/:id` | inline | — | ClientContextGuard, PlanAccessGuard | Editar usuario |
| PUT | `/users/:id/block` | inline | — | ClientContextGuard, PlanAccessGuard | Bloquear usuario |
| POST | `/users/:id/accept-terms` | inline | — | ClientContextGuard, PlanAccessGuard | Aceptar términos |
| DELETE | `/users/:id` | — | — | ClientContextGuard, PlanAccessGuard | Eliminar usuario |

---

## 76. webhooks/mp (router)

**Controller:** `controllers/mp-router.controller.ts` — Prefix: `webhooks/mp`

| HTTP | Ruta | Body DTO | Query DTO | Guards | Notas |
|------|------|----------|-----------|--------|-------|
| POST | `/webhooks/mp/tenant-payments` | raw body | — | @AllowNoTenant | **Router webhook MP para tenant payments** |
| POST | `/webhooks/mp/platform-subscriptions` | raw body | — | @AllowNoTenant | **Router webhook MP para suscripciones plataforma** |

---

## Hallazgos de Auditoría (DTOs y Validación)

### ⚠️ DTOs sin validadores class-validator (riesgo de input no sanitizado)

| DTO / Inline | Ubicación | Riesgo |
|-------------|-----------|--------|
| `CreateDraftAccountDto` (inline) | admin-accounts.controller.ts | email, name, planId sin validación |
| `SendReminderDto` (inline) | admin-client.controller.ts | type, subject, body sin validación |
| `RegisterPaymentDto` (inline) | admin-client.controller.ts | amount sin @IsNumber, method sin @IsString |
| `ToggleStatusDto` (inline) | admin-client.controller.ts | is_active sin @IsBoolean |
| `CreateSocialLinksDto` | social-links/dto/ | whatsApp, instagram, facebook sin validadores |
| `UpdateSettingsDto` (payments) | payments/dto/ | Todos los campos sin decoradores |
| `QuoteDto` (payments) | payments/dto/ | Todos los campos sin decoradores |
| Múltiples inline en admin.controller.ts | admin/admin.controller.ts | ~15 endpoints con body inline sin validación |

### ⚠️ DTOs con validación Zod (en vez de class-validator)

| DTO | Ubicación | Notas |
|-----|-----------|-------|
| `IdentityConfigSchema` | home/dto/identity-config.dto.ts | Zod strict schema con .parse() |
| `AddSectionDto`, `UpdateOrderDto`, `ReplaceSectionDto` | home/dto/section.dto.ts | Zod schemas |
| `HomeDataLiteSchema` | onboarding/dto/home-data-lite.dto.ts | Zod con validaciones complejas |

> Nota: La mezcla de Zod y class-validator es un **patrón inconsistente** que dificulta el mantenimiento. Recomendable estandarizar.

### ⚠️ Paginación inconsistente

| Endpoint | Paginación | Base |
|---------|-----------|------|
| `/products/search` (SearchProductsDto) | page default 1 | **1-based** |
| `/admin/support/tickets` (TicketFiltersDto) | page default 0 | **0-based** |
| General en admin.controller.ts | parseInt(query.page \|\| '0') | **0-based** |

> **Inconsistencia:** El storefront usa 1-based, admin usa 0-based. Riesgo de off-by-one bugs.

### ⚠️ Endpoints sin guards explícitos (potencial acceso abierto)

Los siguientes controllers/endpoints **no tienen guards visibles** a nivel de clase ni de método. Dependen del middleware global (AuthMiddleware + TenantContextGuard global):

- `categories` (GET, GET/:id) — Solo lectura pública OK, pero POST/PUT/DELETE solo tienen RolesGuard
- `contact-info` (GET) — Lectura pública OK
- `favorites` (todos) — Sin guard explícito, depende del middleware
- `home` (GET /data, GET /navigation) — Lectura pública OK
- `legal` (varios GETs) — Lectura pública OK

> Estos pueden estar protegidos por el TenantContextGuard global. Verificar en `app.module.ts` que el guard global esté activo y cubra todas las rutas excepto las marcadas con @AllowNoTenant.

---

## DTOs Completos — Referencia Rápida

### Validación con Decoradores (class-validator)

| DTO | Campos validados | Decoradores principales |
|-----|-----------------|------------------------|
| CreateAddressDto | 12 campos | @IsString, @MaxLength, @MinLength, @Matches (phone), @IsBoolean |
| UpdateAddressDto | 12 campos (todos optional) | @IsOptional + mismos |
| CreateCountryConfigDto | 10 campos | @Length, @Min, @Max, @IsNumber, @IsBoolean |
| UpdateCountryConfigDto | 17 campos (todos optional) | @IsOptional + @IsString, @IsNumber, @IsBoolean |
| UpdateFxConfigDto | 7 campos | @IsIn, @IsNumber @Min @Max, @IsString |
| UpdateQuotaStateDto | 2 campos | @IsIn (QUOTA_STATES), @IsString |
| AddCartItemDto | 4 campos | @IsUUID, @IsInt @Min(1), @IsNumber, @ValidateNested |
| ValidateCouponDto | 3 campos | @IsNotEmpty, @IsString, @IsUUID |
| CreateOptionSetDto | 6 campos | @IsString, @IsIn, @IsArray, @ValidateNested |
| UpdateOptionSetDto | 5 campos (todos optional) | @IsOptional + mismos |
| CreateSizeGuideDto | 5 campos | @IsUUID, @IsString, @IsArray |
| SearchProductsDto | 10 campos | @IsUUID, @IsIn, @Type, @Transform, @IsBooleanString |
| CreateRedirectDto | 5 campos | @IsString, @IsInt, @IsIn([301,302]), @IsBoolean, @MaxLength |
| UpdateEntityMetaDto | 6 campos | @MaxLength(70/160), @IsIn, @IsBoolean |
| UpdateSeoSettingsDto | 12 campos | @IsString, @IsOptional |
| ShippingQuoteDto | 5 campos | @IsIn, @IsString, @Min(0), @ValidateNested |
| UpdateShippingSettingsDto | 15+ campos | @IsBoolean, @IsIn, @IsNumber, @ValidateNested |
| CreateStoreCouponDto | 12 campos | @IsString, @IsIn, @Min(0.01), @IsUUID, @IsBoolean |
| ValidateStoreCouponDto | 4 campos | @IsString, @IsArray, @IsNumber |
| CreateTicketDto | 7 campos | @MaxLength, @IsIn (6 categorías), @ValidateNested |
| TicketFiltersDto | 12 campos | @IsIn, @Transform, @IsInt, @Min |
| UpdateTicketDto | 4 campos | @IsIn, @IsUUID, @IsArray |
| CreateMessageDto | 3 campos | @MaxLength(10000), @ValidateNested, @IsBoolean |
| CloseTicketDto | 2 campos | @IsInt @Min(1) @Max(5), @IsString |
| MercadoPago DTOs (10+) | Todos validados | @IsNumber, @IsIn, @Min, @ValidateNested |
| IdentitySettingsDto | 4 campos | @ValidateNested, @IsArray |

### Validación con Zod

| Schema | Campos | Notas |
|--------|--------|-------|
| IdentityConfigSchema | socials, footer, banners, logo, integrations | .strict() — no permite campos extra |
| HomeDataLiteSchema | products, services, banners, faqs, logo, contactInfo, socialLinks | Con validación SKU únicos |
| AddSectionDto | type, insert_after_id?, props? | Zod simple |
| UpdateOrderDto | ordered_ids (array uuid min 1) | Zod simple |
| ReplaceSectionDto | new_type, props? | Zod simple |
