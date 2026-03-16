# Checklist Pre-Lanzamiento — 20 puntos priorizados

**Fecha**: 2026-03-15
**Criterio**: Ordenados por impacto en conversión × costo de ejecución
**Regla**: Nada de esto es feature nuevo. Es alineación, configuración y claridad.

---

## TIER 1 — Sin esto no se lanza (bloqueante)

### 1. Pricing Bible congelado
**Qué:** Un único documento con precio, límites, features y soporte por plan. Sin contradicciones entre materiales.
**Estado:** Los planes están en la DB (Starter $20, Growth $60, Enterprise $390) con limits reales. Pero los documentos internos tienen números distintos.
**Acción:** Crear `PRICING_BIBLE.md` con los datos de la tabla `plans` como source of truth. Freezar. Todo material público lee de ahí.
**Costo:** 2 horas. Esfuerzo: bajo. Impacto: crítico.

### 2. Una sola política de entrada
**Qué:** Decidir UNA forma de probar/entrar. No tres opciones flotando.
**Recomendación:** Builder gratis + preview real + pago recién al publicar. El onboarding ya soporta esto (el usuario puede completar todo sin pagar y la tienda entra en revisión post-pago).
**Acción:** Confirmar que el flujo permite ver preview sin pagar. Documentar la política. Comunicarla en landing.
**Costo:** 1 hora de decisión + ajuste de copy. Impacto: alto.

### 3. Promesa principal en 5 segundos
**Qué:** Una frase que responda "¿qué es esto y por qué me importa?" sin leer nada más.
**Propuesta:** "Tu tienda online profesional. Mercado Pago, envíos y SEO incluidos. Sin comisión por venta."
**Acción:** Elegir la frase. Usarla en hero de landing, primer mensaje de ads, bio de redes, descripción de app.
**Costo:** 30 minutos de decisión. Impacto: alto.

### 4. Landing alineada al embudo
**Qué:** La landing tiene que responder 6 preguntas en orden: ¿Qué resolvés? ¿Para quién? ¿Por qué me conviene? ¿Cuánto cuesta? ¿Puedo probar? ¿Por qué confiar?
**Estado:** La landing actual tiene hero + beneficios + WhatsApp. Falta: pricing claro, política de prueba, prueba social, comparativa honesta.
**Acción:** Reordenar/reescribir la landing con las 6 preguntas como guía.
**Costo:** 4-8 horas. Impacto: crítico para conversión de ads.

### 5. ICP de lanzamiento definido
**Qué:** Un solo perfil de cliente al que apuntar la primera campaña.
**Definición:** Pyme argentina que hoy vende por WhatsApp/Instagram. Catálogo chico/medio. Necesita cobrar con MP y resolver envíos locales. Dueño decide.
**Acción:** Todo el copy, targeting de ads y onboarding debe hablarle a esta persona. No mencionar B2B, Enterprise, LATAM, multi-país en la vidriera pública.
**Costo:** 0 (es una decisión). Impacto: alto.

---

## TIER 2 — Necesario antes de meter pauta (semana 1)

### 6. Demo grabada del onboarding + tienda
**Qué:** Video corto (60-90 seg) mostrando: registro → IA genera catálogo → preview de la tienda → publicada.
**Estado:** No existe. El sistema está listo para grabar.
**Acción:** Screen recording del happy path. Editar con subtítulos. Usar como pieza principal de ads.
**Costo:** 2-3 horas. Impacto: alto — es la pieza que más convierte en SaaS.

### 7. GA4 + Pixel configurados en novavision.lat
**Qué:** Crear propiedad GA4 y Pixel ID para la landing de NovaVision (no las tiendas — eso ya funciona per-tenant).
**Estado:** El código está implementado. Faltan los IDs/tokens de producción.
**Acción:** Crear propiedad en GA4, confirmar Pixel en Meta Business Manager, generar Access Token CAPI, configurar en env vars.
**Costo:** 1-2 horas. Impacto: bloqueante para medir performance de ads.

### 8. Eventos de onboarding en tracking
**Qué:** PageView, CompleteRegistration, InitiateCheckout, Subscribe deben estar firing en la landing/onboarding.
**Estado:** CAPI server-side ya envía Subscribe y Purchase. Falta verificar que Pixel browser también los dispare en el onboarding.
**Acción:** Verificar en Meta Events Manager que los eventos llegan. Testear con Events Tool.
**Costo:** 1-2 horas de QA. Impacto: bloqueante para optimizar campañas.

### 9. Simplificar narrativa pública a 5 pilares
**Qué:** En la landing y en ads, solo comunicar: (1) tienda lista rápido, (2) Mercado Pago integrado, (3) envíos locales, (4) 0% comisión, (5) SEO con IA.
**Acción:** Reescribir secciones de la landing. Sacar mención a tours, locks, JSON-LD, redirects, configuración avanzada de fees. Eso es para argumentos de cierre/upgrade, no para hero.
**Costo:** 2-3 horas de copy. Impacto: alto.

### 10. Contrato y términos verificados
**Qué:** T&C, privacidad, cancelación, qué pasa con datos/dominio — todo prolijo y publicado.
**Estado:** Verificado — `/terminos` y `/privacidad` existen con contenido completo conforme a Ley 24.240, 25.326, Disposición 954/2025.
**Acción:** Revisar que reflejen la política de entrada elegida (punto 2). Actualizar si cambió algo.
**Costo:** 30 min de revisión. Impacto: necesario para compliance.

---

## TIER 3 — Primera semana de pauta (optimización)

