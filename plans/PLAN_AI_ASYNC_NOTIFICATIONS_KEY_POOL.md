# Plan: AI Generation Async + Notificaciones + Pool de API Keys

## Contexto

Si 100 tiendas generan catálogos/fotos al mismo tiempo, el sistema actual:
- Usa **una sola API key** de OpenAI → rate-limit inmediato
- **Bloquea al usuario** hasta que termina (hasta 180s para catálogo)
- **No tiene cola global** → todas las requests van directo a OpenAI
- **No notifica** cuando termina una generación en background

**Objetivo:** Hacer la generación no-bloqueante, notificar al usuario cuando termine, y distribuir carga entre múltiples API keys.

---

## Bloque 1: OpenAI Key Pool

### 1A: Servicio `OpenAiKeyPool`

**Archivo nuevo:** `api/src/ai-generation/openai-key-pool.ts`

```typescript
@Injectable()
export class OpenAiKeyPool implements OnModuleInit {
  private keys: KeyState[] = [];
  // KeyState = { key: string, client: OpenAI, inFlight: number, cooldownUntil: number }

  onModuleInit() {
    // Lee OPENAI_API_KEYS (comma-separated) o fallback a OPENAI_API_KEY
    const raw = this.config.get('OPENAI_API_KEYS') || this.config.get('OPENAI_API_KEY');
    const keyList = raw.split(',').map(k => k.trim()).filter(Boolean);
    this.keys = keyList.map(k => ({
      key: k,
      client: new OpenAI({ apiKey: k }),
      inFlight: 0,
      cooldownUntil: 0,
    }));
  }

  // Selecciona la key con menos requests en vuelo que no esté en cooldown
  acquire(): { client: OpenAI; release: () => void; markRateLimited: () => void }

  // Semáforo global: máximo N llamadas concurrentes totales
  private readonly maxConcurrent = Number(process.env.AI_MAX_CONCURRENT || 8);
  get totalInFlight(): number
}
```

**Estrategia de selección:** Least-loaded + cooldown awareness
- Ordena keys por `inFlight` ascendente
- Excluye keys con `cooldownUntil > Date.now()`
- Si todas en cooldown → espera con backoff (no reject)
- Si OpenAI devuelve 429 → `markRateLimited()` pone cooldown de 30s en esa key

**Semáforo global:** `maxConcurrent` configurable via `AI_MAX_CONCURRENT` env var. Si se alcanza el límite, los jobs esperan en la cola del worker (no se rechazan).

### 1B: Integrar en AiGenerationService

**Archivo:** `api/src/ai-generation/ai-generation.service.ts`

- Reemplazar `private client: OpenAI | null` por inyección de `OpenAiKeyPool`
- `callOpenAI()`: usa `pool.acquire()` → `try { ... } finally { release() }`
- `callOpenAIImageGeneration()`: idem
- Si OpenAI devuelve 429: `markRateLimited()` + retry con otra key
- Si OpenAI devuelve error no-retryable: no marcar cooldown

### 1C: Env var

```env
# Múltiples keys separadas por coma
OPENAI_API_KEYS=sk-proj-key1,sk-proj-key2,sk-proj-key3
# O la key única existente (backward compatible)
OPENAI_API_KEY=sk-proj-tu-key
# Máximo de llamadas OpenAI concurrentes (default: 8)
AI_MAX_CONCURRENT=8
```

---

## Bloque 2: Tabla `ai_generation_jobs` + Worker

### 2A: Migración

**Archivo nuevo:** `api/migrations/backend/20260319_ai_generation_jobs.sql`

```sql
CREATE TABLE IF NOT EXISTS ai_generation_jobs (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id     uuid NOT NULL REFERENCES clients(id),
  account_id    text NOT NULL,
  job_type      text NOT NULL,  -- 'catalog', 'product_fill', 'product_improve', 'photo', 'logo', 'banner', 'service_improve'
  status        text NOT NULL DEFAULT 'queued',  -- 'queued' | 'processing' | 'completed' | 'failed'
  input_data    jsonb NOT NULL DEFAULT '{}',
  result_data   jsonb,          -- output cuando completa
  error_message text,
  action_code   text NOT NULL,
  tier          text NOT NULL DEFAULT 'normal',
  credits_reserved   int NOT NULL DEFAULT 0,
  credits_consumed   int NOT NULL DEFAULT 0,
  attempts      int NOT NULL DEFAULT 0,
  max_attempts  int NOT NULL DEFAULT 3,
  priority      int NOT NULL DEFAULT 0,  -- mayor = más prioridad
  progress_current int NOT NULL DEFAULT 0,  -- paso actual
  progress_total   int NOT NULL DEFAULT 0,  -- total de pasos
  progress_message text,                    -- mensaje descriptivo del paso actual
  created_at    timestamptz NOT NULL DEFAULT now(),
  started_at    timestamptz,
  completed_at  timestamptz,
  CONSTRAINT valid_status CHECK (status IN ('queued','processing','completed','failed'))
);

CREATE INDEX idx_ai_gen_jobs_pending ON ai_generation_jobs (priority DESC, created_at ASC)
  WHERE status = 'queued';
CREATE INDEX idx_ai_gen_jobs_client ON ai_generation_jobs (client_id, created_at DESC);

-- RLS
ALTER TABLE ai_generation_jobs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "server_bypass" ON ai_generation_jobs FOR ALL
  USING (auth.role() = 'service_role');
CREATE POLICY "tenant_select" ON ai_generation_jobs FOR SELECT
  USING (client_id = current_setting('app.client_id')::uuid);
```

### 2B: Tabla `client_notifications`

```sql
CREATE TABLE IF NOT EXISTS client_notifications (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id   uuid NOT NULL REFERENCES clients(id),
  type        text NOT NULL,     -- 'ai_catalog_complete', 'ai_generation_complete', 'ai_generation_failed'
  title       text NOT NULL,
  body        text,
  data        jsonb DEFAULT '{}', -- { job_id, product_ids, total_created, total_photos, ... }
  read_at     timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_notifications_client_unread ON client_notifications (client_id, created_at DESC)
  WHERE read_at IS NULL;

-- RLS
ALTER TABLE client_notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "server_bypass" ON client_notifications FOR ALL
  USING (auth.role() = 'service_role');
CREATE POLICY "tenant_select" ON client_notifications FOR SELECT
  USING (client_id = current_setting('app.client_id')::uuid);
CREATE POLICY "tenant_update" ON client_notifications FOR UPDATE
  USING (client_id = current_setting('app.client_id')::uuid);
```

### 2C: Worker `AiGenerationWorker`

**Archivo nuevo:** `api/src/ai-generation/ai-generation.worker.ts`

```typescript
@Injectable()
export class AiGenerationWorker {
  private processing = false;
  private readonly BATCH_SIZE = Number(process.env.AI_WORKER_BATCH_SIZE || 3);

  constructor(
    private readonly aiGeneration: AiGenerationService,
    private readonly aiCredits: AiCreditsService,
    private readonly notifications: AiNotificationService,
    private readonly supabaseService: SupabaseService,
  ) {}

  @Cron('*/5 * * * * *')  // cada 5 segundos
  async tick() {
    if (this.processing) return;
    this.processing = true;
    try {
      await this.processJobs();
    } finally {
      this.processing = false;
    }
  }

  private async processJobs() {
    const db = this.supabaseService.getServiceClient();

    // Claim N jobs atómicamente (queued → processing)
    const { data: jobs } = await db
      .from('ai_generation_jobs')
      .update({ status: 'processing', started_at: new Date().toISOString() })
      .eq('status', 'queued')
      .order('priority', { ascending: false })
      .order('created_at', { ascending: true })
      .limit(this.BATCH_SIZE)
      .select();

    if (!jobs?.length) return;

    // Procesar en paralelo (limitado por pool de keys)
    await Promise.allSettled(jobs.map(job => this.processJob(job)));
  }

  private async processJob(job: AiGenerationJob) {
    try {
      const result = await this.executeJob(job);

      // Marcar completado
      await db.from('ai_generation_jobs').update({
        status: 'completed',
        result_data: result,
        credits_consumed: job.credits_reserved,
        completed_at: new Date().toISOString(),
      }).eq('id', job.id);

      // Consumir créditos (mover de reserva a consumo)
      await this.aiCredits.consumeCredit({ ... });

      // Crear notificación
      await this.notifications.notifyJobComplete(job, result);

    } catch (err) {
      const attempts = job.attempts + 1;
      if (attempts >= job.max_attempts) {
        // Fallo definitivo: refund + notificar
        await this.markFailed(job, err.message);
        await this.aiCredits.refundReservedCredits(job);
        await this.notifications.notifyJobFailed(job, err.message);
      } else {
        // Retry: volver a queued
        await db.from('ai_generation_jobs').update({
          status: 'queued',
          attempts,
          started_at: null,
        }).eq('id', job.id);
      }
    }
  }

  private async executeJob(job: AiGenerationJob): Promise<any> {
    switch (job.job_type) {
      case 'catalog':
        return this.executeCatalog(job);
      case 'product_fill':
        return this.executeProductFill(job);
      case 'product_improve':
        return this.executeProductImprove(job);
      // ... etc
    }
  }

  // Cleanup: jobs stuck en 'processing' por más de 10 min
  @Cron('0 */5 * * * *')  // cada 5 minutos
  async cleanupStuckJobs() { ... }
}
```

