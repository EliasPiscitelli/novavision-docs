# 🚀 NovaVision Dev Environment - Quick Start

## Resumen en 60 segundos

**¿Qué estamos construyendo?**

Un entorno de desarrollo profesional con:

1. **Dev Portal** (`/__dev`) - Página guía + playground de componentes
2. **Generación IA** - Prompts estandarizados para Magic Patterns
3. **Auditoría** - Validación automática de multi-tenant, estilos, seguridad
4. **Staging Area** - Revisar código antes de commit
5. **Versionado** - Templates con semver (boutique@1.0.0)

---

## Estructura Base

```
apps/web/src/
├── __dev/           ← Dev Portal (solo DEV)
├── core/            ← Schemas, validators, types
├── ai/              ← Prompts y auditors
├── templates/       ← Templates versionados
└── theme/           ← Tailwind config
```

---

## Primeros Pasos

### 1. Crear rama develop
```bash
cd apps/web
git checkout feature/multitenant-storefront
git checkout -b develop
git push -u origin develop
```

### 2. Instalar dependencias
```bash
npm install zod zod-to-json-schema @monaco-editor/react
npm install -D tailwindcss @tailwindcss/typography @babel/parser @babel/traverse
npx tailwindcss init
```

### 3. Probar Dev Portal
```bash
npm run dev
# Abrir http://localhost:5173/__dev
```

---

## Flujo de Trabajo

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│   develop    │ ←─ │  tu-branch   │    │  Staging     │
│   (base)     │    │  (feature)   │ ←─ │  Area        │
└──────────────┘    └──────────────┘    └──────────────┘
       │                                       ↑
       │                              ┌────────┴────────┐
       │                              │  IA + Auditor   │
       │                              └─────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────┐
│  Cherry-pick a:                                       │
│  • feature/automatic-multiclient-onboarding          │
│  • feature/multitenant-storefront                    │
└──────────────────────────────────────────────────────┘
```

---

## Stack Tecnológico

| Área | Tecnología | Por qué |
|------|------------|---------|
| Estilos | Tailwind CSS | styled-components deprecado |
| Validación | Zod | Runtime + types |
| Editor código | Monaco | VS Code experience |
| Preview | iframe + viewports | Responsive testing |
| IA | Magic Patterns | Genera código listo |

---

## Próximos Pasos

1. **Esta semana:** Crear estructura de carpetas + Dev Portal shell
2. **Semana 2:** Schemas Zod + Playground básico
3. **Semana 3-4:** Sistema de prompts + Auditoría
4. **Semana 5-6:** Staging + Migración Tailwind

Ver plan completo en: [DEV_ENVIRONMENT_MASTER_PLAN.md](./DEV_ENVIRONMENT_MASTER_PLAN.md)
