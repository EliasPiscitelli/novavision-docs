# Nuevas implementaciones dashboard admin NovaVision

- Autor: GitHub Copilot (GPT-5-Codex)
- Fecha: 2025-11-24
- Alcance: Auditoría profunda del panel admin, dependencias técnicas y plan maestro de control de costos.
- Fuentes analizadas: apps/admin/src/App.jsx, rutas completas de `pages/AdminDashboard`, `ClientDetails`, `AdminInbox`; componentes `components/**/*`, servicios `service/*` y `utils/*`; hooks `useDashboardMetrics`, `useUsageSummary`; Edge Functions documentadas (`supabase/functions/*`); scripts en `docs/sql/` y documentación adjunta.

## 1. Panorama general del dashboard

- **Arquitectura UI:** Vite + React con router protegido, `styled-components`, provider de toast y listeners de auth (`AuthListener`, `ProtectedRoute`). Se apoya en supabase-js para ambas bases (hub admin + multicliente) controlando credenciales vía `supabaseClient.jsx` y `window.__RUNTIME__`.
- **Backends consumidos:**
  - Supabase Admin: RPC `dashboard_metrics`, tablas `clients`, `clients_deleted_summary`, `payments`, `invoices`, storage buckets para media y archivos de lead quiz.
  - Backend Railway (API multicliente): endpoints `/admin/metrics/summary`, `/admin/metrics/sync` (consumo/costos), integraciones Mercado Pago.
  - Edge Functions Supabase: `admin-create-client`, `admin-delete-client`, `admin-wa-*` (inbox), más utilitarias documentadas en `supabase/functions`.
- **Dominios operativos cubiertos:** métricas globales, costos y consumo, gestión de clientes y estados, onboarding (alta), lead funnel, comunicaciones (WhatsApp), documentación interna y autenticación centralizada.
- **Drivers de costo actuales:** storage (Supabase buckets y bases), requests (API multicliente), órdenes y conciliaciones, uso de WhatsApp externo, horas de soporte ligado al plan, tiempos de ejecuciones Edge Functions.

## 2. Inventario funcional detallado

