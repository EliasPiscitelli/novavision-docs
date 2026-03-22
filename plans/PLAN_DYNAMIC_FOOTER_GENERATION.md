# Plan: Dynamic Footer Generation

## Estado: Pendiente de implementacion
## Prioridad: Baja
## Complejidad: Grande (todas las capas)

---

## Contexto

Actualmente el footer del storefront usa links estaticos hardcodeados en `FooterParts.tsx` via `getDefaultNavLinks()` y `getLegalLinks()`. No existe forma de que el admin personalice los links, toggles de secciones ni copyright del footer desde el dashboard.

## Objetivo

Permitir al admin personalizar el footer de su tienda: agregar/editar/eliminar links, togglear secciones (social, contacto, legal), y personalizar el copyright.

---

## Fase 1: Backend (API)

### 1.1 Nueva tabla `footer_config` (Backend DB: nv-backend-db)

```sql
CREATE TABLE public.footer_config (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  client_id uuid NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  footer_links jsonb DEFAULT '[]'::jsonb,
  show_social boolean DEFAULT true,
  show_contact boolean DEFAULT true,
  show_legal boolean DEFAULT true,
  show_powered_by boolean DEFAULT true,
  custom_copyright text,
  cta_text text,
  cta_url text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(client_id)
);

-- RLS
ALTER TABLE footer_config ENABLE ROW LEVEL SECURITY;
CREATE POLICY "server_bypass" ON footer_config FOR ALL USING (auth.role() = 'service_role');
CREATE POLICY "select_tenant" ON footer_config FOR SELECT USING (client_id = current_client_id());
CREATE POLICY "write_admin" ON footer_config FOR ALL USING (client_id = current_client_id() AND is_admin());
```

Formato de `footer_links`:
```json
[
  { "label": "Envios", "url": "/envios", "position": 1 },
  { "label": "Devoluciones", "url": "/devoluciones", "position": 2 }
]
```

### 1.2 Nuevo modulo API `footer-config`

| Archivo | Rol |
|---------|-----|
| `footer-config.module.ts` | Modulo NestJS |
| `footer-config.service.ts` | CRUD para footer_config (upsert pattern) |
| `footer-config.controller.ts` | Endpoints |

Endpoints:
- `GET /settings/footer` — Obtener config del footer (publico, scopeado por client_id)
- `PUT /settings/footer` — Actualizar config (admin only)

### 1.3 Feature catalog

Agregar a `featureCatalog.ts`:
```typescript
{
  id: 'content.footer_config',
  title: 'Configuracion de Footer',
  category: 'content',
  surfaces: ['client_dashboard', 'api_only'],
  plans: { starter: true, growth: true, enterprise: true },
  status: 'live',
  evidence: [
    { type: 'endpoint', method: 'GET', path: '/settings/footer' },
    { type: 'endpoint', method: 'PUT', path: '/settings/footer' },
  ],
}
```

---

## Fase 2: Admin Dashboard (Web)

### 2.1 Nuevo componente `FooterConfigSection`

Path: `web/src/components/admin/FooterConfigSection/`

UI:
- Lista de links con drag-to-reorder (o input de orden)
- Boton agregar link (label + url)
- Editar/eliminar links existentes
- Toggles: Mostrar redes sociales, contacto, legal, powered by
- Campo de copyright personalizado
- Preview en vivo (opcional - stretch goal)

### 2.2 Registrar en AdminDashboard

- `SECTION_CATEGORIES`: agregar en categoria "Marca y Contenido"
- `LAZY_SECTION_COMPONENTS`: lazy import del componente
- `SECTION_FEATURES`: mapear a `content.footer_config`

---

## Fase 3: Storefront (Web)

### 3.1 Actualizar SectionRenderer

En `SectionRenderer.tsx` (L294-306), agregar fetch de `/settings/footer` y pasar los datos al componente Footer.

### 3.2 Actualizar FooterParts

En `FooterParts.tsx`, consumir los datos dinamicos en vez de `getDefaultNavLinks()`:
- Si `footer_config` existe → usar links dinamicos
- Si no existe → fallback a links default (retrocompatible)
- Respetar toggles: `show_social`, `show_contact`, `show_legal`, `show_powered_by`
- Si `custom_copyright` existe → usarlo en vez del default

---

## Dependencias

1. Migration de BD primero
2. API module segundo
3. Frontend admin tercero
4. Storefront ultimo (requiere API funcionando)

## Estimacion

- Backend: ~2-3 horas
- Admin Dashboard: ~2-3 horas
- Storefront: ~1-2 horas
- Testing: ~1 hora
- Total: ~7-9 horas

## Archivos afectados

| Archivo | Cambio |
|---------|--------|
| `api/src/footer-config/` (nuevo) | Modulo completo |
| `api/src/plans/featureCatalog.ts` | Agregar `content.footer_config` |
| `web/src/components/admin/FooterConfigSection/` (nuevo) | Componente admin |
| `web/src/pages/AdminDashboard/index.jsx` | Registrar seccion |
| `web/src/components/storefront/Footer/FooterParts.tsx` | Consumir datos dinamicos |
| `web/src/components/storefront/SectionRenderer.tsx` | Fetch footer config |
