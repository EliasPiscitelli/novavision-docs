# Cambio: corrección del contador de warnings en pre-push de web

- Autor: agente-copilot
- Fecha: 2026-03-14
- Rama: develop / feature/multitenant-storefront
- Archivos: apps/web/scripts/pre-push-check.sh

Resumen: se corrigió el script de validación previa al push de web para que el conteo de errores y warnings de ESLint no concatene dos valores `0` cuando no hay coincidencias.

Por qué: el flujo de push estaba pasando, pero mostraba `integer expected` en la comparación numérica del script. La causa era el uso de `grep -c ... || echo "0"`, que en el caso sin matches terminaba devolviendo la salida de `grep` más el fallback, dejando una cadena inválida para `test -gt`.

Cómo probar:

```bash
cd apps/web
bash scripts/pre-push-check.sh
```

Resultado esperado:

- No aparece el warning `integer expected`.
- Si lint no tiene errores, el script informa correctamente warnings y permite el push.

Notas de seguridad: sin impacto en runtime, build, credenciales o contratos. Solo corrige la robustez del script local de validación.