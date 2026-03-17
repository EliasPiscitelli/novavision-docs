# NovaVision — Reporte de QA para Resolución de Issues
**Fecha de sesión QA:** 10/03/2026  
**Alcance:** Tenant Web Storefront (`@nv/web`) + Admin Dashboard (`@nv/admin`)  
**Tenant de prueba usado en QA:** `farma.novavision.lat`  
**Dispositivos evaluados:** Mobile (Samsung Galaxy S20 Ultra / Chrome) + Desktop  
**Rama a impactar:** `develop` → cherry-pick a `production`

---

## ⚠️ INSTRUCCIÓN GLOBAL PARA EL AGENTE

> **Todos los fixes deben ser template-agnósticos.**  
> Los issues fueron encontrados en el tenant `farma` (template `standard_blue` / `Lumina`), pero los componentes afectados son compartidos entre **todos** los templates disponibles (normal, first, Lumina, etc.) y todos los tenants.  
> Antes de cerrar cada fix, el agente debe verificar que:
> 1. El componente o estilo corregido está en el layer compartido (no hardcodeado al template farma).
> 2. Los demás templates renderizan correctamente el mismo componente.
> 3. El fix aplica tanto en mobile como en desktop salvo que se indique lo contrario.
> 4. El Admin Dashboard tiene siempre la misma UX/UI independientemente del template del tenant.

---

## ÍNDICE POR SECCIÓN

| # | Sección | Repo | Issues | Prioridad |
|---|---------|------|--------|-----------|
| 0 | General / Tutoriales | `@nv/admin` | 3 | ALTA |
| 1 | Productos — Storefront | `@nv/web` | 11 | ALTA |
| 2 | Productos — Admin Panel | `@nv/admin` | 9 | ALTA |
| 3 | Importación con IA | `@nv/admin` | 12 | ALTA |
| 4 | Órdenes — Admin Panel | `@nv/admin` | 4 | MEDIA |
| 5 | Pagos — Admin Panel | `@nv/admin` | 2 | ALTA |
| 6 | Envíos — Admin Panel | `@nv/admin` | 6 | ALTA |
| 7 | Cupones — Admin Panel | `@nv/admin` | 1 | BAJA |
| 8 | Opciones de Producto | `@nv/admin` | 3 | ALTA |
| 9 | Servicios — Storefront | `@nv/web` | 2 | MEDIA |
| 10 | Preguntas Frecuentes / Reviews | `@nv/web` | 1 | MEDIA |
| 11 | Banners — Storefront | `@nv/web` | 1 | MEDIA |
| 12 | SEO AI Autopilot | `@nv/admin` | 9 | MEDIA |
| 13 | Datos de Contacto | `@nv/admin` | 1 | MEDIA |
| 14 | Redes Sociales | `@nv/admin` | 1 | MEDIA |
| 15 | Diseño de Tienda (Addon Store) | `@nv/admin` | 1 | ALTA |

---

## 0. GENERAL / TUTORIALES

**Repo:** `@nv/admin`  
**Aplica a:** Todos los tenants / Todos los templates

---

### [GEN-01] Botones "Anterior" / "Siguiente" del tutorial con tipografía ilegible
**Dispositivo:** Mobile + Desktop  
**Descripción:** Los botones de navegación del tutorial de productos muestran un "marco" alrededor de cada letra, haciendo el texto ilegible. Parece un issue de font-rendering o de letter-spacing con border aplicado erróneamente.  
**Componente probable:** `TutorialNavButton` o similar en el sistema de tutoriales del admin.  
**Acción:** Revisar el estilo CSS de los botones `← Anterior` / `Siguiente →`. Verificar que no haya `border` o `outline` aplicado por carácter. Testear con todos los tutoriales del panel (productos, órdenes, envíos, pagos).

---

### [GEN-02] Flecha del tooltip de tutorial no visible
**Dispositivo:** Mobile + Desktop  
**Descripción:** La "flechita" que indica a qué elemento del UI apunta el tooltip del tutorial es blanca sobre fondo claro, haciéndola invisible. El usuario no puede saber a dónde apunta el tutorial.  
**Acción:** Cambiar el color de la flecha del tooltip a un color con suficiente contraste contra el fondo (dark o con outline). Revisar el componente de tooltip/popover del sistema de tutoriales. Verificar en todos los pasos de todos los tutoriales del admin.

---

### [GEN-03] Menú mobile — ítem "Pagos" desalineado (ícono y texto en columna en vez de fila)
**Dispositivo:** Mobile únicamente  
**Sección:** Storefront — Menú hamburguesa (lista de secciones de la página)  
**Descripción:** En el menú mobile de la tienda, el ítem "Pagos" muestra el ícono encima del texto (disposición en columna), mientras que todos los demás ítems muestran ícono + texto en fila horizontal.  
**Repo afectado:** `@nv/web`  
**Acción:** Verificar el componente de ítem de menú mobile en el storefront. El layout debe ser consistente: `flex-direction: row` con `align-items: center` para todos los ítems. Revisar si "Pagos" tiene un wrapper diferente o si el ícono de Pagos tiene dimensiones distintas que fuerzan el quiebre de línea. Aplicar fix al componente compartido — aplica a todos los templates.

---

## 1. PRODUCTOS — STOREFRONT (`@nv/web`)

**Aplica a:** Todos los tenants / Todos los templates de storefront

---

### [WEB-PROD-01] Tabla de productos mobile mal proporcionada (Admin embebido en Web)
**Dispositivo:** Mobile  
**Sección:** Admin Panel embebido, gestión de productos  
**Descripción:** La columna de "Acciones" ocupa demasiado espacio horizontal, comprimiendo el resto de las columnas (nombre, descripción, SKU, precio). El contenido queda ilegible.  
**Repo:** `@nv/admin`  
**Acción:** Revisar el componente de tabla de productos. En mobile, priorizar las columnas de datos y dar a "Acciones" un ancho fijo mínimo (o usar un menú de acciones colapsable). Alternativa recomendada: en mobile, usar una lista de cards en vez de tabla horizontal.

---

### [WEB-PROD-02] Filtro de precios se sale de la pantalla en mobile
**Dispositivo:** Mobile  
**Sección:** Storefront → Catálogo de productos → Dropdown de ordenamiento  
**Descripción:** Al abrir el dropdown de filtro de precios ("Precio: menor a mayor", "Precio: mayor a menor"), el menú se desborda hacia la derecha, saliendo del viewport.  
**Acción:** Agregar `max-width: 100vw` y `overflow: hidden` o `right: 0` al dropdown de filtros. Verificar en todos los templates.

