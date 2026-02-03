# Cambio: Ajustes UI checklist completitud

- Autor: GitHub Copilot
- Fecha: 2026-02-05 12:00
- Rama: pendiente
- Archivos modificados:
  - src/pages/AdminDashboard/ClientApprovalDetail.jsx
  - src/pages/AdminDashboard/PendingCompletionsView.tsx
  - src/constants/reviewChecklist.js

## Resumen
Se eliminaron referencias a banners en la UI de completitud y se ajustó el checklist de revisión para sacar banners e imágenes de producto como requisito.

## Motivo
Banners dejaron de ser requisito de completitud.

## Cómo probar
- Navegar a la vista de aprobación y verificar que el checklist no muestre banners.
- Revisar la vista de completitud pendiente para confirmar que no aparece el item de banners.

## Notas de seguridad
Sin impacto en seguridad.
