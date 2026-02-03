# 🚀 Plan Maestro: Entorno de Desarrollo NovaVision

> **Fecha:** 2026-02-03  
> **Versión:** 1.0.0  
> **Objetivo:** Crear un entorno de desarrollo profesional, escalable y asistido por IA

---

## 📋 Resumen Ejecutivo

### Lo que querés lograr

1. **Rama `develop`** como base de desarrollo → cherry-pick controlado a ramas estables
2. **Dev Portal** en Web con guías, playground, preview de templates/componentes
3. **Generación de código con IA** controlada (prompts estandarizados, auditoría)
4. **Data estandarizada** con schemas validados (Zod)
5. **Componentes separables** reutilizables entre templates + exclusivos por plan
6. **Versionado de templates** (boutique@1.0.0)
7. **Staging area** para revisar código generado antes de commit
8. **Migración a Tailwind** (styled-components deprecado)

---

## 🏗️ Arquitectura Propuesta

### Estructura de Carpetas en Web (templatetwo)

```
apps/web/
├── src/
│   ├── __dev/                    # 🆕 Dev Portal (solo en DEV)
│   │   ├── DevPortalApp.jsx      # App principal del portal
│   │   ├── DevPortalRouter.jsx   # Router interno
│   │   ├── components/           # UI del portal
│   │   │   ├── Sidebar/
│   │   │   ├── PlaygroundShell/
│   │   │   ├── CodePreview/
│   │   │   ├── DataEditor/
│   │   │   └── ResponsiveFrame/
│   │   ├── pages/
│   │   │   ├── IndexPage/        # Página de inicio/guía
│   │   │   ├── TemplatesPage/    # Preview de templates
│   │   │   ├── ComponentsPage/   # Playground de componentes
│   │   │   ├── PromptsPage/      # Biblioteca de prompts
│   │   │   ├── StagingPage/      # Staging area de código
│   │   │   └── AuditPage/        # Resultados de auditoría
│   │   └── hooks/
│   │       ├── useLocalData.js   # Data local para playground
│   │       └── useAudit.js       # Hook de auditoría
│   │
│   ├── core/                     # 🆕 Core compartido
│   │   ├── schemas/              # Zod schemas
│   │   │   ├── homeData.schema.ts
│   │   │   ├── product.schema.ts
│   │   │   ├── banner.schema.ts
│   │   │   └── index.ts
│   │   ├── validators/           # Validadores
│   │   │   └── dataValidator.ts
│   │   ├── types/                # TypeScript types
│   │   │   └── index.ts
│   │   └── constants/            # Constantes globales
│   │       ├── plans.ts          # Planes y features
│   │       └── componentRegistry.ts
│   │
│   ├── components/               # 🔄 Reorganizar
│   │   ├── ui/                   # Componentes UI base (Tailwind)
│   │   │   ├── Button/
│   │   │   ├── Card/
│   │   │   ├── Modal/
│   │   │   ├── Input/
│   │   │   └── ...
│   │   ├── sections/             # Secciones reutilizables
│   │   │   ├── HeroSection/
│   │   │   ├── ProductCarousel/
│   │   │   ├── ServicesGrid/
│   │   │   ├── FaqAccordion/
│   │   │   ├── ContactForm/
│   │   │   └── ...
│   │   └── layout/               # Layouts
│   │       ├── Header/
│   │       ├── Footer/
│   │       └── ...
│   │
│   ├── templates/                # 🔄 Reorganizar con versiones
│   │   ├── manifest.ts           # Registry de templates
│   │   ├── classic/              # Template Classic Store
│   │   │   ├── v1.0.0/
│   │   │   │   ├── pages/
│   │   │   │   ├── components/   # Componentes específicos
│   │   │   │   ├── theme.ts      # Tailwind config específica
│   │   │   │   └── metadata.ts   # Info del template
│   │   │   └── latest -> v1.0.0  # Symlink a última versión
│   │   ├── modern/
│   │   ├── minimal/
│   │   ├── boutique/
│   │   └── bold/
│   │
│   ├── ai/                       # 🆕 Sistema de IA
│   │   ├── prompts/              # Biblioteca de prompts
│   │   │   ├── template.prompt.md
│   │   │   ├── section.prompt.md
│   │   │   ├── component.prompt.md
│   │   │   └── audit.prompt.md
│   │   ├── schemas/              # Output schemas para IA
│   │   │   ├── templateOutput.schema.ts
│   │   │   └── componentOutput.schema.ts
│   │   ├── generators/           # Generadores controlados
│   │   │   ├── PromptBuilder.ts
│   │   │   └── CodeParser.ts
│   │   └── auditors/             # Auditores de código
│   │       ├── MultiTenantAuditor.ts
│   │       ├── SecurityAuditor.ts
│   │       ├── StyleAuditor.ts
│   │       └── PerformanceAuditor.ts
│   │
│   ├── data/                     # 🆕 Data de desarrollo
│   │   ├── demo/                 # Data demo por defecto
│   │   │   ├── homeData.demo.json
│   │   │   └── clients/
│   │   │       ├── demo-client-1.json
│   │   │       └── demo-client-2.json
│   │   └── mocks/                # Mocks para testing
│   │
│   └── theme/                    # 🔄 Migrar a Tailwind
│       ├── tailwind.config.js    # Config base
│       ├── tokens.ts             # CSS variables
│       └── presets/              # Presets de colores
│           ├── default.ts
│           ├── dark.ts
│           └── elegant.ts
```

---

## 📊 Sistema de Data y Schemas

### Schema Principal (Zod)