**Flujo de créditos:**
1. **Endpoint recibe request** → `AiCreditsGuard` valida que hay saldo
2. **Crear job** → `reserveCredits()` debita del ledger inmediatamente
3. **Job completado** → `consumeCredit()` registra consumo real
4. **Job fallido (max retries)** → `refundReservedCredits()` acredita de vuelta

### 2D: Servicio `AiNotificationService`

**Archivo nuevo:** `api/src/ai-generation/ai-notification.service.ts`

```typescript
@Injectable()
export class AiNotificationService {
  async notifyJobComplete(job: AiGenerationJob, result: any) {
    const { title, body, data } = this.buildNotificationContent(job, result);
    await db.from('client_notifications').insert({
      client_id: job.client_id,
      type: `ai_${job.job_type}_complete`,
      title,
      body,
      data: { job_id: job.id, ...data },
    });
  }

  async notifyJobFailed(job: AiGenerationJob, errorMessage: string) {
    await db.from('client_notifications').insert({
      client_id: job.client_id,
      type: `ai_${job.job_type}_failed`,
      title: 'Error en generación IA',
      body: `No se pudo completar: ${errorMessage}. Los créditos fueron devueltos.`,
      data: { job_id: job.id },
    });
  }

  private buildNotificationContent(job, result) {
    switch (job.job_type) {
      case 'catalog':
        return {
          title: 'Catálogo IA generado',
          body: `Se crearon ${result.total_created} productos${result.total_photos > 0 ? ` con ${result.total_photos} fotos` : ''}.`,
          data: { total_created: result.total_created, total_photos: result.total_photos, product_ids: result.products?.map(p => p.id) },
        };
      case 'product_fill':
        return {
          title: 'Producto generado con IA',
          body: `"${result.name}" fue creado en modo borrador.`,
          data: { product_name: result.name },
        };
      // ... otros tipos
    }
  }
}
```

---

## Bloque 3: API — Endpoints de Notificaciones + Jobs

### 3A: Controller de Notificaciones

**Archivo nuevo:** `api/src/notifications/notifications.controller.ts`

```typescript
@Controller('notifications')
@UseGuards(ClientDashboardGuard)
export class NotificationsController {

  // GET /notifications — lista con paginación
  @Get()
  async list(@Req() req, @Query('limit') limit = 20, @Query('offset') offset = 0) {
    // Retorna notificaciones del clientId, ordenadas por created_at DESC
  }

  // GET /notifications/unread-count — solo el contador
  @Get('unread-count')
  async unreadCount(@Req() req) {
    // SELECT count(*) FROM client_notifications WHERE client_id = X AND read_at IS NULL
    return { count: N };
  }

  // PATCH /notifications/:id/read — marcar como leída
  @Patch(':id/read')
  async markRead(@Param('id') id: string, @Req() req) { ... }

  // PATCH /notifications/read-all — marcar todas como leídas
  @Patch('read-all')
  async markAllRead(@Req() req) { ... }
}
```

### 3B: Endpoint de estado de job

**Archivo:** `api/src/ai-generation/ai-generation.controller.ts`

```typescript
// GET /ai-jobs/:id — consultar estado de un job
@Get('ai-jobs/:id')
@UseGuards(ClientDashboardGuard)
async getJobStatus(@Param('id') jobId: string, @Req() req) {
  // Retorna: { id, status, job_type, created_at, started_at, completed_at, result_data }
}

// GET /ai-jobs — listar jobs del tenant (últimos 20)
@Get('ai-jobs')
@UseGuards(ClientDashboardGuard)
async listJobs(@Req() req, @Query('limit') limit = 20) { ... }
```

### 3C: Modificar endpoints existentes para modo async

**Patrón:** Los endpoints pesados (catálogo) pasan a crear un job. Los livianos (service improve, product fill individual) pueden seguir síncronos pero pasar por el pool de keys.

**Catálogo (siempre async):**
```typescript
@Post('products/ai-catalog')
async generateCatalog(@Body() body: AiCatalogDto, @Req() req) {
  // 1. Validar créditos (guard ya lo hizo)
  // 2. Reservar créditos
  const reserved = await this.aiCredits.reserveCredits(accountId, 'ai_catalog_generation', tier);
  // 3. Crear job
  const { data: job } = await db.from('ai_generation_jobs').insert({
    client_id: clientId,
    account_id: accountId,
    job_type: 'catalog',
    action_code: 'ai_catalog_generation',
    tier,
    credits_reserved: reserved.amount,
    input_data: { industry, product_ideas, include_photos, photo_style },
  }).select().single();
  // 4. Retornar inmediatamente
  return { job_id: job.id, status: 'queued', message: 'Tu catálogo se está generando. Te notificaremos cuando esté listo.' };
}
```

**Operaciones livianas (siguen sync, pero con pool):**
Los endpoints de `ai-fill`, `ai-improve`, `ai-photo`, `service-improve`, `logo` siguen siendo síncronos pero ahora usan el `OpenAiKeyPool` para distribuir carga.

---

## Bloque 4: Frontend — Notificaciones + Async UX

### 4A: Hook `useNotifications`

**Archivo nuevo:** `web/src/hooks/useNotifications.js`

```javascript
export default function useNotifications(intervalMs = 15000) {
  const [notifications, setNotifications] = useState([]);
  const [unreadCount, setUnreadCount] = useState(0);
  const { showToast } = useToast();
  const prevCountRef = useRef(0);

  useEffect(() => {
    const poll = async () => {
      const { data } = await apiClient.get('/notifications/unread-count');
      setUnreadCount(data.count);

      // Si hay nuevas notificaciones desde el último poll, mostrar toast
      if (data.count > prevCountRef.current) {
        const { data: latest } = await apiClient.get('/notifications', { params: { limit: 1 } });
        if (latest?.[0]) {
          showToast({ message: latest[0].title, status: 'success', duration: 10000 });
        }
      }
      prevCountRef.current = data.count;
    };

    poll(); // primera vez inmediato
    const id = setInterval(poll, intervalMs);
    return () => clearInterval(id);
  }, [intervalMs]);

  const fetchAll = async (limit = 20) => { ... };
  const markRead = async (id) => { ... };
  const markAllRead = async () => { ... };

  return { notifications, unreadCount, fetchAll, markRead, markAllRead };
}
```

### 4B: Componente `NotificationBell`

**Archivo nuevo:** `web/src/components/admin/NotificationBell/index.jsx`

- Ícono de campana en el header admin
- Badge con `unreadCount` (rojo si > 0)
- Click abre dropdown con lista de notificaciones
- Cada notificación muestra: título, body, timestamp relativo, ícono por tipo
- Click en notificación → `markRead()` + navegar si hay acción (ej: ir a productos)

### 4C: Integración en AdminDashboard Header

**Archivo:** `web/src/components/admin/AdminDashboard/index.jsx` (o el componente de header)

- Agregar `<NotificationBell />` en la barra superior
- El hook `useNotifications` se inicializa a nivel del layout admin

### 4D: Actualizar `AiCatalogWizard`

**Archivo:** `web/src/components/admin/AiCatalogWizard/index.jsx`

Cambiar el flujo:
```
ANTES: Click "Generar" → esperar 30-180s → ver resultado en el wizard
AHORA: Click "Generar" → toast "Tu catálogo se está generando" → cerrar wizard
        → notificación llega en 30-180s → usuario ve resultado en productos
```

