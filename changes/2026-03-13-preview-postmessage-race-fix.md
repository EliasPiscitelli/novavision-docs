# Fix: PostMessage race condition in PreviewHost + height ratchet

- **Fecha:** 2026-03-13
- **Autor:** agente-copilot
- **Rama Web:** develop → cherry-pick a feature/multitenant-storefront, feature/onboarding-preview-stable
- **Rama Admin:** feature/automatic-multiclient-onboarding

## Archivos modificados

- `apps/web/src/pages/PreviewHost/index.tsx` (+110/−19)
- `apps/admin/src/components/PreviewFrame.tsx` (+16)

## Resumen

Corrige el bug donde el preview del Design Studio (Step 4 del builder wizard) se quedaba en "Conectando con el editor…" indefinidamente.

### Causa raíz
Race condition en el protocolo PostMessage iframe:
1. PreviewFrame crea iframe → useEffect dispara `post()` inmediatamente → mensaje perdido (JS del iframe no está listo)
2. El evento `load` del iframe se dispara → PreviewFrame reintenta → PERO el chunk lazy de PreviewHost aún se está cargando → mensaje perdido de nuevo
3. PreviewHost finalmente se monta → intenta enviar `nv:preview:ready` PERO el código viejo bloqueaba cuando `parentOriginRef.current === "*"` → nunca se enviaba
4. Sin más reintentos → "Conectando" persiste para siempre

### Correcciones aplicadas

**PreviewHost (web):**
- `postToParent(msg, forceWildcard)` — acepta modo wildcard, ya no bloquea con origin "*"
- `sendReady()` con fallback wildcard cuando no hay `document.referrer`
- `setInterval(500ms)` reintenta `nv:preview:ready` hasta recibir payload (se limpia al recibir)
- Componente `NotFound` para acceso directo con token inválido
- Check `isEmbedded` (`window.parent !== window`)
- `ALLOWED_ORIGINS` — allowlist de origins basada en env (vacío en dev = acepta todos)
- Reset de height: `lastHeightRef.current = 0` en cada cambio de estado
- `computeHeight` usa solo `root.scrollHeight` (corrige efecto ratchet)
- Logs de diagnóstico en cada gate de validación (`[PreviewHost]`)

**PreviewFrame (admin):**
- Después de `onLoad`, programa 3 reintentos a 300/800/1500ms
- Resetea `lastPayloadRef` antes de cada reintento para evitar dedup
- Listener `onReady` resetea `lastPayloadRef` antes de llamar `post()`
- Función de cleanup limpia los timers en unmount

## Cómo probar

1. Levantar admin (`npm run dev`) y web (`npm run dev`)
2. Ir al builder wizard → Step 4 (Design Studio)
3. El preview del iframe debe cargarse correctamente (no quedarse en "Conectando")
4. Abrir DevTools → Console → filtrar por `[PreviewHost]` para ver logs de diagnóstico
5. Cambiar colores/template y verificar que el preview se actualice

## Notas de seguridad
- `ALLOWED_ORIGINS` vacío en dev permite cualquier origin (conveniente para desarrollo)
- En producción, configurar `VITE_ALLOWED_PREVIEW_ORIGINS` o `VITE_ADMIN_URL` para restringir origins
