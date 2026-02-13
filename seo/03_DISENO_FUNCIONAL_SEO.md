# Diseño Funcional SEO — Super Admin vs Admin Cliente + Producto SEO

**Fecha:** 2026-02-12  
**Autor:** Agente Copilot  
**Prerequisito:** Leer `01_AUDIT_SEO_NOVAVISION.md` y `02_PLAN_FASES_SEO.md`

---

## 1. Separación de Responsabilidades

### Principio: Control Plane vs Tenant Plane

| Aspecto | Super Admin (NovaVision) | Admin Cliente (Tenant) |
|---------|--------------------------|------------------------|
| **Habilitar SEO** | ✅ Activa/desactiva servicio SEO por cuenta | ❌ No puede auto-activar |
| **Ver estado SEO** | ✅ Dashboard global + por tenant | ✅ Solo su tienda |
| **Configurar meta tags** | ❌ No edita contenido del tenant | ✅ Edita meta por producto/categoría/página |
| **Gestionar sitemap** | ✅ Config global (frecuencias, prioridades default) | ✅ Excluir/incluir páginas de sitemap |
| **Schema defaults** | ✅ Define plantillas de schema por plan | ❌ No edita schema directamente |
| **Analytics** | ✅ Ve métricas agregadas cross-tenant | ✅ Configura GA4 de su tienda, ve sus métricas |
| **Redirects** | ❌ No gestiona redirects del tenant | ✅ Crea redirects 301 (límite por plan) |
| **Blog/Contenido** | ❌ No crea contenido del tenant | ✅ CRUD de posts y páginas estáticas |
| **Auditorías** | ✅ Ejecuta y ve auditorías de cualquier tenant | ✅ Ve resultados de auditoría de su tienda |
| **Reports** | ✅ Genera y programa reports | ✅ Recibe y descarga reports mensuales |
| **Custom domain** | ✅ Aprueba/configura DNS | ✅ Solicita dominio (Growth+) |
| **Search Console** | ✅ Ve estado de verificación | ✅ Configura verificación de su dominio |

---

## 2. Pantallas — Super Admin (Admin App)

### 2.1 Tab SEO en Client Details

**Ubicación:** `apps/admin/src/pages/ClientDetails/tabs/SEOTab.jsx`  
**Acceso:** Super admin solamente  
**Sección del dashboard de detalle del cliente**

```
┌─────────────────────────────────────────────────────────┐
│  [Tab: General] [Tab: Billing] [Tab: Features] [Tab: SEO]  │
├─────────────────────────────────────────────────────────┤
│                                                           │
│  SEO Service Status                                       │
│  ┌─────────────────────────────────────────┐            │
│  │ Plan: Growth          SEO: ✅ Activo     │            │
│  │ Habilitado: 2026-01-15                   │            │
│  │ Último report: 2026-02-01                │            │
│  └─────────────────────────────────────────┘            │
│                                                           │
│  📊 Métricas Rápidas (últimos 30 días)                   │
│  ┌──────────┬──────────┬──────────┬──────────┐          │
│  │ Páginas  │ Queries  │ Clicks   │ CWV      │          │
│  │ Indexadas│ Top      │ Orgánico │ Score    │          │
│  │ 342      │ 1,247    │ 8,451    │ 82/100   │          │
│  └──────────┴──────────┴──────────┴──────────┘          │
│                                                           │
│  📋 Checklist de Entregables                             │
│  ☑ robots.txt configurado                                │
│  ☑ Sitemap activo (342 URLs)                            │
│  ☑ Meta tags por producto (291/300 ✅)                   │
│  ☐ Schema Product en todas las páginas                   │
│  ☐ Blog habilitado                                       │
│  ☐ Primera auditoría CWV completada                     │
│                                                           │
│  📜 Historial de Acciones                                │
│  2026-02-01 — Report mensual generado                    │
│  2026-01-28 — Schema Product desplegado                  │
│  2026-01-15 — Servicio SEO habilitado                   │
│                                                           │
│  [🔧 Configurar] [📊 Ver Report] [🔍 Ejecutar Auditoría] │
└─────────────────────────────────────────────────────────┘
```

**Acciones del Super Admin:**
- **Habilitar/deshabilitar** servicio SEO para el tenant
- **Ejecutar auditoría** on-demand (Lighthouse + checks internos)
- **Ver/descargar** reports mensuales
- **Marcar entregables** como completados
- **Ver historial** de acciones SEO