```javascript
const handleGenerate = async () => {
  try {
    const { data } = await apiClient.post('/products/ai-catalog', {
      industry, product_ideas, include_photos, photo_style, ai_tier: tier,
    });
    // data = { job_id, status: 'queued', message: '...' }
    showToast({ message: data.message, status: 'success', duration: 8000 });
    fetchBalances();
    onClose(); // cerrar wizard inmediatamente
  } catch (err) {
    if (err.response?.status !== 402) {
      showToast({ message: 'Error al iniciar generación.', status: 'error' });
    }
  }
};
```

Se eliminan: Step 2 (progress bar) y Step 3 (resultado) del wizard. Solo queda Step 1 (configuración).

---

## Bloque 5: Dashboard de Trabajos IA (Página dedicada)

### 5A: Columnas de progreso en `ai_generation_jobs`

Agregar a la migración de la tabla `ai_generation_jobs`:

```sql
-- Columnas de progreso (agregar a la tabla existente)
ALTER TABLE ai_generation_jobs ADD COLUMN IF NOT EXISTS progress_current int NOT NULL DEFAULT 0;
ALTER TABLE ai_generation_jobs ADD COLUMN IF NOT EXISTS progress_total int NOT NULL DEFAULT 0;
ALTER TABLE ai_generation_jobs ADD COLUMN IF NOT EXISTS progress_message text;
```

**Cómo se actualiza el progreso (worker):**

```
Job tipo 'catalog' con 10 productos + fotos:
  1/12  → "Generando texto del catálogo..."
  2/12  → "Creando producto 1 de 10..."
  3/12  → "Generando foto del producto 1..."
  ...
  11/12 → "Generando foto del producto 10..."
  12/12 → "Insertando productos en la tienda..."
```

El worker llama `updateProgress(job.id, current, total, message)` después de cada paso:

```typescript
private async updateProgress(jobId: string, current: number, total: number, message: string) {
  await this.db.from('ai_generation_jobs').update({
    progress_current: current,
    progress_total: total,
    progress_message: message,
  }).eq('id', jobId);
}
```

**Cálculo de `progress_total` por job_type:**

| job_type | progress_total | Fórmula |
|----------|---------------|---------|
| `catalog` (sin fotos) | `N + 1` | N productos + 1 inserción BD |
| `catalog` (con fotos) | `N * 2 + 1` | N productos × (texto + foto) + 1 inserción BD |
| `product_fill` | 2 | 1 generación + 1 inserción |
| `product_improve` | 2 | 1 generación + 1 update |
| `photo` | 2 | 1 generación + 1 upload |
| `logo` | 2 | 1 generación + 1 upload |
| `banner` | 2 | 1 generación + 1 upload |
| `service_improve` | 2 | 1 generación + 1 update |

### 5B: Endpoint `GET /ai-jobs` mejorado

**Archivo:** `api/src/ai-generation/ai-generation.controller.ts`

```typescript
// GET /ai-jobs — listar jobs del tenant con progreso
@Get('ai-jobs')
@UseGuards(ClientDashboardGuard)
async listJobs(
  @Req() req,
  @Query('status') status?: string,  // 'active' | 'completed' | 'failed' | 'all'
  @Query('limit') limit = 20,
  @Query('offset') offset = 0,
) {
  const clientId = req.clientId;
  let query = db.from('ai_generation_jobs')
    .select('id, job_type, status, priority, progress_current, progress_total, progress_message, credits_reserved, credits_consumed, created_at, started_at, completed_at, error_message')
    .eq('client_id', clientId)
    .order('created_at', { ascending: false })
    .range(offset, offset + limit - 1);

  if (status === 'active') {
    query = query.in('status', ['queued', 'processing']);
  } else if (status === 'completed') {
    query = query.eq('status', 'completed');
  } else if (status === 'failed') {
    query = query.eq('status', 'failed');
  }

  const { data, count } = await query;
  return { jobs: data, total: count };
}

// GET /ai-jobs/summary — resumen rápido para badge/header
@Get('ai-jobs/summary')
@UseGuards(ClientDashboardGuard)
async jobsSummary(@Req() req) {
  const clientId = req.clientId;
  const { count: active } = await db.from('ai_generation_jobs')
    .select('*', { count: 'exact', head: true })
    .eq('client_id', clientId)
    .in('status', ['queued', 'processing']);
  const { count: failed } = await db.from('ai_generation_jobs')
    .select('*', { count: 'exact', head: true })
    .eq('client_id', clientId)
    .eq('status', 'failed')
    .gte('created_at', new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString());
  return { active_jobs: active, recent_failures: failed };
}
```

### 5C: Sección `aiJobs` en AdminDashboard

**Archivo a modificar:** `web/src/pages/AdminDashboard/index.jsx`

Agregar en la categoría `commerce`:

```javascript
// En SECTION_CATEGORIES
{
  key: 'commerce',
  label: '🛒 Tienda y Ventas',
  sections: ['products', 'importWizard', 'orders', 'payments', 'shipping', 'coupons', 'optionSets', 'sizeGuides', 'qaManager', 'reviewsManager', 'aiJobs'],
}

// En SECTION_DETAILS
aiJobs: {
  icon: '🤖',
  title: 'Trabajos IA',
  description: 'Monitoreá el estado y progreso de tus generaciones de contenido con IA.',
}

// En LAZY_SECTION_COMPONENTS
aiJobs: lazy(() => import('components/admin/AiJobsDashboard')),
```

**URL:** `/admin-dashboard?aiJobs`

### 5D: Componente `AiJobsDashboard`

**Archivos nuevos:**
- `web/src/components/admin/AiJobsDashboard/index.jsx`
- `web/src/components/admin/AiJobsDashboard/style.jsx`

**Layout con 3 tabs:**

```
┌─ Tab Bar ──────────────────────────────────────┐
│ 🚀 En Progreso | 📋 Historial | 💳 Créditos   │
└────────────────────────────────────────────────┘
```

**Tab "En Progreso":**
```
┌──────────────────────────────────────────────────┐
│  🟡 Catálogo IA (10 productos con fotos)         │
│  ████████████░░░░░░░░  58% (7/12)                │
│  "Generando foto del producto 4..."              │
│  Iniciado hace 45s · Créditos: 5                 │
├──────────────────────────────────────────────────┤
│  ⏳ Mejorar producto "Remera Classic"            │
│  En cola · Posición #3                           │
│  Creado hace 2 min · Créditos: 1                 │
├──────────────────────────────────────────────────┤
│  ✅ No hay más trabajos en cola                  │
└──────────────────────────────────────────────────┘
```

**Comportamiento:**
- Auto-refresh cada **8 segundos** si hay jobs `queued` o `processing` (patrón de `SeoJobsTab`)
- Pausa polling si tab inactiva (`document.visibilityState`)
- Barra de progreso animada: `(progress_current / progress_total) * 100`
- Posición en cola para jobs `queued`: calculada como `COUNT(*) WHERE status='queued' AND created_at < this_job.created_at`
- Estado visual: 🟡 processing, ⏳ queued, ✅ completed, ❌ failed
- Timestamp relativo: "hace 30s", "hace 2 min", "hace 1 hora"

**Tab "Historial":**
```
┌──────────────────────────────────────────────────┐
│ Filtros: [Todos ▾] [Catálogo ▾] [Últimos 7 días]│
├──────────────────────────────────────────────────┤
│  ✅ Catálogo IA · 10 productos · 7 fotos         │
│  Completado hace 2 horas · 5 créditos            │
│  [Ver productos →]                               │
├──────────────────────────────────────────────────┤
│  ❌ Catálogo IA · Error: rate limit              │
│  Fallido hace 5 horas · 5 créditos devueltos     │
├──────────────────────────────────────────────────┤
│  Paginación: [< 1 2 3 >] (20 por página)        │
└──────────────────────────────────────────────────┘
```

**Tab "Créditos":**
- Balance actual por `action_code` (reutilizar lógica de `useAiCredits`)
- Link a Addon Store filtrado por `family=ai`