```typescript
// src/core/schemas/homeData.schema.ts
import { z } from 'zod';

// Sub-schemas
export const ImageUrlSchema = z.object({
  url: z.string().url(),
  order: z.number().default(0),
});

export const ImageVariantsSchema = z.object({
  lg: z.object({
    w: z.number(),
    avif: z.object({ key: z.string(), bytes: z.number() }).optional(),
    webp: z.object({ key: z.string(), bytes: z.number() }).optional(),
  }).optional(),
  md: z.object({
    w: z.number(),
    avif: z.object({ key: z.string(), bytes: z.number() }).optional(),
    webp: z.object({ key: z.string(), bytes: z.number() }).optional(),
  }).optional(),
  thumb: z.object({
    w: z.number(),
    avif: z.object({ key: z.string(), bytes: z.number() }).optional(),
    webp: z.object({ key: z.string(), bytes: z.number() }).optional(),
  }).optional(),
}).optional();

export const CategorySchema = z.object({
  id: z.string().uuid(),
  name: z.string(),
});

export const ProductSchema = z.object({
  id: z.string().uuid(),
  name: z.string().min(1),
  description: z.string(),
  sku: z.string(),
  filters: z.string().optional(),
  originalPrice: z.number().positive(),
  discountedPrice: z.number().min(0),
  currency: z.enum(['ARS', 'USD', 'EUR']).default('ARS'),
  available: z.boolean(),
  quantity: z.number().int().min(0),
  sizes: z.string().optional(),
  colors: z.string().optional(),
  material: z.string().optional(),
  promotionTitle: z.string().optional(),
  promotionDescription: z.string().optional(),
  discountPercentage: z.number().min(0).max(100),
  validFrom: z.string().nullable(),
  validTo: z.string().nullable(),
  featured: z.boolean(),
  bestSell: z.boolean(),
  sendMethod: z.boolean(),
  tags: z.string().optional(),
  categories: z.array(CategorySchema),
  imageUrl: z.array(ImageUrlSchema),
  client_id: z.string().uuid(),
  image_variants: ImageVariantsSchema.nullable(),
  created_at: z.string(),
  updated_at: z.string(),
});

export const ServiceSchema = z.object({
  id: z.string().uuid(),
  title: z.string(),
  description: z.string(),
  number: z.number(),
  image_url: z.string().url(),
  file_path: z.string(),
  client_id: z.string().uuid(),
  image_variants: ImageVariantsSchema.nullable(),
});

export const BannerSchema = z.object({
  id: z.string().uuid(),
  url: z.string().url(),
  file_path: z.string(),
  type: z.enum(['desktop', 'mobile']),
  link: z.string().nullable(),
  order: z.number(),
  client_id: z.string().uuid(),
  image_variants: ImageVariantsSchema,
});

export const FaqSchema = z.object({
  id: z.string().uuid(),
  question: z.string(),
  answer: z.string(),
  number: z.number(),
  client_id: z.string().uuid(),
});

export const LogoSchema = z.object({
  id: z.string().uuid(),
  url: z.string().url(),
  show_logo: z.boolean(),
  file_path: z.string(),
  client_id: z.string().uuid(),
  image_variants: ImageVariantsSchema,
});

export const ContactInfoSchema = z.object({
  id: z.string().uuid(),
  titleinfo: z.string(),
  description: z.string(),
  number: z.number(),
  created_at: z.string(),
  client_id: z.string().uuid(),
});

export const SocialLinksSchema = z.object({
  id: z.string().uuid(),
  whatsApp: z.string().optional(),
  wspText: z.string().optional(),
  instagram: z.string().url().optional().or(z.literal('')),
  facebook: z.string().url().optional().or(z.literal('')),
  created_at: z.string(),
  client_id: z.string().uuid(),
});

// Schema principal
export const HomeDataSchema = z.object({
  products: z.array(ProductSchema),
  totalItems: z.number(),
  services: z.array(ServiceSchema),
  banners: z.object({
    desktop: z.array(BannerSchema),
    mobile: z.array(BannerSchema),
  }),
  faqs: z.array(FaqSchema),
  logo: LogoSchema,
  contactInfo: z.array(ContactInfoSchema),
  socialLinks: SocialLinksSchema,
});

export type HomeData = z.infer<typeof HomeDataSchema>;
export type Product = z.infer<typeof ProductSchema>;
export type Service = z.infer<typeof ServiceSchema>;
// ... más types
```

### Validador con Corrección Automática

```typescript
// src/core/validators/dataValidator.ts
import { HomeDataSchema, HomeData } from '../schemas/homeData.schema';

export interface ValidationResult {
  isValid: boolean;
  data: HomeData | null;
  errors: string[];
  warnings: string[];
  corrections: string[];
}

export function validateHomeData(data: unknown): ValidationResult {
  const result: ValidationResult = {
    isValid: false,
    data: null,
    errors: [],
    warnings: [],
    corrections: [],
  };

  try {
    // Intentar parsear
    const parsed = HomeDataSchema.safeParse(data);
    
    if (parsed.success) {
      result.isValid = true;
      result.data = parsed.data;
      return result;
    }

    // Si falla, intentar corregir
    const corrected = attemptCorrections(data, parsed.error);
    
    const reparsed = HomeDataSchema.safeParse(corrected.data);
    if (reparsed.success) {
      result.isValid = true;
      result.data = reparsed.data;
      result.corrections = corrected.corrections;
      result.warnings = corrected.warnings;
    } else {
      result.errors = reparsed.error.errors.map(e => 
        `${e.path.join('.')}: ${e.message}`
      );
    }
  } catch (e) {
    result.errors = [`Error inesperado: ${e}`];
  }

  return result;
}

function attemptCorrections(data: any, error: any) {
  const corrections: string[] = [];
  const warnings: string[] = [];
  const corrected = JSON.parse(JSON.stringify(data));

  // Ejemplo de correcciones automáticas:
  
  // 1. Si falta discountPercentage, calcularlo
  if (corrected.products) {
    corrected.products.forEach((p: any, i: number) => {
      if (p.discountPercentage === undefined && p.discountedPrice > 0) {
        p.discountPercentage = Math.round(
          ((p.originalPrice - p.discountedPrice) / p.originalPrice) * 100
        );
        corrections.push(`products[${i}].discountPercentage calculado: ${p.discountPercentage}%`);
      }
      
      // Si imageUrl es string, convertir a array
      if (typeof p.imageUrl === 'string') {
        p.imageUrl = [{ url: p.imageUrl, order: 0 }];
        corrections.push(`products[${i}].imageUrl convertido a array`);
      }
    });
  }

  // 2. Si banners no tiene estructura desktop/mobile
  if (Array.isArray(corrected.banners)) {
    const desktop = corrected.banners.filter((b: any) => b.type !== 'mobile');
    const mobile = corrected.banners.filter((b: any) => b.type === 'mobile');
    corrected.banners = { desktop, mobile };
    corrections.push('banners reestructurado a { desktop, mobile }');
  }

  return { data: corrected, corrections, warnings };
}
```

