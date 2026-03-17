# NovaVision — Ecosistema Completo de Automatizaciones

**Fecha:** 2026-03-17
**Estado:** Implementado y deployado.

---

## Resumen Ejecutivo

NovaVision opera con **3 capas de automatizacion** que trabajan en conjunto:

1. **18 flujos n8n** — Marketing digital + CRM/Ventas conversacionales
2. **20+ procesos automaticos en la API** — Facturacion, salud de cuentas, dominios, operaciones
3. **Super Dashboard Admin** — 42+ modulos de gestion centralizada multi-tenant

El resultado es una plataforma que se gestiona practicamente sola: vende, cobra, optimiza publicidad, mantiene limpia la base de datos, alerta sobre riesgos y reporta resultados — todo sin intervencion manual.

---

# PARTE 1: Automatizaciones de Marketing (8 flujos)

## 1.1 Reporte Diario de Meta Ads
- Se ejecuta todos los dias a las 8:00 AM
- Analiza el rendimiento de Meta Ads del dia anterior: gasto, clicks, impresiones, registros, CTR, CPC
- Una IA (GPT-4o-mini) actua como "CMO virtual" y genera un diagnostico con 3 numeros clave, 1 insight y 1 accion concreta
- **Pausa automaticamente** los anuncios que gastaron mas de $15 sin generar conversiones
- Envia el resumen por WhatsApp al fundador

## 1.2 Reporte Diario de Google Ads
- Se ejecuta a las 8:30 AM
- Obtiene metricas de campanas activas: costo, clicks, impresiones, conversiones, CPC, CPL
- IA genera analisis conciso con insight, campana top y accion recomendada para manana
- Alerta sobre campanas que gastaron mas de USD 20 sin conversiones
- Envia resumen por WhatsApp

## 1.3 Optimizador Inteligente de Presupuesto (Meta Ads)
- Se ejecuta 2 veces al dia (9:00 AM y 5:00 PM)
- Analiza los ultimos 3 dias de todos los anuncios activos
- Aplica 4 reglas automaticas:
  - **Pausa** anuncios con gasto > $15 y 0 conversiones (ejecuta la pausa directamente)
  - **Escala** anuncios rentables (CPA < $20 y 3+ conversiones) subiendo presupuesto un 20%
  - **Alerta frecuencia** si un anuncio se muestra demasiado al mismo publico (>2.5x)
  - **Alerta presupuesto** si el gasto mensual supera el 85% del tope
- Envia resumen consolidado por WhatsApp

## 1.4 Optimizador de Google Ads
- Se ejecuta 2 veces al dia (9:30 AM y 5:30 PM)
- Analiza rendimiento de los ultimos 7 dias por campana
- Genera recomendaciones inteligentes:
  - Pausar campanas con gasto > USD 30 y 0 conversiones
  - Escalar campanas con CPA bajo y buenas conversiones (+15% budget)
  - Subir bid en campanas con baja visibilidad pero que convierten
  - Revisar copy en campanas con CTR < 1%
- Envia alertas por WhatsApp con acciones especificas

## 1.5 Publicador Automatico de Anuncios
- Recibe los datos de un creativo (imagen, textos, CTA, plataformas destino)
- Crea automaticamente el anuncio completo en Meta Ads
- Actualiza el estado del asset a "pendiente de revision"
- Notifica al fundador por WhatsApp que hay un nuevo anuncio listo
- Elimina el proceso manual de subir creativos a Meta Ads Manager

## 1.6 Calendario Editorial Automatizado
- Se ejecuta cada hora
- Busca contenido programado con hora de publicacion ya cumplida
- Publica automaticamente en Instagram y/o Facebook segun corresponda
- Actualiza el estado del post a "PUBLICADO" con fecha y hora
- Notifica por WhatsApp que se publico exitosamente

## 1.7 Monitor de Competidores con IA
- Se ejecuta los lunes y jueves a las 10:00 AM
- Monitorea 3 competidores: Tiendanube, MercadoShops, Shopify Argentina
- Consulta la biblioteca de anuncios de Meta para ver publicidades activas
- Una IA analiza: mensajes, ofertas, tono, CTAs y detecta oportunidades
- Envia reporte consolidado por WhatsApp

