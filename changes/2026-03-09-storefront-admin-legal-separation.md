# Admin + Web — Disclaimer fijo y separación legal de plataforma

- Fecha: 2026-03-09
- Autor: GitHub Copilot
- Repos: `apps/admin`, `apps/web`

## Resumen

Se completó la segunda etapa del ajuste legal:

1. Admin: se agregó un disclaimer fijo en el footer público, debajo de los links legales.
2. Web: se centralizó un bloque legal reusable para footers y se corrigió la LegalPage del storefront para separar con claridad:
   - responsabilidades del comercio vendedor
   - responsabilidades de NovaVision como proveedor tecnológico

## Archivos principales

- `apps/admin/src/components/Footer/index.jsx`
- `apps/admin/src/components/Footer/style.jsx`
- `apps/admin/src/i18n/es.json`
- `apps/admin/src/i18n/en.json`
- `apps/web/src/legal/storeLegal.js`
- `apps/web/src/components/legal/StoreLegalFooterBlock.jsx`
- `apps/web/src/pages/LegalPage/index.jsx`
- `apps/web/src/routes/AppRoutes.jsx`
- footers de templates clásicos, fourth, fifth y vanguard

## Motivo

Se necesitaba que el sitio dejara visible y permanente que NovaVision no es el vendedor, no administra la relación comercial del comercio y no responde por productos, pagos, impuestos, envíos o devoluciones del merchant.

## Validación esperada

- Admin: footer público con disclaimer fijo y links legales reales.
- Web: footers con links legales + identificación del merchant si existe + disclaimer de NovaVision como plataforma.
- LegalPage buyer-facing con copy alineado a esa separación.