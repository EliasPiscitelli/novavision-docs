# Fix: Eliminar datos demo, precios $0, URLs 404 y links de navegación rotos

- **Autor:** agente-copilot
- **Fecha:** 2026-02-26
- **Rama:** develop (commit `7aaa4f0`) → cherry-pick a `feature/multitenant-storefront` (`c5270cd`)
- **Repo:** templatetwo (Web Storefront)

## Archivos modificados (11)

### Testimonials (datos demo eliminados)
- `src/templates/eighth/components/TestimonialsSection/index.jsx`
- `src/templates/seventh/components/TestimonialsSection/index.jsx`
- `src/templates/sixth/components/TestimonialsSection/index.jsx`
- `src/templates/eighth/pages/HomePageLumina/index.jsx`

### Precios y badges de descuento
- `src/templates/eighth/components/ProductShowcase/index.jsx`
- `src/templates/seventh/components/ProductShowcase/index.jsx`
- `src/templates/sixth/components/ProductShowcase/index.jsx`

### URLs de productos (404 fix)
- `src/templates/fourth/components/ProductCard.jsx`
- (+ los 3 ProductShowcase de arriba)

### Links de navegación
- `src/templates/eighth/components/HeroSection/index.jsx`
- `src/templates/eighth/components/FooterLumina/index.jsx`
- `src/templates/fourth/components/Footer.jsx`
- (+ eighth ProductShowcase)

## Resumen de cambios

### 1. Testimonials — datos demo eliminados de producción

**Problema:** Los templates sixth, seventh y eighth mostraban testimonios falsos hardcodeados ("Valentina M.", "Lucía R.", "Sofía G.") en tiendas productivas. El template eighth ni siquiera aceptaba prop `products`.

**Solución:**
- **eighth**: Reescrito completamente — acepta `products` prop, usa `extractReviews()` para extraer reviews reales, retorna `null` si hay menos de 3 reviews con rating >= 3. Se eliminó `DEFAULT_TESTIMONIALS`.
- **seventh/sixth**: Eliminado `DEMO_TESTIMONIALS` como fallback. Ahora retornan `null` si no hay al menos 3 reviews reales con rating >= 3.
- **HomePageLumina (eighth)**: Ahora pasa `products={products}` al componente `<TestimonialsSection>`.

**Regla aplicada:** Si una tienda no tiene reviews reales suficientes (>= 3 con >= 3 estrellas), la sección de testimonios no se renderiza.

### 2. Precio $0 y badge de descuento

**Problema:** Productos sin descuento mostraban `$ 0` como precio con descuento y badges vacíos como `-%` o `-undefined%`.

**Causa raíz:** La condición `hasDiscount = product.discountedPrice != null` era `true` cuando `discountedPrice === 0` (que es el valor por defecto en la DB).

**Solución:**
- Cambiado `discountedPrice != null` → `discountedPrice > 0` en los 3 templates (sixth, seventh, eighth).
- Agregado guard `product.discountPercentage > 0` al badge de descuento del template eighth (los otros ya tenían el guard).
- Corregido el filtro "Con descuento" del eighth ProductShowcase al mismo criterio `> 0`.

### 3. URLs de productos — 404 fix

**Problema:** Product cards y showcases usaban rutas inexistentes (`/producto/:id`, `/product/:id`) que daban 404. La única ruta válida es `/p/:id` (definida en AppRoutes.jsx L72).

**Solución:**
- **fourth/ProductCard**: 3 ocurrencias de `/producto/${id}` → `/p/${id}`
- **sixth/ProductShowcase**: `/product/${product.id}` → `/p/${product.id}`
- **seventh/ProductShowcase**: `/product/${product.id}` → `/p/${product.id}`
- **eighth/ProductShowcase**: `/product/${product.id}` → `/p/${product.id}`

### 4. Links de navegación rotos

**Problema:** Botones CTA ("Explorar colección", "Ver catálogo completo", "Ver todos los productos") y links del footer apuntaban a `/products` o `/productos` que no existen. La ruta correcta de browse es `/search`.

**Solución:**
- **eighth/HeroSection**: `href="/products"` → `href="/search"`
- **eighth/ProductShowcase**: 2 links `/products` → `/search`
- **eighth/FooterLumina**: 3 links (`/products`, `/products?filter=new`, `/products?filter=sale`) → `/search` variants
- **fourth/Footer**: `to="/productos"` → `to="/search"`

## Por qué

Bugs reportados en la tienda productiva de Farma (farma.novavision.lat). Los datos demo aparecían en producción, los precios mostraban $0, los links a productos daban 404, y los botones de navegación principal estaban rotos. Se validaron y corrigieron todos los templates afectados (fourth, sixth, seventh, eighth).

## Cómo probar

1. Levantar `npm run dev` en apps/web
2. Abrir cualquier tienda con template 4, 6, 7 u 8
3. Verificar:
   - **Testimonios**: La sección NO aparece (ya que no hay reviews reales en las tiendas de test)
   - **Precios**: Productos sin descuento muestran solo `originalPrice`, sin `$ 0` ni badge `-%`
   - **URLs**: Click en cualquier product card navega a `/p/:id` (no 404)
   - **Nav links**: "Explorar colección" y "Ver catálogo" van a `/search`

## Notas de seguridad

No aplica — cambios puramente de UI/presentación.

## Riesgos

- **Bajo:** Si una tienda "dependía" de los testimonios demo para mostrar contenido, ahora esa sección no se renderiza. Este es el comportamiento correcto — datos demo nunca deben mostrarse en producción.
- **Ninguno** para precios/URLs/nav: solo se corrigieron rutas a las correctas ya definidas en AppRoutes.