## 1.8 Reporte Estrategico Semanal con IA
- Se ejecuta los domingos a las 8:00 AM
- Combina datos de publicidad (Meta Ads) + datos del funnel de producto (registros, onboardings, pagos, MRR)
- GPT-4o (modelo potente) genera un analisis estrategico completo:
  - Resumen ejecutivo
  - Que funciono y que no
  - Tramo del funnel con mayor caida
  - 3 acciones prioritarias para la semana
- Envia el reporte por WhatsApp al fundador

---

# PARTE 2: Automatizaciones de CRM y Ventas (10 flujos)

## 2.1 Primer Contacto Automatico (Seed Diario)
- Se ejecuta todos los dias a las 10:00 AM
- Toma hasta 50 leads nuevos del dia
- Envia WhatsApp con template aprobado + Email HTML profesional (en paralelo si tiene ambos datos)
- Personaliza con nombre, empresa, fuente de origen y link al builder
- Programa automaticamente el primer follow-up en 3 dias

## 2.2 Seguimientos Automaticos (Follow-ups)
- Se ejecuta 2 veces al dia (11:00 AM y 5:00 PM)
- Busca leads contactados cuyo seguimiento ya vencio
- Envia mensajes de WhatsApp progresivos (4 intentos con cadencia creciente: 3, 5, 7 dias)
- Si el lead no responde despues de 4 intentos, lo marca como "COLD" automaticamente
- Registra exito o fallo de cada intento

## 2.3 Bot de Ventas WhatsApp con IA
- Recibe mensajes entrantes de WhatsApp en tiempo real
- Detecta opt-outs ("stop", "parar", "cancelar") y respeta la baja
- Recupera historial de conversacion (ultimos 10 mensajes) para contexto
- Carga playbook de ventas y catalogo de cupones desde la base de datos
- Una IA (GPT-4.1-mini) responde como vendedor profesional:
  - Sigue el playbook de ventas configurado
  - Ofrece cupones de descuento en el momento estrategico
  - Califica el engagement del lead con scoring automatico
- Si el lead alcanza score alto (>= 80), notifica al equipo como "hot lead"
- Aplica delays humanizados (3-12 segundos) para simular escritura natural
- Registra intent, score, razonamiento y cupones ofrecidos

## 2.4 Bot de Ventas Instagram DM con IA
- Recibe mensajes de Instagram Direct (texto, imagenes, audio, video, stickers)
- Misma logica de IA conversacional que WhatsApp
- Guardrails de compliance:
  - No responde si el contacto hizo opt-out
  - No responde si hay handoff a humano activo
  - No responde fuera de la ventana de 24h de Meta
  - No responde si ya envio 3 mensajes consecutivos sin respuesta
- Gestion de cupones contextual
- Scoring y escalamiento a equipo de ventas

## 2.5 Tracking de Entrega de DMs (Instagram)
- Rastrea si los mensajes de Instagram fueron entregados y leidos
- Alimenta la inteligencia del CRM con datos de engagement real

## 2.6 Limpieza Diaria de Base de Datos
- Se ejecuta a las 3:00 AM todos los dias
- 3 operaciones automaticas en paralelo:
  - **Auto-COLD**: Marca leads inactivos (>14 dias sin actividad + max follow-ups agotados)
  - **Descarte**: Elimina leads con telefonos invalidos o vacios
  - **Deduplicacion**: Elimina duplicados por telefono, conservando el mas antiguo
- Genera resumen post-limpieza y lo registra

## 2.7 Sincronizacion Ventas ↔ Producto
- Se ejecuta cada 2 horas
- Cruza la base de leads con las tablas de onboarding y cuentas activas
- Si un lead se registro solo → el CRM se entera automaticamente:
  - Con cuenta activa → lo marca como "WON"
  - En onboarding → lo marca como "ONBOARDING"
  - Inicio onboarding siendo NEW → lo marca como "QUALIFIED"
- Mantiene sincronizados los mundos de ventas y producto

## 2.8 Alertas CRM (Lifecycle + Tareas Vencidas)
- Se activa cuando el backend detecta un evento relevante
- Dos tipos de alerta por WhatsApp:
  - **Tareas vencidas**: Listado de tareas pendientes con prioridad para el equipo
  - **Transicion de lifecycle**: Cuando una cuenta pasa a "en riesgo" o "churned" con health score y motivo