```javascript
// Hook principal del componente
function AiJobsDashboard() {
  const [activeTab, setActiveTab] = useState('active');
  const [jobs, setJobs] = useState([]);
  const [loading, setLoading] = useState(true);

  // Auto-refresh cada 8s si hay jobs activos
  useEffect(() => {
    const hasActive = jobs.some(j => ['queued', 'processing'].includes(j.status));
    if (!hasActive || document.visibilityState === 'hidden') return;

    const id = setInterval(() => fetchJobs(), 8000);
    return () => clearInterval(id);
  }, [jobs]);

  // Pausar/reanudar en tab visibility change
  useEffect(() => {
    const handler = () => {
      if (document.visibilityState === 'visible') fetchJobs();
    };
    document.addEventListener('visibilitychange', handler);
    return () => document.removeEventListener('visibilitychange', handler);
  }, []);

  const fetchJobs = async () => {
    const status = activeTab === 'active' ? 'active' : activeTab === 'history' ? 'all' : null;
    const { data } = await apiClient.get('/ai-jobs', { params: { status, limit: 20 } });
    setJobs(data.jobs);
  };

  return (
    <Container>
      <TabBar>
        <Tab $active={activeTab === 'active'} onClick={() => setActiveTab('active')}>
          🚀 En Progreso {activeCount > 0 && <Badge>{activeCount}</Badge>}
        </Tab>
        <Tab $active={activeTab === 'history'} onClick={() => setActiveTab('history')}>
          📋 Historial
        </Tab>
        <Tab $active={activeTab === 'credits'} onClick={() => setActiveTab('credits')}>
          💳 Créditos
        </Tab>
      </TabBar>

      {activeTab === 'active' && <ActiveJobsPanel jobs={activeJobs} />}
      {activeTab === 'history' && <JobsHistoryTable jobs={allJobs} />}
      {activeTab === 'credits' && <AiCreditsPanel />}
    </Container>
  );
}
```

### 5E: Componente `ProgressBar` para jobs

```javascript
function JobProgressBar({ current, total, status }) {
  const pct = total > 0 ? Math.round((current / total) * 100) : 0;

  return (
    <ProgressContainer>
      <ProgressTrack>
        <ProgressFill
          $pct={pct}
          $status={status}
          $animated={status === 'processing'}
        />
      </ProgressTrack>
      <ProgressLabel>
        {status === 'processing' ? `${pct}% (${current}/${total})` : status === 'queued' ? 'En cola' : `${pct}%`}
      </ProgressLabel>
    </ProgressContainer>
  );
}
```

---

## Bloque 6: Reserva de Créditos

### 6A: Método `reserveCredits` en AiCreditsService

**Archivo:** `api/src/ai-credits/ai-credits.service.ts`

```typescript
async reserveCredits(accountId: string, actionCode: string, tier: string): Promise<{ amount: number; ledger_id: string }> {
  const pricing = await this.getPricing(actionCode, tier);
  // Insertar en ledger con tipo 'reservation' (negativo como consumo)
  const { data } = await adminClient.from('account_action_credit_ledger').insert({
    account_id: accountId,
    action_code: actionCode,
    delta: -pricing.credit_cost,
    reason: 'ai_generation_reservation',
    metadata: { tier, reserved: true },
  }).select().single();
  return { amount: pricing.credit_cost, ledger_id: data.id };
}

async refundReservedCredits(job: { account_id: string; action_code: string; credits_reserved: number }) {
  // Insertar delta positivo para devolver
  await adminClient.from('account_action_credit_ledger').insert({
    account_id: job.account_id,
    action_code: job.action_code,
    delta: job.credits_reserved,
    reason: 'ai_generation_refund',
    metadata: { refunded: true },
  });
}
```

---

## Orden de Ejecución

| Paso | Bloque | Descripción | Dependencia |
|------|--------|-------------|-------------|
| 1 | 1A | OpenAiKeyPool service | — |
| 2 | 1B | Integrar pool en AiGenerationService | Paso 1 |
| 3 | 2A-2B | Migraciones: ai_generation_jobs (con progreso) + client_notifications | — |
| 4 | 6A | reserveCredits + refundReservedCredits | — |
| 5 | 2D | AiNotificationService | Paso 3 |
| 6 | 2C | AiGenerationWorker (con updateProgress) | Paso 1, 3, 4, 5 |
| 7 | 3A-3C | Endpoints: notificaciones + jobs mejorados + catálogo async | Paso 5, 6 |
| 8 | 4A | Hook useNotifications | — |
| 9 | 4B-4C | NotificationBell + integración header | Paso 8 |
| 10 | 4D | Actualizar AiCatalogWizard (async) | Paso 7 |
| 11 | 5C | Registrar sección aiJobs en AdminDashboard | — |
| 12 | 5D-5E | AiJobsDashboard + ProgressBar | Paso 7, 11 |

---

## Archivos a Crear

| Archivo | Propósito |
|---------|-----------|
| `api/src/ai-generation/openai-key-pool.ts` | Pool de API keys con rotación |
| `api/src/ai-generation/ai-generation.worker.ts` | Worker de cola de generación IA |
| `api/src/ai-generation/ai-notification.service.ts` | Servicio de notificaciones IA |
| `api/src/notifications/notifications.controller.ts` | Endpoints de notificaciones |
| `api/src/notifications/notifications.module.ts` | Módulo NestJS |
| `api/migrations/backend/20260319_ai_generation_jobs.sql` | Tabla de jobs + notificaciones |
| `web/src/hooks/useNotifications.js` | Hook de polling de notificaciones |
| `web/src/components/admin/NotificationBell/index.jsx` | Campana + dropdown |
| `web/src/components/admin/NotificationBell/style.jsx` | Estilos |
| `web/src/components/admin/AiJobsDashboard/index.jsx` | Dashboard de trabajos IA con tabs |
| `web/src/components/admin/AiJobsDashboard/style.jsx` | Estilos (progress bar, job cards, tabs) |

## Archivos a Modificar

| Archivo | Cambio |
|---------|--------|
| `api/src/ai-generation/ai-generation.service.ts` | Reemplazar `client` por `OpenAiKeyPool` en callOpenAI/callOpenAIImageGeneration |
| `api/src/ai-generation/ai-generation.module.ts` | Registrar OpenAiKeyPool, Worker, NotificationService |
| `api/src/ai-generation/ai-generation.controller.ts` | Catálogo → async (crear job), GET /ai-jobs con progreso, GET /ai-jobs/summary |
| `api/src/ai-credits/ai-credits.service.ts` | Agregar reserveCredits + refundReservedCredits |
| `api/src/app.module.ts` | Registrar NotificationsModule |
| `web/src/components/admin/AiCatalogWizard/index.jsx` | Simplificar a Step 1 only, toast + close |
| `web/src/pages/AdminDashboard/index.jsx` | Agregar NotificationBell en header + sección `aiJobs` en commerce |

---

## Verificación

### API
```bash
npm run lint && npm run typecheck && npm run build && ls -la dist/main.js
```

- Pool: configurar 2+ keys → verificar rotación en logs
- Catálogo: `POST /products/ai-catalog` → respuesta inmediata con `job_id`
- Worker: job pasa de `queued` → `processing` → `completed` en 30-60s
- Notificación: `GET /notifications` muestra notificación de catálogo completado
- Refund: si job falla 3 veces, créditos se devuelven
- Concurrencia: AI_MAX_CONCURRENT=2 → solo 2 llamadas simultáneas a OpenAI

### Web
```bash
npx vite build
```

- NotificationBell visible en header admin
- Badge muestra unread count
- Click abre dropdown con notificaciones
- AiCatalogWizard: click generar → toast → wizard se cierra
- Notificación llega después de ~30s

---

## Análisis QA: Edge Cases, Tests y Recomendaciones

### 1. Edge Cases y Escenarios de Fallo

#### 1.1 API Key Pool

**EC-KP-01: Todas las keys en cooldown simultáneamente**
- **Escenario:** Las 3 keys configuradas reciben HTTP 429 dentro de un lapso corto (burst de requests de múltiples tenants). Todas entran en cooldown de 30s.
- **Qué puede salir mal:** Si el plan dice "espera con backoff (no reject)", pero no define un timeout máximo, un job podría quedarse bloqueado indefinidamente esperando que una key salga de cooldown. Mientras tanto, el cron del worker sigue tickeando pero `this.processing = true` bloquea nuevos ticks.
- **Manejo esperado:** Implementar un timeout máximo de espera (ej: 120s). Si ninguna key sale de cooldown, el job debe fallar con error retryable y volver a `queued` con `attempts + 1`.

**EC-KP-02: Key inválida detectada en runtime**
- **Escenario:** Una API key se revoca en el dashboard de OpenAI mientras hay jobs en vuelo que la están usando. El error `invalid_api_key` es non-retryable según `NON_RETRYABLE_ERRORS`.
- **Qué puede salir mal:** El pool sigue intentando asignar esa key a nuevos requests. El plan no menciona un mecanismo para "deshabilitar" una key que devuelve `invalid_api_key`.
- **Manejo esperado:** `markRateLimited()` debería poner esa key en cooldown largo (o infinito) cuando el error es `invalid_api_key`. Alternativamente, implementar un `markDisabled()` separado. Loguear alerta crítica.