| Ruta / Feature                                  | Problema que resuelve                                                                                                 | Data source / endpoints                                                                                                                                                | Puntos débiles actuales                                                                                                                                           |
| ----------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/dashboard/metrics` (MetricsPanel)             | KPIs globales (facturación, órdenes, storage, flujo de altas/bajas) con drilldown por cliente.                        | RPC `dashboard_metrics`; hooks `useDashboardMetrics`, `useDashboardTops`; componentes `ClientDrilldownDrawer`, `TopList`.                                              | No diferencia entre componentes de costo (infra vs servicios); ausencia de comparativa vs presupuesto; sin alertas configurables.                                 |
| `/dashboard/usage` (UsageView)                  | Consolida consumo por cliente (requests, órdenes, egress), costos estimados, top consumidores, sincronización manual. | Endpoints `/admin/metering/summary` (GET) y `/admin/metering/sync` (POST); hook `useUsageSummary`; gráficos `UsageTrendsChart`, `PlanUtilizationCard`, `TopBreakdown`. | Costos proyectados sólo estimativos, sin budget hard/soft; no registra acciones; depende del browser para refrescar manualmente; ausencia de store histórico.     |
| `/dashboard/clients`                            | Listado filtrable de clientes activos/eliminados, alertas de vencimiento, toggles de actividad, apertura a ficha.     | Tabla `clients`, vista `clients_deleted_summary`; utils `getClientsExpiringSoon`, `deleteClientEverywhere`, `ClientStatusToggle`.                                      | Toggle sólo cambia flag `is_active`; sin automatización de cortes (storage, backend). Baja depende de confirmación manual y preview no muestra impacto económico. |
| `/dashboard/clients/new`                        | Provisiona clientes según plan, registra setup fee opcional y genera credenciales temporales.                         | Componentes `AddClientForm`, utils `clientService`, `registerPayment`, Edge Function `admin-create-client`.                                                            | Catálogo de planes definido inline (const `PLANS`); reglas duplicadas en otras vistas; no valida topes de soporte ni extras.                                      |
| `/client/:id`                                   | Vista 360°: estado plan, pagos, consumo mensual, sincronización, facturas, recordatorios y baja.                      | Supabase `clients`, `payments`, `invoices`, utilidades `fetchClientUsage`, `triggerSyncUsage`, `registerPayment`, `sendPaymentReminder`.                               | Acciones manuales y aisladas; no existe panel de toggles de servicios; datos de consumo replican lo de `/usage`; no guarda bitácora de acciones.                  |
| `/dashboard/leads`                              | Orquesta pipeline de leads: importación XLSX, deduplicación, scoring, assets (videos).                                | Servicios `leadsService`, `leadQuizConfig`, `adminStorageService`; librería `xlsx`.                                                                                    | Procesamiento pesado en frontend (memoria + performance); sin rollback transaccional; no se calculan costos de adquisición ni relación con clientes activos.      |
| `/dashboard/inbox`                              | Controla conversaciones WhatsApp: listing, filtros, bot toggle, envío manual.                                         | `waInboxApi` → Edge Functions `admin-wa-conversations`, `admin-wa-messages`, `admin-wa-update-conversation`, `admin-wa-send-reply`.                                    | No hay métricas de desempeño, ni monitoreo de colas; no se cruza con estado financiero del cliente; dependencia fuerte de tokens runtime.                         |
| `/dashboard/playbook`                           | Surface de documentación operativa (MD) y procedimientos.                                                             | Carpeta `docs/`; render en `PlaybookView`.                                                                                                                             | Contenido estático; no relaciona tareas con estados/costos; difícil mantener actualizado.                                                                         |
| `/lead`, `/auth`, `/confirm`, `/reset-password` | Captación de leads y gateway único de auth con enforcement de T&C.                                                    | `AuthListener`, Supabase auth, `useTermsAccepted`.                                                                                                                     | Config de redirects depende de env; sin panel para monitorear conversiones y costos de marketing.                                                                 |

## 3. Matriz de costos y dependencias críticas

- **Planes y tarifas:** definidos en `AddClientForm.PLANS` (USD 20/60/120 + setup) con extras de soporte. Sin versión centralizada → riesgo de inconsistencia con facturación, informes y forecast.
- **Consumo infra:** medido por API (requests, egress, órdenes) y Supabase (storage). No existe relación explícita entre límites de plan y porcentaje consumido (uso manual en `PlanUtilizationCard`).
- **Automatizaciones externas:**
  - WhatsApp bot (Edge Functions) genera costos por lead; no se corta al pausar cliente.
  - Mercado Pago: tokens guardados vía AddClientForm, sin rotación automática ni alertas.
- \*_Storage:_ drena en buckets por cliente, pero UI sólo muestra top 10 sin acciones (limpiar, archivar, mover a cold storage).
- **Horas de soporte:** definidas en planes, no registradas ni descontadas. No hay módulo de control.

## 4. Riesgos y limitaciones (desglosado)

- **Gobierno de costos:**
  - Sin budgets configurables ni topes automáticos → riesgo de sobrefacto (UsageView).
  - Falta consolidar catálogo de planes y add-ons en un módulo reutilizable (AddClientForm, ClientDetails, facturación).
  - No se mide costo de lead ni retorno (LeadsView + ClientDetails).
- **Operaciones y orquestación:**
  - `ClientStatusToggle` sólo actualiza `is_active` → no corta store, cronjobs ni notifica integraciones.
  - `deleteClientEverywhere` depende de preview manual; no calcula deuda ni costos de baja.
  - No existe un panel de control para habilitar/deshabilitar features a nivel cliente (checkout, WhatsApp, automatizaciones, storage extra).
- **Datos y observabilidad:**
  - `MetricsPanel` agrupa storage y órdenes pero sin breakdown por costo monetario (p. ej. USD/GB, USD/request).
  - No se loguea `request_id` ni se enlazan logs Edge Functions ⇔ UI.
  - Dashboard no alerta sobre incidentes (latencia Supabase, fallos en sync, colas WhatsApp).
- **Experiencia operativa / DX:**
  - Config runtime dispersa; `supabaseClient.jsx` maneja fallback a mano. Falta diagnóstico visible de variables faltantes.
  - Tests ausentes para flows críticos (alta, baja, toggles, usage). Cambios rompen sin advertencia.
  - Procesos intensivos (import leads) en frontend sin worker ni cola servidor.

## 5. Roadmap recomendado

### Fase A – Gobierno de costos (duración estimada: 2 sprints)

1. Crear catálogo central `planCatalog.js` con tarifas, límites, cuotas de soporte y add-ons. Reutilizar en todo el panel y exponer API al backend/SDK.
2. Presupuestos y umbrales en UsageView: budgets por cliente, estado (soft/hard limit), alertas multi-canal, acciones automáticas (pausar bots, limitar storage extra).
3. Simulador y forecast: proyectar gasto mensual según histórico + plan. Permitir proponer upgrades.

### Fase B – Control operativo y automatización (2-3 sprints)

1. Panel de toggles y bitácora: Edge Function `admin-toggle-services` que coordine cortes (multicliente, storage, bots). UI en ClientDetails.
2. Flujo de baja avanzado: cálculo de deuda/costos pendientes, checklist, opciones de reactivación, descarga de snapshot, asignación de responsables.
3. Externalizar ingesta de leads a función server-side con colas y reporte de progreso; UI sólo monitorea estado.

### Fase C – Observabilidad y DX (1-2 sprints)

1. Widget de salud del sistema (Supabase latency, colas WhatsApp, errores Edge) + enlaces a logs con request_id.
2. Diagnóstico de entorno en runtime (banner si falta variable, botón para copiar configuraciones).
3. Suite de tests (Vitest/RTL + Playwright) para flows críticos, fixtures de datos y mocks de Edge Functions.

## 6. Iniciativas y tareas concretas

| #   | Objetivo                        | Cambios FE                                                                                                                                               | Cambios Edge/BE                                                                                                                      | Tests / Documentación                                                                |
| --- | ------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------ |
| 1   | Catálogo centralizado de planes | Nuevo módulo `src/config/planCatalog.js`; refactor `AddClientForm`, `ClientDetails`, `UsageView`, `PlanUtilizationCard`; exponer hooks `usePlanCatalog`. | Ajustar endpoint `/admin/metrics/summary` para devolver `plan_code`.                                                                 | Actualizar `docs/SETUP.md`; tests unitarios para selector de plan y cálculos de fee. |
| 2   | Budgets en consumo              | Dialog `BudgetConfigDialog`, tarjetas en UsageView, métricas en `TopBreakdown`.                                                                          | Endpoint `/admin/metrics/summary` devuelve budgets actuales y estados; POST `/admin/metrics/budget`.                                 | Tests de UI con Vitest/RTL (budget card); test integración en backend.               |
| 3   | Orquestación de servicios       | Componente `ClientControlsPanel` en `ClientDetails`, feed de eventos (bitácora).                                                                         | Edge Function `admin-toggle-services` (pausa/resume store, cronjobs, bots); tabla `service_toggles_log`; ajustes en backend Railway. | Documentar flujos en `docs/SETUP.md`; tests e2e pausar/activar.                      |
| 4   | Workflow de baja completo       | Nueva sección “Historial y costos” en `ClientsView`, preview extendida con deuda, acciones post-baja.                                                    | Extender `admin-delete-client` (calcular deuda, generar link de snapshot, registrar bitácora).                                       | Checklist QA en doc; unit tests preview/baja; fixture para clientes dados de baja.   |
| 5   | Ingesta de leads server-side    | UI con subida de archivo + monitor; componente `LeadImportStatus`.                                                                                       | Edge Function `admin-leads-import` con colas, dedupe server, storage; tabla `lead_import_jobs`.                                      | Tests unitarios (dedupe) y e2e (import flow); actualizar `docs/lead_import.md`.      |
| 6   | Observabilidad integrada        | `SystemStatusCard`, panel para logs recientes, hooking con `useSystemHealth`.                                                                            | Endpoint `/admin/health/summary`, métricas Supabase; pipeline de logs con request_id.                                                | Monitoreo en Playwright (capturar widget); docs en `docs/SECURITY_CHECKLIST.md`.     |
| 7   | Runtime diagnostics             | Hook `useRuntimeDiagnostics`, banner global en `App.jsx`; CLI check en build.                                                                            | Script CI que valide variables requeridas (GitHub Action).                                                                           | Tests unitarios del hook; doc “Checklist despliegue admin”.                          |
| 8   | Suite de tests/regresión        | Config Vitest + RTL, carpeta `__tests__` para vistas clave; mocks de supabase y fetch.                                                                   | Ajustar CI (`npm run test:unit`, `npm run test:e2e`).                                                                                | Documentar comandos en README y `docs/SETUP.md`.                                     |

## 7. Implementaciones nuevas sugeridas (deep dive)

- **Matriz de features por cliente:** UI tipo tabla con toggles (checkout, WhatsApp, automatizaciones, storage extra, integraciones). Cada toggle dispara `admin-toggle-services` y registra en bitácora. Permite conocer costo unitario por feature.
- **Simulador de upgrade:** Herramienta en UsageView para ingresar proyecciones (órdenes, bandwidth) y estimar factura en plan actual vs superior. Mostrar ROI y sugerir upgrade automático.
- **Alertas multicanal:** Integración con Slack/email (webhook configurable). Alertas: >80% presupuesto, token Mercado Pago por vencer, WhatsApp sin responder > X minutos, facturas vencidas.
- **Gestión contractual:** Sección en ClientDetails para adjuntar contratos, anexos y renovaciones. Datos guardados en storage seguro + tabla `client_contracts`. Habilita bloqueos si contrato vencido.
- **Cost center tagging:** Permitir etiquetar clientes por segmento o centro de costo, reflejar en métricas y budgets.
- **Playbook accionable:** Convertir playbook en checklists con estados (Pendiente / En curso / Done) y responsables; enlazar cada checklist con toggles y costos.

## 8. Pruebas, monitoreo y gobernanza

- **Testing automatizado:**
  - Unit: `ClientsView`, `ClientDetails`, `UsageView`, `AdminInbox` con mocks de supabase y fetch.
  - E2E: Playwright para altas, toggles, budgets, import leads y WhatsApp reply.
- **Monitoreo operativo:**
  - Instrumentar `useUsageSummary` y `useDashboardMetrics` para loguear latencias y errores (Sentry / DataDog).
  - Registrar `request_id` a nivel UI y mostrarlo al usuario para correlacionar con logs backend.
- **Documentación continua:**
  - Cada iniciativa debe actualizar `docs/SETUP.md`, `docs/SECURITY_CHECKLIST.md` y crear nuevo entry en `docs/changes/`.
  - Mantener checklist de despliegue: validar budgets cargados, toggles sincronizados, alertas configuradas.

## 9. Próximos pasos

1. Socializar este informe con stakeholders (producto, finanzas, soporte) y validar prioridades de Fase A.
2. Crear épicas en el board (p. ej. Jira) para cada iniciativa con subtareas FE/BE/Docs/QA.
3. Preparar rama `feature/admin-governance-{fecha}` y comenzar con refactor del catálogo de planes (depende de casi todas las iniciativas).
4. Definir contrato de nuevas Edge Functions (`admin-toggle-services`, `admin-leads-import`) y documentarlo en `docs/SETUP.md` antes de codificar.
5. Configurar ambiente de staging con datasets de consumo reales para validar budgets y automatización sin riesgo.

## 10. Backlog propuesto de tickets

### TKT-001 – Catálogo centralizado de planes y costos

- **Objetivo:** unificar definición de planes, límites y add-ons para que FE/BE y facturación compartan la misma fuente de verdad.
- **Entregables:**
  - `apps/admin/src/config/planCatalog.js` con estructura tipada y tests.
  - Refactor de `AddClientForm`, `ClientDetails`, `UsageView`, `PlanUtilizationCard` para usar el catálogo.
  - Endpoint `/admin/metrics/summary` devuelve `plan_code`, límites y cargos variables.
  - Documentación actualizada en `docs/SETUP.md` y `docs/changes/` específico.
- **Criterios de aceptación:** selección de plan refleja límites correctos; costos se recalculan automáticamente; build falla si falta plan en catálogo.
- **Riesgos:** regression en formularios de alta/edición; inconsistencias en datos históricos.

### TKT-002 – Presupuestos y alertas de consumo

- **Objetivo:** habilitar budgets mensuales por cliente con alertas soft/hard y acciones automáticas.
- **Entregables:**
  - UI: `BudgetConfigDialog`, tarjeta de estado en `UsageView`, badges en `PlanUtilizationCard`.
  - Backend: endpoints `GET/POST /admin/metrics/budget`, persistencia en tabla `client_budgets`.
  - Notificaciones: hook para Slack/email (configurable por env).
- **Criterios de aceptación:** se puede fijar presupuesto, ver uso % en la UI, recibir alerta simulada al superar límite.
- **Riesgos:** sobrecarga de requests si la sincronización se dispara en loop; dependencia de credenciales externas para webhooks.

### TKT-003 – Panel de control de servicios por cliente

- **Objetivo:** permitir activar/desactivar features (checkout, WhatsApp, automatizaciones, extra storage) con bitácora auditable.
- **Entregables:**
  - Componente `ClientControlsPanel` en `ClientDetails` con switches y logs.
  - Edge Function `admin-toggle-services` + tabla `service_toggles_log`.
  - Integración con backend multicliente y bots para respetar toggles.
- **Criterios de aceptación:** toggle OFF detiene servicio en <2 minutos; bitácora muestra autor y timestamp; reactivación revierte cambios.
- **Riesgos:** coordenar pausas con múltiples sistemas; fallback si la función falla.

### TKT-004 – Workflow de baja con cálculo de costos pendientes

- **Objetivo:** extender la baja de clientes para calcular deuda, generar snapshot y checklist de follow-up.
- **Entregables:**
  - Modal de preview con secciones (deuda, tareas post-baja, snapshot link).
  - Tabla gráfica en `ClientsView` para historial de bajas.
  - Edge Function `admin-delete-client` retorna detalle financiero y adjuntos.
- **Criterios de aceptación:** baja genera registro en `client_tombstones` con costos; snapshot descargable; log de responsable.
- **Riesgos:** cálculos incorrectos de deuda; eliminación irreversible de datos antes de completar checklist.

### TKT-005 – Ingesta de leads server-side y monitoreo

- **Objetivo:** mover parsing/deduplicación de XLSX a Edge Function y exponer seguimiento en UI.
- **Entregables:**
  - Edge Function `admin-leads-import` con batch processing y colas.
  - Componente `LeadImportStatus` para monitorear progreso y errores.
  - Tabla `lead_import_jobs` con auditoría.
- **Criterios de aceptación:** import de 5k registros no congela UI; los duplicados se reportan y se puede descargar log.
- **Riesgos:** tiempos de ejecución largos en Edge; manejo de errores parciales.

### TKT-006 – Observabilidad integrada y health widget

- **Objetivo:** consolidar métricas de salud (latencia Supabase, colas WhatsApp, errores Edge) dentro del dashboard.
- **Entregables:**
  - `SystemStatusCard` visible en `/dashboard/metrics`.
  - Endpoint `/admin/health/summary` agregando métricas y últimos incidentes.
  - Enlace directo a logs con `request_id` y filtros.
- **Criterios de aceptación:** widget se actualiza cada 60s; muestra estado verde/amarillo/rojo; se puede navegar a detalle de logs.
- **Riesgos:** ruido por falsos positivos; exponer información sensible en UI.

### TKT-007 – Diagnóstico de entorno y guardrails DX

- **Objetivo:** detectar faltantes de variables y errores de configuración antes de desplegar/usar.
- **Entregables:**
  - Hook `useRuntimeDiagnostics`; banner global si falta env.
  - Script de verificación en CI (`npm run verify:runtime`) que falla si env crítico ausente.
  - Documentación “Checklist despliegue admin”.
- **Criterios de aceptación:** banner aparece al remover variable; pipeline CI falla sin `VITE_ADMIN_SUPABASE_URL`.
- **Riesgos:** falsos positivos en ambientes locales; sobrecarga de mensajes para usuarios finales.

### TKT-008 – Suite de tests y automatización QA

- **Objetivo:** cubrir flows críticos con tests unitarios/E2E y agregar integración a CI.
- **Entregables:**
  - Configuración Vitest + React Testing Library; carpeta `apps/admin/src/__tests__`.
  - Playwright para flows: alta cliente, toggle servicio, budget alert, import leads.
  - Actualización de `package.json` con scripts `test:unit`, `test:e2e`, `verify`.
- **Criterios de aceptación:** CI ejecuta suite completa en <10 minutos; cobertura mínima 70% sobre módulos nuevos.
- **Riesgos:** flakiness en E2E; tiempo de ejecución elevado.

### TKT-009 – Simulador de costos y recomendaciones de upgrade

- **Objetivo:** ofrecer herramienta de forecasting para anticipar upgrades y costo total.
- **Entregables:**
  - Wizard dentro de `UsageView` para ingresar proyecciones (órdenes, bandwidth, storage extra).
  - Algoritmo que compara plan actual vs superior usando `planCatalog`.
  - Botón “Recomendar upgrade” que abre borrador de comunicación al cliente.
- **Criterios de aceptación:** simulador muestra diferencia de costo en USD; recomendaciones quedan registradas en bitácora.
- **Riesgos:** proyecciones inexactas; decisiones automatizadas sin validación humana.

### TKT-010 – Playbook accionable y seguimiento

- **Objetivo:** evolucionar playbook estático a checklists con responsables, tiempos y métricas asociadas.
- **Entregables:**
  - Motor de checklists (tabla `playbook_tasks`, componente `PlaybookChecklist`).
  - Integración con alertas (Slack/email) cuando tareas vencen o se asignan.
  - KPIs de progreso en la vista `PlaybookView`.
- **Criterios de aceptación:** cada tarea tiene estado y responsable; se puede exportar checklist; métricas actualizadas en tablero.
- **Riesgos:** complejidad de permisos; duplicidad con herramientas externas (Notion, Jira).