---

## 🎨 Dev Portal

### Página Index (Guía Principal)

```jsx
// src/__dev/pages/IndexPage/index.jsx
import { motion } from 'framer-motion';
import { Link } from 'react-router-dom';

const SECTIONS = [
  {
    title: '📦 Templates',
    description: 'Preview y selección de templates disponibles',
    link: '/__dev/templates',
    status: 'stable',
  },
  {
    title: '🧩 Componentes',
    description: 'Playground de componentes con data editable',
    link: '/__dev/components',
    status: 'stable',
  },
  {
    title: '🤖 Prompts IA',
    description: 'Biblioteca de prompts para generar código',
    link: '/__dev/prompts',
    status: 'beta',
  },
  {
    title: '📝 Staging',
    description: 'Revisar código generado antes de commit',
    link: '/__dev/staging',
    status: 'beta',
  },
  {
    title: '🔍 Auditoría',
    description: 'Resultados de auditoría de código',
    link: '/__dev/audit',
    status: 'beta',
  },
  {
    title: '📊 Data Schemas',
    description: 'Documentación de schemas y validadores',
    link: '/__dev/schemas',
    status: 'stable',
  },
];

const QUICK_START = [
  {
    step: 1,
    title: 'Elegir base',
    description: 'Seleccioná un template o componente como punto de partida',
  },
  {
    step: 2,
    title: 'Generar con IA',
    description: 'Usá un prompt para generar variaciones o código nuevo',
  },
  {
    step: 3,
    title: 'Previsualizar',
    description: 'Probá con data demo o de un cliente real',
  },
  {
    step: 4,
    title: 'Auditar',
    description: 'Ejecutá auditoría de multi-tenant, seguridad y estilos',
  },
  {
    step: 5,
    title: 'Commit',
    description: 'Si pasa auditoría, guardá en staging para review',
  },
];

export default function IndexPage() {
  return (
    <div className="min-h-screen bg-slate-50 p-8">
      {/* Header */}
      <motion.header 
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        className="mb-12"
      >
        <h1 className="text-4xl font-bold text-slate-900 mb-2">
          🛠️ NovaVision Dev Portal
        </h1>
        <p className="text-slate-600 text-lg">
          Entorno de desarrollo para crear y gestionar templates y componentes
        </p>
        <div className="mt-4 flex gap-2">
          <span className="px-3 py-1 bg-green-100 text-green-800 rounded-full text-sm">
            Rama: develop
          </span>
          <span className="px-3 py-1 bg-blue-100 text-blue-800 rounded-full text-sm">
            Env: {import.meta.env.MODE}
          </span>
        </div>
      </motion.header>

      {/* Quick Start */}
      <section className="mb-12">
        <h2 className="text-2xl font-semibold text-slate-800 mb-6">
          🚀 Quick Start
        </h2>
        <div className="flex gap-4 overflow-x-auto pb-4">
          {QUICK_START.map((item, i) => (
            <motion.div
              key={item.step}
              initial={{ opacity: 0, x: 20 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ delay: i * 0.1 }}
              className="flex-shrink-0 w-48 p-4 bg-white rounded-xl shadow-sm border border-slate-200"
            >
              <div className="w-8 h-8 bg-nv-primary text-white rounded-full flex items-center justify-center mb-3 font-bold">
                {item.step}
              </div>
              <h3 className="font-medium text-slate-900 mb-1">{item.title}</h3>
              <p className="text-sm text-slate-500">{item.description}</p>
            </motion.div>
          ))}
        </div>
      </section>

      {/* Sections Grid */}
      <section>
        <h2 className="text-2xl font-semibold text-slate-800 mb-6">
          📁 Secciones
        </h2>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {SECTIONS.map((section, i) => (
            <motion.div
              key={section.link}
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: i * 0.1 }}
            >
              <Link
                to={section.link}
                className="block p-6 bg-white rounded-xl shadow-sm border border-slate-200 hover:border-nv-primary hover:shadow-md transition-all"
              >
                <div className="flex items-start justify-between mb-3">
                  <h3 className="text-xl font-medium text-slate-900">
                    {section.title}
                  </h3>
                  <span className={`px-2 py-1 rounded text-xs ${
                    section.status === 'stable' 
                      ? 'bg-green-100 text-green-700'
                      : 'bg-yellow-100 text-yellow-700'
                  }`}>
                    {section.status}
                  </span>
                </div>
                <p className="text-slate-600">{section.description}</p>
              </Link>
            </motion.div>
          ))}
        </div>
      </section>

      {/* Footer con links útiles */}
      <footer className="mt-12 pt-8 border-t border-slate-200">
        <div className="flex gap-8">
          <a href="https://github.com/EliasPiscitelli/templatetwo" 
             className="text-slate-600 hover:text-nv-primary">
            📚 Repo Web
          </a>
          <a href="https://github.com/EliasPiscitelli/novavision-docs" 
             className="text-slate-600 hover:text-nv-primary">
            📖 Documentación
          </a>
          <a href="/__dev/prompts" 
             className="text-slate-600 hover:text-nv-primary">
            🤖 Prompts IA
          </a>
        </div>
      </footer>
    </div>
  );
}
```

### Playground de Componentes

