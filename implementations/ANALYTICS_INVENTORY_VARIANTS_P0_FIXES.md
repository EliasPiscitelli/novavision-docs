# P0 — Critical Fixes antes de ejecutar Analytics/Inventory/Variants

**Fecha:** 2026-02-13  
**Propósito:** Resolver problemas operativos que romperían producción si se implementan las features tal cual están en el plan base  
**Prerequisito de:** `ANALYTICS_INVENTORY_VARIANTS_PLAN.md`

---

## ⚠️ Contexto

El plan original (`ANALYTICS_INVENTORY_VARIANTS_PLAN.md`) describe **qué** construir, pero asume un entorno ideal. En producción con **Railway multi-instancia, Supabase dual-DB y clientes reales**, hay 5 "time bombs" que debemos resolver ANTES de escribir código de features.

---

## 🔴 P0.1 — Distributed Locking para Cron/Workers

### Problema

**Síntoma:** Workers de NestJS con `@Cron()` se ejecutan **1 vez por instancia activa**. Si Railway escala a 2+ instancias:
- `calculateDailySales` corre 2 veces → doble upsert en `analytics_daily_sales`
- `checkLowStockAlerts` corre 2 veces → emails de alerta duplicados
- `releaseExpiredReservations` corre 2 veces → posible doble liberación

**Impacto:** Métricas infladas, spam de emails, race conditions en stock.

### Fix Obligatorio: Distributed Lock Layer

#### Nueva Tabla: `job_runs`

```sql
CREATE TABLE job_runs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_key TEXT NOT NULL, -- 'analytics:daily_sales', 'inventory:alerts', etc
  run_for_date DATE DEFAULT CURRENT_DATE, -- fecha del batch procesado
  status TEXT NOT NULL DEFAULT 'running', -- 'running', 'completed', 'failed'
  instance_id TEXT, -- identificador del pod/worker
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  finished_at TIMESTAMPTZ,
  error_message TEXT,
  rows_processed INTEGER DEFAULT 0,
  -- Lock: solo 1 job activo por (job_key, run_for_date)
  UNIQUE(job_key, run_for_date, status) WHERE status = 'running'
);

CREATE INDEX idx_job_runs_key_date ON job_runs(job_key, run_for_date DESC);
CREATE INDEX idx_job_runs_status ON job_runs(status, started_at);
```

#### Service: `DistributedLockService`

```typescript
// src/common/distributed-lock/distributed-lock.service.ts
import { Injectable, Logger } from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';
import { v4 as uuidv4 } from 'uuid';

@Injectable()
export class DistributedLockService {
  private readonly logger = new Logger(DistributedLockService.name);
  private readonly instanceId = uuidv4(); // único por instancia

  constructor(private readonly supabase: SupabaseService) {}

  /**
   * Intenta adquirir lock para un job.
   * @returns jobRunId si adquirido, null si otro worker ya lo tiene
   */
  async acquireLock(
    jobKey: string,
    runForDate: Date = new Date(),
  ): Promise<string | null> {
    try {
      const { data, error } = await this.supabase.adminClient
        .from('job_runs')
        .insert({
          job_key: jobKey,
          run_for_date: runForDate.toISOString().split('T')[0],
          status: 'running',
          instance_id: this.instanceId,
        })
        .select('id')
        .single();

      if (error) {
        // Unique constraint violation = otro worker ya corriendo
        if (error.code === '23505') {
          this.logger.debug(`Lock already held for ${jobKey} on ${runForDate}`);
          return null;
        }
        throw error;
      }

      this.logger.log(`Lock acquired: ${jobKey} by ${this.instanceId}`);
      return data.id;
    } catch (err) {
      this.logger.error(`Failed to acquire lock for ${jobKey}:`, err);
      return null;
    }
  }

  /**
   * Libera lock marcando como completado
   */
  async releaseLock(
    jobRunId: string,
    rowsProcessed: number = 0,
  ): Promise<void> {
    await this.supabase.adminClient
      .from('job_runs')
      .update({
        status: 'completed',
        finished_at: new Date().toISOString(),
        rows_processed: rowsProcessed,
      })
      .eq('id', jobRunId);

    this.logger.log(`Lock released: ${jobRunId}`);
  }

  /**
   * Marca lock como fallido
   */
  async failLock(jobRunId: string, errorMessage: string): Promise<void> {
    await this.supabase.adminClient
      .from('job_runs')
      .update({
        status: 'failed',
        finished_at: new Date().toISOString(),
        error_message: errorMessage,
      })
      .eq('id', jobRunId);

    this.logger.error(`Lock failed: ${jobRunId} - ${errorMessage}`);
  }

  /**
   * Cleanup de locks huérfanos (running > 1 hora)
   */
  async cleanupStaleLocks(): Promise<number> {
    const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString();

    const { data, error } = await this.supabase.adminClient
      .from('job_runs')
      .update({ status: 'failed', error_message: 'Stale lock cleanup', finished_at: new Date().toISOString() })
      .eq('status', 'running')
      .lt('started_at', oneHourAgo)
      .select('id');

    if (error) throw error;

    const cleaned = data?.length || 0;
    if (cleaned > 0) {
      this.logger.warn(`Cleaned ${cleaned} stale locks`);
    }

    return cleaned;
  }
}
```

#### Uso en Workers

