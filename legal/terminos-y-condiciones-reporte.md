# Cumplimiento legal y flujo de aceptación en NovaVision (Argentina)

## Resumen ejecutivo

- **Responsabilidades diferenciadas:** NovaVision es proveedora de la plataforma SaaS; **el merchant** (propietario de la tienda) es responsable exclusivo de las operaciones comerciales (productos, envíos, devoluciones). Los **compradores finales** contratan con el merchant. Los documentos legales deben aclarar que NovaVision es meramente el proveedor de software y hosting, no participa en la venta de productos. Se incluirá un *disclaimer* visible indicando que “NovaVision no es el vendedor” (por ej. en footer) para evitar confusión con un marketplace.  
- **Obligaciones de información:** Según la Ley 24.240 de Defensa del Consumidor, todo proveedor que venda a consumidores debe brindar información “cierta, clara y detallada” sobre las características esenciales del bien/servicio【58†L119-L127】. En práctica, esto implica que el merchant debe mostrar en su tienda los datos de identificación (nombre legal, CUIT, domicilio), descripción de productos, precios finales con impuestos, costos de envío y plazos de entrega【58†L119-L127】【58†L208-L217】. NovaVision deberá facilitar campos obligatorios en el panel de administración para que el merchant ingrese esta información y asegurarse de que quede registrada (p.ej. en la plantilla de términos de venta).  
- **Derecho de arrepentimiento:** La Ley de Defensa del Consumidor (art. 34) otorga al comprador un plazo de 10 días corridos desde la entrega para revocar la compra sin invocar motivo【52†L625-L633】. En el sitio del merchant debe existir un mecanismo visible (por ejemplo, un *botón de arrepentimiento*) que permita al consumidor ejercer este derecho digitalmente, sin pasos adicionales como registro. La Disposición 954/2025 exige específicamente un “BOTÓN DE ARREPENTIMIENTO” en la primera vista de la web para facilitar este trámite【50†L162-L171】. NovaVision implementará este botón estándar en el checkout de la tienda (y en la e-mail de confirmación). Además, se debe informar al comprador sobre este derecho en el comprobante (textos claros en la política de cambios/devoluciones).  
- **Reversión de suscripciones (baja):** Si NovaVision ofrece planes de suscripción al merchant, igualmente corresponde un “botón de baja” según la Disposición 954/2025 (art. 4)【50†L216-L225】. Esto permitirá al merchant cancelar su suscripción fácilmente desde el panel. Tras la solicitud, NovaVision emitirá un código de trámite dentro de 24h y procederá a efectivizar la baja【50†L227-L234】. Debe comunicarse esta opción al merchant (en onboarding y en el panel).  
- **Contratos de adhesión y publicación de términos:** La Ley 24.240 (art. 38) establece que los contratos de adhesión deben publicarse en el sitio web【26†L748-L756】. Esto aplica a los términos de servicio de NovaVision (páginas de registro/onboarding) y, por extensión, al “modelo de contrato” que el merchant pone a disposición del comprador (es decir, los *Términos de la Tienda* que aceptará el comprador). Ambos deben estar accesibles antes de finalizar la compra y al crear cuenta. En los locales físicos se exhibe un cartel informando de este derecho【26†L748-L756】 (en nuestro caso, el cartel es el texto en el panel de alta).  
- **Protección de datos personales:** Rige la Ley 25.326 (Habeas Data) y normas complementarias. NovaVision debe presentar un Aviso de Privacidad claro: informar las finalidades del tratamiento de datos, quién es el responsable (NovaVision) y los derechos ARCO de los titulares【34†L194-L202】. Por ejemplo, el merchant deberá aceptar la política de privacidad en onboarding. El encargado (NovaVision) implementará medidas de seguridad razonables (cifrado, permisos mínimos) para proteger los datos【34†L240-L249】. Si se comparte información con terceros (p.ej. hosting, analítica, pasarela de pago), debe informarse al titular y, si son fuera del país, asegurarse niveles adecuados de protección. Se debe contar con un **Acuerdo de Tratamiento de Datos** (DPA) firmado con cada merchant para regular esta relación responsable-encargado (incluyendo subprocesadores).  
- **Consentimiento y pruebas de aceptación:** Para cada aceptación de términos (tanto el merchant aceptando T&C de NovaVision en el onboarding como el comprador aceptando Términos de la Tienda), se recogerá prueba robusta de consentimiento. Esto incluye versión del documento aceptado, timestamp, dirección IP, user_id y tenant_id. Por ejemplo, en el flujo mostrado en el código de Step11, al hacer POST a `/accept-terms` se guardará la versión de T&C (TERMS_VERSION) y se deberá complementar registrando en el backend la fecha/hora e IP del cliente. También se puede guardar en storage local como backup. De esta forma quedará rastro inalterable de la aceptación.  
- **Flujos de onboarding y checkout:** Se modela el producto en tres niveles: 
  1. **Home/marketing de NovaVision:** Captura leads y detalla features. No recolecta datos sensibles (solo email/contacto). Requiere atención a claims publicitarios (“tienda en 24h”, “500+ tiendas”, “sin comisiones ocultas”) y disclaimers generales (p.ej. “sujeto a aprobación”). Cualquier formulario de contacto debe incluir checkbox de consentimiento de datos (Ley de Protección de Datos y Ley Spam).  
  2. **Onboarding merchant (registro/config):** Aquí se recolectan datos del merchant (razón social, CUIT, email, datos de facturación, password). El merchant elige plan y acepta varios documentos: T&C de NovaVision (B2B), privacidad, AUP. También se firma implícitamente el DPA. Deberá haber validación visible de términos (checkbox) y nota de versión. Disputas típicas: desconocimiento de pagos recurrentes, sospecha de fraude. Se guardarían logs de alta de cuenta, cambio de plan, envío de email de confirmación.  
  3. **Storefront (tienda del merchant):** Aquí el buyer navega, selecciona productos y paga. Se recogen datos del comprador (nombre, dirección, email, pagos). Se promete “ventas seguras” pero se debe aclarar que el merchant es quien entrega el producto. Disputas comunes: envíos demorados, productos no recibidos, chargebacks por fraude, devoluciones. Debe implementarse un sistema para cargar términos de venta al checkout (confirmación de compra). Logs clave: pedido final, aceptación de términos, confirmación de pago, actualizaciones de estado de envío.  