```jsx
// src/__dev/pages/ComponentsPage/index.jsx
import { useState, useCallback } from 'react';
import { CodePreview } from '../../components/CodePreview';
import { DataEditor } from '../../components/DataEditor';
import { ResponsiveFrame } from '../../components/ResponsiveFrame';
import { COMPONENT_REGISTRY } from '../../../core/constants/componentRegistry';

export default function ComponentsPage() {
  const [selectedComponent, setSelectedComponent] = useState(null);
  const [localData, setLocalData] = useState({});
  const [viewport, setViewport] = useState('desktop'); // desktop | tablet | mobile

  const handleDataChange = useCallback((newData) => {
    // Solo guarda en memoria local, no en nube
    setLocalData(newData);
  }, []);

  const handleLoadJSON = useCallback((file) => {
    const reader = new FileReader();
    reader.onload = (e) => {
      try {
        const json = JSON.parse(e.target.result);
        setLocalData(json);
      } catch (err) {
        alert('JSON inválido');
      }
    };
    reader.readAsText(file);
  }, []);

  return (
    <div className="flex h-screen">
      {/* Sidebar - Lista de componentes */}
      <aside className="w-64 bg-slate-900 text-white p-4 overflow-y-auto">
        <h2 className="text-lg font-semibold mb-4">Componentes</h2>
        
        {/* Filtro por categoría */}
        <div className="mb-4">
          <select className="w-full bg-slate-800 rounded px-3 py-2 text-sm">
            <option value="all">Todos</option>
            <option value="ui">UI Base</option>
            <option value="sections">Secciones</option>
            <option value="layout">Layout</option>
          </select>
        </div>

        {/* Lista */}
        <ul className="space-y-1">
          {Object.entries(COMPONENT_REGISTRY).map(([key, comp]) => (
            <li key={key}>
              <button
                onClick={() => setSelectedComponent(comp)}
                className={`w-full text-left px-3 py-2 rounded text-sm hover:bg-slate-800 ${
                  selectedComponent?.id === comp.id ? 'bg-slate-700' : ''
                }`}
              >
                <span className="mr-2">{comp.icon}</span>
                {comp.name}
                {comp.plan && (
                  <span className="ml-2 text-xs bg-yellow-600 px-1 rounded">
                    {comp.plan}
                  </span>
                )}
              </button>
            </li>
          ))}
        </ul>
      </aside>

      {/* Main content */}
      <main className="flex-1 flex flex-col">
        {/* Toolbar */}
        <div className="h-14 bg-white border-b flex items-center px-4 gap-4">
          {/* Viewport selector */}
          <div className="flex gap-1 bg-slate-100 p-1 rounded">
            {['desktop', 'tablet', 'mobile'].map((v) => (
              <button
                key={v}
                onClick={() => setViewport(v)}
                className={`px-3 py-1 rounded text-sm ${
                  viewport === v ? 'bg-white shadow' : ''
                }`}
              >
                {v === 'desktop' ? '🖥️' : v === 'tablet' ? '📱' : '📲'}
              </button>
            ))}
          </div>

          {/* Load JSON */}
          <label className="cursor-pointer px-3 py-1 bg-slate-100 rounded text-sm hover:bg-slate-200">
            📁 Cargar JSON
            <input
              type="file"
              accept=".json"
              className="hidden"
              onChange={(e) => handleLoadJSON(e.target.files[0])}
            />
          </label>

          {/* Reset */}
          <button 
            onClick={() => setLocalData(selectedComponent?.defaultData || {})}
            className="px-3 py-1 bg-slate-100 rounded text-sm hover:bg-slate-200"
          >
            🔄 Reset Data
          </button>
        </div>

        {/* Content area */}
        <div className="flex-1 flex">
          {/* Preview */}
          <div className="flex-1 p-4 bg-slate-100">
            {selectedComponent ? (
              <ResponsiveFrame viewport={viewport}>
                <selectedComponent.component {...localData} />
              </ResponsiveFrame>
            ) : (
              <div className="h-full flex items-center justify-center text-slate-400">
                Seleccioná un componente
              </div>
            )}
          </div>

          {/* Data editor */}
          <div className="w-96 border-l bg-white overflow-hidden flex flex-col">
            <div className="p-3 border-b font-medium">📝 Data Editor</div>
            <DataEditor
              data={localData}
              schema={selectedComponent?.schema}
              onChange={handleDataChange}
            />
          </div>
        </div>
      </main>
    </div>
  );
}
```

---

## 🤖 Sistema de IA y Prompts

### Estructura de Prompts

```markdown
<!-- src/ai/prompts/template.prompt.md -->
# Prompt: Generar Template Completo

## Instrucciones

Sos un generador de templates para NovaVision, una plataforma de e-commerce multi-tenant.

### Stack Obligatorio
- React 18 + Vite (JavaScript/TypeScript)
- Tailwind CSS (NO styled-components)
- framer-motion para animaciones
- react-icons (opcional)

### Estructura de Carpetas
```
templates/{nombre}/
├── v1.0.0/
│   ├── pages/
│   │   └── Home/
│   │       └── index.jsx
│   ├── components/
│   │   ├── Header/
│   │   ├── ProductCard/
│   │   ├── ...
│   ├── theme.ts        # Tailwind extend config
│   └── metadata.ts     # Info del template
```

### Contrato de Data
El template recibe `homeData` con esta estructura exacta:
```json
{SCHEMA_PLACEHOLDER}
```

### Variables CSS Obligatorias
Usar siempre `var(--nv-*)`:
- `--nv-primary`, `--nv-primary-fg`
- `--nv-secondary`, `--nv-secondary-fg`
- `--nv-accent`
- `--nv-bg`, `--nv-surface`
- `--nv-text`, `--nv-muted`
- `--nv-border`

### Reglas de Diseño
1. 100% responsive (mobile-first)
2. Accesible (alt en imágenes, focus visible, semántica)
3. Animaciones sutiles con framer-motion
4. NO hardcodear colores, todo con CSS variables

### Componentes Requeridos
- Header (con logo, nav, iconos búsqueda/carrito)
- BannerHome (carousel responsive)
- ProductCarousel (con ProductCard)
- ServicesContent
- Faqs (accordion)
- ContactSection
- Footer
- ToTopButton

### Output Esperado
Generá todos los archivos listados arriba. Cada componente en su carpeta con index.jsx.

---

## Input del Usuario

**Tipo de negocio:** {BUSINESS_TYPE}
**Estilo visual:** {VISUAL_STYLE}
**Paleta sugerida:** {PALETTE}
**Features especiales:** {FEATURES}
```