---

### [WEB-PROD-03] Botones del catálogo de productos poco evidentes en la sección inicio (Mobile + Desktop)
**Dispositivo:** Mobile + Desktop  
**Sección:** Storefront → Inicio → Sección de productos  
**Descripción:** Los CTAs para ir al catálogo completo ("Ver catálogo completo" / "Ver todos los productos") son difíciles de encontrar. Los usuarios no los identifican fácilmente.  
**Acción:** Aumentar el contraste visual de los botones CTA del catálogo. Considerar hacerlos más prominentes (mayor tamaño, fondo de color primario del tenant, o añadir un ícono de flecha). El cambio debe respetar el tema del tenant via CSS variables. Aplica a todos los templates.

---

### [WEB-PROD-04] Banner "Buscá y encontrá el producto ideal" molesta en catálogo
**Dispositivo:** Mobile + Desktop  
**Sección:** Storefront → Catálogo de productos → Banner superior  
**Descripción:** El cartel azul fijo en la parte superior del catálogo de productos es intrusivo y obstruye la vista del contenido.  
**Acción:** Eliminar el banner o convertirlo en un elemento dismissible (con botón de cierre) que no reaparezca una vez cerrado (usar localStorage o sessionStorage). Verificar que la eliminación no rompa el layout en ningún template.

---

### [WEB-PROD-05a] Fotos del producto cortadas a la derecha en vista detalle (Mobile)
**Dispositivo:** Mobile  
**Sección:** Storefront → Catálogo → Producto individual  
**Descripción:** Las imágenes del carrusel de fotos del producto se cortan hacia la derecha. El ícono de navegación de la imagen siguiente tampoco es visible.  
**Acción:** Revisar el componente de galería de imágenes del producto. Aplicar `overflow: hidden` correctamente al contenedor del carrusel y asegurar que los botones de navegación estén posicionados dentro del contenedor visible. Aplica a todos los templates.

---

### [WEB-PROD-05b] Flecha fantasma en "También te puede interesar" (Mobile)
**Dispositivo:** Mobile  
**Sección:** Storefront → Producto individual → Sección "También te puede interesar"  
**Descripción:** Aparece una flecha de navegación (`<`) sobre la foto del producto en la sección de productos relacionados que no realiza ninguna acción al pulsarla.  
**Acción:** Identificar el componente de carrusel de productos relacionados. Remover o deshabilitar los botones de navegación si el carrusel no tiene suficientes items para navegar, o corregir el handler del evento. Verificar en todos los templates.

---

### [WEB-PROD-05c] En mobile, reordenar: título primero, imagen después en detalle de producto
**Dispositivo:** Mobile  
**Sección:** Storefront → Producto individual  
**Descripción:** En mobile, la imagen del producto aparece antes que el título. El usuario quiere ver primero el nombre del producto.  
**Acción:** En el breakpoint mobile (`max-width: 768px` o el que use el proyecto), modificar el order CSS del título y la galería de imágenes en el layout del detalle de producto. El título debe renderizarse antes de la imagen. Aplica a todos los templates.

---

### [WEB-PROD-06] Botón de filtros poco visible (muy claro) en catálogo
**Dispositivo:** Mobile + Desktop  
**Sección:** Storefront → Catálogo de productos  
**Descripción:** El botón/link de "Filtros" tiene muy poco contraste contra el fondo, haciéndolo casi invisible.  
**Acción:** Aumentar el contraste del botón de filtros. Usar el color de acento del tenant o un color de texto con suficiente ratio de contraste WCAG (mínimo 4.5:1). Aplica a todos los templates.

---

### [WEB-PROD-07] Al aplicar un filtro, no hace scroll al inicio de la lista de productos
**Dispositivo:** Desktop  
**Sección:** Storefront → Catálogo de productos → Filtros  
**Descripción:** Al seleccionar un filtro de categoría, la página no hace scroll hacia arriba para mostrar los resultados. El usuario queda en la posición donde estaba y no ve los productos filtrados.  
**Acción:** Al aplicar cualquier filtro (categoría, precio, ordenamiento), ejecutar `window.scrollTo({ top: productsListTop, behavior: 'smooth' })` o equivalente. Aplica a todos los templates.

---

### [WEB-PROD-08] Doble estado de "Cargando" al filtrar productos
**Dispositivo:** Desktop  
**Sección:** Storefront → Catálogo de productos → Filtros  
**Descripción:** Al seleccionar o limpiar un filtro, aparecen dos indicadores de carga simultáneos: uno blanco "Cargando..." y otro celeste "Cargando productos..." superpuestos.  
**Acción:** Unificar el estado de loading en un único componente/indicador. Revisar si hay dos queries o dos estados de React corriendo en paralelo innecesariamente. Solo debe existir un loading state visible al usuario.

---

### [WEB-PROD-09] Categorías duplicadas al importar por nombre similar (Desktop)
**Dispositivo:** Desktop  
**Sección:** Storefront → Catálogo → Panel Admin → Importar Excel  
**Descripción:** Al importar un Excel con una categoría "Digestivos", si ya existía "Digestivo", el sistema crea ambas como categorías distintas en lugar de detectar el match. Las categorías además no se listan en orden alfabético.  
**Repo:** `@nv/api` + `@nv/admin`  
**Acciones:**  
  1. En el servicio de importación de la API, implementar normalización al comparar categorías: trim + lowercase + (opcional) distancia de Levenshtein para matches cercanos, con confirmación del usuario si hay ambigüedad.  
  2. Las categorías en los filtros del catálogo deben ordenarse alfabéticamente (ORDER BY name ASC en la query o sort en frontend).

---

### [WEB-PROD-10] Productos sin stock sin indicación visual en catálogo
**Dispositivo:** Desktop + Mobile  
**Sección:** Storefront → Catálogo de productos  
**Descripción:** Los productos sin stock se muestran igual que los disponibles. No hay badge, etiqueta ni diferenciación visual. El usuario no puede saber cuáles están agotados sin entrar al detalle.  
**Acción:** Agregar un badge "Sin stock" o "Agotado" sobre la imagen del producto cuando `available = false` o `stock = 0`. El nombre del producto puede mostrarse con menor opacidad (ej: 60%). El botón "Agregar al carrito" debe estar deshabilitado. Aplica a todos los templates.

---

