# Plan de validacion y resolucion de warnings en API

- Fecha: 2026-03-07
- Autor: GitHub Copilot
- Repo objetivo: apps/api
- Base actual: 1379 warnings, 0 errors en `npm run lint`

## Objetivo

Reducir warnings de manera controlada, sin mezclar limpieza de tipos con cambios funcionales y sin volver a romper bootstrap, contratos de pago ni tests.

## Estado actual

- `npm run lint`: 1379 warnings, 0 errors.
- `npm run typecheck`: OK.
- `npm run build`: OK.
- `npm test -- --runInBand`: OK.

## Principio de trabajo

- No atacar los 1379 warnings en un solo batch.
- Limpiar por dominio funcional y por tipo de warning.
- Cada etapa debe cerrar con validacion completa del API.
- No convertir `any` a tipos falsos o engañosos solo para silenciar ESLint.

## Priorizacion

### Etapa 1: warnings en codigo tocado recientemente

Foco:

- `src/tenant-payments/**`
- `src/import-wizard/**`
- `src/shipping/**`
- specs y helpers modificados en esta tanda

Objetivo:

- bajar warnings en zonas activas del flujo de pagos, importacion y checkout
- evitar nueva deuda en areas donde ya hubo cambios productivos

### Etapa 2: controllers y services de bajo riesgo

Foco:

- `src/users/**`
- `src/themes/**`
- `src/categories/**`
- `src/contact-info/**`
- `src/social-links/**`
- `src/faq/**`
- `src/service/**`

Objetivo:

- reemplazar `any` por DTOs, interfaces de respuesta y tipos de Supabase en superficies CRUD simples

### Etapa 3: dominios pesados y workers

Foco:

- `src/worker/provisioning-worker.service.ts`
- `src/tenant/tenant.service.ts`
- `src/tenant-payments/mercadopago.service.ts`

Objetivo:

- atacar los archivos con mayor concentracion de warnings
- introducir tipos compartidos para payloads externos, snapshots y respuestas intermedias

## Estrategia tecnica

### 1. Clasificar warnings

Separar por categorias:

- `@typescript-eslint/no-explicit-any`
- parámetros implícitos de integraciones externas
- respuestas de Supabase sin tipado
- mocks de tests con tipos incompletos

### 2. Crear tipos reutilizables

Antes de reemplazar `any`, definir:

- tipos de `OrderSnapshot`, `PaymentDetails`, `ClientPlanEntitlements`
- tipos de filas mínimas para consultas Supabase frecuentes
- helpers para mocks tipados en tests

### 3. Resolver por lotes pequeños

Lote sugerido: 50 a 120 warnings por PR.

Cada lote debe tener alcance único:

- pagos
- shipping
- import wizard
- CRUD dashboard
- workers

## Validacion obligatoria por lote

En `apps/api`:

```bash
npm run lint
npm run typecheck
npm run build
npm test -- --runInBand
```

## Criterios de aceptacion por etapa

- no suben los warnings totales
- no aparecen errores nuevos de lint ni typecheck
- build verde
- tests verdes
- sin regresiones en bootstrap ni healthcheck

## Riesgos

- tipar mal respuestas dinámicas de Supabase y romper servicios en runtime
- endurecer demasiado tipos de tests y generar mocks frágiles
- mezclar refactor de tipos con cambio funcional real

## Mitigaciones

- priorizar tipos mínimos y evolutivos
- usar `unknown` + narrowing cuando no exista contrato estable
- mantener PRs chicas y por dominio
- correr suite completa después de cada lote

## Orden recomendado de ejecucion

1. `tenant-payments` y `shipping`
2. `import-wizard`
3. CRUD simples (`users`, `themes`, `categories`, `contact-info`, `social-links`, `faq`, `service`)
4. `worker/provisioning-worker.service.ts`
5. `tenant/tenant.service.ts`

## Resultado esperado

- corto plazo: eliminar warnings en zonas de mayor riesgo operativo
- mediano plazo: bajar el total por debajo de 800
- largo plazo: dejar `lint` sin warnings bloqueando nueva deuda desde CI