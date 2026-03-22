# SimPilot

Traducciones: [English](README.md) | [日本語](README.ja.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | **Español** | [한국어](README.ko.md) | [Português do Brasil](README.pt-BR.md)

SimPilot es un conjunto de agent skills para pruebas y verificación en iOS Simulator, impulsado por solicitudes en lenguaje natural desde Claude Code o Codex.

Solo se traduce el README de nivel superior. Los skill docs y el código siguen en inglés.

## Qué hace

- **`/sipi-test`**: automatización de pruebas de UI en iOS Simulator. Define pruebas en lenguaje natural; el skill automatiza la interacción y la verificación. Soporta suites de regresión, ejecución en varios dispositivos y auditorías de calidad (accesibilidad, localización y apariencia).
- **`/sipi-verify`**: verificación posterior a la implementación. Confirma que una función o un arreglo funciona correctamente después de cambios en el código.

Los resultados se guardan en `.simpilot/` con informes HTML que se pueden abrir en el navegador.

## Requisitos previos

- macOS 15 o posterior
- Xcode 26 o posterior
- [AXe](https://github.com/cameroncooke/AXe) CLI
  - `brew install cameroncooke/axe/axe`
  - `axe init`
- [Claude Code](https://claude.com/claude-code) o Codex

La simulator automation de SimPilot asume que el entorno del agente tiene disponible el skill `axe`.

## Instalación

```bash
git clone https://github.com/hmhv/SimPilot.git
cd SimPilot
make install
```

`make install` hace lo siguiente:

- Registra los skills de SimPilot en Claude Code (`~/.claude/skills/`)
- Registra los skills de SimPilot en Codex (`~/.agents/skills/`)

Para actualizar o desinstalar:

```bash
make update
make uninstall
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
/sipi-test Crea una prueba desde la pantalla actual
```

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
```

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
      report.html              # HTML report (open in browser)
      <test-id>/
        result.json            # Test result
        step-NNN.png           # Step screenshots
        recording.mp4          # (if enabled)
  verify/                      # Verification results (sipi-verify)
    <timestamp>_<description>/
      report.html
```

Se recomienda añadir `.simpilot/` completa, o al menos `runs/` y `verify/`, al `.gitignore` del proyecto.

## Referencia

- **[JSON-REFERENCE.md](.claude/skills/sipi-test/references/json-reference.md)**: especificación JSON completa para tests, suites, dispositivos, resultados y metadata

## Limitaciones conocidas

- La entrada de texto usa el portapapeles; no hay `axe type` para contraseñas
- `axe type` asume una distribución de teclado de EE. UU.
- No se pueden reproducir gestos de drag and drop, pinch ni rotation
- Los elementos de system UI como PhotosPicker no son accesibles mediante `describe-ui`

## Note

Este repositorio está gestionado principalmente por IA. Se agradecen los issues y comentarios, pero no se aceptan pull requests. Si quieres adaptarlo a tu flujo, haz un fork y usa tu propia copia.

## License

Consulta [LICENSE](LICENSE).