### Prompt Builder

```typescript
// src/ai/generators/PromptBuilder.ts
import templatePrompt from '../prompts/template.prompt.md?raw';
import sectionPrompt from '../prompts/section.prompt.md?raw';
import componentPrompt from '../prompts/component.prompt.md?raw';
import { HomeDataSchema } from '../../core/schemas/homeData.schema';
import { zodToJsonSchema } from 'zod-to-json-schema';

interface PromptParams {
  type: 'template' | 'section' | 'component';
  businessType?: string;
  visualStyle?: string;
  palette?: string;
  features?: string[];
  componentName?: string;
  sectionType?: string;
}

export class PromptBuilder {
  private schema: string;

  constructor() {
    // Generar JSON Schema desde Zod
    const jsonSchema = zodToJsonSchema(HomeDataSchema, 'HomeData');
    this.schema = JSON.stringify(jsonSchema, null, 2);
  }

  build(params: PromptParams): string {
    let basePrompt = '';

    switch (params.type) {
      case 'template':
        basePrompt = templatePrompt;
        break;
      case 'section':
        basePrompt = sectionPrompt;
        break;
      case 'component':
        basePrompt = componentPrompt;
        break;
    }

    // Reemplazar placeholders
    let prompt = basePrompt
      .replace('{SCHEMA_PLACEHOLDER}', this.schema)
      .replace('{BUSINESS_TYPE}', params.businessType || '[A completar]')
      .replace('{VISUAL_STYLE}', params.visualStyle || '[A completar]')
      .replace('{PALETTE}', params.palette || '[A completar]')
      .replace('{FEATURES}', params.features?.join(', ') || '[A completar]');

    return prompt;
  }

  // Generar prompt listo para copiar a Magic Patterns
  buildForMagicPatterns(params: PromptParams): string {
    const base = this.build(params);
    
    // Agregar instrucciones específicas para Magic Patterns
    return `${base}

---
## Notas para Magic Patterns
- Usar clases de Tailwind directamente
- Exportar componente como default
- Incluir PropTypes o TypeScript types
- Comentarios breves explicando decisiones de diseño
`;
  }
}
```

---

## 🔍 Sistema de Auditoría

### Auditor Multi-tenant

```typescript
// src/ai/auditors/MultiTenantAuditor.ts
import { parse } from '@babel/parser';
import traverse from '@babel/traverse';

interface AuditResult {
  passed: boolean;
  issues: AuditIssue[];
  warnings: AuditWarning[];
}

interface AuditIssue {
  type: 'error' | 'warning';
  message: string;
  file: string;
  line?: number;
  suggestion?: string;
}

interface AuditWarning {
  message: string;
  file: string;
}

export class MultiTenantAuditor {
  audit(code: string, filename: string): AuditResult {
    const result: AuditResult = {
      passed: true,
      issues: [],
      warnings: [],
    };

    const ast = parse(code, {
      sourceType: 'module',
      plugins: ['jsx', 'typescript'],
    });

    traverse(ast, {
      // Verificar que queries usen client_id
      CallExpression: (path) => {
        const callee = path.node.callee;
        
        // Detectar llamadas a supabase sin filtro de client_id
        if (this.isSupabaseQuery(path)) {
          if (!this.hasClientIdFilter(path)) {
            result.issues.push({
              type: 'error',
              message: 'Query a Supabase sin filtro client_id',
              file: filename,
              line: path.node.loc?.start.line,
              suggestion: 'Agregar .eq("client_id", clientId) al query',
            });
            result.passed = false;
          }
        }

        // Detectar fetch sin header x-client-id
        if (this.isFetchCall(path)) {
          if (!this.hasClientIdHeader(path)) {
            result.warnings.push({
              message: 'fetch() sin header x-client-id',
              file: filename,
            });
          }
        }
      },

      // Verificar que no haya localStorage directo
      MemberExpression: (path) => {
        if (this.isLocalStorageAccess(path)) {
          result.warnings.push({
            message: 'Uso directo de localStorage (usar scopedStorage)',
            file: filename,
          });
        }
      },
    });

    return result;
  }

  private isSupabaseQuery(path: any): boolean {
    // Detectar patrones como supabase.from('table').select()
    const code = path.toString();
    return code.includes('.from(') && 
           (code.includes('.select(') || code.includes('.insert(') || 
            code.includes('.update(') || code.includes('.delete('));
  }

  private hasClientIdFilter(path: any): boolean {
    const code = path.toString();
    return code.includes('client_id') || code.includes('clientId');
  }

  private isFetchCall(path: any): boolean {
    const callee = path.node.callee;
    return callee.name === 'fetch' || 
           (callee.type === 'MemberExpression' && 
            callee.property?.name === 'fetch');
  }

  private hasClientIdHeader(path: any): boolean {
    const code = path.toString();
    return code.includes('x-client-id') || code.includes('X-Client-Id');
  }

  private isLocalStorageAccess(path: any): boolean {
    const obj = path.node.object;
    return obj?.name === 'localStorage' || 
           (obj?.type === 'MemberExpression' && 
            obj?.property?.name === 'localStorage');
  }
}
```

### Auditor de Estilos

