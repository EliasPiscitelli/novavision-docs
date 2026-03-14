# Cambio: paridad de preview en template_8 y reducción de ruido inicial

- Autor: agente-copilot
- Fecha: 2026-03-14
- Rama: develop / feature/automatic-multiclient-onboarding
- Archivos: apps/web/src/templates/eighth/pages/HomePageLumina/index.jsx, apps/web/src/templates/eighth/pages/HomePageLumina/index.test.jsx, apps/admin/src/components/PreviewFrame.tsx

Resumen: se corrigió la duplicación del footer en `template_8` cuando la home se renderiza desde `config.sections`, y se eliminaron reintentos redundantes del `PreviewFrame` después del `load` del iframe.

Por qué: el preview nativo de `template_8` estaba mezclando dos contratos de render. En modo dinámico ya recorría las secciones configuradas, incluyendo `footer.eighth`, pero además agregaba un `FooterLumina` fijo al final. Eso generaba inconsistencia visual entre preview y tienda publicada. A la vez, la página importaba el layout estático completo aunque no se usara, y el `PreviewFrame` reenviaba el mismo payload varias veces, lo que amplificaba el ruido del primer render.

Cómo probar:

```bash
cd apps/web
npm run test -- src/templates/eighth/pages/HomePageLumina/index.test.jsx
npm run lint
npm run typecheck
npm run build

cd ../admin
npm run lint
npm run typecheck
```

Notas de seguridad: sin impacto en credenciales, RLS o contratos de API. El cambio solo afecta composición de UI y mensajería del iframe de preview.