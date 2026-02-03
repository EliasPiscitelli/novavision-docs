# Cambio: Dev Portal + AI Tools + Design System Infrastructure

- **Autor:** GitHub Copilot Agent
- **Fecha:** 2026-02-03
- **Ramas Afectadas:** 
  - Web: `feature/multitenant-storefront` → pushed ✅
  - API: `feature/automatic-multiclient-onboarding` → pushed ✅
  - Admin: `feature/automatic-multiclient-onboarding` → pushed ✅
- **Apps Afectadas:** Web (templatetwo), API (templatetwobe), Admin (novavision)

---

## Resumen

Creación completa de la infraestructura del Dev Portal, herramientas de AI para generación de código, sistema de auditoría multi-tenant/estilos/seguridad, y configuración del design system con Tailwind CSS + CSS Variables.

---

## Archivos Creados

### Dev Portal UI (8 archivos)

| Archivo | Descripción |
|---------|-------------|
| `src/__dev/DevPortalApp.jsx` | Entry point del Dev Portal |
| `src/__dev/DevPortalRouter.jsx` | Configuración de rutas |
| `src/__dev/context/DevPortalContext.tsx` | Estado global (viewport, theme, staging) |
| `src/__dev/components/DevPortalLayout.jsx` | Layout con sidebar y controles |
| `src/__dev/components/ResponsiveFrame.jsx` | Frame responsivo para previews |
| `src/__dev/pages/IndexPage/index.jsx` | Dashboard principal |
| `src/__dev/pages/ComponentsPage/index.jsx` | Playground de componentes |
| `src/__dev/pages/TemplatesPage/index.jsx` | Preview de templates |
| `src/__dev/pages/GeneratorPage/index.jsx` | Generador de prompts AI |
| `src/__dev/pages/AuditorPage/index.jsx` | Auditor de código |
| `src/__dev/pages/StagingPage/index.jsx` | Área de staging |
| `src/__dev/pages/DataEditorPage/index.jsx` | Editor JSON |
| `src/__dev/README.md` | Documentación del Dev Portal |

### AI Prompts (3 archivos)

| Archivo | Descripción |
|---------|-------------|
| `src/ai/prompts/template.prompt.md` | Prompt para templates completos |
| `src/ai/prompts/component.prompt.md` | Prompt para componentes |
| `src/ai/prompts/audit.prompt.md` | Prompt para auditoría de código |

### AI Generators (1 archivo)

| Archivo | Descripción |
|---------|-------------|
| `src/ai/generators/PromptBuilder.ts` | Builder fluido para construir prompts |

### AI Auditors (4 archivos)

| Archivo | Descripción |
|---------|-------------|
| `src/ai/auditors/MultiTenantAuditor.ts` | Detecta problemas de aislamiento |
| `src/ai/auditors/StyleAuditor.ts` | Detecta violaciones del design system |
| `src/ai/auditors/SecurityAuditor.ts` | Detecta vulnerabilidades |
| `src/ai/auditors/index.ts` | Auditor unificado |

### Core Data (1 archivo)

| Archivo | Descripción |
|---------|-------------|
| `src/core/data/demoClients.ts` | Datos demo para testing |

### Styles (2 archivos)

| Archivo | Descripción |
|---------|-------------|
| `src/styles/variables.css` | CSS Variables del design system |
| `tailwind.config.js` | Configuración de Tailwind con tokens |

---

## Por Qué Se Hizo

1. **Dev Portal:** Necesidad de un entorno de desarrollo integrado para previsualizar componentes, templates, y probar con datos demo antes de deployar.

2. **AI Tools:** Optimizar el workflow con Magic Patterns mediante prompts estandarizados que incluyen todas las reglas del design system.

3. **Auditors:** Automatizar la detección de:
   - Violaciones de multi-tenant (crítico para SaaS)
   - Uso de styled-components (deprecated en favor de Tailwind)
   - Vulnerabilidades de seguridad

