# Cambio: workflow IG inbound compatible con relay validado por API

- Autor: agente-copilot
- Fecha: 2026-03-09
- Rama: main
- Archivos: n8n-workflows/wf-ig-inbound-v1.json

Resumen: el nodo `Verify Meta Signature` ahora acepta payloads reenviados por la API cuando vienen marcados con `relay.validated_by_api=true`.

Por qué: el API de NovaVision valida la firma HMAC usando el raw body original de Meta. Cuando luego reenvía el payload a n8n, el JSON puede reserializarse y hacer fallar una segunda validación bit a bit. El workflow debe confiar en la validación ya hecha por la API para no bloquear el auto-reply.

Cómo probar:

1. Reimportar o actualizar el workflow `WF-IG-INBOUND-V1 — Instagram DM Inbound` en n8n.
2. Publicarlo/activarlo.
3. Enviar un DM de prueba al Instagram de NovaVision.
4. Verificar que se ejecute `Send IG Reply` y que aparezca el outbound en `message_events`.

Notas de seguridad:
- el bypass aplica sólo cuando el payload trae `relay.validated_by_api=true`
- la validación original HMAC sigue ocurriendo en la API antes del reenvío a n8n