# Sesión de Cleanup - 2026-02-03

## Resumen

Sesión de cleanup de código donde se identificaron varios problemas y se corrigieron.

## Aprendizaje Clave

**⚠️ Los 3 repos son INDEPENDIENTES** - No crear packages compartidos ni tratar como monorepo.

## Cambios Revertidos

Los siguientes cambios fueron creados asumiendo estructura monorepo y fueron **revertidos**:

### templatetwobe (API)
- ❌ `packages/contracts/` - Schemas Zod compartidos (REVERTIDO)
- ❌ `packages/ai/` - Utilidades AI (REVERTIDO)
- ❌ `.github/workflows/` - CI centralizado (REVERTIDO)
- ❌ `docs/cleanup/` - Documentación (REVERTIDO)

### novavision (Admin)
- ❌ Dependencia `@novavision/contracts` (REVERTIDO)
- ❌ `src/utils/jsonImport/` que dependía de contracts (REVERTIDO)
- ❌ `src/pages/DevPortal/` (REVERTIDO)

### templatetwo (Web)
- ❌ `src/components/templates/manifest.json` (REVERTIDO)

## Cambios Útiles para Re-implementar

Los siguientes cambios son útiles pero deben implementarse **directamente en cada repo**:

### Admin Dashboard (novavision)
1. **Design System / Theme Tokens**
   - Unificación de colores desde `theme/colors.js`
   - Uso de `theme()` de Tailwind en lugar de hardcoded
   
2. **JSON Import Validation**
   - Validación de clientes importados
   - Puede usar Zod **localmente** (no como package externo)

### Web Storefront (templatetwo)
1. **Templates Manifest** (opcional)
   - Si se necesita configuración de templates

### API (templatetwobe)
1. **Onboarding validation schemas**
   - Mantener Zod validations pero **dentro del propio repo**

## Estructura Correcta

```
NovaVisionRepo/          ← CARPETA LOCAL (NO GIT)
├── apps/
│   ├── api/             ← templatetwobe (git independiente)
│   ├── admin/           ← novavision (git independiente)
│   └── web/             ← templatetwo (git independiente)

novavision-docs/         ← NUEVO REPO (4to repo)
├── rules/
├── changes/
├── analysis/
└── architecture/
```

## Próximos Pasos

1. [x] Revertir commits monorepo en los 3 repos
2. [x] Crear estructura novavision-docs
3. [ ] Usuario crea repo en GitHub
4. [ ] Push inicial de novavision-docs
5. [ ] Re-implementar features útiles SIN packages compartidos