4. **Design System:** Migración a Tailwind CSS con CSS Variables para:
   - Theming dinámico por cliente
   - Mejor performance
   - Consistencia visual

---

## Cómo Probar

### 1. Verificar estructura creada

```bash
# Listar estructura del Dev Portal
ls -la src/__dev/
ls -la src/__dev/pages/
ls -la src/ai/
```

### 2. Verificar imports (lint)

```bash
npm run lint
npm run typecheck
```

### 3. Probar Dev Portal localmente

```bash
npm run dev
# Navegar a: http://localhost:5173/__dev
```

### 4. Probar un auditor

```javascript
import { audit } from './src/ai/auditors';

const code = `
  const { data } = await supabase
    .from('products')
    .select('*');  // ❌ Sin client_id
`;

const result = audit(code, 'test.jsx');
console.log(result);
```

---

## Decisiones de Diseño

1. **Tailwind sobre styled-components:** Mejor performance, theming más simple con CSS vars, mayor adopción en el ecosistema.

2. **Zod para validación:** Type-safe, buena integración con TypeScript, transformaciones automáticas.

3. **Auditors separados:** Cada auditor es independiente y testeable. Se combinan en el index para uso unificado.

4. **Context API sobre Redux:** Suficiente para el estado del Dev Portal, más simple de mantener.

5. **CSS Variables con prefijo `--nv-`:** Evita colisiones, clarifica origen de los valores.

---

## Riesgos y Rollback

### Riesgos

1. **Tailwind config:** Si no se importa `variables.css` antes de otros estilos, las variables estarán undefined.

2. **Dev Portal en producción:** El acceso está protegido por check de `import.meta.env.DEV`, pero verificar que no queden rutas expuestas.

3. **Auditors false positives:** Pueden reportar warnings en código válido (ej: UUIDs legítimos). Refinar regex según casos de uso.

### Rollback

Si hay problemas:

```bash
# Eliminar archivos del Dev Portal
rm -rf src/__dev/
rm -rf src/ai/

# Revertir tailwind.config.js al anterior
git checkout HEAD^ -- tailwind.config.js
```

---

## Notas de Seguridad

- ✅ El Dev Portal solo está accesible en modo desarrollo
- ✅ No se exponen SERVICE_ROLE_KEY en ningún archivo creado
- ✅ Los auditors detectan exposición de secrets
- ✅ Los demo clients no contienen datos reales

---

## Próximos Pasos

1. Integrar Monaco Editor en DataEditorPage para mejor experiencia
2. Agregar más demo clients
3. Conectar staging workflow con Git branches
4. Agregar métricas de uso de componentes
5. Testing E2E del Dev Portal

---

## Commits Realizados

| Repo | Rama | Commit | Mensaje |
|------|------|--------|---------|
| Web | `feature/multitenant-storefront` | `31ad9c9` | feat(dev-portal): Add Dev Portal with AI tools, auditors, and design system |
| API | `feature/automatic-multiclient-onboarding` | `8cc2cc6` | ci: Add GitHub Actions workflow for lint, typecheck, and build validation |
| Admin | `feature/automatic-multiclient-onboarding` | `0aec641` | ci: Add GitHub Actions workflow for lint, typecheck validation |

## Ramas Develop Creadas

Se crearon nuevas ramas `develop` en los 3 repos basadas en las ramas de producción actuales:

- **Web:** `develop` basada en `feature/multitenant-storefront`
- **API:** `develop` basada en `feature/automatic-multiclient-onboarding`
- **Admin:** `develop` basada en `feature/automatic-multiclient-onboarding`

Las ramas `develop` antiguas fueron eliminadas y reemplazadas.

---

## Referencias

- [Tailwind CSS](https://tailwindcss.com/docs)
- [Zod](https://zod.dev)
- [Magic Patterns](https://www.magicpatterns.com/)
- [Dev Portal README](../apps/web/src/__dev/README.md)
