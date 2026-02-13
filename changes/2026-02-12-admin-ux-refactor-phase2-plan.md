# Admin UX/UI Refactor — Fase 2: Migración completa de componentes

- **Autor:** agente-copilot
- **Fecha:** 2026-02-12
- **Rama:** `feature/multitenant-storefront`
- **Repo:** templatetwo (web)

---

## Contexto

La Fase 1 (commit `4f0e8c8`) estableció la librería `_shared/` con 8 componentes reusables y migró parcialmente 10+ componentes al sistema de tokens `--nv-admin-*`. Sin embargo, muchos componentes todavía usan:

- **`themeUtils`** (styled-components con `${({ theme }) => getSurface(theme)}`)
- **`globalStyles`** exports legacy (`Button`, `ModalOverlay`, `Modal`, `ModalTitle`, `ModalBody`)
- **Colores hardcoded** (`#hex`, `rgba(...)`)
- **Spinners/empty/error states custom** en vez de los componentes `_shared`
- **Tokens storefront** (`--nv-*`) en vez de admin (`--nv-admin-*`)

---

## Inventario de estado actual

### ✅ Ya refactorizados (referencia)
| Componente | Estado |
|---|---|
| OrderDashboard | ✅ _shared + tokens completo |
| ProductDashboard | ✅ _shared + bridge pattern |

### 🟡 Tokens OK, falta adoptar _shared
| Componente | Líneas | Pendiente |
|---|---|---|
| ContactInfoSection | ~454 | Reemplazar globalStyles → _shared, usar AdminModal para delete |
| FaqSection | ~469 | Igual |
| ServiceSection | ~598 | Igual |
| SocialLinksSection | ~527 | Igual |
| AnalyticsDashboard | ~519 | Agregar AdminLoadingInline/AdminErrorState |
| BannerSection | ~537 | Agregar AdminLoadingInline/AdminEmptyState, reemplazar modales |
| LogoSection | ~316 | Adoptar _shared loading/error |
| PaymentsConfig | ~1774 | Agregar _shared loading/error |

### 🟠 Tokens parciales + deuda
| Componente | Líneas | Pendiente |
|---|---|---|
| CouponDashboard | ~1353 | 18+ status colors hardcoded → mapa semántico |
| SubscriptionManagement | ~1515 | themeUtils en JSX, spinner custom, fallbacks CSS |
| UsageDashboard | ~423 | Tokens storefront → admin, spinner custom |

### 🔴 Legacy completo
| Componente | Líneas | Pendiente |
|---|---|---|
| ConfirmModal | ~240 | themeUtils completo → tokens admin |
| UserDashboard | ~660 | themeUtils 100%, globalStyles, 3 modales inline |
| IdentityConfigSection | ~591 | Tokens storefront, inline styles, 8 colores hardcoded |

---

## Plan por fases

### Fase 1 — Fundación: ConfirmModal + CRUD Sections (4 componentes)
**Impacto:** Alto. ConfirmModal es dependency de muchos componentes.

| # | Componente | Trabajo | Esfuerzo |
|---|---|---|---|
| 1.1 | **ConfirmModal** | Migrar themeUtils → `--nv-admin-*` tokens. Limpiar colores hardcoded. | ~45min |
| 1.2 | **ContactInfoSection** | Reemplazar globalStyles (Button/Modal*) → AdminButton + AdminModal. Agregar AdminEmptyState. | ~45min |
| 1.3 | **FaqSection** | Igual que ContactInfoSection | ~45min |
| 1.4 | **ServiceSection** | Igual que ContactInfoSection | ~45min |
| 1.5 | **SocialLinksSection** | Igual que ContactInfoSection | ~45min |

**Entregable:** Los 4 CRUD sections (Contact, FAQ, Service, Social) y ConfirmModal sin dependencias `globalStyles` legacy.

---

### Fase 2 — Dashboards visuales (4 componentes)
**Impacto:** Medio. Mejora visual consistente en dashboards de datos.

| # | Componente | Trabajo | Esfuerzo |
|---|---|---|---|
| 2.1 | **AnalyticsDashboard** | Agregar AdminLoadingInline, AdminErrorState donde corresponda | ~30min |
| 2.2 | **BannerSection** | Agregar AdminLoadingInline, AdminEmptyState, migrar modales globales → AdminModal | ~1h |
| 2.3 | **LogoSection** | Agregar AdminLoadingInline si no tiene, review tokens | ~20min |
| 2.4 | **UsageDashboard** | Migrar `--nv-*` → `--nv-admin-*`, reemplazar spinner custom → AdminLoadingInline | ~1h |

**Entregable:** Dashboards visuales consistentes con loading/error/empty states uniformes.

---

### Fase 3 — Componentes pesados (5 componentes)
**Impacto:** Alto en consistencia, esfuerzo mayor.

