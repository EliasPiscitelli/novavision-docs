# Cambio: T&C — Compliance legal completo (envíos, pagos, facturación, exclusión NovaVision)

- **Autor:** agente-copilot
- **Fecha:** 2026-02-19
- **Rama:** feature/multitenant-storefront → cherry-pick a develop + feature/onboarding-preview-stable
- **Archivos:** `src/components/TermsConditions/index.jsx`

## Resumen

Se completó la auditoría legal del componente `TermsConditions` comparando contra los 8 documentos legales en `novavision-docs/legal/`. Se identificaron gaps y se agregaron las secciones faltantes para cumplimiento normativo argentino.

## Cambios aplicados

### Sección VI: ENVÍOS, ENTREGAS Y FORMAS DE PAGO (nueva)

- **6.1. Envíos y Entregas:** El Vendedor es el único responsable de despacho, plazos y calidad de envío. NovaVision no participa en logística.
- **6.2. Formas de Pago:** Mercado Pago procesa los pagos. Ni Vendedor ni NovaVision almacenan datos de tarjetas. Precios incluyen IVA.
- **6.3. Facturación:** Emisión de facturas electrónicas es responsabilidad exclusiva del Vendedor (RG AFIP 4291/2018). NovaVision no emite facturas ni interviene en gestión tributaria.

### Sección IX: EXCLUSIÓN DE RESPONSABILIDAD DE NOVAVISION (nueva)

- NovaVision es únicamente la proveedora de la plataforma tecnológica.
- No participa en fabricación, almacenamiento, envío ni entrega.
- No procesa devoluciones ni reembolsos.
- No asume responsabilidad por incumplimientos fiscales de los comercios.
- Podrá brindar información de registro si lo requieren autoridades competentes.

### Renumeración

- Secciones VI→VII (Arrepentimiento), VII→VIII (Devoluciones), anteriormente sin numerar → IX (Exclusión), VIII→X (Legislación).
- Corregidas todas las referencias cruzadas (sección 7.4, 10.3, etc.).

### Sección X.3: Resolución alternativa de conflictos (nueva)

- Links a COPREC y Dirección Nacional de Defensa del Consumidor.

## Matriz de compliance final

| Item | Legal docs | Componente T&C | Estado |
|------|-----------|----------------|--------|
| Disclaimer NovaVision no es vendedor | ✅ 08-aviso-legal | ✅ Sección IX | OK |
| Exclusión envíos/devoluciones | ✅ 07-terminos (Sec. 9) | ✅ Sección IX + VI | OK |
| Envíos y entregas | ✅ 07-terminos (Sec. 4) | ✅ Sección VI.1 | OK |
| Formas de pago (Mercado Pago) | ✅ 07-terminos (Sec. 3) | ✅ Sección VI.2 | OK |
| Facturación electrónica | ✅ 01-terminos (3.6) | ✅ Sección VI.3 + IX | OK |
| Botón de Baja suscripción | ✅ 06-suscripcion | N/A (merchants) | OK |

## Cómo probar

1. Levantar web: `npm run dev`
2. Abrir cualquier tienda → aceptar T&C → "Ver todos los términos"
3. Verificar que aparecen las secciones VI (Envíos/Pagos/Facturación), IX (Exclusión NovaVision), X.3 (COPREC/Defensa Consumidor)
4. Verificar numeración correlativa I→X

## Commits

- `7c08915` — feat(web): T&C - add facturación electrónica as merchant obligation + NovaVision exclusion
- `d4c6739` — feat(web): T&C - add envíos/pagos/exclusión NovaVision sections, renumber and fix cross-references

## Notas de seguridad

No aplica — cambios son solo de contenido legal en JSX estático. No hay cambios en lógica, API ni DB.
