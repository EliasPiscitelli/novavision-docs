# Cambio: Sistema de Tutoriales Interactivos — Admin Dashboard

- **Autor:** agente-copilot
- **Fecha:** 2026-02-15
- **Rama:** develop (cherry-pick a feature/multitenant-storefront + feature/onboarding-preview-stable)
- **Archivos:**
  - `apps/web/package.json` (dependencia driver.js)
  - `apps/web/src/tour/` (nuevo directorio — infraestructura completa)
  - `apps/web/src/components/admin/ProductDashboard/index.jsx` (data-tour-target attrs)
  - `apps/web/src/pages/AdminDashboard/index.jsx` (TourProvider + botón Tutorial)
  - `apps/web/src/pages/AdminDashboard/style.jsx` (estilos del botón)

## Resumen

Implementación de Etapa 0 + Etapa 1 del sistema de tutoriales interactivos para el Admin Dashboard.
Permite a los usuarios de cada tienda iniciar un tour guiado paso a paso ("como video en vivo")
que destaca, enfoca y explica cada elemento del dashboard con overlay + highlighting + tooltips.

**MVP:** Tour completo de "Crear Producto" (~15 pasos) en la sección Products.

## Arquitectura

```
src/tour/
├── TourProvider.jsx         — Context provider global (wrappea AdminDashboard)
├── TourEngine.js            — State machine (idle/starting/running/paused/completed/aborted/error)
├── TourOverlay.jsx          — Integración con Driver.js (overlay, highlight, tooltip)
├── tourRegistry.js          — Registry de tours por sectionKey
├── tourPersistence.js       — localStorage scoped por tenant+user
├── useTour.js               — Hook para componentes consumidores
└── definitions/
    └── products-crear-producto.js  — Tour "Crear Producto" (15 pasos)
```

## Por qué

- Los clientes admin necesitan onboarding contextual para usar el dashboard efectivamente.
- Reduce tickets de soporte y tiempo de activación de nuevos clientes.
- Driver.js elegido por: 5KB gzip, CSS clip-path overlay (performance), API imperativa, mobile-first, a11y nativa.

## Cómo probar

1. `cd apps/web && npm run dev`
2. Loguearse como admin
3. Ir a `/admin-dashboard?products`
4. Hacer clic en botón "Tutorial" en el header
5. Validar: overlay + highlight + tooltip + navegación paso a paso
6. Validar: salir, pausar, retomar, skip de targets faltantes
7. Validar mobile: tooltip sin solapamiento, touch-friendly

## Notas de seguridad

- El tour NO crea/modifica/borra datos — solo guía visualmente
- No interfiere con API calls ni modifica estado de negocio
- Persistencia solo en localStorage (no server-side)
