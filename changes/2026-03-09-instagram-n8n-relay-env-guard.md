# Cambio: Instagram n8n relay sin env en Code nodes

- Fecha: 2026-03-09
- Autor: GitHub Copilot
- Rama: main
- Archivos:
  - n8n-workflows/wf-ig-webhook-verify-v1.json
  - n8n-workflows/wf-ig-inbound-v1.json
  - n8n-workflows/wf-ig-delivery-status-v1.json
  - n8n-workflows/docs/ig-dm-staging-smoke-2026-03-08.md
  - n8n-workflows/implementations/ig-dm-production-scope-2026-03-08.md

Resumen:
Se alineó la documentación y los workflows fuente de Instagram con la arquitectura real de producción: Meta verifica contra el backend API y n8n procesa sólo payloads relayed por el backend ya validados.

Por qué:
El runtime actual de n8n está bloqueando acceso a env vars dentro de nodos Code. Eso rompía `WF-IG-WEBHOOK-VERIFY-V1` y dejaba frágiles los nodos de verificación de inbound/status pese a que la firma ya se valida en el backend antes del relay.

Cómo probar:
1. Importar nuevamente los workflows actualizados en n8n.
2. Publicar `WF-IG-INBOUND-V1` y `WF-IG-DELIVERY-STATUS-V1`.
3. Despublicar o dejar sin uso público `WF-IG-WEBHOOK-VERIFY-V1`.
4. Confirmar en Meta que el callback público es `https://api.novavision.lat/webhooks/instagram`.
5. Enviar un DM de prueba y revisar que el inbound llegue a n8n sin error en `Verify Meta Signature`.

Notas de seguridad:
- Se evita exponer o resolver secretos de Meta dentro de nodos Code de n8n.
- La validación de firma y verify token queda centralizada en el backend, que ya maneja secretos de entorno de forma segura.