```typescript
// src/analytics/analytics-worker.service.ts
@Injectable()
export class AnalyticsWorkerService {
  constructor(
    private readonly lockService: DistributedLockService,
    // ...
  ) {}

  @Cron('0 2 * * *') // 2:00 AM
  async calculateDailySales() {
    const yesterday = new Date(Date.now() - 24 * 60 * 60 * 1000);
    const jobKey = 'analytics:daily_sales';

    // 1. Intentar adquirir lock
    const lockId = await this.lockService.acquireLock(jobKey, yesterday);
    if (!lockId) {
      // Otro worker ya procesando
      return;
    }

    try {
      // 2. Procesar
      const rowsProcessed = await this.processDailySales(yesterday);

      // 3. Liberar lock
      await this.lockService.releaseLock(lockId, rowsProcessed);
    } catch (err) {
      // 4. Marcar como fallido
      await this.lockService.failLock(lockId, err.message);
      throw err;
    }
  }
}
```

#### Cron de Cleanup

```typescript
// src/common/distributed-lock/distributed-lock-worker.service.ts
@Injectable()
export class DistributedLockWorkerService {
  @Cron('*/15 * * * *') // cada 15 min
  async cleanupStaleLocks() {
    await this.lockService.cleanupStaleLocks();
  }
}
```

---

## 🔴 P0.2 — Source of Truth de Stock: `inventory_items`

### Problema

**Plan original:** `products.stock` es el stock, variantes heredan de ahí, multi-warehouse agrega `warehouse_stock`.

**Conflicto:**
- ¿`products.stock` es el stock total o del warehouse default?
- ¿Variante hereda stock de padre o tiene propio?
- ¿Cómo sumo stock cross-warehouse para mostrar disponibilidad?

**Resultado:** Reescribir la mitad del sistema cuando agregues la 2da feature.

### Fix Obligatorio: Abstracción de Inventory Item

#### Nueva Tabla: `inventory_items` (Source of Truth)

```sql
-- Source of truth de stock: TODO pasa por acá
CREATE TABLE inventory_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  
  -- Qué representa este item
  item_type TEXT NOT NULL, -- 'product' | 'variant'
  ref_id UUID NOT NULL, -- products.id (si type=product) o product_variant.id
  
  -- Stock (ahora acá, no en products)
  quantity INTEGER NOT NULL DEFAULT 0,
  reserved INTEGER NOT NULL DEFAULT 0,
  available INTEGER GENERATED ALWAYS AS (quantity - reserved) STORED,
  
  -- Ubicación (para multi-warehouse)
  location_id UUID REFERENCES warehouse_locations(id) ON DELETE SET NULL, -- null = ubicación default
  
  -- Metadata
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  UNIQUE(client_id, item_type, ref_id, location_id)
);

CREATE INDEX idx_inventory_items_client_type ON inventory_items(client_id, item_type);
CREATE INDEX idx_inventory_items_ref ON inventory_items(ref_id);
CREATE INDEX idx_inventory_items_location ON inventory_items(location_id) WHERE location_id IS NOT NULL;

-- RLS
CREATE POLICY "inventory_items_select_tenant"
  ON inventory_items FOR SELECT
  USING (client_id = current_client_id());

CREATE POLICY "inventory_items_server_bypass"
  ON inventory_items FOR ALL
  USING (auth.role() = 'service_role');

ALTER TABLE inventory_items ENABLE ROW LEVEL SECURITY;
```

#### Migrar `products.stock` (backward compat)

```sql
-- Opción 1: Migración destructiva (si no tenés datos en prod)
ALTER TABLE products DROP COLUMN stock;

-- Opción 2: Mantener column pero deprecado (para migración gradual)
ALTER TABLE products RENAME COLUMN stock TO stock_deprecated;
ALTER TABLE products ADD COLUMN stock INTEGER GENERATED ALWAYS AS (
  (SELECT COALESCE(SUM(quantity), 0) 
   FROM inventory_items 
   WHERE item_type = 'product' AND ref_id = products.id)
) STORED;

-- Opción 3: View para APIs legacy
CREATE VIEW products_with_stock AS
SELECT 
  p.*,
  COALESCE(SUM(ii.quantity), 0) AS current_stock,
  COALESCE(SUM(ii.available), 0) AS available_stock
FROM products p
LEFT JOIN inventory_items ii ON ii.ref_id = p.id AND ii.item_type = 'product'
GROUP BY p.id;
```

#### Actualizar `stock_movements` para apuntar a `inventory_item_id`

```sql
ALTER TABLE stock_movements 
  ADD COLUMN inventory_item_id UUID REFERENCES inventory_items(id) ON DELETE CASCADE;

-- Migración: vincular movements existentes con inventory_items
UPDATE stock_movements sm
SET inventory_item_id = ii.id
FROM inventory_items ii
WHERE ii.ref_id = sm.product_id AND ii.item_type = 'product';

-- Hacer obligatorio después de migración
ALTER TABLE stock_movements ALTER COLUMN inventory_item_id SET NOT NULL;

-- Deprecar product_id (o dejarlo para auditoría)
-- ALTER TABLE stock_movements DROP COLUMN product_id;
```

#### RPC Functions actualizadas