**EC-KP-03: Pool con una sola key (backward compatible)**
- **Escenario:** El entorno usa `OPENAI_API_KEY` (una sola key). El pool tiene size = 1. Cuando esa key recibe 429, no hay alternativa.
- **Qué puede salir mal:** Todo el sistema de generación se detiene por 30s. Si hay 10 jobs queued y el batch size es 3, todos esperan en la misma key.
- **Manejo esperado:** El sistema debe funcionar correctamente con 1 key. El semáforo global (`AI_MAX_CONCURRENT`) debería reducirse automáticamente o el operador debería configurarlo bajo (ej: 2-3).

**EC-KP-04: Keys con quotas/tiers diferentes**
- **Escenario:** key1 es Tier 1 (500 RPM), key2 es Tier 5 (10,000 RPM). El algoritmo least-loaded las trata igual.
- **Qué puede salir mal:** key1 entra en cooldown constantemente. El plan no soporta pesos/prioridades por key.
- **Manejo esperado:** Documentar que las keys deben ser del mismo tier/quota, o implementar pesos. En la v1, aceptar esta limitación y documentarla.

**EC-KP-05: Variable `OPENAI_API_KEYS` con formato inválido**
- **Escenario:** El operador configura `OPENAI_API_KEYS=sk-key1,,sk-key2,` (comas extra, strings vacíos).
- **Qué puede salir mal:** `split(',').map(k => k.trim()).filter(Boolean)` ya maneja esto según el plan, pero si todas son vacías, `this.keys = []` y `acquire()` fallará.
- **Manejo esperado:** En `onModuleInit`, si no hay keys válidas, loguear error crítico y lanzar excepción fatal (o marcar servicio como no disponible, como ya hace el AiGenerationService actual con `this.client = null`).

#### 1.2 Job Queue

**EC-JQ-01: Worker crash o restart mid-job**
- **Escenario:** El proceso Node.js se reinicia (Railway redeploy, OOM kill) mientras un job está en status `processing`. El job queda "stuck".
- **Qué puede salir mal:** Sin el `cleanupStuckJobs`, el job queda en `processing` permanentemente. Con el cleanup (cada 5 min, threshold 10 min), el job se reintenta pero se pierden 5-10 minutos.
- **Manejo esperado:** El cron `cleanupStuckJobs` debería mover jobs `processing` con `started_at` > 10 min a `queued` (incrementando `attempts`). Si ya alcanzó `max_attempts`, mover a `failed` con refund. Validar que esto está implementado.

**EC-JQ-02: Duplicate job processing (race condition en claim) — CRÍTICO**
- **Escenario:** Si el sistema escala a 2 réplicas (horizontal scaling), ambos workers ejecutan el cron simultáneamente. El query de Supabase `.update().eq('status', 'queued').limit(3)` no es atómico con SELECT FOR UPDATE.
- **Qué puede salir mal:** El plan usa la API de Supabase (PostgREST), no SQL crudo. Un UPDATE con WHERE + LIMIT en PostgREST no garantiza atomicidad entre múltiples callers. Dos workers podrían reclamar los mismos jobs.
- **Manejo esperado:** Usar una función RPC en PostgreSQL (`claim_ai_jobs`) con `SELECT FOR UPDATE SKIP LOCKED` (como hace `claim_email_jobs` en el patrón existente de `EmailJobsWorker`). Esto es un gap crítico en el plan.

**EC-JQ-03: Job stuck forever (ni completa ni falla)**
- **Escenario:** OpenAI responde pero con datos corruptos. El parsing de `JSON.parse(raw)` lanza excepción, que es atrapada por el catch de `processJob`. Pero si el error ocurre después del update a `completed` y antes de `consumeCredit`, el job queda en estado inconsistente.
- **Qué puede salir mal:** Créditos reservados nunca se consumen ni se reembolsan. El job dice `completed` pero no hay notificación.
- **Manejo esperado:** Envolver todo el bloque post-ejecución en transacción, o implementar reconciliación periódica que detecte jobs `completed` sin consumo de créditos.

**EC-JQ-04: `input_data` excesivamente grande**
- **Escenario:** Un tenant envía `product_ideas` con 10 items de 5000 caracteres cada uno. El campo `input_data` JSONB podría ser muy grande.
- **Qué puede salir mal:** Performance de la tabla, índice inflado. El DTO `AiCatalogDto` ya limita `product_ideas` a `ArrayMaxSize(10)` y `MaxLength(100)` en `industry`, pero no limita longitud individual de `product_ideas` items.
- **Manejo esperado:** Agregar `@MaxLength(200)` o similar a cada item de `product_ideas` en el DTO. Considerar un límite de tamaño en `input_data` a nivel de base de datos o servicio.

**EC-JQ-05: Job type no reconocido por el worker**
- **Escenario:** Se inserta un job con `job_type = 'unknown_type'` (por un bug en código futuro o manipulación directa de BD).
- **Qué puede salir mal:** El `switch` en `executeJob` no tiene `default` case. Retorna `undefined`, que se procesa como completado con `result_data: undefined`.
- **Manejo esperado:** Agregar `default: throw new Error('Unknown job type: ...')` para que el job falle y se reintente/refunde correctamente.

**EC-JQ-06: Orden de procesamiento y starvation**
- **Escenario:** Un tenant crea 100 jobs de tipo `product_fill` (priority=0). Otro tenant crea 1 job de tipo `catalog` (priority=0). El primer tenant ocupa todos los batch slots.
- **Qué puede salir mal:** El segundo tenant sufre starvation. El plan no implementa fairness por tenant.
- **Manejo esperado:** Considerar un mecanismo de fairness: limitar jobs por tenant en un tick, o round-robin por client_id. En la v1, documentar esta limitación.

#### 1.3 Sistema de Créditos

**EC-CR-01: Double-spend (doble reserva de créditos) — CRÍTICO**
- **Escenario:** Dos requests simultáneas del mismo tenant para el mismo `action_code`. El `AiCreditsGuard` valida saldo para ambas antes de que la primera reserve. Ambas pasan el guard. Ambas llaman `reserveCredits()`. Si el saldo era exactamente para una sola, ahora el balance queda negativo.
- **Qué puede salir mal:** El plan dice que el guard valida y luego reserva, pero la reserva es un INSERT en el ledger (no un UPDATE atómico con CHECK). No hay constraint en el ledger que impida balance negativo.
- **Manejo esperado:** `reserveCredits()` debe re-verificar el balance antes de insertar (o usar una constraint/trigger en PostgreSQL que impida balance negativo). Alternativamente, usar `SELECT FOR UPDATE` en una transaction.

**EC-CR-02: Refund race condition**
- **Escenario:** Un job falla (max retries). El worker llama `refundReservedCredits()`. Pero simultáneamente, el `cleanupStuckJobs` cron detecta el mismo job como stuck y también intenta refund.
- **Qué puede salir mal:** Doble refund. El tenant recibe el doble de créditos devueltos.
- **Manejo esperado:** El refund solo debe ocurrir si el status pasa de `processing` a `failed` de forma atómica. Verificar que el refund es idempotente (ej: insertar con metadata `{ refunded_job_id }` y agregar un check UNIQUE o query `WHERE NOT EXISTS` antes de insertar).

**EC-CR-03: Créditos expiran entre reserva y completamiento**
- **Escenario:** Se reservan créditos a las 23:55. El job se completa a las 00:10. Los créditos tenían `expires_at = 00:00`. La vista `account_action_credit_balance_view` ya filtra expirados.
- **Qué puede salir mal:** La reserva fue un INSERT con `credits_delta = -N`. Cuando expira, la vista ignora ese ledger entry. El balance se "restaura" artificialmente (como si la reserva no existiera). Luego el consumo intenta hacer otro `credits_delta = -N`, causando doble deducción efectiva.
- **Manejo esperado:** Las reservas no deben tener `expires_at` (son inmediatas). O la vista debe considerar las reservas como consumos inmediatos. Revisar la lógica de la vista.

