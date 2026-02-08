# NovaVision – Documentación de Bases de Datos

> Última actualización: 2026-02-07
> Contexto: Post-limpieza de datos de prueba

---

## 1. Conexiones

| DB | Alias env | Host Supabase | Supabase URL |
|----|-----------|---------------|--------------|
| **Admin** | `ADMIN_DB_URL` | `db.erbfzlsznqsmwmjugspo.supabase.co` | `https://erbfzlsznqsmwmjugspo.supabase.co` |
| **Multicliente** | `BACKEND_DB_URL` | `db.ulndkhijxtxvpmbbfrgp.supabase.co` | `https://ulndkhijxtxvpmbbfrgp.supabase.co` |

Ambas: puerto `5432`, user `postgres`, database `postgres`.  
Credenciales en `apps/api/.env`.

---

## 2. Admin DB (erbfzlsznqsmwmjugspo) – 64 tablas

### Datos actuales post-limpieza

| Entidad | Detalle |
|---------|---------|
| `nv_accounts` | 1 cuenta: `kaddocpendragon@gmail.com` (slug: `test`, status: `approved`, plan: `growth`) |
| `users` | 3: kaddocpendragon (client), novavision.contact (admin), urbanprint.contacto (client) |
| `auth.users` | 2: kaddocpendragon@gmail.com, novavision.contact@gmail.com |
| `nv_onboarding` | 1: onboarding de kaddocpendragon (client_id → Tienda Test) |
| `subscriptions` | 1: vinculada a la cuenta kaddocpendragon |

### Tablas (64 total)

#### Core – Cuentas y Onboarding
| Tabla | Propósito | FK principal | Rows |
|-------|-----------|-------------|------|
| `nv_accounts` | Cuentas de clientes NovaVision | — | 1 |
| `nv_onboarding` | Sesiones de onboarding/wizard | `account_id → nv_accounts` | 1 |
| `nv_account_settings` | Config por cuenta | `nv_account_id → nv_accounts` | 0 |
| `onboarding_links` | Links de acceso al onboarding | `account_id → nv_accounts` | 0 |
| `slug_reservations` | Slugs reservados | `account_id → nv_accounts` | 1 |

#### Subscripciones y Billing
| Tabla | Propósito | FK principal | Rows |
|-------|-----------|-------------|------|
| `subscriptions` | Suscripciones activas | `account_id → nv_accounts` | 1 |
| `subscription_events` | Eventos de suscripción | `subscription_id → subscriptions` | 0 |
| `subscription_locks` | Locks de concurrencia | `account_id → nv_accounts` | 0 |
| `subscription_notification_outbox` | Notificaciones pendientes | `account_id → nv_accounts` | 0 |
| `subscription_payment_failures` | Fallos de pago | `subscription_id → subscriptions` | 0 |
| `subscription_price_history` | Historial de precios | `subscription_id → subscriptions` | 0 |
| `billing_cycle` | Ciclos de facturación | `client_id` | 0 |
| `invoices` | Facturas | `client_id` | 1 |
| `payments` | Pagos admin | `client_id` | 0 |
| `plans` | Catálogo de planes | — | 6 |
| `metering_prices` | Precios de medición | — | 0 |
| `nv_billing_events` | Eventos de billing | `account_id → nv_accounts` | 0 |

#### Coupons
| Tabla | Propósito | FK principal | Rows |
|-------|-----------|-------------|------|
| `coupons` | Cupones de descuento | — | 7 |
| `coupon_redemptions` | Canjes de cupones | `account_id → nv_accounts`, `coupon_id → coupons`, `subscription_id → subscriptions` | 1 |

#### Provisioning
| Tabla | Propósito | FK principal | Rows |
|-------|-----------|-------------|------|
| `provisioning_jobs` | Jobs de setup de tienda | `account_id → nv_accounts` | 0 |
| `provisioning_job_steps` | Steps de provisioning | `job_id → provisioning_jobs`, `account_id → nv_accounts` | 0 |
| `backend_clusters` | Clusters disponibles | — | 1 |