### [WEB-PROD-11] Fotos pixeladas en vista detalle de producto
**Dispositivo:** Desktop  
**Sección:** Storefront → Producto individual  
**Descripción:** Las imágenes del producto se ven pixeladas al visualizarlas en la vista de detalle.  
**Acción:** Revisar si hay compresión agresiva en el pipeline de upload de imágenes o si el componente de imagen tiene un `max-width` muy bajo que fuerza el escalado. Verificar que se sirva la resolución original o una versión optimizada de mayor calidad. Revisar configuración de CDN/storage (Supabase Storage).

---

### [WEB-PROD-12] Flechas para navegar fotos en cards de producto (desde inicio)
**Dispositivo:** Desktop  
**Sección:** Storefront → Inicio → Sección de productos  
**Descripción:** El usuario pide poder navegar las fotos de un producto directamente desde la card del catálogo de inicio, sin tener que entrar al detalle.  
**Acción (feature request / mejora UX):** Si el producto tiene más de 1 imagen, mostrar flechas de navegación al hacer hover sobre la card (desktop) o en los laterales de la imagen (mobile). Implementar navegación lazy entre imágenes dentro de la card. Aplica a todos los templates.

---

### [WEB-PROD-13] Categoría desfasada visualmente en cards de inicio (Mobile + Desktop)
**Dispositivo:** Mobile + Desktop  
**Sección:** Storefront → Inicio → Cards de productos  
**Descripción:** Los productos con categoría asignada muestran el texto de categoría encima del nombre, mientras que los productos sin categoría solo muestran el nombre. Esto genera un desalineamiento visual entre cards.  
**Acción:** Mover la etiqueta de categoría **debajo** del nombre del producto en la card, o asegurarse de que el espacio para la categoría siempre esté reservado (con altura mínima o `min-height`) incluso cuando no hay categoría. Aplica a todos los templates.

---

## 2. PRODUCTOS — ADMIN PANEL (`@nv/admin`)

---

### [ADMIN-PROD-01] Cartel confuso "No hay cambios pendientes en este producto"
**Dispositivo:** Mobile  
**Sección:** Admin → Crear Producto y Editar Producto  
**Descripción:** Al abrir el formulario de creación o edición de un producto, aparece inmediatamente el mensaje "No hay cambios pendientes en este producto". Esto confunde al usuario ya que es un estado esperado al abrir el formulario vacío.  
**Acción:** Ocultar este mensaje al cargar el formulario. Solo mostrarlo si el usuario intentó guardar sin haber realizado cambios, o directamente eliminarlo si no aporta valor en el flujo.

---

### [ADMIN-PROD-02] Botón "Guardar Cambios" en edición de producto con transparencia / se empasta
**Dispositivo:** Mobile  
**Sección:** Admin → Editar Producto → Footer de acciones  
**Descripción:** El botón "Guardar Cambios" tiene transparencia aplicada, haciéndolo difícil de distinguir del contenido que hay detrás en mobile.  
**Acción:** Asegurar que el botón de acción principal tenga fondo sólido (`background-color` sin `opacity` o `rgba` con canal alpha al 100%). Revisar si el issue es de `position: sticky` con backdrop que genera el efecto de transparencia.

---

### [ADMIN-PROD-03] Ordenamiento alfabético solo aplica a la página actual, no a todos los productos
**Dispositivo:** Desktop  
**Sección:** Admin → Gestión de Productos → Tabla paginada  
**Descripción:** Al ordenar por nombre (A-Z), el orden se aplica solo dentro de la página actual (ej: página 1 de 4). Las páginas 2, 3, 4 siguen con su propio orden, en lugar de reordenar el dataset completo.  
**Acción:** El sort debe ejecutarse en la query de la API (ORDER BY en SQL), no en el frontend sobre el slice de la página actual. Verificar el endpoint de listado de productos y asegurar que el parámetro `sort` se pase correctamente a la query.

---

### [ADMIN-PROD-04] Columna "Acciones" con transparencia en tabla de órdenes (Mobile)
**Dispositivo:** Mobile  
**Sección:** Admin → Gestión de Productos → Tabla  
**Descripción:** La columna de acciones (Editar/Borrar) tiene transparencia y se empasta con el contenido adyacente al hacer scroll horizontal.  
**Acción:** Si la columna de acciones es sticky (fija al hacer scroll horizontal), aplicar un `background-color` sólido que coincida con el fondo de la fila. Usar la variable CSS correspondiente (`--nv-admin-card` o `--nv-admin-bg-alt`).

---

### [ADMIN-PROD-05] Header transparente en preview del Excel al hacer scroll
**Dispositivo:** Desktop  
**Sección:** Admin → Importar Excel → Previsualización de la carga  
**Descripción:** La primera fila del preview (cabecera de columnas) es sticky pero tiene fondo transparente, superponiendo visualmente los datos al hacer scroll vertical.  
**Acción:** Agregar `background-color` sólido a la fila header sticky de la tabla de preview. Usar `--nv-admin-card` o `white` según el diseño.

---

### [ADMIN-PROD-06] Indicador de alerta para productos inactivos o sin stock en tabla
**Dispositivo:** Desktop  
**Sección:** Admin → Gestión de Productos → Tabla  
**Descripción (feature/mejora):** No hay indicación visual de qué productos están inactivos o sin stock en la tabla de gestión.  
**Acción:** Agregar una columna de estado (o ícono de advertencia ⚠️) al principio de la tabla que indique:  
  - `available = false` → Badge "Inactivo"  
  - `stock = 0` → Badge "Sin stock"  
  Puede ser una columna pequeña con ícono + tooltip descriptivo.

---

### [ADMIN-PROD-07] Productos inactivos al importar: comportamiento por defecto no documentado
**Dispositivo:** Desktop  
**Sección:** Admin → Importar Excel / JSON  
**Descripción:** Al importar un producto con `disponible = false` (o sin marcar disponible), la plataforma lo pone como activo por defecto. El usuario no sabe que esto pasa y no puede configurarlo durante la importación.  
**Acción:**  
  1. Documentar el comportamiento en la UI (tooltip o nota en el paso de importación).  
  2. Evaluar si el valor de `available` del Excel/JSON debería respetarse en lugar de usar un default.  
  3. Si el default es intencional, agregar una nota visible en la previsualización: "Los productos importados se marcan como disponibles por defecto. Podés cambiarlos después desde Gestión de Productos."

---

## 3. IMPORTACIÓN CON IA (`@nv/admin`)

---

