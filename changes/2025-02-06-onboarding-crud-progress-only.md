# Cambio: CRUD onboarding → solo progress JSON (eliminar queries a multicliente)

- **Autor:** agente-copilot
- **Fecha:** 2025-02-06
- **Rama:** feature/automatic-multiclient-onboarding
- **Repos:** templatetwobe (API), novavision (Admin)

---

## Archivos modificados

### API (templatetwobe)
- `src/admin/admin.service.ts`

### Admin (novavision)
- `src/pages/AdminDashboard/ClientApprovalDetail.jsx`

---

## Resumen del cambio

### Corrección arquitectónica: la página ClientApprovalDetail es de **onboarding**, no de tiendas publicadas

La página de aprobación de clientes (`ClientApprovalDetail`) es exclusivamente para el flujo de onboarding pre-publicación. Todo el CRUD de esta página debe operar **únicamente** sobre `nv_onboarding.progress` (JSON en admin DB). Nunca debe tocar la base multicliente.

### Bugs corregidos

1. **FAQs `created_at`**: El endpoint devolvía `"column faqs.created_at does not exist"` porque la tabla multicliente `faqs` no tiene esa columna. Se eliminó la referencia.

2. **Categories vacías**: La UI mostraba `(5/4) Sin categorías` porque el endpoint leía de la tabla multicliente (vacía) en vez del progress JSON (que tenía 5 categorías). Ahora lee siempre del progress.

3. **UI inconsistente**: Categories/FAQs/Services usaban `<button>` + `<FaTimes>` con position absolute. Se estandarizaron a `<Button variant="secondary">` + `<FaTrash>` con layout flex, igual que Products.

### Cambios en admin.service.ts

| Método | Antes | Después |
|--------|-------|---------|
| `getAccountCategories` | Híbrido (multicliente → fallback progress) | Solo progress JSON |
| `createAccountCategory` | Híbrido (insert multicliente → fallback progress) | Solo progress JSON |
| `deleteAccountCategory` | Híbrido (delete multicliente → fallback progress) | Solo progress JSON |
| `getAccountFaqs` | Híbrido (multicliente → fallback progress) | Solo progress JSON |
| `createAccountFaq` | Híbrido (insert multicliente → fallback progress) | Solo progress JSON |
| `deleteAccountFaq` | Híbrido (delete multicliente → fallback progress) | Solo progress JSON |
| `refreshCompletionChecklist` | Firma de 4 args (adminSupa, accountId, backendSupa?, clientId?) | Firma de 2 args (adminSupa, accountId) — solo cuenta desde progress |

### Cambios en ClientApprovalDetail.jsx

- **Categorías**: `<button>` + `<FaTimes size={10}>` → `<Button variant="secondary">` + `<FaTrash size={10}>` con flex layout
- **Servicios**: misma estandarización, de position:absolute a flex layout
- **FAQs**: misma estandarización, de position:absolute a flex layout

---

## Principio arquitectónico

```
┌─────────────────────────────────┐    ┌─────────────────────────────────┐
│   Onboarding / Aprobación       │    │   Tienda Publicada              │
│   (ClientApprovalDetail)        │    │   (Post-provisioning)           │
│                                 │    │                                 │
│   Fuente: nv_onboarding.progress│    │   Fuente: multicliente DB       │
│   (Admin DB, JSON)              │    │   (products, categories, faqs)  │
│                                 │    │                                 │
│   ❌ NUNCA toca multicliente    │    │   ✅ Lee/escribe multicliente   │
└─────────────────────────────────┘    └─────────────────────────────────┘
```

---

## Cómo probar

1. Abrir un cliente en estado `pending_approval` o `incomplete`
2. Tab **Categorías**: verificar que muestra las categorías del progress JSON
3. Tab **FAQs**: verificar que lista las FAQs del progress, sin error `created_at`
4. Agregar/eliminar categoría → se persiste en progress, no en multicliente
5. Agregar/eliminar FAQ → se persiste en progress, no en multicliente
6. Botones de eliminar ahora muestran ícono de papelera (FaTrash) consistente

---

## Build

- **API**: `npm run build` → 0 errores, 741 warnings (solo `no-explicit-any`)
- **Admin**: `npm run typecheck` → sin errores

---

## Notas de seguridad

- No se modificó ningún endpoint público ni se cambiaron permisos
- Se redujo la superficie de ataque al eliminar queries innecesarias a multicliente desde el flujo de onboarding
