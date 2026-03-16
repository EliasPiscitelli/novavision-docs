# Cambio: guía operativa de Claude Code por fases

- Autor: agente-copilot
- Fecha: 2026-03-14
- Repos: novavision-docs
- Archivos: `runbooks/claude-code-por-fases.md`

## Resumen

Se agregó una guía operativa en documentación para usar Claude Code por fases dentro de NovaVision.

La guía organiza el uso del agente en un flujo estándar:

1. apertura del repo correcto;
2. relevamiento de contexto;
3. implementación;
4. auditoría de contrato y seguridad;
5. validación local;
6. documentación y cierre.

Luego se amplió para incluir una fase opcional de `Remote Control`, con el comportamiento real de la versión local instalada y notas prácticas para sesiones concurrentes en NovaVision.

## Por qué

Ya existía la instalación y configuración técnica de Claude Code, pero faltaba un runbook simple para usarlo de manera consistente en API, Admin y Web.

El objetivo de esta guía es reducir prompts improvisados y dejar un método operativo claro para cualquier sesión futura.

Además, se incorporó explícitamente el índice oficial `llms.txt` como punto de partida para descubrir documentación de Claude Code antes de profundizar en páginas específicas.

## Resultado

La documentación quedó disponible en:

- `novavision-docs/runbooks/claude-code-por-fases.md`

Incluye:

- agentes por repo;
- fases del flujo;
- comandos por repo;
- uso opcional de Remote Control;
- plantillas de prompts;
- anti-patrones a evitar.