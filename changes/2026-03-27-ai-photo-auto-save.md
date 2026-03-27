# AI Photo Auto-Save + Discard UX

**Fecha:** 2026-03-27
**Apps:** API, Web
**Tipo:** Feature + Bug fix (Ticket #3 Farma)

## Problema

Las imagenes generadas por IA en modo creacion de producto se guardaban en storage temporal (`/temp/`). Si el usuario no guardaba el producto explicitamente, las imagenes se perdian. Esto causaba el problema reportado por el cliente Farma (ticket #3).

## Cambios

### API (`apps/api`)
- **`ai-generation.controller.ts`**: Endpoint `POST /products/ai-photo-from-content` ahora guarda directamente en `tenant_media` (permanente) en lugar de temp storage. Retorna `{ media_id, public_url, variants }` en vez de `{ temp_url, temp_key }`.
- **`confirm-ai-image`**: Marcado como DEPRECATED con log de warning. Mantenido para backward compat.

### Web (`apps/web`)
- **`ProductModal/index.jsx`**:
  - Modo creacion usa `media_id`/`public_url` directamente (sin temp flow)
  - Eliminado flujo de `confirm-ai-image` del `onSubmit`
  - Eliminado `aiTempKeys` del objeto `updatedProduct`
  - Nuevo handler `handleDiscardAiPhoto` que borra de `tenant_media` via `DELETE /media-library/:id`
  - Textos actualizados para comunicar auto-guardado
- **`AiImagePreviewModal.jsx`**:
  - Nueva prop `onDiscard` para boton "Descartar" (rojo, borra imagen)
  - Nueva prop `autoSaved` para hint visual de auto-guardado
  - 3 acciones: Descartar (borra), Cerrar (imagen queda en biblioteca), Usar en producto
  - Hint: "Guardada automaticamente en tu biblioteca de medios"

## Flujo nuevo

1. Usuario genera foto AI → se guarda permanentemente en `tenant_media`
2. Modal muestra la imagen con hint de auto-guardado
3. **Usar en producto** → agrega a galeria del producto
4. **Cerrar** → cierra modal, imagen queda en biblioteca de medios
5. **Descartar** → borra de `tenant_media` y cierra

## Ticket de soporte

- **Ticket #3** (Farma): "Tengo problemas para generar una imagen de un producto con ia"
- **Causa raiz**: Imagenes temporales se perdian por falta de guardado explicito
- **Resolucion**: Auto-guardado permanente + deploy a ambas ramas prod
- **Status**: Resolved

## Commits

- API: `4bdf462` en `feature/automatic-multiclient-onboarding`
- Web: `aaa9f3c` en `develop`, cherry-picked a `feature/multitenant-storefront` y `feature/onboarding-preview-stable`
- Monorepo: `2402df6` en `develop`
