# Sprint 5 AI Pro — M11

**Fecha:** 2026-03-25
**Plan:** `PLAN_AI_PRO.md` Sprint 5
**Estado:** M11 implementado, M12 pendiente (n8n AI Closer — no es código API)

---

## M11: Mejorar prompt de AI FAQ con contexto completo de tienda

### Problema
El prompt de FAQ en modo contexto solo recibía: servicios, categorías, contacto y nombre/descripción de la tienda. Faltaban datos clave que los compradores preguntan: envíos (costos, zonas, tiempos), medios de pago (cuotas, MercadoPago), y rubro/industria.

### Solución
1. **Prompt enriquecido**: `FAQ_CONTEXT_SYSTEM_PROMPT` reescrito con temas a cubrir (envío, pagos, cambios, productos, compra) y regla "entre 5 y 10 preguntas".
2. **`FaqContextInput` extendido** con 4 campos nuevos:
   - `industry` — rubro de la tienda (desde `nv_accounts.industry`)
   - `shippingZones` — zonas de envío con nombre, costo y tiempo estimado
   - `shippingIntegrations` — integraciones activas (Andreani, OCA, etc.)
   - `paymentInfo` — MercadoPago conectado, cuotas habilitadas, máx cuotas, débito
3. **`buildFaqContextPrompt()` extendido**: Renderiza secciones de envío y pagos en el prompt.
4. **`generateFaqsFromContext()` extendido**: 7 queries paralelas (antes 4) + query a Admin DB para industry/mp_connected.

### Datos que ahora alimentan las FAQs
| Dato | Tabla | BD |
|------|-------|----|
| Servicios | `services` | Backend |
| Contacto | `contact_info` | Backend |
| Categorías | `categories` | Backend |
| Zonas de envío | `shipping_zones` | Backend |
| Integraciones envío | `shipping_integrations` | Backend |
| Config pagos | `client_payment_settings` | Backend |
| Rubro + MP conectado | `nv_accounts` | Admin |

### Archivos modificados
- `api/src/ai-generation/prompts/index.ts` — prompt reescrito, FaqContextInput extendido, buildFaqContextPrompt con secciones envío/pagos
- `api/src/ai-generation/ai-generation.service.ts` — generateFaqsFromContext con 7+1 queries

---

## M12: AI Closer (pendiente)
M12 requiere configuración en n8n (workflow `wf-inbound-v2.json`, playbook, guardrails). No es código API.

---

## Validación
- TypeScript: `tsc --noEmit` OK
- Build: `npm run build` OK
- Tests: 106/106 suites, 1033/1035 tests OK (2 skipped)
