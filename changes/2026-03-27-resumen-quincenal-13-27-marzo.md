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

## Planes activos referenciados (validado contra planes reales)

| Plan | Estado | Detalle |
|------|--------|---------|
| `PLAN_TEMPLATE_COMPONENT_UNIFICATION` | **Completado** | T0-T6 + wiring + hardening + deployment. 8/8 sub-fases. |
| `PLAN_SUPPORT_TICKETS_AI_PIPELINE` | **Completado** | 4/4 fases: migracion SQL, backend, admin frontend, web storefront. |
| `PLAN_UNIFIED_MEDIA_REGISTRATION` | **Completado** | 4/4 fases: migraciones, helpers, integracion en productos, backwards compat. |
| `PLAN_CRM_INTERNAL_SUPERADMIN` | En ejecucion | F1 completa + F2 parcial (health cron + alertas n8n). Faltan: automatizaciones core, tareas overdue, vistas especializadas, RBAC (F2-F3). |
| `PLAN_CHURN_LIFECYCLE` | En ejecucion | 6/17 items. Hecho: cancel_log, grace dinamico, reactivacion, pausa, downgrade, lifecycle churned. Faltan: exit survey, dashboard churn, win-back emails, pre-churn deteccion, archivado frio, analytics (11 items). |
| `PLAN_STORE_DESIGN_PARITY_AND_UNIFICATION` | Avanzado | Trabajo extenso (12 changelogs): variant registry, draft/apply, grouped props, public parity. Pendiente confirmar: persistencia componentKey en API, normalizacion plan keys, tipos compartidos cross-app. |
| `PLAN_DYNAMIC_FOOTER_GENERATION` | En ejecucion | 1/3 fases. Hecho: backend + DB + endpoints. Faltan: F2 Admin UI (FooterConfigSection), F3 Storefront (SectionRenderer + FooterParts dinamicos). |
| `PLAN_ONBOARDING_DINAMICO_MULTILATAM` | En ejecucion | Fase A completa + Fase B parcial (1.5 de 5 fases). Faltan: B parcial (business-info refactor), C (frontend dinamico), D (suscripciones multi-pais), E (captcha + rate limiting). |
| `PLAN_AI_PRODUCT_FULL_GENERATION` | Apenas iniciado | Solo Bloque 3A (migracion imagenes). Faltan: B1 (ai-fill full product), B2 (ProductModal AI), B4 (ServiceSection/Logo/Banners AI), B5 (Tours IA), B6 (Pricing UI). |

**Nota**: Los changelogs Sprint AI Pro (M1-M11) corresponden a un plan separado no listado aqui. Ese plan tiene 8/12 milestones completados.

---

## Deuda tecnica resuelta

- **P0-P2 Tech Debt** (15/03): 6 tests preexistentes corregidos, features pendientes implementadas.
- **QA Report Sprint 1-4** (18/03): 63 de 76 issues resueltos (5 bloqueantes, 14 CSS mobile, 23 i18n).
- **AI Audit** (23/03): 2 bugs criticos corregidos — double-charging en catalogo async y consume-before-AI en column mapping.
- **E2E Audit** (26/03): 100% de tests E2E pasando.

---

## Pendientes concretos por prioridad

### Alta prioridad (bloqueantes de negocio)
1. **Onboarding Multi-LATAM Fases C-E**: Frontend dinamico, suscripciones multi-pais, captcha. Bloquea expansion a nuevos paises.
2. **Churn Lifecycle — Exit survey + Win-back emails**: Items de retencion directa de clientes (11 items pendientes).
3. **AI Product Full Generation — Bloques 1-2**: ai-fill full product + ProductModal AI. Core de la propuesta de valor IA.

### Media prioridad (mejoras operativas)
4. **CRM Fases 2-3**: Automatizaciones, tareas overdue, RBAC, dashboard KPIs.
5. **Dynamic Footer Fases 2-3**: Admin UI + storefront. Feature visible para tenants.
6. **Store Design**: Validar persistencia componentKey y normalizacion plan keys.

### Baja prioridad (optimizacion)
7. **Churn Lifecycle items 4.x**: Archivado frio, money-back, free tier, analytics dashboard.
8. **AI Pro milestones restantes**: M5 (AI Onboarding Coach), M6 (Discoverability), M10 (n8n reporting), M12 (AI Closer).
