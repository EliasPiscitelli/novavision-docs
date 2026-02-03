# Implementación Frontend para NovaVision

Este documento contiene instrucciones para implementar los cambios en el frontend para alinearse con las mejoras realizadas en el backend.

## Mejoras implementadas

1. **Soporte para ETags**
   - Optimización de peticiones mediante If-None-Match
   - Caché local para respuestas no modificadas (304)
   - Reducción de transferencia de datos

2. **Manejo de Rate Limiting**
   - Detección y manejo de respuestas 429
   - Backoff exponencial con jitter para reintentos
   - Uso de headers retry-after o campos retry_after_ms

3. **Polling inteligente para pagos**
   - Secuencia de delays con backoff exponencial
   - Cancelación temprana cuando se alcanza un estado final
   - Manejo adecuado de ETags para no saturar el backend

4. **Optimización de imágenes**
   - Soporte para múltiples variantes (thumbnail, small, medium, large)
   - Fallback automático a otras variantes o imagen original
   - Carga progresiva y manejo de errores

5. **Seguridad de tenant**
   - Obtención consistente de client_id desde múltiples fuentes
   - Headers de autenticación unificados
   - Prevención de cross-tenant data access

## Estructura de archivos

```
src/
├── api/
│   ├── index.js               # API centralizada con todas las utilidades
│   ├── mercadopagoEnhanced.js # API mejorada para Mercado Pago
│   ├── ordersEnhanced.js      # API mejorada para órdenes
│   └── paymentsEnhanced.js    # API mejorada para pagos
├── components/
│   ├── OptimizedImage.jsx     # Componente para imágenes optimizadas con variantes
│   ├── PaymentStatusMonitor.jsx # Componente para monitorear estado de pagos
│   └── RateLimitError.jsx     # Componente para errores de rate limiting
├── pages/
│   ├── PaymentProcessPage.jsx # Ejemplo de página para procesar pagos
│   └── PaymentProcessPage.css # Estilos para la página de proceso
└── utils/
    ├── fetchWithRateLimitAndEtag.js # Utilidad para fetch con rate limit y ETags
    └── useApiWithRateLimit.jsx      # Hooks de React para la API mejorada
```

## Cómo utilizar la API mejorada

### 1. Para peticiones simples con soporte de ETag

```javascript
import { fetchWithETag } from '../utils/fetchWithRateLimitAndEtag';

// Ejemplo de uso
async function getDataWithEtag() {
  const response = await fetchWithETag('/api/data', {
    headers: { /* headers adicionales */ }
  });
  
  if (response.fromCache) {
    console.log('Datos obtenidos desde la caché local');
  }
  
  return response.data;
}
```

### 2. Para peticiones con React Hooks

```javascript
import { useFetchWithETag } from '../utils/useApiWithRateLimit';

function MyComponent() {
  const { data, loading, error, fromCache, reload } = useFetchWithETag(
    '/api/data',
    { immediate: true, useCache: true }
  );
  
  return (
    <div>
      {loading && <p>Cargando...</p>}
      {error && <p>Error: {error}</p>}
      {data && <div>Datos: {JSON.stringify(data)}</div>}
      {fromCache && <p>Datos obtenidos desde caché</p>}
      <button onClick={reload}>Recargar</button>
    </div>
  );
}
```

### 3. Para polling con backoff exponencial

```javascript
import { usePolling } from '../utils/useApiWithRateLimit';

function PaymentStatus({ orderId }) {
  const { data, loading, error, isComplete } = usePolling(
    `/orders/status/${orderId}`,
    {
      autoStart: true,
      shouldContinue: (data) => {
        // Continuar hasta que el estado sea final
        return !['approved', 'rejected', 'cancelled'].includes(data?.status);
      }
    }
  );
  
  return (
    <div>
      {loading && <p>Consultando estado...</p>}
      {data && <p>Estado: {data.status}</p>}
      {isComplete && <p>Proceso finalizado</p>}
    </div>
  );
}
```

### 4. Para imágenes optimizadas

```javascript
import OptimizedImage from '../components/OptimizedImage';

function ProductCard({ product }) {
  return (
    <div className="product-card">
      <OptimizedImage
        src={product.imageUrl}
        alt={product.name}
        size="medium"
        variants={product.imageVariants}
        onError={() => console.log('Error cargando la imagen')}
      />
      <h3>{product.name}</h3>
    </div>
  );
}
```

## Integración con el backend actualizado

### 1. Manejo de Rate Limiting

El backend ahora envía:
- Status code 429 cuando se excede el límite
- Header `Retry-After` (segundos) o campo `retry_after_ms` (milisegundos)
- Un período de espera recomendado

La implementación frontend:
- Detecta automáticamente respuestas 429
- Espera el tiempo indicado antes de reintentar
- Muestra un mensaje de error con countdown al usuario
- Aplica jitter para evitar thundering herd

### 2. Soporte para ETags

El backend ahora envía:
- Header `ETag` con cada respuesta
- Respuestas 304 (Not Modified) cuando corresponde

La implementación frontend:
- Guarda ETags en localStorage para cada URL
- Envía header `If-None-Match` con peticiones
- Utiliza la caché local cuando recibe 304
- Actualiza la caché cuando cambia el ETag

### 3. Seguridad de Tenant

El backend ahora verifica:
- Header `x-client-id` para accesos específicos de tenant
- Ownership de órdenes y recursos

La implementación frontend:
- Incluye consistentemente el header `x-client-id`
- Obtiene el client_id de múltiples fuentes posibles
- Asegura que cada petición incluya el tenant correcto

## Consideraciones para implementación

1. **Refactorización incremental**: Puedes migrar gradualmente utilizando primero los hooks y utilidades sin cambiar los servicios existentes.

2. **Compatibilidad**: Las nuevas implementaciones son compatibles con la estructura actual, facilitando una migración progresiva.

3. **Pruebas**: Asegúrate de probar minuciosamente el manejo de rate limit y los escenarios de caché.

4. **Monitoreo**: Implementa logging para detectar problemas con rate limiting o ETags.

5. **Fallbacks**: Todas las utilidades incluyen mecanismos de fallback cuando no se pueden usar caché o ETags.