```sql
-- Decrementar stock (ahora sobre inventory_items)
CREATE OR REPLACE FUNCTION decrement_inventory_stock(
  p_client_id UUID,
  p_item_type TEXT,
  p_ref_id UUID,
  p_quantity INTEGER,
  p_location_id UUID DEFAULT NULL,
  p_order_id UUID DEFAULT NULL,
  p_user_id UUID DEFAULT NULL
) RETURNS BOOLEAN AS $$
DECLARE
  v_item RECORD;
BEGIN
  -- Lock item
  SELECT * INTO v_item
  FROM inventory_items
  WHERE client_id = p_client_id 
    AND item_type = p_item_type
    AND ref_id = p_ref_id
    AND (location_id = p_location_id OR (location_id IS NULL AND p_location_id IS NULL))
  FOR UPDATE;

  IF v_item IS NULL THEN
    RAISE EXCEPTION 'Inventory item not found';
  END IF;

  IF v_item.available < p_quantity THEN
    RAISE EXCEPTION 'Insufficient stock';
  END IF;

  -- Decrementar
  UPDATE inventory_items
  SET quantity = quantity - p_quantity, updated_at = NOW()
  WHERE id = v_item.id;

  -- Registrar movimiento
  INSERT INTO stock_movements (
    client_id, inventory_item_id, movement_type, quantity,
    stock_before, stock_after, order_id, user_id
  ) VALUES (
    p_client_id, v_item.id, 'sale', -p_quantity,
    v_item.quantity, v_item.quantity - p_quantity, p_order_id, p_user_id
  );

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- Reservar stock
CREATE OR REPLACE FUNCTION reserve_inventory_stock(
  p_client_id UUID,
  p_item_type TEXT,
  p_ref_id UUID,
  p_quantity INTEGER,
  p_session_id TEXT,
  p_user_id UUID DEFAULT NULL,
  p_ttl_minutes INTEGER DEFAULT 15
) RETURNS UUID AS $$
DECLARE
  v_item RECORD;
  v_reservation_id UUID;
BEGIN
  -- Lock item
  SELECT * INTO v_item
  FROM inventory_items
  WHERE client_id = p_client_id 
    AND item_type = p_item_type
    AND ref_id = p_ref_id
    AND location_id IS NULL -- solo default location por ahora
  FOR UPDATE;

  IF v_item.available < p_quantity THEN
    RAISE EXCEPTION 'Insufficient available stock';
  END IF;

  -- Incrementar reserved
  UPDATE inventory_items
  SET reserved = reserved + p_quantity, updated_at = NOW()
  WHERE id = v_item.id;

  -- Crear reserva
  INSERT INTO stock_reservations (
    client_id, inventory_item_id, quantity, session_id, user_id, 
    expires_at
  ) VALUES (
    p_client_id, v_item.id, p_quantity, p_session_id, p_user_id,
    NOW() + (p_ttl_minutes || ' minutes')::INTERVAL
  ) RETURNING id INTO v_reservation_id;

  -- Movimiento
  INSERT INTO stock_movements (
    client_id, inventory_item_id, movement_type, quantity,
    stock_before, stock_after, user_id, reason
  ) VALUES (
    p_client_id, v_item.id, 'reservation', -p_quantity,
    v_item.quantity, v_item.quantity, p_user_id, 'Checkout reservation'
  );

  RETURN v_reservation_id;
END;
$$ LANGUAGE plpgsql;

-- Liberar reserva
CREATE OR REPLACE FUNCTION release_inventory_reservation(p_reservation_id UUID) RETURNS BOOLEAN AS $$
DECLARE
  v_reservation RECORD;
  v_item RECORD;
BEGIN
  -- Lock reserva
  SELECT * INTO v_reservation
  FROM stock_reservations
  WHERE id = p_reservation_id AND NOT released
  FOR UPDATE;

  IF v_reservation IS NULL THEN
    RETURN FALSE;
  END IF;

  -- Lock item
  SELECT * INTO v_item
  FROM inventory_items
  WHERE id = v_reservation.inventory_item_id
  FOR UPDATE;

  -- Decrementar reserved
  UPDATE inventory_items
  SET reserved = reserved - v_reservation.quantity, updated_at = NOW()
  WHERE id = v_item.id;

  -- Marcar liberada
  UPDATE stock_reservations
  SET released = true, released_at = NOW()
  WHERE id = p_reservation_id;

  -- Movimiento
  INSERT INTO stock_movements (
    client_id, inventory_item_id, movement_type, quantity,
    stock_before, stock_after, reason
  ) VALUES (
    v_reservation.client_id, v_item.id, 'reservation_release', v_reservation.quantity,
    v_item.quantity, v_item.quantity, 'Reservation released'
  );

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql;
```

#### Service Layer (NestJS)

```typescript
// src/inventory/inventory.service.ts
async getAvailableStock(
  clientId: string,
  itemType: 'product' | 'variant',
  refId: string,
): Promise<number> {
  const { data } = await this.supabase.client
    .from('inventory_items')
    .select('available')
    .eq('client_id', clientId)
    .eq('item_type', itemType)
    .eq('ref_id', refId)
    .is('location_id', null); // solo default location

  return data?.reduce((sum, item) => sum + item.available, 0) || 0;
}

async decrementStock(
  clientId: string,
  itemType: 'product' | 'variant',
  refId: string,
  quantity: number,
  orderId?: string,
) {
  const { data, error } = await this.supabase.client.rpc(
    'decrement_inventory_stock',
    {
      p_client_id: clientId,
      p_item_type: itemType,
      p_ref_id: refId,
      p_quantity: quantity,
      p_order_id: orderId,
    },
  );

  if (error) throw error;
  return data;
}
```