| # | Componente | Trabajo | Esfuerzo |
|---|---|---|---|
| 3.1 | **UserDashboard** | Migrar style.jsx completo themeUtils → tokens, reemplazar 3 modales inline → AdminModal, globalStyles → _shared | ~2.5h |
| 3.2 | **IdentityConfigSection** | Separar styles a style.jsx, migrar a `--nv-admin-*`, reemplazar colores hardcoded domain status, agregar AdminLoadingInline | ~2h |
| 3.3 | **CouponDashboard** | Extraer 18+ status colors a mapa semántico con tokens, limpiar tokens storefront residuales | ~1.5h |
| 3.4 | **SubscriptionManagement** | Migrar themeUtils del JSX, reemplazar spinner custom, limpiar fallbacks CSS | ~2h |
| 3.5 | **PaymentsConfig** | Agregar _shared loading/error, review completo | ~1h |

**Entregable:** Todos los componentes admin migrados completamente.

---

## Patrones de reemplazo (guía rápida)

### globalStyles → _shared

```jsx
// ANTES
import { Button, ModalOverlay, Modal, ModalTitle, ModalBody } from 'globalStyles';

// DESPUÉS  
import { AdminButton, AdminModal } from 'components/admin/_shared';
```

### themeUtils → CSS vars

```jsx
// ANTES (style.jsx)
background: ${({ theme }) => getSurface(theme)};
color: ${({ theme }) => getText(theme)};
border: 1px solid ${({ theme }) => getBorder(theme)};

// DESPUÉS
background: var(--nv-admin-card-bg, #fff);
color: var(--nv-admin-text, #1e293b);
border: 1px solid var(--nv-admin-border, #e2e8f0);
```

### Modal inline → AdminModal

```jsx
// ANTES
{showDeleteModal && (
  <ModalOverlay onClick={() => setShowDeleteModal(false)}>
    <Modal onClick={e => e.stopPropagation()}>
      <ModalTitle>¿Eliminar elemento?</ModalTitle>
      <ModalBody>Esta acción no se puede deshacer.</ModalBody>
      <div className="btnCtn">
        <Button className="secondary" onClick={() => setShowDeleteModal(false)}>Cancelar</Button>
        <Button className="delete" onClick={handleDelete}>Eliminar</Button>
      </div>
    </Modal>
  </ModalOverlay>
)}

// DESPUÉS
<AdminModal
  open={showDeleteModal}
  onClose={() => setShowDeleteModal(false)}
  title="¿Eliminar elemento?"
  footer={
    <>
      <AdminButton $variant="secondary" onClick={() => setShowDeleteModal(false)}>Cancelar</AdminButton>
      <AdminButton $variant="danger" onClick={handleDelete}>Eliminar</AdminButton>
    </>
  }
>
  <p>Esta acción no se puede deshacer.</p>
</AdminModal>
```

### Loading/Empty/Error custom → _shared

```jsx
// ANTES
if (loading) return <div className="spinner">Cargando...</div>;
if (error) return <p style={{color:'red'}}>{error}</p>;
if (!data.length) return <p>No hay datos</p>;

// DESPUÉS
if (loading) return <AdminLoadingInline text="Cargando datos…" />;
if (error) return <AdminErrorState message={error} onRetry={fetchData} />;
if (!data.length) return <AdminEmptyState title="Sin datos" message="No hay elementos para mostrar." />;
```

---

## Checklist de validación por componente

- [ ] Sin imports de `globalStyles` (Button/Modal/ModalOverlay/etc.)
- [ ] Sin imports de `themeUtils` (getSurface/getText/getBorder/etc.)
- [ ] Todos los colores usan `var(--nv-admin-*)` o tokens semánticos
- [ ] Loading states usan `AdminLoadingInline` o `AdminLoadingOverlay`
- [ ] Empty states usan `AdminEmptyState`
- [ ] Error states usan `AdminErrorState`
- [ ] Modales de confirmación usan `ConfirmModal` o `AdminModal`
- [ ] Botones de acción usan `AdminButton` con variantes semánticas

---

## Riesgos

1. **ShippingPanel** (3564 líneas): el componente más grande. Los colores de proveedores de envío son funcionales (semáforo). Se propone NO migrar esos colores a tokens sino dejarlos como constante documentada.
2. **CouponDashboard status colors**: Similar a ShippingPanel — los colores de badges (active=verde, expired=naranja, etc.) son funcionales. Se propone un objeto `STATUS_COLORS` centralizado.
3. **ConfirmModal es dependencia directa** de UserDashboard y potencialmente otros. Migrarlo primero evita trabajo doble.
4. **PaymentsConfig tiene Simulator.jsx** embebido. El refactor se limita a loading/error patterns, no a la lógica del simulador.

---

## Comandos de validación

```bash
# Después de cada fase
npm run ci:storefront   # prebuild + no-mocks + lint + typecheck + build

# Verificación rápida de imports legacy residuales
grep -rn "from 'globalStyles'" src/components/admin/ --include="*.jsx" | grep -v node_modules
grep -rn "from.*themeUtils" src/components/admin/ --include="*.jsx" | grep -v node_modules
```
