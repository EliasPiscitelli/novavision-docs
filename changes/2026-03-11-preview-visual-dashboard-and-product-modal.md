# Cambio: preview visual acotado + mejora del modal de producto

- Autor: GitHub Copilot
- Fecha: 2026-03-11
- Rama: feature/onboarding-preview-stable
- Archivos: src/pages/AdminDashboard/index.jsx, src/pages/AdminDashboard/style.jsx, src/components/admin/StoreDesignSection/index.jsx, src/components/admin/BannerSection/index.jsx, src/components/admin/ProductDashboard/index.jsx, src/components/ProductModal/index.jsx, src/components/ProductModal/style.jsx

## Resumen

Se ajustó la variante `feature/onboarding-preview-stable` para que el admin dashboard quede centrado en edición visual del storefront, con mensajes explícitos de disponibilidad por plan y sin upsell comercial desde preview. Además se rediseñó el modal de producto para mejorar legibilidad, jerarquía visual y confirmaciones antes de acciones destructivas.

## Qué se cambió

- El dashboard de admin en preview ahora muestra solo módulos visuales y de contenido visible.
- Se reemplazó el copy genérico de “plan superior” por disponibilidad exacta (`Growth` o `Enterprise`) en dashboard, Store Design, banners y carga masiva de productos.
- En Store Design se eliminó la redirección comercial a `addonStore` y se aclaró que preview solo informa la disponibilidad por plan.
- Se hizo visible y más explícita la zona de edición visual/estructura dentro de Store Design.
- Se corrigió el render del dashboard para que `Información y Anuncios` y `Templates, Themes y Edición Visual` abran sus paneles reales en lugar de derivar a una vista de uso.
- En carga masiva de productos se actualizó el copy de plan y se corrigió el refresh post-upload para recargar el listado sin llamar una referencia inexistente.
- El modal de producto recibió overlay opaco con blur, mejor contenedor, bloques de información, chips de estado, footer de acciones y confirmaciones para descartar cambios o eliminar imágenes.

## Por qué

- La rama preview no debe comportarse como un panel operativo completo: su objetivo es validar templates, themes, combinaciones y contenido visible.
- Los mensajes genéricos de acceso por plan confundían especialmente en casos Growth vs Enterprise.
- El modal de producto tenía problemas de contraste y transparencia, además de carecer de confirmaciones internas para acciones sensibles.

## Cómo probar

En `apps/web`:

```bash
npm run typecheck
npm run build
```

Verificación manual sugerida:

1. Abrir `/admin-dashboard` en la rama preview.
2. Confirmar que la home muestra solo secciones visuales/contenido visible.
3. Abrir `Templates, Themes y Edición Visual` y validar que la sección `Edición de secciones visibles` aparece y no hay CTA a Addon Store.
4. Validar que los templates o palettes bloqueados muestran el plan exacto requerido.
5. Abrir el editor de producto y verificar overlay, legibilidad y confirmaciones al cerrar con cambios o borrar imágenes.

## Notas de seguridad

No se agregaron credenciales ni cambios de permisos. El ajuste reduce exposición funcional en preview y elimina redirecciones comerciales desde ese ambiente.