### 11. Tablero de métricas mínimo
**Qué:** Dashboard interno (puede ser en Supabase/Google Sheets/Retool) que muestre: builder starts, onboarding completions, pagos, publicaciones, primer pedido, soporte por cliente.
**Estado:** Los datos existen en la DB. No hay dashboard unificado.
**Acción:** Crear queries SQL o dashboard mínimo que se pueda consultar diariamente.
**Costo:** 4-6 horas. Impacto: necesario para decidir si escalar pauta.

### 12. Growth como plan recomendado
**Qué:** En la landing, marcar Growth como "Más popular" o "Recomendado". Starter es para entrar. Enterprise es "Consultá".
**Estado:** La tabla de pricing no tiene highlight visual.
**Acción:** Agregar badge "Recomendado" a Growth en la landing. Enterprise cambia a "Contactanos".
**Costo:** 1 hora de frontend. Impacto: medio — mejora conversión a plan más rentable.

### 13. Mensaje comparativo honesto
**Qué:** No decir "somos mejores que Shopify". Decir: "Para una pyme argentina que quiere dejar de vender por DM, NovaVision es más simple y más alineado al mercado local."
**Acción:** Si se hace comparativa en ads, usar datos reales: 0% comisión vs 0.7-2% de TN, MP nativo vs config manual, SEO AI incluido vs inexistente.
**Costo:** Incluido en el trabajo de copy. Impacto: medio.

### 14. Respuesta a "¿puedo probar gratis?"
**Qué:** Tener preparada la respuesta para la objeción #1 de cualquier lead.
**Opciones reales que la infra soporta:** (a) builder gratis, pagás al publicar; (b) 7 días trial Growth; (c) primer mes bonificado con código.
**Acción:** Elegir UNA. Tener el copy listo. Si es código promo, tenerlo cargado en la DB.
**Costo:** 30 min de configuración. Impacto: alto en conversión de leads indecisos.

### 15. Soporte acotado y documentado
**Qué:** Definir qué soporte se da en cada plan y comunicarlo claramente.
**Propuesta:** Starter = email/WhatsApp async, respuesta en 48h. Growth = prioridad 24h. Enterprise = consultar.
**Acción:** Documentar en FAQ de la landing. No prometer "acompañamiento personalizado" en Starter.
**Costo:** 30 min. Impacto: evita burnout operativo post-lanzamiento.

---

## TIER 4 — Primeras 2-4 semanas post-lanzamiento

### 16. Recovery de onboarding optimizado
**Qué:** Los 3 emails de recovery (24h, 48h, 72h) ya están implementados. Revisar copy y subject lines para maximizar re-engagement.
**Acción:** A/B test de subjects si hay volumen suficiente. Revisar que los emails tengan CTA claro y no sean genéricos.
**Costo:** 1-2 horas. Impacto: medio — recupera leads que no pagaron.

### 17. Demo de tienda live como prueba social
**Qué:** Una tienda de ejemplo publicada y accesible para que los leads vean el resultado final.
**Estado:** Farma existe como tienda live.
**Acción:** Crear 1-2 tiendas demo de rubros distintos (ej: indumentaria, deco). Linkear desde la landing como "Mirá cómo queda".
**Costo:** 2-3 horas por tienda demo. Impacto: alto — prueba tangible > promesa abstracta.

### 18. UGC / Founder video
**Qué:** Video cara a cámara del founder explicando por qué creó NovaVision. 60-90 segundos, cercano, sin producción excesiva.
**Acción:** Grabar, editar mínimamente, publicar como ad y en la landing.
**Costo:** 2 horas. Impacto: medio-alto — genera confianza y diferenciación.

### 19. First-purchase celebration per tenant
**Qué:** Cuando una tienda recibe su primer pedido, enviar un email de felicitación al admin. "Tu primera venta online — esto recién empieza."
**Estado:** Los webhooks de orden existen. El email template system existe.
**Acción:** Agregar trigger de email en el primer pedido de cada tenant.
**Costo:** 2-3 horas de desarrollo. Impacto: retención early-stage.

### 20. Churn early warning
**Qué:** Si una tienda publicada tiene 0 pedidos en 14 días, enviar email proactivo con tips: "¿Necesitás ayuda para recibir tu primer pedido? Acá van 3 ideas."
**Estado:** Los datos de órdenes por tenant existen. El sistema de emails existe.
**Acción:** Agregar cron job que detecte tiendas sin pedidos y dispare email.
**Costo:** 3-4 horas de desarrollo. Impacto: retención y reducción de churn temprano.

---

## Resumen visual

```
SEMANA -1 (antes de pauta):
  [1] Pricing Bible ✏️
  [2] Política de entrada 🚪
  [3] Promesa 5 seg 💬
  [4] Landing alineada 🖥️
  [5] ICP definido 🎯

SEMANA 0 (lanzamiento de pauta):
  [6] Demo grabada 🎥
  [7] GA4 + Pixel en prod 📊
  [8] Eventos verificados ✅
  [9] Narrativa 5 pilares 📝
  [10] T&C revisados 📋

SEMANA 1-2 (optimización):
  [11] Tablero métricas 📈
  [12] Growth recomendado 🏷️
  [13] Comparativa honesta ⚖️
  [14] Respuesta "¿gratis?" 🆓
  [15] Soporte documentado 🤝

SEMANA 3-4 (retención):
  [16] Recovery emails 📧
  [17] Tiendas demo live 🏪
  [18] Founder video 🎬
  [19] First-purchase email 🎉
  [20] Churn warning email ⚠️
```

---

## Nota final

Los puntos 1-5 son **decisiones**, no desarrollo. Se resuelven en una tarde sentado con foco.
Los puntos 6-10 son **configuración y contenido** — 1 semana de trabajo concentrado.
Los puntos 11-20 son **optimización** — se trabajan durante las primeras semanas de pauta.

El producto ya está. Lo que falta es claridad comercial para venderlo.