## 2.9 Reporte Semanal de Pipeline
- Se ejecuta los lunes a las 9:00 AM
- Consulta 5 metricas en paralelo:
  1. Funnel completo (leads por estado)
  2. Actividad semanal (contactados, conversaciones, calificados, ganados, perdidos)
  3. Metricas de mensajeria (enviados, recibidos, respondedores unicos, errores)
  4. KPIs de conversion (tasa de conversion, engagement, score promedio IA)
  5. Top 10 hot leads activos
- Envia reporte estructurado por WhatsApp

## 2.10 Verificacion de Webhook Instagram
- Endpoint auxiliar de infraestructura para el flujo de webhooks de Instagram
- Redirige verificacion a la API principal

---

# PARTE 3: Automatizaciones del Backend (API)

## 3.1 Facturacion y Cobros Automaticos
- **Cobro automatico mensual**: El dia 5 de cada mes cobra automaticamente ajustes pendientes (sobrecostos, comisiones) a suscriptores con auto-cobro activo
- **Calculo de comisiones GMV**: El dia 2 calcula comisiones basadas en volumen de ventas cuando excede el umbral del plan
- **Pipeline de ventas diario**: Suma ordenes pagadas por tenant y convierte a USD
- **Calculo de costos**: El dia 3 calcula el costo real por cliente (comisiones gateway + ordenes + API calls + almacenamiento)
- **Consolidacion de uso**: Diariamente consolida metricas de uso (requests, ordenes, storage) en resumenes mensuales
- **Acumulacion de sobrecostos**: El dia 3 acumula sobrecostos para cobro automatico en proximo ciclo

## 3.2 Suscripciones y Addons
- **Facturacion recurrente de addons**: El dia 2 genera cargos mensuales por addons contratados
- **Reconciliacion de addons**: Diariamente verifica estados y marca como moroso si falla el pago
- **Alerta de vencimiento de creditos**: Notifica cuentas cuyos creditos venceran en 30 dias

## 3.3 Salud de Cuentas y CRM Automatico
- **Health Score cada 6 horas**: Calcula una puntuacion de salud (0-100) por cada cuenta basada en:
  - Estado de pagos
  - Nivel de activacion (cantidad de productos)
  - Estado de publicacion de tienda
  - Recencia de actividad
  - Progreso de onboarding
- **Transiciones automaticas de lifecycle**:
  - Cuenta saludable → Si cae a riesgo, se crea tarea de revision y alerta al equipo
  - Cuenta en riesgo → Si mejora, vuelve a activa automaticamente
  - Cuenta en riesgo → Si cancela suscripcion, pasa a churned
- **Tareas vencidas cada 30 minutos**: Detecta tareas CRM pendientes y alerta

## 3.4 Ordenes y Pedidos
- **Expiracion de ordenes cada 5 minutos**: Cancela ordenes sin pagar despues de 30 minutos, revierte stock y cupones
- **Limpieza de QR diaria**: Elimina codigos QR de ordenes viejas del almacenamiento

## 3.5 Dominios y Certificados
- **Verificacion de dominios cada 10 minutos**: Verifica ownership de dominios personalizados pendientes
- **Revision de expiracion diaria**: Revisa vencimiento de dominios gestionados y obtiene cotizaciones de renovacion
- **Verificacion DNS cada 6 horas**: Comprueba resolucion DNS de dominios en configuracion

## 3.6 Soporte y Operaciones
- **Monitor SLA cada 5 minutos**: Detecta tickets de soporte que estan por incumplir SLA
- **Procesador de emails**: Cola de envios con reintentos automaticos (confirmaciones de orden, notificaciones de pago, etc.)
- **Validacion de integridad cada 6 horas**: Verifica consistencia de datos criticos

## 3.7 Webhooks Automaticos
- **MercadoPago**: Recibe y procesa pagos de ordenes de tienda + pagos de suscripciones de plataforma, con validacion de seguridad
- **WhatsApp**: Recibe mensajes entrantes y los envia a los bots de IA
- **Instagram**: Recibe DMs y actualizaciones de estado
- **Shipping**: Recibe actualizaciones de envios de proveedores logisticos y notifica al comprador

---

# PARTE 4: Tracking Multi-Plataforma (Web Storefront)

## Funnel completo cubierto por tenant:

| Evento | GA4 | Meta Pixel | TikTok Pixel | GTM |
|--------|-----|------------|--------------|-----|
| Busqueda | Si | Si | Si | Si |
| Ver producto | Si | Si | Si | Si |
| Agregar al carrito | Si | Si | Si | Si |
| Iniciar checkout | Si | Si | Si | Si |
| Compra | Si | Si | Si | Si |

