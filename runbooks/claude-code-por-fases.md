# Guía: uso de Claude Code por fases en NovaVision

- Fecha: 2026-03-14
- Autor: agente-copilot
- Repos: templatetwobe, novavision, templatetwo, novavision-docs

## Objetivo

Estandarizar cómo usar Claude Code en NovaVision para que el trabajo sea repetible, auditable y alineado con las reglas de los tres repos productivos:

- API: `apps/api`
- Admin: `apps/admin`
- Web: `apps/web`

La idea no es “pedirle todo junto” al agente, sino trabajar por fases con responsabilidades claras.

## Requisitos previos

Antes de usar esta guía, debe estar resuelto lo siguiente:

1. Claude Code instalado y autenticado.
2. Configuración project-level creada en cada repo:
   - `CLAUDE.md`
   - `.claude/settings.json`
   - `.claude/agents/`
   - `.claude/rules/`
3. El usuario debe iniciar Claude Code desde la raíz del repo correcto.
4. Si se va a usar Remote Control, el repo debe haber sido abierto al menos una vez con `claude` para aceptar el workspace trust.

## Documentación base consultada

Para descubrir páginas disponibles de Claude Code, usar primero el índice oficial:

- `https://code.claude.com/docs/llms.txt`

Páginas especialmente útiles para NovaVision:

- `overview`
- `authentication`
- `settings`
- `memory`
- `sub-agents`
- `remote-control`

## Agentes disponibles por repo

### API

- `context-mapper`
- `api-engineer`
- `contract-guardian`
- `quality-gate`

### Admin

- `context-mapper`
- `admin-engineer`
- `contract-guardian`
- `quality-gate`

### Web

- `context-mapper`
- `storefront-engineer`
- `contract-guardian`
- `quality-gate`

## Modelo operativo por fases

## Fase 0. Abrir el repo correcto

Primero definir en qué repo vive el cambio principal.

### Cuándo usar cada repo

- API: contratos, auth, pagos, multi-tenant, NestJS, DB, webhooks.
- Admin: dashboard, onboarding, Edge Functions, operaciones super-admin.
- Web: storefront, checkout, carrito, templates, preview, navegación y UX final.

### Comando de entrada

#### API

```bash
cd /Users/eliaspiscitelli/Documents/NovaVision/NovaVisionRepo/apps/api
claude
```

#### Admin

```bash
cd /Users/eliaspiscitelli/Documents/NovaVision/NovaVisionRepo/apps/admin
claude
```

#### Web

```bash
cd /Users/eliaspiscitelli/Documents/NovaVision/NovaVisionRepo/apps/web
claude
```

## Fase 0.5. Habilitar trabajo remoto opcional

Usar esta fase solo si querés continuar una sesión local desde otro dispositivo en `claude.ai/code` o desde la app móvil.

### Cuándo conviene

- querés seguir una sesión del repo desde el teléfono o desde otro navegador;
- necesitás dejar corriendo una sesión local y retomarla fuera de tu escritorio;
- querés usar el entorno local real, no Claude Code on the web.

### Requisitos

1. Claude Code autenticado con `claude.ai`.
2. Workspace trust ya aceptado en el repo.
3. Mantener abierto el proceso local de Claude Code.

### Opción A. Servidor dedicado de Remote Control

```bash
claude remote-control --name "NovaVision Web"
```

Flags verificadas en la versión local `2.1.76`:

- `--name <name>`
- `--permission-mode <mode>`
- `--spawn <mode>`
- `--capacity <N>`
- `--create-session-in-dir` / `--no-create-session-in-dir`
- `--verbose`

Modos de spawn soportados localmente:

- `same-dir`
- `worktree`
- `session`

### Opción B. Desde una sesión interactiva ya abierta

Dentro de Claude Code:

```text
/remote-control
```

o:

```text
/remote-control NovaVision API
```

### Recomendación de uso en NovaVision

- usar `same-dir` para lectura, debugging liviano o seguimiento;
- usar `worktree` si vas a abrir sesiones remotas concurrentes sobre cambios de código;
- evitar usar varias sesiones en `same-dir` editando los mismos archivos.

