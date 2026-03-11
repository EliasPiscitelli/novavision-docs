# NovaVision – Implementación Inbox WhatsApp (Admin)

**Fecha:** 2025-11-22  
**Ámbitos:** Admin / Supabase / Edge Functions / Integraciones Meta

---

## 1) Resumen ejecutivo
- Se habilitó el flujo completo de Inbox de WhatsApp dentro del panel admin (`/dashboard/inbox`), incluyendo listado, lectura, respuesta manual y toggle del bot.  
- Se modeló la información en Supabase agregando campos específicos a `outreach_leads`, normalizando `outreach_logs` y exponiendo la vista `wa_conversations_view` con control de seguridad por invocador.  
- Se publicaron Edge Functions (`admin-wa-*`) que encapsulan la lógica de consulta, escritura y envío a la API de WhatsApp (Graph API) utilizando credenciales server-side.  
- Se ajustó la navegación para que todas las rutas administrativas queden protegidas por `ProtectedRoute`, evitando accesos directos sin rol.

---

## 2) Arquitectura técnica

### 2.1 Base de datos (Supabase / Postgres)
- **`apps/admin/supabase/sql/16_outreach_leads_inbox_columns.sql`**: añade campos clave (`interest_level`, `hot_lead`, `bot_enabled`, `assigned_to_user_id`, `tags`, `pain_points`, `updated_at`) y crea trigger `trg_outreach_leads_updated_at` para mantener la traza de edición.  
- **`apps/admin/supabase/sql/17_outreach_logs_inbox_columns.sql`**: estandariza `outreach_logs` con metadatos de canal/dirección/tipo, agrega columna `message_text`, payload `raw` y el índice `outreach_logs_lead_created_idx` para acelerar consultas por lead y fecha.  
- **`apps/admin/supabase/sql/15_wa_inbox_support.sql`**: recrea `wa_conversations_view` utilizando `JOIN LATERAL` sobre `outreach_logs` filtrando mensajes nulos o vacíos. Expone únicamente leads con actividad real y calcula `last_message_at` con fallback en `last_contact_at` y timestamps del lead.  
- Todas las piezas son idempotentes (uso de `if not exists`) para facilitar despliegues múltiples.

### 2.2 Edge Functions (Deno)
- **`_shared/wa-common.ts`**: factoriza CORS, obtención de variables de entorno y `requireAdmin` que valida roles (`admin`/`super_admin`) contra `auth.users`, `profiles` o `users`. Instancia `adminClient` con `SUPABASE_SERVICE_ROLE`.  
- **`admin-wa-conversations/index.ts`**: lectura paginada de `wa_conversations_view` con filtros `page`, `pageSize`, `hotOnly`, `search`. Devuelve `data` + metadata de paginación ordenada desc por `last_message_at` (`nullsLast`).  
- **`admin-wa-messages/index.ts`**: lista secuencial de `outreach_logs` por `lead_id`, exponiendo dirección, canal, tipo, remitente y timestamp.  
- **`admin-wa-update-conversation/index.ts`**: permite actualizar `bot_enabled` y `assigned_to_user_id`, devolviendo el lead normalizado.  
- **`admin-wa-send-reply/index.ts`**: envía textos a WhatsApp Graph API (`WHATSAPP_PHONE_NUMBER_ID` + `WHATSAPP_TOKEN`), registra el log en `outreach_logs` con payload completo y refresca `last_contact_at` del lead.

### 2.3 Frontend (React + styled-components)
- **Página `apps/admin/src/pages/AdminInbox/index.jsx`**: controla estado y efectos; soporta búsqueda debounced (400 ms), filtro de hot leads, paginación, selección de conversación y carga lazy de mensajes. Deshabilita composer cuando el bot sigue activo y realiza optimistic updates al enviar mensajes.  
- **Componentes compartidos en `apps/admin/src/components/Inbox/*`**:  
	- `ConversationList`: listado con badges `Hot`, `Humano`, estado y preview; maneja empty state y loading.  
	- `ConversationHeader`: muestra datos del lead, botón para pausar/activar bot y metadata (archivo no detallado aquí).  
	- `MessageList`: timeline oscuro con separación por remitente.  
	- `MessageComposer`: textarea con envío `Ctrl+Enter`, manejo de loading e inhabilitación.  
- **Estilos `apps/admin/src/pages/AdminInbox/style.jsx`**: layout tipo split view con dark theme (`surfacePrimary`, `surfaceSecondary`), filtros en barra superior y paginador en la izquierda.  
- **Servicio `apps/admin/src/services/waInboxApi.js`**: resuelve `FUNCTIONS_BASE` desde runtime/env, adjunta token Supabase actual y normaliza respuestas con `ok`, `data`, `errorMessage`.

