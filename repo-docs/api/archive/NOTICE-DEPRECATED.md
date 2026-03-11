> [!CAUTION] > **DEPRECATED**: Este documento describe un modelo de "1 deploy por cliente" (multi-site)  
> que fue **descartado** en favor del **modelo multi-tenant de deploy único**.
>
> **Reemplazo**: Ver [plan-tecnico-onboarding-v1.3.6-SHIP.md](../planes-accion/plan-tecnico-onboarding-v1.3.6-SHIP.md)
>
> **Fecha de deprecación**: 2025-12-17  
> **Motivo**: Arquitectura en v1.3.6 usa:
>
> - ✅ 1 solo deploy en Netlify para todas las tiendas
> - ✅ Wildcard DNS `*.novavision.app`
> - ✅ Resolución de tenant por `slug` desde hostname
> - ✅ Tabla `clients` (NO `tenants`)
> - ❌ NO hay "rama por cliente"
> - ❌ NO hay "site de Netlify por cliente"

---

# Arquitectura de Onboarding Automatizado NovaVision (DEPRECATED)

**Autor:** Elias Piscitelli  
**Fecha:** 2025-11-27  
**Versión:** 1.0  
**Estado:** ❌ **OBSOLETO** - No implementar

---

_[Contenido original del documento archivado aquí... se mantiene solo para referencia histórica]_
