# Favorites System — Sistema de favoritos

- **Autor:** agente-copilot
- **Fecha:** 2026-02-18
- **Rama API:** feature/automatic-multiclient-onboarding
- **Rama Web:** feature/multitenant-storefront

## Resumen

Implementación del sistema de favoritos que permite a los compradores marcar productos como favoritos y gestionarlos desde una página dedicada.

## Archivos modificados/creados

### Backend (API)
- `src/favorites/favorites.controller.ts` — CRUD endpoints (GET, POST, DELETE) con scope por tenant
- `src/favorites/favorites.service.ts` — Lógica de negocio con filtro por client_id

### Web (Storefront)
- `src/context/FavoritesProvider.jsx` — Provider de React con contexto de favoritos
- `src/pages/FavoritesPage/index.jsx` — Página de favoritos del usuario
- `src/pages/FavoritesPage/style.jsx` — Estilos de la página
- `src/favorites/` — Módulo de favoritos (nuevo)
- `src/components/ProductCard/index.jsx` — Botón de favorito en tarjeta de producto
- `src/templates/first/components/ProductCard/index.jsx` — Favoritos en template 1
- `src/templates/fourth/components/ProductCard.jsx` — Favoritos en template 4
- `src/templates/second/components/ProductCard/index.jsx` — Favoritos en template 2
- `src/templates/fifth/pages/Home/index.jsx` — Favoritos en template 5
- `src/pages/SearchPage/ProductCard.jsx` — Favoritos en búsqueda

## Multi-tenant
- Todas las queries filtran por `client_id`
- RLS en tabla `favorites` con policies owner + admin + tenant

## Cómo probar
1. Login como comprador en la tienda
2. Click en corazón en cualquier ProductCard → se agrega a favoritos
3. Ir a `/favoritos` → ver lista de productos favoritos
4. Click en corazón para remover