```typescript
// src/ai/auditors/StyleAuditor.ts
export class StyleAuditor {
  audit(code: string, filename: string): AuditResult {
    const result: AuditResult = {
      passed: true,
      issues: [],
      warnings: [],
    };

    // Detectar colores hardcodeados
    const hardcodedColors = this.findHardcodedColors(code);
    if (hardcodedColors.length > 0) {
      hardcodedColors.forEach(match => {
        result.issues.push({
          type: 'warning',
          message: `Color hardcodeado: ${match.color}`,
          file: filename,
          line: match.line,
          suggestion: 'Usar var(--nv-*) en su lugar',
        });
      });
    }

    // Verificar uso de styled-components (deprecado)
    if (code.includes('styled-components') || code.includes('styled.')) {
      result.issues.push({
        type: 'error',
        message: 'styled-components está deprecado',
        file: filename,
        suggestion: 'Migrar a Tailwind CSS',
      });
      result.passed = false;
    }

    // Verificar que use CSS variables --nv-*
    if (!code.includes('var(--nv-') && this.hasStyleCode(code)) {
      result.warnings.push({
        message: 'No usa CSS variables --nv-*',
        file: filename,
      });
    }

    return result;
  }

  private findHardcodedColors(code: string): Array<{color: string, line: number}> {
    const results: Array<{color: string, line: number}> = [];
    const lines = code.split('\n');
    
    // Patrones de colores hardcodeados
    const patterns = [
      /#[0-9A-Fa-f]{3,8}\b/g,           // Hex colors
      /rgb\([^)]+\)/gi,                  // rgb()
      /rgba\([^)]+\)/gi,                 // rgba()
      /hsl\([^)]+\)/gi,                  // hsl()
    ];

    lines.forEach((line, i) => {
      // Ignorar comentarios y var(--nv-*)
      if (line.trim().startsWith('//') || line.includes('var(--nv-')) {
        return;
      }

      patterns.forEach(pattern => {
        const matches = line.match(pattern);
        if (matches) {
          matches.forEach(color => {
            results.push({ color, line: i + 1 });
          });
        }
      });
    });

    return results;
  }

  private hasStyleCode(code: string): boolean {
    return code.includes('className=') || 
           code.includes('style=') || 
           code.includes('css`');
  }
}
```

---

## 🚦 Staging Area

### Flujo de Staging

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Código         │     │  Staging        │     │  Commit         │
│  Generado       │ ──► │  Area           │ ──► │  (PR)           │
│  (IA/Manual)    │     │  (Review)       │     │                 │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        │                       │                       │
        │                       ▼                       │
        │               ┌─────────────┐                 │
        │               │  Auditoría  │                 │
        │               │  Automática │                 │
        │               └─────────────┘                 │
        │                       │                       │
        │                       ▼                       │
        │               ┌─────────────┐                 │
        └──────────────►│  Rechazado  │◄────────────────┘
                        │  (Fix)      │
                        └─────────────┘
```

### Componente de Staging

```jsx
// src/__dev/pages/StagingPage/index.jsx
import { useState, useEffect } from 'react';
import { CodeEditor } from '../../components/CodeEditor';
import { AuditPanel } from '../../components/AuditPanel';
import { runAllAuditors } from '../../../ai/auditors';

export default function StagingPage() {
  const [stagedItems, setStagedItems] = useState([]);
  const [selectedItem, setSelectedItem] = useState(null);
  const [auditResults, setAuditResults] = useState(null);
  const [isAuditing, setIsAuditing] = useState(false);

  // Cargar items del staging (localStorage en dev)
  useEffect(() => {
    const stored = localStorage.getItem('__dev_staging');
    if (stored) {
      setStagedItems(JSON.parse(stored));
    }
  }, []);

  const handleAudit = async () => {
    if (!selectedItem) return;
    
    setIsAuditing(true);
    try {
      const results = await runAllAuditors(selectedItem.code, selectedItem.filename);
      setAuditResults(results);
    } finally {
      setIsAuditing(false);
    }
  };

  const handleApprove = () => {
    if (!selectedItem || !auditResults?.allPassed) return;
    
    // En un escenario real, esto crearía un commit o PR
    // Por ahora, solo copiamos al clipboard con instrucciones
    const instructions = `
## Código aprobado para commit

**Archivo:** ${selectedItem.filename}
**Auditoría:** Pasada ✅
**Fecha:** ${new Date().toISOString()}

### Código:
\`\`\`jsx
${selectedItem.code}
\`\`\`

### Pasos:
1. Crear archivo en la ruta indicada
2. Revisar imports
3. Commit con mensaje: "feat(${selectedItem.type}): add ${selectedItem.name}"
4. Push a develop
    `.trim();

    navigator.clipboard.writeText(instructions);
    alert('Instrucciones copiadas al clipboard');
  };

  const handleReject = (reason) => {
    // Mover a "rechazados" para fix
    const updated = stagedItems.map(item => 
      item.id === selectedItem.id 
        ? { ...item, status: 'rejected', rejectReason: reason }
        : item
    );
    setStagedItems(updated);
    localStorage.setItem('__dev_staging', JSON.stringify(updated));
  };

  return (
    <div className="flex h-screen">
      {/* Lista de items */}
      <aside className="w-72 bg-slate-900 text-white p-4 overflow-y-auto">
        <h2 className="text-lg font-semibold mb-4">📝 Staging Area</h2>
        
        {stagedItems.length === 0 ? (
          <p className="text-slate-400 text-sm">
            No hay items en staging. Generá código desde la sección de Prompts.
          </p>
        ) : (
          <ul className="space-y-2">
            {stagedItems.map(item => (
              <li 
                key={item.id}
                onClick={() => setSelectedItem(item)}
                className={`p-3 rounded cursor-pointer ${
                  selectedItem?.id === item.id ? 'bg-slate-700' : 'bg-slate-800 hover:bg-slate-700'
                }`}
              >
                <div className="flex items-center justify-between">
                  <span className="font-medium">{item.name}</span>
                  <span className={`text-xs px-2 py-1 rounded ${
                    item.status === 'pending' ? 'bg-yellow-600' :
                    item.status === 'approved' ? 'bg-green-600' :
                    item.status === 'rejected' ? 'bg-red-600' : ''
                  }`}>
                    {item.status}
                  </span>
                </div>
                <div className="text-xs text-slate-400 mt-1">
                  {item.type} • {item.filename}
                </div>
              </li>
            ))}
          </ul>
        )}
      </aside>

      {/* Editor y preview */}
      <main className="flex-1 flex flex-col">
        {selectedItem ? (
          <>
            {/* Toolbar */}
            <div className="h-14 bg-white border-b flex items-center px-4 gap-4">
              <button
                onClick={handleAudit}
                disabled={isAuditing}
                className="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 disabled:opacity-50"
              >
                {isAuditing ? '⏳ Auditando...' : '🔍 Auditar'}
              </button>
              
              <button
                onClick={handleApprove}
                disabled={!auditResults?.allPassed}
                className="px-4 py-2 bg-green-600 text-white rounded hover:bg-green-700 disabled:opacity-50"
              >
                ✅ Aprobar
              </button>
              
              <button
                onClick={() => handleReject('Requiere revisión manual')}
                className="px-4 py-2 bg-red-600 text-white rounded hover:bg-red-700"
              >
                ❌ Rechazar
              </button>
            </div>

            {/* Content */}
            <div className="flex-1 flex">
              {/* Code editor */}
              <div className="flex-1 overflow-hidden">
                <CodeEditor
                  value={selectedItem.code}
                  language="jsx"
                  onChange={(code) => {
                    const updated = stagedItems.map(item =>
                      item.id === selectedItem.id ? { ...item, code } : item
                    );
                    setStagedItems(updated);
                    setSelectedItem({ ...selectedItem, code });
                  }}
                />
              </div>

              {/* Audit panel */}
              {auditResults && (
                <div className="w-80 border-l overflow-y-auto">
                  <AuditPanel results={auditResults} />
                </div>
              )}
            </div>
          </>
        ) : (
          <div className="flex-1 flex items-center justify-center text-slate-400">
            Seleccioná un item del staging
          </div>
        )}
      </main>
    </div>
  );
}
```

---

## 📱 Preview Responsive

### ResponsiveFrame Component

```jsx
// src/__dev/components/ResponsiveFrame/index.jsx
import { useState } from 'react';

