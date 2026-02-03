# Arquitectura NovaVision

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         USUARIOS FINALES                                │
│                                                                          │
│    Compradores (Web)              Admins de Tienda              Super Admin
│         │                              │                              │
│         ▼                              ▼                              ▼
│    ┌─────────┐                   ┌─────────┐                   ┌─────────┐
│    │   Web   │                   │  Admin  │                   │  Admin  │
│    │Storefront│                   │Dashboard│                   │Dashboard│
│    └────┬────┘                   └────┬────┘                   └────┬────┘
│         │                              │                              │
└─────────┼──────────────────────────────┼──────────────────────────────┼──┘
          │                              │                              │
          ▼                              ▼                              ▼
    ┌──────────────────────────────────────────────────────────────────────┐
    │                          NETLIFY (Frontends)                          │
    │                                                                        │
    │   templatetwo.netlify.app          novavision.netlify.app             │
    │   (Web Storefront)                 (Admin Dashboard)                   │
    └────────────────────────────────────┬─────────────────────────────────┘
                                         │
                                         │ HTTPS
                                         ▼
    ┌──────────────────────────────────────────────────────────────────────┐
    │                          RAILWAY (API)                                │
    │                                                                        │
    │   templatetwobe.railway.app                                           │
    │   - Auth (/auth/*)                                                    │
    │   - Products (/products/*)                                            │
    │   - Orders (/orders/*)                                                │
    │   - Payments (/payments/*)                                            │
    │   - Webhooks (/webhooks/*)                                            │
    └────────────────────────────────────┬─────────────────────────────────┘
                                         │
                                         │
                                         ▼
    ┌──────────────────────────────────────────────────────────────────────┐
    │                          SUPABASE                                     │
    │                                                                        │
    │   ┌─────────────────────┐      ┌─────────────────────┐               │
    │   │    Admin DB         │      │   Backend DB        │               │
    │   │                     │      │   (Multicliente)    │               │
    │   │ - clients           │      │                     │               │
    │   │ - users (admin)     │      │ - products          │               │
    │   │ - invoices          │      │ - orders            │               │
    │   │ - payments (NV)     │      │ - payments (MP)     │               │
    │   └─────────────────────┘      │ - cart_items        │               │
    │                                │ - users (tienda)    │               │
    │                                │ - banners           │               │
    │                                │ - categories        │               │
    │                                │ - etc...            │               │
    │                                └─────────────────────┘               │
    └──────────────────────────────────────────────────────────────────────┘
```

## Flujo de Datos

### 1. Compra en Web Storefront
```
Usuario → Web → API → Supabase Backend DB
                  ↓
              Mercado Pago
                  ↓
              Webhook → API → Update Order Status
```

### 2. Admin gestiona productos
```
Admin → Dashboard → API → Supabase Backend DB (con client_id filtrado)
```

### 3. Super Admin gestiona clientes
```
Super Admin → Dashboard → Edge Function → Supabase Admin DB
                                      → Supabase Backend DB (replica)
```

## Repositorios y Deploys

| Repo | Tecnología | Deploy | URL |
|------|------------|--------|-----|
| templatetwobe | NestJS | Railway | api.novavision.com |
| novavision | Vite+React | Netlify | admin.novavision.com |
| templatetwo | Vite+React | Netlify | {client}.novavision.com |
| novavision-docs | Markdown | - | Solo documentación |

## Variables de Entorno por Repo

### API (templatetwobe)
```
SUPABASE_URL=
SUPABASE_SERVICE_ROLE_KEY=
MP_ACCESS_TOKEN=
JWT_SECRET=
```

### Admin (novavision)
```
VITE_SUPABASE_URL=
VITE_SUPABASE_ANON_KEY=
VITE_API_URL=
```

### Web (templatetwo)
```
VITE_SUPABASE_URL=
VITE_SUPABASE_ANON_KEY=
VITE_API_URL=
VITE_MP_PUBLIC_KEY=
```