---

## 🔴 P0.3 — Feature Gating Server-Side

### Problema

**Plan original:** `featureCatalog.ts` + validación en UI.

**Brechas:**
- Bug de frontend expone feature Enterprise a Growth
- Llamada directa a endpoint (curl/Postman) bypasea gating
- No hay límites enforceados en DB (ej. max 100 variantes Growth)

### Fix Obligatorio: Guard + Middleware + DB Constraints

#### Guard: `FeatureGuard`

```typescript
// src/common/guards/feature.guard.ts
import { Injectable, CanActivate, ExecutionContext, ForbiddenException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { PlanService } from '../plan/plan.service';

export const REQUIRE_FEATURE = 'require_feature';

@Injectable()
export class FeatureGuard implements CanActivate {
  constructor(
    private reflector: Reflector,
    private planService: PlanService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const requiredFeature = this.reflector.get<string>(
      REQUIRE_FEATURE,
      context.getHandler(),
    );

    if (!requiredFeature) {
      return true; // No feature requerido
    }

    const request = context.switchToHttp().getRequest();
    const clientId = request.clientId; // del middleware
    const userId = request.user?.id;

    if (!clientId) {
      throw new ForbiddenException('Client context required');
    }

    // Obtener plan del cliente
    const client = await this.planService.getClientWithPlan(clientId);

    // Verificar si el plan incluye la feature
    const hasFeature = await this.planService.hasFeature(
      client.plan,
      requiredFeature,
    );

    if (!hasFeature) {
      throw new ForbiddenException(
        `Feature '${requiredFeature}' not available in ${client.plan} plan`,
      );
    }

    return true;
  }
}
```

#### Decorador: `@RequireFeature()`

```typescript
// src/common/decorators/require-feature.decorator.ts
import { SetMetadata } from '@nestjs/common';
import { REQUIRE_FEATURE } from '../guards/feature.guard';

export const RequireFeature = (featureKey: string) => 
  SetMetadata(REQUIRE_FEATURE, featureKey);
```

#### Uso en Controllers

```typescript
// src/analytics/analytics.controller.ts
@Controller('analytics')
@UseGuards(AuthGuard, FeatureGuard)
export class AnalyticsController {
  @Get('sales/overview')
  @RequireFeature('dashboard.analytics')
  async getSalesOverview(@Query() query: AnalyticsQueryDto) {
    // Solo clientes Growth+ pueden acceder
  }

  @Get('conversion/funnel')
  @RequireFeature('dashboard.analytics_enterprise')
  async getConversionFunnel(@Query() query: AnalyticsQueryDto) {
    // Solo Enterprise
  }
}
```

#### Límites en DB: Constraints

```sql
-- Max variantes por plan (ejemplo Growth)
CREATE OR REPLACE FUNCTION check_variant_limit() RETURNS TRIGGER AS $$
DECLARE
  v_plan TEXT;
  v_variant_count INTEGER;
  v_max_allowed INTEGER;
BEGIN
  -- Obtener plan del cliente
  SELECT plan INTO v_plan FROM clients WHERE id = NEW.client_id;

  -- Contar variantes existentes
  SELECT COUNT(*) INTO v_variant_count
  FROM products
  WHERE client_id = NEW.client_id AND is_variant = true;

  -- Determinar límite
  CASE v_plan
    WHEN 'growth', 'growth_annual' THEN v_max_allowed := 100;
    WHEN 'enterprise', 'enterprise_annual' THEN v_max_allowed := NULL; -- ilimitado
    ELSE v_max_allowed := 0; -- starter no puede
  END CASE;

  IF v_max_allowed IS NOT NULL AND v_variant_count >= v_max_allowed THEN
    RAISE EXCEPTION 'Variant limit exceeded for plan %: max % allowed', v_plan, v_max_allowed;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_variant_limit
  BEFORE INSERT ON products
  FOR EACH ROW
  WHEN (NEW.is_variant = true)
  EXECUTE FUNCTION check_variant_limit();
```

---

## 🔴 P0.4 — Observabilidad: System Events

### Problema

**Síntoma:** Workers fallan, reservas expiran mal, decrementos se duplican, y te enterás cuando el cliente escribe "mi stock está raro".

### Fix Obligatorio: Event Logging + Dashboard de Salud

#### Tabla: `system_events`

```sql
CREATE TABLE system_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID REFERENCES clients(id) ON DELETE CASCADE, -- null si es global
  event_type TEXT NOT NULL, -- 'inventory.decrement_failed', 'reservation.expired', etc
  severity TEXT NOT NULL DEFAULT 'info', -- 'debug', 'info', 'warning', 'error', 'critical'
  message TEXT NOT NULL,
  metadata JSONB, -- { product_id, order_id, error_code, etc }
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_system_events_client_type ON system_events(client_id, event_type, created_at DESC);
CREATE INDEX idx_system_events_severity ON system_events(severity, created_at DESC) WHERE severity IN ('error', 'critical');
CREATE INDEX idx_system_events_created ON system_events(created_at DESC);

-- Retention: 90 días
CREATE OR REPLACE FUNCTION cleanup_old_system_events() RETURNS INTEGER AS $$
DECLARE
  deleted_count INTEGER;
BEGIN
  DELETE FROM system_events WHERE created_at < NOW() - INTERVAL '90 days';
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;
```

