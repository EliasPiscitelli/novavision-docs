# ONBOARDING REGRESSION CHECKLIST

**Fecha:** 2025-07-25  
**Ref:** ONBOARDING_FIXPACK.md

---

## Pre-requisitos

- [ ] Backend (`apps/api`) levantado con `npm run start:dev`
- [ ] Admin (`apps/admin`) levantado con `npm run dev`
- [ ] Cuenta de prueba con plan Starter, Growth y Enterprise disponibles
- [ ] Cuenta de Mercado Pago sandbox configurada

---

## Regression Tests — Por Issue

### OB-01: Drag & Drop Logo (Step 2)

| # | Caso | Resultado Esperado |
|---|------|--------------------|
| 1 | Arrastrar imagen PNG/JPG sobre la zona punteada | Imagen se previsualiza correctamente |
| 2 | Arrastrar archivo no-imagen (PDF, TXT) | Modal de error: "Archivo inválido" |
| 3 | Arrastrar imagen >2MB | Modal de error: "Archivo demasiado grande" |
| 4 | Click en la zona punteada → seleccionar archivo | Funciona igual que antes (regression) |
| 5 | Arrastrar sobre la zona → verificar feedback visual | Borde se destaca (clase `drag-over`) |
| 6 | Arrastrar fuera de la zona → verificar que desaparece highlight | Borde vuelve a normal |

### OB-02: Botón Importar Sticky (Step 3)

| # | Caso | Resultado Esperado |
|---|------|--------------------|
| 1 | Generar catálogo con >10 productos → scrollear abajo | Botón "Importar" visible como sticky en el bottom |
| 2 | Catálogo con <3 productos | Botón visible normalmente sin sticky (no hay scroll) |
| 3 | Click en botón sticky funciona | Productos se importan correctamente |

### OB-03: Precio == $0 en Catálogo (Step 3)

| # | Caso | Resultado Esperado |
|---|------|--------------------|
| 1 | Generar catálogo IA → verificar precios | Ningún producto muestra $0 (salvo que realmente cueste $0) |
| 2 | Producto SIN descuento | Muestra 1 precio, sin precio tachado |
| 3 | Producto CON descuento real (discountedPrice < originalPrice) | Muestra precio descontado con original tachado |
| 4 | Producto con discountedPrice = null | Muestra originalPrice sin tachado |
| 5 | JSON manual con `"discountedPrice": 0` | NO muestra como descuento, muestra originalPrice |

### OB-04: Replacement Modal con Theme Tokens (Step 4)

| # | Caso | Resultado Esperado |
|---|------|--------------------|
| 1 | Click en "Reemplazar" en un header/footer | Modal aparece con fondo oscuro (dark theme) |
| 2 | Hover sobre variante de componente | Card se destaca con borde violeta (brand-primary) |
| 3 | Textos del modal | Título blanco, subtítulo gris claro, todo legible |
| 4 | Botón Cancelar | Estilizado con borde y fondo consistente con dark theme |

### OB-05: Plan Gating Estructura (Step 4)

| # | Caso | Resultado Esperado |
|---|------|--------------------|
| 1 | Seleccionar template base (Starter) | Plan sugerido = Starter |
| 2 | Agregar sección nueva (custom) | Plan sugerido sube a Growth |
| 3 | Seleccionar paleta premium → agregar sección | Plan = max(paleta, Growth) |
| 4 | Eliminar sección custom → verificar plan baja | ⚠️ Puede mantener Growth si hay otros selections |

### OB-06: Toast sobre Header

| # | Caso | Resultado Esperado |
|---|------|--------------------|
| 1 | Provocar un toast (error de validación) | Toast visible ENCIMA del header |
| 2 | Toast no se corta con el tope del viewport | Completamente visible (top: 100px) |
| 3 | Múltiples toasts | Se apilan correctamente debajo del primero |

### OB-07: Google OAuth Account Selector

