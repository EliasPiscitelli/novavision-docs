# Pricing Bible — NovaVision

**Fecha:** 2026-03-16
**Source of truth:** Tabla `plans` en Admin DB
**Regla:** Todo material externo (landing, ads, propuestas, docs) lee de este documento. Si hay contradicción, este gana.

---

## Precios confirmados (2026-03-16)

| Plan | Mensual | Anual | Setup | CTA |
|------|---------|-------|-------|-----|
| **Starter** | $20 USD | $200 USD | $0 | Empezar gratis |
| **Growth** | $60 USD | $600 USD | $0 | Empezar gratis |
| **Enterprise** | $390 USD | $3,500 USD | Consultar (caso a caso) | Consultar |

**Nota:** La DB (plans table) todavía tiene Enterprise a $250/mo — requiere migración para unificar a $390/mo.

---

## Planes activos

### Starter — $20/mes | $200/año

**Para:** Emprendedores que quieren validar su tienda online.

| Límite | Valor |
|--------|-------|
| Productos | 300 |
| Imágenes por producto | 1 |
| Órdenes/mes | 200 |
| Storage | 2 GB |
| Egress/mes | 50 GB |
| Banners activos | 3 |
| Custom domain | No (*.novavision.lat) |
| Infraestructura | Compartida |

**Features incluidas:**
- Panel autoadministrable (productos, categorías, pedidos)
- Mercado Pago integrado (OAuth, un click)
- 8 templates + 14 paletas
- SEO técnico (sitemap, robots, canonical, JSON-LD, OG tags)
- Envíos manuales (sin carriers API)
- Logo, banners, FAQs, servicios, redes sociales, contacto
- Reviews y preguntas por producto
- Favoritos/wishlist
- Generación de catálogo asistida por IA

**No incluye:**
- Dominio propio
- Cupones de descuento
- Tracking per-tenant (GA4/GTM/Pixel)
- SEO AI Autopilot
- Variantes/option sets
- Guías de talles
- Carriers API (Andreani/OCA/Correo Argentino)
- Configuración avanzada de pagos

**Soporte:** Email, 48h SLA

**Overages:** Hard limit (no se cobra extra, se bloquea)

---

### Growth — $60/mes | $600/año

**Para:** Negocios en crecimiento que necesitan herramientas avanzadas.

**Recomendado** — Este es el plan que comunicamos como "Recomendado" en la landing.

| Límite | Valor |
|--------|-------|
| Productos | 2,000 |
| Imágenes por producto | 4 |
| Órdenes/mes | 1,000 |
| Storage | 10 GB |
| Egress/mes | 200 GB |
| Banners activos | 8 |
| Custom domain | Sí |
| Infraestructura | Compartida |

**Todo lo de Starter +**
- Dominio propio con SSL
- Cupones de descuento (%, monto fijo, free shipping, mínimo de compra)
- Option sets / variantes (talles, colores, materiales)
- Guías de talles
- Carriers API: Andreani, OCA, Correo Argentino + zonas + free shipping threshold
- SEO AI Autopilot (generación por IA, auditoría, créditos, locks manuales)
- Tracking per-tenant: GA4 + GTM + Meta Pixel con eventos ecommerce automáticos
- Google Search Console verification
- Redirects 301/302
- Panel de conexiones con guías paso a paso
- Configuración avanzada de pagos (recargos por cuota, exclusión de medios, días de acreditación)
- Analytics básico
- User management
- 6 paletas premium adicionales (total: 20)
- AI Import Wizard (50 items/batch, 5 batches/día)

**Soporte:** Email/WhatsApp prioritario, 24h SLA

**Overages:** Soft cap — se cobra extra:
- Órdenes: $0.015 USD/extra
- Egress: $0.08 USD/GB extra
- API requests: $0.30 USD/1k extra
- Storage: $0.021 USD/GB-mes extra

---

### Enterprise — $390/mes | $3,500/año (consultar)