**EC-CR-04: Créditos insuficientes para la porción de fotos del catálogo**
- **Escenario:** El plan actual del catálogo (síncrono) primero genera texto (1 crédito de `ai_catalog_generation`) y luego intenta generar fotos (10 créditos de `ai_photo_product`). El guard solo valida créditos de `ai_catalog_generation`. Los créditos de foto se validan por separado.
- **Qué puede salir mal:** En el flujo async, la reserva se hace solo para `ai_catalog_generation`. Las fotos se intentan generar después, y pueden fallar por falta de créditos de foto. El usuario no fue advertido al crear el job.
- **Manejo esperado:** Si `include_photos = true`, la reserva debe incluir tanto créditos de catálogo como créditos de foto (estimados: hasta 10 unidades de `ai_photo_product`). El plan actual no menciona esta reserva combinada. Es un gap.

**EC-CR-05: Pricing cambia entre reserva y consumo**
- **Escenario:** Super admin cambia el `credit_cost` de `ai_catalog_generation` de 5 a 10 mientras hay jobs en vuelo con `credits_reserved = 5`.
- **Qué puede salir mal:** El consumo usa `job.credits_reserved` (no re-consulta pricing), así que no hay impacto directo. Pero el refund devuelve 5, no 10. Si el usuario esperaba el nuevo precio, hay confusión.
- **Manejo esperado:** Almacenar el pricing snapshot en `input_data` o `credits_reserved` del job. El plan ya hace esto (`credits_reserved = reserved.amount`). Documentar que el precio se congela al momento de crear el job.

#### 1.4 Sistema de Notificaciones

**EC-NT-01: Tabla `client_notifications` crece sin límites**
- **Escenario:** 100 tenants usando IA activamente. Cada uno genera 5-10 notificaciones/día. En un año, la tabla tiene ~350,000 filas.
- **Qué puede salir mal:** El índice `idx_notifications_client_unread` crece. El polling cada 15s por 100 tenants simultáneos genera 7 queries/segundo solo para `unread-count`.
- **Manejo esperado:** Implementar TTL/cleanup: purgar notificaciones leídas con más de 90 días. Agregar un cron para esto. El plan no menciona limpieza.

**EC-NT-02: Polling con datos stale (eventual consistency)**
- **Escenario:** El worker completa un job y crea una notificación. El poll del frontend ocurre 1ms antes del INSERT. El usuario no ve la notificación hasta el siguiente poll (15s después).
- **Manejo esperado:** Aceptable para v1. Documentar el delay de hasta 15s. El intervalo se puede reducir a 10s si es necesario.

**EC-NT-03: Notificación para tenant eliminado/desactivado**
- **Escenario:** Un tenant es desactivado (soft delete) mientras tiene jobs en vuelo. El job completa y el worker intenta crear notificación con un `client_id` que ya no existe (o tiene FK violation).
- **Manejo esperado:** Verificar que el job check si el client sigue activo antes de crear la notificación. O manejar el FK error gracefully y loguear sin crash.

**EC-NT-04: Notificación con `data` JSONB muy grande**
- **Escenario:** Un catálogo genera 10 productos. La notificación incluye `product_ids: [...]` con 10 UUIDs. Esto es pequeño, pero si alguien extiende el schema y mete datos grandes en `data`, podría ser un problema.
- **Manejo esperado:** Bajo riesgo. Aceptable para v1.

#### 1.5 Concurrencia

**EC-CC-01: 100 tenants envían catálogos simultáneamente**
- **Escenario:** 100 jobs `queued` al mismo tiempo. `AI_MAX_CONCURRENT = 8`. El batch size es 3.
- **Qué puede salir mal:** Solo 3 jobs se procesan por tick (cada 5s). Los 100 jobs tardarían ~33 ticks = ~165s en empezar a procesarse todos. Los últimos en la cola esperan ~3 minutos solo para empezar.
- **Manejo esperado:** Esto es by-design. El sistema protege la API de OpenAI. Considerar un endpoint `GET /ai-jobs/:id` que devuelva la posición estimada.

**EC-CC-02: Mismo tenant envía 5 catálogos seguidos**
- **Escenario:** El actual `acquireGeneratingLock` impide generación simultánea por `accountId:actionCode`. Pero en el flujo async, el lock desaparece: el endpoint crea el job y retorna inmediatamente. Nada impide al usuario hacer 5 POSTs seguidos.
- **Manejo esperado:** Implementar rate limiting por tenant en el endpoint (ej: max 1 catalog job cada 60s). O verificar si ya existe un job `queued` o `processing` para ese tenant/action_code.

**EC-CC-03: Worker claim race (doble instancia)**
- **Escenario:** Ya descrito en EC-JQ-02. El plan usa un flag `this.processing` en memoria, que solo protege contra re-entrancy del mismo proceso. No protege contra múltiples réplicas.
- **Manejo esperado:** Para single-instance (Railway con 1 réplica), el flag es suficiente. Para escalar, necesita `SELECT FOR UPDATE SKIP LOCKED` vía RPC.

**EC-CC-04: Pool semáforo y deadlock**
- **Escenario:** `AI_MAX_CONCURRENT = 8`. 3 jobs de catálogo, cada uno necesita 1 call de texto + 10 calls de foto = 33 calls. Pero el semáforo global solo permite 8.
- **Qué puede salir mal:** Si los 3 jobs inician sus 10 photos cada uno, los 30 calls compiten por 8 slots. Si la implementación usa un semáforo que bloquea (await), hay riesgo de livelock donde los jobs monopolizan slots y nuevos ticks no pueden procesar nada.
- **Manejo esperado:** El semáforo debe ser non-blocking con queue. Los jobs de catálogo deben limitar photos concurrentes (ej: 2-3 por job). El plan no especifica este límite interno.

#### 1.6 Seguridad Multi-Tenant

**EC-SEC-01: Datos de job visibles entre tenants**
- **Manejo esperado:** La tabla `ai_generation_jobs` tiene RLS policy `tenant_select` que filtra por `client_id`. El endpoint debe usar el service_role client y setear `app.client_id` correctamente, o filtrar por `client_id` en el query.

**EC-SEC-02: Notificación visible para tenant equivocado**
- **Manejo esperado:** RLS policy idéntica. El endpoint `GET /notifications` debe filtrar por `client_id`.

**EC-SEC-03: Bypass de RLS vía service_role**
- **Escenario:** El worker usa `service_role` para actualizar jobs de todos los tenants. Si un bug pasa un `client_id` incorrecto al crear la notificación, la notificación va al tenant equivocado.
- **Manejo esperado:** El `client_id` de la notificación debe sacarse siempre del job (que fue creado con el `client_id` validado del request original). Nunca recibir `client_id` de fuentes externas en el worker.

**EC-SEC-04: Manipulación de `job_id` en el endpoint de status**
- **Manejo esperado:** El query debe incluir `.eq('id', jobId).eq('client_id', clientId)`.

**EC-SEC-05: Inyección en `input_data`**
- **Manejo esperado:** Sanitizar input en DTOs (ya hay `@MinLength`, `@MaxLength`). El riesgo de prompt injection es inherente al uso de IA y no está en scope del plan.

#### 1.7 Frontend

**EC-FE-01: Usuario cierra browser antes del toast**
- **Manejo esperado:** El `NotificationBell` mostrará las notificaciones no leídas cuando el usuario vuelva. Aceptable para v1.

**EC-FE-02: Polling cuando el usuario está offline**
- **Escenario:** El usuario pierde conexión a internet. El `setInterval` del hook `useNotifications` sigue ejecutándose cada 15s pero todas las requests fallan.
- **Manejo esperado:** El hook debe detectar errores de red y pausar el polling (back off). Usar `navigator.onLine` o silenciar errores de red.

**EC-FE-03: Stale notification count**
- **Escenario:** El usuario marca una notificación como leída (`PATCH /notifications/:id/read`). Pero el poll del `unread-count` se ejecuta antes de que la request de mark-read complete.
- **Manejo esperado:** El `markRead` debe actualizar `unreadCount` localmente de forma optimista (decrementar sin esperar al poll).

**EC-FE-04: Toast duplicado por race condition en count**
- **Escenario:** Dos notificaciones llegan entre dos polls. El count sube de 0 a 2. El hook fetch el latest 1 y muestra solo un toast.
- **Manejo esperado:** Considerar obtener `latest N` donde N = `data.count - prevCountRef.current` para mostrar toast de cada nueva notificación.

**EC-FE-05: Polling agresivo con múltiples tabs**
- **Escenario:** El usuario tiene 5 tabs abiertas del dashboard. Cada una hace polling cada 15s.
- **Manejo esperado:** Usar `document.visibilityState` para pausar polling en tabs inactivas. El plan no menciona esto.

#### 1.8 Integridad de Datos

