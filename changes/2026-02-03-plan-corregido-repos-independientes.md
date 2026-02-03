# Cambio: Plan Corregido para Repos Independientes

- **Fecha:** 2026-02-03
- **Autor:** Copilot Agent
- **Rama:** feature/automatic-multiclient-onboarding (API/Admin), feature/multitenant-storefront (Web)

---

## Contexto

El plan anterior de implementación asumía incorrectamente que NovaVision era un **monorepo con packages compartidos**. En realidad son **3 repositorios Git independientes**:

1. `templatetwobe` (API)
2. `novavision` (Admin)
3. `templatetwo` (Web)
4. `novavision-docs` (Documentación)

Se revirtieron los cambios de "monorepo" y se creó un plan corregido.

---

## Archivos Creados

### Documentación
- [novavision-docs/analysis/PLAN_CORREGIDO_REPOS_INDEPENDIENTES.md](../analysis/PLAN_CORREGIDO_REPOS_INDEPENDIENTES.md) - Plan corregido completo
- [novavision-docs/architecture/CSS_VARIABLES_CONTRACT.md](../architecture/CSS_VARIABLES_CONTRACT.md) - Contrato de CSS variables `--nv-*`

### Web (templatetwo)
- [apps/web/src/templates/manifest.js](../../apps/web/src/templates/manifest.js) - Registro de templates con metadata

### CI/CD (todos los repos)
- `apps/api/.github/workflows/ci.yml`
- `apps/admin/.github/workflows/ci.yml`
- `apps/web/.github/workflows/ci.yml`

---

## Resumen del Plan Corregido

### Lo que NO hacer
- ❌ Crear `packages/` compartidos entre repos
- ❌ Importar código de un repo en otro
- ❌ CI centralizado que dependa de múltiples repos
- ❌ Git submodules o symlinks

### Lo que SÍ hacer
- ✅ Documentar contratos (APIs, tokens, schemas) en `novavision-docs`
- ✅ Copiar código común cuando sea necesario
- ✅ CI independiente por repo
- ✅ PRs que referencian docs compartidos

---

## Próximos Pasos (Sprint 1)

| # | Repo | Tarea | Estado |
|---|------|-------|--------|
| 1 | Todos | Crear rama `develop` | Pendiente |
| 2 | Todos | CI básico en `.github/workflows/` | ✅ Completado |
| 3 | Admin | Unificar naming a `--nv-*` | Pendiente |
| 4 | Web | Manifest de templates | ✅ Completado |
| 5 | Docs | Contrato de CSS variables | ✅ Completado |

---

## Cómo Validar

```bash
# Verificar CI en cada repo
cat apps/api/.github/workflows/ci.yml
cat apps/admin/.github/workflows/ci.yml
cat apps/web/.github/workflows/ci.yml

# Verificar manifest de templates
cat apps/web/src/templates/manifest.js

# Verificar docs
cat novavision-docs/architecture/CSS_VARIABLES_CONTRACT.md
```

---

## Notas de Seguridad

- Los workflows de CI no exponen secrets
- El manifest de templates no contiene datos sensibles
- El contrato de CSS variables es solo documentación
