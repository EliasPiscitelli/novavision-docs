# Fix: Auto-resolución de items en revisión de onboarding

**Fecha:** 2026-01-28
**Autor:** Copilot Agent
**Rama:** feature/automatic-multiclient-onboarding
**Issue:** Loop infinito en solicitud de cambios de onboarding

---

## Problema Identificado

El sistema de revisión de onboarding tenía un loop donde:

1. Admin solicita cambios (ej: "Falta logo o no cumple formato")
2. El sistema actualiza `client_completion_checklist` con `review_status: 'changes_requested'`
3. **Inmediatamente después**, el método `getApprovalDetail()` sincroniza datos reales y puede actualizar `logo_uploaded: true`
4. El cliente queda **atrapado** con `review_status: 'changes_requested'` pero todos los items completados (71% en el caso reportado)
5. Se generan múltiples eventos de "changes_requested" sin progreso (8 veces en el caso reportado)

**Evidencia del problema:**
```json
{
  "review_status": "changes_requested",
  "review_request_count": 8,
  "review_items": ["Falta logo o no cumple formato"],
  "completion_percentage": 71,
  "logo_uploaded": false  // Pero probablemente el logo SÍ está subido
}
```

---

## Solución Implementada

### 1. Auto-resolución inteligente en `resubmitChecklist()`

**Archivo:** `apps/api/src/client-dashboard/client-dashboard.service.ts`

Cuando el cliente presiona "Reenviar a revisión", el sistema:

1. **Valida cada item solicitado** contra el estado actual del checklist
2. **Auto-elimina items ya resueltos** de la lista de `review_items`
3. **Cambia el estado automáticamente**:
   - Si todos los items están resueltos → `review_status: 'pending_review'`
   - Si quedan items pendientes → `review_status: 'resubmitted'`
4. **Notifica al admin** si se auto-aprueba

**Validaciones implementadas:**
```typescript
// Logo
if (itemLower.includes('logo') && checklist.logo_uploaded) {
  // Auto-clear: logo está subido
}

// Banner
if (itemLower.includes('banner') && checklist.banner_uploaded) {
  // Auto-clear: banner está subido
}

// Productos
if (itemLower.includes('producto') && checklist.products_count > 0) {
  // Auto-clear: hay productos
}

// Categorías
if (itemLower.includes('categor') && checklist.categories_count > 0) {
  // Auto-clear: hay categorías
}

// FAQs
if ((itemLower.includes('faq') || itemLower.includes('pregunta')) && checklist.faqs_added) {
  // Auto-clear: FAQs agregadas
}

// Contacto
if (itemLower.includes('contacto') && checklist.contact_info_added) {
  // Auto-clear: contacto agregado
}

// Redes sociales
if ((itemLower.includes('social') || itemLower.includes('redes')) && checklist.social_links_added) {
  // Auto-clear: redes agregadas
}
```

### 2. Mejora en UI (Frontend)

**Archivo:** `apps/admin/src/pages/ClientCompletionDashboard/index.tsx`

**Cambios:**

1. **Indicador visual de items resueltos:**
   - ✅ Items completados (tachados en verde)
   - ⚠️ Items pendientes (en rojo)
   - Muestra razón de resolución (ej: "Logo ya subido", "5 productos agregados")

2. **Mensaje al usuario:**
   - "Verificaremos automáticamente los items completados"
   - Feedback claro al resubmitir

3. **Feedback de auto-aprobación:**
   ```typescript
   if (autoApproved) {
     setAlertState({
       title: "✅ Aprobado automáticamente",
       message: "Todos los items solicitados están completos. Tu tienda está en revisión final."
     });
   }
   ```

### 3. Eventos de auditoría mejorados

**Tabla:** `client_completion_events`

Ahora registra:
```typescript
{
  type: 'resubmitted',
  payload: {
    review_request_count: 8,
    items_resolved: 1,        // Nuevo
    items_remaining: 0,       // Nuevo
    auto_approved: true       // Nuevo
  }
}
```

---

## Flujo Corregido

### Antes:
```
1. Admin: "Falta logo" → review_status: 'changes_requested'
2. Cliente sube logo
3. getApprovalDetail() → actualiza logo_uploaded: true
4. Cliente presiona "Reenviar" → review_status: 'resubmitted'
5. Admin vuelve a revisar → ve que falta logo (contradicción)
6. Loop infinito...
```

### Después:
```
1. Admin: "Falta logo" → review_status: 'changes_requested'
2. Cliente sube logo (o ya estaba subido)
3. Cliente presiona "Reenviar"
4. Sistema valida: logo_uploaded: true → ✅ item resuelto
5. review_items: [] (vacío)
6. review_status: 'pending_review' (auto-aprobado)
7. Notificación al admin
8. FIN ✅
```

---

## Testing

### Caso de prueba 1: Item ya resuelto
```bash
# Estado inicial
review_status: "changes_requested"
review_items: ["Falta logo o no cumple formato"]
logo_uploaded: true

# Acción
POST /client-dashboard/completion-checklist/resubmit

# Resultado esperado
review_status: "pending_review"
review_items: []
auto_approved: true
```

### Caso de prueba 2: Items parcialmente resueltos
```bash
# Estado inicial
review_status: "changes_requested"
review_items: ["Falta logo", "Agregar productos"]
logo_uploaded: true
products_count: 0

# Acción
POST /client-dashboard/completion-checklist/resubmit

# Resultado esperado
review_status: "resubmitted"
review_items: ["Agregar productos"]
auto_approved: false
```

---

## Monitoreo

**Logs a revisar:**
```
Auto-clearing logo issue for {accountId} - logo is uploaded
Resubmit for {accountId}: 1 items → 0 remaining. New status: pending_review
Client {accountId} auto-approved after resolving all review items
```

**Query de auditoría:**
```sql
SELECT 
  account_id,
  type,
  payload->>'items_resolved' as resolved,
  payload->>'items_remaining' as remaining,
  payload->>'auto_approved' as auto_approved,
  created_at
FROM client_completion_events
WHERE type = 'resubmitted'
ORDER BY created_at DESC
LIMIT 20;
```

---

## Riesgos y Consideraciones

### Riesgos Mitigados:
- ❌ **Loop infinito:** resuelto con auto-validación
- ❌ **Contradicciones:** items validados contra estado real
- ❌ **Spam de emails:** auto-aprobación reduce notificaciones

### Consideraciones:
- ⚠️ La validación es **case-insensitive** y basada en **keywords**
- ⚠️ Si el admin escribe items muy específicos no cubiertos, el sistema no los auto-resuelve
- ⚠️ El admin debe seguir revisando casos complejos manualmente

### Extensibilidad:
Para agregar nuevas validaciones, añadir en `resubmitChecklist()`:
```typescript
if (itemLower.includes('nueva_keyword') && checklist.nueva_condicion) {
  // Auto-clear
}
```

---

## Rollback

Si esta solución causa problemas:

1. **Revertir cambios en backend:**
   ```bash
   git revert <commit-hash>
   ```

2. **Restaurar lógica anterior:**
   - Eliminar auto-validación en `resubmitChecklist()`
   - Mantener solo cambio de estado simple

---

## Próximos Pasos

1. ✅ Monitorear logs de auto-aprobación
2. ⏳ Agregar validaciones para casos edge (ej: calidad de imagen)
3. ⏳ Dashboard de admin con métricas de auto-resolución
4. ⏳ Notificación al admin solo cuando requiera intervención manual

---

**Status:** ✅ Implementado y listo para deploy
**Deploy:** Verificar en staging antes de producción