- Tracking CAPI server-side: 3 eventos (CompleteRegistration, Subscribe, Lead)
- Gated por consentimiento del usuario
- Configuracion por tenant (cada tienda tiene sus propios pixel IDs)

---

# PARTE 5: Super Dashboard Admin

## 5.1 Metricas y Finanzas (5 modulos)

| Modulo | Que permite hacer |
|--------|-------------------|
| **Metricas** | Panel consolidado con totales, almacenamiento y alertas tempranas de desvios |
| **Finanzas** | Conciliacion financiera: cash cobrado vs facturacion devengada, cuentas por cobrar, margen neto |
| **Uso y Costos** | Consumo de cada cliente: costos, limites, proyecciones |
| **Growth HQ** | Dashboard de adquisicion: MRR, CAC, CPL, ROAS, hot leads, gasto publicitario por plataforma |
| **Ad Performance** | Rendimiento diario de campanas: gasto, clicks, impresiones, conversiones, CTR, CPC, CPL |

## 5.2 Clientes y Ventas (7 modulos)

| Modulo | Que permite hacer |
|--------|-------------------|
| **Clientes** | Fichas completas, accesos, permisos, planes, busqueda avanzada, historial de eliminados |
| **Alta de Cliente** | Creacion con provisioning automatico de recursos |
| **Leads** | Funnel completo (Quiz → Reunion → Proximos pasos), import Excel masivo, deteccion de duplicados |
| **Aprobaciones Pendientes** | Revision de tiendas completadas antes del go-live |
| **Estado de Completacion** | Progreso de clientes en post-pago, deteccion de bloqueos |
| **CRM Interno** | Customer 360, lifecycle management, notas internas, tareas, timeline, health score por cuenta |
| **Outreach Pipeline** | Funnel visual completo, hot leads, cupones, metricas de conversion, filtros por canal y periodo |

## 5.3 Facturacion y Planes (12 modulos)

| Modulo | Que permite hacer |
|--------|-------------------|
| **Planes** | Administracion de limites, precios y requisitos por plan (Starter, Growth, Enterprise) |
| **Centro de Renovaciones** | Monitor de vencimientos de dominios, renovaciones, overrides manuales |
| **Facturacion Hub** | Gestion centralizada de cobros: planes, dominios, fees |
| **Cupones Plataforma** | Codigos de descuento para suscripciones, campanas de retencion |
| **Cupones de Tienda** | Vista cross-tenant de cupones, monitoreo de uso por tienda |
| **Addon Store Ops** | Registro de compras de servicios (SEO, uplift), fulfillment |
| **FX Rates** | Tasas de cambio por pais, facturacion LATAM, sincronizacion de precios locales |
| **Country Configs** | Configuracion fiscal por pais: moneda, impuestos, formatos |
| **Quotas** | Estado de cuota por tenant: ordenes, bandwidth, enforcement |
| **Ajustes / Comisiones GMV** | Comisiones por volumen de ventas, overages, opciones de cobro/exencion |
| **Fee Schedules** | Tablas de comision de MercadoPago por pais y cuotas |
| **SEO AI Pricing** | Packs de creditos SEO AI, gestion de precios y saldos |

## 5.4 Operaciones (10 modulos)

| Modulo | Que permite hacer |
|--------|-------------------|
| **Playbook** | Guias operativas, mensajes modelo, workflows para equipo comercial |
| **Inbox WhatsApp** | Conversaciones centralizadas, historial completo, respuestas directas |
| **Inbox Instagram** | Vista de conversaciones, hot leads, trazabilidad |
| **Emails** | Monitoreo de jobs de correo, deteccion de fallos, reintentos manuales |
| **Shipping** | Vision cross-tenant de envios, integraciones logisticas, Dead Letter Queue |
| **SEO** | Titulos, meta descriptions, OG images, Analytics, Search Console por cliente |
| **Soporte Tecnico** | Tickets con SLA, asignacion de agentes, prioridades, categorias |
| **Eventos de Suscripcion** | Historial de cancelaciones, upgrades, reactivaciones |
| **Cancelaciones / Churn** | Dashboard de motivos, seguimiento de contacto, metricas de retencion |
| **Detalle de Suscripcion** | Informacion detallada, historico de cambios, estados |

## 5.5 Infraestructura y Configuracion (4 modulos)