### Ejemplos por repo

#### API

```bash
cd /Users/eliaspiscitelli/Documents/NovaVision/NovaVisionRepo/apps/api
claude remote-control --name "NovaVision API" --spawn worktree
```

#### Admin

```bash
cd /Users/eliaspiscitelli/Documents/NovaVision/NovaVisionRepo/apps/admin
claude remote-control --name "NovaVision Admin" --spawn worktree
```

#### Web

```bash
cd /Users/eliaspiscitelli/Documents/NovaVision/NovaVisionRepo/apps/web
claude remote-control --name "NovaVision Web" --spawn worktree
```

### Advertencias

1. Remote Control no reemplaza las reglas del repo ni los permisos configurados.
2. Si cerrás la terminal o matás el proceso `claude`, la sesión remota termina.
3. Para trabajo concurrente real sobre código, preferir `worktree`.
4. No confundir Remote Control con Claude Code on the web: Remote Control usa tu máquina local.

## Fase 1. Relevamiento del contexto

En NovaVision no conviene implementar a ciegas. La primera fase siempre es de mapa técnico y de impacto.

### Agente a usar

- `context-mapper`

### Qué pedirle

Ejemplos:

```text
Usá context-mapper para relevar este cambio y decime archivos, contratos, riesgos y validaciones.
```

```text
Usá context-mapper para mapear el flujo afectado, dependencias cross-repo y tests relevantes.
```

### Resultado esperado

La salida de esta fase debería decirte:

1. dónde vive el cambio realmente;
2. qué archivos toca;
3. si impacta otros repos;
4. qué comandos habrá que correr;
5. qué riesgos hay.

Si la sesión se está usando por Remote Control, esta fase sigue siendo igual: primero contexto, después implementación.

### Regla

Si el relevamiento detecta impacto cross-repo, no pasar a implementación sin asumir explícitamente ese alcance.

## Fase 2. Implementación del cambio

Una vez entendido el alcance, usar el agente implementador del repo.

### Agente a usar por repo

- API: `api-engineer`
- Admin: `admin-engineer`
- Web: `storefront-engineer`

### Qué pedirle

```text
Usá api-engineer para implementar el cambio con el alcance que detectó context-mapper.
```

```text
Usá admin-engineer para aplicar el cambio sin romper onboarding, contratos ni seguridad.
```

```text
Usá storefront-engineer para implementar esto respetando multi-tenant y la estrategia de ramas.
```

### Buenas prácticas en esta fase

1. Pedir cambios pequeños y verificables.
2. Si hay riesgo contractual, dividir la tarea en dos pasos.
3. No mezclar implementación con revisión final en el mismo pedido.
4. Si el cambio toca docs, pedirlo explícitamente.

## Fase 3. Auditoría de contrato y seguridad

Después de implementar, hacer una pasada específica de revisión técnica y no confiar solo en que “compila”.

### Agente a usar

- `contract-guardian`

### Qué pedirle

```text
Usá contract-guardian para revisar impacto cross-repo, contratos, multi-tenant y riesgos residuales.
```

### Qué debería revisar

- cambios de request/response;
- auth y permisos;
- deriva entre API, Admin y Web;
- ramas o flujo operativo incorrecto;
- tests faltantes;
- docs faltantes.

### Cuándo esta fase es obligatoria

Siempre que se toque alguno de estos temas:

- DTOs o endpoints;
- pagos o webhooks;
- onboarding/provisioning;
- tenant resolution;
- checkout o auth;
- Edge Functions;
- reglas de plan, billing o entitlements.

## Fase 4. Validación local

Con la implementación y la auditoría hechas, recién ahí correr la validación final.

### Agente a usar

- `quality-gate`

### Qué pedirle

```text
Usá quality-gate para validar este cambio y devolveme solo errores accionables.
```

### Comandos por repo

#### API

```bash
npm run lint
npm run typecheck
npm run build
ls -la dist/main.js
npm run test
```

Si toca auth, pagos, multi-tenant o flujos integrados:

```bash
npm run test:e2e
```

#### Admin