| # | Caso | Resultado Esperado |
|---|------|--------------------|
| 1 | Login con Google (1 cuenta cacheada) | Google muestra selector de cuentas |
| 2 | Login con Google (múltiples cuentas) | Muestra todas las cuentas disponibles |
| 3 | Cancelar en el selector | Vuelve al login sin error |

### OB-08: Grid de Planes Desktop (Step 6)

| # | Caso | Resultado Esperado |
|---|------|--------------------|
| 1 | Viewport ≥1024px | 3 planes lado a lado en grid |
| 2 | Viewport <768px | Planes en 1 columna (responsive) |
| 3 | Viewport 768-1023px | Verificar transición suave (2 columnas?) |

### OB-09: No Auto-skip en Pasos de Pago/MP

| # | Caso | Resultado Esperado |
|---|------|--------------------|
| 1 | Completar pago en Step 6 → volver | Puede ver Step 6 con estado confirmado |
| 2 | Conectar MP en Step 7 → volver atrás → avanzar | Step 7 muestra estado "Conectado" con botón Continuar |
| 3 | Después de OAuth callback de MP | Se ve la pantalla de éxito, NO se salta |
| 4 | Click en "Continuar" en Step 7 post-éxito | Avanza a Step 8 |
| 5 | Navegar entre pasos libremente | Ningún paso se salta automáticamente |

### OB-10: Copy de MP Mejorado (Step 7)

| # | Caso | Resultado Esperado |
|---|------|--------------------|
| 1 | Ver Step 7 antes de conectar | Header explica "pagos directo a tu cuenta" y "100% tuya" |
| 2 | Después de conectar exitosamente | Éxito dice "se acreditará directamente en tu cuenta" |

### OB-11: DNI Visible en Aprobación Admin

| # | Caso | Resultado Esperado |
|---|------|--------------------|
| 1 | Abrir detalle de aprobación con DNI (formato raw path) | Imagen de DNI visible correctamente |
| 2 | DNI con formato legacy (URL pública) | Imagen de DNI visible correctamente |
| 3 | DNI con path inexistente | No muestra imagen rota, maneja el null gracefully |
| 4 | Cuenta sin DNI subido | No muestra sección de DNI / placeholder correcto |

### OB-12: Contraste en Success Page (Step 12)

| # | Caso | Resultado Esperado |
|---|------|--------------------|
| 1 | Ver Step 12 | Códigos (`<code>`) tienen contraste fuerte (fondo oscuro, texto violeta) |
| 2 | Dominio en `.domain-code` | Claramente legible con borde visible |
| 3 | Verificar en modo oscuro (si aplica) | CSS vars fallbacks no rompen el contraste |

### OB-13: Mención de Excel para Growth

| # | Caso | Resultado Esperado |
|---|------|--------------------|
| 1 | Ver Step 3 tab IA | Hint de "plan Growth → Excel/CSV" visible debajo del texto intro |
| 2 | Texto no bloquea ni confunde | Es informativo, no un botón |

---

## Regression General

| # | Caso | Resultado Esperado |
|---|------|--------------------|
| 1 | Completar wizard completo Steps 1-12 | Flujo sin interrupciones |
| 2 | Refrescar página en cualquier paso | Wizard retoma el paso correcto |
| 3 | Navegar Back/Forward en el wizard | Funciona correctamente |
| 4 | Builder token expira mid-wizard | Error manejado, redirect a Step 1 |
| 5 | Desktop (1920px) | Layout correcto en todos los pasos |
| 6 | Tablet (768px) | Layout responsive en todos los pasos |
| 7 | Mobile (375px) | Layout mobile en todos los pasos |

---

## Definition of Done

- [ ] Todos los checkmarks de regression arriba pasan
- [ ] 0 errores nuevos en lint + typecheck
- [ ] Build de producción exitoso para admin y api
- [ ] ONBOARDING_FIXPACK.md creado y revisado
- [ ] Este checklist completado y firmado por QA