- **Mínima evidencia y protección:** Ante posibles reclamos (fraude, incumplimiento), se recomienda un proceso preventivo: validar al merchant (revisión de tienda antes de activación), almacenar comunicaciones con compradores (tickets), guardar comprobantes de envío y mensajes. Contractualmente, se incluirán cláusulas de indemnidad donde el merchant asuma toda responsabilidad por su tienda y exima a NovaVision de daños ocasionados por sus productos o acciones. NovaVision limitará su responsabilidad a casos de fuerza mayor o negligencia grave.  

- **Cumplimiento de resoluciones y leyes recientes:** Además de la LDC y LDP, hay normativas actuales (por ej. Disposición 954/2025 sobre “botones”) que ya se deben respetar【50†L162-L171】【50†L216-L225】. No se deben usar expresiones que la ley prohíbe (por ejemplo, contratos de adhesión nulos si contienen estipulaciones abusivas)【52†L714-L723】. Se evitará cualquier cláusula que limite garantías básicas o derechos ARCO de manera ilegítima.  

- **Checklist técnico-legal:** Ver sección de checklist (abajo).  

- **Matriz de riesgos y mitigación:** Ver sección de matriz al final.  

## Documentos requeridos (mínimo vs. recomendado)

- **Obligatorios (mínimo legal):**  
  1. **Términos y Condiciones NovaVision (B2B)**: Contrato entre NovaVision y el merchant. Incluye licencia de uso del software, obligaciones de pago, limitaciones de responsabilidad, terminación de servicio, y cláusulas de indemnidad del merchant.  
  2. **Política de Privacidad NovaVision** (+ Cookies): Explica cómo NovaVision trata los datos personales (datos del merchant y de clientes de las tiendas), bases legales, derechos ARCO, recolección de cookies y analítica, y contactos. Debe cumplir Ley 25.326 y Ley de Spam.  
  3. **Acuerdo de Tratamiento de Datos (DPA)**: Establece el rol de NovaVision como encargado de datos cuando los merchants usan la plataforma (incluye normas de seguridad, subprocesadores y notificación de brechas).  
  4. **Política de Uso Aceptable (AUP) y Lista de Rubros Prohibidos:** Define actividades y contenidos vedados (fraude, ilegalidades, IP, productos regulados, etc.) en las tiendas. Contiene procedimientos de suspensión/terminación por incumplimiento.  
  5. **Política de Soporte / SLA:** Describe alcance del soporte (horarios, tiempos de respuesta, actualizaciones), uptime esperado, procedimientos de ticket, y exclusiones.  
  6. **Política de Suscripción/Cancelación:** Reglas claras de planes (renovación automática, precios, pasarelas), plazo de prueba, procedimiento de baja (incluyendo botón de baja), política de reembolsos (si aplica).  
  7. **Términos de la Tienda (Merchant→Buyer):** Plantilla para cada tienda. Debe incluir identificación del merchant (nombre y CUIT), condiciones de entrega/envío, políticas de cambio y devoluciones (incluyendo derecho de arrepentimiento 10 días)【52†L625-L633】, garantía legal (vicios, responsabilidad solidaria del proveedor), facturación e impuestos, atención al cliente, y una sección que exima a NovaVision como plataforma.  
  8. **Aviso Legal / Disclaimer (footer):** Mensaje breve en cada storefront explicando que NovaVision es sólo el proveedor de tecnología (no vendedor), por ejemplo: “NovaVision es plataforma de tiendas online. Los productos son ofrecidos y vendidos exclusivamente por el comercio; NovaVision no administra pagos ni entrega productos”.  

- **Recomendados (pro-bono / mejores prácticas):**  
  - **Política de Cookies detallada:** Si se usan cookies para analítica o marketing, listarlas con opción de gestión.  
  - **Consentimiento de Marketing:** Modal o checkbox para envíos comerciales (Ley 27.078).  
  - **Contrato de Licencia / End-User License Agreement (si fuera necesario):** Aunque cubierto en T&C, se puede detallar más formalmente el derecho de uso.  
  - **Protocolo de Incidentes de Seguridad:** Documento interno con pasos de respuesta ante brechas (notificación a AAIP, usuarios, etc.).  
  - **Informe de Impacto de Privacidad (si se maneja volumen grande de datos sensibles).**  