```bash
npm run lint
npm run typecheck
npm run build
```

Si toca Edge Functions críticas:

```bash
./scripts/test-edge-function.sh
```

#### Web

```bash
node scripts/ensure-no-mocks.mjs
npm run lint
npm run typecheck
npm run build
```

Si toca componentes/hooks:

```bash
npm run test:unit
```

Si toca checkout, auth, carrito o navegación crítica:

```bash
npm run test:e2e
```

Validación integral recomendada:

```bash
npm run ci:storefront
```

## Fase 5. Documentación del cambio

Si el cambio fue real y persistente, debe quedar documentado.

### Dónde documentar

Siempre en:

- `novavision-docs/changes/`

Y si además hace falta una guía operativa o análisis más largo:

- `runbooks/`
- `analysis/`
- `plans/`

### Regla práctica

- `changes/`: qué se hizo.
- `runbooks/`: cómo se usa o cómo se opera.
- `plans/`: qué se va a hacer.
- `analysis/`: por qué pasó o qué se auditó.

## Fase 6. Cierre y siguiente paso

La tarea se considera cerrada cuando tenés:

1. cambio implementado;
2. revisión de contrato hecha;
3. validación ejecutada;
4. documentación actualizada;
5. claridad sobre si hay que seguir con otro repo.

Si no se cumple alguno de esos puntos, la sesión no está realmente cerrada.

## Flujos rápidos recomendados

## Caso A. Cambio típico de backend

```text
1. Usá context-mapper para relevar el cambio.
2. Usá api-engineer para implementarlo.
3. Usá contract-guardian para revisar contratos y multi-tenant.
4. Usá quality-gate para validar.
```

## Caso B. Cambio típico de dashboard admin

```text
1. Usá context-mapper para mapear UI, hooks, Edge Functions e impacto en API.
2. Usá admin-engineer para implementarlo.
3. Usá contract-guardian para revisar payloads, onboarding y seguridad.
4. Usá quality-gate para validar.
```

## Caso C. Cambio típico de storefront

```text
1. Usá context-mapper para mapear vista, template, hook y riesgos cross-repo.
2. Usá storefront-engineer para implementarlo.
3. Usá contract-guardian para revisar contratos, tenant resolution y ramas.
4. Usá quality-gate para validar.
```

## Caso D. Cambio que impacta más de un repo

Secuencia sugerida:

1. arrancar en el repo principal del cambio;
2. hacer relevamiento;
3. implementar el repo fuente del contrato;
4. revisar el impacto en el repo consumidor;
5. validar ambos lados;
6. documentar todo en `novavision-docs/changes/`.

## Anti-patrones a evitar

No usar Claude Code así:

1. pedir implementación sin relevamiento previo;
2. mezclar tres repos en el mismo prompt sin definir repo principal;
3. pedir commit o push sin validación;
4. omitir `contract-guardian` en cambios de contrato;
5. omitir `quality-gate` cuando el cambio toca código;
6. hacer cambios grandes sin documentar el resultado.

## Plantillas cortas para usar en el chat

### Relevamiento

```text
Usá context-mapper para relevar esta tarea y resumime alcance, archivos, riesgos, tests y comandos.
```

### Implementación

```text
Usá api-engineer para implementar este cambio con foco en multi-tenant y contratos estables.
```

```text
Usá admin-engineer para implementar este cambio sin romper onboarding ni exponer secretos en frontend.
```

```text
Usá storefront-engineer para implementar este cambio respetando multi-tenant y la estrategia de ramas.
```

### Revisión

```text
Usá contract-guardian para revisar impacto cross-repo, contratos, seguridad y riesgos residuales.
```

### Validación

```text
Usá quality-gate para validar el cambio y devolveme solo errores accionables.
```

## Resumen ejecutivo

La secuencia estándar para NovaVision es:

1. `context-mapper`
2. implementador del repo
3. `contract-guardian`
4. `quality-gate`
5. documentación en `novavision-docs`

Si se respeta ese orden, Claude Code deja de ser una caja negra y pasa a operar como un proceso de desarrollo controlado por fases.