# Cambio: Store Design con borrador estructural, preview interactivo y apply diferido

- Autor: GitHub Copilot
- Fecha: 2026-03-11
- Rama: feature/onboarding-preview-stable
- Repos: apps/web, novavision-docs
- Archivos:
  - apps/web/src/components/admin/StoreDesignSection/index.jsx
  - apps/web/src/components/admin/StoreDesignSection/SectionPropsEditor.jsx
  - apps/web/src/__tests__/store-design-section.test.jsx

## Resumen

Se refactorizó el tab de estructura dentro de Store Design para que deje de persistir cambios en caliente sobre `home_sections` y pase a trabajar con un borrador local:

- el preview interactúa primero con un draft local scoped por tenant;
- agregar, reemplazar, mover, borrar y editar bloques ya no pega inmediatamente contra la API;
- el usuario aplica la estructura cuando decide publicar el borrador;
- si faltan créditos de `ws_action_structure_edit`, el borrador se conserva en storage y la UI deriva a compra;
- la superficie ahora muestra todo el catálogo estructural, incluyendo bloques bloqueados por plan;
- la copy se alineó mejor a “Estructura del storefront” en lugar de “Página real del storefront”.

## Por qué

El flujo previo tenía tres problemas de producto:

1. cada click estructural impactaba directo en el storefront real;
2. con 0 créditos el usuario chocaba con `409 Conflict` antes de poder explorar;
3. la UI no mostraba claramente qué componentes existían, qué estaba bloqueado y cuándo se aplicaban los cambios.

Con este cambio, Store Design se acerca más al mental model del Step 4: preview primero, aplicar después, y bloqueo comercial accionable sin perder trabajo.

## Detalle técnico

- Se introdujo un borrador local scoped por tenant para la estructura de Store Design.
- El preview usa el borrador cuando existe; si no, cae a la estructura publicada o al preset visual del template.
- La barra inferior ahora diferencia el modo estructura del guardado visual de template/theme.
- `Aplicar cambios` ejecuta una secuencia controlada contra la API actual:
  - altas de bloques nuevos
  - reemplazos
  - updates de props
  - bajas
  - reorder final
- Se estima la cantidad de acciones estructurales antes de aplicar para detectar faltante de créditos sin golpear la API prematuramente.
- Se mantuvo el contrato backend actual; no se agregó un endpoint batch nuevo en esta iteración.

## Cómo probar

En apps/web:

```bash
npx eslint src/components/admin/StoreDesignSection/index.jsx src/components/admin/StoreDesignSection/SectionPropsEditor.jsx src/__tests__/store-design-section.test.jsx
npm run test:unit -- src/__tests__/store-design-section.test.jsx
npm run typecheck
npm run build
```

Flujo manual sugerido:

1. Abrir `admin-dashboard?storeDesign` en un tenant con Store Design habilitado.
2. Ir al tab `Estructura`.
3. Seleccionar un bloque del catálogo, incluso con créditos en 0.
4. Confirmar que el preview cambia sin persistir en vivo.
5. Editar contenido del bloque y verificar que el inspector habla de borrador, no de guardado inmediato.
6. Intentar aplicar con créditos insuficientes y confirmar:
   - mensaje comercial claro
   - borrador conservado al refrescar
7. Comprar créditos o usar un tenant con saldo y aplicar.
8. Confirmar que el storefront publicado recién cambia al aplicar.

## Riesgos / notas

- El apply estructural sigue usando el contrato actual por operación, por lo que un borrador grande consume múltiples acciones de estructura.
- El comando de tests unitarios del repo sigue arrastrando dos suites históricas ajenas a este cambio:
  - `src/__tests__/addon-store-dashboard.test.jsx`
  - `src/__tests__/contact-section-renderer.test.jsx`
  La suite específica de Store Design sí pasó.