### [ADMIN-IA-01] Botón "Abrir ChatGPT" se corta / sobresale (Mobile)
**Dispositivo:** Mobile  
**Sección:** Admin → Crear Producto → Importación con IA → Paso 1  
**Descripción:** El botón "Abrir ChatGPT" sobresale del contenedor, quedando cortado visualmente.  
**Acción:** Aplicar `overflow: hidden` al contenedor del paso o usar `flex-wrap: wrap` en el grupo de botones. Asegurar que los botones de acción respondan correctamente en viewports estrechos.

---

### [ADMIN-IA-02] Slider de pasos poco visible (Mobile)
**Dispositivo:** Mobile  
**Sección:** Admin → Importación con IA → Indicador de progreso de pasos  
**Descripción:** El stepper/slider de pasos ("1 Cargar datos → 2 Validación → ...") es muy claro y difícil de leer. El contraste es insuficiente.  
**Acción:** Aumentar el contraste del componente de stepper. Los pasos completados pueden usar el color de acento (`--nv-admin-accent`), el paso actual destacarse con un color primario sólido, y los pasos pendientes tener texto/ícono con contraste mínimo WCAG AA.

---

### [ADMIN-IA-03] Texto instructivo incorrecto en "Genera productos con IA" (Desktop)
**Dispositivo:** Desktop  
**Sección:** Admin → Importación con IA → Paso 1  
**Descripción:** El texto dice "Copiá el prompt, pegalo en ChatGPT o Claude, completá tu rubro y pegá el JSON resultante abajo." Falta la aclaración de dónde completar el rubro.  
**Acción:** Cambiar el texto a: **"Copiá el prompt, pegalo en ChatGPT o Claude, completá tu rubro (al final del prompt) y pegá el JSON resultante abajo."**

---

### [ADMIN-IA-04] Botón "Copiar Prompt" no centrado (Desktop)
**Dispositivo:** Desktop  
**Sección:** Admin → Importación con IA → Paso 1 → Sección "Generá productos con IA"  
**Descripción:** El botón "Copiar Prompt" no está centrado correctamente dentro de su sección.  
**Acción:** Revisar el layout del contenedor. Aplicar `text-align: center` o `justify-content: center` según el contexto (flex/grid).

---

### [ADMIN-IA-05] No aparece descripción del producto en modal de edición del Paso 3 (Desktop)
**Dispositivo:** Desktop  
**Sección:** Admin → Importación con IA → Paso 3 (Revisar items) → Editar producto (✏️)  
**Descripción:** Al abrir el modal de edición de un producto generado por IA, el campo "Descripción" aparece vacío aunque el JSON generado sí incluía descripción.  
**Acción:** Verificar el mapeo del campo `descripcion` / `description` al cargar los datos del JSON en el modal de edición. Revisar si hay un mismatch de keys entre el JSON generado por la IA y el modelo esperado por el formulario.

---

### [ADMIN-IA-06] "Advertencia" no es accionable — usuario no sabe cómo verla (Desktop)
**Dispositivo:** Desktop  
**Sección:** Admin → Importación con IA → Paso 3 → Columna "Estado"  
**Descripción:** El badge "ADVERTENCIA" en la tabla no es clickeable ni expansible. La advertencia solo se ve al abrir el editor (✏️), lo cual no es intuitivo. Además, los íconos de acción están muy claros (bajo contraste).  
**Acciones:**  
  1. Hacer el badge "ADVERTENCIA" clickeable para mostrar un tooltip o modal con el detalle del problema.  
  2. Agregar un cartel visible en el paso 3 que indique explícitamente: "Revisá y abrí el editor (✏️) de cada producto para verificar stock y datos antes de importar."  
  3. Aumentar la saturación/contraste de los íconos de acción (✏️, 🗑️, ✕) a la derecha.

---

### [ADMIN-IA-07] Texto de instrucciones "Revisá y editá cada producto..." muy claro (Desktop)
**Dispositivo:** Desktop  
**Sección:** Admin → Importación con IA → Paso 3  
**Descripción:** El texto "Revisá y editá cada producto antes de importar. Usá ✏️ para editar, ✕ para quitar categorías y 🗑 para eliminar." tiene muy bajo contraste (gris claro).  
**Acción:** Aumentar el contraste de este texto. Dado que es una instrucción importante, considerar mostrarlo en una nota/callout con fondo de color suave y texto oscuro en lugar de texto gris desvanecido.

---

### [ADMIN-IA-08] Campos limitados en modal de edición del Paso 3 (Desktop)
**Dispositivo:** Desktop  
**Sección:** Admin → Importación con IA → Paso 3 → Modal de edición  
**Descripción:** El modal solo muestra: SKU, Stock, Nombre, Precio original, Precio con descuento, Descripción, Categoría. Faltan campos relevantes como: Disponible/Activo, Destacado, Más vendido, Envío habilitado, variantes.  
**Acción:** Evaluar si es técnicamente viable agregar los campos faltantes al modal de edición de la importación. Como mínimo, agregar el toggle de "Disponible" ya que impacta directamente si el producto se publica activo o no.

---

### [ADMIN-IA-09] Error "Validation failed (uuid is expected)" al cargar imágenes en Paso 4
**Dispositivo:** Desktop  
**Sección:** Admin → Importación con IA → Paso 4 (Imágenes)  
**Descripción:** Al intentar cargar una imagen en el paso 4 de la importación con IA, aparece un toast de error turquesa: "Validation failed (uuid is expected)". La misma imagen sí carga correctamente desde la gestión manual de productos.  
**Severidad:** CRÍTICA — bloquea la carga de imágenes en el flujo de IA.  
**Acción:** Revisar el endpoint de upload de imágenes usado en el paso 4. Probablemente el `productId` o `clientId` que se envía no está correctamente formado (puede ser un ID temporal del staging en lugar de un UUID real). Verificar que el producto exista en DB antes de intentar asociarle imágenes, o que el flujo de staging use el UUID correcto.

---

### [ADMIN-IA-10] Paso 5 indica "no se detectaron nuevas categorías" incorrectamente
**Dispositivo:** Desktop  
**Sección:** Admin → Importación con IA → Paso 5 (Categorías)  
**Descripción:** En el paso 3 se mostraban categorías nuevas que iban a ser creadas, pero en el paso 5 aparece "No se detectaron categorías nuevas. Todas las categorías referenciadas ya existen en tu tienda."  
**Acción:** Revisar el estado compartido entre el Paso 3 y el Paso 5. Las categorías nuevas detectadas en el paso 3 deben persistirse en el contexto/estado del wizard y pasarse correctamente al paso 5. Verificar si hay un reset de estado entre pasos.

---