#### Service: `SystemEventsService`

```typescript
// src/common/system-events/system-events.service.ts
@Injectable()
export class SystemEventsService {
  async log(
    clientId: string | null,
    eventType: string,
    severity: 'debug' | 'info' | 'warning' | 'error' | 'critical',
    message: string,
    metadata?: Record<string, any>,
  ) {
    await this.supabase.adminClient.from('system_events').insert({
      client_id: clientId,
      event_type: eventType,
      severity,
      message,
      metadata,
    });
  }

  async getRecentErrors(clientId?: string, limit = 50) {
    let query = this.supabase.adminClient
      .from('system_events')
      .select('*')
      .in('severity', ['error', 'critical'])
      .order('created_at', { ascending: false })
      .limit(limit);

    if (clientId) {
      query = query.eq('client_id', clientId);
    }

    const { data } = await query;
    return data || [];
  }
}
```

#### Integrar en Workers

```typescript
// src/inventory/inventory-worker.service.ts
try {
  await this.dbService.query(`SELECT release_inventory_reservation($1)`, [reservation.id]);
} catch (err) {
  await this.systemEvents.log(
    reservation.client_id,
    'inventory.reservation_release_failed',
    'error',
    `Failed to release reservation ${reservation.id}: ${err.message}`,
    { reservation_id: reservation.id, error: err.stack },
  );
  throw err;
}
```

#### Super Admin Dashboard: `/dashboard/system-health`

**Componente:**
```jsx
// apps/admin/src/pages/AdminDashboard/SystemHealthView.jsx
export function SystemHealthView() {
  const [events, setEvents] = useState([]);
  const [failedJobs, setFailedJobs] = useState([]);

  useEffect(() => {
    fetchSystemEvents();
    fetchFailedJobs();
  }, []);

  return (
    <Container>
      <Header>
        <Title>System Health</Title>
      </Header>

      {/* Sección 1: Failed Jobs */}
      <Section>
        <SectionTitle>Failed Jobs (Last 24h)</SectionTitle>
        <Table>
          <thead>
            <tr>
              <th>Job Key</th>
              <th>Run For Date</th>
              <th>Instance</th>
              <th>Error</th>
              <th>Started At</th>
            </tr>
          </thead>
          <tbody>
            {failedJobs.map(job => (
              <tr key={job.id}>
                <td>{job.job_key}</td>
                <td>{job.run_for_date}</td>
                <td><Code>{job.instance_id.slice(0, 8)}</Code></td>
                <td><ErrorMessage>{job.error_message}</ErrorMessage></td>
                <td>{formatDate(job.started_at)}</td>
              </tr>
            ))}
          </tbody>
        </Table>
      </Section>

      {/* Sección 2: Recent Errors por Tenant */}
      <Section>
        <SectionTitle>Recent Errors (All Tenants)</SectionTitle>
        <EventsList>
          {events.map(event => (
            <EventCard key={event.id} severity={event.severity}>
              <EventType>{event.event_type}</EventType>
              <EventMessage>{event.message}</EventMessage>
              <EventMeta>
                Client: {event.client_id ? <Link to={`/clients/${event.client_id}`}>{event.client_id.slice(0, 8)}</Link> : 'System'}
                | {formatDate(event.created_at)}
              </EventMeta>
            </EventCard>
          ))}
        </EventsList>
      </Section>
    </Container>
  );
}
```

**Endpoints:**
```typescript
// src/admin/admin.controller.ts
@Get('system/health/events')
async getSystemEvents(@Query('severity') severity?: string) {
  return this.systemEventsService.getRecentErrors(undefined, 100);
}

@Get('system/health/jobs')
async getFailedJobs() {
  return this.jobRunsService.getFailedJobs(24); // last 24h
}
```

---

## 🔴 P0.5 — Backfill para Analytics

### Problema

**Síntoma:** Cliente activa Analytics, ve dashboard vacío durante 30 días. Desconfianza.

### Fix Obligatorio: Job de Backfill + UI de Estado

#### Worker: `AnalyticsBackfillService`

```typescript
// src/analytics/analytics-backfill.service.ts
@Injectable()
export class AnalyticsBackfillService {
  async backfillDailySales(
    clientId: string,
    dateFrom: Date,
    dateTo: Date,
  ): Promise<number> {
    let processedDays = 0;
    const current = new Date(dateFrom);

    while (current <= dateTo) {
      try {
        // Agregar órdenes del día
        const { data: orders } = await this.supabase.client
          .from('orders')
          .select('*')
          .eq('client_id', clientId)
          .gte('created_at', current.toISOString())
          .lt('created_at', new Date(current.getTime() + 24 * 60 * 60 * 1000).toISOString());

        const revenue = orders?.reduce((sum, o) => sum + parseFloat(o.total), 0) || 0;
        const ordersCount = orders?.length || 0;
        const avgOrderValue = ordersCount > 0 ? revenue / ordersCount : 0;

        // Upsert en analytics_daily_sales
        await this.supabase.client
          .from('analytics_daily_sales')
          .upsert({
            client_id: clientId,
            date: current.toISOString().split('T')[0],
            orders_count: ordersCount,
            revenue,
            avg_order_value: avgOrderValue,
          }, { onConflict: 'client_id,date' });

        processedDays++;
      } catch (err) {
        this.logger.error(`Backfill failed for ${clientId} on ${current}:`, err);
      }

      // Avanzar 1 día
      current.setDate(current.getDate() + 1);

      // Throttle: sleep 100ms entre días (evita pegar DB)
      await new Promise(resolve => setTimeout(resolve, 100));
    }

    return processedDays;
  }
}
```

