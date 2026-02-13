# Plan de Implementación: Analytics, Inventory & Product Variants

**Fecha:** 2026-02-13  
**Alcance:** API + Web + Admin  
**Prioridad:** Alta  
**Estimación Total:** 6-8 sprints (12-16 semanas)

---

## 📊 Tabla de Contenidos

1. [Analytics Dashboard](#1-analytics-dashboard)
2. [Inventory Management](#2-inventory-management)
3. [Product Variants](#3-product-variants)
4. [Feature Gating por Plan](#4-feature-gating-por-plan)
5. [Super Admin Dashboard](#5-super-admin-dashboard)
6. [Orden de Implementación Sugerido](#6-orden-de-implementación-sugerido)
7. [Arquitectura Transversal](#7-arquitectura-transversal)
8. [Testing Strategy](#8-testing-strategy)

---

## 1. Analytics Dashboard

### 1.1. Análisis de Requisitos

**Objetivo:** Proveer insights accionables sobre ventas, productos y conversión para que los administradores de tienda tomen decisiones basadas en datos.

**Métricas Core:**
- **Ventas:** ingresos totales, órdenes, ticket promedio, tendencias temporales
- **Productos Top:** más vendidos, más vistos, mejor margen, abandonos en carrito
- **Conversión:** funnel checkout, tasa de conversión, abandono por etapa
- **Clientes:** nuevos vs recurrentes, CLV (Customer Lifetime Value), geografía

**Requisitos Técnicos:**
- Agregaciones pre-calculadas (tablas materializadas o vistas para performance)
- Cache de métricas (TTL 15-30 min para datos near-real-time)
- Exportación CSV/Excel de reportes
- Filtros: rango de fechas, categoría, producto, estado de orden
- Charts: líneas (tendencias), barras (comparativas), pie (distribución)

### 1.2. Diseño de Base de Datos

#### Nuevas Tablas (Backend DB)

```sql
-- Tabla de agregaciones diarias (pre-calculadas por worker)
CREATE TABLE analytics_daily_sales (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  -- Métricas de ventas
  orders_count INTEGER NOT NULL DEFAULT 0,
  revenue NUMERIC(12,2) NOT NULL DEFAULT 0,
  avg_order_value NUMERIC(12,2) NOT NULL DEFAULT 0,
  items_sold INTEGER NOT NULL DEFAULT 0,
  -- Métricas de conversión
  visitors INTEGER DEFAULT 0, -- requiere tracking de visitas
  add_to_cart INTEGER DEFAULT 0,
  initiated_checkout INTEGER DEFAULT 0,
  completed_checkout INTEGER DEFAULT 0,
  conversion_rate NUMERIC(5,2) DEFAULT 0, -- completed/visitors * 100
  -- Métricas de clientes
  new_customers INTEGER DEFAULT 0,
  returning_customers INTEGER DEFAULT 0,
  -- Metadata
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(client_id, date)
);

CREATE INDEX idx_analytics_daily_client_date ON analytics_daily_sales(client_id, date DESC);

-- Tabla de productos top (pre-calculada diariamente)
CREATE TABLE analytics_product_performance (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  -- Métricas de producto
  views INTEGER DEFAULT 0,
  add_to_cart_count INTEGER DEFAULT 0,
  units_sold INTEGER DEFAULT 0,
  revenue NUMERIC(12,2) DEFAULT 0,
  avg_price NUMERIC(10,2) DEFAULT 0,
  -- Métricas de stock
  stock_start INTEGER DEFAULT 0,
  stock_end INTEGER DEFAULT 0,
  -- Metadata
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(client_id, product_id, date)
);

CREATE INDEX idx_analytics_product_client_date ON analytics_product_performance(client_id, date DESC);
CREATE INDEX idx_analytics_product_revenue ON analytics_product_performance(client_id, revenue DESC);
CREATE INDEX idx_analytics_product_units ON analytics_product_performance(client_id, units_sold DESC);

-- Tabla de eventos de conversión (para funnel analysis)
CREATE TABLE analytics_conversion_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  session_id TEXT NOT NULL, -- cookie/fingerprint del usuario
  user_id UUID REFERENCES users(id) ON DELETE SET NULL, -- nullable para anónimos
  event_type TEXT NOT NULL, -- 'page_view', 'product_view', 'add_to_cart', 'checkout_start', 'checkout_complete'
  event_data JSONB, -- { product_id, category_id, order_id, value, etc }
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_analytics_events_client_type_date ON analytics_conversion_events(client_id, event_type, created_at DESC);
CREATE INDEX idx_analytics_events_session ON analytics_conversion_events(session_id, created_at DESC);

-- Tabla de cohorts de clientes (calculada mensualmente)
CREATE TABLE analytics_customer_cohorts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  cohort_month DATE NOT NULL, -- primer mes de compra del cohorte
  months_since_first INTEGER NOT NULL, -- 0 = mes de adquisición, 1 = mes 1, etc
  customers_count INTEGER NOT NULL,
  orders_count INTEGER NOT NULL,
  revenue NUMERIC(12,2) NOT NULL,
  retention_rate NUMERIC(5,2) NOT NULL, -- % que volvió a comprar
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(client_id, cohort_month, months_since_first)
);

CREATE INDEX idx_analytics_cohorts_client_month ON analytics_customer_cohorts(client_id, cohort_month DESC);
```

#### Políticas RLS

```sql
-- analytics_daily_sales
CREATE POLICY "analytics_daily_sales_select_tenant"
  ON analytics_daily_sales FOR SELECT
  USING (client_id = current_client_id());

CREATE POLICY "analytics_daily_sales_server_bypass"
  ON analytics_daily_sales FOR ALL
  USING (auth.role() = 'service_role');

ALTER TABLE analytics_daily_sales ENABLE ROW LEVEL SECURITY;

-- Repetir para analytics_product_performance, analytics_conversion_events, analytics_customer_cohorts
```

### 1.3. Backend API (NestJS)

#### Módulo y Estructura

```
src/analytics/
├── analytics.module.ts
├── analytics.controller.ts        # 12 endpoints REST
├── analytics.service.ts           # Lógica de agregaciones
├── analytics-worker.service.ts    # Cron jobs para pre-cálculo
├── dto/
│   ├── analytics-query.dto.ts     # Filtros comunes (dateFrom, dateTo, etc)
│   ├── sales-metrics.dto.ts
│   └── product-performance.dto.ts
└── __tests__/
    ├── analytics.service.spec.ts
    └── analytics-worker.spec.ts
```

#### Endpoints API

| Método | Ruta | Plan | Descripción |
|--------|------|------|-------------|
| GET | `/analytics/sales/overview` | Growth+ | Métricas resumen: revenue, orders, avg ticket (período) |
| GET | `/analytics/sales/timeline` | Growth+ | Serie temporal de ventas (diaria/semanal/mensual) |
| GET | `/analytics/products/top` | Growth+ | Top N productos por revenue/units/views |
| GET | `/analytics/products/:id/performance` | Growth+ | Detalle de performance de un producto |
| GET | `/analytics/conversion/funnel` | Enterprise | Funnel completo (visitors → checkout) |
| GET | `/analytics/conversion/abandonment` | Enterprise | Análisis de abandono por etapa |
| GET | `/analytics/customers/cohorts` | Enterprise | Análisis de cohortes de retención |
| GET | `/analytics/customers/clv` | Enterprise | Customer Lifetime Value promedio |
| GET | `/analytics/categories/performance` | Growth+ | Performance por categoría |
| POST | `/analytics/events/track` | Growth+ | Registrar evento de conversión (desde front) |
| GET | `/analytics/export/sales` | Growth+ | Exportar CSV de ventas |
| GET | `/analytics/export/products` | Growth+ | Exportar CSV de productos |

**Query Params Comunes:**
- `dateFrom` (ISO 8601)
- `dateTo` (ISO 8601)
- `granularity` (day | week | month)
- `limit` (default 10, max 100)
- `categoryId` (opcional)
- `productId` (opcional)

#### Worker Service (Cron Jobs)

```typescript
@Injectable()
export class AnalyticsWorkerService {
  // Cron: todos los días a las 2:00 AM
  @Cron('0 2 * * *')
  async calculateDailySales() {
    // Para cada client_id activo:
    // 1. Agregar orders del día anterior (group by client_id, date)
    // 2. Upsert en analytics_daily_sales
    // 3. Calcular métricas (avg_order_value, conversion_rate si hay datos)
  }

  @Cron('0 3 * * *')
  async calculateProductPerformance() {
    // Para cada client_id activo:
    // 1. Agregar order_items del día anterior por producto
    // 2. Sumar revenue, units_sold
    // 3. Obtener stock_start/end desde stock_movements (si existe tabla)
    // 4. Upsert en analytics_product_performance
  }

  @Cron('0 4 1 * *') // 1er día del mes a las 4 AM
  async calculateCustomerCohorts() {
    // Para cada client_id:
    // 1. Agrupar usuarios por cohort_month (mes de su primera orden)
    // 2. Calcular retention_rate por mes desde adquisición
    // 3. Upsert en analytics_customer_cohorts
  }

  @Cron('0 5 * * *')
  async cleanupOldEvents() {
    // Eliminar analytics_conversion_events > 90 días (GDPR compliance)
  }
}
```

### 1.4. Frontend Web (Tienda - Admin Dashboard)

#### Componentes Nuevos

```
src/components/analytics/
├── SalesOverview/
│   ├── index.jsx                 # Cards con métricas clave
│   ├── SalesChart.jsx            # Chart.js línea temporal
│   └── style.jsx
├── ProductsPerformance/
│   ├── index.jsx                 # Tabla top productos
│   ├── ProductChart.jsx          # Chart.js barras comparativas
│   └── style.jsx
├── ConversionFunnel/
│   ├── index.jsx                 # Funnel visual (Enterprise)
│   └── style.jsx
├── CustomersInsights/
│   ├── CohortsTable.jsx          # Tabla de cohortes (Enterprise)
│   ├── CLVCard.jsx
│   └── style.jsx
└── AnalyticsFilters/
    ├── index.jsx                 # Date range picker, selects
    └── style.jsx
```

#### Nueva Página: `/admin/analytics`

```jsx
// src/pages/AdminDashboard/AnalyticsView.jsx
import { useState, useEffect } from 'react';
import { SalesOverview } from '@/components/analytics/SalesOverview';
import { ProductsPerformance } from '@/components/analytics/ProductsPerformance';
import { ConversionFunnel } from '@/components/analytics/ConversionFunnel';
import { CustomersInsights } from '@/components/analytics/CustomersInsights';
import { AnalyticsFilters } from '@/components/analytics/AnalyticsFilters';
import { useAnalytics } from '@/hooks/useAnalytics';

export function AnalyticsView() {
  const [filters, setFilters] = useState({
    dateFrom: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000), // últimos 30 días
    dateTo: new Date(),
    granularity: 'day',
  });

  const {
    salesOverview,
    salesTimeline,
    topProducts,
    conversionFunnel,
    loading,
    error,
    refetch,
  } = useAnalytics(filters);

  return (
    <Container>
      <Header>
        <Title>Analytics</Title>
        <ExportButton onClick={() => handleExport()}>
          Exportar CSV
        </ExportButton>
      </Header>

      <AnalyticsFilters filters={filters} onChange={setFilters} />

      {/* Sección 1: Ventas (Growth+) */}
      <Section>
        <SectionTitle>Ventas</SectionTitle>
        <SalesOverview data={salesOverview} timeline={salesTimeline} />
      </Section>

      {/* Sección 2: Productos (Growth+) */}
      <Section>
        <SectionTitle>Productos Top</SectionTitle>
        <ProductsPerformance products={topProducts} />
      </Section>

      {/* Sección 3: Conversión (Enterprise) */}
      {plan === 'enterprise' && (
        <Section>
          <SectionTitle>Embudo de Conversión</SectionTitle>
          <ConversionFunnel data={conversionFunnel} />
        </Section>
      )}

      {/* Sección 4: Clientes (Enterprise) */}
      {plan === 'enterprise' && (
        <Section>
          <SectionTitle>Insights de Clientes</SectionTitle>
          <CustomersInsights />
        </Section>
      )}
    </Container>
  );
}
```

#### Hook: `useAnalytics`

```javascript
// src/hooks/useAnalytics.js
import { useState, useEffect } from 'react';
import { analyticsService } from '@/services/analytics';

export function useAnalytics(filters) {
  const [data, setData] = useState({
    salesOverview: null,
    salesTimeline: [],
    topProducts: [],
    conversionFunnel: null,
  });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const fetchData = async () => {
    setLoading(true);
    try {
      const [overview, timeline, products, funnel] = await Promise.all([
        analyticsService.getSalesOverview(filters),
        analyticsService.getSalesTimeline(filters),
        analyticsService.getTopProducts(filters),
        // Solo en Enterprise:
        plan === 'enterprise' 
          ? analyticsService.getConversionFunnel(filters)
          : Promise.resolve(null),
      ]);

      setData({ salesOverview: overview, salesTimeline: timeline, topProducts: products, conversionFunnel: funnel });
    } catch (err) {
      setError(err);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchData();
  }, [filters.dateFrom, filters.dateTo, filters.granularity]);

  return { ...data, loading, error, refetch: fetchData };
}
```

#### Tracking de Eventos (Client-Side)

```javascript
// src/services/analytics.js (agregar método)
export const analyticsService = {
  // ... métodos existentes

  // Llamar desde ProductPage, CartPage, CheckoutPage
  async trackEvent(eventType, eventData) {
    try {
      // Obtener session_id de cookie o generar fingerprint
      const sessionId = getOrCreateSessionId();
      
      await api.post('/analytics/events/track', {
        session_id: sessionId,
        event_type: eventType, // 'product_view', 'add_to_cart', etc
        event_data: eventData,  // { product_id, value, etc }
      });
    } catch (err) {
      console.warn('Analytics tracking failed:', err);
      // No bloquear UX si tracking falla
    }
  },
};

// Ejemplo de uso en ProductPage
useEffect(() => {
  analyticsService.trackEvent('product_view', { product_id: product.id });
}, [product.id]);

// Ejemplo en CartProvider al agregar item
const addItem = (product, quantity) => {
  // ... lógica existente
  analyticsService.trackEvent('add_to_cart', { 
    product_id: product.id, 
    quantity,
    value: product.price * quantity,
  });
};
```

### 1.5. Super Admin Dashboard

#### Nueva Vista: `/dashboard/analytics-overview`

**Funcionalidad:**
- Ver métricas agregadas de TODAS las tiendas
- Top tiendas por revenue, órdenes
- Benchmark de conversión promedio
- Identificar tiendas con bajo performance (candidatos a churn)

**Endpoint API:**
```
GET /admin/analytics/cross-tenant/overview
GET /admin/analytics/cross-tenant/top-stores
```

**Componentes:**
- `CrossTenantAnalyticsView.jsx` en `apps/admin/src/pages/AdminDashboard/`
- Tabla con columnas: Tienda, Revenue (30d), Órdenes, Ticket Promedio, Conversión %
- Filtros por plan, estado (active/paused), rango de fechas

### 1.6. Plan de Implementación (Fases)

#### Fase 1: Fundamentos (Sprint 1-2)
- [ ] Migración: tablas `analytics_daily_sales`, `analytics_product_performance`
- [ ] Backend: `AnalyticsModule` + 6 endpoints básicos (sales overview/timeline, products top)
- [ ] Worker: cron `calculateDailySales` + `calculateProductPerformance`
- [ ] Feature catalog: `dashboard.analytics` (growth+)
- [ ] Tests: 15 unit tests en service

#### Fase 2: Frontend Tienda (Sprint 3)
- [ ] Frontend Web: componentes `SalesOverview` + `ProductsPerformance`
- [ ] Hook `useAnalytics`
- [ ] Página `/admin/analytics` con gating por plan
- [ ] Tracking de eventos básicos (product_view, add_to_cart)
- [ ] Tests: 8 component tests

#### Fase 3: Conversión & Clientes (Sprint 4)
- [ ] Migración: tablas `analytics_conversion_events` + `analytics_customer_cohorts`
- [ ] Backend: endpoints funnel + cohorts (Enterprise)
- [ ] Worker: cron `calculateCustomerCohorts`
- [ ] Frontend: `ConversionFunnel` + `CustomersInsights` (Enterprise gated)
- [ ] Tests: 10 unit tests

#### Fase 4: Super Admin (Sprint 5)
- [ ] Backend: endpoints cross-tenant
- [ ] Admin Dashboard: `CrossTenantAnalyticsView`
- [ ] Tests: 5 integration tests

#### Fase 5: Optimización (Sprint 6)
- [ ] Cache layer (Redis) para métricas de alta demanda
- [ ] Exportación CSV/Excel
- [ ] Vistas materializadas para queries complejas (opcional)
- [ ] Performance tuning (índices, query optimization)
- [ ] Documentación y runbook

### 1.7. Estimación de Esfuerzo

| Fase | Backend | Frontend Web | Admin | Testing | Total |
|------|---------|--------------|-------|---------|-------|
| Fase 1 | 3d | - | - | 1d | 4d |
| Fase 2 | 1d | 4d | - | 1d | 6d |
| Fase 3 | 2d | 2d | - | 1d | 5d |
| Fase 4 | 1d | - | 2d | 0.5d | 3.5d |
| Fase 5 | 1d | 1d | - | 0.5d | 2.5d |
| **Total** | **8d** | **7d** | **2d** | **4d** | **21d (~4 sprints)** |

---

## 2. Inventory Management

### 2.1. Análisis de Requisitos

**Objetivo:** Gestión proactiva de stock para prevenir quiebres y optimizar reabastecimiento.

**Funcionalidades Core:**
- **Alertas de stock bajo:** notificación cuando stock < umbral configurable
- **Historial de movimientos:** entrada/salida de stock con razón (venta, ajuste, devolución)
- **Reabastecimiento automático:** sugerencias basadas en velocidad de venta
- **Reservas de stock:** bloquear unidades durante checkout (TTL 15 min)
- **Stock por ubicación:** multi-warehouse (Enterprise)
- **Proyecciones:** cuándo se agotará el stock (basado en tendencia)

**Requisitos Técnicos:**
- Transacciones ACID para movimientos de stock
- RPC functions para operaciones atómicas (decrementar, reservar, liberar)
- Cron job para alertas diarias
- Webhooks/emails cuando stock crítico
- Logs de auditoría completos

### 2.2. Diseño de Base de Datos

#### Nuevas Tablas (Backend DB)

```sql
-- Configuración de alertas por producto
CREATE TABLE inventory_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  -- Umbrales
  low_stock_threshold INTEGER NOT NULL DEFAULT 10,
  reorder_point INTEGER NOT NULL DEFAULT 20,
  reorder_quantity INTEGER NOT NULL DEFAULT 50,
  -- Estado
  alerts_enabled BOOLEAN NOT NULL DEFAULT true,
  auto_reorder_enabled BOOLEAN NOT NULL DEFAULT false, -- Enterprise
  -- Metadata
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(client_id, product_id)
);

CREATE INDEX idx_inventory_settings_client ON inventory_settings(client_id);

-- Historial de movimientos de stock
CREATE TABLE stock_movements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  -- Movimiento
  movement_type TEXT NOT NULL, -- 'sale', 'purchase', 'adjustment', 'return', 'reservation', 'reservation_release'
  quantity INTEGER NOT NULL, -- positivo = entrada, negativo = salida
  stock_before INTEGER NOT NULL,
  stock_after INTEGER NOT NULL,
  -- Referencias
  order_id UUID REFERENCES orders(id) ON DELETE SET NULL,
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  -- Metadata
  reason TEXT,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by UUID REFERENCES users(id) ON DELETE SET NULL
);

CREATE INDEX idx_stock_movements_client_product ON stock_movements(client_id, product_id, created_at DESC);
CREATE INDEX idx_stock_movements_order ON stock_movements(order_id);

-- Reservas de stock (TTL 15 min durante checkout)
CREATE TABLE stock_reservations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  quantity INTEGER NOT NULL,
  -- Referencia al carrito/orden
  session_id TEXT NOT NULL, -- cart session o order temp ID
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  -- TTL
  expires_at TIMESTAMPTZ NOT NULL,
  released BOOLEAN NOT NULL DEFAULT false,
  released_at TIMESTAMPTZ,
  -- Metadata
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_stock_reservations_product ON stock_reservations(client_id, product_id) WHERE NOT released;
CREATE INDEX idx_stock_reservations_expires ON stock_reservations(expires_at) WHERE NOT released;

-- Alertas de stock bajo
CREATE TABLE inventory_alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  alert_type TEXT NOT NULL, -- 'low_stock', 'out_of_stock', 'reorder_point'
  current_stock INTEGER NOT NULL,
  threshold INTEGER NOT NULL,
  -- Estado
  status TEXT NOT NULL DEFAULT 'pending', -- 'pending', 'notified', 'resolved', 'dismissed'
  notified_at TIMESTAMPTZ,
  resolved_at TIMESTAMPTZ,
  dismissed_at TIMESTAMPTZ,
  dismissed_by UUID REFERENCES users(id) ON DELETE SET NULL,
  -- Metadata
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_inventory_alerts_client ON inventory_alerts(client_id, status, created_at DESC);
CREATE INDEX idx_inventory_alerts_product ON inventory_alerts(product_id, status);

-- Órdenes de reabastecimiento (Enterprise)
CREATE TABLE restock_orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  quantity INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending', -- 'pending', 'ordered', 'received', 'cancelled'
  -- Proveedor (si aplica)
  supplier_name TEXT,
  supplier_order_id TEXT,
  expected_delivery_date DATE,
  -- Costos
  unit_cost NUMERIC(10,2),
  total_cost NUMERIC(12,2),
  -- Metadata
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_restock_orders_client ON restock_orders(client_id, status);
CREATE INDEX idx_restock_orders_product ON restock_orders(product_id);

-- Stock por ubicación (Enterprise - multi-warehouse)
CREATE TABLE warehouse_locations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  code TEXT NOT NULL, -- ej: 'WH-01', 'STORE-CAPITAL'
  address TEXT,
  is_default BOOLEAN NOT NULL DEFAULT false,
  active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(client_id, code)
);

CREATE INDEX idx_warehouse_locations_client ON warehouse_locations(client_id);

CREATE TABLE warehouse_stock (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  location_id UUID NOT NULL REFERENCES warehouse_locations(id) ON DELETE CASCADE,
  quantity INTEGER NOT NULL DEFAULT 0,
  reserved INTEGER NOT NULL DEFAULT 0, -- unidades reservadas
  available INTEGER GENERATED ALWAYS AS (quantity - reserved) STORED,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(client_id, product_id, location_id)
);

CREATE INDEX idx_warehouse_stock_client_location ON warehouse_stock(client_id, location_id);
CREATE INDEX idx_warehouse_stock_product ON warehouse_stock(product_id);
```

#### Funciones RPC para Operaciones Atómicas

```sql
-- Decrementar stock (venta)
CREATE OR REPLACE FUNCTION decrement_product_stock(
  p_client_id UUID,
  p_product_id UUID,
  p_quantity INTEGER,
  p_order_id UUID DEFAULT NULL,
  p_user_id UUID DEFAULT NULL
) RETURNS BOOLEAN AS $$
DECLARE
  v_current_stock INTEGER;
  v_new_stock INTEGER;
BEGIN
  -- Lock row para evitar race conditions
  SELECT stock INTO v_current_stock
  FROM products
  WHERE id = p_product_id AND client_id = p_client_id
  FOR UPDATE;

  IF v_current_stock IS NULL THEN
    RAISE EXCEPTION 'Product not found';
  END IF;

  IF v_current_stock < p_quantity THEN
    RAISE EXCEPTION 'Insufficient stock';
  END IF;

  v_new_stock := v_current_stock - p_quantity;

  -- Actualizar stock
  UPDATE products
  SET stock = v_new_stock, updated_at = NOW()
  WHERE id = p_product_id AND client_id = p_client_id;

  -- Registrar movimiento
  INSERT INTO stock_movements (
    client_id, product_id, movement_type, quantity,
    stock_before, stock_after, order_id, user_id
  ) VALUES (
    p_client_id, p_product_id, 'sale', -p_quantity,
    v_current_stock, v_new_stock, p_order_id, p_user_id
  );

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- Reservar stock temporalmente
CREATE OR REPLACE FUNCTION reserve_product_stock(
  p_client_id UUID,
  p_product_id UUID,
  p_quantity INTEGER,
  p_session_id TEXT,
  p_user_id UUID DEFAULT NULL,
  p_ttl_minutes INTEGER DEFAULT 15
) RETURNS UUID AS $$
DECLARE
  v_current_stock INTEGER;
  v_available INTEGER;
  v_reservation_id UUID;
  v_expires_at TIMESTAMPTZ;
BEGIN
  v_expires_at := NOW() + (p_ttl_minutes || ' minutes')::INTERVAL;

  -- Calcular stock disponible (stock - reservas activas)
  SELECT stock INTO v_current_stock
  FROM products
  WHERE id = p_product_id AND client_id = p_client_id
  FOR UPDATE;

  SELECT COALESCE(SUM(quantity), 0) INTO v_available
  FROM stock_reservations
  WHERE product_id = p_product_id 
    AND client_id = p_client_id
    AND NOT released
    AND expires_at > NOW();

  v_available := v_current_stock - v_available;

  IF v_available < p_quantity THEN
    RAISE EXCEPTION 'Insufficient available stock';
  END IF;

  -- Crear reserva
  INSERT INTO stock_reservations (
    client_id, product_id, quantity, session_id, user_id, expires_at
  ) VALUES (
    p_client_id, p_product_id, p_quantity, p_session_id, p_user_id, v_expires_at
  ) RETURNING id INTO v_reservation_id;

  -- Registrar movimiento
  INSERT INTO stock_movements (
    client_id, product_id, movement_type, quantity,
    stock_before, stock_after, user_id, reason
  ) VALUES (
    p_client_id, p_product_id, 'reservation', -p_quantity,
    v_current_stock, v_current_stock, p_user_id, 'Checkout reservation'
  );

  RETURN v_reservation_id;
END;
$$ LANGUAGE plpgsql;

-- Liberar reserva
CREATE OR REPLACE FUNCTION release_stock_reservation(p_reservation_id UUID) RETURNS BOOLEAN AS $$
DECLARE
  v_reservation RECORD;
BEGIN
  SELECT * INTO v_reservation
  FROM stock_reservations
  WHERE id = p_reservation_id AND NOT released
  FOR UPDATE;

  IF v_reservation IS NULL THEN
    RETURN FALSE; -- Ya liberada o no existe
  END IF;

  -- Marcar como liberada
  UPDATE stock_reservations
  SET released = true, released_at = NOW()
  WHERE id = p_reservation_id;

  -- Registrar movimiento
  INSERT INTO stock_movements (
    client_id, product_id, movement_type, quantity,
    stock_before, stock_after, reason
  ) VALUES (
    v_reservation.client_id, v_reservation.product_id, 'reservation_release', v_reservation.quantity,
    (SELECT stock FROM products WHERE id = v_reservation.product_id),
    (SELECT stock FROM products WHERE id = v_reservation.product_id),
    'Reservation expired or cancelled'
  );

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql;
```

### 2.3. Backend API (NestJS)

#### Módulo y Estructura

```
src/inventory/
├── inventory.module.ts
├── inventory.controller.ts           # 15 endpoints
├── inventory.service.ts              # CRUD + lógica de alertas
├── inventory-alerts.service.ts       # Generación y notificación de alertas
├── inventory-worker.service.ts       # Cron jobs (alertas, cleanup)
├── dto/
│   ├── inventory-settings.dto.ts
│   ├── stock-movement.dto.ts
│   ├── restock-order.dto.ts
│   └── warehouse.dto.ts
└── __tests__/
    └── inventory.service.spec.ts
```

#### Endpoints API

| Método | Ruta | Plan | Descripción |
|--------|------|------|-------------|
| GET | `/inventory/settings` | Starter | Configuración de alertas y umbrales |
| PUT | `/inventory/settings/:productId` | Starter | Actualizar umbrales de un producto |
| GET | `/inventory/movements` | Starter | Historial de movimientos (paginado) |
| POST | `/inventory/movements/adjustment` | Starter | Ajuste manual de stock (admin) |
| GET | `/inventory/alerts` | Starter | Alertas activas |
| PATCH | `/inventory/alerts/:id/dismiss` | Starter | Descartar alerta |
| POST | `/inventory/reserve` | Growth+ | Reservar stock durante checkout |
| POST | `/inventory/release/:reservationId` | Growth+ | Liberar reserva |
| GET | `/inventory/projections` | Growth+ | Proyección de agotamiento |
| GET | `/inventory/restock-suggestions` | Growth+ | Sugerencias de reabastecimiento |
| POST | `/inventory/restock-orders` | Enterprise | Crear orden de reabastecimiento |
| GET | `/inventory/restock-orders` | Enterprise | Listar órdenes de restock |
| PATCH | `/inventory/restock-orders/:id/receive` | Enterprise | Marcar como recibida |
| GET | `/inventory/warehouses` | Enterprise | Listar ubicaciones (multi-warehouse) |
| GET | `/inventory/warehouses/:id/stock` | Enterprise | Stock por ubicación |

#### Worker Service

```typescript
@Injectable()
export class InventoryWorkerService {
  // Cron: todos los días a las 9:00 AM
  @Cron('0 9 * * *')
  async checkLowStockAlerts() {
    const clients = await this.getActiveClients();
    
    for (const client of clients) {
      const products = await this.getProductsWithSettings(client.id);
      
      for (const product of products) {
        const { stock } = product;
        const { low_stock_threshold, reorder_point, alerts_enabled } = product.inventory_settings;
        
        if (!alerts_enabled) continue;
        
        // Alerta de stock bajo
        if (stock <= low_stock_threshold && stock > 0) {
          await this.createAlert(client.id, product.id, 'low_stock', stock, low_stock_threshold);
        }
        
        // Alerta de sin stock
        if (stock === 0) {
          await this.createAlert(client.id, product.id, 'out_of_stock', stock, 0);
        }
        
        // Punto de reorden (Enterprise con auto-reorder)
        if (stock <= reorder_point && product.auto_reorder_enabled) {
          await this.createRestockOrder(client.id, product.id);
        }
      }
      
      // Enviar email resumen de alertas
      await this.sendAlertsSummaryEmail(client.id);
    }
  }
  
  // Cron: cada 5 minutos
  @Cron('*/5 * * * *')
  async releaseExpiredReservations() {
    // Buscar reservas vencidas (expires_at < NOW() AND NOT released)
    const expired = await this.dbService.query(`
      SELECT id FROM stock_reservations
      WHERE expires_at < NOW() AND NOT released
    `);
    
    for (const reservation of expired) {
      await this.dbService.query(`SELECT release_stock_reservation($1)`, [reservation.id]);
    }
  }
}
```

### 2.4. Frontend Web (Tienda - Admin Dashboard)

#### Componentes Nuevos

```
src/components/inventory/
├── InventorySettings/
│   ├── index.jsx                    # Form para configurar umbrales
│   └── style.jsx
├── StockMovements/
│   ├── index.jsx                    # Tabla de movimientos + filtros
│   └── style.jsx
├── InventoryAlerts/
│   ├── index.jsx                    # Lista de alertas activas
│   ├── AlertCard.jsx
│   └── style.jsx
├── RestockOrders/                   # Enterprise
│   ├── index.jsx
│   └── style.jsx
└── WarehouseManager/                # Enterprise
    ├── index.jsx
    └── style.jsx
```

#### Nueva Página: `/admin/inventory`

```jsx
// src/pages/AdminDashboard/InventoryView.jsx
export function InventoryView() {
  const [activeTab, setActiveTab] = useState('overview'); // overview | alerts | movements | restock
  const { alerts, movements, settings, loading } = useInventory();

  return (
    <Container>
      <Header>
        <Title>Gestión de Inventario</Title>
        <Tabs>
          <Tab active={activeTab === 'overview'} onClick={() => setActiveTab('overview')}>
            Resumen
          </Tab>
          <Tab active={activeTab === 'alerts'} onClick={() => setActiveTab('alerts')}>
            Alertas {alerts.length > 0 && <Badge>{alerts.length}</Badge>}
          </Tab>
          <Tab active={activeTab === 'movements'} onClick={() => setActiveTab('movements')}>
            Movimientos
          </Tab>
          {plan === 'enterprise' && (
            <Tab active={activeTab === 'restock'} onClick={() => setActiveTab('restock')}>
              Reabastecimiento
            </Tab>
          )}
        </Tabs>
      </Header>

      {activeTab === 'overview' && (
        <>
          <StatsGrid>
            <StatCard>
              <Label>Productos con stock bajo</Label>
              <Value>{stats.lowStockCount}</Value>
            </StatCard>
            <StatCard>
              <Label>Sin stock</Label>
              <Value danger>{stats.outOfStockCount}</Value>
            </StatCard>
            <StatCard>
              <Label>Valor total inventario</Label>
              <Value>${stats.totalInventoryValue}</Value>
            </StatCard>
          </StatsGrid>
          
          <InventorySettings products={products} onUpdate={handleUpdateSettings} />
        </>
      )}

      {activeTab === 'alerts' && <InventoryAlerts alerts={alerts} onDismiss={handleDismiss} />}
      {activeTab === 'movements' && <StockMovements movements={movements} />}
      {activeTab === 'restock' && plan === 'enterprise' && <RestockOrders />}
    </Container>
  );
}
```

#### Integración en Checkout (Stock Reservations)

```javascript
// src/hooks/useCheckout.js (modificar)
const createPreference = async () => {
  try {
    // 1. Reservar stock antes de crear preferencia MP
    const reservations = await Promise.all(
      cart.items.map(item => 
        inventoryService.reserveStock({
          product_id: item.product.id,
          quantity: item.quantity,
          session_id: cartSessionId,
        })
      )
    );
    
    // 2. Crear preferencia MP con reservation_ids
    const preference = await checkoutService.createPreference({
      items: cart.items,
      reservation_ids: reservations.map(r => r.id),
      // ...
    });
    
    return preference;
  } catch (err) {
    // Si falla, liberar reservas
    if (reservations) {
      await Promise.all(reservations.map(r => inventoryService.releaseReservation(r.id)));
    }
    throw err;
  }
};
```

### 2.5. Super Admin Dashboard

#### Vista: `/dashboard/inventory-overview`

**Funcionalidad:**
- Ver alertas de stock bajo de todas las tiendas
- Identificar tiendas con alto % de productos sin stock (riesgo de ventas perdidas)
- Métricas agregadas: tasa de quiebre promedio, valor de inventario total

**Endpoint API:**
```
GET /admin/inventory/cross-tenant/alerts
GET /admin/inventory/cross-tenant/stats
```

### 2.6. Plan de Implementación (Fases)

#### Fase 1: Fundamentos (Sprint 1)
- [ ] Migración: tablas `inventory_settings`, `stock_movements`, `inventory_alerts`
- [ ] Backend: `InventoryModule` + 8 endpoints básicos
- [ ] RPC functions: decrement, reserve, release
- [ ] Feature catalog: `commerce.inventory_management` (starter)
- [ ] Tests: 20 unit tests

#### Fase 2: Alertas y Worker (Sprint 2)
- [ ] Worker: cron `checkLowStockAlerts` + `releaseExpiredReservations`
- [ ] Email templates para alertas
- [ ] Backend: endpoints de alertas (list, dismiss)
- [ ] Tests: 8 unit tests

#### Fase 3: Frontend Tienda (Sprint 3)
- [ ] Componentes UI: settings, alerts, movements
- [ ] Página `/admin/inventory`
- [ ] Integración con checkout (reservas)
- [ ] Tests: 10 component tests

#### Fase 4: Reabastecimiento (Sprint 4 - Enterprise)
- [ ] Migración: tabla `restock_orders`
- [ ] Backend: endpoints restock + suggestions
- [ ] Frontend: componente `RestockOrders`
- [ ] Tests: 5 unit tests

#### Fase 5: Multi-Warehouse (Sprint 5 - Enterprise)
- [ ] Migración: tablas `warehouse_locations`, `warehouse_stock`
- [ ] Backend: endpoints warehouses + stock por ubicación
- [ ] Frontend: componente `WarehouseManager`
- [ ] Tests: 8 unit tests

#### Fase 6: Super Admin (Sprint 6)
- [ ] Backend: endpoints cross-tenant
- [ ] Admin Dashboard: `InventoryOverviewView`
- [ ] Tests: 5 integration tests

### 2.7. Estimación de Esfuerzo

| Fase | Backend | Frontend Web | Admin | Testing | Total |
|------|---------|--------------|-------|---------|-------|
| Fase 1 | 3d | - | - | 1d | 4d |
| Fase 2 | 2d | - | - | 0.5d | 2.5d |
| Fase 3 | 1d | 4d | - | 1d | 6d |
| Fase 4 | 2d | 2d | - | 0.5d | 4.5d |
| Fase 5 | 2d | 2d | - | 1d | 5d |
| Fase 6 | 1d | - | 2d | 0.5d | 3.5d |
| **Total** | **11d** | **8d** | **2d** | **4.5d** | **25.5d (~5 sprints)** |

---

## 3. Product Variants

### 3.1. Análisis de Requisitos

**Objetivo:** Permitir productos con múltiples variaciones (talla, color, material) manteniendo SKU único por combinación y sincronización de stock.

**Casos de Uso:**
- Remera: variaciones por talla (S, M, L, XL) y color (Blanco, Negro, Azul)
- Zapatillas: variaciones por talla (35-45) y color
- Notebook: variaciones por RAM (8GB, 16GB) y SSD (256GB, 512GB, 1TB)

**Requisitos Clave:**
- **SKU único por variante** (ej: `REM-001-S-BLK`, `REM-001-M-BLK`)
- **Stock independiente** por variante
- **Precio puede variar** por variante (ej: +$500 por RAM 16GB)
- **Imágenes por variante** (opcional)
- **Producto padre** (master) agrupa todas las variantes
- **Selector inteligente** en frontend (deshabilitado si sin stock)
- **Sincronización:** si se borra producto padre → borrar variantes

**Restricciones:**
- Máximo 3 atributos por producto (ej: talla + color + material)
- Máximo 50 combinaciones por producto padre
- Plan Starter: 0 variantes (productos simples only)
- Plan Growth: hasta 100 variantes totales en catálogo
- Plan Enterprise: ilimitadas

### 3.2. Diseño de Base de Datos

#### Nuevas Tablas (Backend DB)

```sql
-- Conceptualmente, products se convierte en "producto padre" cuando has_variants = true
ALTER TABLE products ADD COLUMN has_variants BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE products ADD COLUMN is_variant BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE products ADD COLUMN parent_product_id UUID REFERENCES products(id) ON DELETE CASCADE;

CREATE INDEX idx_products_parent ON products(parent_product_id) WHERE parent_product_id IS NOT NULL;
CREATE INDEX idx_products_has_variants ON products(client_id, has_variants);

-- Atributos de variación (ej: 'Talla', 'Color')
CREATE TABLE variant_attributes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  parent_product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  attribute_name TEXT NOT NULL, -- 'Talla', 'Color', 'Capacidad', etc
  attribute_order INTEGER NOT NULL DEFAULT 0, -- orden de display (1=primero)
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(client_id, parent_product_id, attribute_name)
);

CREATE INDEX idx_variant_attributes_parent ON variant_attributes(parent_product_id);

-- Valores de atributos (ej: 'S', 'M', 'L' para atributo 'Talla')
CREATE TABLE variant_attribute_values (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  attribute_id UUID NOT NULL REFERENCES variant_attributes(id) ON DELETE CASCADE,
  value TEXT NOT NULL, -- 'S', 'Rojo', '256GB', etc
  sort_order INTEGER NOT NULL DEFAULT 0,
  -- Precio/stock adicional (opcional)
  price_adjustment NUMERIC(10,2) DEFAULT 0, -- +/- sobre precio base
  -- Metadata
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(attribute_id, value)
);

CREATE INDEX idx_variant_attribute_values_attribute ON variant_attribute_values(attribute_id);

-- Mapeo de variante → valores (M:N)
CREATE TABLE product_variant_values (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  attribute_value_id UUID NOT NULL REFERENCES variant_attribute_values(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(product_id, attribute_value_id)
);

CREATE INDEX idx_product_variant_values_product ON product_variant_values(product_id);
CREATE INDEX idx_product_variant_values_attribute_value ON product_variant_values(attribute_value_id);

-- Vista para facilitar queries (JOIN de producto variante con sus atributos)
CREATE VIEW products_with_variants AS
SELECT 
  p.id AS variant_id,
  p.parent_product_id,
  pp.name AS parent_name,
  p.name AS variant_name,
  p.sku AS variant_sku,
  p.price AS variant_price,
  p.stock AS variant_stock,
  p.imageUrl AS variant_image,
  json_agg(
    json_build_object(
      'attribute_name', va.attribute_name,
      'value', vav.value,
      'price_adjustment', vav.price_adjustment
    )
  ) AS variant_attributes
FROM products p
INNER JOIN products pp ON p.parent_product_id = pp.id
INNER JOIN product_variant_values pvv ON pvv.product_id = p.id
INNER JOIN variant_attribute_values vav ON pvv.attribute_value_id = vav.id
INNER JOIN variant_attributes va ON vav.attribute_id = va.id
WHERE p.is_variant = true
GROUP BY p.id, pp.id;
```

#### Constraints y Validaciones

```sql
-- Un producto NO puede ser padre Y variante al mismo tiempo
ALTER TABLE products ADD CONSTRAINT chk_not_both_parent_and_variant 
  CHECK (NOT (has_variants = true AND is_variant = true));

-- Si is_variant=true, parent_product_id NOT NULL
ALTER TABLE products ADD CONSTRAINT chk_variant_has_parent 
  CHECK (NOT is_variant OR parent_product_id IS NOT NULL);

-- Límite de atributos (máximo 3 por producto padre)
CREATE OR REPLACE FUNCTION check_max_attributes() RETURNS TRIGGER AS $$
BEGIN
  IF (SELECT COUNT(*) FROM variant_attributes WHERE parent_product_id = NEW.parent_product_id) > 3 THEN
    RAISE EXCEPTION 'Maximum 3 variant attributes per product';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_max_attributes
  BEFORE INSERT ON variant_attributes
  FOR EACH ROW
  EXECUTE FUNCTION check_max_attributes();
```

### 3.3. Backend API (NestJS)

#### Módulo y Estructura

```
src/product-variants/
├── product-variants.module.ts
├── product-variants.controller.ts       # 12 endpoints
├── product-variants.service.ts          # Lógica de CRUD variantes
├── dto/
│   ├── create-variant-product.dto.ts
│   ├── update-variant.dto.ts
│   ├── variant-attribute.dto.ts
│   └── bulk-create-variants.dto.ts
└── __tests__/
    └── product-variants.service.spec.ts
```

#### Endpoints API

| Método | Ruta | Plan | Descripción |
|--------|------|------|-------------|
| POST | `/products/:id/variants/setup` | Growth+ | Inicializar producto como padre + atributos |
| GET | `/products/:id/variants` | Growth+ | Listar variantes de un producto |
| POST | `/products/:id/variants` | Growth+ | Crear una variante |
| POST | `/products/:id/variants/bulk` | Growth+ | Crear múltiples variantes (matriz) |
| PUT | `/products/:parentId/variants/:variantId` | Growth+ | Actualizar variante (precio, stock, SKU) |
| DELETE | `/products/:parentId/variants/:variantId` | Growth+ | Eliminar variante |
| GET | `/products/:id/variant-attributes` | Growth+ | Atributos + valores de un producto padre |
| POST | `/products/:id/variant-attributes` | Growth+ | Agregar atributo (ej: 'Material') |
| POST | `/variant-attributes/:id/values` | Growth+ | Agregar valor a atributo (ej: 'Algodón') |
| DELETE | `/variant-attributes/:id` | Growth+ | Eliminar atributo (y sus valores) |
| GET | `/products/variant/:sku` | Starter+ | Buscar variante por SKU |
| GET | `/products/:id/available-variants` | Growth+ | Variantes con stock > 0 (público) |

#### Ejemplo de Setup (POST `/products/:id/variants/setup`)

```typescript
// DTO
class SetupVariantsDto {
  attributes: {
    name: string; // 'Talla', 'Color'
    values: { value: string; price_adjustment?: number }[]; // [{ value: 'S' }, { value: 'M' }, ...]
  }[];
}

// Service
async setupVariants(clientId: string, productId: string, dto: SetupVariantsDto) {
  // 1. Marcar producto como padre
  await this.db.query(`
    UPDATE products 
    SET has_variants = true 
    WHERE id = $1 AND client_id = $2
  `, [productId, clientId]);

  // 2. Crear atributos + valores
  for (const [index, attr] of dto.attributes.entries()) {
    const attrId = await this.createAttribute(clientId, productId, attr.name, index);
    
    for (const [sortOrder, val] of attr.values.entries()) {
      await this.createAttributeValue(attrId, val.value, sortOrder, val.price_adjustment || 0);
    }
  }

  return { success: true };
}
```

#### Ejemplo de Bulk Create (POST `/products/:id/variants/bulk`)

```typescript
// DTO
class BulkCreateVariantsDto {
  // Matriz de combinaciones: [{ Talla: 'S', Color: 'Rojo', sku: 'REM-001-S-RED', price: 1500, stock: 10 }, ...]
  variants: {
    attributes: Record<string, string>; // { 'Talla': 'S', 'Color': 'Rojo' }
    sku: string;
    price?: number; // opcional, hereda del padre
    stock: number;
    imageUrl?: string;
  }[];
}

// Service
async bulkCreateVariants(clientId: string, parentProductId: string, dto: BulkCreateVariantsDto) {
  const parent = await this.getProductById(clientId, parentProductId);
  
  if (!parent.has_variants) {
    throw new BadRequestException('Product is not set up for variants');
  }

  const createdVariants = [];

  for (const variant of dto.variants) {
    // 1. Crear producto variante
    const variantProduct = await this.db.query(`
      INSERT INTO products (
        client_id, parent_product_id, is_variant, 
        name, sku, price, stock, imageUrl, active
      ) VALUES ($1, $2, true, $3, $4, $5, $6, $7, true)
      RETURNING id
    `, [
      clientId,
      parentProductId,
      this.buildVariantName(parent.name, variant.attributes), // ej: 'Remera - S / Rojo'
      variant.sku,
      variant.price || parent.price,
      variant.stock,
      variant.imageUrl || parent.imageUrl,
    ]);

    const variantId = variantProduct.rows[0].id;

    // 2. Vincular con attribute_values
    for (const [attrName, value] of Object.entries(variant.attributes)) {
      const attributeValueId = await this.getAttributeValueId(clientId, parentProductId, attrName, value);
      
      await this.db.query(`
        INSERT INTO product_variant_values (product_id, attribute_value_id)
        VALUES ($1, $2)
      `, [variantId, attributeValueId]);
    }

    createdVariants.push({ id: variantId, sku: variant.sku });
  }

  return { created: createdVariants.length, variants: createdVariants };
}
```

### 3.4. Frontend Web (Tienda)

#### Selector de Variantes en ProductPage

```jsx
// src/components/products/VariantSelector/index.jsx
export function VariantSelector({ product, variants, selectedVariant, onVariantChange }) {
  // Agrupar atributos por nombre
  const attributesMap = useMemo(() => {
    const map = {};
    variants.forEach(v => {
      v.variant_attributes.forEach(attr => {
        if (!map[attr.attribute_name]) {
          map[attr.attribute_name] = new Set();
        }
        map[attr.attribute_name].add(attr.value);
      });
    });
    
    return Object.entries(map).map(([name, values]) => ({
      name,
      values: Array.from(values),
    }));
  }, [variants]);

  const [selectedAttributes, setSelectedAttributes] = useState({});

  const handleSelectAttribute = (attrName, value) => {
    const newSelection = { ...selectedAttributes, [attrName]: value };
    setSelectedAttributes(newSelection);

    // Buscar variante que matchee la combinación
    const matchingVariant = variants.find(v => 
      v.variant_attributes.every(attr => 
        newSelection[attr.attribute_name] === attr.value
      )
    );

    if (matchingVariant) {
      onVariantChange(matchingVariant);
    }
  };

  const isValueAvailable = (attrName, value) => {
    // Verificar si existe una variante con esta combinación + stock > 0
    const testSelection = { ...selectedAttributes, [attrName]: value };
    
    return variants.some(v => 
      v.variant_attributes.every(attr => 
        !testSelection[attr.attribute_name] || testSelection[attr.attribute_name] === attr.value
      ) && v.variant_stock > 0
    );
  };

  return (
    <Container>
      {attributesMap.map(attribute => (
        <AttributeGroup key={attribute.name}>
          <AttributeName>{attribute.name}</AttributeName>
          <ValuesGrid>
            {attribute.values.map(value => {
              const isSelected = selectedAttributes[attribute.name] === value;
              const isAvailable = isValueAvailable(attribute.name, value);
              
              return (
                <ValueButton
                  key={value}
                  selected={isSelected}
                  disabled={!isAvailable}
                  onClick={() => handleSelectAttribute(attribute.name, value)}
                >
                  {value}
                  {!isAvailable && <OutOfStockBadge>Sin stock</OutOfStockBadge>}
                </ValueButton>
              );
            })}
          </ValuesGrid>
        </AttributeGroup>
      ))}

      {selectedVariant && (
        <SelectedInfo>
          <Price>${selectedVariant.variant_price}</Price>
          <Stock>{selectedVariant.variant_stock} disponibles</Stock>
          <SKU>SKU: {selectedVariant.variant_sku}</SKU>
        </SelectedInfo>
      )}
    </Container>
  );
}
```

#### ProductPage Modificado

```jsx
// src/pages/ProductPage/index.jsx (modificar)
export function ProductPage() {
  const { productId } = useParams();
  const { product, variants, loading } = useProduct(productId);
  const [selectedVariant, setSelectedVariant] = useState(null);

  const displayProduct = selectedVariant || product;

  return (
    <Container>
      <ImageGallery images={[displayProduct.imageUrl]} />
      
      <ProductInfo>
        <Title>{product.name}</Title>
        <Price>${displayProduct.price}</Price>
        
        {product.has_variants && variants.length > 0 && (
          <VariantSelector
            product={product}
            variants={variants}
            selectedVariant={selectedVariant}
            onVariantChange={setSelectedVariant}
          />
        )}

        <AddToCartButton
          disabled={product.has_variants && !selectedVariant}
          onClick={() => handleAddToCart(displayProduct)}
        >
          {product.has_variants && !selectedVariant 
            ? 'Selecciona una opción' 
            : 'Agregar al carrito'}
        </AddToCartButton>
      </ProductInfo>
    </Container>
  );
}
```

### 3.5. Frontend Admin (Gestión de Variantes)

#### Wizard de Creación en Admin Dashboard

```jsx
// src/components/admin/ProductVariantsWizard/index.jsx
export function ProductVariantsWizard({ product, onComplete }) {
  const [step, setStep] = useState(1);
  const [attributes, setAttributes] = useState([
    { name: 'Talla', values: ['S', 'M', 'L', 'XL'] },
  ]);
  const [generatedMatrix, setGeneratedMatrix] = useState([]);

  // Step 1: Definir atributos y valores
  const handleAddAttribute = () => {
    setAttributes([...attributes, { name: '', values: [] }]);
  };

  // Step 2: Generar matriz de combinaciones
  const generateCombinations = () => {
    const combinations = cartesianProduct(attributes.map(a => a.values));
    
    const matrix = combinations.map((combo, idx) => ({
      attributes: attributes.reduce((acc, attr, i) => {
        acc[attr.name] = combo[i];
        return acc;
      }, {}),
      sku: `${product.sku}-${idx + 1}`,
      price: product.price,
      stock: 0,
    }));

    setGeneratedMatrix(matrix);
    setStep(2);
  };

  // Step 3: Editar SKU/precio/stock de cada variante
  const handleUpdateVariant = (index, field, value) => {
    const updated = [...generatedMatrix];
    updated[index][field] = value;
    setGeneratedMatrix(updated);
  };

  // Step 4: Guardar
  const handleSave = async () => {
    try {
      // 1. Setup atributos
      await productVariantsService.setupVariants(product.id, { attributes });
      
      // 2. Bulk create variantes
      await productVariantsService.bulkCreateVariants(product.id, { variants: generatedMatrix });
      
      onComplete();
    } catch (err) {
      console.error(err);
    }
  };

  return (
    <WizardContainer>
      {step === 1 && (
        <>
          <Title>Paso 1: Definir Atributos</Title>
          {attributes.map((attr, idx) => (
            <AttributeRow key={idx}>
              <Input
                placeholder="Nombre (ej: Talla)"
                value={attr.name}
                onChange={e => {
                  const updated = [...attributes];
                  updated[idx].name = e.target.value;
                  setAttributes(updated);
                }}
              />
              <TagsInput
                placeholder="Valores (ej: S, M, L)"
                values={attr.values}
                onChange={values => {
                  const updated = [...attributes];
                  updated[idx].values = values;
                  setAttributes(updated);
                }}
              />
            </AttributeRow>
          ))}
          <Button onClick={handleAddAttribute}>+ Agregar Atributo</Button>
          <Button primary onClick={generateCombinations}>
            Generar Combinaciones ({cartesianProduct(attributes.map(a => a.values)).length})
          </Button>
        </>
      )}

      {step === 2 && (
        <>
          <Title>Paso 2: Editar Variantes</Title>
          <Table>
            <thead>
              <tr>
                <th>Combinación</th>
                <th>SKU</th>
                <th>Precio</th>
                <th>Stock</th>
              </tr>
            </thead>
            <tbody>
              {generatedMatrix.map((variant, idx) => (
                <tr key={idx}>
                  <td>{Object.values(variant.attributes).join(' / ')}</td>
                  <td>
                    <Input
                      value={variant.sku}
                      onChange={e => handleUpdateVariant(idx, 'sku', e.target.value)}
                    />
                  </td>
                  <td>
                    <Input
                      type="number"
                      value={variant.price}
                      onChange={e => handleUpdateVariant(idx, 'price', parseFloat(e.target.value))}
                    />
                  </td>
                  <td>
                    <Input
                      type="number"
                      value={variant.stock}
                      onChange={e => handleUpdateVariant(idx, 'stock', parseInt(e.target.value))}
                    />
                  </td>
                </tr>
              ))}
            </tbody>
          </Table>
          <Button onClick={() => setStep(1)}>Volver</Button>
          <Button primary onClick={handleSave}>Crear Variantes</Button>
        </>
      )}
    </WizardContainer>
  );
}
```

### 3.6. Super Admin Dashboard

**Vista:** `/dashboard/variants-usage`

**Funcionalidad:**
- Métricas de uso de variantes por tienda (cuántas tienen activadas, cuántas combinaciones promedio)
- Top tiendas con más variantes
- Alertar si una tienda Growth está cerca del límite (100 variantes)

**Endpoint API:**
```
GET /admin/product-variants/cross-tenant/stats
```

### 3.7. Plan de Implementación (Fases)

#### Fase 1: DB y Backend Core (Sprint 1)
- [ ] Migración: columnas en `products` (has_variants, is_variant, parent_product_id)
- [ ] Migración: tablas `variant_attributes`, `variant_attribute_values`, `product_variant_values`
- [ ] Backend: `ProductVariantsModule` + 6 endpoints básicos (setup, create, list, update, delete)
- [ ] Feature catalog: `commerce.product_variants` (growth+)
- [ ] Tests: 15 unit tests

#### Fase 2: Bulk Creation + Constraints (Sprint 2)
- [ ] Backend: endpoint bulk create + validaciones (max 3 atributos, max 50 combinaciones)
- [ ] Función cartesiana en service para generar combinaciones
- [ ] Plan limits: growth=100 variantes total, enterprise=unlimited
- [ ] Tests: 10 unit tests

#### Fase 3: Frontend Tienda (Sprint 3)
- [ ] Componente `VariantSelector` con lógica de disponibilidad
- [ ] `ProductPage` modificado para productos con variantes
- [ ] Hook `useProduct` con soporte de variantes
- [ ] Tests: 8 component tests

#### Fase 4: Admin Wizard (Sprint 4)
- [ ] Componente `ProductVariantsWizard` (2 pasos)
- [ ] Integración en `ProductsSection` del admin dashboard
- [ ] UI de edición inline de variantes existentes
- [ ] Tests: 5 component tests

#### Fase 5: Sincronización y Edge Cases (Sprint 5)
- [ ] Sincronización: borrar padre → cascade delete variantes
- [ ] Validación: no permitir agregar al carrito producto padre sin seleccionar variante
- [ ] Stock reservations compatible con variantes
- [ ] Tests: 10 integration tests

#### Fase 6: Super Admin (Sprint 6)
- [ ] Backend: endpoints cross-tenant stats
- [ ] Admin Dashboard: `VariantsUsageView`
- [ ] Tests: 3 integration tests

### 3.8. Estimación de Esfuerzo

| Fase | Backend | Frontend Web | Admin | Testing | Total |
|------|---------|--------------|-------|---------|-------|
| Fase 1 | 3d | - | - | 1d | 4d |
| Fase 2 | 2d | - | - | 1d | 3d |
| Fase 3 | 0.5d | 4d | - | 1d | 5.5d |
| Fase 4 | - | - | 4d | 0.5d | 4.5d |
| Fase 5 | 2d | 1d | - | 1d | 4d |
| Fase 6 | 1d | - | 2d | 0.5d | 3.5d |
| **Total** | **8.5d** | **5d** | **6d** | **5d** | **24.5d (~5 sprints)** |

---

## 4. Feature Gating por Plan

### Tabla de Features por Plan

| Feature | Starter | Growth | Enterprise |
|---------|---------|--------|------------|
| **Analytics Dashboard** | ❌ | ✅ Básico | ✅ Completo |
| - Sales Overview/Timeline | ❌ | ✅ | ✅ |
| - Top Products | ❌ | ✅ (Top 10) | ✅ (Top 50) |
| - Conversion Funnel | ❌ | ❌ | ✅ |
| - Customer Cohorts | ❌ | ❌ | ✅ |
| - Export CSV | ❌ | ✅ | ✅ |
| **Inventory Management** | ✅ Básico | ✅ Avanzado | ✅ Completo |
| - Alertas Stock Bajo | ✅ | ✅ | ✅ |
| - Historial Movimientos | ✅ (30 días) | ✅ (90 días) | ✅ (Ilimitado) |
| - Stock Reservations | ❌ | ✅ | ✅ |
| - Reabastecimiento Auto | ❌ | ❌ | ✅ |
| - Multi-Warehouse | ❌ | ❌ | ✅ |
| **Product Variants** | ❌ | ✅ Limited | ✅ Unlimited |
| - Max Variantes Totales | 0 | 100 | Ilimitado |
| - Max Atributos por Producto | 0 | 3 | 3 |
| - Max Combinaciones | 0 | 50 | 200 |

### Feature Catalog (agregar a `src/common/featureCatalog.ts`)

```typescript
// Analytics
{
  key: 'dashboard.analytics',
  name: 'Analytics Dashboard',
  description: 'Métricas de ventas, productos y conversión',
  eligiblePlans: ['growth', 'growth_annual', 'enterprise', 'enterprise_annual'],
  tier: 'growth',
  isActive: true,
  limits: {
    starter: { enabled: false },
    growth: { 
      enabled: true,
      max_top_products: 10,
      retention_days: 90,
      export_enabled: true,
    },
    enterprise: {
      enabled: true,
      max_top_products: 50,
      retention_days: 365,
      export_enabled: true,
      advanced_features: ['funnel', 'cohorts', 'clv'],
    },
  },
},

// Inventory
{
  key: 'commerce.inventory_management',
  name: 'Inventory Management',
  description: 'Gestión avanzada de inventario con alertas',
  eligiblePlans: ['starter', 'growth', 'growth_annual', 'enterprise', 'enterprise_annual'],
  tier: 'starter',
  isActive: true,
  limits: {
    starter: { 
      enabled: true,
      alerts_enabled: true,
      movements_retention_days: 30,
      reservations_enabled: false,
      auto_reorder_enabled: false,
      multi_warehouse_enabled: false,
    },
    growth: {
      enabled: true,
      alerts_enabled: true,
      movements_retention_days: 90,
      reservations_enabled: true,
      auto_reorder_enabled: false,
      multi_warehouse_enabled: false,
    },
    enterprise: {
      enabled: true,
      alerts_enabled: true,
      movements_retention_days: null, // ilimitado
      reservations_enabled: true,
      auto_reorder_enabled: true,
      multi_warehouse_enabled: true,
    },
  },
},

// Variants
{
  key: 'commerce.product_variants',
  name: 'Product Variants',
  description: 'Productos con variaciones (talla, color, etc)',
  eligiblePlans: ['growth', 'growth_annual', 'enterprise', 'enterprise_annual'],
  tier: 'growth',
  isActive: true,
  limits: {
    starter: { 
      enabled: false,
      max_variants_total: 0,
    },
    growth: {
      enabled: true,
      max_variants_total: 100,
      max_attributes_per_product: 3,
      max_combinations_per_product: 50,
    },
    enterprise: {
      enabled: true,
      max_variants_total: null, // ilimitado
      max_attributes_per_product: 3,
      max_combinations_per_product: 200,
    },
  },
},
```

---

## 5. Super Admin Dashboard

### Nuevas Vistas Cross-Tenant

#### 5.1. Analytics Overview (`/dashboard/analytics-overview`)

**Métricas Agregadas:**
- Revenue total (todas las tiendas, últimos 30 días)
- Órdenes totales
- Ticket promedio general
- Conversión promedio
- Top 10 tiendas por revenue
- Top 10 tiendas por conversión
- Tiendas con bajo performance (< 1% conversión) — riesgo de churn

**Componentes:**
```
apps/admin/src/pages/AdminDashboard/
├── CrossTenantAnalyticsView.jsx
├── TopStoresTable.jsx
└── LowPerformanceAlert.jsx
```

**Endpoints:**
```typescript
GET /admin/analytics/cross-tenant/overview
  ?dateFrom=2026-01-13&dateTo=2026-02-13

Response:
{
  aggregated: {
    total_revenue: 1250000,
    total_orders: 3420,
    avg_order_value: 365.50,
    avg_conversion_rate: 2.8,
  },
  top_stores: [
    { client_id: '...', name: 'Tienda A', revenue: 85000, orders: 240, conversion: 4.2 },
    // ...
  ],
  low_performance: [
    { client_id: '...', name: 'Tienda Z', conversion: 0.8, orders: 5, last_order: '2026-01-20' },
    // ...
  ],
}
```

#### 5.2. Inventory Overview (`/dashboard/inventory-overview`)

**Métricas Agregadas:**
- Total de alertas activas (todas las tiendas)
- Top 10 tiendas con más alertas
- Tiendas con >20% productos sin stock (crítico)
- Valor total de inventario

**Endpoints:**
```typescript
GET /admin/inventory/cross-tenant/alerts
  ?status=pending&limit=50

GET /admin/inventory/cross-tenant/stats
```

#### 5.3. Variants Usage (`/dashboard/variants-usage`)

**Métricas:**
- Tiendas con variantes activadas
- Promedio de combinaciones por producto
- Top tiendas con más variantes
- Tiendas Growth cerca del límite (>90 variantes)

**Endpoints:**
```typescript
GET /admin/product-variants/cross-tenant/stats

Response:
{
  stores_with_variants: 42,
  total_variant_products: 1250,
  avg_combinations_per_product: 8.5,
  top_stores: [...],
  near_limit: [
    { client_id: '...', name: 'Tienda B', plan: 'growth', variants_count: 95, limit: 100 },
  ],
}
```

### 5.4. Navegación Actualizada

```jsx
// apps/admin/src/components/Sidebar/index.jsx
const navItems = [
  // ... secciones existentes
  {
    category: 'Insights',
    icon: FiBarChart2,
    items: [
      { label: 'Analytics Overview', path: '/dashboard/analytics-overview', superOnly: true },
      { label: 'Inventory Overview', path: '/dashboard/inventory-overview', superOnly: true },
      { label: 'Variants Usage', path: '/dashboard/variants-usage', superOnly: true },
    ],
  },
];
```

---

## 6. Orden de Implementación Sugerido

### Prioridad 1: Inventory Management (Crítico para Operaciones)
**Justificación:** 
- Impacta directamente en ventas (prevenir quiebres de stock)
- Menor complejidad técnica que Analytics y Variants
- Valor inmediato para tiendas activas
- Fundamento para Variants (stock por variante)

**Timeline:** 5 sprints (10 semanas)

### Prioridad 2: Product Variants (Diferenciador Competitivo)
**Justificación:**
- Feature muy demandado por clientes con indumentaria/calzado
- Aumenta catálogo efectivo sin esfuerzo de fotografía
- Requiere Inventory Management ya implementado (stock por variante)

**Timeline:** 5 sprints (10 semanas)

### Prioridad 3: Analytics Dashboard (Insights para Retención)
**Justificación:**
- Ayuda a clientes a tomar decisiones basadas en datos
- Reduce churn (clientes con analytics ven valor)
- Requiere datos históricos (beneficio crece con el tiempo)
- Puede empezar simple e iterar

**Timeline:** 4 sprints (8 semanas)

---

## 7. Arquitectura Transversal

### 7.1. Cache Strategy

**Redis Keys Pattern:**
```
analytics:{client_id}:sales:overview:{dateFrom}:{dateTo}  (TTL 15min)
analytics:{client_id}:products:top:{limit}:{dateFrom}:{dateTo}  (TTL 30min)
inventory:{client_id}:alerts:count  (TTL 5min)
inventory:{client_id}:projections:{product_id}  (TTL 1h)
variants:{client_id}:product:{product_id}:available  (TTL 10min)
```

### 7.2. Performance Considerations

**Analytics:**
- Pre-calcular métricas diarias (workers nocturnos)
- Vistas materializadas para queries complejas (opcional)
- Índices en columnas de fecha y client_id
- Limitar rango de fechas máximo (1 año)

**Inventory:**
- RPC functions para operaciones atómicas (stock decrement, reserve)
- Advisory locks en transacciones críticas
- Índices en product_id + client_id para movimientos

**Variants:**
- Eager loading de variantes al cargar producto padre
- Cache de matriz de disponibilidad (stock > 0)
- Límites estrictos (max 50/200 combinaciones)

### 7.3. Monitoring & Observability

**Key Metrics to Track:**
- Analytics: query duration (P95), cache hit rate, worker execution time
- Inventory: reservation expiry rate, alert generation time, stock update latency
- Variants: variant selector load time, matrix generation time

**Alertas Críticas:**
- Analytics worker failed > 3 runs consecutivos
- Inventory: >100 reservas expiradas sin liberar (leak)
- Variants: cliente crea >50 combinaciones sin plan Enterprise

---

## 8. Testing Strategy

### 8.1. Unit Tests (Target 80% Coverage)

**Analytics:**
- Service: agregación de ventas, cálculo de métricas, cohorts
- Worker: generación de datos diarios, cleanup de eventos

**Inventory:**
- Service: CRUD settings, generación de alertas, proyecciones
- RPC functions: decrement, reserve, release (mock DB)

**Variants:**
- Service: setup attributes, bulk create, cartesian product
- Validations: max attributes, max combinations

### 8.2. Integration Tests

**Analytics:**
- E2E: crear órdenes → ejecutar worker → verificar analytics_daily_sales
- Funnel tracking: page_view → product_view → add_to_cart → checkout_complete

**Inventory:**
- Stock workflow: checkout → reserve → payment → decrement (o release)
- Alert generation: producto bajo umbral → cron → alerta creada → email enviado

**Variants:**
- CRUD completo: setup → bulk create → update variant → delete variant
- Selector: todas las combinaciones navegables, solo con stock habilitadas

### 8.3. E2E Tests (Playwright)

**User Journeys:**
1. Admin crea producto con variantes → comprador selecciona variante → checkout → confirma orden
2. Admin recibe alerta de stock bajo → ajusta stock → alerta se resuelve
3. Comprador ve analytics de su tienda → exporta CSV → verifica datos

**Escenarios de Carga:**
- 100 usuarios simultáneos agregando al carrito (reservas)
- Worker nocturno con 1000 tiendas activas

---

## 📊 Resumen Ejecutivo

### Estimación Total de Esfuerzo

| Feature | Backend | Frontend Web | Admin | Testing | Total | Sprints |
|---------|---------|--------------|-------|---------|-------|---------|
| **Analytics** | 8d | 7d | 2d | 4d | **21d** | **4** |
| **Inventory** | 11d | 8d | 2d | 4.5d | **25.5d** | **5** |
| **Variants** | 8.5d | 5d | 6d | 5d | **24.5d** | **5** |
| **TOTAL** | **27.5d** | **20d** | **10d** | **13.5d** | **71d** | **14** |

**Timeline General:** 14 sprints (~28 semanas / 7 meses)

**Timeline Secuencial (Priorizado):**
1. Inventory: sprints 1-5 (10 semanas)
2. Variants: sprints 6-10 (10 semanas)
3. Analytics: sprints 11-14 (8 semanas)

**Timeline Paralelo (Team de 2):**
- 10 sprints (~20 semanas / 5 meses)

### Riesgos Identificados

| Riesgo | Probabilidad | Impacto | Mitigación |
|--------|--------------|---------|------------|
| Performance de workers nocturnos con 1000+ tiendas | Media | Alto | Pre-calcular solo clientes activos, batch processing |
| Complejidad del selector de variantes en frontend | Media | Medio | Prototipo temprano, user testing |
| Race conditions en stock reservations | Alta | Alto | RPC functions + advisory locks |
| Carga en DB por tracking de eventos | Media | Medio | TTL agresivo (90 días), índices optimizados |
| Límites de variantes no respetados | Baja | Medio | Validación server-side + client-side |

### Dependencias Externas

- **Redis:** para cache de métricas (Analytics)
- **Chart.js / Recharts:** para gráficos (Analytics frontend)
- **react-select / react-tags-input:** para wizard de variantes
- **Ninguna:** Inventory y Variants usan stack existente

---

## 📋 Checklist de Entrega por Feature

### Analytics Dashboard
- [ ] Migración: 4 tablas analytics + índices
- [ ] Backend: 12 endpoints + 3 workers
- [ ] Frontend Web: 4 componentes + hook
- [ ] Admin: 1 vista cross-tenant
- [ ] Tests: 40 unit + 10 integration
- [ ] Docs: runbook de workers, guía de métricas
- [ ] CI/CD: smoke tests post-deploy

### Inventory Management
- [ ] Migración: 6 tablas inventory + 3 RPC functions
- [ ] Backend: 15 endpoints + 2 workers
- [ ] Frontend Web: 5 componentes + integración checkout
- [ ] Admin: 1 vista cross-tenant
- [ ] Tests: 60 unit + 15 integration
- [ ] Docs: runbook de alertas, guía de reabastecimiento
- [ ] Email templates: alertas de stock

### Product Variants
- [ ] Migración: 3 tablas + constraints + vista
- [ ] Backend: 12 endpoints + validaciones
- [ ] Frontend Web: 2 componentes (selector + page)
- [ ] Admin: 1 wizard + gestión inline
- [ ] Tests: 50 unit + 15 integration
- [ ] Docs: guía de creación de variantes
- [ ] E2E: journey completo comprador

---

## 🎯 Métricas de Éxito (Post-Launch)

### Analytics Dashboard
- **Adopción:** >60% de clientes Growth/Enterprise acceden al menos 1x/semana
- **Engagement:** sesión promedio >3 min en Analytics
- **Exportaciones:** >100 CSV descargados en primer mes
- **Feedback:** NPS >8 en encuesta post-feature

### Inventory Management
- **Prevención:** reducción de 50% en quiebres de stock (órdenes canceladas por falta de inventario)
- **Alertas:** <5% de alertas desestimadas (alta relevancia)
- **Reservations:** 0 double-sells (mismo producto vendido 2 veces)
- **Reabastecimiento:** >80% de sugerencias aceptadas (Enterprise)

### Product Variants
- **Adopción:** >40% de clientes Growth activan variantes en primer mes
- **Catálogo:** aumento de 3x en SKUs promedio por tienda
- **Conversión:** +15% en add-to-cart en productos con variantes bien configuradas
- **Límites:** <1% de clientes Growth alcanzan límite de 100 variantes

---

**Fin del Plan de Implementación**
