# Resumen Quincenal — 13 al 27 de Marzo 2026

**Periodo**: 13/03/2026 – 27/03/2026
**Alcance**: API, Admin, Web, E2E, Docs
**Total de changelogs**: 45+ entradas

---

## Highlights de la quincena

### 1. Sistema de IA Monetizable (AI Credits)
El cambio mas grande del periodo. Se construyo un sistema completo de creditos IA con monetizacion por feature.

- **AI Credits + Store DNA + Column Mapping** (18/03): Pool de creditos por action_code, Store DNA como contexto maestro para todas las features IA, mapeo inteligente de columnas para importacion de catalogo, dashboard de pricing para super admin.
- **AI Credits Universal Pool** (22/03): Migracion de 14 pools aislados por feature a un pool universal unico. Vista `account_ai_credit_pool_view`, packs unificados.
- **AI Async + Notificaciones + Key Pool** (19/03): Generacion asincrona con cola de jobs, pool de keys OpenAI con cooldown, notificaciones push al completar.
- **AI Brand Colors** (22/03): Las imagenes generadas ahora respetan la paleta de colores real de la tienda.
- **AI CSS Generation** (20/03): El admin describe estilos en lenguaje natural y Claude genera CSS para revision.
- **AI Photo Auto-Save** (27/03): Las fotos IA se guardan directo en tenant_media (permanente), no en storage temporal.
- **Sprint AI Pro M1-M11** (25/03): PlanLimitsGuard en 6 endpoints, provider Anthropic para tier Pro, cost tracking USD, contexto enriquecido para FAQs.

### 2. Template Unification (Design System)
Reescritura completa del sistema de templates para eliminar duplicacion y habilitar el Design Studio.

- **T1-T6 Component Unification** (19/03): ProductCard, FAQ, Contact, Footer, Services, ProductCarousel — cada uno reemplaza 3-8 implementaciones separadas con variants lazy-loaded.
- **Wiring + Activation** (19/03): 5 componentes unificados activados en pipeline de renderizado.
- **Hardening Post-Unification** (20/03): 5 bugs criticos de produccion corregidos (CSS overrides, cron borrando CSS custom, fontKey validation).
- **CSS Cascade Fix** (21/03): Variables `--nv-*` propagandose correctamente al header, eliminacion de re-fetch cascade.
- **Design Studio Fases A-B-C** (21/03): FontSelector en onboarding, tab "Editar con IA" con 3 modos de edicion.

### 3. CRM Interno + Marketing OS
Dos sistemas nuevos que reemplazan procesos manuales.

- **CRM Phase 1** (16/03): Migracion de BD, modulo NestJS con 15 endpoints, dashboard CRM completo en Admin. Hardening posterior con DTO validado, batch processing, guard de concurrencia.
- **Marketing OS** (17/03): Sistema completo de marketing automatizado (reemplaza agencias TOU/FLY/VUZZ). Reporting IA, auto-optimizacion, publicacion de creatives. DB + API + Admin + Web + n8n.

### 4. Churn Lifecycle + Reactivacion
Pipeline completo anti-churn desde cancelacion hasta reactivacion.

- **Churn Lifecycle Fase 1** (26/03): Tabla `subscription_cancel_log`, grace periods dinamicos por plan, auditoria de proceso de cancelacion.
- **Subscription Pause/Downgrade** (26/03): Nuevos endpoints pause/resume/downgrade con guards Builder + Client, integracion MP, auto-pause de tienda. UI completa con modales y eligibility checks.
- **Reactivation Flow** (25/03): Flujo end-to-end para tenants cancelados — enrichment de sesion con `subscription_status`, redirect automatico a `/reactivate`, nueva ReactivationPage, creacion de nuevo preapproval MP, forzar reactivacion desde super admin.

### 5. Support Tickets + AI Pipeline
Sistema de soporte con analisis IA integrado.

