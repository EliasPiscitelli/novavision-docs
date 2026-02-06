# Restauración del Sistema de Preview + Sincronización de Ramas

- **Autor:** agente-copilot
- **Fecha:** 2025-02-06
- **Repo:** templatetwo (web storefront)
- **Ramas afectadas:** `develop`, `feature/onboarding-preview-stable`, `feature/automatic-multiclient-onboarding`

---

## Resumen ejecutivo

Se restauró completamente el sistema de preview de tiendas para el onboarding de NovaVision. El preview estaba roto por 5 causas raíz identificadas tras un análisis profundo de divergencia entre 3 ramas. Se implementó un sistema de seguridad de 3 capas (token gate, network guard, mock providers) y se sincronizaron las ramas de trabajo con `develop`.

---

## ¿Qué es VITE_PREVIEW_TOKEN?

### Propósito
`VITE_PREVIEW_TOKEN` es un secreto compartido que protege la ruta `/preview` de acceso no autorizado. Solo los iframes cargados desde el panel de admin NovaVision que conozcan este token pueden renderizar la preview de tienda.

### Cómo funciona
1. El **admin panel** (novavision) genera la URL del iframe: `{storeUrl}/preview?token={VITE_PREVIEW_TOKEN}`
2. El **componente PreviewHost** en el storefront (templatetwo) extrae el `token` de la query string
3. Llama a `isValidPreviewToken(token)` que compara contra `import.meta.env.VITE_PREVIEW_TOKEN`
4. Si el token no coincide → se renderiza una página 404 (no se revela que `/preview` existe)
5. Si el token es válido → se monta `PreviewProviders` y se escucha `postMessage` del admin

### Comportamiento en desarrollo
Si `VITE_PREVIEW_TOKEN` **no está definida** (entorno local sin `.env`), la validación retorna `true` para facilitar desarrollo. En producción **SIEMPRE** debe estar configurada.

### Dónde configurar

| Entorno | Dónde va | Valor |
|---------|----------|-------|
| **Netlify (preview-stable)** | Site settings → Environment variables | `VITE_PREVIEW_TOKEN=ffa23c570352e29e8492874f75a1d06dc1092d34c93d65b44af3cba9da0aa1be` |
| **Netlify (multiclient)** | Site settings → Environment variables | Mismo valor (o uno diferente si es otro site) |
| **Admin panel** | Variable de entorno del admin que construye la URL del iframe | Mismo valor que el storefront correspondiente |
| **Local (.env.local)** | `apps/web/.env.local` | `VITE_PREVIEW_TOKEN=dev-token-local` (o cualquier valor para testear) |

### Token generado
```
ffa23c570352e29e8492874f75a1d06dc1092d34c93d65b44af3cba9da0aa1be
```
(64 caracteres hexadecimales, generado con `openssl rand -hex 32`)

### Regenerar token
```bash
openssl rand -hex 32
# o
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

---

## Archivos creados/modificados

### Nuevos (src/preview/)

| Archivo | Líneas | Propósito |
|---------|--------|-----------|
| `src/preview/RenderModeContext.tsx` | 34 | Context para detectar modo store/editor/preview |
| `src/preview/previewUtils.js` | 41 | Validación de token + detección de modo preview |
| `src/preview/BuilderDataContext.tsx` | 182 | Demo data provider con normalización de productos/FAQs/services |
| `src/preview/PreviewNetworkGuard.tsx` | 131 | **SEGURIDAD**: Bloquea requests no-GET y URLs sensibles |
| `src/preview/PreviewProviders.tsx` | 255 | Shell de providers mock (Auth/Cart/Favorites) + ThemeProvider |

### Modificados

| Archivo | Cambio |
|---------|--------|
| `src/pages/PreviewHost/index.tsx` | Reemplazó stub por import real + token gate con 404 fallback |
| `src/routes/AppRoutes.jsx` | Agregó ruta `/preview` |
| `src/context/AuthProvider.jsx` | (solo multiclient) Restaurado con OAuth cross-origin handoff |
| `docs/branch-workflow.md` | Nuevo: documentación del workflow de ramas |

---

## Sistema de seguridad de 3 capas

### Capa 1: Token Gate (previewUtils.js)
```
URL /preview?token=xxx → isValidPreviewToken(xxx) → ¿Coincide con VITE_PREVIEW_TOKEN?
  ├─ NO → Render <NotFound /> (404)
  └─ SI → Montar PreviewProviders