### 2.4 Routing y seguridad
- `apps/admin/src/utils/ProtectedRoute.jsx` ahora puede actuar como wrapper o elemento suelto (retorna `<Outlet />` cuando no recibe `children`).  
- `apps/admin/src/App.jsx` coloca `/dashboard/*` y `/client/:clientId` dentro de un único `<Route element={<ProtectedRoute />}>`, evitando accesos sin rol. El dashboard deriva a `metrics` por default y expone la nueva pestaña `Inbox WhatsApp`.

### 2.5 Configuración y secretos
- Variables necesarias en Supabase Edge Functions: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE`, `WHATSAPP_PHONE_NUMBER_ID`, `WHATSAPP_TOKEN`.  
- En el frontend debe existir `VITE_ADMIN_SUPABASE_URL` (o `VITE_SUPABASE_URL`) para construir `FUNCTIONS_BASE`.  
- Los tokens de acceso de usuario son provistos por Supabase Auth; no se persisten en localStorage para estos llamados.

---

## 3) Flujo funcional
1. Administrador ingresa a `/dashboard/inbox` (requiere sesión y rol).  
2. Se consulta `admin-wa-conversations` con paginación 20 items y filtros activos; se selecciona automáticamente la primera conversación.  
3. Al seleccionar un lead se dispara `admin-wa-messages` para recuperar el historial completo ordenado ascendente.  
4. El usuario puede pausar/reactivar el bot (`admin-wa-update-conversation`) y enviar mensajes manuales (`admin-wa-send-reply`). Cada envío refresca la lista y agrega un log humano.  
5. Paginador lateral permite navegar por todas las conversaciones ordenadas por recencia real (`last_message_at`).

---

## 4) Despliegue / pasos operativos
1. **Migraciones DB** (orden sugerido):  
	 - `supabase db execute --file supabase/sql/16_outreach_leads_inbox_columns.sql`  
	 - `supabase db execute --file supabase/sql/17_outreach_logs_inbox_columns.sql`  
	 - `supabase db execute --file supabase/sql/15_wa_inbox_support.sql`  
2. **Edge Functions**: `supabase functions deploy admin-wa-conversations admin-wa-messages admin-wa-update-conversation admin-wa-send-reply`.  
3. **Variables de entorno**: cargar en Supabase Dashboard (Project Settings → API → Config) los tokens mencionados en §2.5.  
4. **Frontend**: `npm run dev`/`build` en `apps/admin`; confirmar que `.env` contenga `VITE_ADMIN_SUPABASE_URL` correcto.

---

## 5) Verificación y QA
- `curl` a `wa_conversations_view` debe retornar `count` igual al número de leads con `outreach_logs` con `message_text` válido.  
- `curl` GET `functions/v1/admin-wa-conversations?page=1&pageSize=20` con token admin:  
	- `pagination.total` consistente con vista.  
	- Primer ítem tiene `last_message_at` más reciente.  
- En UI:  
	- Buscar por nombre/teléfono filtra en 400 ms (sin recargar manual).  
	- Toggle “Solo hot leads” limita resultados y mantiene paginación.  
	- Si el bot está activo, el composer muestra placeholder deshabilitado.  
	- Enviar mensaje agrega log en la lista y aparece badge “Humano” en el lead.  
	- Pausar bot refleja `bot_enabled = false` en Supabase.  
- Acceso sin rol admin → redirección inmediata al home.

---

## 6) Riesgos y consideraciones
- El envío manual depende de la disponibilidad de la API de WhatsApp (Graph). Se propaga el status HTTP y payload en `outreach_logs.raw` para auditoría.  
- El filtrado en vista excluye mensajes sin texto; si se requieren plantillas/medios se deberá ampliar la lógica (`msg_type`).  
- `JOIN LATERAL` convierte la vista en inner join: leads sin mensajes ya no aparecen; validar si algún flujo necesita verlos igualmente.

---

## 7) Próximos pasos sugeridos
- Implementar Webhooks entrantes para refrescar la lista en tiempo real.  
- Agregar métricas de SLA (tiempo primera respuesta) usando los timestamps normalizados.  
- Construir tests e2e (Playwright) que validen login admin + envío de mensajes mockeado.  
- Permitir asignación de agentes desde el header de conversación aprovechando `assigned_to_user_id`.