| Modulo | Que permite hacer |
|--------|-------------------|
| **Clusters Backend** | Administracion de data-plane, almacenamiento seguro, routing controlado |
| **Sistema de Diseno** | Templates, paletas, presets reutilizables por cliente |
| **Dev Portal Whitelist** | Acceso controlado a herramientas de desarrollo |
| **Option Sets** | Plantillas globales de variantes (talles, colores) reutilizables |

## 5.6 Navegacion y UX del Dashboard
- Busqueda global por nombre, descripcion e impacto
- 5 categorias organizadas: Metricas, Clientes, Facturacion, Operaciones, Infraestructura
- Tema claro/oscuro
- Selector de pais para contexto regional
- Modulos protegidos solo para super-admin
- Verificacion de identidad para admins

---

# PARTE 6: Comparativa vs Agencias

## Marketing: NovaVision vs Agencias Tradicionales

| Capacidad | Agencia TOU (USD 2.150/mes) | Agencia FLY/VUZZ (USD 1.020/mes) | NovaVision Marketing OS (~USD 100/mes infra) |
|-----------|---------------------------|----------------------------------|----------------------------------------------|
| Meta Ads gestion | Manual | Manual | Automatizado con IA |
| Google Ads | Extra (no incluido) | Excluido | Preparado, activar semana 3-4 |
| TikTok Ads | No | No | Fase 2 |
| Tracking client-side | Si | Basico | GA4 + Meta + TikTok + GTM |
| Tracking CAPI server-side | Si | No | 3 eventos (CompleteRegistration, Subscribe, Lead) |
| Reporte diario | No | No | Automatico 8AM + WhatsApp |
| Reporte semanal con IA | No | Mensual manual | GPT-4o domingos |
| Auto-pause ads malos | No (manual) | No (manual semanal) | Automatico 2x/dia |
| Auto-scale ads ganadores | No | No | Automatico 2x/dia (+20% budget) |
| Optimizacion Google Ads | No | No | Automatica 2x/dia con 4 reglas |
| Monitor competidores | No | No | 2x/semana con IA |
| Content publishing organico | No | No | Automatico desde content_calendar |
| Dashboard funnel completo | No | Dashboard basico | Growth HQ (MRR, CAC, CPL, ROAS, funnel) |
| Ad performance analytics | Reporte mensual PDF | Reporte mensual | Diario + filtros por fecha y plataforma |
| Creatividades/mes | 6-10 piezas | 8-10 piezas | Founder graba, sistema publica |
| Control de activos | Parcial | Parcial | 100% propio |
| Canales | Solo Meta | Solo Meta | Meta + Google + TikTok (fase 2) |

## CRM y Ventas: NovaVision vs Herramientas Externas

| Capacidad | CRM Generico (HubSpot/Pipedrive) | Chatbot Basico | NovaVision CRM + Outreach |
|-----------|----------------------------------|----------------|---------------------------|
| Primer contacto automatico multicanal | Config manual | No | WA + Email diario a las 10AM |
| Follow-ups automaticos | Config manual | No | 4 intentos con cadencia creciente |
| Bot de ventas WhatsApp con IA | No nativo | Template basico | IA conversacional con playbook, cupones y scoring |
| Bot de ventas Instagram con IA | No | No | IA con guardrails de compliance |
| Scoring automatico de leads | Manual | No | Automatico por engagement + IA |
| Hot lead alerts | Config manual | No | Automatico al equipo por WhatsApp |
| Limpieza de base diaria | No | No | Auto-COLD, descarte invalidos, dedup |
| Sync ventas ↔ producto | Integracion externa | No | Cada 2 horas automatico |
| Lifecycle management | Manual | No | Transiciones automaticas basadas en health score |
| Reporte semanal pipeline | Exportar + armar | No | Automatico los lunes 9AM por WhatsApp |
| Opt-out management | Manual | No | Deteccion automatica de keywords |
| Humanizacion de respuestas | No | No | Delays de 3-12s simulando escritura |

## Operaciones: NovaVision vs SaaS Tradicional

