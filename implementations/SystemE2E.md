Configuración del repositorio E2E novavision-e2e con Playwright (TypeScript)
Esta guía detalla paso a paso cómo crear y configurar un nuevo repositorio de pruebas end-to-end (E2E) llamado novavision-e2e, usando Playwright con TypeScript. El objetivo es construir un framework de pruebas sólido y escalable, basado en los flujos reales de onboarding, tienda y compra definidos en la documentación. Se organizarán los tests y los recursos (páginas, datos, utilitarios) de forma modular
. Además, la configuración inicial será para ejecuciones locales con reporte HTML. A continuación se describen los pasos generales y se sugiere un prompt específico para la IA en cada etapa, de modo que consulte siempre la documentación y los flujos reales al generar los tests.
Paso 1: Crear el repositorio novavision-e2e
Crea un nuevo repositorio en el sistema de control de versiones (por ejemplo, GitHub) con el nombre novavision-e2e. Inicializa el proyecto con un README.md, la rama principal (main) y, si es necesario, archivos básicos como .gitignore o plantillas de licencia. Este repositorio será exclusivo para las pruebas E2E y servirá como base de código independiente del desarrollo de la aplicación. Prompt (IA): “Crea un repositorio en GitHub llamado novavision-e2e. Inicializa el repositorio con un README.md explicando el objetivo (pruebas E2E con Playwright), agrega un .gitignore para Node.js y configura la rama principal como main.”
Paso 2: Inicializar el proyecto con Node, TypeScript y Playwright
Dentro del repositorio, configura el entorno de Node.js y TypeScript. Ejecuta npm init -y para crear un package.json. Luego instala Playwright y sus herramientas de prueba: npm install -D @playwright/test @playwright/cli. Playwright soporta TypeScript de forma nativa
, por lo que basta con escribir los tests en .ts. Corre npx playwright install para descargar los navegadores necesarios. Crea un archivo tsconfig.json en la raíz (o en una carpeta tests/) configurando las opciones mínimas para TypeScript. Por ejemplo, puedes usar una tsconfig.json que especifique los paths o baseUrl para facilitar importaciones
. En resumen, TypeScript y Playwright trabajarán juntos sin pasos adicionales, aunque se recomienda ejecutar el compilador (tsc) en paralelo para verificar tipos durante el desarrollo
. Prompt (IA): “En el repositorio novavision-e2e, ejecuta npm init -y y luego npm install -D @playwright/test @playwright/cli typescript. Después, crea un archivo tsconfig.json básico y corre npx playwright install para instalar los navegadores. Configura Playwright para que use ese tsconfig.json (o uno en la carpeta de tests) según la documentación oficial
.”
Paso 3: Definir la estructura de carpetas y archivos
Organiza el proyecto en carpetas claras y modulares. Una estructura recomendada es:
novavision-e2e/
├── tests/            # Archivos de prueba (.spec.ts)
├── pages/            # Page Objects o Feature Objects (TS classes)
├── fixtures/         # Ficheros de configuración de contexto (p. ej. setup de login)
├── utils/            # Funciones o comandos reutilizables (p. ej. manejo de dropdown)
├── data/             # Datos de prueba (JSON, CSV) o mocks
├── playwright.config.ts
├── tsconfig.json
└── package.json
Este diseño separa claramente tests, objetos de página, utilitarios y datos
. Cada carpeta cumple una sola responsabilidad (por ejemplo, pages/ contiene clases con métodos y selectores, tests/ contiene los archivos de prueba), lo cual facilita el mantenimiento y escalado
. Un ejemplo de Page Object simplificado sería una clase TypeScript en pages/OnboardingPage.ts que encapsula las interacciones de la pantalla de onboarding
. Emplear este patrón (o “Feature Object”) mejora la legibilidad y evita repetir selectores en cada test
. Prompt (IA): “Crea la siguiente estructura de carpetas en el proyecto: tests/, pages/, utils/, fixtures/, data/. Dentro de pages/, agrega archivos TypeScript vacíos para cada área: por ejemplo, OnboardingPage.ts, StorePage.ts, CheckoutPage.ts. Genera un playwright.config.ts en la raíz. Explica con un comentario que esta estructura sigue las mejores prácticas (carpetas separadas para tests, páginas y utilidades)
.”
Paso 4: Revisar la documentación de los flujos reales
Antes de escribir tests, analiza los flujos de usuario definidos en la documentación (onboarding, tienda/catálogo, compra). Revisa los requisitos y pasos de cada flujo en los documentos internos (por ejemplo, en Notion o la Wiki de la empresa) para identificar las acciones clave: formularios a completar, páginas a navegar, casos exitosos y de error. Es importante extraer de manera precisa qué debe verificar cada test, basándose en el comportamiento visible del usuario
. Por ejemplo, en el flujo de onboarding, identifica la secuencia de registro (nombre de usuario, email, contraseña, etc.) y las pantallas de validación. En el flujo de compra, determina los pasos de búsqueda de un producto, agregar al carrito y confirmar la orden.
Prompt (IA): “Lee la documentación interna del proyecto sobre el flujo de onboarding. Resume los pasos principales que realiza el usuario (p.ej. completar formulario de registro con nombre y contraseña, validación de email) y los resultados esperados en cada paso.”
Prompt (IA): “Luego, haz lo mismo con el flujo de tienda (catálogo o productos): enumera cómo el usuario navega, selecciona y visualiza productos.”
Prompt (IA): “Finalmente, extrae los pasos clave del flujo de compra/checkout: por ejemplo, agregar un producto al carrito, completar el pago, y recibir confirmación. Describe cada paso en términos de acción del usuario y comportamiento de la aplicación.”
Paso 5: Diseñar casos de prueba basados en los flujos (patrón AAA)
Con la información de los flujos, crea descripciones detalladas de los casos de prueba (scenarios) en formato AAA (Arrange-Act-Assert). Cada caso debe enfocarse en el comportamiento visible para el usuario
 y estar aislado de los demás
