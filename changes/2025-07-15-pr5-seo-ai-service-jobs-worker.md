# PR5: SEO AI Service + Jobs + Worker + Batch Execution

- **Autor:** agente-copilot
- **Fecha:** 2025-07-15
- **Rama API:** feature/automatic-multiclient-onboarding
- **Repos afectados:** API, Docs

---

## Resumen

Implementación completa del motor de generación SEO con IA (OpenAI gpt-4o-mini).  
Incluye: servicio de IA, sistema de jobs con cola, worker polling con chunks de 25,  
debito de créditos, audit log de cambios, y endpoints REST protegidos.

## Archivos creados/modificados

### API (templatetwobe)

**Nuevos:**
- `src/seo-ai/seo-ai.module.ts` — Módulo NestJS que registra controller, services y worker
- `src/seo-ai/seo-ai.service.ts` — Wrapper de OpenAI: gpt-4o-mini, JSON response format, retry con backoff
- `src/seo-ai/seo-ai-job.service.ts` — CRUD de jobs (seo_ai_jobs), guardrails (1 concurrent, 5/día), claim atómico CAS
- `src/seo-ai/seo-ai-worker.service.ts` — Worker con @Interval(10s), chunks de 25, debito créditos, audit log
- `src/seo-ai/seo-ai.controller.ts` — 5 endpoints: POST jobs, GET jobs, GET jobs/:id, GET jobs/:id/log, GET status
- `src/seo-ai/prompts/system.prompt.ts` — System prompt SEO + builder de entity prompt

**Modificados:**
- `src/app.module.ts` — Importa SeoAiModule, excluye rutas `seo-ai/*` del AuthMiddleware
- `package.json` — Agrega dependencia `openai`

### Docs (novavision-docs)

- `changes/2025-07-15-pr5-seo-ai-service-jobs-worker.md` — Este archivo

## Arquitectura

```
POST /seo-ai/jobs  →  SeoAiController  →  SeoAiJobService.createJob()
                                              ↓ (insert a seo_ai_jobs status=pending)
                                              
SeoAiWorkerService  ──@Interval(10s)──→  claimNextPending()  ──→  processJob()
  ↓                                                                    ↓
  chunks de 25 entities                                     SeoAiService.generateEntitySeo()
  ↓                                                                    ↓
  UPDATE products/categories SET seo_title, seo_description, seo_source='ai'
  ↓
  INSERT seo_ai_log (audit trail con diff)
  ↓
  SeoAiBillingService.addCredits(-N) ← debito por chunk
```

## Guardrails

| Guardrail | Valor |
|---|---|
| Max tokens por request | 500 |
| Title max chars | 65 |
| Description max chars | 160 |
| Rate limit por tenant/día | 5 jobs |
| Jobs simultáneos max | 1 por tenant |
| Chunk size | 25 items |
| Retry on failure | 2 retries con backoff exponencial |
| No pisar `seo_locked` | Check antes de fetch |
| OpenAI model | gpt-4o-mini |
| Temperature | 0.3 |
| Response format | json_object |

## Endpoints

| Método | Ruta | Guard | Descripción |
|--------|------|-------|-------------|
| POST | /seo-ai/jobs | ClientDashboardGuard | Crear job de generación SEO |
| GET | /seo-ai/jobs | ClientDashboardGuard | Listar jobs del tenant |
| GET | /seo-ai/jobs/:id | ClientDashboardGuard | Detalle de un job |
| GET | /seo-ai/jobs/:id/log | ClientDashboardGuard | Log de cambios del job |
| GET | /seo-ai/status | ClientDashboardGuard | Health check: AI configurado + balance |

## Variables de entorno

- `OPENAI_API_KEY` — **NUEVA** — API key de OpenAI. Configurar en Railway.
  - Sin esta key el worker no procesa jobs (safe degradation).

## Cómo probar

1. Configurar `OPENAI_API_KEY` en `.env`
2. Levantar API: `npm run start:dev`
3. Crear un job:
```bash
curl -X POST http://localhost:3000/seo-ai/jobs \
  -H "Authorization: Bearer <JWT>" \
  -H "Content-Type: application/json" \
  -d '{"job_type":"products","mode":"update_missing"}'
```
4. El worker lo toma en ≤10s, procesa en chunks, debita créditos
5. Ver progreso: `GET /seo-ai/jobs/<id>`
6. Ver log: `GET /seo-ai/jobs/<id>/log`

## Notas de seguridad

- OPENAI_API_KEY solo server-side, nunca expuesta al frontend
- Todos los endpoints protegidos por ClientDashboardGuard (Builder Token o Supabase JWT admin)
- Worker accede a DB con service_role (RLS bypass) — tablas seo_ai_jobs y seo_ai_log son service_role only
- Debito de créditos validado: si balance < chunk → job falla con mensaje claro
- OpenAI response se parsea y valida (trunca a 65/160 chars)

## Riesgos

- **OpenAI rate limits**: En producción con muchos tenants simultáneos, podría haber throttling. Mitigado por: solo 1 job activo por tenant, worker procesa 1 job a la vez.
- **Costs**: gpt-4o-mini es cost-effective (~$0.15/1M input tokens). Un producto típico usa ~200 tokens → ~$0.00003 por generación.
- **Fallback**: Si OPENAI_API_KEY no está configurada, el worker simplemente no arranca (safe degradation).
