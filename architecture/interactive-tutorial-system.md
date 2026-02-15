# Sistema de Tutoriales Interactivos — Admin Dashboard NovaVision

> Documento de diseño y plan de ejecución.
> Fecha: 2026-02-15 | Autor: agente-copilot

---

## 1. Resumen Ejecutivo

1. El dashboard tiene **15 secciones** con complejidad variada (desde read-only como Usage/Analytics/Billing hasta CRUD completo con 4 modales como ProductDashboard).
2. **No existe infraestructura previa** de tours/tutoriales. Es desarrollo 100% desde cero.
3. **Feature gating por plan ya funciona** — el sistema de tours lo respeta sin duplicar lógica.
4. 7 de 15 componentes manejan `useDevice()` — el soporte mobile es desigual y requiere atención caso por caso.
5. **Todos los modales son React state-driven** (no portales), lo que simplifica targeting pero complica timing (wait-for-render).
6. La navegación por querystring (`?products`, `?orders`) ya está sincronizada — el tour se engancha después de esa resolución, nunca la interfiere.
7. **Librería elegida: Driver.js v1.x** — ligera (~5KB gzip), zero-dependency, overlay nativo CSS clip-path, mobile-first, a11y con focus trap, API imperativa compatible con state machine custom.
8. **MVP en ProductDashboard** (sección más compleja, mayor valor de onboarding) → escalar al resto por prioridad.
9. Persistencia en `localStorage` scoped por tenant+user para "completado", "no mostrar", "retomar desde paso N".
10. Risk principal: timing de modales — se resuelve con MutationObserver + timeout + fallback graceful.

---

## 2. Mapa de Secciones

| # | Sección | Objetivo | Acciones críticas | Riesgos frecuentes | Plan mín. |
|---|---------|----------|-------------------|---------------------|-----------|
| 1 | products | Crear/editar catálogo | CRUD + Excel bulk + categorías | Imágenes pesadas, SKU duplicado, precio $0 | starter |
| 2 | users | Gestionar accesos | CRUD + block + password | Borrar admin accidentalmente | growth |
| 3 | orders | Consultar pedidos | Buscar + filtrar + detalle + QR | Filtros vacíos sin feedback | starter |
| 4 | logo | Subir identidad visual | Upload + toggle + delete | Formato incorrecto, resolución baja | starter |
| 5 | banners | Configurar carrusel | CRUD + link + orden | Dimensiones incorrectas, link roto | starter |
| 6 | services | Mostrar servicios | CRUD + imagen + orden | Imagen no optimizada | starter |
| 7 | faqs | Preguntas frecuentes | CRUD + orden | Respuesta truncada por límite | starter |
| 8 | contactInfo | Info de contacto | CRUD + orden | Datos incompletos | starter |
| 9 | socialLinks | Redes sociales | CRUD (singleton) | WhatsApp sin código país | starter |
| 10 | payments | Config de cobros | OAuth MP + config compleja | Desconectar MP en prod, fee routing | growth |
| 11 | shipping | Envíos | CRUD + test + toggle | API key incorrecta | growth |
| 12 | analytics | KPIs y reportes | Filtro fechas + visualización | Rango vacío | growth |
| 13 | identity | Branding del sitio | Redes + footer + dominio (tabs) | CNAME mal, socials duplicadas | growth |
| 14 | usage | Consumo del plan | Solo lectura (barras) | No entender métricas | starter |
| 15 | billing | Facturación | Solo lectura (tabla) | No encontrar "Pagar Ahora" | growth |

---

## 3. Arquitectura

```
┌──────────────────────────────────────────────────────────────┐
│                    AdminDashboard                             │
│  ┌────────────────────────────────────────────────────────┐  │
│  │                   TourProvider                          │  │
│  │  ┌─────────────┐  ┌──────────────┐  ┌──────────────┐  │  │
│  │  │ TourRegistry │  │  TourEngine  │  │  TourOverlay │  │  │
│  │  │ (Map<id,def>)│  │ (state mach.)│  │  (Driver.js) │  │  │
│  │  └──────┬──────┘  └──────┬───────┘  └──────┬───────┘  │  │
│  │         │                │                   │          │  │
│  │  ┌──────▼──────┐  ┌─────▼──────┐  ┌────────▼───────┐  │  │
│  │  │ tour-defs/  │  │ useTour()  │  │  Tooltip       │  │  │
│  │  │  *.js       │  │   hook     │  │  + Highlight   │  │  │
│  │  │ (lazy load) │  │            │  │  + Progress    │  │  │
│  │  └─────────────┘  └────────────┘  └────────────────┘  │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐  │
│  │              Sección Activa (ej: Products)              │  │
│  │  <div data-tour-target="products-create-btn">           │  │
│  │  ...                                                     │  │
│  └────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

### State Machine (TourEngine)

```
IDLE → STARTING → RUNNING(stepIndex) → COMPLETED
                     ↕                   ↑
                  PAUSED            ABORTED / ERROR
                     ↕
              WAITING_FOR_TARGET
```

---

## 4. Roadmap por Etapas

### Etapa 0 — Preparación (1-2 días)
- Instalar driver.js
- Crear TourProvider, TourEngine, TourOverlay, tourRegistry, tourPersistence, useTour
- Agregar data-tour-target attrs iniciales en ProductDashboard
- DoD: TourProvider wrappea AdminDashboard sin romper nada

### Etapa 1 — MVP Products (3-4 días)
- Tour "Crear Producto" con 15 pasos
- Botón "Tutorial" en HeaderBar
- Overlay + highlight + tooltip funcional
- Fallback si target no existe
- Persistencia localStorage
- Mobile compatible
- DoD: tour end-to-end en desktop y mobile sin regresiones

### Etapa 2 — Modales y flows complejos (2-3 días)
- awaitModal, click actions, guards
- Verificación post-acción
- Cleanup de modales al finalizar

### Etapa 3 — Escalado (5-7 días P1+P2, 5-7 días P3+P4)
- Logo, Banners, Orders → P1
- Services, FAQs, ContactInfo, SocialLinks → P2
- Payments, Shipping, Identity → P3
- Usage, Billing, Analytics, Users → P4

### Etapa 4 — Observabilidad (3-4 días)
- Event tracking
- Playwright tests
- Modo asistido v1

---

## 5. Decisiones Técnicas

| Decisión | Opción elegida | Justificación |
|----------|---------------|---------------|
| Librería | Driver.js v1.x | 5KB, CSS clip-path, API imperativa, mobile-first, a11y |
| Overlay | CSS clip-path | Performance superior a canvas/SVG |
| Persistencia | localStorage scoped | No requiere backend; scoped por tenant+user |
| Targeting | data-tour-target attrs | Desacoplado de CSS classes, resiliente a cambios de estilo |
| Tour defs | JS modules (no JSON) | Permite imports dinámicos y funciones en guards/hooks |

---

## 6. Reglas de Seguridad

1. El tour NUNCA modifica estado de negocio
2. El tour NUNCA navega a secciones bloqueadas
3. Si un target no existe en 3s → skip graceful
4. Back/forward del browser → aborta el tour
5. Refresh → se puede retomar desde localStorage
6. El tour no bloquea interacción crítica del usuario