### [ADMIN-IA-11] Botón "Ver historial" no funciona en Paso 7 (Desktop)
**Dispositivo:** Desktop  
**Sección:** Admin → Importación con IA → Paso 7 (Reporte final)  
**Descripción:** El botón "Ver historial" no realiza ninguna acción al hacer click.  
**Severidad:** MEDIA — el flujo de importación concluye correctamente, pero el historial es inaccesible.  
**Acción:** Verificar el handler del botón "Ver historial". Probablemente apunta a una ruta que no existe o la navegación está mal configurada. Implementar la navegación al historial de importaciones.

---

### [ADMIN-IA-12] Errores de validación en inglés (Mobile)
**Dispositivo:** Mobile  
**Sección:** Admin → Opciones de Producto → Crear opción  
**Descripción:** Los mensajes de error de validación aparecen en inglés: `"Items.0.label must be a string"`, `"type must be one of the following values: apparel, footwear, accessory, generic"`.  
**Acción:** Internacionalizar todos los mensajes de error de validación de la API. En el contexto de NestJS + class-validator, configurar mensajes en español para los DTOs afectados. Todos los errores de la API que se muestran al usuario final deben estar en español.

---

## 4. ÓRDENES — ADMIN PANEL (`@nv/admin`)

---

### [ADMIN-ORD-01] Columna "Acciones" con transparencia en tabla de órdenes (Mobile)
**Dispositivo:** Mobile  
**Sección:** Admin → Órdenes → Tabla de gestión  
**Descripción:** La columna "Acciones" es semi-transparente y al hacer scroll horizontal se empasta con los datos adyacentes.  
**Acción:** Igual que ADMIN-PROD-04. Aplicar `background-color` sólido a las celdas sticky de la columna de acciones. Verificar si es el mismo componente de tabla reutilizable con el mismo bug.

---

### [ADMIN-ORD-02] Ícono de búsqueda no centrado en su contenedor (Mobile)
**Dispositivo:** Mobile  
**Sección:** Admin → Órdenes → Input de búsqueda  
**Descripción:** El ícono de lupa (🔍) está descentrado dentro de su botón/contenedor circular.  
**Acción:** Aplicar `display: flex; align-items: center; justify-content: center` al botón del ícono de búsqueda.

---

### [ADMIN-ORD-03] Columnas "Estado" y "Envío" se desbordan de su columna en tabla (Mobile)
**Dispositivo:** Mobile  
**Sección:** Admin → Órdenes → Tabla  
**Descripción:** El texto/badge de las columnas "Estado" (ej: "Pendiente") y "Envío" (ej: "Sin envío") se desborda fuera de los límites de su celda.  
**Acción:** Agregar `white-space: nowrap` + `overflow: hidden` + `text-overflow: ellipsis` en las celdas, o reducir el tamaño del badge. Verificar el ancho mínimo de las columnas en la tabla responsive.

---

### [ADMIN-ORD-04] Escáner QR no muestra la cámara en mobile
**Dispositivo:** Mobile  
**Sección:** Admin → Órdenes → Escáner QR  
**Descripción:** Al abrir el escáner QR, el modal muestra un recuadro en blanco en lugar del feed de la cámara.  
**Severidad:** ALTA — bloquea el flujo de verificación de órdenes por QR en mobile.  
**Acción:** Verificar que se soliciten los permisos de cámara correctamente (`navigator.mediaDevices.getUserMedia`). Revisar si el componente de QR scanner (probablemente una librería como `react-qr-reader`) está correctamente inicializado y si el contexto HTTPS está disponible (requerido para acceso a cámara). Verificar en distintos navegadores mobile.

---

## 5. PAGOS — ADMIN PANEL (`@nv/admin`)

---

### [ADMIN-PAY-01] Sección de pagos cortada a la derecha en mobile
**Dispositivo:** Mobile  
**Sección:** Admin → Pagos  
**Descripción:** La pantalla de configuración de pagos tiene contenido que se corta hacia la derecha del viewport.  
**Acción:** Revisar el layout del componente de la sección de pagos. Aplicar `max-width: 100%` y `overflow-x: hidden` a los contenedores. Verificar que no haya elementos con `width` fijo mayor al viewport.

---

### [ADMIN-PAY-02] Tabla "Tarifas Mercado Pago" cortada a la derecha y problemas de scroll (Mobile)
**Dispositivo:** Mobile  
**Sección:** Admin → Pagos → Ver tarifas MP (modal/sección)  
**Descripción:** La tabla de tarifas de MP se corta. Además, "Acreditaciones (pagos)" está desalineada en su fila. Al tocar en ciertas zonas, el scroll se aplica al fondo en lugar de a la tabla, generando confusión.  
**Acciones:**  
  1. Envolver la tabla en un `div` con `overflow-x: auto` para habilitar scroll horizontal interno.  
  2. Corregir la alineación vertical de la celda "Acreditaciones (pagos)": usar `vertical-align: middle` o `align-items: center`.  
  3. Si la tabla está en un modal, asegurar que el scroll sea `overflow-y: auto` dentro del modal y no se propague al body (usar `overscroll-behavior: contain`).

---

## 6. ENVÍOS — ADMIN PANEL (`@nv/admin`)

---

### [ADMIN-SHIP-01] Campo "Monto fijo" no permite borrar el 0 inicial (Mobile)
**Dispositivo:** Mobile  
**Sección:** Admin → Envíos → Configuración → Costo del servicio → Monto fijo (ARS)  
**Descripción:** Al ingresar un monto en el campo de monto fijo, el cero inicial no se puede borrar. El valor queda como "0200" en lugar de "200".  
**Acción:** Usar `type="number"` en el input o implementar un handler `onChange` que elimine los ceros a la izquierda. Alternativamente, usar `parseFloat` al leer el valor antes de guardarlo. Si ya es `type="number"`, revisar si el issue es de renderizado del valor inicial como string.

---

### [ADMIN-SHIP-02] Tutorial tapa el elemento que está siendo explicado (Mobile)
**Dispositivo:** Mobile  
**Sección:** Admin → Envíos → Configuración → Tutorial  
**Descripción:** El popover del tutorial cubre el elemento de la UI al que hace referencia, impidiendo que el usuario lo vea mientras lee la explicación.  
**Acción:** Revisar el posicionamiento del tooltip/popover del tutorial. Debe posicionarse de manera que no tape el elemento target. Usar una estrategia de posicionamiento inteligente (arriba, abajo, costados) dependiendo del espacio disponible en el viewport. Problema ya registrado en GEN-02, verificar si es el mismo componente de tutoriales.

---

