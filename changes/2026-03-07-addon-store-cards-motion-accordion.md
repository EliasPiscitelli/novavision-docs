# Cambio: refinamiento visual de cards en Addon Store

- Autor: GitHub Copilot
- Fecha: 2026-03-07
- Rama: develop / feature/multitenant-storefront
- Archivos: apps/web/src/components/admin/AddonStoreDashboard/index.jsx

Resumen:
Se refinó la presentación visual de las cards del Addon Store para que el contenido quede más centrado, con mejor jerarquía tipográfica, foco visual superior, bloque de precio más claro y un bloque de beneficios plegable. También se agregaron animaciones de aparición y micro-movimiento al interactuar.

Por qué:
La versión anterior seguía viéndose pesada y desalineada. El objetivo fue darle una lectura más comercial y más limpia, sin tocar la lógica de compra, gating por plan ni el flujo de checkout.

Qué cambió:
- Layout de card más centrado y con mejor balance vertical.
- Foco visual superior con identificador por familia del addon.
- Mayor peso visual y legibilidad en el título.
- Bloque de precio más protagonista y más fácil de escanear.
- Caja “Por qué te conviene” convertida en acordeón desplegable.
- El grid ya no estira las cards vecinas cuando un acordeón se abre.
- Animación de entrada por card con leve desplazamiento.
- Hover con micro-movimiento y elevación visual.
- CTA y campo de cupón alineados con el nuevo layout.

Cómo probar:
1. En apps/web correr npm run dev.
2. Abrir una tienda con admin dashboard y navegar a ?addonStore.
3. Verificar que las cards entren con animación suave.
4. Verificar que “Por qué te conviene” abra y cierre correctamente.
5. Confirmar que el botón Comprar, los bloqueos por plan y los accesos a módulo/billing sigan funcionando.

Notas de seguridad:
- Sin cambios de contrato API.
- Sin cambios de permisos, tenant scope ni checkout.