## Textos completos listos para publicar

A continuación se incluyen los documentos con lenguaje claro (ES-AR) y placeholders:

<details><summary><strong>1. Términos y Condiciones NovaVision (Merchant/Tenant)</strong></summary>

```markdown
# Términos y Condiciones de NovaVision

**Última actualización:** {DATE}  
**Empresa:** {COMPANY_NAME} (CUIT {CUIT}, domicilio {LEGAL_ADDRESS}, email legal {LEGAL_EMAIL})

## 1. Objeto del Contrato
1.1 NovaVision otorga al Merchant una licencia de uso limitado, no exclusiva e intransferible de su plataforma SaaS de ecommerce (“el Servicio”), según el plan contratado.  
1.2 El Merchant podrá crear y administrar tiendas online bajo su propiedad usando esta plataforma. El uso del Servicio implica la aceptación de estos Términos.

## 2. Obligaciones de NovaVision
2.1 NovaVision se compromete a proveer el Servicio contratado (hosting, acceso al sistema, actualizaciones de software) con un nivel de disponibilidad razonable.  
2.2 No garantiza resultados comerciales (ventas, ranking web) ni ingresos para el merchant. Cualquier claim de marketing es una meta o característica técnica, sin promesa de efectos.  
2.3 NovaVision podrá realizar mantenimientos programados; avisará con anticipación mínima de 48h en la plataforma.  
2.4 NovaVision implementa medidas de seguridad técnicas razonables (SSL, cifrado, backups), pero no se responsabiliza por accesos ilícitos realizados por terceros sofisticados.

## 3. Obligaciones del Merchant
3.1 Brindar información veraz y actualizada al registrarse (datos de empresa, contacto, facturación).  
3.2 Pagar puntualmente la suscripción acordada. NovaVision puede suspender el Servicio tras 5 días de mora notificados sin solución.  
3.3 El Merchant es responsable de la configuración y operación de su tienda: publicación de productos, precios, envíos, atención al cliente. Debe cumplir la Ley de Defensa del Consumidor【58†L119-L127】.  
3.4 En particular, informará en forma clara al usuario comprador sobre características, precios y condiciones de la venta, plazos de entrega y garantías.  
3.5 Facilitar el cumplimiento del derecho de arrepentimiento: incluir botón visible o link de reversión de compra en la tienda【50†L162-L171】 y política de devoluciones acorde a la normativa (10 días).  
3.6 Cumplir con obligaciones fiscales: emitir facturas electrónicas, declarar IVA y tributos que correspondan por sus ventas. NovaVision no asume responsabilidad fiscal.

## 4. Licencia de Propiedad Intelectual
4.1 El software, código, diseño y marca NovaVision son propiedad exclusiva de NovaVision S.R.L. El Merchant solo recibe licencia de uso.  
4.2 El Merchant conserva la titularidad de todo contenido propio que inserte en la tienda (textos, imágenes, catálogos), y garantiza no infringir derechos de terceros.  
4.3 NovaVision no asume responsabilidad por el contenido cargado por el Merchant; sin embargo, puede remover contenido que viole estos Términos o la ley (ver punto 6).  

## 5. Uso Aceptable (AUP)
5.1 El Merchant se compromete a usar el Servicio para fines lícitos. Queda prohibido usar la plataforma para:  
  - Comercio de productos ilegales o prohibidos (drogas, armas no permitidas, pornografía infantil, juegos de azar ilegales, etc.).  
  - Violación de derechos de autor o marcas (p.ej. venta de productos falsificados).  
  - Actividades fraudulentas (p.ej. phishing, estafas) o spam con fines comerciales.  
5.2 En caso de incumplimiento, NovaVision podrá suspender o cancelar la cuenta sin reembolso y, si corresponde, exigir indemnización por daños.

## 6. Contenido y Moderación
6.1 Todas las tiendas nuevas serán revisadas por NovaVision antes de su activación (para cumplimiento de políticas). Este proceso típicamente se completa en [X] horas hábiles.  
6.2 NovaVision puede eliminar o bloquear contenidos/productos que:  
   - Vuelen leyes nacionales o internacionales (p.ej. violen derechos de terceros).  
   - Se consideren ofensivos, difamatorios o peligrosos.  
6.3 El Merchant será notificado de cualquier remoción por incumplimiento; si persiste la infracción, se podrá terminar el servicio.

## 7. Pagos y Facturación
7.1 Las cuotas de suscripción se facturan por adelantado en la frecuencia seleccionada (mensual o anual). Los precios se listan en la página de planes, impuestos incluidos.  
7.2 La renovación es automática al vencimiento salvo cancelación previa por el Merchant con al menos 5 días de anticipación.  
7.3 No hay prorrateos ni reembolsos por cancelaciones parciales. Si se ofrece prueba gratuita, la suspensión antes de su fin evitará el cobro siguiente.  
7.4 NovaVision podrá revisar los límites de uso (número de productos, espacio en disco) previstos en cada plan; el Merchant no deberá excederlos.

## 8. Protección de Datos Personales
8.1 NovaVision cumple con la Ley 25.326. El Merchant y sus clientes podrán ejercitar sus derechos ARCO contactando a {LEGAL_EMAIL}.  
8.2 NovaVision trata datos necesarios para prestar el servicio (registro de cuenta, detalles de compra). Estos datos se utilizan para gestión interna y no se cederán a terceros para fines distintos sin consentimiento.  
8.3 NovaVision informa sobre finalidades y responsables en la Política de Privacidad. El Merchant autoriza el tratamiento de datos conforme a esa política, la cual puede modificar ocasionalmente.

## 9. Soporte y SLA
9.1 NovaVision ofrece soporte en el horario comercial (lun-vie 9:00–18:00). Los tiempos de respuesta son: confirmar ticket en 24h y resolver consultas básicas en 3 días hábiles.  
9.2 El Servicio apunta a un uptime del 99% mensual. Ante caídas prolongadas imputables a NovaVision, se podrá compensar con días de servicio gratuitos (según cálculo proporcional), salvo fuerza mayor.  
9.3 No se garantiza disponibilidad ilimitada; mantenimientos o problemas externos pueden generar interrupciones. NovaVision notificará previo a interrupciones programadas significativas.

## 10. Responsabilidad y Limitaciones
10.1 NovaVision no es responsable por daños indirectos, lucro cesante, pérdida de datos o ingresos sufridos por el Merchant.  
10.2 El Merchant exime a NovaVision de toda responsabilidad relacionada con reclamos de terceros (consumidores, autoridades) por los productos o servicios vendidos en la tienda. En particular, NovaVision no asume responsabilidades de transportista, proveedor o fabricante.  
10.3 El Merchant indemnizará a NovaVision en caso de demandas judiciales o administrativas derivadas de la actividad del Merchant.  

## 11. Suspensión y Terminación
11.1 NovaVision puede suspender temporalmente el acceso al Servicio si detecta uso indebido o impago.  
11.2 Cada parte puede rescindir este contrato con 30 días de preaviso por escrito. Si el Merchant lo hace, su cuenta se desactivará al final del periodo pagado; si lo hace NovaVision por incumplimiento grave, se hará de inmediato sin reembolso.  
11.3 Al término, NovaVision podrá borrar los datos del Merchant tras 60 días si no hay solicitud de migración.

## 12. Cambios en los Términos
12.1 NovaVision puede modificar estos Términos. Notificará cambios significativos al Merchant por email o anuncio en el panel con al menos 30 días de anticipación.  
12.2 El uso continuado del Servicio tras la modificación implicará aceptación de los nuevos términos.

## 13. Ley Aplicable y Jurisdicción
Este contrato se rige por leyes de la República Argentina. En caso de disputa, ambas partes aceptan la jurisdicción de tribunales de CABA, renunciando a cualquier otro fuero.

```
</details>

