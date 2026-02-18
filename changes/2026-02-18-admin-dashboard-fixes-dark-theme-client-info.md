# Cambios: Admin dashboard stability, dark theme, client info panel, UX fixes

- **Autor:** agente-copilot
- **Fecha:** 2026-02-18
- **Ramas:** Web `feature/multitenant-storefront` (e7b114c) | Admin `feature/automatic-multiclient-onboarding` (b566a4f) | API `feature/automatic-multiclient-onboarding` (fe1a1c6)

---

## Archivos modificados

### Web (templatetwo) — 8 archivos
| Archivo | Cambio |
|---------|--------|
| `src/components/admin/AnalyticsDashboard/index.jsx` | useRef + useCallback para estabilizar `showToast` |
| `src/components/admin/ReviewsDashboard/index.jsx` | useRef fix para loop infinito por `showToast` inestable |
| `src/components/admin/QADashboard/index.jsx` | Mismo pattern useRef |
| `src/components/admin/IdentityConfigSection/index.jsx` | Removido toggle "Powered by NovaVision", agregado preview live de footer links por columna |
| `src/components/admin/SupportTickets/style.jsx` | SendButton: `padding: 0`, `min-width/height: 40px`, `overflow: visible`, svg display rules |
| `src/components/admin/PaymentsConfig/index.jsx` | Key compuesto en `mpRates.map()` para evitar duplicate key warnings |
| `src/pages/AdminDashboard/index.jsx` | Removida sección socialLinks redundante (ya está en IdentityConfigSection) |
| `src/sections/footer/ClassicFooter/index.jsx` | "Powered by NovaVision" siempre visible (sin toggle) |

### Admin (novavision) — 2 archivos
| Archivo | Cambio |
|---------|--------|
| `src/pages/AdminDashboard/SupportConsoleView.jsx` | Dark theme completo + panel de info del cliente con contacto rápido |
| `src/i18n/es.json` | Traducciones para nuevos labels del panel de soporte |

### API (templatetwobe) — 1 archivo
| Archivo | Cambio |
|---------|--------|
| `src/support/support.service.ts` | Expanded `nv_accounts` select: +phone, is_active, plan_paid_until, last_payment_at |

---

## Resumen de cambios

### 1. Estabilidad de dashboards (useRef pattern)
**Problema:** AnalyticsDashboard, ReviewsDashboard y QADashboard sufrían re-renders infinitos o inestabilidad porque `showToast` del contexto `useToast()` no está memoizado, causando que `useEffect`/`useCallback` se re-ejecuten en cada render.

**Solución:** Patrón `useRef` + `useEffect` para mantener referencia estable:
```jsx
const showToastRef = useRef(showToast);
useEffect(() => { showToastRef.current = showToast; }, [showToast]);
// En callbacks: showToastRef.current('mensaje') en vez de showToast('mensaje')
```

### 2. Botón de envío en tickets (SendButton)
**Problema:** El ícono FiSend dentro del SendButton (40×40px) no se veía porque el padding global de botones lo ocultaba.

**Solución:** Agregado `padding: 0`, `min-width: 40px`, `min-height: 40px`, `overflow: visible` y reglas explícitas para `svg { display: block; flex-shrink: 0; }`.

### 3. Dark theme en consola de soporte (Admin)
**Problema:** SupportConsoleView tenía TODOS los colores hardcodeados (`#1a1a2e`, `#fff`, `#6b7280`, etc.). En dark mode, el texto oscuro era invisible sobre fondo oscuro.

**Solución:** Conversión completa de todos los styled-components a theme tokens con fallbacks:
- `${({ theme }) => theme.text?.primary || '#1a1a2e'}`
- `${({ theme }) => theme.card?.bg || theme.bg?.surface || '#fff'}`
- `${({ theme }) => theme.border?.default || '#e5e7eb'}`
- etc.

Componentes convertidos: Header, MetricCard, SearchInput, FilterSelect, Table, Pagination, EmptyState, DetailContainer, TicketHeader, ActionButton, MessageBubble, ReplyArea, CheckboxLabel, Sidebar, SidebarField, BackButton.

### 4. Panel de info del cliente en soporte
**Problema:** El super admin no tenía acceso rápido a datos del cliente (teléfono, estado de suscripción, plan) al gestionar tickets.

**Solución:**
- **Backend:** Expanded select de `nv_accounts` para incluir `phone`, `is_active`, `plan_paid_until`, `last_payment_at`
- **Frontend:** Nuevo `ClientInfoCard` entre el sidebar y el área de conversación con:
  - Nombre del negocio, email, plan, teléfono
  - Fechas de suscripción (plan_paid_until, last_payment_at)
  - Badge de estado (Activo/Inactivo)
  - Botón WhatsApp (abre wa.me con número del cliente)
  - Botón Email (abre mailto con asunto del ticket)

### 5. Duplicate key warnings (PaymentsConfig)
**Problema:** `mpRates.map((r, idx) => <tr key={r.id || idx}>)` generaba warnings de duplicate key cuando múltiples filas de mp_fee_table compartían el mismo id numérico.

**Solución:** Key compuesto único: `` key={`rate-${r.method}-${r.settlement_days ?? r.settlement}-${r.installments_from}-${idx}`} ``

### 6. UX de footer e identidad
- Toggle "Powered by NovaVision" eliminado — ahora siempre se muestra
- Sección socialLinks removida de AdminDashboard (redundante con IdentityConfigSection)
- Preview live de footer links por columna en IdentityConfigSection

---

## Validación

| App | Lint | Typecheck | Build |
|-----|------|-----------|-------|
| API | 0 errores ✅ | Sin errores ✅ | — |
| Web | 0 errores ✅ | Errores preexistentes (.tsx no relacionados) | ✅ 5.79s |
| Admin | 0 errores ✅ | Sin errores ✅ | — |

## Cómo probar

1. **Analytics:** Abrir sección Analytics en admin → no debe haber loop infinito ni crash
2. **SendButton:** Abrir un ticket en soporte (cliente) → el botón de envío debe mostrar el ícono
3. **Dark theme:** Entrar a Admin (super admin) → Soporte → verificar que todo se lee en dark mode
4. **Client info:** Abrir un ticket → ver panel lateral con datos del cliente y botones de contacto
5. **Duplicate keys:** Abrir consola del navegador en PaymentsConfig → no deben aparecer warnings de duplicate key
6. **Footer:** Verificar que "Powered by NovaVision" aparece siempre en el footer público

## Notas de seguridad
- El select expandido de `nv_accounts` solo agrega campos no sensibles (phone, is_active, fechas) que ya son visibles para super_admin
- No se exponen tokens ni credenciales
- El panel de info del cliente solo es visible para super_admin (ruta protegida por guard existente)

## Riesgos
- **Bajo:** Si el provider de `useToast` se refactoriza para memoizar `showToast`, los useRef quedan como overhead mínimo pero no rompen nada
- **Nulo:** Los cambios de dark theme son puramente visuales con fallbacks a los colores originales