### 2.2 Vista Global SEO (Dashboard)

**Ubicación:** `apps/admin/src/pages/AdminDashboard/SEOOverview.jsx`

```
┌─────────────────────────────────────────────────────────┐
│  📈 SEO Overview (todos los tenants con servicio activo)  │
├─────────────────────────────────────────────────────────┤
│                                                           │
│  Tenants con SEO activo: 12 / 45 Growth+ accounts        │
│                                                           │
│  ┌─────────┬──────────┬──────────┬──────────┬─────────┐ │
│  │ Tenant  │ Plan     │ Indexed  │ CWV      │ Status  │ │
│  ├─────────┼──────────┼──────────┼──────────┼─────────┤ │
│  │ modafit │ Growth   │ 342      │ 82       │ ✅ OK   │ │
│  │ techbuy │ Enterpr. │ 5,021    │ 91       │ ✅ OK   │ │
│  │ artdeco │ Growth   │ 45       │ 64       │ ⚠️ CWV  │ │
│  └─────────┴──────────┴──────────┴──────────┴─────────┘ │
│                                                           │
│  ⚠️ Alertas activas: 3                                   │
│  - artdeco: LCP > 4s (producto con imagen 5MB)          │
│  - sportzone: Sitemap error 500                         │
│  - modafit: 15 productos sin meta description           │
└─────────────────────────────────────────────────────────┘
```

---

## 3. Pantallas — Admin Cliente (Web Storefront /admin-dashboard)

### 3.1 Sección SEO en Admin Dashboard del Tenant

**Ubicación:** `apps/web/src/components/admin/SEOSettings/`  
**Acceso:** Solo tenants con plan Growth o Enterprise + servicio SEO habilitado  
**Gating:** Verificar `plan_key` en entitlements + flag `seo_service_enabled` en account settings

```
┌─────────────────────────────────────────────────────────┐
│  [Productos] [Pedidos] [Apariencia] [SEO] [Config]       │
├─────────────────────────────────────────────────────────┤
│                                                           │
│  🔍 SEO de tu Tienda                                     │
│                                                           │
│  📊 Resumen                                              │
│  ┌──────────┬──────────┬──────────┐                     │
│  │ Productos│ Con meta │ Sin meta │                     │
│  │ 300      │ 291 ✅   │ 9  ⚠️   │                     │
│  └──────────┴──────────┴──────────┘                     │
│                                                           │
│  ⚡ Acciones Rápidas                                     │
│  [📝 Editar Meta de Home]                                │
│  [📊 Ver Report Mensual]                                 │
│  [🔗 Gestionar Redirects]                                │
│  [📖 Gestionar Blog]                                     │
│                                                           │
│  🏪 Meta de la Tienda (Home)                             │
│  ┌─────────────────────────────────────────┐            │
│  │ Título SEO:    [ModaFit - Ropa Depor...] │            │
│  │ Descripción:   [Tienda online de ropa...] │            │
│  │ OG Image:      [📷 Subir imagen]          │            │
│  │ Canonical URL:  https://modafit.com       │            │
│  └─────────────────────────────────────────┘            │
│  [💾 Guardar]                                            │
│                                                           │
│  🔧 Configuración                                        │
│  ┌─────────────────────────────────────────┐            │
│  │ Google Analytics ID: [G-XXXXXXXXXX]      │            │
│  │ Search Console:      [Meta tag o archivo] │            │
│  │ Noindex tienda:      [Toggle OFF]        │            │
│  └─────────────────────────────────────────┘            │
└─────────────────────────────────────────────────────────┘
```

### 3.2 SEO por Producto (inline en editor de producto)

**Ubicación:** Sección colapsable dentro del editor de producto existente

