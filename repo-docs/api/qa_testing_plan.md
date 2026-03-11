# Plan de QA - Testing Exhaustivo

## 🎯 Objetivos del QA

Validar los 3 sistemas implementados:

1. **Theme System** - Backward compatibility + Delta storage
2. **Security** - RLS, Maintenance Guard, Identity Modal
3. **Design Studio** - Plan gating, Section limits, Custom palettes

---

## 📋 ESCENARIO 1: Starter Plan (Happy Path)

### Setup

- Plan: Starter ($20/mes)
- Límites: 5 secciones máx, 0 custom palettes

### Pasos de Testing

**1.1 Onboarding Completo**

```
□ Ir a admin.novavision.app
□ Paso 1: Email + Slug "tienda-starter-test"
  Expected: sessionId en localStorage

□ Paso 2: Subir logo (opcional - saltar)
  Expected: Avanza a paso 3

□ Paso 3: Catalog manual (3 productos)
  Expected: products_draft en localStorage

□ Paso 4: Template "classic" + Palette "ocean"
  Expected: Guardado en nv_onboarding

□ Intentar agregar 6ta sección
  Expected: ❌ Bloqueado - Modal upsell aparece

□ Verificar custom palette editor NO disponible
  Expected: ❌ No visible (Starter no tiene acceso)
```

**1.2 Payment Flow**

```
□ Paso 5: Seleccionar Starter plan
□ Click "Pagar con Mercado Pago"
  Expected: Redirect a MP checkout

□ Completar pago (sandbox)
  Expected: Webhook recibido, provision job creado
```

**1.3 Identity Verification**

```
□ Después de publish success
  Expected: IdentityModal aparece (blocking)

□ Ingresar DNI inválido: "12345" (5 dígitos)
  Expected: Error "Debe contener 7 u 8 dígitos"

□ Ingresar DNI válido: "12345678"
  Expected: Modal cierra, redirect a dashboard

□ Verificar DB: nv_accounts.identity_verified = true
□ Second login
  Expected: Identity modal NO aparece
```

**1.4 Store Validation**

```
□ Visitar: https://tienda-starter-test.novavision.app
  Expected: Store live y funcional

□ Verificar theme aplicado (ocean colors)
□ Verificar 5 secciones o menos
□ Verificar productos visibles
```

**Success Criteria:**

- ✅ Onboarding completa sin errores
- ✅ 6ta sección bloqueada
- ✅ Custom palette no disponible
- ✅ Identity verification funciona
- ✅ Store live con theme correcto

---

## 📋 ESCENARIO 2: Growth Plan (Custom Palette)

### Setup

- Plan: Growth ($220/mes)
- Límites: 10 secciones máx, 3 custom palettes

### Pasos de Testing

**2.1 Custom Palette Creation**

```
□ Completar pasos 1-3 (igual Starter)

□ Paso 4: Seleccionar palette base "sunset"
□ Click "Personalizar Colores" (Growth+ feature)
  Expected: Custom palette editor abre

□ Modificar:
  - Primary color: #FF6B9D
  - Secondary color: #C3E88D

□ Guardar como "Mi Paleta Rosa"
  Expected:
    - Draft en localStorage (custom_palette_draft)
    - selected_palette_key = "custom-mi-paleta-rosa"
```

**2.2 Section Management**

```
□ Agregar 8 secciones diferentes
  Expected: OK (< 10 limit)

□ Intentar agregar 11va sección
  Expected: ❌ Modal upsell "Upgrade a Pro"

□ Reemplazar header-1 → header-2
  Expected: Props migrados (brandName preservado)
```

**2.3 Publish & Persistence**

```
□ Completar payment (Growth plan)
□ Publish store
  Expected: Worker ejecuta syncCustomPalette()

□ Verificar DB: custom_palettes table
  Query:
    SELECT * FROM custom_palettes
    WHERE client_id = 'abc-123';

  Expected: 1 row con:
    - palette_name: "Mi Paleta Rosa"
    - theme_vars: {"--nv-primary": "#FF6B9D", ...}
```

**2.4 Palette Limit**

```
□ Crear 2 custom palettes más
  Expected: OK (total 3)

□ Intentar crear 4ta custom palette
  Expected: ❌ Error "Max 3 custom palettes"
```

**Success Criteria:**

- ✅ Custom palette editor disponible
- ✅ Palette persiste en DB post-publish
- ✅ 10 secciones permitidas
- ✅ 11va sección bloqueada
- ✅ Límite 3 custom palettes enforced

---

## 📋 ESCENARIO 3: Pro Plan (Unlimited)

### Setup

- Plan: Pro ($2000/mes)
- Límites: 15 secciones máx, ∞ custom palettes

### Pasos de Testing

**3.1 Pro Sections Access**

```
□ En Step4, verificar section library
  Expected: Todas las sections desbloqueadas
    - analytics-dashboard ✅
    - custom-code ✅
    - advanced-hero ✅
```

**3.2 Maximum Sections**

```
□ Agregar 15 secciones
  Expected: OK

□ Intentar agregar 16va
  Expected: ❌ Bloqueado (hard limit backend)
```

**3.3 Unlimited Custom Palettes**

```
□ Crear 5 custom palettes
  Expected: OK

□ Crear 6ta, 7ma, 8va...
  Expected: OK (sin límite)
```

**3.4 Backend Validation Bypass Attempt**

```
□ Modificar request payload (DevTools)
  POST /onboarding/:id/preferences
  Body: { design_config: { sections: [20 sections] } }

  Expected: ❌ 400 Bad Request
  Error: "Plan pro allows max 15 sections, but design has 20"
```

**Success Criteria:**