| Capacidad | SaaS sin automatizacion | NovaVision |
|-----------|------------------------|------------|
| Facturacion recurrente | Manual o Stripe basico | Auto-cobro dia 5, comisiones GMV, addons, multi-moneda |
| Deteccion de churn | Reactiva | Proactiva: health score cada 6h + alertas automaticas |
| Expiracion de ordenes | Manual o sin control | Cada 5 min, revierte stock y cupones |
| Monitor de dominios | Manual | Verificacion cada 10min, expiracion diaria, DNS cada 6h |
| SLA de soporte | Sin enforcement | Monitor cada 5min con alertas |
| Integridad de datos | Rezar | Validacion automatica cada 6h |
| Envio de emails | Fire-and-forget | Cola con reintentos automaticos |
| Webhooks de pagos | Basico | Validacion HMAC + deduplicacion + Dead Letter Queue |

---

# PARTE 7: Ahorro Proyectado

## vs Agencias de Marketing

| Periodo | vs TOU (USD 2.150/mes) | vs FLY/VUZZ (USD 1.020/mes) |
|---------|------------------------|----------------------------|
| Mes 1 | -USD 1.575 | -USD 470 |
| 3 meses | -USD 3.525 | -USD 1.335 |
| 12 meses | -USD 14.100 | -USD 5.340 |

*(Considerando ~USD 125/mes de infra + misma pauta USD 450)*

## vs Herramientas CRM/Outreach Externas

| Herramienta | Costo mensual estimado |
|-------------|----------------------|
| HubSpot Sales Hub (Starter) | USD 20-50/usuario |
| Chatbot WhatsApp (Respond.io, Wati) | USD 99-299/mes |
| Chatbot Instagram (ManyChat Pro) | USD 15-65/mes |
| Lead scoring tool | USD 50-200/mes |
| **Total externo estimado** | **USD 200-600/mes** |
| **NovaVision (incluido en la plataforma)** | **USD 0 adicional** |

---

# PARTE 8: Ventajas Competitivas

## Lo que NovaVision hace que nadie mas ofrece junto

1. **Reportes diarios con IA** — Las agencias dan reportes mensuales
2. **Auto-optimizacion 2x/dia** — Las agencias lo hacen manual, semanal
3. **Monitor de competidores con IA** — Ninguna agencia lo ofrecia
4. **Bot de ventas multicanal** — IA que vende por WhatsApp e Instagram simultaneamente
5. **CRM con lifecycle automatico** — Health score + transiciones sin intervencion
6. **Sync ventas ↔ producto** — El CRM se entera solo cuando un lead se registra
7. **CAPI server-side** — Tracking premium que muchas agencias ni mencionan
8. **Multi-plataforma tracking** — GA4 + Meta + TikTok + GTM en un solo setup
9. **42+ modulos de gestion** — Dashboard admin que cubre finanzas, clientes, operaciones y marketing
10. **100% control de activos** — Cuentas, datos, tokens, todo propio

## Lo que NO reemplaza

- **Produccion de creatividades** (6-10 piezas/mes). Grabar videos y disenar piezas sigue siendo manual o requiere freelancer UGC.
- **Experiencia creativa** — Saber que hooks y angulos funcionan. El sistema da los datos para iterar, pero la intuicion creativa se aprende con la practica.
- **Intervencion humana en ventas complejas** — Los bots escalan hot leads al equipo; el cierre final puede requerir una persona.

---

# Mapa de Automatizaciones por Horario

| Hora (Argentina) | Que se ejecuta |
|------------------|----------------|
| 03:00 AM | Limpieza de base de leads + QR cleanup |
| 06:00 AM | Consolidacion de uso + GMV pipeline |
| 08:00 AM | Reporte diario Meta Ads |
| 08:30 AM | Reporte diario Google Ads |
| 09:00 AM | Optimizador de presupuesto Meta (1ra pasada) + Reporte pipeline (lunes) |
| 09:30 AM | Optimizador Google Ads (1ra pasada) |
| 10:00 AM | Seed diario (primer contacto) + Monitor competidores (lun/jue) |
| 11:00 AM | Follow-ups (1ra pasada) |
| 5:00 PM | Optimizador Meta (2da) + Optimizador Google (2da) + Follow-ups (2da) |
| Cada hora | Content publishing organico |
| Cada 2 horas | Sync ventas ↔ producto |
| Cada 5 min | Expiracion de ordenes + Monitor SLA |
| Cada 6 horas | Health score CRM + DNS check + Integridad datos |
| Cada 10 min | Verificacion de dominios |
| Domingos 8AM | Reporte estrategico semanal con IA |
| Tiempo real | Bots WhatsApp + Instagram, webhooks de pagos, envios, mensajes |