. Por ejemplo, un caso podría ser “User Registration: Arrange (abrir página de registro), Act (llenar datos de usuario y enviar), Assert (verificar que aparece mensaje de éxito)”. Documenta varios escenarios: casos positivos (datos válidos) y negativos (errores de validación). Por cada escenario, lista los pasos de prueba y los resultados esperados. Es recomendable agrupar los tests por funcionalidad usando descriptores claros (p.ej. test.describe("Onboarding")). Prompt (IA): “Basándote en el flujo de onboarding, escribe 2–3 casos de prueba en formato Arrange-Act-Assert. Por ejemplo: describe cómo configurar los datos (Arrange), qué acción realiza el usuario (Act) y qué debe verificarse (Assert). Haz lo mismo para el flujo de compra (añadir al carrito, checkout). Usa nombres de test descriptivos (por ejemplo, ‘registro-usuario-exitoso’, ‘registro-usuario-con-errores’).”
Paso 6: Implementar objetos de página (Page Objects)
Crea clases de tipo Page Object (o Feature Object) para encapsular la interacción con la aplicación. Cada clase en pages/ representará una pantalla o conjunto de funcionalidades (p.ej. OnboardingPage, ProductsPage, CheckoutPage). En estas clases, define selectores usando locators de Playwright (page.getByRole, page.locator, etc.)
 y métodos que realicen acciones (por ejemplo, async fillForm(data), async clickSubmit()). Esto centraliza los selectores y evita repetirlos en cada test
