# Cambio: instalación y configuración de Claude Code para API, Admin y Web

- Autor: agente-copilot
- Fecha: 2026-03-14
- Rama: feature/automatic-multiclient-onboarding / feature/multitenant-storefront
- Archivos: `~/.bashrc`, `~/.bash_profile`, `~/.zprofile`, `~/.zshrc`, `~/.claude/settings.json`, `~/.claude/CLAUDE.md`, `apps/api/CLAUDE.md`, `apps/api/.claude/**`, `apps/admin/CLAUDE.md`, `apps/admin/.claude/**`, `apps/web/CLAUDE.md`, `apps/web/.claude/**`

## Resumen

Se instaló Claude Code en la máquina con el instalador nativo oficial y se dejó una configuración operativa homogénea para los tres repos productivos de NovaVision.

La configuración quedó dividida en tres capas:

1. global del usuario en `~/.claude/`;
2. configuración de proyecto por repo en `CLAUDE.md` y `.claude/settings.json`;
3. subagentes especializados por responsabilidad dentro de `.claude/agents/` para API, Admin y Web.

## Qué se configuró

### Instalación global

- Claude Code instalado en `~/.local/bin/claude`.
- Se agregó `~/.local/bin` al `PATH` de Bash y Zsh para que la CLI quede disponible en terminales nuevas.
- Se creó `~/.claude/settings.json` con idioma español, canal `stable` y modo de teammates `in-process`.
- Se creó `~/.claude/CLAUDE.md` con reglas globales mínimas: español, sin commit/push sin confirmación y revisión previa de `novavision-docs` en proyectos NovaVision.

### Configuración por repo

Cada repo productivo ahora tiene:

- `CLAUDE.md` con reglas del repo y flujo recomendado.
- `.claude/settings.json` con:
  - `plansDirectory` apuntando a `novavision-docs/plans`;
  - `additionalDirectories` para que Claude pueda leer los otros repos y `novavision-docs`;
  - permisos `allow/ask/deny` alineados al stack real y bloqueando lectura de `.env`.
- `.claude/rules/*.md` con reglas path-scoped del tipo de código principal de cada repo.

### Agentes especializados

Se definió un proceso base común en los tres repos:

1. `context-mapper`: relevamiento inicial y mapa de impacto.
2. `repo-engineer` del repo (`api-engineer`, `admin-engineer`, `storefront-engineer`): implementación.
3. `contract-guardian`: auditoría de contratos, seguridad y compatibilidad cross-repo.
4. `quality-gate`: validación local con comandos reales del repo.

## Por qué

El objetivo fue dejar Claude Code listo para trabajar con una metodología repetible y específica para NovaVision, evitando dos problemas habituales:

- configuraciones genéricas que no respetan ramas, multi-tenant ni reglas cross-repo;
- prompts largos repetidos manualmente en cada sesión.

Con esta base, Claude Code puede arrancar con instrucciones persistentes, acceso controlado a los repos hermanos y agentes con responsabilidades claras.

## Cómo usarlo

### Primera ejecución

```bash
claude --version
claude
```

Luego autenticarse desde la CLI en el primer arranque interactivo.

### Flujo sugerido por tarea

En cualquiera de los tres repos:

1. arrancar Claude Code en la raíz del repo;
2. pedir: “usá `context-mapper` para relevar este cambio”;
3. pedir: “usá `api-engineer` / `admin-engineer` / `storefront-engineer` para implementarlo”;
4. pedir: “usá `contract-guardian` para revisar impacto cross-repo”;
5. pedir: “usá `quality-gate` para validar”.

## Validación realizada

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

Resultado esperado tras abrir una terminal nueva:

```bash
claude --version
```

## Riesgos / notas

- La autenticación inicial de Claude Code requiere intervención del usuario en el primer `claude` interactivo.
- Los subagentes son project-level: si se los crea o modifica manualmente durante una sesión ya abierta, Claude Code puede requerir recarga o reinicio para detectarlos.
- Se bloquearon lecturas de `.env` a nivel de proyecto, pero eso no reemplaza prácticas seguras del repo ni revisiones humanas.