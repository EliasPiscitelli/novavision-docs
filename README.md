# NovaVision Documentation

Repositorio central de documentación, reglas, arquitectura y registro de cambios del sistema NovaVision.

## Estructura

```
novavision-docs/
├── architecture/     ← Documentación de arquitectura del sistema
├── rules/            ← Reglas fijas y convenciones
├── runbooks/         ← Guías operativas y playbooks de uso
├── changes/          ← Log de cambios por sesión (IA + manual)
├── analysis/         ← Auditorías, análisis de sistema
└── cleanup/          ← Planes de cleanup y mejoras
```

## Repositorios del Sistema

| Repo | Descripción | Deploy |
|------|-------------|--------|
| [templatetwobe](https://github.com/EliasPiscitelli/templatetwobe) | API NestJS | Railway |
| [novavision](https://github.com/EliasPiscitelli/novavision) | Admin Dashboard (React) | Netlify |
| [templatetwo](https://github.com/EliasPiscitelli/templatetwo) | Web Storefront (React) | Netlify |

## Convenciones

### Registro de Cambios

Cada sesión de trabajo (IA o manual) debe documentarse en `changes/` con el formato:

```
changes/YYYY-MM-DD_descripcion-breve.md
```

Contenido mínimo:
- Fecha y autor (humano o agente IA)
- Repos afectados
- Cambios realizados
- Archivos modificados
- Razón del cambio

### Reglas

Las reglas en `rules/` son inmutables y deben respetarse en todo cambio:
- Estructura de repos (independientes, no monorepo)
- Convenciones de código por repo
- Flujos de deploy

---

## 🔥 Tópicos Destacados (Active)

### [🤖 Claude Code por Fases](./runbooks/claude-code-por-fases.md)
**Status**: ✅ disponible

Guía operativa para usar Claude Code por fases en los tres repos productivos de NovaVision:

- apertura del repo correcto;
- relevamiento con `context-mapper`;
- implementación con el agente del repo;
- revisión con `contract-guardian`;
- validación con `quality-gate`;
- documentación y cierre.

### [🎨 Theme System Refactor - 2026-02-04](./THEME_QUICK_REFERENCE.md)
**Status**: ✅ **COMPLETE** - Unified theme resolver para storefront + admin

**Quick Start**:
- **One Page**: [THEME_QUICK_REFERENCE.md](./THEME_QUICK_REFERENCE.md) (5 min read)
- **Full Summary**: [THEME_FINAL_SUMMARY.md](./THEME_FINAL_SUMMARY.md) (10 min read)
- **Validation**: [THEME_VALIDATION_MANUAL.md](./THEME_VALIDATION_MANUAL.md) (20 min checklist)
- **Admin Integration**: [THEME_ADMIN_INTEGRATION.md](./THEME_ADMIN_INTEGRATION.md) (Phase 6)
- **All Docs**: [THEME_DOCUMENTATION_INDEX.md](./THEME_DOCUMENTATION_INDEX.md)

**What Changed**:
- ✅ Created `resolveEffectiveTheme.ts` - unified resolver
- ✅ Created `useEffectiveTheme.ts` - React hook wrapper
- ✅ Created `ThemeDebugPanel.jsx` - visual debug tool (🎨 button)
- ✅ Integrated in `App.jsx` - uses API config now
- ✅ Zero breaking changes, fully backward compatible

**Files**:
- `/apps/web/src/theme/resolveEffectiveTheme.ts` (400+ lines)
- `/apps/web/src/hooks/useEffectiveTheme.ts` (40 lines)
- `/apps/web/src/components/ThemeDebugPanel/ThemeDebugPanel.jsx` (400+ lines)
- `/apps/web/src/App.jsx` (updated)

---

*Última actualización: 2026-02-04*

