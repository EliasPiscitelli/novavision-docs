# Archivos Recomendados para el Proyecto Claude "NovaVision"

## Estrategia

Claude Projects tiene un límite de ~200K tokens en archivos. Priorizamos documentos
que dan contexto **denso y reutilizable** (arquitectura, contratos, schemas) sobre
documentos volátiles (changelogs individuales, audit details).

---

## Tier 1 — Esenciales (subir primero)

Estos 6 archivos dan el 80% del contexto necesario:

| # | Archivo | Tamaño aprox | Justificación |
|---|---------|-------------|---------------|
| 1 | `architecture/database-schema-reference.md` | ~15K | Tablas de ambas DBs, relaciones, datos reales |
| 2 | `architecture/ROUTING_RULES.md` | ~8K | Multi-tenant resolution completa |
| 3 | `architecture/config-source-of-truth.md` | ~6K | Flujo de configuración del storefront |
| 4 | `architecture/PLANS_LIMITS_ECONOMICS.md` | ~12K | Planes, pricing, quotas, modelo financiero |
| 5 | `architecture/ENV_INVENTORY.md` | ~10K | Todas las variables de entorno por app |
| 6 | `architecture/n8n-outreach-system-v2.md` | ~55K | Audit completo de n8n, state machine, bugs |

**Total Tier 1: ~106K tokens**

---

## Tier 2 — Alta prioridad (si queda espacio)

| # | Archivo | Tamaño aprox | Justificación |
|---|---------|-------------|---------------|
| 7 | `architecture/system_flows_and_persistence.md` | ~20K | Flujos de theme, provisioning, checkout |
| 8 | `architecture/LATAM_INTERNATIONALIZATION_PLAN.md` | ~15K | Hardcodes por país, plan de internacionalización |
| 9 | `n8n-workflows/docs/03-WF-INBOUND-ia-conversacional.md` | ~8K | AI Closer spec detallada |
| 10 | `architecture/subscription-hardening-plan.md` | ~10K | Pipeline de subscripciones MP |

**Total Tier 1+2: ~159K tokens**

---

## Tier 3 — Útil pero opcional

| # | Archivo | Justificación |
|---|---------|---------------|
| 11 | `audits/2026-03-16-custom-domain-system-audit.md` | P0/P1 bugs de custom domains |
| 12 | `runbooks/claude-code-por-fases.md` | Workflow recomendado con Claude Code |
| 13 | `plans/PLAN_ADDON_STORE_HARD_ENTITLEMENTS.md` | Diseño del addon store |
| 14 | `runbooks/go-live-argentina.md` | Checklist pre-lanzamiento |

---

## Archivos que NO subir

- **Changelogs individuales** (`changes/`) — Son 276+, volátiles, mejor consultar ad-hoc
- **JSONs de n8n** (`wf-*.json`) — Demasiado grandes y mejor parseados con código
- **Archivos de archivo** (`archive/`) — Documentación obsoleta
- **Legal/Marketing** — No aportan al contexto técnico
- **.env reales** — NUNCA subir secrets (usar ENV_INVENTORY.md que es sanitizado)

---

## Cómo subir

1. En claude.ai → Proyecto "NovaVision" → Panel derecho → "Archivos" → "+"
2. Subir los archivos del Tier 1 primero
3. Verificar que no se exceda el límite
4. Agregar Tier 2 si hay espacio

Los archivos están en: `~/Documents/NovaVision/novavision-docs/`
