# Cambio: Dashboard Outreach Pipeline — Super Admin

- **Autor:** agente-copilot
- **Fecha:** 2025-07-17
- **Rama:** feature/automatic-multiclient-onboarding (admin)
- **Archivos creados/modificados:**
  - `apps/admin/src/hooks/useOutreachMetrics.js` (NUEVO — 170 líneas)
  - `apps/admin/src/pages/AdminDashboard/OutreachView.jsx` (NUEVO — ~480 líneas)
  - `apps/admin/src/pages/AdminDashboard/index.jsx` (MODIFICADO — +11 líneas: import FaBullhorn + NAV_ITEM)
  - `apps/admin/src/App.jsx` (MODIFICADO — +2 líneas: import + route)

---

## Resumen

Se agregó una vista completa de **Outreach Pipeline** al dashboard de super admin, conectada a las tablas de outreach del Admin DB de Supabase.

### Hook: `useOutreachMetrics.js`
- Consulta directa a `adminSupabase` (service-role)
- Métricas producidas:
  - **Funnel snapshot**: leads agrupados por status (NEW → CONTACTED → IN_CONVERSATION → QUALIFIED → ONBOARDING → WON) + otros (LOST, COLD, DISCARDED)
  - **Activity series**: logs agrupados por día y dirección (inbound/outbound/bot) para los últimos N días
  - **Hot Leads**: top 15 por `ai_engagement_score`, excluyendo LOST/COLD/DISCARDED
  - **Coupons**: ofertas realizadas, canjeadas, tasa de conversión, cupones activos
  - **Config**: todas las filas de `outreach_config`
  - **KPIs calculados**: totalLeads, contacted, contactRate, won, conversionRate, lost, cold, discarded, totalMessages
- Parámetro configurable: `{ days }` (default 30)
- Retorna: `{ data, loading, error, reload }`

### Vista: `OutreachView.jsx`
Secciones visuales:
1. **Header** con selector de rango temporal (7d / 14d / 30d / 90d) + botón reload
2. **KPI Cards** (6): Total Leads, Tasa de Contacto, Ganados, Conversión, Mensajes, Lost+Cold
3. **Funnel BarChart** (Recharts): barras coloreadas por status
4. **Pipeline PieChart** (donut): distribución porcentual de todos los estados
5. **Activity LineChart**: 3 líneas (inbound/bot/outbound) por día
6. **Cupones**: badge habilitado/deshabilitado, KPIs (ofrecidos/canjeados/conversión), lista de cupones activos
7. **Config panel**: key-value de outreach_config
8. **Hot Leads table**: nombre, empresa, teléfono, status (badge), stage, score (color-coded), hot flag, último contacto

Estilo coherente con el theme dark del admin existente (colores de UsageTrendsChart.jsx).

### Wiring
- **NAV_ITEM**: `{ to: 'outreach', icon: <FaBullhorn />, label: 'Outreach Pipeline', category: 'clients-sales', superOnly: true }`
- **Ruta**: `<Route path="outreach" element={<OutreachView />} />`

---

## Por qué

El equipo necesita visibilidad en tiempo real del pipeline de outreach automatizado (n8n + AI Closer + WhatsApp) desde el mismo panel donde gestiona clientes y ventas. Antes no existía ninguna vista de estos datos.

## Cómo probar

1. Levantar admin con `npm run dev` (terminal admin)
2. Loguearse como super admin
3. Ir a Dashboard → sección "Clientes y Ventas" → Outreach Pipeline
4. Verificar que carguen los datos de `outreach_leads`, `outreach_logs`, `outreach_config`, `outreach_coupons` y `outreach_coupon_offers`
5. Cambiar el rango temporal (7d/14d/30d/90d) y verificar que los gráficos se actualicen

## Tablas consultadas (Admin DB)

| Tabla | Operación |
|-------|-----------|
| `outreach_leads` | SELECT con group by status; SELECT top 15 por score |
| `outreach_logs` | SELECT con group by day/direction |
| `outreach_config` | SELECT * |
| `outreach_coupons` | SELECT where active=true |
| `outreach_coupon_offers` | SELECT con group by status |

## Notas de seguridad

- Solo visible para `superOnly: true` (super admins)
- Usa `adminSupabase` (service-role) — no expone datos a usuarios regulares
- No modifica datos, solo lectura
