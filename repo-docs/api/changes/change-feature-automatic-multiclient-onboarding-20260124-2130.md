# Cambio: Normalización legacy → --nv-* en paletas de onboarding

- Autor: agente-copilot
- Fecha: 2026-01-24
- Rama: feature/automatic-multiclient-onboarding
- Archivos: apps/api/src/palettes/palettes.service.ts, apps/api/src/onboarding/onboarding.service.ts

Resumen: Se mapean keys legacy de paletas (primary/background/text/accent/…) a variables `--nv-*` antes de limpiar, para evitar previews incompletas que generaban botones y textos oscuros en temas starter (ej. Startup Naranja).

Por qué: El catálogo seed usa keys legacy. El normalizador eliminaba esas keys sin mapear, dejando `paletteVars` vacías y provocando estilos inconsistentes.

Cómo probar / comandos ejecutados:
- No ejecutado en esta etapa.

Notas de seguridad:
- Sin cambios en credenciales ni flujos sensibles.