**Para:** Empresas con catálogo grande, integraciones o volumen alto.

| Límite | Valor |
|--------|-------|
| Productos | 50,000 |
| Imágenes por producto | 8 |
| Órdenes/mes | 20,000 |
| Storage | 100 GB |
| Egress/mes | 1,024 GB (1 TB) |
| Banners activos | 100 |
| Custom domain | Sí |
| Infraestructura | **Dedicada** (Supabase + Railway propios) |

**Todo lo de Growth +**
- Base de datos dedicada (aislamiento total)
- SEO Redirects 301 (exclusivo Enterprise)
- AI Import Wizard (200 items/batch, 20 batches/día)
- Todos los add-ons premium
- Desarrollos custom cotizados aparte

**Soporte:** Canal directo, 12h SLA, soporte premium

**Setup:** Cotización caso a caso ($500-$2,000 orientativo según complejidad). Incluye discovery, migración, configuración avanzada, capacitación.

**Overages:** Negociables

---

## Ciclos de facturación

| Ciclo | Descuento | Ahorro |
|-------|-----------|--------|
| Mensual | — | — |
| Anual | 2 meses gratis (~17%) | Starter $40, Growth $120, Enterprise $500 |

---

## Medios de pago

- **Cobro:** Mercado Pago (PreApproval recurrente)
- **Moneda de referencia:** USD
- **Moneda local:** ARS al tipo de cambio del día (vía FxService)
- **Sin permanencia:** Cancelación inmediata sin penalidad
- **Trial:** 0 días actualmente (configurable por plan)

---

## Modelo económico

- **Comisión por venta:** 0% — SIEMPRE. Es el diferencial #1.
- **Margen bruto:** ≥76% en todos los planes
- **Revenue streams:** Suscripción + Addon Store + Overages (Growth+) + Setup Enterprise

---

## Sistema de cupones (plataforma)

Cupones pre-seeded para onboarding de suscripciones:

| Código | Tipo | Descuento | Cupos | Aplica a |
|--------|------|-----------|-------|----------|
| WELCOME30 | % | 30% | Ilimitado | Primer mes, cualquier plan |
| STARTER50 | % | 50% | 200 | Primer mes, solo Starter |
| GROWTH20 | % | 20% | 100 | Primeros 3 meses, solo Growth |
| FREEMONTH | % | 100% | 150 | Primer mes gratis, cualquier plan |
| LAUNCH2026 | Fijo | $10 off | 500 | Primer mes (expira 2026-06-30) |
| ANNUAL15 | % | 15% | Ilimitado | Primer pago anual |
| AMIGO25 | % | 25% | Ilimitado | Primer mes (referidos) |
| ENTERPRISE40 | % | 40% | 50 | Primer mes, solo Enterprise |
| BLACKFRIDAY | % | 60% | 300 | Primer mes (inactivo por defecto) |
| TRIAL3M | % | 100% | 100 | 3 meses gratis, solo Starter |
| SETUP0 | Fijo | $50 off | 200 | Setup fee |
| PARTNER10 | % | 10% | Ilimitado | Recurrente (partners) |

---

## Addon Store

| Addon | Precio | Tipo | Billing |
|-------|--------|------|---------|
| SEO AI Pack 50 créditos | $5 | Consumible | One-time |
| SEO AI Pack 100 créditos | $9 | Consumible | One-time |
| +10 GB storage | $5/mes | Uplift | Mensual |
| Custom homepage design | Cotización | Servicio | One-time |

---

## Nota sobre Enterprise productizado

Enterprise se vende como implementación profesional sobre plataforma probada, NO como desarrollo a medida. Ver `ENTERPRISE_PRODUCTIZED_OFFER.md` para detalles del proceso comercial.

**Componentes Enterprise:**
1. **Setup (pago único):** $500-$2,000 según complejidad
2. **Suscripción mensual:** Precio según tabla de arriba
3. **Extras:** Cotización aparte (integraciones ERP, módulos custom, migración compleja)