```
┌─────────────────────────────────────────────────────────┐
│  Editar Producto: "Remera Dry-Fit Pro"                   │
│  ...campos existentes (nombre, precio, stock, etc.)...   │
│                                                           │
│  ▼ SEO (Growth/Enterprise)                               │
│  ┌─────────────────────────────────────────┐            │
│  │ Meta Título:    [Remera Dry-Fit Pro -... ] │            │
│  │                 57/60 caracteres ✅        │            │
│  │                                           │            │
│  │ Meta Descripción: [Remera deportiva de..] │            │
│  │                   142/160 caracteres ✅   │            │
│  │                                           │            │
│  │ URL slug:       /p/remera-dry-fit-pro     │            │
│  │                 (auto-generado, editable) │            │
│  │                                           │            │
│  │ 🔍 Preview en Google:                    │            │
│  │ ┌───────────────────────────────────┐    │            │
│  │ │ Remera Dry-Fit Pro - ModaFit     │    │            │
│  │ │ modafit.com/p/remera-dry-fit-pro │    │            │
│  │ │ Remera deportiva de alta perfor...│    │            │
│  │ └───────────────────────────────────┘    │            │
│  │                                           │            │
│  │ Incluir en Sitemap: [Toggle ON]          │            │
│  └─────────────────────────────────────────┘            │
└─────────────────────────────────────────────────────────┘
```

### 3.3 Gestión de Redirects

**Ubicación:** `apps/web/src/components/admin/SEORedirects/`

```
┌─────────────────────────────────────────────────────────┐
│  🔗 Redirects (3/20 usados)                              │
│                                                           │
│  ┌──────────────┬──────────────┬──────────┬───────────┐ │
│  │ Desde        │ Hacia        │ Tipo     │ Acciones  │ │
│  ├──────────────┼──────────────┼──────────┼───────────┤ │
│  │ /old-product │ /p/abc123    │ 301      │ [✏️] [🗑️] │ │
│  │ /promo       │ /search?q=.. │ 302      │ [✏️] [🗑️] │ │
│  └──────────────┴──────────────┴──────────┴───────────┘ │
│                                                           │
│  [➕ Agregar Redirect]                                    │
│                                                           │
│  Límite por plan:                                        │
│  Growth: 20 redirects | Enterprise: ilimitados           │
└─────────────────────────────────────────────────────────┘
```

---

## 4. Modelo de Datos — Migraciones Necesarias

### 4.1 Multicliente DB (tablas de negocio)

```sql
-- SEO settings por tenant (1:1 con clients)
CREATE TABLE seo_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id UUID NOT NULL UNIQUE REFERENCES clients(id) ON DELETE CASCADE,
    
    -- Home meta
    home_meta_title TEXT,
    home_meta_description TEXT,
    home_og_image_url TEXT,
    
    -- Analytics
    ga_measurement_id TEXT,         -- G-XXXXXXXXXX
    search_console_verification TEXT, -- Meta tag content
    
    -- Control
    noindex_store BOOLEAN NOT NULL DEFAULT FALSE,  -- Tenant puede ocultar su tienda
    sitemap_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    
    -- Defaults para auto-generación de meta
    meta_title_template TEXT DEFAULT '{product_name} - {store_name}',  -- Template
    meta_desc_template TEXT DEFAULT '{product_description}',
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS
ALTER TABLE seo_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "seo_settings_select_tenant" ON seo_settings FOR SELECT
    USING (client_id = current_client_id());
CREATE POLICY "seo_settings_write_admin" ON seo_settings FOR ALL
    USING (client_id = current_client_id() AND is_admin())
    WITH CHECK (client_id = current_client_id() AND is_admin());
CREATE POLICY "server_bypass" ON seo_settings FOR ALL
    USING (auth.role() = 'service_role') WITH CHECK (auth.role() = 'service_role');

-- SEO meta por producto (1:1 con products)
CREATE TABLE product_seo (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    
    meta_title TEXT,               -- Override del template
    meta_description TEXT,         -- Override
    url_slug TEXT,                 -- slug amigable para URL (futuro)
    include_in_sitemap BOOLEAN NOT NULL DEFAULT TRUE,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(client_id, product_id)
);

-- RLS (misma estructura que seo_settings)
ALTER TABLE product_seo ENABLE ROW LEVEL SECURITY;
CREATE POLICY "product_seo_select_tenant" ON product_seo FOR SELECT
    USING (client_id = current_client_id());
CREATE POLICY "product_seo_write_admin" ON product_seo FOR ALL
    USING (client_id = current_client_id() AND is_admin())
    WITH CHECK (client_id = current_client_id() AND is_admin());
CREATE POLICY "server_bypass" ON product_seo FOR ALL
    USING (auth.role() = 'service_role') WITH CHECK (auth.role() = 'service_role');

-- Redirects del tenant
CREATE TABLE tenant_redirects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
    
    from_path TEXT NOT NULL,       -- /old-product
    to_path TEXT NOT NULL,         -- /p/abc123
    status_code INT NOT NULL DEFAULT 301 CHECK (status_code IN (301, 302)),
    active BOOLEAN NOT NULL DEFAULT TRUE,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(client_id, from_path)
);

-- RLS
ALTER TABLE tenant_redirects ENABLE ROW LEVEL SECURITY;
CREATE POLICY "redirects_select_tenant" ON tenant_redirects FOR SELECT
    USING (client_id = current_client_id());
CREATE POLICY "redirects_write_admin" ON tenant_redirects FOR ALL
    USING (client_id = current_client_id() AND is_admin())
    WITH CHECK (client_id = current_client_id() AND is_admin());
CREATE POLICY "server_bypass" ON tenant_redirects FOR ALL
    USING (auth.role() = 'service_role') WITH CHECK (auth.role() = 'service_role');

-- Índices
CREATE INDEX idx_seo_settings_client ON seo_settings(client_id);
CREATE INDEX idx_product_seo_client ON product_seo(client_id);
CREATE INDEX idx_product_seo_product ON product_seo(product_id);
CREATE INDEX idx_redirects_client ON tenant_redirects(client_id);
CREATE INDEX idx_redirects_path ON tenant_redirects(client_id, from_path);
```