#### Mercado Pago
| Tabla | Propósito | FK principal | Rows |
|-------|-----------|-------------|------|
| `mp_events` | Eventos MP | `account_id → nv_accounts` | 0 |
| `tenant_payment_events` | Eventos pago tenant | — | 0 |
| `oauth_state_nonces` | OAuth state tokens | `client_id` | 0 |

#### Themes y Palettes
| Tabla | Propósito | FK principal | Rows |
|-------|-----------|-------------|------|
| `palette_catalog` | Catálogo de paletas disponibles | — | 20 |
| `custom_palettes` | Paletas personalizadas | `based_on_key → palette_catalog`, `client_id` | 0 |
| `client_themes` | Themes por cliente | `client_id` | 0 |
| `nv_templates` | Templates de tienda | — | 5 |

#### Lifecycle y Auditoría
| Tabla | Propósito | FK principal | Rows |
|-------|-----------|-------------|------|
| `lifecycle_events` | Eventos ciclo de vida | `account_id → nv_accounts` | 1 |
| `client_completion_checklist` | Checklist completitud | `account_id → nv_accounts` | 1 |
| `client_completion_events` | Eventos de completitud | `account_id → nv_accounts` | 10 |
| `system_events` | Eventos de sistema | `account_id`, `client_id`, `user_id` | 0 |
| `webhook_events` | Webhooks recibidos | — | 0 |

#### Usuarios y Auth
| Tabla | Propósito | FK principal | Rows |
|-------|-----------|-------------|------|
| `users` | Usuarios admin | `client_id` | 3 |
| `super_admins` | Super admins registrados | — | 2 |
| `dashboard_admins` | Admins del dashboard | — | 1 |
| `auth_bridge_codes` | Códigos auth bridge | `user_id` | 0 |
| `auth_handoff` | Handoff auth entre apps | `user_id`, `client_id` | 0 |

#### Dominios
| Tabla | Propósito | FK principal | Rows |
|-------|-----------|-------------|------|
| `managed_domains` | Dominios custom | `account_id → nv_accounts` | 0 |
| `managed_domain_renewals` | Renovaciones dominio | `managed_domain_id → managed_domains` | 0 |

#### Usage / Métricas
| Tabla | Propósito | FK principal | Rows |
|-------|-----------|-------------|------|
| `usage_event` | Eventos de uso crudo | `client_id` | 11 |
| `usage_hourly` | Agregados por hora | `client_id` | 130 |
| `usage_daily` | Agregados por día | `client_id` | 45 |
| `usage_ledger` | Ledger de uso | `client_id`, `user_id` | 1466 |
| `client_usage_month` | Uso mensual por cliente | `client_id` | 1 |

#### Outreach / Leads
| Tabla | Propósito | FK principal | Rows |
|-------|-----------|-------------|------|
| `leads` | Leads de contacto | — | 7 |
| `lead_assets` | Assets de leads | `lead_id → leads` | 0 |
| `outreach_leads` | Leads de outreach masivo | — | 47403 |
| `outreach_logs` | Logs de outreach | `lead_id → outreach_leads` | 39 |
| `meetings` | Reuniones programadas | `lead_id → leads` | 0 |

#### Config y Extras
| Tabla | Propósito | FK principal | Rows |
|-------|-----------|-------------|------|
| `app_settings` | Config global app | — | 7 |
| `app_secrets` | Secretos app | — | 1 |
| `client_extra_costs` | Costos extras | `client_id` | 0 |
| `client_tombstones` | Registros de borrado | `client_id` | 0 |
| `dev_portal_whitelist` | Whitelist dev portal | — | 0 |
| `email_jobs` | Emails en cola | `client_id` | 1 |
| `nv_playbook` | Playbook NovaVision | — | 85 |
| `orders_bridge` | Bridge de órdenes | `client_id` | 0 |
| `sync_cursors` | Cursores de sincronización | `client_id` | 0 |
| `pro_projects` | Proyectos pro | `account_id → nv_accounts` | 0 |
| `account_addons` | Addons por cuenta | `account_id → nv_accounts` | 0 |
| `account_entitlements` | Entitlements | `account_id → nv_accounts` | 0 |
| `addon_catalog` | Catálogo addons | — | 1 |

