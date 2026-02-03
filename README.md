# NovaVision Documentation

Repositorio central de documentación, reglas, arquitectura y registro de cambios del sistema NovaVision.

## Estructura

```
novavision-docs/
├── architecture/     ← Documentación de arquitectura del sistema
├── rules/            ← Reglas fijas y convenciones
├── changes/          ← Log de cambios por sesión (IA + manual)
├── analysis/         ← Auditorías, análisis de sistema
└── cleanup/          ← Planes de cleanup y mejoras
```

## Repositorios del Sistema

| Repo | Descripción | Deploy |
|------|-------------|--------|
| [templatetwobe](https://github.com/EliasPiscitelli/templatetwobe) | API NestJS | Railway |
| [novavision](https://github.com/EliasPiscitelli/novavision) | Admin Dashboard (React) | Netlify |
| [templatetwo](https://github.com/EliasPiscitelli/templatetwo) | Web Storefront (React) | Netlify |

## Convenciones

### Registro de Cambios

Cada sesión de trabajo (IA o manual) debe documentarse en `changes/` con el formato:

```
changes/YYYY-MM-DD_descripcion-breve.md
```

Contenido mínimo:
- Fecha y autor (humano o agente IA)
- Repos afectados
- Cambios realizados
- Archivos modificados
- Razón del cambio

### Reglas

Las reglas en `rules/` son inmutables y deben respetarse en todo cambio:
- Estructura de repos (independientes, no monorepo)
- Convenciones de código por repo
- Flujos de deploy

---

*Última actualización: 2026-02-03*