<details><summary><strong>2. Política de Privacidad de NovaVision</strong></summary>

```markdown
# Política de Privacidad de NovaVision

**Última actualización:** {DATE}  
NovaVision S.R.L. (CUIT {CUIT}) es responsable del tratamiento de datos personales bajo las normas argentinas. Respetamos tu privacidad y cumplimos Ley 25.326 (Habeas Data) y Ley 27.078 (spam).

## 1. Información que Recopilamos
- **Datos del Merchant/Usuario:** Nombre, razón social, CUIT, email, teléfono, dirección, datos de facturación y pago. Se obtienen al registrarse o comprar un plan.  
- **Datos de Clientes de las Tiendas:** La plataforma almacena el nombre, dirección, email y detalles de envío de los compradores finales de cada tienda para procesar órdenes.  
- **Datos de navegación:** Para mejoras de servicio podemos recopilar datos anónimos (tiempo en página, IP, navegador) vía cookies u herramientas de análisis.

## 2. Finalidad y Uso de Datos
- Gestionar la relación contractual con el usuario (registro, soporte, facturación).  
- Prestar el servicio contratado (alojar la tienda, procesar pagos con pasarela Mercado Pago, enviar notificaciones de pedido).  
- Mantener la seguridad del sistema y prevenir fraudes (autenticación, alertas de actividad sospechosa).  
- Cumplir obligaciones legales (almacenar registros contables, fiscales).  
- Enviar comunicaciones comerciales sólo si el usuario lo autorizó expresamente (newsletters con ofertas propias). 

## 3. Base Legal del Tratamiento
- **Ejecución de contrato:** Para brindar el servicio, se requieren los datos básicos del Merchant y sus clientes.  
- **Consentimiento:** Para envíos promocionales y para el uso de cookies de marketing, se solicitará aceptación explícita.  
- **Obligaciones legales:** Conservación de datos fiscales por los plazos tributarios.  

## 4. Destinatarios de Datos
- **Subencargados:** NovaVision comparte datos con proveedores necesarios: hosting (e.g. AWS, Heroku), plataformas de email (por ej. Mailchimp), mensajería SMS/WhatsApp, y con Mercado Pago como pasarela de pago. Ellos tratan los datos solo para los fines de la prestación de esos servicios.  
- **Transferencias Internacionales:** El almacenamiento de datos (servidores) puede ser fuera de Argentina. Nos aseguramos de que estos terceros ofrezcan niveles adecuados de protección o utilizamos cláusulas contractuales estándar.  
- **Autoridades:** Podemos revelar datos a autoridades competentes si la ley lo exige (por ejemplo, solicitudes judiciales por delitos informáticos). 

## 5. Derechos de los Titulares (ARCO)
Los titulares (merchants o compradores) pueden solicitar: acceso, rectificación, cancelación u oposición de sus datos. Para ejercerlos, pueden escribir a {LEGAL_EMAIL} o contactarnos por soporte. Responderemos gratuitamente dentro de los 10 días hábiles según Ley 25.326. 

## 6. Cookies y Tecnologías Similares
- **Cookies esenciales:** Las usamos para mantener la sesión iniciada, idioma seleccionado y carrito de compras. Son necesarias para el funcionamiento básico y no requieren consentimiento explícito.  
- **Cookies analíticas y de marketing:** No se usan actualmente, pero si se integran en el futuro (p.ej. Google Analytics), informaremos y solicitaremos consentimiento.  
- **Gestión:** El usuario puede configurar su navegador para rechazar cookies no esenciales. Sin embargo, el Servicio podría no funcionar correctamente sin ellas.

## 7. Seguridad de los Datos
Adoptamos medidas técnicas y organizativas razonables: conexiones cifradas (HTTPS), bases de datos seguras, actualizaciones periódicas y acceso restringido. Nuestro personal con acceso está obligado a confidencialidad. Aun así, ningún método es 100% infalible; en caso de brecha de seguridad crítica, notificaremos a los afectados según buenas prácticas.

## 8. Conservación de Datos
Los datos de usuarios se conservarán mientras exista la relación comercial y hasta 5 años después (para cumplir con obligaciones legales). Después de ese plazo, los datos se eliminarán o anonimizarán, salvo que se requiera por ley su conservación.

## 9. Menores
NovaVision no está dirigido a menores. No recolectamos conscientemente datos personales de menores de 16 años. En caso de que sepamos que lo hicimos sin consentimiento parental, eliminaremos la información.

## 10. Cambios en esta Política
Podemos actualizar esta política. Publicaremos la versión más reciente en nuestro sitio y notificaremos por email a los merchants registrados sobre cambios sustanciales. 

**Contacto:** Para consultas sobre privacidad, escribir a {LEGAL_EMAIL}. 

```
</details>