### [ADMIN-SHIP-03] Error "No se pudo guardar" / "No se pudo restablecer" al editar configuración de envíos (Mobile)
**Dispositivo:** Mobile  
**Sección:** Admin → Envíos → Configuración → Guardar / Restablecer defaults  
**Descripción:** Al intentar guardar la configuración de envíos o restablecer los defaults, aparece un toast de error en rojo. La operación no se completa.  
**Severidad:** CRÍTICA — bloquea la configuración de envíos en mobile.  
**Acción:** Reproducir el error en mobile e inspeccionar la respuesta del endpoint de guardado. Puede ser un issue de: (a) validación server-side que falla silenciosamente, (b) problema de autenticación/token en mobile, (c) error en el payload enviado. Revisar los logs del API en Railway.

---

### [ADMIN-SHIP-04] Al guardar envíos, aparece spinner gris pequeño y no se guarda (Mobile)
**Dispositivo:** Mobile  
**Sección:** Admin → Envíos → Configuración → Botón "Guardar" (parte inferior)  
**Descripción:** Al presionar "Guardar" al final de la configuración de envíos, aparece brevemente un recuadro gris pequeño (spinner o indicador de carga) y luego no pasa nada. Los datos no se guardan.  
**Severidad:** CRÍTICA — mismo bloqueo que ADMIN-SHIP-03, investigar si son el mismo issue.  
**Acción:** Verificar que el botón "Guardar" al final esté correctamente conectado al mismo handler que el botón de guardar principal. Puede ser que haya dos botones de guardar con handlers distintos o que el scroll hasta el fondo del formulario en mobile esté interfiriendo con el submit.

---

### [ADMIN-SHIP-05] Items deshabilitados muy claros — contraste insuficiente (Mobile)
**Dispositivo:** Mobile  
**Sección:** Admin → Envíos → Configuración  
**Descripción:** Las opciones que no están habilitadas (ej: "Envíos a domicilio" cuando está desactivado) muestran texto en gris muy claro, prácticamente ilegible.  
**Acción:** El estado deshabilitado debe tener suficiente contraste para ser legible (ratio WCAG AA: 4.5:1 para texto normal). Usar `--nv-admin-muted` pero con un valor que cumpla el ratio mínimo de contraste. El estado deshabilitado puede diferenciarse por `opacity` o `font-style: italic` además del color, no solo por claridad extrema.

---

### [ADMIN-SHIP-06] Último tab del slider "Configuración / Integraciones / Guías..." cortado (Mobile)
**Dispositivo:** Mobile  
**Sección:** Admin → Envíos → Tab bar superior  
**Descripción:** El último tab del slider de navegación de Envíos no es completamente visible (se corta a la derecha).  
**Acción:** Implementar scroll horizontal en el tab bar o ajustar el tamaño de los tabs para que todos sean visibles. Usar `overflow-x: auto` con `scrollbar-width: none` en el contenedor del tab bar. Alternativamente, usar un tamaño de fuente más pequeño en los tabs si hay muchos items.

---

## 7. CUPONES — ADMIN PANEL (`@nv/admin`)

---

### [ADMIN-CUP-01] Términos "Usos totales máximos" y "Usos por usuario" sin explicación (Desktop)
**Dispositivo:** Desktop  
**Sección:** Admin → Cupones → Crear cupón  
**Descripción:** Los campos "Usos totales máximos" y "Usos por usuario" no son claros para el usuario. No hay tooltip ni descripción que explique su diferencia.  
**Acción:** Agregar un ícono de ayuda (ℹ️) con tooltip a cada campo:  
  - **Usos totales máximos:** "Cantidad máxima de veces que este cupón puede ser usado en total por todos los clientes. Ej: 3 = el cupón deja de funcionar después de 3 usos totales."  
  - **Usos por usuario:** "Cantidad máxima de veces que un mismo usuario puede usar este cupón. Ej: 1 = cada cliente solo puede usarlo una vez."

---

## 8. OPCIONES DE PRODUCTO (`@nv/admin`)

---

### [ADMIN-OPT-01] Tabla de opciones de producto cortada a la derecha (Mobile)
**Dispositivo:** Mobile  
**Sección:** Admin → Opciones de Producto  
**Descripción:** La tabla de opciones (Nombre, Tipo, PREDEFINIDO) se corta hacia la derecha, no permitiendo ver la columna "Tipo" completa.  
**Acción:** Aplicar `overflow-x: auto` al wrapper de la tabla. Considerar una vista de cards en mobile en lugar de tabla horizontal.

---

### [ADMIN-OPT-02] Error al crear opción — mensajes en inglés y validación confusa (Mobile)
**Dispositivo:** Mobile  
**Sección:** Admin → Opciones de Producto → Crear opciones  
**Descripción:** Al intentar crear una opción:  
  - Error 1: `"Items.0.label must be a string"` — aparece aunque se completaron los campos.  
  - Error 2: `"type must be one of the following values: apparel, footwear, accessory, generic"` — el valor "talle" (en español) no es aceptado aunque aparece en el selector.  
**Acciones:**  
  1. Los mensajes de error deben estar en español (ver ADMIN-IA-12 — mismo root cause).  
  2. Si el selector de "Tipo" muestra "Talle" como opción, el valor enviado al backend debe mapearse al valor interno en inglés (`apparel`). Revisar el mapeo entre los labels del select y los valores enviados en el payload.  
  3. El campo `items[0].label` puede estar enviando undefined si el input de "Items" no está correctamente bindeado al estado del formulario.

---

### [ADMIN-OPT-03] Tabla de Guía de Talles cortada (Mobile)
**Dispositivo:** Mobile  
**Sección:** Admin → Opciones de Producto → Guía de Talles  
**Descripción:** La tabla de guía de talles se corta a la derecha. Al expandir una guía para ver más detalle, la tabla interna también se corta.  
**Acción:** Igual que ADMIN-OPT-01. Aplicar `overflow-x: auto` a los wrappers de ambas tablas (listado de guías y detalle de guía).

---

## 9. SERVICIOS — STOREFRONT (`@nv/web`)

---

### [WEB-SRV-01] Íconos de servicios no centrados y desalineados (Mobile)
**Dispositivo:** Mobile  
**Sección:** Storefront → Servicios  
**Descripción:** Los íconos de los servicios están alineados a la izquierda en lugar de estar centrados. El layout esperado es centrado verticalmente y horizontalmente dentro de cada card.  
**Acción:** Aplicar `display: flex; align-items: center; justify-content: center` al contenedor del ícono en cada card de servicio. Aplica a todos los templates.