```

### Capa 2: Network Guard (PreviewNetworkGuard.tsx)
Parchea `window.fetch` y `XMLHttpRequest.prototype.open` para:
- **Bloquear** todo request que no sea GET o HEAD
- **Bloquear** URLs que contengan: `payments`, `mercadopago`, `orders`, `checkout`, `cart`, `preference`, `webhook`, `charge`, `subscribe`
- **Restaurar** los originales al desmontar el componente

### Capa 3: Mock Providers (PreviewProviders.tsx)
- `MockAuthProvider`: usuario ficticio, nunca intenta login real
- `MockCartProvider`: carrito vacío, operaciones no-op
- `MockFavoritesProvider`: favoritos vacío, operaciones no-op
- No expone tokens, no llama APIs

---

## Sincronización de ramas

### Problema original
- `feature/onboarding-preview-stable` tenía 18 commits divergentes con código degradado
- `feature/automatic-multiclient-onboarding` tenía 20 commits divergentes con 279 archivos y 34 conflictos

### Solución aplicada

```
develop (fuente de verdad)
  ├── fix/preview-restore (rama temporal con los 5 archivos + modificaciones)
  │    └── merge → develop
  │    └── merge → preview-stable (previamente reseteada a develop)
  │    └── merge → multiclient (previamente reseteada a develop)
  └── AuthProvider.jsx restaurado del backup → solo en multiclient
```

### Backups creados (antes de operaciones destructivas)
- `backup/onboarding-preview-stable-20260206`
- `backup/automatic-multiclient-onboarding-20260206`

---

## Cómo probar

### Preview local
```bash
# Terminal 1: API
cd apps/api && npm run start:dev

# Terminal 2: Web
cd apps/web && npm run dev

# Abrir en navegador:
http://localhost:5173/preview?token=dev-token-local
# Si VITE_PREVIEW_TOKEN no está en .env.local → funciona sin token
```

### Preview con token
```bash
# Agregar a apps/web/.env.local:
VITE_PREVIEW_TOKEN=mi-token-secreto

# Abrir sin token → 404
http://localhost:5173/preview

# Abrir con token incorrecto → 404
http://localhost:5173/preview?token=malo

# Abrir con token correcto → Preview funcional
http://localhost:5173/preview?token=mi-token-secreto
```

### Verificar Network Guard
En la consola del navegador, dentro del preview:
```javascript
// Debería fallar (blocked by PreviewNetworkGuard)
fetch('/api/orders', { method: 'POST', body: '{}' })
// Debería fallar (URL sensible)
fetch('/api/payments/create-preference')
// Debería funcionar (GET permitido, URL no sensible)
fetch('/api/products')
```

---

## Estado de pushes

| Rama | Estado | Tipo de push |
|------|--------|-------------|
| `develop` | ✅ Pushed | Regular (3 commits ahead) |
| `feature/onboarding-preview-stable` | ✅ Pushed | Force-with-lease (reseteada a develop + 2 commits) |
| `feature/automatic-multiclient-onboarding` | ✅ Pushed | Force-with-lease (reseteada a develop + 3 commits) |

---

## Notas de seguridad

- `VITE_PREVIEW_TOKEN` se inyecta en build time por Vite. **No es un secreto del servidor**, queda embebido en el bundle JS. Su propósito es prevenir acceso casual, no proteger contra ingeniería inversa deliberada.
- El verdadero muro de seguridad es `PreviewNetworkGuard` + los mock providers, que impiden que el preview ejecute transacciones reales.
- Para seguridad total, el backend debería rechazar requests con origin/referer de preview (no implementado aún).

---

## Riesgos y rollback

- **Rollback inmediato:** restaurar desde los backups `backup/onboarding-preview-stable-20260206` / `backup/automatic-multiclient-onboarding-20260206`
- **Riesgo bajo:** los cambios son aditivos (archivos nuevos) excepto la sincronización de ramas
- **Riesgo medio:** multiclient perdió commits específicos de preview viejo, pero se validó que eran redundantes (theme/styles ya absorbidos por develop)
