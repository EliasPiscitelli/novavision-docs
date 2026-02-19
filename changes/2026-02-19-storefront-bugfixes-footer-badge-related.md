# Bug Fixes: Storefront — Productos Relacionados, Badge, Footer, Header, PropTypes

- **Autor:** agente-copilot
- **Fecha:** 2026-02-19
- **Rama Web:** `develop` → cherry-pick a `feature/multitenant-storefront`
- **Commits:** `dee7d26` (bug fixes), `3297b2f` (footer copyright + fourth template)

---

## Resumen

Corrección de múltiples bugs detectados en e2e-alpha.novavision.lat y mejoras visuales en templates fourth y fifth del storefront.

---

## Bugs Corregidos

### A) Productos Relacionados vacíos (`ProductPage/index.jsx`)
- **Síntoma:** Sección "Productos relacionados" siempre vacía.
- **Causa:** La query de la API retornaba vacío (posiblemente por RLS, ver doc de RLS fix).
- **Fix:** Se agregó fetch alternativo de productos desde la API cuando el resultado inicial está vacío.

### B) Badge de descuento oscuro sobre oscuro (`ProductCard/style.jsx` — fifth template)
- **Síntoma:** Badge de descuento ilegible en temas oscuros (texto oscuro sobre fondo oscuro).
- **Fix:** Se aplicó CSS variable `--nv-accent-fg` para garantizar contraste adecuado del texto.

### C) PropTypes de image_variants (`ProductCard/index.jsx` — fifth template)
- **Síntoma:** Warning en consola de React por PropTypes incorrecto.
- **Fix:** Se corrigió la definición de PropTypes para `image_variants`.

### D) Error en carga de imágenes (`ServicesContent/index.jsx` — fifth template)
- **Síntoma:** Error visual cuando una imagen de servicio no carga.
- **Fix:** Se agregó handler `onError` en `<img>` para fallback graceful.

### E) Toggle de tema visible (`Header/index.jsx` — fifth template)
- **Síntoma:** Icono de toggle de tema (light/dark) visible cuando no debería.
- **Fix:** Se ocultó el icono de toggle de tema.

### F) Copyright estático en Footer (`Footer/index.jsx` — fifth template)
- **Síntoma:** Año de copyright hardcodeado.
- **Fix:** Se usa `new Date().getFullYear()` para año dinámico.

### G) Footer del fourth template (`Footer.jsx` — fourth template)
- **Síntoma:** Footer incompleto, sin links dinámicos, contacto ni redes sociales.
- **Fix:** Rework completo del componente con:
  - Links dinámicos desde settings
  - Información de contacto
  - Links de redes sociales
  - Copyright dinámico

### H) Home del fourth template (`Home.jsx` — fourth template)
- **Síntoma:** Props faltantes para el nuevo Footer.
- **Fix:** Se pasan props de settings al componente Footer.

---

## Archivos Modificados

| Archivo | Template | Cambio |
|---------|----------|--------|
| `src/pages/ProductPage/index.jsx` | Compartido | Fetch alternativo de productos relacionados |
| `src/templates/fifth/components/ProductCard/style.jsx` | Fifth | CSS variable `--nv-accent-fg` para badge |
| `src/templates/fifth/components/ProductCard/index.jsx` | Fifth | PropTypes fix para `image_variants` |
| `src/templates/fifth/components/ServicesContent/index.jsx` | Fifth | Image error fallback handler |
| `src/templates/fifth/components/Header/index.jsx` | Fifth | Theme toggle icon hidden |
| `src/templates/fifth/components/Footer/index.jsx` | Fifth | Dynamic copyright year |
| `src/templates/fifth/pages/Home/index.jsx` | Fifth | Copyright prop to Footer |
| `src/templates/fourth/components/Footer.jsx` | Fourth | Complete footer rework |
| `src/templates/fourth/pages/Home.jsx` | Fourth | Footer props from settings |

---

## Distribución a Ramas

| Rama | Cherry-pick | Motivo |
|------|:-----------:|--------|
| `develop` | ✅ (origen) | Fuente de verdad |
| `feature/multitenant-storefront` | ✅ | Deploy de tiendas |
| `feature/onboarding-preview-stable` | ❌ | Cambios de storefront, no aplican a onboarding |

---

## Cómo Probar

1. Abrir un producto en el storefront → verificar que "Productos relacionados" muestra items.
2. Producto con descuento → verificar que el badge es legible (contraste adecuado).
3. Abrir consola del navegador → verificar que no hay warnings de PropTypes.
4. Verificar footer de fifth template → copyright muestra 2026.
5. Verificar footer de fourth template → muestra links, contacto y redes sociales dinámicamente.
