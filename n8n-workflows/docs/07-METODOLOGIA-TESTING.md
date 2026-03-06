# Metodología de Testing — Outreach Pipeline

## Respuesta corta

Las pruebas se realizaron con **tests unitarios usando Jest y datos ficticios (mocks)**, no activando los workflows reales con datos de producción. Se validó la lógica del servicio NestJS de forma aislada, sin llamadas reales a WhatsApp, Supabase ni n8n.

---

## ¿Qué se testeó?

Se creó un archivo de tests completo en:
```
apps/api/src/outreach/outreach.service.spec.ts
```

Contiene **55 tests** organizados en **8 grupos** que cubren todas las funcionalidades del `OutreachService`:

| Grupo | Tests | Qué valida |
|-------|:-----:|-----------|
| `claimLeads — seed` | 4 | Selección de leads NEW, batch_size, errores de DB |
| `claimLeads — followup` | 1 | Selección de leads CONTACTED/IN_CONVERSATION |
| `commitAttempt` | 7 | Envío WA (template + texto plano), transiciones de estado, logging, skip sin credenciales |
| `buildMessageContext & renderMessageTemplate` | 2 | Resolución de placeholders, fallbacks |
| `evaluateOffer` | 4 | Sistema de cupones (habilitado/deshabilitado, stage, max por lead) |
| `commitOffer` | 2 | Inserción de oferta, idempotencia |
| `bridgeOnboarding` | 2 | Llamada a onboarding/builder/start, manejo de error |
| `handleWhatsAppWebhook` | 4 | Webhook inbound, firma HMAC, deduplicación |
| State machine (exhaustivo) | 28 | 20 transiciones válidas + 8 inválidas |
| **Total** | **55** | |

---

## ¿Cómo se hicieron las pruebas?

### Técnica: Unit Testing con Mocks

Se usó el framework de testing de NestJS (`@nestjs/testing`) junto con Jest para crear un módulo de testing aislado:

```typescript
const module: TestingModule = await Test.createTestingModule({
  providers: [
    OutreachService,
    {
      provide: DbRouterService,
      useValue: { getAdminClient: () => dbMock },
    },
    {
      provide: ConfigService,
      useValue: { get: configGet },
    },
  ],
}).compile();
```

### ¿Qué se mockeó?

#### 1. Base de datos (Supabase)
Se creó una función `createChainMock()` que simula el query builder de Supabase:

```typescript
function createChainMock(resolveWith: { data: any; error: any }) {
  const chain: any = {};
  // Cada método devuelve el chain (chainable)
  for (const m of ['select', 'insert', 'update', 'delete', 'upsert',
    'eq', 'in', 'or', 'lte', 'gte', 'gt', 'lt', 'order', 'limit', 'is']) {
    chain[m] = jest.fn().mockReturnValue(chain);
  }
  // Métodos terminales
  chain.single = jest.fn().mockResolvedValue(resolveWith);
  chain.maybeSingle = jest.fn().mockResolvedValue(resolveWith);
  chain.then = (resolve) => resolve(resolveWith);
  return chain;
}
```

Esto permite controlar qué devuelve cada query. Por ejemplo:
- `createChainMock({ data: [leadSeed], error: null })` → simula que hay un lead
- `createChainMock({ data: null, error: { message: 'timeout' } })` → simula error de DB
- `createChainMock({ data: [], error: null })` → simula resultado vacío

#### 2. WhatsApp API (Meta Graph API)
Se usó `jest.spyOn(global, 'fetch')` para interceptar todas las llamadas HTTP:

```typescript
fetchSpy = jest.spyOn(global, 'fetch').mockResolvedValue({
  ok: true,
  status: 200,
  json: async () => ({
    messages: [{ id: 'wamid.test123456' }],
  }),
} as Response);
```

Después de cada test se verifica:
- Que se llamó a la URL correcta de Meta
- Que el body contiene el template correcto
- Que los parámetros dinámicos se resolvieron bien

#### 3. Variables de entorno
Se mockeó `ConfigService.get()` para devolver valores controlados:

```typescript
configGet = jest.fn((key) => ({
  WHATSAPP_PHONE_NUMBER_ID: '889890894207625',
  WHATSAPP_TOKEN: 'test-wa-token',
  OUTREACH_SENDER_NAME: 'Eli de NovaVision',
  OUTREACH_CTA_LINK: 'https://admin.novavision.app',
  // ...
}[key]));
```

### Datos ficticios utilizados

Se definieron 3 personas demo que representan leads en distintas etapas del pipeline:

| Persona | Status | Nombre | Email | Teléfono | Escenario |
|---------|--------|--------|-------|----------|-----------|
| Seed | `NEW` | María García | maria@tienda.com | 5491155551234 | Lead nuevo, primer contacto |
| Followup | `CONTACTED` | Carlos López | carlos@bakery.com | 5491166665678 | Lead contactado, pendiente de seguimiento |
| Qualified | `QUALIFIED` | Ana Ruiz | ana@ruiz.com | 5491177779012 | Lead calificado, potencial onboarding |

Y un cupón demo:

| Campo | Valor |
|-------|-------|
| Código | NOVA50 |
| Tipo | percent |
| Valor | 50 |
| Max usos | 100 |
| Usos actuales | 5 |

---

## ¿Qué NO se testeó con este método?

