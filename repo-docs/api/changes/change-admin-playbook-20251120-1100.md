# Cambio: Alta tabla nv_playbook para Playbook comercial

- Autor: github-copilot
- Fecha: 2025-11-20
- Rama: multiclient
- Archivos: apps/admin/supabase/sql/13_nv_playbook_tables.sql, apps/admin/supabase/sql/14_nv_playbook_rls.sql, docs/changes/change-admin-playbook-20251120-1100.md

## Resumen
Se crea la tabla `public.nv_playbook` con índices, disparador `update_updated_at_column` y semillas iniciales segmentadas para ventas. Se habilitan políticas RLS para el usuario admin autenticado y el `service_role`.

## Motivo
Permite gestionar contenido del playbook comercial directamente desde el dashboard administrativo sin depender del backend multicliente. Las semillas proveen material base para integraciones de prompts/RAG internas.

## Cómo probar (local Admin)
1. Aplicar migración: `supabase db push --env-file .env.local`.
2. Ingresar al Admin Dashboard → Playbook y verificar que las entradas semilla aparecen.
3. Crear/editar/pausar una entrada y confirmar que los cambios se reflejan en Supabase.

## Riesgos / Notas
- Validar que el UUID del usuario administrador (`a1b4ca03-3873-440e-8d81-802c677c5439`) continúe vigente.
- Semillas deberán revisarse periódicamente para mantener contenido vigente.
