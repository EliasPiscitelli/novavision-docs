# Migración a Storage Multi-Cliente

## ⚠️ IMPORTANTE - LEER ANTES DE EJECUTAR

Esta migración implementa almacenamiento segmentado por cliente para aislar completamente los archivos media entre tenants. Es un cambio **CRÍTICO** que afecta:

- Estructura de carpetas en Supabase Storage
- Políticas RLS en `storage.objects`
- Código de backend para subida/acceso de archivos
- Referencias en base de datos

## Pre-requisitos

1. **Backup completo** de la base de datos y storage
2. **Acceso de service_role** a Supabase
3. **Entorno de staging** para pruebas
4. **Plan de rollback** preparado

## Pasos de Migración

### 1. Aplicar Políticas RLS de Storage

```bash
# En staging primero
psql -d $DATABASE_URL -f migrations/20251014_multiclient_storage.sql

# Verificar que las políticas se aplicaron
psql -d $DATABASE_URL -c "SELECT policyname FROM pg_policies WHERE schemaname='storage' AND tablename='objects';"
```

### 2. Ejecutar Migración de Archivos

```bash
# DRY RUN - Ver qué se migrará (SIEMPRE PRIMERO)
npm run migration:storage -- --dry-run

# Revisar el output detalladamente antes de continuar

# Ejecutar migración real en lotes pequeños
npm run migration:storage -- --execute --batch-size=25

# Para lotes más grandes (usar con cuidado)
npm run migration:storage -- --execute --batch-size=50
```

### 3. Verificar Migración

```bash
# Verificar estructura de archivos
psql -d $DATABASE_URL -c "
SELECT 
  split_part(name, '/', 1) as prefix,
  split_part(name, '/', 2) as client_id,
  split_part(name, '/', 3) as category,
  COUNT(*) as file_count
FROM storage.objects 
WHERE bucket_id = 'product-images' 
GROUP BY 1, 2, 3 
ORDER BY 1, 2, 3;
"

# Verificar que no hay archivos sin prefijo cliente
psql -d $DATABASE_URL -c "
SELECT COUNT(*) as legacy_files
FROM storage.objects 
WHERE bucket_id = 'product-images' 
AND name NOT LIKE 'clients/%';
"
```

### 4. Probar Endpoints

```bash
# Probar subida (debe usar nueva estructura)
curl -X POST http://localhost:3000/api/products/upload-image \
  -H "Authorization: Bearer $TOKEN" \
  -F "file=@test.jpg" \
  -F "clientId=test-client-id"

# Probar borrado masivo (dry run)
curl -X DELETE "http://localhost:3000/admin/media/clients/test-client-id?dryRun=true" \
  -H "Authorization: Bearer $ADMIN_TOKEN"
```

## Estructura Final Esperada

```
storage.objects (bucket: product-images)
├── clients/
│   ├── client-uuid-1/
│   │   ├── branding/
│   │   │   ├── logo/1697234567890.png
│   │   │   └── favicon/1697234567891.ico
│   │   ├── banners/
│   │   │   └── banner-id/
│   │   │       ├── desktop/1697234567892.jpg
│   │   │       └── mobile/1697234567893.jpg
│   │   ├── products/
│   │   │   └── product-id/
│   │   │       ├── original/1697234567894.jpg
│   │   │       ├── thumb/1697234567895.jpg
│   │   │       └── medium/1697234567896.jpg
│   │   └── services/
│   │       └── service-id/1697234567897.png
│   └── client-uuid-2/
│       └── ... (misma estructura)
└── (archivos legacy sin prefijo - para limpieza posterior)
```

## Monitoreo Post-Migración

### Logs a revisar

```bash
# Errores de storage en logs de aplicación
grep -i "STORAGE.*ERROR" /var/log/app.log

# Políticas RLS bloqueando accesos legítimos
grep -i "policy.*denied\|rls.*denied" /var/log/postgresql.log
```

### Métricas importantes

- Latencia de subida/descarga de archivos
- Errores 403 (posibles problemas de RLS)
- Archivos huérfanos sin referencias en BD
- Uso de storage por cliente

## Rollback de Emergencia

⚠️ **Solo en caso de problemas críticos**

```sql
-- 1. Deshabilitar RLS temporalmente
ALTER TABLE storage.objects DISABLE ROW LEVEL SECURITY;

-- 2. Crear política temporal permisiva
CREATE POLICY temp_permissive_policy ON storage.objects
FOR ALL TO authenticated
USING (true) WITH CHECK (true);

-- 3. Revertir a estructura anterior
-- (Requiere script de rollback específico - NO incluido)
```

## Validación de Éxito

✅ **La migración es exitosa cuando:**

1. Todos los archivos nuevos se guardan bajo `clients/{client_id}/`
2. Usuarios solo pueden acceder a archivos de su cliente
3. No hay errores de RLS en logs
4. Endpoints de admin funcionan correctamente
5. Frontend renderiza imágenes sin problemas

## Problemas Comunes

### Error: "Policy denied"
- **Causa**: JWT no contiene `client_id` o es incorrecto
- **Solución**: Verificar configuración de auth y JWT

### Error: "Bucket not found"
- **Causa**: Bucket `product-images` no existe o no tiene permisos
- **Solución**: Verificar configuración de Supabase Storage

### Archivos no se migran
- **Causa**: Paths en BD no coinciden con estructura real
- **Solución**: Revisar script de migración y paths en BD

### Performance degradada
- **Causa**: Políticas RLS muy complejas o índices faltantes
- **Solución**: Optimizar políticas o agregar índices específicos

## Contacto de Soporte

En caso de problemas críticos durante la migración:

1. **STOP** la migración inmediatamente
2. Implementar rollback si es necesario
3. Documentar el problema específico
4. Revisar logs detalladamente

---

**Recuerda**: Esta es una migración de una sola vía. Una vez aplicada y los archivos legacy eliminados, no hay vuelta atrás sin backup.