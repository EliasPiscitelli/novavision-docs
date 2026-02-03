# Reglas de Estructura de Repositorios

> **Estado:** INMUTABLE  
> **Última revisión:** 2026-02-03

## Principio Fundamental

**Los 3 repositorios son INDEPENDIENTES.** No comparten código, no son monorepo, no tienen dependencias entre sí.

## Repositorios

### 1. templatetwobe (API)
- **Tecnología:** NestJS + TypeScript
- **Deploy:** Railway (auto-deploy en push a main)
- **Base de datos:** Supabase (Admin DB + Backend DB multicliente)
- **Ramas:**
  - `main` → Producción
  - `feature/*` → Desarrollo

### 2. novavision (Admin Dashboard)
- **Tecnología:** Vite + React + JavaScript/JSX
- **Deploy:** Netlify (auto-deploy en push a main)
- **Conecta a:** API via `VITE_API_URL`, Supabase Admin via `VITE_SUPABASE_URL`
- **Ramas:**
  - `main` → Producción
  - `feature/*` → Desarrollo

### 3. templatetwo (Web Storefront)
- **Tecnología:** Vite + React + JavaScript/JSX
- **Deploy:** Netlify (auto-deploy en push a main)
- **Conecta a:** API via `VITE_API_URL`, Supabase Multicliente via `VITE_SUPABASE_URL`
- **Ramas:**
  - `main` → Producción
  - `feature/*` → Desarrollo

## Reglas de Código

### NO HACER:
- ❌ Crear packages compartidos entre repos
- ❌ Referencias cruzadas (`../../otro-repo`)
- ❌ Monorepo con workspaces
- ❌ CI/CD centralizado
- ❌ Modificar estructura de carpetas raíz sin autorización

### SÍ HACER:
- ✅ Cada repo tiene su propio `package.json`
- ✅ Cada repo tiene su propio CI/CD (Netlify/Railway automático)
- ✅ Si se necesita código compartido, se **copia** (no se linkea)
- ✅ Documentar cambios en `novavision-docs`

## Carpeta Local de Contexto

```
NovaVisionRepo/          ← SOLO LOCAL, no es repo
├── apps/
│   ├── api/             ← Clone de templatetwobe
│   ├── admin/           ← Clone de novavision
│   └── web/             ← Clone de templatetwo
```

Esta carpeta existe **únicamente** para que el agente IA tenga contexto de los 3 repos simultáneamente. No debe trackearse en git.

---

*Regla establecida por: Principal Engineer*