| Aspecto | Cubierto | Cómo validar |
|---------|----------|-------------|
| Lógica del servicio NestJS | ✅ | Tests unitarios (55 tests) |
| Máquina de estados (transiciones válidas/inválidas) | ✅ | 28 tests exhaustivos |
| Rendering de templates y placeholders | ✅ | Tests de renderización |
| Firma HMAC del webhook | ✅ | Tests con crypto real |
| Sistema de cupones (evaluación + idempotencia) | ✅ | 6 tests |
| Workflows de n8n end-to-end | ❌ | Requiere n8n corriendo + DB real |
| Envío real por WhatsApp | ❌ | Requiere token activo + número verificado |
| Queries SQL reales (Supabase) | ❌ | Requiere DB con datos |
| Respuesta real de GPT-4.1-mini | ❌ | Requiere OpenAI key válida |
| Flujo completo seed → followup → inbound → onboarding | ❌ | E2E con n8n + API + DB |

---

## Resultado de la ejecución

```
$ npm test -- --testPathPattern=outreach.service.spec

 PASS  src/outreach/outreach.service.spec.ts
  OutreachService
    claimLeads — seed
      ✓ devuelve leads NEW y los marca CONTACTED
      ✓ devuelve vacío cuando no hay leads NEW
      ✓ lanza BadRequestException si hay error de DB
      ✓ respeta batch_size hasta máximo 20
    claimLeads — followup
      ✓ devuelve leads CONTACTED/IN_CONVERSATION con followup pendiente
    commitAttempt
      ✓ envía WA template con parámetros dinámicos y actualiza lead
      ✓ rechaza transición inválida (NEW → QUALIFIED)
      ✓ rechaza transición inválida (WON → CONTACTED)
      ✓ permite transición válida (CONTACTED → IN_CONVERSATION)
      ✓ permite transición COLD → CONTACTED (reactivación)
      ✓ lanza NotFoundException si lead no existe
      ✓ envía WA texto plano (sin template)
      ✓ skip WA si no hay credenciales
    buildMessageContext & renderMessageTemplate
      ✓ resuelve placeholders con datos del lead y params
      ✓ usa fallbacks cuando faltan datos del lead
    evaluateOffer
      ✓ retorna offer_allowed: true cuando hay cupón disponible
      ✓ rechaza si cupones están deshabilitados
      ✓ rechaza si stage no está permitido
      ✓ rechaza si lead ya tiene max cupones
    commitOffer
      ✓ inserta oferta nueva y actualiza current_uses
      ✓ es idempotente si la oferta ya existe
    bridgeOnboarding
      ✓ llama a onboarding/builder/start y actualiza lead a ONBOARDING
      ✓ lanza BadRequestException si onboarding falla
    handleWhatsAppWebhook
      ✓ procesa mensaje inbound válido y despacha a n8n
      ✓ rechaza firma inválida
      ✓ rechaza si WHATSAPP_APP_SECRET no está configurado
      ✓ deduplica mensajes por wamid
    state machine transitions (exhaustivo)
      ✓ permite NEW → CONTACTED
      ✓ permite NEW → DISCARDED
      ✓ permite CONTACTED → IN_CONVERSATION
      ... (20 transiciones válidas + 8 inválidas)

Tests:       55 passed, 55 total
Time:        ~3s
```

---

## ¿Y los workflows de n8n?

Los 6 workflows de n8n (`WF-SEED`, `WF-FOLLOWUP`, `WF-INBOUND`, `WF-HYGIENE`, `WF-ONBOARDING-BRIDGE`, `WF-WEEKLY-REPORT`) **NO fueron testeados activándolos directamente**. Están desplegados en Railway con estado **activo** pero requieren validación E2E cuando:

1. La credencial de Admin DB esté verificada (conexión SSL OK)
2. El webhook de Meta esté configurado (para WF-INBOUND)
3. Las variables de entorno de Railway estén completas
4. Haya leads reales o de prueba en `outreach_leads`

### Plan de validación E2E sugerido

| Workflow | Cómo validar | Prerequisito |
|----------|-------------|-------------|
| WF-SEED | Insertar 1 lead `NEW` en DB → esperar Cron 10:00 → verificar status `CONTACTED` | DB credential OK |
| WF-FOLLOWUP | Tener lead `CONTACTED` con `next_followup_at < now()` → esperar Cron 11:00/17:00 | DB credential OK |
| WF-INBOUND | Enviar mensaje WA al número → verificar que llega a n8n y genera respuesta AI | Meta webhook + OpenAI credential |
| WF-HYGIENE | Insertar leads con datos inválidos → esperar Cron 06:00 → verificar limpieza | DB credential OK |
| WF-ONBOARDING-BRIDGE | Tener lead cuyo email matchea un `nv_onboarding` → esperar Cron /2h | DB credential OK + onboarding existente |
| WF-WEEKLY-REPORT | Esperar Lunes 12:00 UTC → verificar que llega WA con reporte | WA token + SALES_ALERT_PHONE |

---

## Archivos relevantes

| Archivo | Contenido |
|---------|-----------|
| [outreach.service.spec.ts](apps/api/src/outreach/outreach.service.spec.ts) | 55 tests unitarios |
| [outreach.service.ts](apps/api/src/outreach/outreach.service.ts) | Servicio principal testeado |
| [jest.config.ts](apps/api/jest.config.ts) | Configuración Jest (ts-jest) |