- ✅ Todas las sections accesibles
- ✅ 15 secciones permitidas
- ✅ 16va rechazada (backend)
- ✅ Custom palettes ilimitadas
- ✅ Backend validation previene bypass

---

## 📋 ESCENARIO 4: Theme System Validation

### Backward Compatibility Test

```
□ Cliente existente con theme legacy
□ Deploy nuevo code (theme system refactored)
  Expected: Store sigue funcionando (1084+ usages)

□ Verificar:
  - Colors aplicados correctamente
  - Components renders sin errores
  - No console errors
```

### Delta Storage Test

```
□ Cliente con theme override (solo primary color)
□ Verificar DB: client_themes.overrides
  Expected: Solo 1 key: {"tokens":{"colors":{"primary":"#custom"}}}

□ Size comparison:
  - Full theme object: ~10KB
  - Override only: ~100B

  Expected: 99% reducción
```

---

## 📋 ESCENARIO 5: Security Validation

### RLS Test

```
□ Como user A: SELECT * FROM nv_accounts WHERE id != my_id
  Expected: 0 rows (blocked by RLS)

□ Como service_role: Same query
  Expected: All rows visible
```

### MaintenanceGuard Test

```
□ Set maintenance_mode = true para client X
  UPDATE backend_clusters
  SET maintenance_mode = true
  WHERE client_id = 'client-x';

□ User de client X intenta POST request
  Expected: 503 Service Unavailable
  Headers: Retry-After: 3600

□ User de client Y (maintenance_mode = false)
  Expected: Request proceeds normally
```

---

## 🧪 TESTS AUTOMATIZADOS (Opcional)

### Unit Tests

```typescript
// design.validator.spec.ts
describe('validateDesignConfig', () => {
  it('should reject 6 sections for starter', () => {
    const config = { sections: Array(6).fill({}) };
    const result = validateDesignConfig(config, 'starter');
    expect(result.valid).toBe(false);
    expect(result.errors).toContain('Max 5 sections');
  });

  it('should accept custom palette for growth', () => {
    const config = {
      paletteKey: 'custom-test',
      themeOverride: {...}
    };
    const result = validateDesignConfig(config, 'growth');
    expect(result.valid).toBe(true);
  });
});
```

### Integration Tests

```typescript
// identity-flow.e2e.spec.ts
describe("Identity Verification Flow", () => {
  it("should show modal if not verified", async () => {
    // Mock: identity_verified = false
    const modal = await page.waitForSelector('[data-testid="identity-modal"]');
    expect(modal).toBeTruthy();
  });

  it("should save DNI and close modal", async () => {
    await page.fill('[data-testid="dni-input"]', "12345678");
    await page.click('[data-testid="submit-dni"]');

    // Verify API called
    expect(mockPost).toHaveBeenCalledWith("/accounts/identity", {
      session_id: expect.any(String),
      dni: "12345678",
    });
  });
});
```

---

## 📊 QA CHECKLIST MASTER

### Pre-QA Setup

- [ ] All dev servers running (API, Admin, Web)
- [ ] Test database seeded with all 3 plans
- [ ] MP sandbox credentials configured
- [ ] RLS policies verified active

### Functional Tests

- [ ] Starter: 5 section limit ✓
- [ ] Starter: No custom palette ✓
- [ ] Growth: Custom palette persists ✓
- [ ] Growth: 3 palette limit ✓
- [ ] Growth: 10 section limit ✓
- [ ] Pro: All sections unlocked ✓
- [ ] Pro: 15 section limit ✓
- [ ] Pro: Unlimited palettes ✓

### Security Tests

- [ ] RLS blocks unauthorized access ✓
- [ ] MaintenanceGuard returns 503 ✓
- [ ] Backend validation prevents bypass ✓
- [ ] Identity modal shows if not verified ✓
- [ ] DNI saved correctly ✓

### Integration Tests

- [ ] Onboarding → Payment → Provision → Live ✓
- [ ] localStorage cleared post-publish ✓
- [ ] Worker syncs custom palette ✓
- [ ] Theme applied correctly ✓

### Regression Tests

- [ ] Existing stores still work (backward compat) ✓
- [ ] No console errors ✓
- [ ] Performance acceptable (Lighthouse > 80) ✓

---

## 🐛 Known Issues / Edge Cases

### To Test

1. **Concurrent Edits:** 2 users editing same section simultaneously
2. **Network Failure:** Publish fails mid-provision
3. **Invalid JSON:** AI returns malformed catalog data
4. **Browser Cache:** Old wizard state persists
5. **MP Webhook Retry:** Duplicate provision attempts

### Mitigation

- Idempotency in worker (provision job status check)
- Error boundaries in React components
- Validation before saving to DB
- localStorage versioning
- Job deduplication logic

---

## ✅ QA Sign-Off Criteria

Para considerar QA completo, ALL de estos deben pasar:

- ✅ All 5 escenarios ejecutados sin errores críticos
- ✅ Backend validation enforceda (bypass attempts blocked)
- ✅ RLS policies activas y funcionando
- ✅ Identity verification flow completo
- ✅ Custom palette persistence verified
- ✅ Backward compatibility confirmed
- ✅ No console errors en ningún flow
- ✅ Performance aceptable (< 3s load time)

---

## 📝 Bug Report Template

```markdown
### Bug Report

**Scenario:** [Starter/Growth/Pro - Specific Test]
**Expected:** [What should happen]
**Actual:** [What happened instead]
**Steps to Reproduce:**

1. Step 1
2. Step 2
3. ...

**Screenshots:** [If applicable]
**Console Errors:** [If any]
**DB State:** [Relevant queries]
**Priority:** [Critical/High/Medium/Low]
```

---

**Tiempo Estimado Total:** 4-5 horas  
**Owner:** QA Team / Developer  
**Status:** Ready to Execute
