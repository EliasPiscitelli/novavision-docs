# Cambio: ajuste de copy comercial en Addon Store

- Autor: GitHub Copilot
- Fecha: 2026-03-07
- Rama: develop / feature/multitenant-storefront
- Archivos: apps/web/src/components/admin/AddonStoreDashboard/index.jsx

Resumen: se refinó el copy del Addon Store para que las cards expliquen mejor el valor comercial de cada compra, con mensajes más claros sobre impacto, beneficio y bloqueo por plan.

Por qué: el layout ya había mejorado, pero el texto seguía sonando demasiado técnico. Este pase busca que el usuario entienda más rápido qué compra, qué cambia en su tienda y por qué le conviene activarlo.

Cómo probar:

1. En apps/web correr npm run ci:storefront.
2. Entrar a /admin-dashboard?addonStore.
3. Verificar que las cards muestren copy más comercial en encabezado, impacto y beneficio.
4. Verificar que los addons no habilitados para Starter muestren un mensaje más directo de upgrade requerido.

Notas de seguridad: sin cambios de lógica, permisos ni contratos. Solo se ajustó contenido textual del frontend.