<details><summary><strong>3. Acuerdo de Tratamiento de Datos (DPA)</strong></summary>

```markdown
# Acuerdo de Tratamiento de Datos (DPA) – NovaVision

Entre **Responsable** (el Merchant, propietario de la tienda) y **Encargado** (NovaVision S.R.L.) se celebra este Acuerdo para regular el tratamiento de datos personales. Se aplica conforme a la Ley 25.326 y su reglamentación.

## 1. Roles
- **Responsable:** el Merchant que decide cómo y para qué se tratarán los datos de sus clientes.  
- **Encargado:** NovaVision, que procesa datos personales por cuenta del Merchant al operar la plataforma.

## 2. Datos Personales Procesados
- **Datos de Clientes (Titulares):** nombre, apellido, dirección, email, teléfono, datos de pago parciales (solo lo necesario para enviar pasarela), historial de pedidos.  
- **Datos del Responsable:** nombre, CUIT, datos de contacto del merchant.

## 3. Finalidad del Tratamiento
NovaVision tratará los datos únicamente para ofrecer el servicio contratado: gestionar la cuenta del merchant, procesar y enviar pedidos, integrarse con pasarelas de pago y enviar comunicaciones relacionadas con el servicio. No se utilizarán para fines propios de NovaVision sin autorización.

## 4. Obligaciones del Encargado
4.1 Tratar los datos conforme a las instrucciones documentadas del Responsable.  
4.2 Garantizar confidencialidad: el personal y subcontratistas estarán bajo obligación de secreto.  
4.3 Implementar medidas de seguridad técnicas y organizativas (encriptación, cortafuegos, controles de acceso) para proteger los datos【34†L240-L249】.  
4.4 No revelar datos a terceros sin autorización, salvo para prestar el servicio o cumplir orden judicial.  
4.5 Asistir al Responsable en el ejercicio de derechos ARCO: notificar de inmediato y ayudar a responder solicitudes de acceso, rectificación o eliminación de datos de parte de los titulares.  
4.6 Avisar sin demora al Responsable si detecta una violación de seguridad que afecte los datos.  

## 5. Subprocesadores
NovaVision podrá contratar subprocesadores (p.ej. AWS para hosting, proveedores de análisis, servicios de emailing). Incluirá cláusulas contractuales de confidencialidad y seguridad con ellos. El merchant será informado en caso de incorporación de nuevos subprocesadores.

## 6. Transferencias Internacionales
Los datos de titular pueden almacenarse en servidores fuera de Argentina. NovaVision asegura que dichos proveedores cumplen estándares internacionales de protección (por ejemplo, nivel adecuado de la UE, o mecanismos legales como Cláusulas Tipo).

## 7. Duración
Este DPA estará vigente mientras el servicio esté activo y por los plazos que exija la ley posterior (mínimo 5 años para efectos administrativos). A la finalización, NovaVision devolverá o destruirá los datos según instrucciones, salvo retención necesaria por obligaciones legales.

## 8. Responsabilidad
El Encargado será responsable ante la AAIP y el Responsable por daños causados por incumplimientos del presente Acuerdo. El Responsable retiene la responsabilidad principal ante titulares.

```
</details>