---

### [WEB-SRV-02] Ícono con foto custom se ve desproporcionadamente grande (Mobile + Desktop)
**Dispositivo:** Mobile + Desktop  
**Sección:** Storefront → Servicios + Admin → Servicios → Carga de imagen  
**Descripción:** Cuando un servicio usa una imagen custom en lugar de un ícono vectorial, la imagen se muestra a tamaño completo (mucho más grande que los íconos SVG de los otros servicios). Se rompe la consistencia visual.  
**Acción:** Definir un tamaño fijo para el contenedor del ícono/imagen del servicio (ej: `width: 48px; height: 48px`) con `object-fit: contain`. La imagen custom debe escalarse al mismo tamaño que los íconos predefinidos. Aplica a todos los templates.

---

## 10. PREGUNTAS FRECUENTES / REVIEWS (`@nv/web`)

---

### [WEB-REV-01] Sección de comentarios de clientes en columnas — texto ilegible (Mobile)
**Dispositivo:** Mobile  
**Sección:** Storefront → Sección de testimonios/comentarios de clientes  
**Descripción:** Los testimonios de clientes se muestran en 3 columnas en mobile. El texto de cada testimonio se divide en muchas líneas muy angostas (1-2 palabras por línea), haciendo la lectura prácticamente imposible.  
**Acción:** En mobile, mostrar los testimonios en 1 columna (100% de ancho) apilados verticalmente. Usar `grid-template-columns: 1fr` en mobile y `repeat(3, 1fr)` en desktop. Aplica a todos los templates.

---

## 11. BANNERS — STOREFRONT (`@nv/web`)

---

### [WEB-BAN-01] Banners horizontales no adaptados al viewport mobile
**Dispositivo:** Mobile  
**Sección:** Storefront → Inicio → Sección de banners  
**Descripción:** Los banners cargados en formato horizontal (landscape) se muestran en mobile con el mismo ratio, ocupando muy poco espacio vertical y mucho horizontal. El usuario esperaría una versión adaptada o crop al formato vertical.  
**Acción:** Implementar una de estas estrategias para mobile:  
  1. Usar `aspect-ratio: 16/9` en mobile para mantener el banner con altura proporcional.  
  2. O usar `object-fit: cover` con una altura fija en mobile (ej: `height: 200px`) para que el banner ocupe un espacio vertical más visible.  
  Aplica a todos los templates. Si en el futuro se soportan banners separados para mobile/desktop, documentarlo.

---

## 12. SEO AI AUTOPILOT (`@nv/admin`)

---

### [ADMIN-SEO-01] Textos de etiquetas no centrados en mobile
**Dispositivo:** Mobile  
**Sección:** Admin → SEO AI Autopilot → Configuraciones SEO técnico  
**Descripción:** Los textos en negro como "Titulo del sitio" no están centrados horizontalmente en su contenedor.  
**Acción:** Revisar el CSS del componente de card SEO. Los títulos de sección deben tener `text-align: center` o estar alineados consistentemente.

---

### [ADMIN-SEO-02] "Cobertura del catálogo 0%" y el badge al lado — deben estar en columna (Mobile)
**Dispositivo:** Mobile  
**Sección:** Admin → SEO AI Autopilot → Cobertura de contenido  
**Descripción:** El texto "Cobertura del catalogo: 0%" y el badge/chip con "0/38 productos con título" están en fila horizontal en mobile, cuando deberían estar uno debajo del otro.  
**Acción:** En mobile, cambiar `flex-direction: row` a `flex-direction: column` en el contenedor de esta métrica.

---

### [ADMIN-SEO-03] Textos en gris claro poco legibles — contraste insuficiente (Mobile)
**Dispositivo:** Mobile  
**Sección:** Admin → SEO AI Autopilot → Resumen del catálogo + Edición manual  
**Descripción:** Varios textos secundarios en gris claro son casi ilegibles en mobile (contraste insuficiente).  
**Acción:** Aumentar el contraste de los textos secundarios del SEO Autopilot. Usar `--nv-admin-muted` con valor mínimo de contraste WCAG AA. Revisar todos los textos de helper/placeholder en el módulo SEO.

---

### [ADMIN-SEO-04] Tabla "Problemas detectados" cortada a la derecha (Mobile)
**Dispositivo:** Mobile  
**Sección:** Admin → SEO AI Autopilot → Problemas detectados  
**Descripción:** La tabla de problemas (TIPO, NOMBRE, PROBLEMA, SEVERIDAD) se corta a la derecha en mobile.  
**Acción:** Aplicar `overflow-x: auto` al wrapper de la tabla o implementar una vista de cards/lista en mobile.

---

### [ADMIN-SEO-05] Campo "Descripción del sitio" muy pequeño en edición manual (Mobile)
**Dispositivo:** Mobile  
**Sección:** Admin → SEO AI Autopilot → Edición manual → Descripción del Sitio  
**Descripción:** El textarea de descripción del sitio (0/160 caracteres) es muy pequeño en mobile, dificultando la edición.  
**Acción:** Aumentar la altura mínima del textarea: `min-height: 80px` o `rows={3}`. Considerar que al hacer focus en mobile el teclado ocupa parte de la pantalla, por lo que el textarea debe ser lo suficientemente grande para ser cómodo.

---

### [ADMIN-SEO-06] Texto de instrucciones desborda el recuadro en "Google Search Console" (Mobile)
**Dispositivo:** Mobile  
**Sección:** Admin → SEO AI Autopilot → Edición manual → Google Search Console (token)  
**Descripción:** El texto de instrucciones del campo de Google Search Console no cabe dentro del recuadro blanco y se desborda visualmente.  
**Acción:** Aplicar `word-break: break-word` y `overflow-wrap: break-word` al contenedor de instrucciones. Verificar que el `max-width` del contenedor sea `100%`.

---

### [ADMIN-SEO-07] SEO "se guarda correctamente" pero sigue en rojo al volver (Mobile)
**Dispositivo:** Mobile  
**Sección:** Admin → SEO AI Autopilot → Edición manual de producto  
**Descripción:** Al guardar el SEO de un producto, aparece el toast "SEO guardado correctamente" en verde. Sin embargo, al volver a la lista, el producto sigue mostrando badge rojo "Sin SEO".  
**Severidad:** ALTA — el usuario cree que guardó pero el estado no se refleja.  
**Acción:** Verificar si el guardado falla silenciosamente (el toast siempre es positivo) o si la invalidación del cache/query de React Query no está funcionando. Después de un save exitoso, forzar el refetch de la lista de productos con su estado SEO.