. Siguiendo las mejores prácticas, usa atributos legibles (roles o textos) para los locators cuando sea posible
.
Prompt (IA): “Crea un archivo pages/OnboardingPage.ts con una clase OnboardingPage. Incluye locators para cada campo del formulario de registro (por ejemplo, nombre, email, contraseña) usando page.getByLabel o getByRole, y un método async registerUser(data) que llene los campos y presione el botón de envío.”
Prompt (IA): “De manera similar, crea pages/CheckoutPage.ts con una clase CheckoutPage. Agrega locators y métodos para las acciones de compra (por ejemplo, addItemToCart(), proceedToCheckout(), enterPaymentInfo()). Usa métodos descriptivos para cada operación de usuario.”
Paso 7: Escribir tests E2E en Playwright con TypeScript
Ahora implementa los tests reales en tests/. Cada test importará los objetos de página creados y seguirá el patrón AAA. Ejemplo de estructura en un archivo tests/onboarding.spec.ts:
import { test, expect } from '@playwright/test';
import { OnboardingPage } from '../pages/OnboardingPage';

test.describe('Onboarding', () => {
  test('registro-usuario-exitoso', async ({ page }) => {
    const onboarding = new OnboardingPage(page); // Arrange
    await onboarding.goto();                    // Arrange: abrir página de registro
    await onboarding.registerUser({ ... });     // Act: llenar formulario y enviar
    // Assert: verificar mensaje de bienvenida o redirección esperada
    await expect(onboarding.successMessage).toBeVisible();
  });
});
Siguiendo la guía oficial, cada test debe ser independiente (usar hooks beforeEach si es necesario, o fixtures personalizados)
. Por ejemplo, puedes usar un fixture de Playwright para iniciar sesión previamente si varios tests requieren autenticación. Usa selectores confiables y evita codificar tiempos de espera manuales, ya que Playwright gestiona esperas automáticamente con los locators
. Organiza los archivos de prueba por funcionalidad (por ejemplo, tests/onboarding/registro.spec.ts, tests/compra/checkout.spec.ts) para mantener la estructura clara.
Prompt (IA): “Escribe el contenido de tests/onboarding.spec.ts que utilice la clase OnboardingPage. Incluye al menos un test que verifique el registro exitoso usando el flujo AAA mostrado, y otro que valide un error (p.ej. email inválido). Usa expect para las aserciones.”
Prompt (IA): “Escribe otro archivo tests/compra.spec.ts con un test que agregue un producto al carrito y complete la compra usando el objeto CheckoutPage. Sigue el patrón AAA: configuras la página, realizas las acciones y verificas un mensaje de confirmación de orden.”
Paso 8: Configurar el orquestador de pruebas (run script)
Para ejecutar los tests de forma sencilla, crea un script de orquestación. Dado que la prioridad es la simplicidad y facilidad de uso para un agente, podemos usar un script TypeScript (por ejemplo, run-tests.ts) que lance Playwright desde Node. En este script, se podría usar child_process para llamar a npx playwright test --reporter=html. Por ejemplo:
import { spawnSync } from 'child_process';
const result = spawnSync('npx', ['playwright', 'test', '--reporter=html'], { stdio: 'inherit' });
process.exit(result.status);
También es útil añadir un script en package.json como "test": "npx playwright test". En el futuro se podría crear un CLI más elaborado (como un comando qa run shopper), pero por ahora un script simple es suficiente. Esto cumple el requisito de ser automático, estable y fácil de entender
. Prompt (IA): “Crea un archivo run-tests.ts que ejecute los tests de Playwright. Por ejemplo, utiliza child_process.spawnSync para correr npx playwright test --reporter=html. Asegúrate de propagar el código de salida del comando. Además, actualiza package.json agregando un script "test": "ts-node run-tests.ts".”
Paso 9: Configurar reportes e informes de prueba
Para generar reportes legibles tras la ejecución local, usa el reporter HTML integrado de Playwright. Esto crea una carpeta playwright-report/ con un resumen interactivo
. En playwright.config.ts, configura el reporter de esta manera:
import { defineConfig } from '@playwright/test';
export default defineConfig({
  reporter: [['html', { open: 'never' }]]
});
Luego, al ejecutar npm test o npx playwright test, los resultados se guardarán en playwright-report/. Para ver el reporte, usa npx playwright show-report. De este modo obtendrás gráficos y pasos detallados de cada test. También puedes configurar reportes adicionales (JUnit, JSON) si en el futuro se integra CI. El uso del reporter HTML facilita la revisión de resultados locales
. Prompt (IA): “Configura el archivo playwright.config.ts para usar el reporter HTML (reporter: [['html', { open: 'never' }]]). Explica cómo ejecutar los tests (npm test) y luego abrir el reporte con npx playwright show-report para inspeccionar los resultados.”
Paso 10: Documentación de ejecución y uso del framework
Finalmente, documenta cómo usar este repositorio. En el README.md, agrega instrucciones claras: cómo instalar dependencias (npm install), cómo correr los tests (npm test o npx playwright test), y dónde encontrar los reportes (p.ej. playwright-report/index.html). También explica la organización de carpetas (qué va en pages/, utils/, etc.) y las convenciones de nombres de tests. Esto sirve como guía para cualquier miembro del equipo. Puedes incluir ejemplos de comandos útiles (como filtrar tests con tags o ejecutar tests específicos). Una buena documentación asegura que otros entiendan el framework y cómo consultarlo. Prompt (IA): “Escribe un README.md que incluya: descripción del propósito (novavision-e2e con Playwright TS), pasos para instalar (Node, dependencias), comandos para ejecutar tests y generar reportes, y breve explicación de la estructura de carpetas (tests, pages, utils, etc.). Menciona que las pruebas se basan en los flujos de onboarding, tienda y compra definidos en la documentación interna.” <p>Con estos pasos y prompts, la IA tendrá una guía clara para configurar y poblar el repositorio de pruebas E2E, siempre refiriéndose a la documentación y flujos reales para generar casos y guías de implementación. Las referencias usadas destacan buenas prácticas de Playwright (arquitectura modular, uso de TypeScript nativo, patrones AAA, page objects y reportes):contentReference[oaicite:27]{index=27}:contentReference[oaicite:28]{index=28}:contentReference[oaicite:29]{index=29}:contentReference[oaicite:30]{index=30}:contentReference[oaicite:31]{index=31}:contentReference[oaicite:32]{index=32}.</p>
Citas