#### Tabla: `backfill_jobs`

```sql
CREATE TABLE backfill_jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  job_type TEXT NOT NULL, -- 'analytics_daily_sales', 'analytics_product_performance'
  date_from DATE NOT NULL,
  date_to DATE NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending', -- 'pending', 'running', 'completed', 'failed'
  progress INTEGER DEFAULT 0, -- días procesados
  total INTEGER, -- total días a procesar
  started_at TIMESTAMPTZ,
  finished_at TIMESTAMPTZ,
  error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_backfill_jobs_client_status ON backfill_jobs(client_id, status);
```

#### Endpoint para iniciar backfill

```typescript
// src/analytics/analytics.controller.ts
@Post('backfill')
@RequireFeature('dashboard.analytics')
async startBackfill(
  @Body() dto: { days: number }, // ej. 30, 90
) {
  const clientId = this.request.clientId;
  const dateTo = new Date();
  const dateFrom = new Date(Date.now() - dto.days * 24 * 60 * 60 * 1000);

  // Crear job
  const { data: job } = await this.supabase.client
    .from('backfill_jobs')
    .insert({
      client_id: clientId,
      job_type: 'analytics_daily_sales',
      date_from: dateFrom.toISOString().split('T')[0],
      date_to: dateTo.toISOString().split('T')[0],
      total: dto.days,
    })
    .select()
    .single();

  // Encolar para procesamiento async (o trigger worker)
  await this.backfillQueue.add('process-backfill', { jobId: job.id });

  return { jobId: job.id, status: 'pending' };
}

@Get('backfill/:jobId/status')
async getBackfillStatus(@Param('jobId') jobId: string) {
  const { data: job } = await this.supabase.client
    .from('backfill_jobs')
    .select('*')
    .eq('id', jobId)
    .single();

  return {
    status: job.status,
    progress: job.progress,
    total: job.total,
    percentage: job.total > 0 ? (job.progress / job.total) * 100 : 0,
  };
}
```

#### UI: Banner en Analytics Dashboard

```jsx
// src/components/analytics/BackfillBanner.jsx
export function BackfillBanner() {
  const [job, setJob] = useState(null);
  const [polling, setPolling] = useState(false);

  const startBackfill = async (days) => {
    const response = await analyticsService.startBackfill(days);
    setJob(response);
    setPolling(true);
  };

  useEffect(() => {
    if (!polling || !job) return;

    const interval = setInterval(async () => {
      const status = await analyticsService.getBackfillStatus(job.jobId);
      setJob(prev => ({ ...prev, ...status }));

      if (status.status === 'completed' || status.status === 'failed') {
        setPolling(false);
      }
    }, 2000);

    return () => clearInterval(interval);
  }, [polling, job]);

  if (job?.status === 'running') {
    return (
      <Banner type="info">
        <Spinner /> Generando datos históricos... {job.progress}/{job.total} días procesados
        <ProgressBar value={job.percentage} />
      </Banner>
    );
  }

  if (job?.status === 'completed') {
    return (
      <Banner type="success">
        ✓ Datos históricos generados. Dashboard actualizado.
      </Banner>
    );
  }

  // Mostrar solo si no hay datos en analytics_daily_sales
  return (
    <Banner type="warning">
      <Message>
        Para ver métricas, genera datos históricos (puede tardar 1-2 minutos).
      </Message>
      <Button onClick={() => startBackfill(30)}>Generar últimos 30 días</Button>
      <Button onClick={() => startBackfill(90)}>Generar últimos 90 días</Button>
    </Banner>
  );
}
```

---

## 📦 Mejoras Específicas por Feature

### Analytics: Pragmatismo sobre Perfección

#### A) Evitar "Visitors" al inicio

**Razón:** Requiere sessionización, consent, deduplicación, compliance GDPR.

**Approach MVP:**
- Métricas **solo de e-commerce** (órdenes, revenue, checkout).
- `analytics_daily_sales.visitors` nullable, no usado.
- `analytics_conversion_events` trackea solo: `add_to_cart`, `checkout_start`, `checkout_complete` (sin page_view ni product_view).
- Conversión calculada como: `completed_checkout / initiated_checkout * 100`.

**Upgrade path (Enterprise):**
- Integración GA4/PostHog para traffic real.
- SDK de tracking con consent management.

#### B) Event Schema + Dedupe

**Problema:** 1 usuario ve 10 productos = 10 eventos. En 30 días explosivo.

**Fix:**
```sql
ALTER TABLE analytics_conversion_events 
  ADD COLUMN dedupe_key TEXT GENERATED ALWAYS AS (
    md5(session_id || event_type || COALESCE(event_data->>'product_id', '') || date_trunc('minute', created_at)::TEXT)
  ) STORED,
  ADD CONSTRAINT unique_event_dedupe UNIQUE (client_id, dedupe_key);
```

**Retention agresivo:**
```sql
-- Cron: eliminar eventos > 90 días
DELETE FROM analytics_conversion_events WHERE created_at < NOW() - INTERVAL '90 days';
```