---

### [ADMIN-SEO-08] Campos técnicos sin explicación — necesitan tooltip (Mobile)
**Dispositivo:** Mobile  
**Sección:** Admin → SEO AI Autopilot → Edición manual → Configuración SEO de la Tienda  
**Descripción:** Campos como "Favicon", "Google Analytics 4 (ID)", "Meta Pixel (Facebook)", "Google Search Console (token)" y "robots.txt personalizado" no tienen descripción que ayude al usuario a entender qué son o cómo obtener los valores.  
**Acción:** Agregar un ícono (ℹ️) con tooltip o texto de ayuda expandible a cada campo:  
  - **Favicon:** "Ícono pequeño que aparece en la pestaña del navegador. Debe ser una URL de imagen (ej: .ico o .png de 32x32px)."  
  - **Google Analytics 4:** "ID de seguimiento de Google Analytics. Lo encontrás en tu cuenta de GA4 > Admin > Flujos de datos. Formato: G-XXXXXXXXXX."  
  - **Meta Pixel:** "ID de seguimiento de Facebook/Meta. Lo encontrás en el Administrador de Eventos de Meta. Solo el número, ej: 1234567890."  
  - **Google Search Console:** "Token de verificación de propiedad de tu sitio en Google Search Console. Pegá el valor del contenido del meta tag de verificación."  
  - **robots.txt:** "Instrucciones para los rastreadores de Google. Si no sabés qué es esto, dejalo con el valor por defecto."

---

### [ADMIN-SEO-09] Textos en gris claro en edición manual SEO muy poco visibles (Mobile)
**Dispositivo:** Mobile  
**Sección:** Admin → SEO AI Autopilot → Edición manual  
**Descripción:** Los textos de ayuda/placeholder en gris claro son casi ilegibles.  
**Acción:** Consolidar con ADMIN-SEO-03. Mismo fix de contraste.

---

## 13. DATOS DE CONTACTO (`@nv/admin`)

---

### [ADMIN-CON-01] Botón azul se superpone con título "Gestión de Información de Contacto" (Mobile)
**Dispositivo:** Mobile  
**Sección:** Admin → Datos de Contacto  
**Descripción:** Hay un botón azul (probablemente el botón de agregar nueva dirección/contacto) que se superpone visualmente con el título de la sección.  
**Acción:** Revisar el layout del header de la sección. El botón de acción principal debe estar correctamente posicionado (a la derecha del título o debajo). Revisar si hay un `position: absolute` o `z-index` mal configurado.

---

## 14. REDES SOCIALES (`@nv/admin`)

---

### [ADMIN-SOC-01] Botón inaccesible superpuesto con título "Gestión de Enlaces Sociales" (Mobile)
**Dispositivo:** Mobile  
**Sección:** Admin → Redes Sociales  
**Descripción:** Mismo patrón que ADMIN-CON-01. Un botón azul se superpone con el título y no puede ser presionado.  
**Acción:** Mismo fix que ADMIN-CON-01. Revisar si es el mismo componente de header de sección reutilizable que tiene el bug de posicionamiento.

---

## 15. DISEÑO DE TIENDA / ADDON STORE (`@nv/admin`)

---

### [ADMIN-DES-01] Diseño de Tienda casi invisible en mobile — contenido cortado y botones fuera
**Dispositivo:** Mobile  
**Sección:** Admin → Diseño de Tienda  
**Descripción:** En mobile, la sección de Diseño de Tienda muestra muy poco contenido. Hay un recuadro blanco que tapa la mayor parte de la interfaz y los botones se cortan a la derecha.  
**Severidad:** ALTA — el flujo de personalización de la tienda es inutilizable en mobile.  
**Acción:** Revisar el layout completo del componente de Diseño de Tienda en mobile. Identificar qué elemento genera el recuadro blanco superpuesto (puede ser un overlay, un modal que no se oculta, o un `div` con `background: white` y `position: absolute`). Asegurar que todos los botones de acción estén dentro del viewport.

---

## PENDIENTES DE REVISIÓN (Secciones no evaluadas en esta sesión)

Las siguientes secciones fueron marcadas en el reporte de QA como **"No ha sido revisado aún"** y quedan pendientes para la próxima sesión de QA:

| Sección | Repo |
|---------|------|
| Logo | `@nv/web` + `@nv/admin` |
| Información y Anuncios | `@nv/admin` |
| Uso del Plan | `@nv/admin` |
| Analytics | `@nv/admin` |
| Facturación | `@nv/admin` |
| Suscripción | `@nv/admin` |
| Soporte | `@nv/admin` |
| Usuarios | `@nv/admin` |
| Opiniones y Reviews (admin) | `@nv/admin` |
| Desktop (Órdenes, Pagos, Envíos, Cupones, Opciones) | `@nv/admin` |

---

## RESUMEN DE ISSUES CRÍTICOS (ACCIÓN INMEDIATA)

| ID | Descripción | Repo | Impacto |
|----|-------------|------|---------|
| ADMIN-IA-09 | Error uuid al cargar imágenes en importación IA | `@nv/admin` + `@nv/api` | Bloquea upload de imágenes en flujo IA |
| ADMIN-SHIP-03 | No se puede guardar configuración de envíos (mobile) | `@nv/admin` + `@nv/api` | Bloquea configuración de envíos en mobile |
| ADMIN-SHIP-04 | Botón Guardar envíos no funciona (mobile) | `@nv/admin` | Bloquea configuración de envíos en mobile |
| ADMIN-ORD-04 | Escáner QR sin cámara en mobile | `@nv/admin` | Bloquea verificación de órdenes por QR |
| ADMIN-SEO-07 | SEO guarda pero sigue en rojo | `@nv/admin` + `@nv/api` | UX confusa — usuario cree que guardó |
| ADMIN-DES-01 | Diseño de Tienda inutilizable en mobile | `@nv/admin` | Bloquea personalización de tienda en mobile |

---

## RECORDATORIO QA — PENDIENTE VALIDAR

> Revisar cómo se ven los productos **sin stock** en el catálogo de la tienda: ¿están más grises o con algún indicador visual? (Ver issue WEB-PROD-10 para el fix propuesto.)

---

*Reporte generado a partir de sesión QA del 10/03/2026 sobre tenant `farma.novavision.lat`.*  
*Todos los fixes deben validarse contra los templates: `normal`, `first`, `Lumina` y cualquier otro template activo.*  
*Branch target: `develop`. Cherry-pick a `production` después de validación.*