### 4.2 Admin DB (gestión del servicio)

```sql
-- Flag de servicio SEO por cuenta
ALTER TABLE nv_accounts 
    ADD COLUMN seo_service_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN seo_service_enabled_at TIMESTAMPTZ;

-- Historial de acciones SEO (super admin tracking)
CREATE TABLE seo_service_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID NOT NULL REFERENCES nv_accounts(id) ON DELETE CASCADE,
    action TEXT NOT NULL,           -- 'enabled', 'audit_run', 'report_sent', 'deliverable_completed'
    data JSONB,                     -- Detalles de la acción
    performed_by UUID,              -- User ID del super admin
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_seo_log_account ON seo_service_log(account_id);
CREATE INDEX idx_seo_log_created ON seo_service_log(created_at);

-- Entregables por cuenta
CREATE TABLE seo_deliverables (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID NOT NULL REFERENCES nv_accounts(id) ON DELETE CASCADE,
    name TEXT NOT NULL,             -- 'robots_configured', 'sitemap_active', etc.
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'in_progress', 'completed')),
    completed_at TIMESTAMPTZ,
    completed_by UUID,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_seo_deliv_account ON seo_deliverables(account_id);
```

---

## 5. Propuesta de Servicio — Growth SEO vs Enterprise SEO

### 5.1 Growth SEO

| Concepto | Detalle |
|----------|---------|
| **Precio sugerido** | Incluido en plan Growth (o upsell +$X/mes) |
| **Setup inicial** | robots.txt, sitemap, meta tags, schema base, analytics |
| **Panel SEO** | Sección en admin dashboard: meta por producto, redirects (20), resumen |
| **Report** | Mensual automático (email + descargable) |
| **Auditoría** | 1 auditoría Lighthouse trimestral |
| **Soporte** | Documentación + FAQs SEO |
| **SLA** | Sitemap generado en < 1 hora post-publicación de producto |
| **Límites** | 20 redirects, sin blog, sin landings custom |

**Entregables incluidos:**
1. ✅ robots.txt dinámico por tenant
2. ✅ Sitemap XML automático
3. ✅ Meta tags editables por producto (title, description)
4. ✅ Canonical URLs automáticos
5. ✅ Schema Product base
6. ✅ OG/Twitter meta dinámicos (social previews)
7. ✅ GA4 setup
8. ✅ Breadcrumbs
9. ✅ Noindex en rutas privadas
10. ✅ 20 redirects 301/302

### 5.2 Enterprise SEO