#### C) PostgreSQL sobre Redis (inicialmente)

**Approach:**
- Cache en memoria por instancia (simple Map con TTL).
- Redis solo cuando P95 > 500ms en endpoints críticos.

```typescript
// src/analytics/analytics-cache.service.ts
@Injectable()
export class AnalyticsCacheService {
  private cache = new Map<string, { data: any; expires: number }>();

  get(key: string): any | null {
    const entry = this.cache.get(key);
    if (!entry) return null;
    if (Date.now() > entry.expires) {
      this.cache.delete(key);
      return null;
    }
    return entry.data;
  }

  set(key: string, data: any, ttlMs: number = 15 * 60 * 1000) {
    this.cache.set(key, { data, expires: Date.now() + ttlMs });
  }
}
```

---

### Inventory: Idempotencia en Checkout → Webhook

#### Flujo Completo Robusto

```typescript
// src/checkout/checkout.service.ts
async createPreference(clientId: string, cartItems: CartItem[]) {
  const idempotencyKey = uuidv4(); // único por intento de checkout

  // 1. Reservar stock (idempotente por session_id + product_id)
  const reservations = await Promise.all(
    cartItems.map(item =>
      this.inventoryService.reserveStock({
        client_id: clientId,
        item_type: 'product',
        ref_id: item.product_id,
        quantity: item.quantity,
        session_id: this.cartSessionId,
        idempotency_key: idempotencyKey,
      })
    )
  );

  try {
    // 2. Crear preferencia MP
    const preference = await this.mercadoPagoService.createPreference({
      items: cartItems,
      metadata: {
        client_id: clientId,
        reservation_ids: reservations.map(r => r.id),
        idempotency_key: idempotencyKey,
      },
    });

    // 3. Guardar orden en estado "pending"
    await this.ordersService.create({
      client_id: clientId,
      user_id: this.userId,
      status: 'pending',
      payment_id: preference.id,
      idempotency_key: idempotencyKey,
      total: cartItems.reduce((sum, i) => sum + i.price * i.quantity, 0),
    });

    return preference;
  } catch (err) {
    // Si falla: liberar reservas
    await Promise.all(reservations.map(r => this.inventoryService.releaseReservation(r.id)));
    throw err;
  }
}
```

```typescript
// src/payments/mercadopago-webhook.service.ts
async handleNotification(payment_id: string, topic: string) {
  // 1. Buscar orden por payment_id (idempotente: si ya processed, skip)
  const order = await this.ordersService.findByPaymentId(payment_id);
  if (!order || order.status !== 'pending') {
    this.logger.warn(`Order already processed or not found: ${payment_id}`);
    return; // idempotencia
  }

  // 2. Consultar estado en MP
  const payment = await this.mercadoPagoService.getPayment(payment_id);

  // 3. Según estado
  if (payment.status === 'approved') {
    // Decrementar stock (final, libera reservas automáticamente)
    await this.inventoryService.finalizeOrder(order.id);

    // Actualizar orden
    await this.ordersService.update(order.id, { status: 'paid' });

    // Email de confirmación
    await this.emailService.sendOrderConfirmation(order.id);
  } else if (payment.status === 'rejected' || payment.status === 'cancelled') {
    // Liberar reservas
    await this.inventoryService.cancelOrder(order.id);

    // Actualizar orden
    await this.ordersService.update(order.id, { status: 'cancelled' });
  }
  // pending/in_process → no action, esperar siguiente notification
}
```

#### `finalizeOrder` (convierte reservas en decrementos)

```typescript
// src/inventory/inventory.service.ts
async finalizeOrder(orderId: string) {
  // 1. Obtener reservas de la orden
  const reservations = await this.getReservationsByOrder(orderId);

  for (const res of reservations) {
    // 2. Decrementar stock (final)
    await this.supabase.client.rpc('decrement_inventory_stock', {
      p_client_id: res.client_id,
      p_item_type: res.item_type,
      p_ref_id: res.ref_id,
      p_quantity: res.quantity,
      p_order_id: orderId,
    });

    // 3. Marcar reserva como "finalized" (para evitar doble release)
    await this.supabase.client
      .from('stock_reservations')
      .update({ released: true, released_at: new Date().toISOString() })
      .eq('id', res.id);
  }
}
```

---

### Variants: Combination Key para unicidad

```sql
-- Generar combination_key: hash ordenado de attribute_value_ids
ALTER TABLE products 
  ADD COLUMN combination_key TEXT;

CREATE UNIQUE INDEX idx_products_unique_combination 
  ON products(client_id, parent_product_id, combination_key) 
  WHERE is_variant = true AND combination_key IS NOT NULL;

-- Function para generar key
CREATE OR REPLACE FUNCTION generate_combination_key(p_variant_id UUID) RETURNS TEXT AS $$
DECLARE
  v_key TEXT;
BEGIN
  SELECT string_agg(pvv.attribute_value_id::TEXT, '|' ORDER BY pvv.attribute_value_id)
  INTO v_key
  FROM product_variant_values pvv
  WHERE pvv.product_id = p_variant_id;

  RETURN md5(COALESCE(v_key, ''));
END;
$$ LANGUAGE plpgsql;

-- Trigger para auto-generar
CREATE OR REPLACE FUNCTION trg_generate_combination_key() RETURNS TRIGGER AS $$
BEGIN
  NEW.combination_key := generate_combination_key(NEW.id);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_products_combination_key
  BEFORE INSERT OR UPDATE ON products
  FOR EACH ROW
  WHEN (NEW.is_variant = true)
  EXECUTE FUNCTION trg_generate_combination_key();
```

