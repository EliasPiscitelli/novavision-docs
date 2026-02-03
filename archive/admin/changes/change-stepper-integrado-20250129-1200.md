# Cambio: Implementación Stepper Integrado - Landing /enterprise

- **Autor**: agente-copilot
- **Fecha**: 2025-01-29
- **Rama**: feature/automatic-multiclient-onboarding
- **Archivos**: 
  - `src/pages/LeadIntakePage/index.jsx`
  - `src/pages/LeadIntakePage/style.jsx`

---

## Resumen

Se implementó el rediseño UX/UI "Opción A: Stepper Integrado Inline" para la landing page `/enterprise`. El video de presentación que antes "flotaba" desconectado en la parte superior ahora está integrado dentro del Paso 2 como contenido del card, creando un flujo lineal claro.

---

## Cambios Realizados

### 1. Nuevo Layout - Stepper Vertical Unificado

**Antes:**
- Hero con video + formulario mezclados
- MainSection con 2 columnas (Step 2 y Step 3)
- Jerarquía visual confusa

**Ahora:**
- Hero compacto (solo título, subtítulo, progress indicator horizontal, CTAs)
- StepperSection con contenedor de max-width 760px
- 3 IntegratedStepCard apilados verticalmente
- Video integrado DENTRO del Paso 2

### 2. Nuevos Styled Components (style.jsx)

Se agregaron ~350 líneas de componentes para el stepper integrado:

- `StepperSection`, `StepperContainer` - Contenedor principal
- `ProgressIndicator`, `ProgressStep`, `ProgressDot`, `ProgressLine` - Indicador horizontal
- `IntegratedStepCard` - Card unificado con estados locked/active/done
- `StepHeader`, `StepHeaderLeft`, `StepNumber`, `StepTitleInline`, `StepStatusBadge` - Header del card
- `StepDescriptionText`, `StepBody` - Contenido
- `VideoContainer`, `VideoPlayerWrapper`, `VideoMeta`, `VideoDuration` - Video embebido
- `VideoProgressInline`, `VideoProgressTrack`, `VideoProgressFillInline`, `VideoProgressText` - Progreso video
- `UnlockHint` - Mensaje de desbloqueo
- `StepCta` - CTA principal del paso
- `LockedMessage` - Overlay para pasos bloqueados

### 3. Estados Visuales Implementados

Cada paso ahora tiene 3 estados visuales claros:

| Estado | Borde | Opacidad | Badge | Interacción |
|--------|-------|----------|-------|-------------|
| `locked` | gris | 0.6 | 🔒 Bloqueado | deshabilitada |
| `active` | cyan | 1.0 | En progreso | habilitada |
| `done` | verde | 1.0 | ✓ Completado | habilitada |

### 4. Flujo de Desbloqueo

```
Paso 1 (Formulario) → siempre disponible
         ↓ submit exitoso
Paso 2 (Video)      → se desbloquea
         ↓ 80% visto (2 min)
Paso 3 (Calendly)   → se desbloquea
```

### 5. Microcopy Actualizado

- CTA Paso 1: "Enviar y continuar →"
- Paso 2 header: "Mirá la presentación"
- Paso 2 descripción: "En 2 minutos entendés qué incluye tu demo..."
- Unlock hint: "Mirá ~X min más para desbloquear la agenda"
- Unlock completado: "¡Listo! Ya podés agendar tu demo personalizada"

---

## Cómo Probar

### Prerequisitos
```bash
cd apps/admin
npm run dev
```

### Pasos de Prueba

1. **Acceder a /enterprise**
   - Verificar que NO redirija a /onboarding/status
   - Hero compacto visible con progress indicator [1]—[2]—[3]
   
2. **Verificar Paso 1 (Formulario)**
   - Card visible con estado "active" (borde cyan)
   - Formulario expandible funcional
   - Submit habilitado
   
3. **Verificar Paso 2 (Bloqueado)**
   - Card con opacidad reducida y overlay
   - Badge muestra "🔒 Bloqueado"
   - Mensaje: "Completá el formulario del Paso 1..."
   
4. **Completar formulario**
   - Llenar datos y enviar
   - Paso 1 cambia a "done" (borde verde, ✓)
   - Paso 2 se desbloquea (borde cyan, "En progreso")
   - Video visible dentro del card
   
5. **Ver video**
   - Controles funcionan (play/pause, rewind, forward, mute, fullscreen)
   - Barra de progreso muestra %
   - UnlockHint actualiza tiempo restante
   
6. **Desbloquear Paso 3**
   - Al llegar a 80% (2 min), UnlockHint cambia a "¡Listo!"
   - Paso 3 se desbloquea
   - Calendly carga

### Datos de Prueba
- Email: test@example.com
- WhatsApp: +54 9 11 5555-5555
- Tipo de negocio: cualquier opción

---

## Notas Técnicas

### Variables Marcadas como No Usadas

Se prefijaron con `_` las siguientes variables del diseño anterior que ya no se usan pero se mantienen para posible rollback:

- `_isPortraitVideo`, `_setIsPortraitVideo`
- `_goToStep1Label`, `_goToVideoActionLabel`
- `_videoHeroBadge`, `_videoStepBadge`, `_calendlyStepBadge`
- `_step1Badge`, `_step1SubmitIdle`, `_videoStepTitle`
- `_videoPrimaryActionLabel`, `_unlockStatusMessage`
- `_heroVideoNoteMessage`, `_videoButtonHelperText`
- `_unlockButtonDisabled`, `_videoStepDescription`, `_videoStatusCopy`

### Componentes Styled Eliminados del Import

Se limpiaron imports no usados del nuevo diseño:
- `StepsRow`, `StepChip`, `StepIcon`, `StepLabel`
- `HeroVideoCard`, `HeroVideoBadge`, `HeroVideoWrapper`, `HeroVideoNote`, `HeroVideoActions`
- `VideoUnlockButton`, `VideoHelperText`
- `StepCard`, `StepBadge`, `StepTitle`, `StepDescription`, `StepContent`
- `MainSection`, `StepColumns`, `PrimaryColumn`
- `VideoStat`, `VideoProgress`, `VideoProgressLabel`, `VideoProgressBar`, `VideoProgressFill`
- `VideoActions`

---

## Riesgos / Rollback

### Riesgos Identificados
1. **Video no carga**: Si el video tiene problemas, el usuario queda bloqueado en Paso 2
   - Mitigación: El video tiene fallback poster y mensaje de error
   
2. **Progress no se guarda**: Si localStorage falla, el usuario pierde progreso
   - Mitigación: El progreso también se guarda en backend via `lead`

### Plan de Rollback
Si es necesario revertir:
```bash
git revert <commit-hash>
```
Los cambios están aislados en 2 archivos.

---

## Screenshots / Evidencias

(Agregar capturas después de deploy a staging)

- [ ] Vista desktop - Paso 1 activo
- [ ] Vista desktop - Paso 2 desbloqueado con video
- [ ] Vista desktop - Paso 3 desbloqueado con Calendly
- [ ] Vista mobile - Stack vertical
- [ ] Progress indicator estados

---

## Checklist

- [x] Lint pasa sin errores ni warnings
- [x] Typecheck pasa
- [x] No se exponen credentials
- [x] Variables no usadas prefijadas con `_`
- [x] Documento de cambios creado