### Relaciones FK (Admin DB)

```
backend_clusters ← nv_accounts.backend_cluster_id
nv_accounts ← account_addons, account_entitlements, client_completion_checklist,
               client_completion_events, coupon_redemptions, lifecycle_events,
               managed_domains, mp_events, nv_account_settings, nv_billing_events,
               nv_onboarding, onboarding_links, provisioning_jobs (+steps),
               slug_reservations, subscription_notification_outbox, subscriptions
subscriptions ← subscription_events, subscription_notification_outbox,
                subscription_payment_failures, subscription_price_history,
                coupon_redemptions, nv_accounts.subscription_id
coupons ← coupon_redemptions, subscriptions
leads ← lead_assets, meetings
outreach_leads ← outreach_logs
managed_domains ← managed_domain_renewals
palette_catalog ← custom_palettes
provisioning_jobs ← provisioning_job_steps
```

---

## 3. Backend/Multicliente DB (ulndkhijxtxvpmbbfrgp) – 32 tablas

### Datos actuales post-limpieza

| Entidad | Detalle |
|---------|---------|
| `clients` | 2: **urbanprint** (f2d3f270) + **Tienda Test** (19986d95) |
| `users` | 3: elias.piscitelli (urbanprint), novavision.contact (urbanprint), urbanprint.contacto (urbanprint) |
| `auth.users` | 1: novavision.contact@gmail.com |
| `products` | 19 (entre ambas tiendas) |
| `categories` | 8 |
| `orders` | 3 |

### Tablas (32 total)

#### Core – Tiendas
| Tabla | Propósito | FK principal | Rows |
|-------|-----------|-------------|------|
| `clients` | Tiendas/tenants | — | 2 |
| `users` | Usuarios de tienda | `client_id → clients` | 3 |

#### Catálogo
| Tabla | Propósito | FK principal | Rows |
|-------|-----------|-------------|------|
| `products` | Productos | `client_id → clients` | 19 |
| `categories` | Categorías | `client_id → clients` | 8 |
| `product_categories` | Relación M:N | `product_id → products`, `category_id → categories`, `client_id → clients` | 14 |
| `services` | Servicios | `client_id → clients` | 3 |

#### Carrito y Órdenes
| Tabla | Propósito | FK principal | Rows |
|-------|-----------|-------------|------|
| `cart_items` | Items del carrito | `client_id → clients`, `user_id → users`, `product_id → products` | 1 |
| `favorites` | Favoritos | `client_id`, `user_id`, `product_id → products` | 2 |
| `orders` | Pedidos | `client_id → clients`, `user_id → users` | 3 |
| `order_items` | Items del pedido | `order_id → orders`, `product_id → products` | 0 |
| `order_payment_breakdown` | Desglose de pagos | `client_id` | 0 |
| `payments` | Pagos MP | `client_id → clients` | 0 |
| `coupons` | Cupones tienda | `client_id → clients` | 0 |

#### Apariencia y Contenido
| Tabla | Propósito | FK principal | Rows |
|-------|-----------|-------------|------|
| `banners` | Banners | `client_id → clients` | 0 |
| `logos` | Logos | `client_id → clients` | 0 |
| `faqs` | Preguntas frecuentes | `client_id → clients` | 6 |
| `contact_info` | Info de contacto | `client_id → clients` | 0 |
| `social_links` | Redes sociales | `client_id → clients` | 1 |
| `home_sections` | Secciones home | `client_id → clients` | 0 |
| `home_settings` | Config de home | `client_id → clients` | 1 |
| `client_home_settings` | Config home avanzada | `client_id → clients` | 0 |
| `client_assets` | Assets subidos | `client_id → clients` | 0 |

