# Caché Diferenciado y Validación de Precios en Carrito

- **Fecha**: 2025-02-05
- **Autor**: Copilot Agent
- **Rama API**: develop (templatetwobe)
- **Rama Web**: develop (templatetwo)

## Archivos Modificados

### Backend (templatetwobe)

1. **src/cart/dto/add-cart-item.dto.ts**
   - Agregado campo opcional `expectedPrice`: precio que el usuario ve en el catálogo
   - Se usa para detectar discrepancias con el precio real

2. **src/cart/cart.controller.ts**
   - Pasaje de `expectedPrice` al servicio
   - Log mejorado incluyendo el precio esperado

3. **src/cart/cart.service.ts**
   - Nueva lógica para calcular precio actual del producto
   - Detección de cambio de precio (tolerancia de 0.01 para evitar falsos positivos por redondeo)
   - Retorna `priceInfo` con: `priceChanged`, `expectedPrice`, `currentPrice`, `priceDifference`, `productName`

### Frontend (templatetwo)

1. **src/hooks/cart/useCartItems.js**
   - `addItem` ahora envía `expectedPrice` al backend
   - Si el backend detecta cambio de precio, muestra un toast al usuario
   - Formato amigable: "El precio de 'X' aumentó/disminuyó $Y"

2. **src/services/homeData/useFetchHomeData.base.jsx**
   - **Caché diferenciado**:
     - Datos estáticos (banners, contacto, social, faqs, theme): 10 minutos
     - Datos dinámicos (productos, categorías): 2 minutos
   - Nueva función `refetch()` para forzar actualización
   - Claves de caché separadas: `homeDataCache:static:*` y `homeDataCache:products:*`

3. **src/context/CartProvider.jsx**
   - Expuesto `refreshCart` para revalidar el carrito

4. **src/pages/CartPage/index.jsx**
   - Al entrar al carrito, se llama `refreshCart()` automáticamente
   - Garantiza que los precios mostrados son los actuales del backend

## Resumen del Cambio

Implementación de una estrategia de caché inteligente que:

1. **Cachea datos estáticos por más tiempo** (10 min) para mejorar performance
2. **Cachea productos por menos tiempo** (2 min) para mantener precios actualizados
3. **Valida precios al agregar al carrito** - si el precio cambió, notifica al usuario
4. **Revalida al entrar al carrito** - siempre muestra precios actuales

## Por Qué se Hizo

El usuario solicitó:
- Mejorar tiempos de carga (más caché)
- Pero asegurar que los precios estén siempre actualizados
- Evitar la queja: "lo agregué a $100 pero en el carrito está $120"

Esta solución balancea ambos requerimientos:
- Datos que no cambian frecuentemente tienen caché largo
- Precios se validan siempre contra el backend al agregar al carrito
- El carrito siempre muestra precios frescos

## Cómo Probar

### Test de cambio de precio:

1. Levantar API y Web:
   ```bash
   # Terminal 1 (api)
   cd apps/api && npm run start:dev
   
   # Terminal 2 (web)
   cd apps/web && npm run dev
   ```

2. Abrir tienda en http://localhost:5173/?tenant=demo-store

3. Ver un producto y anotar su precio

4. En Supabase, cambiar el precio del producto (aumentar o disminuir)

5. Sin refrescar la página, agregar el producto al carrito

6. **Resultado esperado**: Toast mostrando "El precio de 'X' aumentó/disminuyó $Y"

### Test de caché diferenciado:

1. Navegar al home
2. Abrir DevTools > Application > Local Storage
3. Verificar que existen dos claves:
   - `homeDataCache:static:localhost`
   - `homeDataCache:products:localhost`
4. Verificar timestamps diferentes según TTL

### Test de refresh en carrito:

1. Agregar productos al carrito
2. En Supabase, cambiar el precio de un producto
3. Ir a la página del carrito
4. **Resultado esperado**: El precio mostrado es el nuevo (actualizado)

## Notas de Seguridad

- El precio final **siempre** lo determina el backend, no el frontend
- El `expectedPrice` es solo para UX (mostrar notificación)
- El backend valida stock y precios desde la DB en cada operación
- No hay forma de "engañar" al sistema enviando un precio bajo

## Impacto en Performance

- **Mejora**: Datos estáticos se cachean 5x más tiempo (10 min vs 2 min anterior)
- **Trade-off**: Productos siguen con TTL de 2 min para mantener precios frescos
- **Optimización**: Al entrar al carrito se hace 1 request en lugar de mostrar datos potencialmente obsoletos

## Riesgos y Rollback

- **Riesgo bajo**: Los cambios son aditivos y backward-compatible
- **Rollback**: Revertir los 4 archivos modificados
- Si hay problemas con el toast, se puede comentar la línea del `showToast` en `useCartItems.js`

## Queries de Verificación (Supabase)

```sql
-- Ver productos con precios para test
SELECT id, name, price, "discountedPrice", quantity 
FROM products 
WHERE client_id = 'tu-client-id' 
LIMIT 10;

-- Actualizar precio de un producto para test
UPDATE products 
SET "discountedPrice" = "discountedPrice" + 50 
WHERE id = 'id-producto';
```
