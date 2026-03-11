# NovaVision – Playbook comercial (Admin + RAG)

**Fecha:** 2025-11-20  
**Rama:** multiclient  
**Ámbitos:** DB / Backend / Admin / SDK

## 1) Resumen
- Tabla `nv_playbook` con RLS para centralizar snippets del closer.
- SDK y tipos compartidos para consumir el playbook desde API, admin o flujos externos.
- Vista de administración en `apps/admin` para crear, editar y pausar contenido.

## 2) Cambios aplicados
### DB
- Migración `20251120_create_nv_playbook.sql` con índices, trigger de auditoría y políticas RLS.

### Backend
- Módulo `PlaybookModule` con endpoint `GET /internal/playbook`.
- Test unitario de `PlaybookService` cubriendo filtros principales.

### Admin
- Nueva sección “Playbook” para CRUD con filtros segment/stage/type y control de estado.

### SDK/Types
- Definiciones comunes (`packages/types`) y repositorio Supabase (`packages/sdk`).

## 3) Migraciones
- `apps/api/migrations/20251120_create_nv_playbook.sql`

## 4) Post-deploy
- Correr migración: `npm run -w apps/api migrate`.
- Sembrar al menos 10 entradas iniciales (value prop, objeciones y cierres).
- Actualizar los flujos de n8n para consumir `nv_playbook` con filtros por segmento/etapa.

## 5) Verificación
- [ ] Se puede crear/editar/pausar entradas desde el dashboard.
- [ ] El endpoint `/internal/playbook` respeta filtros y requiere rol admin.
- [ ] El flow del closer recibe contenido priorizado según `priority`.