**EC-DI-01: Catálogo crea 7 de 10 productos y luego falla**
- **Escenario:** El worker genera 10 productos con OpenAI. Inserta 7 en la BD. El 8o falla por error de BD. El job lanza excepción.
- **Qué puede salir mal:** Los 7 productos insertados quedan en la BD. El job se reintenta y crea otros 10 productos, 7 duplicados.
- **Manejo esperado:** El flujo de catálogo debe ser idempotente. Opciones: (a) usar transacción para insertar todos o ninguno, (b) asociar cada producto insertado con el `job_id` y verificar duplicados en retry.

**EC-DI-02: Generación de fotos falla parcialmente**
- **Escenario:** De 10 fotos, 7 se generan exitosamente y 3 fallan.
- **Manejo esperado:** La notificación debe indicar claramente: "Se crearon 10 productos con 7 fotos (3 fotos no se pudieron generar)."

**EC-DI-03: Job completado pero notificación no se crea**
- **Escenario:** El worker completa el job pero el INSERT de notificación falla por BD momentáneamente no disponible.
- **Manejo esperado:** El fallo de notificación no debe fallar el job completo. Debe ser fire-and-forget con logging de error. Considerar cron de reconciliación.

**EC-DI-04: Créditos consumidos pero job no se marca completed**
- **Escenario:** `consumeCredit()` se ejecuta, pero el update de status a `completed` falla.
- **Manejo esperado:** El orden debería ser: (1) actualizar job a `completed`, (2) consumir créditos, (3) crear notificación. Si (1) falla, los créditos no se consumen. Agregar reconciliación periódica.

---

### 2. Casos de Test

#### 2.1 KeyPool (KP)

| ID | Título | Resultado Esperado | Prioridad |
|---|---|---|---|
| TC-KP-01 | Inicializar pool con múltiples keys | Pool contiene 3 KeyState con `inFlight=0`, `cooldownUntil=0` | P0 |
| TC-KP-02 | Fallback a key única | Pool contiene 1 key. Sistema funcional | P0 |
| TC-KP-03 | acquire() retorna la key con menor inFlight | Retorna key con menor inFlight | P0 |
| TC-KP-04 | release() decrementa inFlight | `inFlight` se decrementa correctamente | P0 |
| TC-KP-05 | markRateLimited() pone cooldown de 30s | Key no se selecciona hasta que pase el cooldown | P0 |
| TC-KP-06 | Todas las keys en cooldown: espera y reintenta | `acquire()` espera con backoff, no lanza error | P1 |
| TC-KP-07 | Semáforo global respeta AI_MAX_CONCURRENT | 3ra llamada queda en espera hasta release | P0 |
| TC-KP-08 | Key inválida: handle graceful | Key deshabilitada, siguiente acquire retorna otra key | P1 |
| TC-KP-09 | Sin keys configuradas | Error crítico inmediato "No API keys configured" | P0 |
| TC-KP-10 | Cooldown expira correctamente | Key disponible después de expirar cooldown | P1 |
| TC-KP-11 | Error 429 dispara markRateLimited + retry con otra key | Retry usa otra key, request exitoso | P0 |
| TC-KP-12 | Error non-retryable no pone cooldown | Key sigue disponible, error se propaga | P1 |

#### 2.2 JobQueue (JQ)

| ID | Título | Resultado Esperado | Prioridad |
|---|---|---|---|
| TC-JQ-01 | Job transiciona queued → processing → completed | Status completed, result_data presente, credits consumidos | P0 |
| TC-JQ-02 | Job falla y se reintenta | Vuelve a queued, attempts+1 | P0 |
| TC-JQ-03 | Job falla max retries: refund + notificación | Status failed, refund ejecutado, notificación de fallo creada | P0 |
| TC-JQ-04 | Worker respeta batch size | Solo N jobs pasan a processing | P1 |
| TC-JQ-05 | Worker respeta prioridad | Jobs con mayor priority se procesan primero | P1 |
| TC-JQ-06 | Worker no procesa si ya está procesando | Tick retorna inmediatamente | P0 |
| TC-JQ-07 | cleanupStuckJobs detecta jobs stuck | Job vuelve a queued con attempts+1 | P1 |
| TC-JQ-08 | cleanupStuckJobs: job stuck con max retries | Status failed, refund, notificación | P1 |
| TC-JQ-09 | No hay jobs queued: tick es noop | Sin errores, sin procesamiento | P2 |
| TC-JQ-10 | Job de catálogo ejecuta texto + fotos | Productos creados con fotos en BD | P0 |
| TC-JQ-11 | Job de catálogo sin fotos | Solo texto, sin llamadas a image API | P1 |
| TC-JQ-12 | Job type desconocido | Error "Unknown job type", reintento correcto | P1 |
| TC-JQ-13 | Múltiples jobs procesados en paralelo | Promise.allSettled, fallo aislado | P0 |
| TC-JQ-14 | Job con input_data corrupto | Error capturado, no crash del worker | P1 |
| TC-JQ-15 | POST /ai-catalog retorna job_id inmediatamente | Respuesta < 1s con job_id y status queued | P0 |
| TC-JQ-16 | GET /ai-jobs/:id retorna estado del job | Datos completos del job | P0 |
| TC-JQ-17 | GET /ai-jobs/:id de otro tenant retorna 404 | No leak de datos cross-tenant | P0 |

#### 2.3 Credits (CR)

| ID | Título | Resultado Esperado | Prioridad |
|---|---|---|---|
| TC-CR-01 | Reserva exitosa debita del ledger | Balance reducido correctamente | P0 |
| TC-CR-02 | Reserva falla por créditos insuficientes | HTTP 402, no se crea job | P0 |
| TC-CR-03 | Consumo post-completamiento registra en ledger | Ledger entry de consumo creada | P1 |
| TC-CR-04 | Refund por fallo devuelve créditos | Balance restaurado | P0 |
| TC-CR-05 | Double-spend prevention: requests simultáneas | Solo 1 job se crea, balance nunca negativo | P0 |
| TC-CR-06 | Refund idempotente: no doble refund | Solo 1 refund, balance correcto | P0 |
| TC-CR-07 | Catálogo con fotos: reserva combinada | Reserva de créditos de catálogo + foto | P1 |
| TC-CR-08 | Balance negativo no ocurre por race condition | Máximo N exitosos según saldo disponible | P0 |
| TC-CR-09 | Pricing snapshot se congela al crear job | Se consumen créditos al precio original | P1 |
| TC-CR-10 | Créditos expirados no se usan para reserva | 402 si solo hay créditos expirados | P1 |

#### 2.4 Notifications (NT)

| ID | Título | Resultado Esperado | Prioridad |
|---|---|---|---|
| TC-NT-01 | Notificación creada al completar job | INSERT correcto con tipo, título, body, data | P0 |
| TC-NT-02 | Notificación creada al fallar job | Body menciona refund de créditos | P0 |
| TC-NT-03 | GET /notifications retorna paginado | Ordenadas por created_at DESC, limit/offset funcional | P1 |
| TC-NT-04 | GET /notifications/unread-count | Count correcto de no leídas | P0 |
| TC-NT-05 | PATCH /notifications/:id/read marca como leída | read_at seteado | P1 |
| TC-NT-06 | PATCH /notifications/read-all marca todas | Todas con read_at, unread_count = 0 | P1 |
| TC-NT-07 | Marcar notificación de otro tenant: falla | 404 o 0 rows affected | P0 |
| TC-NT-08 | Notificación para client_id inexistente | Error logueado, worker no crashea | P2 |

#### 2.5 Concurrency (CC)

| ID | Título | Resultado Esperado | Prioridad |
|---|---|---|---|
| TC-CC-01 | 10 tenants crean jobs simultáneamente | 10 jobs queued, respuestas inmediatas | P0 |
| TC-CC-02 | Worker procesa batch sin race condition | Exactamente N jobs, sin duplicados | P0 |
| TC-CC-03 | Mismo tenant: múltiples catalog jobs | Sin crash ni datos corruptos | P1 |
| TC-CC-04 | AI_MAX_CONCURRENT limita llamadas OpenAI | Solo N llamadas activas simultáneas | P0 |
| TC-CC-05 | Worker claim atómico (sin duplicados) | SELECT FOR UPDATE SKIP LOCKED previene duplicados | P0 |
| TC-CC-06 | Flag processing impide re-entrancy | Segundo tick retorna inmediatamente | P1 |
| TC-CC-07 | Cleanup no colisiona con procesamiento activo | Solo jobs con > 10 min se marcan stuck | P1 |
| TC-CC-08 | Pool round-robin bajo carga | Distribución aproximadamente uniforme | P1 |