#### Config de Pagos
| Tabla | Propósito | FK principal | Rows |
|-------|-----------|-------------|------|
| `client_payment_settings` | Config pagos por tenant | `client_id` | 0 |
| `client_mp_fee_overrides` | Override fees MP | `client_id` | 0 |
| `mp_fee_table` | Tabla de comisiones MP (global) | — | 10 |
| `mp_idempotency` | Idempotencia webhooks | `client_id` | 3 |
| `client_secrets` | Secrets por tenant (MP tokens, etc) | `client_id → clients` | 1 |

#### Operaciones
| Tabla | Propósito | FK principal | Rows |
|-------|-----------|-------------|------|
| `email_jobs` | Emails en cola | `client_id` | 5 |
| `cors_origins` | Orígenes CORS | `client_id → clients` | 1 |
| `client_usage` | Métricas uso | `client_id → clients` | 2 |
| `oauth_state_nonces` | OAuth nonces | `client_id` | 0 |
| `webhook_events` | Webhooks recibidos | — | 0 |

### Relaciones FK (Backend DB)

```
clients ← banners, cart_items, categories, client_assets, client_home_settings,
           client_secrets, client_usage, contact_info, cors_origins, coupons,
           faqs, home_sections, home_settings, logos, orders, payments,
           product_categories, products, services, social_links, users
products ← cart_items, favorites, order_items, product_categories
categories ← product_categories
orders ← order_items
users ← cart_items, orders
```

---

## 4. Operación de Limpieza (2026-02-07)

### Objetivo
Eliminar todos los datos de prueba/test de ambas BDs, conservando solo:
- **urbanprint** (Pablo Piscitelli) — client `f2d3f270-583b-4644-9a61-2c0d6824f101`
- **kaddocpendragon** (Tienda Test) — client `19986d95-2702-4cf2-ba3d-5b4a3df01ef7`, account `7f62b1e5-c518-402c-abcb-88ab9db56dfe`

### Qué se eliminó

**Backend DB:**
- 3 clients eliminados: Dev Store (demo-store), Elias Piscitelli (testclientnova), Test Store Manual
- ~10 users de clients eliminados
- ~56 products + 16 product_categories + 8 categories de clients eliminados
- ~32 orders + 2 payments de clients eliminados
- 4 cart_items, 8 favorites
- Todos los webhook_events y oauth_state_nonces

**Admin DB:**
- 2 nv_accounts eliminados: demo-store (provisioned), test-store-manual (live)
- Todas las tablas dependientes por CASCADE (subscriptions, lifecycle_events, etc.)
- 6 client_themes + 6 custom_palettes
- 64 system_events
- 385 usage_hourly entries de clientes borrados
- 5877 usage_ledger entries de clientes borrados

### Qué se conservó intacto
- Tablas de catálogo global: `plans` (6), `palette_catalog` (20), `nv_templates` (5), `nv_playbook` (85), `mp_fee_table` (10)
- `outreach_leads` (47403) + `outreach_logs` (39)
- `leads` (7)
- `super_admins` (2)
- `app_settings` (7), `app_secrets` (1)
- Todos los `auth.users` válidos

### Scripts utilizados
- `apps/api/scripts/cleanup-backend-db.sql`
- `apps/api/scripts/cleanup-admin-db.sql`

---

## 5. IDs de referencia rápida

| Entidad | ID | Email/Slug |
|---------|----|------------|
| Client urbanprint (backend) | `f2d3f270-583b-4644-9a61-2c0d6824f101` | urbanprint.contacto@gmail.com |
| Client Tienda Test (backend) | `19986d95-2702-4cf2-ba3d-5b4a3df01ef7` | kaddocpendragon@gmail.com |
| Account kaddocpendragon (admin) | `7f62b1e5-c518-402c-abcb-88ab9db56dfe` | slug: `test` |
| User novavision.contact (backend auth) | `d879a6e1-178c-4e69-b389-f13f395f44c4` | super_admin |
| User novavision.contact (admin auth) | `a1b4ca03-3873-440e-8d81-802c677c5439` | admin |
| User kaddocpendragon (admin auth) | `8e2dddb6-071e-4a3c-95a3-2efde374b8e1` | client |
| User urbanprint (backend public) | `bb984bef-b3eb-4cf9-85d7-81a2f0167ca6` | admin (urbanprint) |
