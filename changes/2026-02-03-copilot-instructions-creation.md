# Cambio: Creación de copilot-instructions.md para los 3 repos

- **Autor:** agente-copilot
- **Fecha:** 2026-02-03
- **Rama:** feature/automatic-multiclient-onboarding (api, admin), feature/multitenant-storefront (web)
- **Repos afectados:** templatetwobe, novavision, templatetwo

## Archivos creados/modificados

### templatetwobe (API)
- `apps/api/.github/copilot-instructions.md` - **CREADO**

### novavision (Admin)
- `apps/admin/.github/copilot-instructions.md` - **CREADO**

### templatetwo (Web)
- `apps/web/.github/copilot-instructions.md` - **CREADO**

## Resumen de cambios

Se crearon archivos `.github/copilot-instructions.md` para guiar a agentes AI en cada repositorio. Cada archivo incluye:

1. **Arquitectura específica del repo**
   - Stack tecnológico
   - Flujo de datos
   - Estructura de módulos/carpetas

2. **Comandos de desarrollo**
   - Build, lint, typecheck, test
   - Comandos específicos (diagnose:smtp, supabase functions, etc.)

3. **Patrones críticos**
   - Multi-tenant con filtros `client_id`
   - Storage paths con prefijo clientId
   - Webhooks de Mercado Pago

4. **Variables de entorno**
   - Requeridas por cada repo
   - Reglas de seguridad (SERVICE_ROLE_KEY solo server-side)

5. **Reglas obligatorias (inmutables)**
   - Documentar TODOS los cambios en `novavision-docs/changes/`
   - Validar impacto ANTES de aplicar (lint, typecheck)
   - Repos INDEPENDIENTES (no monorepo, no packages compartidos)

## Por qué

- Mejorar productividad de agentes AI al trabajar con el codebase
- Establecer reglas claras sobre documentación de cambios
- Evitar errores comunes (exponer keys, romper multi-tenant, asumir monorepo)
- Centralizar convenciones específicas del proyecto

## Cómo probar

```bash
# API
cd apps/api
npm run lint && npm run typecheck

# Admin
cd apps/admin
npm run lint && npm run typecheck

# Web
cd apps/web
npm run lint && npm run typecheck
```

## Referencias

- Documentación base: `novavision-docs/rules/REPO_STRUCTURE.md`
- Arquitectura: `novavision-docs/architecture/OVERVIEW.md`
- Auditoría: `novavision-docs/audit/NOVAVISION_SYSTEM_AUDIT.md`

## Notas de seguridad

Sin impacto en seguridad. Los archivos solo contienen instrucciones y patrones, no credenciales.