#### 2.6 Security (SEC)

| ID | Título | Resultado Esperado | Prioridad |
|---|---|---|---|
| TC-SEC-01 | RLS en ai_generation_jobs impide lectura cross-tenant | Solo ve sus propios jobs | P0 |
| TC-SEC-02 | RLS en client_notifications impide lectura cross-tenant | Solo ve sus propias notificaciones | P0 |
| TC-SEC-03 | GET /ai-jobs/:id filtra por client_id | 404 para jobs de otro tenant | P0 |
| TC-SEC-04 | API keys no expuestas en logs ni responses | Solo key index o alias en logs | P0 |
| TC-SEC-05 | Worker solo usa client_id del job | Nunca de fuente externa | P0 |
| TC-SEC-06 | PATCH /notifications/:id/read valida ownership | 0 rows para otro tenant | P0 |

#### 2.7 Frontend (FE)

| ID | Título | Resultado Esperado | Prioridad |
|---|---|---|---|
| TC-FE-01 | Toast se muestra al crear job de catálogo | Toast con mensaje, wizard se cierra | P0 |
| TC-FE-02 | NotificationBell muestra badge con unread count | Badge rojo con número visible | P1 |
| TC-FE-03 | Toast de nueva notificación al polling | Toast aparece, badge se actualiza | P1 |
| TC-FE-04 | Click en notificación la marca como leída | markRead() llamado, badge decrementado | P1 |
| TC-FE-05 | Polling se pausa en tab inactiva | No requests mientras tab inactiva | P2 |
| TC-FE-06 | Error 402 muestra link a addon store | Interceptor 402 con link correcto | P1 |

#### 2.8 Integration / End-to-End (E2E)

| ID | Título | Resultado Esperado | Prioridad |
|---|---|---|---|
| TC-E2E-01 | Flujo completo: catálogo async happy path | queued → processing → completed, productos + notificación + créditos | P0 |
| TC-E2E-02 | Flujo completo: catálogo fallo tras max retries | Status failed, refund, notificación de fallo | P0 |
| TC-E2E-03 | Operación liviana (ai-fill) sigue sync con pool | Respuesta síncrona, pool distribuye request | P1 |
| TC-E2E-04 | Notificación llega al frontend vía polling | Badge + toast actualizados | P1 |
| TC-E2E-05 | Multi-tenant isolation end-to-end | Ningún dato cruzado entre tenants | P0 |
| TC-E2E-06 | Catálogo con fotos parciales | Notificación indica resultado parcial | P1 |

#### 2.9 Dashboard de Trabajos IA (DJ)

| ID | Título | Resultado Esperado | Prioridad |
|---|---|---|---|
| TC-DJ-01 | Sección aiJobs accesible desde AdminDashboard | URL `/admin-dashboard?aiJobs` carga AiJobsDashboard | P0 |
| TC-DJ-02 | Tab "En Progreso" muestra jobs activos | Jobs queued y processing con progreso visible | P0 |
| TC-DJ-03 | Barra de progreso refleja progress_current/progress_total | Porcentaje correcto, animación en processing | P0 |
| TC-DJ-04 | Auto-refresh cada 8s actualiza progreso | Barra de progreso se actualiza sin reload manual | P0 |
| TC-DJ-05 | Posición en cola visible para jobs queued | "Posición #3" calculada correctamente | P1 |
| TC-DJ-06 | Polling se pausa en tab inactiva | No hay requests mientras `visibilityState === 'hidden'` | P2 |
| TC-DJ-07 | Tab "Historial" muestra jobs completados/fallidos paginados | 20 por página, ordenados por fecha DESC | P1 |
| TC-DJ-08 | Filtros en historial (tipo, estado) | Filtrado correcto por job_type y status | P2 |
| TC-DJ-09 | Job fallido muestra créditos devueltos | Texto "X créditos devueltos" visible | P1 |
| TC-DJ-10 | Tab "Créditos" muestra balance por action_code | Balance actualizado, link a addon store | P1 |
| TC-DJ-11 | GET /ai-jobs/summary retorna contadores correctos | active_jobs y recent_failures precisos | P1 |
| TC-DJ-12 | Worker actualiza progress_current/total durante ejecución | Columnas se actualizan en cada paso del job | P0 |
| TC-DJ-13 | Aislamiento multi-tenant: solo jobs del tenant | Tenant A no ve jobs de Tenant B | P0 |

---

### 3. Recomendaciones

#### 3.1 Aspectos faltantes en el plan (por prioridad)

1. **Claim atómico de jobs (CRÍTICO):** Usar función RPC con `SELECT FOR UPDATE SKIP LOCKED`, siguiendo el patrón de `claim_email_jobs` existente. Sin esto, si se escala a 2+ réplicas, habrá procesamiento duplicado de jobs.

2. **Doble-spend de créditos (CRÍTICO):** No hay protección contra race condition en la reserva de créditos. Se necesita: (a) constraint a nivel de BD que impida balance negativo, (b) lock por `accountId:actionCode` en el endpoint, o (c) `SELECT FOR UPDATE` en `assertAvailable`.

3. **Idempotencia en retry de catálogo (ALTO):** Si el job de catálogo falla después de insertar 7 de 10 productos, el retry crea duplicados. Se necesita almacenar `job_id` en cada producto creado y verificar duplicados en retry.

4. **Reserva combinada catálogo + fotos (MEDIO):** Cuando `include_photos=true`, reservar créditos de `ai_catalog_generation` + `ai_photo_product` al crear el job.

5. **Rate limiting por tenant en endpoints async (MEDIO):** El lock in-memory actual (`acquireGeneratingLock`) no aplica al flujo async. Verificar si ya existe un job `queued` o `processing` para ese tenant/action_code.

6. **Limpieza de notificaciones antiguas (BAJO):** Cron de purga para notificaciones leídas con más de 90 días.

7. **Posición en cola (BAJO):** Endpoint que indique posición estimada del job en la cola.

#### 3.2 Mejoras potenciales

1. **Dead letter queue:** Jobs que fallan `max_attempts` veces deberían marcarse para revisión manual por super admin.
2. **SSE alternativo al polling:** Server-Sent Events como mejora futura para notificaciones en tiempo real.
3. **Dashboard de super admin para jobs:** Panel con jobs en curso, fallidos, y métricas del pool de keys.
4. **Cancelación de jobs:** Permitir cancelar un job `queued` y recuperar créditos.
5. **TTL en jobs:** Jobs `queued` que llevan más de X horas sin procesarse deberían marcarse como `failed` con refund.

#### 3.3 Monitoring y Observabilidad

**Métricas críticas:**
- `ai_jobs_queued_count` (gauge) — Alerta si > 50
- `ai_jobs_processing_time_seconds` (histogram) — Por job_type
- `ai_jobs_failed_total` (counter) — Alerta si rate > 5/min
- `ai_key_pool_cooldowns_active` (gauge) — Alerta si = total_keys
- `ai_key_pool_inflight` (gauge por key) — Requests en vuelo
- `ai_credits_refunded_total` (counter) — Anomalía si > 20%
- `ai_notifications_undelivered` (gauge) — Jobs completed sin notificación

**Logging estructurado:** Cada operación del worker debe loguear `job_id`, `client_id`, `job_type`, `attempt`, `duration_ms`, `key_index` en formato JSON.

**Alerta de pool degradado:** Si más de la mitad de las keys están en cooldown por más de 5 minutos, enviar alerta vía `FounderNotificationsService` (WhatsApp).

**Reconciliación periódica:** Cron diario que verifique:
- Jobs `completed` sin registro de consumo de créditos
- Jobs `failed` sin registro de refund
- Jobs `processing` con `started_at` > 1 hora

#### 3.4 Preocupaciones de Performance

1. **Índice parcial en `ai_generation_jobs`:** Excelente para queued. Considerar archivar jobs completados/fallidos a tabla histórica.
2. **Polling de notificaciones bajo carga:** 100 tenants × 4 polls/min = 400 queries/min. El índice parcial cubre esto eficientemente.
3. **Promise.allSettled en el worker:** Si 3 jobs de catálogo generan fotos, son potencialmente 30 llamadas a OpenAI limitadas por el semáforo. El tick queda bloqueado hasta que todos terminen.
4. **Buffer de fotos en memoria:** Cada foto ~1-3MB base64. Si 3 jobs generan fotos simultáneamente (30 fotos), son ~90MB en RAM. Monitorear uso de memoria.
