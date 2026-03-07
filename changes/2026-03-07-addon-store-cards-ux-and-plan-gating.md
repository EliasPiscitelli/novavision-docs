# Cambio: mejora visual y gating por plan en cards del Addon Store

- Autor: GitHub Copilot
- Fecha: 2026-03-07
- Rama: develop / feature/multitenant-storefront
- Archivos: apps/web/src/components/admin/AddonStoreDashboard/index.jsx

Resumen: se rediseñaron las cards del Addon Store para mostrar mejor jerarquía visual, el impacto concreto de cada compra y el beneficio esperado. Además, se bloquearon visualmente los addons que no están permitidos para el plan actual del tenant.

Por qué: las cards estaban muy planas, con poca información accionable y sin diferenciar claramente qué cambia en la tienda después de comprar un addon. También faltaba evitar que una cuenta Starter intente comprar uplifts disponibles solo desde Growth.

Cómo probar:

1. En apps/web correr npm run ci:storefront.
2. Entrar a /admin-dashboard?addonStore con una tienda Starter.
3. Verificar que los addons Growth-only queden bloqueados con mensaje "Solo planes Growth o superiores".
4. Confirmar que cada card muestre secciones de impacto y beneficio.
5. Confirmar que los addons permitidos sigan enviando a checkout normalmente.

Notas de seguridad: el bloqueo es visual y de UX, pero se apoya en allowed_plans del catálogo. La validación dura sigue estando en backend con ensureAddonAllowedForPlan.