<details><summary><strong>4. Política de Uso Aceptable (AUP) y Rubros Prohibidos</strong></summary>

```markdown
# Política de Uso Aceptable (AUP)

NovaVision provee infraestructura para tiendas online. Para proteger la plataforma y a sus usuarios, el Merchant se compromete a:

- **Usos permitidos:** Comercializar productos lícitos y permitidos, publicar contenido veraz relacionado con su negocio y brindar atención adecuada al cliente.  
- **Usos prohibidos:** Se prohíbe expresamente usar la plataforma para:  
  - Venta o publicidad de bienes o servicios ilegales (drogas ilegales, armas sin permiso, falsificaciones).  
  - Contenido con pornografía infantil o con difamación/discriminación.  
  - Infracción de derechos de propiedad intelectual de terceros (software pirateado, música/films sin licencia, copias no autorizadas).  
  - Actividades de fraude, phishing, spam o malware.  
  - Juegos de azar o loterías no autorizadas legalmente.  

- **Consecuencias de violación:** NovaVision puede suspender o eliminar inmediatamente cualquier tienda que infrinja esta política. El Merchant indemnizará a NovaVision por daños o multas resultantes de su incumplimiento.

```
</details>

<details><summary><strong>5. Política de Soporte/SLA</strong></summary>

```markdown
# Política de Soporte y Nivel de Servicio (SLA)

- **Horario de Soporte:** Lunes a viernes de 9:00 a 18:00 (Argentina), vía email y sistema de tickets. Tiempo de respuesta inicial: máximo 24 horas.  
- **Tiempo de Resolución:** Consultas básicas en hasta 3 días hábiles; incidentes críticos serán escalados inmediatamente.  
- **Disponibilidad:** Meta de 99% de uptime mensual. No garantizamos 100%: mantenimientos o eventos fuera de nuestro control pueden causar interrupciones.  
- **Notificación de Mantenimiento:** Se avisará con 48h de antelación los mantenimientos programados que afecten más de 2 horas.  
- **Exclusiones:** No se garantiza soporte para integraciones externas no autorizadas ni corrección de datos ingresados erróneamente por el merchant.  
- **Reclamos:** El merchant puede reportar incidencias críticas para evaluación de compensaciones (por ej. créditos en factura).

```
</details>

<details><summary><strong>6. Política de Cancelación / Suscripción</strong></summary>

```markdown
# Política de Suscripción y Cancelación

- **Planes y Facturación:** Los planes se cobran por adelantado según lo seleccionado (mensual/anual). Los precios son fijos durante cada período.  
- **Renovación Automática:** Salvo aviso previo (5 días antes del vencimiento), la suscripción se renueva automáticamente.  
- **Cancelación por el Merchant:** El merchant puede cancelar en cualquier momento desde el panel. La cancelación tendrá efecto al fin del período ya pagado. No hay reembolso por cancelación anticipada.  
- **Prueba Gratuita:** Si se ofrece trial, la cancelación antes de su fin evitará el cobro del primer período. No hay extendida automática tras el trial.  
- **Botón de Baja:** Conforme normativa, el panel incluye un “Botón de Baja de Servicio”【50†L216-L225】. Al usarlo, el sistema confirmará con código y procederá a cancelar la cuenta en 24h【50†L227-L234】.  
- **Deudas Pendientes:** Al cancelar, el merchant debe saldar cualquier cuota pendiente. El acceso al panel se retendrá hasta la resolución de adeudos.

```
</details>

<details><summary><strong>7. Términos de la Tienda (Template para el Merchant)</strong></summary>

