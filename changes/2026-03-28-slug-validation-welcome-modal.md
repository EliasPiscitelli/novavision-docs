# Validación de slug + Modal de bienvenida del onboarding

**Fecha:** 2026-03-28
**Apps afectadas:** Admin
**Tipo:** feat + fix

## Resumen

Validación robusta del slug en Step1 del onboarding y modal de bienvenida que orienta al usuario sobre qué configurar ahora vs después de publicar.

## Cambios

### Validación de slug

**Archivos:**
- `apps/admin/src/pages/BuilderWizard/utils/slugValidation.ts` — **NUEVO** (funciones puras `validateSlug` y `sanitizeSlug`)
- `apps/admin/src/pages/BuilderWizard/steps/Step1Slug.tsx` — refactorizado para usar utility extraído

**Reglas implementadas:**
- Min 3 / max 40 caracteres
- Solo `a-z`, `0-9`, `-` (sin acentos, espacios, caracteres especiales)
- No puede empezar ni terminar con guión
- No guiones consecutivos (`--`)
- No puede ser solo números
- 18 nombres reservados bloqueados (admin, api, www, novavision, etc.)
- Auto-sanitize de acentos en el input (café → cafe, ñ → n via NFD normalization)

**Tests:** 42 unit tests en `slugValidation.test.ts`

### Modal de bienvenida

**Archivos:**
- `apps/admin/src/pages/BuilderWizard/components/WelcomeModal.tsx` — **NUEVO**
- `apps/admin/src/pages/BuilderWizard/components/WelcomeModal.css` — **NUEVO**
- `apps/admin/src/pages/BuilderWizard/index.tsx` — integración modal + botón "?"
- `apps/admin/src/pages/BuilderWizard/BuilderWizard.css` — estilos del FAB "?"

**Contenido del modal:**
1. **Sección "Mínimo"**: dominio/diseño, credenciales MP, datos fiscales, mínimo de productos
2. **Callout ilustrativo**: aclara que templates muestran contenido de demo, imágenes se suben o generan con IA después
3. **Sección "Después"**: carga con IA, carga masiva, imágenes con IA, personalización avanzada
4. **Sección "Regalos"**: créditos IA incluidos, SSL/hosting, dominio personalizado (con agente), configuración y carga asistida (con agente), soporte prioritario

**UX:**
- Aparece solo la primera vez (localStorage flag)
- Botón flotante "?" en esquina inferior derecha para reconsultar
- Animaciones: slide-up, staggered list items, pulsing CTA, shimmer en badge de regalos

**Tests:** 13 unit tests en `WelcomeModal.test.tsx`

## Validación

- Admin: lint ✓, typecheck ✓, build ✓, tests ✓ (148/148 pass)