Playwright Test Framework Structure: Best Practices for Scalability | by Divya Kandpal | Medium

https://medium.com/@divyakandpal93/playwright-test-framework-structure-best-practices-for-scalability-eddf6232593d

Playwright Test Framework Structure: Best Practices for Scalability | by Divya Kandpal | Medium

https://medium.com/@divyakandpal93/playwright-test-framework-structure-best-practices-for-scalability-eddf6232593d

TypeScript | Playwright

https://playwright.dev/docs/test-typescript

TypeScript | Playwright

https://playwright.dev/docs/test-typescript

A Simple and Effective E2E Test Architecture with Playwright and TypeScript | by Denis Skvortsov | Medium

https://medium.com/@denisskvrtsv/a-simple-and-effective-e2e-test-architecture-with-playwright-and-typescript-913c62ce0e89

Page object models | Playwright

https://playwright.dev/docs/pom

Best Practices | Playwright

https://playwright.dev/docs/best-practices

Best Practices | Playwright

https://playwright.dev/docs/best-practices

Best Practices | Playwright

https://playwright.dev/docs/best-practices

A Simple and Effective E2E Test Architecture with Playwright and TypeScript | by Denis Skvortsov | Medium

https://medium.com/@denisskvrtsv/a-simple-and-effective-e2e-test-architecture-with-playwright-and-typescript-913c62ce0e89

A Simple and Effective E2E Test Architecture with Playwright and TypeScript | by Denis Skvortsov | Medium

https://medium.com/@denisskvrtsv/a-simple-and-effective-e2e-test-architecture-with-playwright-and-typescript-913c62ce0e89

Reporters | Playwright

https://playwright.dev/docs/test-reporters
Todas las fuentes

medium