```markdown
# Términos y Condiciones de la Tienda {slug}.novavision.lat

**Comerciante:** {MERCHANT_NAME} (CUIT {MERCHANT_CUIT}), con domicilio en {MERCHANT_ADDRESS}. Contacto: {MERCHANT_EMAIL}, Tel: {MERCHANT_PHONE}.

## 1. Venta de Productos
{MERCHANT_NAME} es responsable de la oferta y venta de los productos publicados en esta tienda. Al completar una compra, el Cliente acuerda comprar del comerciante.

## 2. Precios e Impuestos
Los precios mostrados incluyen IVA y cualquier impuesto aplicable. Posibles costos de envío se informan al finalizar la compra. El comercio es responsable de la facturación (factura electrónica) al cliente final.

## 3. Formas de Pago
Se aceptan las siguientes formas de pago: tarjetas de crédito/débito y Mercado Pago. El procesamiento de pagos lo realiza Mercado Pago; el comercio no manipula datos de tarjeta.

## 4. Envíos y Entregas
El comerciante despacha los productos dentro de {X} días hábiles tras la compra. Los plazos de entrega estimados se comunicaran al final del proceso de compra. Los gastos y métodos de envío serán seleccionados por el cliente, salvo oferta distinta.

## 5. Devoluciones y Reembolsos
- **Derecho de Arrepentimiento:** Conforme ley【52†L625-L633】, usted puede revocar la compra dentro de los 10 días corridos desde la entrega del producto, notificándolo al comerciante sin incurrir en penalidad.  
- **Proceso de devolución:** Para ejercerlo, debe devolver el producto en buenas condiciones (salvo fallas de fábrica) al comercio. El comerciante reembolsará el precio del producto más los gastos de envío asociados (según ley).  
- **Excepciones:** No aplican devoluciones a bienes personalizados, perecederos o consumidos, o conforme excepciones previstas en el art. 1.116 del Código Civil.  

## 6. Garantías
- El comercio es responsable por cualquier vicio o defecto de los productos vendidos. Usted tiene derecho a reparación, cambio o devolución del dinero según corresponda, sin costo adicional【52†L625-L633】.  
- El comercio puede ofrecer garantía comercial adicional (indicada en la ficha del producto).  

## 7. Uso de Datos Personales
Al comprar, usted autoriza al comercio a usar sus datos personales para procesar esta transacción y enviar comunicaciones relacionadas (factura, seguimiento del envío). El uso de datos del cliente está sujeto a la Política de Privacidad del comercio (disponible en el sitio). NovaVision como plataforma también puede usar datos de forma anónima para mejorar el servicio, pero no accede a información de pago.

## 8. Atención al Cliente
Para consultas o reclamos, contáctenos en {MERCHANT_EMAIL} o {MERCHANT_PHONE}. Nos comprometemos a responder en breve. Para asistencia técnica de la plataforma, puede contactar a NovaVision (info en nuestro sitio web).

## 9. Exclusión de NovaVision
NovaVision S.R.L. es únicamente la proveedora de plataforma tecnológica. No participa en la entrega, envío ni calidad de los productos. Cualquier disputa o problema con su compra debe resolverlo directamente con {MERCHANT_NAME}. NovaVision no puede procesar devoluciones ni reembolsos por usted ni interceder en la transacción, salvo para brindar información de registro (pedido, pagos, etc.) si fuese necesaria.

## 10. Legislación Aplicable
Estos términos se rigen por la Ley de Defensa del Consumidor de Argentina y demás normativa aplicable. En caso de conflicto, usted podrá acudir a la oficina de defensa del consumidor más cercana o ejercer sus derechos ante la justicia correspondiente.

```
</details>

<details><summary><strong>8. Aviso Legal / Disclaimer (Footer de Storefront)</strong></summary>

```markdown
© {YEAR} NovaVision S.R.L. – Aviso legal: NovaVision es proveedor de la plataforma de tiendas online. Los productos vendidos en esta tienda son oferta exclusiva del comerciante (nombre: {MERCHANT_NAME}). NovaVision **no administra pagos ni participa en la transacción comercial**; sólo brinda el servicio técnico. Cualquier consulta sobre productos o pedidos debe dirigirse directamente al comerciante. 

```
</details>

## Checklist técnico-legal (implementación)

- **Formularios y checkboxes obligatorios:**  
  - **Onboarding Merchant:** Incluir checkbox de aceptación de Términos y Política de Privacidad antes de crear la cuenta (ya presente en código). Colocar un texto breve junto al checkbox indicando versionado (ej. “Acepto Términos y Condiciones (v{TERMS_VERSION})”).  
  - **Checkout Buyer:** Integrar, antes de procesar el pago, un checkbox de aceptación de los *Términos de la Tienda* (plantilla 7) con enlace. Mostrar nota sobre derecho de devolución.  
  - **Consentimiento de Datos:** Cualquier formulario de captura de email/contacto en la home debe incluir casilla de consentimiento para comunicaciones (Ley 27.078).

- **Prueba de aceptación:** Registrar en logs todas las aceptaciones: versión del documento, fecha/hora, dirección IP, user_id (si aplicable) y tenant_id. El código actual guarda la versión y timestamp local. Hay que complementar guardando estos datos en el backend al aceptar, vinculándolos al registro de sesión del usuario (por ejemplo, en la llamada a `accept-terms` incluir IP y `state.builderToken` si es identificador). Esto crea evidencia inmutable de consentimiento【34†L194-L202】.  

- **Retención de logs:** Conservar los registros de aceptación junto con otros logs clave por al menos 5 años (según obligación de archivo contable). Guardar también historial de cambios de plan, pagos, soporte y acciones de los usuarios en el admin (edición de productos, precios, etc.) para auditar disputas.  

- **Botones de acción en UI:**  
  - **Botón de Arrepentimiento (comprador):** Implementar en la tienda, accesible desde la primera página de usuario y en correos de confirmación. Debe permitir al comprador iniciar el proceso de devolución de forma simple【50†L162-L171】.  
  - **Botón de Baja (merchant):** En el panel de configuración de la cuenta del merchant, colocar enlace “Dar de baja mi cuenta” (esencial para planes de suscripción). Al hacer clic, confirmar cancelación y emitir un código de trámite, según Disp. 954/2025【50†L216-L225】【50†L227-L234】.  
  - **Aviso de aceptación:** En step 11, ya se muestra “Tu tienda será revisada…”; añadir texto que mencione la versión de términos aceptada y un enlace a la política de privacidad o a la página de T&C completa (aunque ya está el scroll).  

- **Logs de disputa y evidencia:**  
  - **Reclamos de pago (chargebacks):** Mantener registros de pagos (confirmaciones de Mercado Pago), envíos (tracking) y comunicación con el cliente. Tener plantillas de respuesta con indicación de dónde enviar pruebas (ticket).  
  - **Fraude y contenido ilegal:** Sistema para recibir denuncias de usuarios o propietarios de IP: canal de contacto visible y proceso interno documentado (tickets).  
  - **Actualizaciones documentales:** Versionar y publicar fechas de actualización de T&C y políticas. En el código, ya se ve VERSION; asegúrese de actualizar `TERMS_VERSION` con cada cambio y anotar fecha.