---

## 🗂️ Orden de Implementación Revisado

### PR0 — Foundations (1 sprint) — **CRÍTICO**

**Objetivo:** Resolver los 5 P0 antes de escribir features.

- [ ] Migración: `job_runs`, `system_events`, `backfill_jobs`
- [ ] Service: `DistributedLockService` + `SystemEventsService`
- [ ] Middleware: `FeatureGuard` + validaciones de plan
- [ ] Worker: cleanup de locks + eventos
- [ ] Tests: 20 unit tests (lock acquisition, feature gating)
- [ ] Docs: runbook de observabilidad

### PR1 — Inventory Core (1.5 sprints)

**Objetivo:** Source of truth + operations atómicas.

- [ ] Migración: `inventory_items` + `stock_movements` actualizado + RPC functions
- [ ] Service: `InventoryService` con métodos sobre inventory_items
- [ ] Deprecar `products.stock` (view o generated column)
- [ ] Tests: 30 unit tests + 10 integration

### PR2 — Reservations + MP Finalize (1 sprint)

**Objetivo:** Checkout robusto con idempotency.

- [ ] Migración: `stock_reservations` vinculada a inventory_items
- [ ] Service: reserve/release/finalize
- [ ] Integración: checkout crea reservas, webhook finaliza
- [ ] Worker: liberar expiradas cada 5 min
- [ ] Tests: 25 integration tests (full flow)

### PR3 — Inventory Alertas + UI (1 sprint)

**Objetivo:** Alertas, UI admin, proyecciones.

- [ ] Migración: `inventory_settings`, `inventory_alerts`
- [ ] Worker: cron alertas diarias
- [ ] Frontend Web: página `/admin/inventory`
- [ ] Tests: 15 unit + 5 e2e

### PR4 — Variants Foundation (1 sprint)

**Objetivo:** Producto padre/variante con stock por variante.

- [ ] Migración: columnas en products + `variant_attributes` + `product_variant_values` + combination_key
- [ ] Backend: endpoints setup + bulk create
- [ ] Integración: variantes usan inventory_items (item_type='variant')
- [ ] Tests: 20 unit tests

### PR5 — Variants UI + Selector (1 sprint)

**Objetivo:** Wizard admin + selector storefront.

- [ ] Frontend Admin: `ProductVariantsWizard`
- [ ] Frontend Web: `VariantSelector` + ProductPage modificado
- [ ] Tests: 10 component + 5 e2e

### PR6 — Analytics MVP (Order-Based) (1.5 sprints)

**Objetivo:** Métricas de órdenes sin "visitors".

- [ ] Migración: `analytics_daily_sales`, `analytics_product_performance`
- [ ] Backend: 6 endpoints (sales, products)
- [ ] Worker: daily aggregation con distributed lock
- [ ] Backfill: job de generación histórica
- [ ] Frontend Web: dashboard básico con backfill banner
- [ ] Tests: 20 unit + 5 integration

### PR7 — Analytics Events + Funnel (1 sprint) — **Enterprise**

**Objetivo:** Tracking de conversión.

- [ ] Migración: `analytics_conversion_events` con dedupe_key
- [ ] Backend: endpoints funnel + cohorts
- [ ] Frontend: tracking client-side (add_to_cart, checkout)
- [ ] Tests: 15 integration

### PR8 — Super Admin Views (0.5 sprint)

**Objetivo:** Cross-tenant dashboards.

- [ ] Backend: 6 endpoints cross-tenant (analytics, inventory, variants)
- [ ] Admin Dashboard: 3 vistas nuevas + System Health
- [ ] Tests: 5 integration

---

## 📊 Estimación Revisada

| PR | Objetivo | Esfuerzo | Dependencias |
|----|----------|----------|--------------|
| PR0 | Foundations | 5d | - |
| PR1 | Inventory Core | 7d | PR0 |
| PR2 | Reservations + MP | 5d | PR1 |
| PR3 | Inventory Alerts + UI | 5d | PR2 |
| PR4 | Variants Foundation | 5d | PR1 |
| PR5 | Variants UI | 5d | PR4 |
| PR6 | Analytics MVP | 7d | PR0 |
| PR7 | Analytics Events | 5d | PR6 |
| PR8 | Super Admin | 2.5d | PR3 + PR5 + PR7 |
| **TOTAL** | | **46.5d (~9 sprints)** | |

**Timeline Secuencial:** 9 sprints (~18 semanas / 4.5 meses)  
**Timeline Paralelo (Team de 2):** 6 sprints (~12 semanas / 3 meses)

---

## ✅ Checklist de "Ready to Implement"

Antes de empezar cualquier PR de features:

- [ ] PR0 mergeado + deployed
- [ ] `job_runs` funcionando en prod (verificar con 1 worker corriendo 2x)
- [ ] `system_events` recibiendo logs
- [ ] `FeatureGuard` validado con cliente Growth vs Enterprise
- [ ] Monitoring de Railway: logs de workers visibles
- [ ] Runbook de "qué hacer si worker falla" documentado

---

**Fin de P0 Fixes**