- **Support Tickets AI Pipeline** (23/03): Analisis con Claude, pipeline de desarrollo (open/dev/qa/done), chat de intake con auto-diagnostico, descomposicion de tareas, workflow de aprobacion.
- **Security + Cancel + Toggle + Monthly Limits** (23/03): Seguridad reforzada, toggle de acceso por cuenta, limites mensuales configurables.

### 6. Multi-LATAM + Custom Domain
Expansion internacional y dominios personalizados.

- **Country/Currency Hardening** (15/03): Captura de `mp_site_id` en OAuth, mapeo completo de 7 paises, seed de fee tables LATAM.
- **Custom Domain Fase 3-4** (16/03): Audit trail, Domain Center en tenant dashboard, notificaciones por email.
- **Onboarding Multi-LATAM Admin CRUD** (26/03): 8 endpoints admin para subdivisions y fiscal categories (149 subdivisions, 24 categorias fiscales).

### 7. Media + Imagenes
Unificacion del sistema de imagenes.

- **Unified Media Registration** (24/03): Productos ahora registran imagenes en tenant_media al crear/editar. Metodo `registerAndLink()`, seguridad multi-tenant reforzada.
- **Image Migration** (26/03): Migracion batch de imagenes existentes a tenant_media. Idempotente, extrae storage keys de URLs de Supabase.

---

## Metricas de la quincena

| Metrica | Valor |
|---------|-------|
| Changelogs registrados | 45+ |
| Features nuevas | ~25 |
| Bugfixes | ~12 |
| Refactors / Hardening | ~8 |
| Apps tocadas | API, Admin, Web, E2E, Docs |
| QA issues resueltos | 63/76 (83%) del reporte Sprint 1-4 |
| Tablas de BD nuevas/modificadas | ~15+ |
| Endpoints nuevos | ~40+ |

---

## Planes activos referenciados

| Plan | Estado | Progreso estimado |
|------|--------|-------------------|
| `PLAN_CHURN_LIFECYCLE` | En ejecucion | Fase 1-2 completas, Fase 3 (reactivacion) completa |
| `PLAN_TEMPLATE_COMPONENT_UNIFICATION` | Completado | T1-T16 + wiring + hardening |
| `PLAN_CRM_INTERNAL_SUPERADMIN` | Phase 1 completo | Backend + DB + UI base |
| `PLAN_SUPPORT_TICKETS_AI_PIPELINE` | En ejecucion | AI analysis + pipeline + intake funcional |
| `PLAN_AI_PRODUCT_FULL_GENERATION` | Sprints 1-5 completos | PlanLimitsGuard, Anthropic provider, cost tracking |
| `PLAN_UNIFIED_MEDIA_REGISTRATION` | Completado | Registration + migration + auto-save |
| `PLAN_STORE_DESIGN_PARITY_AND_UNIFICATION` | Completado | Fases A-B-C + hardening |
| `PLAN_DYNAMIC_FOOTER_GENERATION` | Fase 1 completa | Backend + DB, falta frontend |
| `PLAN_ONBOARDING_DINAMICO_MULTILATAM` | En ejecucion | Admin CRUD completado |

---

## Deuda tecnica resuelta

- **P0-P2 Tech Debt** (15/03): 6 tests preexistentes corregidos, features pendientes implementadas.
- **QA Report Sprint 1-4** (18/03): 63 de 76 issues resueltos (5 bloqueantes, 14 CSS mobile, 23 i18n).
- **AI Audit** (23/03): 2 bugs criticos corregidos — double-charging en catalogo async y consume-before-AI en column mapping.
- **E2E Audit** (26/03): 100% de tests E2E pasando.

---

## Proximos pasos sugeridos

1. **Churn Lifecycle Fase 3**: Emails automaticos de win-back, dashboard de metricas de churn.
2. **CRM Phase 2**: Automatizaciones, scoring de leads, integracion con Marketing OS.
3. **Support AI**: Respuestas automaticas para tickets comunes.
4. **Dynamic Footer**: Frontend para configuracion de footer personalizado.
5. **Multi-LATAM**: Expansion a nuevos paises con fiscal config completa.