- **Seguridad mínima:**  
  - Validar que cada merchant solo pueda acceder a su tienda (multi-tenant isolation).  
  - Imponer contraseñas robustas y sugerir (u obligar) 2FA. En la próxima iteración, se puede habilitar autenticación MFA vía Google.  
  - Revisar configuración CORS y headers de seguridad en el backend (por ej. Content Security Policy).  
  - Auditar el código para evitar vulnerabilidades (inyección, XSS en campos de tiendas, etc.).  

- **Textos exactos de disclaimers (UI):**  
  - **Pantalla principal (marketing):** Incluir texto de aviso legal en pie de página: “*NovaVision™ es marca registrada. Los planes y características están sujetos a Términos y Precios publicados. Es posible que ciertas funcionalidades dependan de servicios de terceros (p.ej. pasarelas de pago). Ver Términos de Servicio para más detalles.*”  
  - **Onboarding merchant:** Junto al botón de registro, agregar nota corta: “*Acepto los Términos de NovaVision (v{TERMS_VERSION}) y la Política de Privacidad*”.  
  - **Checkout tienda:** Mostrar mensaje: “*Revisa las Condiciones de Venta antes de finalizar. Recuerda que tienes 10 días para arrepentirte de tu compra según la ley.*” con link a términos de la tienda.  

- **Flujos de disputa/documentación:** Documentar un procedimiento interno para tratar: (a) contracargos: pasos y contactos en Mercado Pago; (b) denuncias de infracción: formulario de contacto legal; (c) consultas de consumidores: tipificar tickets y notificar al merchant.  

- **Cumplimiento GDPR/Leyes extranjeros:** Si hay clientes fuera de AR, adaptar textos (Base legal, derechos adicionales). En Privacy, agregar cláusula de transferencia internacional con mención de cláusulas estándar si aplica.  
- **Registro de Base de Datos:** Si corresponde (por volumen de datos personales), registrar la base de datos en la Dirección Nacional de Protección de Datos (DNPDP).  

## Matriz de riesgo y mitigaciones

| Riesgo / Escenario                                | Probabilidad | Impacto | Mitigación contractual                                    | Mitigación de producto (UX/controles)                                          | Evidencia a guardar                 | Riesgo residual |
|---------------------------------------------------|--------------|---------|----------------------------------------------------------|------------------------------------------------------------------------------|-------------------------------------|-----------------|
| **Contenido ilegal o infractor**                   | Medio        | Alto    | Prohibido en AUP; Merchant indemniza a NovaVision.       | Moderación previa (revisión de tienda nueva). Botón de denuncia visible en tienda. | Logs de productos subidos, denuncias recibidas. | Medio (pueden evadir controles). |
| **Incumplimiento de info obligatoria al consumidor** | Medio        | Medio   | Cláusula en Términos merchant indicando responsabilidad del vendedor (Art. 4 LDC)【58†L119-L127】. | Formularios obligatorios para completar datos (marcar "acepto" info de precio final). | Captura de pantalla de ficha de producto, registro de meta-datos. | Bajo (obligación contractual). |
| **Error en cobros / facturación**                  | Medio        | Medio   | Merchant responsable por datos de facturación. T&C establecen no reembolsos fuera de políticas. | Validar campos de facturación. Enviar confirmación detallada por email.   | Registros de factura emitida, emails de aviso.       | Bajo (suficiente documentación). |
| **Contracargos bancarios**                         | Medio-Alto   | Medio   | Merchant asume contenciosos. NovaVision exime responsabilidad. | Alertar merchant de cada cargo. Facilitar uploads de prueba en panel.       | Comprobantes de entrega, logs de pago MP.            | Medio (depende de resolución de pasarela). |
| **Fallas de plataforma / downtime**                | Medio        | Alto    | SLA limita compensación. Clausula de fuerza mayor.         | Infra redundante (backups, balanceo). Monitor de uptime + alertas.         | Registros de uptime, reporte de incidentes.        | Bajo (con buena infra). |
| **Falsa representación de NovaVision como vendedor** | Bajo        | Medio   | Disclaimer y Términos enfatizan que NovaVision solo provee plataforma. | Texto visible “Aviso legal” en tiendas y home. Entrenamiento de soporte para aclarar dudas. | Captura de avisos legales, logs de QA del sitio.      | Bajo (bien comunicado). |
| **Violación de datos personales / brecha**         | Medio        | Alto    | Limitación de responsabilidad si se siguen medidas razonables. | Encriptación, firewall, escaneos de vulnerabilidades periódicos.           | Registros de accesos, reportes de seguridad.       | Medio (semitransparencia posible). |
| **Cláusulas abusivas**                             | Bajo         | Alto    | No permitido por ley. Términos redactados contra abuso (Art. 37 LDC)【52†L714-L723】. | Validaciones al crear T&C de tienda, plantillas cerradas.                   | Versión aceptada de T&C, diligencias legales.        | Bajo (ley protege al consumidor). |

