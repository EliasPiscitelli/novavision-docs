# 2026-03-19 — Template Unification: T3 ContactSection Unificado

## Repo: `@nv/web` (branch: `develop`)

## Resumen

Implementación del ticket T3: ContactSection unificado que reemplaza DynamicContactSection (T1-T5) + 3 implementaciones separadas (T6, T7, T8) con un único componente que usa lazy-loaded variants.

## Arquitectura

```
src/components/storefront/ContactSection/
├── index.tsx                  ← Entry point: normaliza datos + variant router
├── ContactInfoCard.tsx        ← Shared card con icon resolution (inline SVG)
├── SocialLinks.tsx            ← Shared social links + WhatsApp URL builder
├── ContactSectionSkeleton.tsx ← Skeleton de carga
└── variants/
    ├── Cards.tsx              ← T1-T3: cards grid + mapa opcional + social
    ├── TwoColumn.tsx          ← T4, T5, T8: split contact + mapa/social CTA
    └── Minimal.tsx            ← T6, T7: header + cards, sin mapa
```

## Decisiones de diseño

### Partial unification ya existente
A diferencia de ProductCard y FAQSection (8 implementaciones independientes), ContactSection ya tenía `DynamicContactSection` sirviendo T1-T5 vía SectionRenderer. Solo T6 (Drift), T7 (Vanguard) y T8 (Lumina) tenían componentes separados activos.

### Inline SVG icons
Reemplaza `react-icons/fi` (FiMapPin, FiPhone, FiMail, etc.) con SVGs inline tipo Feather. Esto elimina la dependencia de react-icons para los chunks de contacto.

### Keyword-based icon resolution
Merge de los keyword maps de T6, T7 y T8:
- `direc`, `address`, `ubica`, `local`, `mapa` → MapPin
- `tel`, `cel`, `phone`, `fono` → Phone
- `mail`, `email`, `correo` → Mail
- `hora`, `aten`, `lunes`, `time`, `horario` → Clock
- `whats`, `chat`, `mensaje` → MessageCircle
- Fallback → Info

### WhatsApp URL sanitization
T7 y DynamicContactSection strip non-digits del teléfono. T6 y T8 no lo hacían. El componente unificado siempre sanitiza: `phone.replace(/\D/g, '')`.

### Data normalization en entry point
SectionRenderer ya envía datos normalizados (4-layer merge, líneas 202-292), pero el componente añade:
- Resolución de 3 prop names: `info || contactInfo || infoCards`
- Soporte `titleinfo` vs `title` (T4 usa `title`)
- IDs estables cuando faltan
- Multi-key sort: `number → position → order → Infinity`
- Fallback desde props individuales (`address`, `phone`, etc.)

### Map embed sin framer-motion
Cards y TwoColumn soportan Google Maps embed vía `normalizeMapEmbedUrl()`. Sin preview mode handling por ahora (se puede agregar post-migration).

### Sin framer-motion, sin styled-components
Consistente con T1 y T2: puro inline CSSProperties + `var(--nv-*)` tokens.

## Problemas encontrados (del análisis)

| Issue | Descripción | Resolución |
|-------|------------|------------|
| T8 crash | `[...info].sort()` con `info` undefined | Guard con `Array.isArray` |
| T7 null return | Retorna null si no hay info ni social | Igual, pero con guard robusto |
| T6 DEFAULT_CONTACT | Fallback hardcodeado con datos demo | Eliminado — usa fallback props |
| Social fragmentation | DCS usa `react-icons/fa`, T6-T8 usan `/fi` | Inline SVGs unificados |
| WA phone no-sanitize | T6/T8 no strip non-digits del teléfono | Siempre `replace(/\D/g, '')` |
| titleinfo vs title | T4 usa `title` en vez de `titleinfo` | Soporta ambos con fallback |

## Archivos nuevos

| Archivo | Líneas | Propósito |
|---------|--------|-----------|
| `ContactSection/index.tsx` | 145 | Entry point + normalizer + variant router |
| `ContactSection/ContactInfoCard.tsx` | 150 | Card con icon resolution (inline SVG) |
| `ContactSection/SocialLinks.tsx` | 130 | Social links + WhatsApp URL builder |
| `ContactSection/ContactSectionSkeleton.tsx` | 55 | Skeleton de carga |
| `ContactSection/variants/Cards.tsx` | 115 | Variante cards (T1-T3) |
| `ContactSection/variants/TwoColumn.tsx` | 130 | Variante two-column (T4, T5, T8) |
| `ContactSection/variants/Minimal.tsx` | 80 | Variante minimal (T6, T7) |
| `src/__tests__/contact-section.test.ts` | 350 | 34 tests unitarios |

## Validación

- `typecheck`: 0 errores
- `build`: exitoso (6.42s)
- `test:unit`: 263/263 tests pasan (34 nuevos)
- `ensure-no-mocks`: OK
- `check:bundle`: todos los chunks dentro del budget

## Próximos pasos

- T4: Footer unificado
- T5: ServicesSection unificado
