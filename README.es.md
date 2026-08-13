# SimPilot

Traducciones: [English](README.md) | [日本語](README.ja.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | **Español** | [한국어](README.ko.md) | [Português do Brasil](README.pt-BR.md)

SimPilot es un conjunto de agent skills para pruebas y verificación en iOS Simulator, impulsado por solicitudes en lenguaje natural desde Claude Code o Codex.

Solo se traduce el README de nivel superior. Los skill docs y el código siguen en inglés.

## Qué hace

- **`/sipi-test`**: automatización de pruebas de UI y de estados adversos en iOS Simulator. El skill convierte la intención en lenguaje natural en especificaciones JSON v2 explícitas y luego `sipi run-test` / `sipi run-suite` las ejecuta con un harness determinista. Las pruebas guardadas pueden controlar permisos, deep links, notificaciones push, ubicación, apariencia, Dynamic Type, Increase Contrast, Face ID / Touch ID, el resto de ajustes de apariencia de accesibilidad, el entorno de lanzamiento y un proveedor de condiciones de red configurado explícitamente.
- **`/sipi-verify`**: verificación posterior a la implementación. Confirma que una función o un arreglo funciona correctamente después de cambios en el código.

Los resultados se guardan en `.simpilot/` con informes HTML que se pueden abrir en el navegador.

## Requisitos previos

- macOS 15 o posterior
- Xcode 26 o posterior: necesario en **tiempo de ejecución** para controlar el Simulator (SimPilot carga los private Simulator frameworks de Xcode). No hace falta para instalar. Xcode 27 o posterior habilita además Face ID / Touch ID y los ajustes de apariencia de accesibilidad, que pasan por `xcrun devicectl`.
- [Claude Code](https://claude.com/claude-code) o Codex

## Instalación

SimPilot se distribuye como un único binario `sipi` con los skills incorporados. Se instala con un solo comando:

```bash
curl -fsSL https://raw.githubusercontent.com/hmhv/SimPilot/main/install.sh | bash
```

El instalador descarga el binario `sipi` precompilado y luego `sipi` registra los skills incorporados `sipi-common` / `sipi-test` / `sipi-verify` en:

- Claude Code (`~/.claude/skills/`)
- Codex (`~/.agents/skills/`)

Verifica las capacidades del simulador con `sipi doctor`.

Para actualizar o desinstalar:

```bash
sipi update      # descarga el sipi más reciente desde GitHub Releases y actualiza los skills
sipi uninstall   # elimina los skills, la metadata de instalación y el binario sipi
```

## Inicio rápido

En tu proyecto de app iOS:

- Claude Code: usa slash commands como `/sipi-test`
- Codex: menciona el skill de forma natural, por ejemplo `Use the sipi-test skill to ...`

**Pruebas:**
```text
/sipi-test Crea una prueba para cambiar entre las pestañas de inicio y ajustes
Use the sipi-test skill to create a test for switching between the home and settings tabs
```

En el primer uso, SimPilot detecta tu proyecto, crea `.simpilot/config.json` y prepara la sesión del simulator.

**Verificación:**
```text
/sipi-verify Comprueba que el nuevo flujo de inicio de sesión funciona en el simulator
Use the sipi-verify skill to verify the dark mode fix looks correct
```

## Tareas comunes

**Crear pruebas:**
```text
/sipi-test Crea una prueba para cambiar pestañas en la pantalla principal
/sipi-test Crea una prueba que inicie sesión y abra ajustes
/sipi-test Crea una prueba que ajuste el deslizador de brillo al 80% y active las notificaciones
/sipi-test Crea una prueba desde la pantalla actual
```

Las pruebas guardadas controlan toda la superficie de interacción —toques, toques dobles, interruptores, deslizadores, gestos, arrastres, pulsación larga, pellizco y multitáctil en bruto, combinaciones de teclas y rotación— como pasos deterministas, no solo toques y deslizamientos.

También pueden crear condiciones previas de error reales controladas por el Simulator, como permisos denegados, deep links, entrega de push, coordenadas simuladas, coincidencia y no coincidencia de Face ID / Touch ID, toda la superficie de apariencia de accesibilidad (reducir movimiento, reducir transparencia, filtros de color, opacidad de Liquid Glass) y perfiles de offline/latencia respaldados por un proveedor. SimPilot no incluye ni imita ningún acondicionador de red propietario: comprueba `sipi network-condition status` antes de usar un perfil de red.

La verificación va más allá de la coincidencia de texto: además de `contains` / `absent` y las expresiones regulares, un paso puede afirmar cosas sobre los propios elementos —que un control está deshabilitado, que una lista tiene exactamente cinco filas, que un valor coincide con un patrón o que un área táctil cumple los 44pt.

**Ejecutar pruebas:**
```text
/sipi-test Ejecuta la prueba settings-navigation
/sipi-test Ejecuta la suite regression
/sipi-test Ejecuta las pruebas con la etiqueta smoke
/sipi-test Ejecuta la suite regression en iPhone 16 Pro
/sipi-test Ejecuta las pruebas en iPhone 16 y iPhone 15
/sipi-test Ejecuta las pruebas con el conjunto de dispositivos regression-profile
```

Cuando se especifican varios dispositivos, las pruebas se ejecutan en paralelo. Si `.simpilot/config.json` incluye una entrada `build`, la app se compila antes de ejecutar.

**Ver resultados:**
```text
/sipi-test Muestra los resultados más recientes
/sipi-test Muestra el detalle del fallo de la prueba settings-toggle
/sipi-test Muestra el detalle de todas las pruebas fallidas
/sipi-test Abre el informe HTML
```

Cada ejecución genera `report.html` dentro del directorio del run. Los resultados se guardan en `.simpilot/runs/`.

**Gestionar suites:**
```text
/sipi-test Muestra todas las pruebas
/sipi-test Muestra las pruebas con la etiqueta smoke
/sipi-test Crea una suite regression con app-launch, settings-toggle y tab-navigation
```

**Auditorías de calidad:**
```text
/sipi-test Audita las pantallas onboarding y settings para accesibilidad
/sipi-test Revisa etiquetas e identificadores de accesibilidad faltantes
/sipi-test Revisa onboarding en English, japonés y alemán para comprobar la traducción
/sipi-test Revisa texto sin traducir y texto recortado
/sipi-test Compara la pantalla profile en modo Light y Dark
/sipi-test Revisa el flujo de settings con tamaños grandes de Dynamic Type
/sipi-test Audita esta pantalla con Reducir movimiento y un filtro de color activados
```

`sipi a11y-audit` ejecuta la parte mecánica desde la línea de comandos contra cualquier simulador arrancado —áreas táctiles demasiado pequeñas, controles sin etiqueta, etiquetas duplicadas ambiguas, etiquetas sin sentido, texto recortado— y sale con un código distinto de cero ante un hallazgo de severidad error, así que puede bloquear el CI. La auditoría de accesibilidad propia de Xcode solo se ejecuta desde dentro de un target de pruebas de UI.

## Estructura del workspace

SimPilot usa esta estructura estándar dentro de `.simpilot/`:

```text
.simpilot/
  config.json                  # Project configuration (app bundle ID, build settings)
  tests/                       # Test definitions
    <test-id>.json
  suites/                      # Test suites
    <suite-name>.json
  devices/                     # Device/simulator profiles
    <profile-name>.json
  runs/                        # Test run results (sipi-test)
    <run-id>/
      run.json                 # Run summary
      summary.json             # Compact agent/CI summary
      report.html              # HTML report (open in browser)
      <test-id>/
        result.json            # Test result
        trace.jsonl            # Per-test event trace
        step-NNN.png           # Step screenshots
        step-NNN.describe-before.json
        step-NNN.describe-after.json
        recording.mp4          # (if enabled)
  verify/                      # Verification results (sipi-verify)
    <timestamp>_<description>/
      checks.json
      findings.json
      report.html
```

Se recomienda añadir `.simpilot/` completa, o al menos `runs/` y `verify/`, al `.gitignore` del proyecto.

## Referencia

- **[JSON-REFERENCE.md](.claude/skills/sipi-test/references/json-reference.md)**: especificación JSON completa para tests, suites, dispositivos, resultados y metadata

## Limitaciones conocidas

- La entrada de texto escribe por defecto el valor de accesibilidad del campo (`set-text`), que no necesita teclado y admite cualquier sistema de escritura. La entrada tecla a tecla (`type`) pega por el portapapeles de forma predeterminada; la escritura HID directa tecla por tecla solo cubre la distribución de teclado de EE. UU.
- **Un simulador con mucho uso puede dejar de entregar HID de teclado** (medido en Xcode 27.0 beta 4): pegar, escribir tecla por tecla y seleccionar todo + borrar se ignoran, mientras la entrada táctil sigue funcionando. Depende de la antigüedad del dispositivo, no de la versión de iOS, y ni `simctl erase` ni un reinicio lo recuperan: cree un dispositivo nuevo. `type` detecta esta condición y falla en lugar de informar éxito; `set-text` no se ve afectado
- Face ID / Touch ID y las facetas de apariencia de accesibilidad más allá de light/dark necesitan Xcode 27: pasan por `xcrun devicectl`, que solo apunta a simuladores de esa versión en adelante
- Las relaciones de contraste y el texto recortado quedan fuera del alcance de `sipi a11y-audit`; ambos requieren un análisis de píxeles del fotograma renderizado
- Solo simulador: los dispositivos físicos no son compatibles

## Note

Este repositorio está gestionado principalmente por IA. Se agradecen los issues y comentarios, pero no se aceptan pull requests. Si quieres adaptarlo a tu flujo, haz un fork y usa tu propia copia.

## Descargo de responsabilidad

SimPilot es una herramienta de desarrollo. Controla el Simulador de iOS a través de los **frameworks privados no documentados** de Apple, que Apple puede cambiar o eliminar en cualquier actualización de Xcode o macOS, lo que puede romper SimPilot sin previo aviso. No está afiliado ni respaldado por Apple, y no está pensado para su uso en la App Store ni en producción. Se proporciona **tal cual, sin garantía: úsalo bajo tu propia responsabilidad.**

## License

MIT © 2026 hmhv. Consulta [LICENSE](LICENSE).
