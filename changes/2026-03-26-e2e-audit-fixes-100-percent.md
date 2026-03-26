# Auditoría E2E + Correcciones para 100% productivo

**Fecha**: 2026-03-26
**Tipo**: Fix + Regla + Auditoría
**Apps**: API (rules), Admin (4 fixes), Monorepo (CLAUDE.md)

## Contexto

Auditoría completa cruzando 51 planes, 87 controllers y 217 changelogs para detectar features implementadas solo en un lado del stack. Cobertura E2E resultante: >95%. Brechas corregidas.

## Cambios realizados

### 1. Support Admin — Migración a adminApi.js (Admin)

**Problema**: SupportConsoleView y componentes de soporte llamaban directamente a `adminApi.get('/admin/support/...')` en vez de usar helpers semánticos.

**Fix**:
- `adminApi.js`: +18 helpers de support (`getSupportMetrics`, `getSupportTickets`, `updateSupportTicket`, `addSupportMessage`, `assignSupportAgent`, `generateSupportAnalysis`, `approveSupportPlan`, `advanceSupportStage`, `getSupportTicketTasks`, `toggleSupportTask`, etc.)
- `SupportConsoleView.jsx`: 11 llamadas directas migradas a helpers
- `StagePipeline.jsx`: 1 llamada migrada
- `AiAnalysisSection.jsx`: 2 llamadas migradas
- `TicketTasks.jsx`: 2 llamadas migradas

### 2. AddonPurchasesView tests — Fix TypeScript (Admin)

**Problema**: 11 instancias de `mockResolvedValue({ data: ... })` sin el shape completo de `AxiosResponse`.

**Fix**: Helper `axiosOk<T>()` que wrappea data con `status: 200, statusText: 'OK', headers: {}, config: {} as any`.

### 3. tsconfig.json — paths alias (Admin)

**Problema**: Vite tenía alias para `utils/`, `components/`, etc. pero `tsconfig.json` no, causando error TS2307 en `UpsellModal.tsx` y `PricingSection/index.jsx`.

**Fix**: Agregados `baseUrl: "src"` y `paths` para todos los alias de Vite: `utils/*`, `components/*`, `hooks/*`, `services/*`, `service/*`, `context/*`, `assets/*`.

### 4. Regla E2E obligatoria (Monorepo)

**Archivos**:
- `.claude/rules/e2e-mandatory.md` — Regla con `alwaysApply: true` que inyecta checklist E2E en toda sesión
- `CLAUDE.md` raíz — Reglas 8 (E2E obligatorio) y 9 (Plan = E2E)
- Spawn prompts de 5 teammates actualizados con `REGLA E2E` específica por rol

## Validación

| Check | Resultado |
|-------|-----------|
| TypeScript Admin | 0 errores (antes: 12) |
| Lint Admin | 0 errores |
| Build Admin | OK (4.74s) |
| TypeScript Web | 0 errores |
| Build Web | OK |

## Items que requieren acción externa (no código)

### Quota Enforcement
- Env var: `ENABLE_QUOTA_ENFORCEMENT=true` en Railway
- Prerequisitos verificados: tablas quota_state, usage_rollups_monthly, plans con límites
- Acción: setear variable + redeploy API

### AI Pro M10/M12
- M10: Activar workflow Weekly Report en n8n + agregar nodo validación post-IA
- M12: Importar wf-inbound-v2.json en n8n + configurar credenciales Meta WA
- Ninguno requiere cambios en código NestJS