const VIEWPORTS = {
  mobile: { width: 375, height: 667, label: '📲 Mobile' },
  tablet: { width: 768, height: 1024, label: '📱 Tablet' },
  desktop: { width: 1280, height: 800, label: '🖥️ Desktop' },
  wide: { width: 1920, height: 1080, label: '🖥️ Wide' },
};

export function ResponsiveFrame({ children, viewport = 'desktop' }) {
  const [zoom, setZoom] = useState(1);
  const config = VIEWPORTS[viewport];

  const containerStyle = {
    width: config.width * zoom,
    height: config.height * zoom,
    transform: `scale(${zoom})`,
    transformOrigin: 'top left',
  };

  return (
    <div className="flex flex-col h-full">
      {/* Controls */}
      <div className="flex items-center gap-4 p-2 bg-slate-200 rounded-t">
        <span className="text-sm font-medium">{config.label}</span>
        <span className="text-xs text-slate-500">
          {config.width} × {config.height}
        </span>
        
        {/* Zoom control */}
        <div className="flex items-center gap-2 ml-auto">
          <button 
            onClick={() => setZoom(z => Math.max(0.25, z - 0.25))}
            className="w-6 h-6 bg-white rounded text-sm"
          >
            −
          </button>
          <span className="text-xs w-12 text-center">{Math.round(zoom * 100)}%</span>
          <button 
            onClick={() => setZoom(z => Math.min(2, z + 0.25))}
            className="w-6 h-6 bg-white rounded text-sm"
          >
            +
          </button>
        </div>
      </div>

      {/* Frame */}
      <div className="flex-1 overflow-auto bg-slate-300 p-4">
        <div 
          className="bg-white shadow-xl mx-auto overflow-hidden"
          style={containerStyle}
        >
          {children}
        </div>
      </div>
    </div>
  );
}
```

---

## 🏷️ Versionado de Templates

### Manifest con Versiones

```typescript
// src/templates/manifest.ts
export interface TemplateVersion {
  version: string;
  releaseDate: string;
  changelog: string[];
  deprecated?: boolean;
}

export interface TemplateConfig {
  id: string;
  name: string;
  description: string;
  category: 'ecommerce' | 'services' | 'portfolio' | 'landing';
  status: 'stable' | 'beta' | 'deprecated';
  plan?: 'basic' | 'pro' | 'enterprise'; // null = disponible para todos
  preview: string;
  features: string[];
  versions: TemplateVersion[];
  currentVersion: string;
}

export const TEMPLATES: Record<string, TemplateConfig> = {
  classic: {
    id: 'classic',
    name: 'Classic Store',
    description: 'Template clásico para tiendas online tradicionales',
    category: 'ecommerce',
    status: 'stable',
    plan: null, // Disponible para todos
    preview: '/previews/classic.png',
    features: ['header-sticky', 'banner-carousel', 'product-grid', 'faq-section'],
    versions: [
      {
        version: '1.0.0',
        releaseDate: '2025-06-01',
        changelog: ['Versión inicial'],
      },
      {
        version: '1.1.0',
        releaseDate: '2025-09-15',
        changelog: ['Migración a Tailwind', 'Mejoras de accesibilidad'],
      },
    ],
    currentVersion: '1.1.0',
  },

  modern: {
    id: 'modern',
    name: 'Modern Grid',
    description: 'Diseño moderno con grid masonry y animaciones',
    category: 'ecommerce',
    status: 'stable',
    plan: null,
    preview: '/previews/modern.png',
    features: ['masonry-grid', 'infinite-scroll', 'parallax'],
    versions: [
      {
        version: '1.0.0',
        releaseDate: '2025-07-01',
        changelog: ['Versión inicial'],
      },
    ],
    currentVersion: '1.0.0',
  },

  boutique: {
    id: 'boutique',
    name: 'Boutique Premium',
    description: 'Template elegante para marcas de lujo',
    category: 'ecommerce',
    status: 'stable',
    plan: 'pro', // Solo plan Pro
    preview: '/previews/boutique.png',
    features: ['full-screen-hero', 'video-backgrounds', 'luxury-typography'],
    versions: [
      {
        version: '1.0.0',
        releaseDate: '2025-10-01',
        changelog: ['Versión inicial'],
      },
    ],
    currentVersion: '1.0.0',
  },

  bold: {
    id: 'bold',
    name: 'Bold & Vibrant',
    description: 'Colores vibrantes y tipografía grande',
    category: 'ecommerce',
    status: 'beta',
    plan: null,
    preview: '/previews/bold.png',
    features: ['bold-typography', 'gradient-backgrounds', 'animations'],
    versions: [
      {
        version: '0.9.0',
        releaseDate: '2026-01-15',
        changelog: ['Beta inicial'],
      },
    ],
    currentVersion: '0.9.0',
  },
};