| Concepto | Detalle |
|----------|---------|
| **Precio sugerido** | Incluido en plan Enterprise |
| **Todo Growth SEO** | + lo siguiente |
| **Blog/CMS** | Módulo de blog con categories, meta, schema Article |
| **Static Pages** | Páginas gestionables (FAQ, Sobre Nosotros, Políticas) |
| **Redirects** | Ilimitados |
| **Custom domain** | Setup incluyendo SEO migration (canonical, sitemap) |
| **Performance** | Hardening CWV: image optimization audit, cache review |
| **Schema avanzado** | FAQ, HowTo, Article, BreadcrumbList, SearchAction |
| **Auditoría** | Mensual con recomendaciones personalizadas |
| **Report** | Semanal + mensual con insights y benchmarks |
| **Consultoria** | 1 sesión/mes de estrategia de contenido |
| **SLA** | Response < 24h para issues SEO críticos |

**Entregables adicionales Enterprise:**
1. ✅ Blog con editor
2. ✅ Páginas estáticas gestionables
3. ✅ Redirects ilimitados
4. ✅ Schema avanzado (FAQ, Article, SearchAction)
5. ✅ Dashboard SEO Health completo
6. ✅ Alertas automáticas (caída indexación, CWV)
7. ✅ Performance audit mensual
8. ✅ Estrategia de keywords y contenido
9. ✅ Report semanal de métricas
10. ✅ Soporte prioritario SEO

### 5.3 Responsabilidades

| Acción | NovaVision | Cliente |
|--------|:----------:|:-------:|
| Configurar robots/sitemap/canonical | ✅ | ❌ |
| Escribir meta descriptions de productos | Genera defaults con template | ✅ Revisa y ajusta |
| Crear contenido de blog | ❌ (puede asesorar) | ✅ |
| Configurar GA4/Search Console | ✅ Setup | ✅ Provee acceso |
| Monitorear CWV | ✅ | ❌ |
| Resolver issues técnicos SEO | ✅ | ❌ |
| Proveer imágenes de calidad | ❌ | ✅ |
| Definir URLs / estructura | ✅ Recomienda | ✅ Aprueba |

---

## 6. Checklist QA SEO

### 6.1 No rompe checkout
- [ ] Flujo completo compra: agregar al carrito → checkout → pago MP → confirmación
- [ ] No se agregan scripts/meta que interfieran con MP SDK
- [ ] Helmet NO modifica headers de seguridad (CSP, COOP) en rutas de pago
- [ ] Performance de PaymentResultPage no degradada

### 6.2 Zero cross-tenant
- [ ] `curl -H "x-tenant-slug: tiendaA" /seo/sitemap.xml` → solo URLs de tienda A
- [ ] `curl -H "x-tenant-slug: tiendaB" /seo/sitemap.xml` → solo URLs de tienda B
- [ ] Meta tags edge function: verificar con User-Agent de bot que meta corresponden al tenant del request
- [ ] robots.txt: no filtra info de otros tenants
- [ ] GA4: cada tenant tiene su propio measurement ID
- [ ] JSON-LD: `brand.name` = nombre del tenant, no "NovaVision"
- [ ] OG image: imagen del tenant/producto, no logo NovaVision

### 6.3 Sitemap correcto por tenant
- [ ] XML válido (schema validation)
- [ ] URLs usan el dominio correcto (subdomain o custom domain)
- [ ] Solo productos activos incluidos
- [ ] `<lastmod>` coincide con `updated_at` del producto
- [ ] No incluye rutas privadas (/admin, /cart, /profile)
- [ ] Responde con `Content-Type: application/xml`
- [ ] Cache funciona (ETag/If-None-Match)

### 6.4 Noindex en preview/staging
- [ ] Branch deploy de `onboarding-preview-stable` → `robots.txt` con `Disallow: /`
- [ ] Tiendas en estado `draft` o `pending_approval` → meta noindex en todas las páginas
- [ ] Preview URL (`?preview=token`) → noindex
- [ ] Deploy preview de Netlify → noindex (Netlify lo hace automáticamente con `X-Robots-Tag`)

### 6.5 Performance no degradada
- [ ] Lighthouse Performance score no baja más de 5 puntos vs baseline
- [ ] LCP no aumenta más de 500ms
- [ ] Bundle size no aumenta más de 20KB gzipped (por react-helmet-async + schema components)
- [ ] Edge function meta injection latencia < 200ms (p95)

### 6.6 Regresión general
- [ ] Todas las rutas existentes siguen funcionando
- [ ] Tema/template del tenant no se rompe
- [ ] Login/registro funciona
- [ ] Admin dashboard funciona
- [ ] Imágenes siguen cargando correctamente
