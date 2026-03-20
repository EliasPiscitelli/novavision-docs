# T13 — Update database-first.md docs across all repos

**Fecha:** 2026-03-20
**Módulo:** Web + API + Admin (documentación `.claude/rules/`)
**Commits:** `782b54e` (web/develop) + `0c85e37` (api) + `13d988d` (admin)

## Problema

Los 3 archivos `database-first.md` estaban desactualizados — no incluían tablas creadas en migraciones de febrero-marzo 2026.

## Cambios

### Tablas nuevas agregadas (Backend DB)

| Grupo | Tablas | Migración origen |
|-------|--------|-----------------|
| Opciones de producto | `option_sets`, `option_set_items`, `size_guides` | `20260216_option_sets_tables.sql` |
| Q&A y reviews | `product_questions`, `product_reviews`, `product_review_aggregates` | `20260217_qa_reviews_tables.sql` |
| Biblioteca de imágenes | `tenant_media`, `product_media` | `20260316_create_tenant_media.sql` |
| Cola de uploads | `media_upload_batches`, `media_upload_jobs` | `20260316_create_media_upload_jobs.sql` |

### Columnas nuevas documentadas

- `products`: `option_mode`, `option_set_id`, `option_config`
- `cart_items`: `selected_options`, `options_hash`

### Archivos actualizados

| Archivo | Nivel de detalle |
|---------|-----------------|
| `apps/web/.claude/rules/database-first.md` | Completo — tabla expandida con 4 grupos nuevos |
| `apps/api/.claude/rules/database-first.md` | Completo — mismas adiciones |
| `apps/admin/.claude/rules/database-first.md` | Resumido — mención de los 3 grupos |

## Nota

Estos archivos son dev-only (`.claude/rules/`) — NO se cherry-pickean a ramas de producción. Solo afectan el contexto de los agentes de IA al trabajar en cada repo.
