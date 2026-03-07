# Cambio: cleanup de open handle en tests de API

- Autor: GitHub Copilot
- Fecha: 2026-03-07
- Rama: feature/automatic-multiclient-onboarding
- Archivos: apps/api/src/shipping/shipping-quote.service.ts

Resumen: Se corrigio un intervalo interno de ShippingQuoteService que quedaba vivo despues de cerrar Nest en tests e2e y podia disparar el mensaje de Jest sobre open handles.

Por que: El servicio creaba un setInterval en el constructor para limpiar cotizaciones expiradas, pero no implementaba cleanup en el ciclo de vida del modulo. Aunque los tests ejecutaran app.close(), el intervalo podia mantener el event loop activo.

Como probar:

```bash
cd apps/api
npm test -- test/app.e2e-spec.ts --runInBand --detectOpenHandles
```

Resultado esperado: La suite finaliza sin el mensaje "Jest did not exit one second after the test run has completed" por este intervalo.

Notas de seguridad: Sin impacto de seguridad. Es un ajuste de ciclo de vida y limpieza de recursos.