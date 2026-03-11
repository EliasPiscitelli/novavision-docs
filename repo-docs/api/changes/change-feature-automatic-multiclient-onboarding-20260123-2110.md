# Cambio: Normalización de planes en paletas/onboarding

- Autor: agente-copilot
- Fecha: 2026-01-23
- Rama: feature/automatic-multiclient-onboarding
- Archivos: apps/api/src/palettes/palettes.service.ts, apps/api/src/onboarding/onboarding.service.ts

## Resumen
Se normalizó el plan legacy "pro" a "enterprise" en las respuestas de paletas y en el onboarding para evitar inconsistencias entre Admin y Builder.

## Por qué
Garantizar que el builder reciba el plan correcto y que las paletas se etiqueten con Enterprise de forma consistente.

## Cómo probar
- GET /palettes/catalog y /palettes/admin/catalog: verificar que min_plan_key nunca sea "pro".
- Onboarding paso de paletas: confirmar etiquetas Growth/Enterprise correctas.

## Notas de seguridad
Sin impacto en seguridad.