// Helpers
export function getTemplate(id: string): TemplateConfig | undefined {
  return TEMPLATES[id];
}

export function getTemplatesByPlan(plan: string | null): TemplateConfig[] {
  return Object.values(TEMPLATES).filter(t => 
    t.plan === null || t.plan === plan
  );
}

export function getLatestVersion(templateId: string): string {
  return TEMPLATES[templateId]?.currentVersion || '1.0.0';
}
```

---

## 👥 Clientes Demo

### Sistema de Clientes Demo

```typescript
// src/core/constants/demoClients.ts
export interface DemoClient {
  id: string;
  name: string;
  slug: string;
  description: string;
  template: string;
  theme: string;
  isDemo: true;
}

export const DEMO_CLIENTS: DemoClient[] = [
  {
    id: 'demo-client-1',
    name: 'Demo Tienda Ropa',
    slug: 'demo-ropa',
    description: 'Cliente demo para probar templates de indumentaria',
    template: 'modern',
    theme: 'default',
    isDemo: true,
  },
  {
    id: 'demo-client-2',
    name: 'Demo Tienda Tech',
    slug: 'demo-tech',
    description: 'Cliente demo para probar templates de tecnología',
    template: 'classic',
    theme: 'dark',
    isDemo: true,
  },
];

export function isDemoClient(clientId: string): boolean {
  return DEMO_CLIENTS.some(c => c.id === clientId);
}

export function getDemoClients(): DemoClient[] {
  return DEMO_CLIENTS;
}
```

---

## 🗓️ Plan de Implementación

### Sprint 1: Fundamentos (2 semanas)

| Día | Tarea | Archivos |
|-----|-------|----------|
| 1-2 | Crear rama `develop` en Web | Git |
| 3-4 | Estructura de carpetas `__dev/`, `core/`, `ai/` | Folders |
| 5-6 | Schemas Zod + validador | `core/schemas/*.ts` |
| 7-8 | Dev Portal shell (router + layout) | `__dev/DevPortalApp.jsx` |
| 9-10 | Index Page con guía | `__dev/pages/IndexPage/` |

### Sprint 2: Playground (2 semanas)

| Día | Tarea | Archivos |
|-----|-------|----------|
| 1-3 | Component Registry | `core/constants/componentRegistry.ts` |
| 4-6 | Components Page + DataEditor | `__dev/pages/ComponentsPage/` |
| 7-8 | ResponsiveFrame | `__dev/components/ResponsiveFrame/` |
| 9-10 | Carga de JSON local | `__dev/hooks/useLocalData.js` |

### Sprint 3: IA y Prompts (2 semanas)

| Día | Tarea | Archivos |
|-----|-------|----------|
| 1-3 | Biblioteca de prompts | `ai/prompts/*.md` |
| 4-5 | PromptBuilder | `ai/generators/PromptBuilder.ts` |
| 6-8 | Prompts Page (viewer + copiar) | `__dev/pages/PromptsPage/` |
| 9-10 | Integración con Magic Patterns | Documentación |

### Sprint 4: Auditoría (2 semanas)

| Día | Tarea | Archivos |
|-----|-------|----------|
| 1-3 | MultiTenantAuditor | `ai/auditors/MultiTenantAuditor.ts` |
| 4-5 | StyleAuditor | `ai/auditors/StyleAuditor.ts` |
| 6-7 | SecurityAuditor | `ai/auditors/SecurityAuditor.ts` |
| 8-10 | Audit Page | `__dev/pages/AuditPage/` |

### Sprint 5: Staging y Versionado (2 semanas)

| Día | Tarea | Archivos |
|-----|-------|----------|
| 1-4 | Staging Page | `__dev/pages/StagingPage/` |
| 5-7 | Template manifest con versiones | `templates/manifest.ts` |
| 8-10 | Templates Page (selector + preview) | `__dev/pages/TemplatesPage/` |

### Sprint 6: Migración Tailwind (2+ semanas)

| Día | Tarea | Archivos |
|-----|-------|----------|
| 1-5 | Setup Tailwind + tokens | `theme/tailwind.config.js` |
| 6-10 | Migrar componentes UI base | `components/ui/*` |
| 11+ | Migrar templates uno por uno | `templates/*/` |

---

## 🔗 Dependencias Nuevas

```json
{
  "dependencies": {
    "zod": "^3.22.4",
    "zod-to-json-schema": "^3.22.4",
    "@monaco-editor/react": "^4.6.0"
  },
  "devDependencies": {
    "tailwindcss": "^3.4.0",
    "@tailwindcss/typography": "^0.5.10",
    "@babel/parser": "^7.23.0",
    "@babel/traverse": "^7.23.0"
  }
}
```

---

## ✅ Checklist Final

- [ ] Rama `develop` creada desde `feature/multitenant-storefront`
- [ ] Estructura de carpetas implementada
- [ ] Schemas Zod funcionando
- [ ] Dev Portal accesible en `/__dev`
- [ ] Playground de componentes operativo
- [ ] Biblioteca de prompts completa
- [ ] Auditoría automática integrada
- [ ] Staging area funcional
- [ ] Al menos 2 templates migrados a Tailwind
- [ ] CI configurado para `develop`
- [ ] Deploy preview en `dev.novavision.com` (o similar)

---

## 📚 Referencias

- [Zod Documentation](https://zod.dev/)
- [Tailwind CSS](https://tailwindcss.com/)
- [Magic Patterns](https://www.magicpatterns.com/)
- [Monaco Editor](https://microsoft.github.io/monaco-editor/)
