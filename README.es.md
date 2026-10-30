# SimPilot

Traducciones: [English](README.md) | [日本語](README.ja.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | **Español** | [한국어](README.ko.md) | [Português do Brasil](README.pt-BR.md)

SimPilot permite que Claude Code o Codex controlen iOS Simulator con lenguaje natural —leer la pantalla, tocar, escribir, plegar, capturar, poner archivos en la app y leer lo que guardó— y mantiene instalada y limpia la cadena de herramientas de Xcode y del simulador que hay detrás. Cómo comprobar un resultado queda en manos del agente: lee la pantalla, la captura y lee los datos de la app de la forma que mejor encaje con la tarea.

Solo se traduce el README de nivel superior. Los skill docs y el código siguen en inglés.

## Qué hace

- **Controlar el simulador**: `sipi` lee el árbol de accesibilidad y actúa sobre él de forma nativa y headless: toques por etiqueta o id, entrada de texto en cualquier sistema de escritura, gestos, botones físicos, rotación, plegado de un iPhone Duo, capturas de pantalla y vídeo, Face ID / Touch ID, los ajustes de apariencia de accesibilidad y los avisos de presión de memoria.
- **Trabajar con los datos de la app**: pon archivos en el contenedor de datos de la app, en un App Group o en Files.app; inspecciona lo que guardó la app como texto, JSON, plist o SQLite; toma instantáneas del contenedor y compáralas; recopila los informes de fallos de la app.
- **Gestionar Xcode y los runtimes del simulador**: `sipi xcode list / install / uninstall` muestra, instala y elimina versiones de Xcode, y `sipi runtime list` muestra los runtimes del simulador que ofrece Apple; instalar y eliminar runtimes y dispositivos se hace con `xcodebuild` y `simctl`, como describe el skill.
- **Limpiar**: encuentra y elimina lo que Xcode y los simuladores dejan atrás: DerivedData, archivos de soporte de dispositivos, dispositivos de previsualización y de pruebas, runtimes inutilizables, versiones antiguas de Xcode. No se elimina nada sin aprobación, y los archivos van a la Papelera.

## Requisitos previos

- Xcode 27.2 o posterior
- macOS 26.6 o posterior
- [Claude Code](https://claude.com/claude-code) o Codex

## Instalación

SimPilot se distribuye como un único binario `sipi` con el skill incorporado. Se instala con un solo comando:

```bash
curl -fsSL https://raw.githubusercontent.com/hmhv/SimPilot/main/install.sh | bash
```

El instalador descarga el binario `sipi` precompilado y luego `sipi` instala el skill incorporado `sipi-common` en:

- Claude Code (`~/.claude/skills/`)
- Codex (`~/.agents/skills/`)

Verifica las capacidades del simulador con `sipi doctor`.

Para actualizar o desinstalar:

```bash
sipi update      # descarga el sipi más reciente de GitHub Releases y actualiza el skill
sipi uninstall   # elimina el skill, los metadatos de instalación y el binario sipi
```

Al actualizar desde 2.x se eliminan los skills `sipi-test` y `sipi-verify`. En los repositorios de tus apps, `.simpilot/tests/`, `suites/`, `devices/`, `runs/` y `verify/`, y toda clave de `config.json` distinta de `app` y `build`, ya no se usan: bórralos cuando no los necesites.

## Inicio rápido

En tu proyecto de app iOS:

- Claude Code: `/sipi-common` seguido de la solicitud, o simplemente pídelo
- Codex: menciona el skill, por ejemplo `Use the sipi-common skill to ...`

```text
/sipi-common Compila la app y comprueba que el nuevo flujo de inicio de sesión funciona en el simulador
/sipi-common Abre los ajustes y activa las notificaciones
/sipi-common Pon sample.pdf en el Inbox de la app y revisa la pantalla de importación
/sipi-common Muestra lo que la app guardó tras iniciar sesión
/sipi-common Instala Xcode 27.2 y el runtime de iOS 27.2
/sipi-common Limpia el espacio en disco que ocupa Xcode
```

En el primer uso, SimPilot detecta tu proyecto, crea `.simpilot/config.json` y prepara el simulador.

## Controlar el simulador directamente

`sipi` es una CLI normal que un agente llama paso a paso. `describe-ui --format compact` imprime el árbol de accesibilidad con un elemento por línea —tipo, etiqueta, id, valor, frame, punto de toque— en una fracción del tamaño del JSON; `wait-for` sondea hasta que una etiqueta, id, valor o texto aparece (o desaparece) en lugar de dormir; `screenshot --max-pixel 600` devuelve una captura lo bastante pequeña para mirarla a bajo coste; `memory-warning` envía el aviso de presión de memoria que ofrecía el menú Debug de Simulator.app (Xcode 27+); `fold-state` indica cuál de las dos pantallas de un iPhone Duo está encendida, `fold --closed|--open|--angle` lo pliega —algo que ni simctl ni devicectl pueden hacer— y `--display inner|cover` captura la pantalla apagada. Ejecuta `sipi --help` para ver todos los comandos.

`sipi a11y-audit` revisa la pantalla actual contra cualquier simulador arrancado —áreas táctiles demasiado pequeñas, controles sin etiqueta, etiquetas duplicadas ambiguas, etiquetas sin sentido, texto recortado—. La auditoría de accesibilidad propia de Xcode solo se ejecuta desde dentro de un target de pruebas de UI.

Los comandos de datos de la app se describen en [App data and evidence commands](docs/data-artifacts.md).

## Xcode y runtimes del simulador

```bash
sipi xcode install 27B48
```

Pasa un número de build de `sipi xcode list` (tomado de [xcodereleases.com](https://xcodereleases.com)). Se abre una ventana en developer.apple.com; inicia sesión allí y se cierra sola. La sesión solo vive en memoria durante esa ejecución: no se guarda nada. La app se instala como `/Applications/Xcode-<version>.app` (por ejemplo, `Xcode-27.2.0-release.candidate.app`). Seleccionarla requiere root, así que `sipi` imprime los comandos `sudo xcode-select -s …` y `sudo xcodebuild -runFirstLaunch` para que los ejecutes tú.

`sipi runtime list` muestra los runtimes del simulador que ofrece Apple y marca los instalados (ni `xcodebuild` ni `simctl` pueden listarlos). `xcodebuild -downloadPlatform iOS -buildVersion <versión> -architectureVariant arm64` instala uno, `xcrun simctl runtime delete` elimina uno y `xcrun simctl create` crea dispositivos. El skill conoce estos comandos y los ejecuta por ti.

## Archivos del proyecto

SimPilot mantiene dos archivos en tu proyecto:

```text
.simpilot/
  config.json   # bundle ID y cómo compilar la app
  notes.md      # particularidades de interacción de la app que registra el skill
```

Conviene poner ambos bajo control de versiones: le sirven a un compañero de equipo o a otro agente.

## Limitaciones conocidas

- La entrada de texto escribe por defecto el valor de accesibilidad del campo (`set-text`), que no necesita teclado y admite cualquier sistema de escritura. La entrada tecla a tecla (`type`) pega por el portapapeles de forma predeterminada; la escritura HID directa tecla por tecla solo cubre la distribución de teclado de EE. UU. y escribe caracteres incorrectos si el invitado tiene activa otra distribución
- **Un simulador con mucho uso puede dejar de aceptar HID de teclado** (medido en Xcode 27.0 beta 6): pegar, escribir tecla por tecla y seleccionar todo + borrar se ignoran, mientras la entrada táctil sigue funcionando. Depende de la antigüedad del dispositivo, no de la versión de iOS, y ni `simctl erase` ni un reinicio lo recuperan. `type` detecta esta condición y falla en lugar de informar éxito; `set-text` no se ve afectado. `type --xcode-mcp` escribe en su lugar a través del servicio propio de Xcode 27, lo que rescató el dispositivo medido, con un coste (véase más abajo)
- Un toque sobre un elemento que el árbol de accesibilidad declara presente pero cuya área visible no es realmente táctil sigue informando éxito. `describe-point` también devuelve ese elemento, así que ninguna capa puede distinguirlo; las herramientas del propio Xcode se comportan igual
- Las relaciones de contraste y el texto cortado por su contenedor sin puntos suspensivos quedan fuera del alcance de `sipi a11y-audit`; ambos requieren un análisis de píxeles del fotograma renderizado
- **iPhone Duo** (medido en Xcode 27.2): los toques, deslizamientos, la escritura y los botones físicos llegan a ambas pantallas. La pantalla interior no responde a la prueba de impacto de accesibilidad, así que allí un toque por selector va al marco del elemento sin comprobarlo, y `set-text` / `describe-point` solo funcionan en la exterior. Mientras Device Hub está abierto se queda con la entrada del dispositivo: la pantalla interior descarta los toques y el portapapeles del Mac sustituye al del simulador, por lo que `type` se niega a pegar. `sipi doctor` lo indica y `sipi repair-input` reconecta la entrada. Nada puede girar un simulador Duo desde un script, y `sipi orientation --set` lo rechaza; usa el botón de rotación de Device Hub
- Solo simulador: los dispositivos físicos no son compatibles

## Escribir en un simulador que dejó de aceptar pulsaciones

Un simulador puede llegar a un estado en el que ignora los eventos de teclado que inyecta SimPilot. El toque sigue funcionando; pegar, escribir tecla por tecla y seleccionar todo + borrar, no. SimPilot envía exactamente los mismos eventos en un dispositivo sano y en uno afectado, así que no hay nada que corregir de su lado. En cambio, el servicio de interacción con dispositivos del propio Xcode 27 escribe por otra vía que el dispositivo afectado medido sí aceptó (uno más desgastado ignoró también esa vía), y esa vía además ignora la distribución de teclado del invitado.

`sipi type --xcode-mcp` selecciona esa vía. SimPilot nunca la toma por su cuenta: en iOS 27, una sola sesión deja a toda app lanzada después en ese dispositivo con el árbol de accesibilidad vacío hasta que el dispositivo se reinicia (`simctl shutdown` + `boot`), así que úsela al final, o reinicie antes del siguiente lanzamiento. Todo lo demás en SimPilot funciona sin nada de esto, y `set-text` nunca necesita teclado.

Deben cumplirse tres condiciones:

```bash
xcode-select -p                    # Xcode 27.2 o posterior
sudo xcrun mcp-server enable       # activar el modo headless
sipi xcode-mcp --approve <ruta a un .xcodeproj o .xcworkspace>
```

El proyecto se abre solo para provocar el diálogo de aprobación de Xcode y se cierra de inmediato. Una vez configurado, sipi inicia el servicio si no está en marcha. Xcode vincula la concesión al binario exacto, así que `sipi update` o una recompilación obligan a repetir el paso de aprobación. `sipi xcode-mcp` informa del estado actual —incluida una concesión que pertenece a una compilación anterior en la misma ruta— y `sipi doctor` indica si esa vía está disponible.

`--clear` no puede usar esta vía: seleccionar todo y borrar también son pulsaciones, y el servicio escribe pero no puede vaciar un campo. Use `sipi set-text` para reemplazar un valor por completo.

El coste viene de la sesión, no de la escritura: medido de nuevo en Xcode 27.2, una sesión de un solo toque dejó todas las apps abiertas después con un árbol de accesibilidad vacío hasta reiniciar el dispositivo.


## Note

Este repositorio está gestionado principalmente por IA. Se agradecen los issues y comentarios, pero no se aceptan pull requests. Si quieres adaptarlo a tu flujo, haz un fork y usa tu propia copia.

## Descargo de responsabilidad

SimPilot es una herramienta de desarrollo. Controla el Simulador de iOS a través de los **frameworks privados no documentados** de Apple, que Apple puede cambiar o eliminar en cualquier actualización de Xcode o macOS, lo que puede romper SimPilot sin previo aviso. No está afiliado ni respaldado por Apple, y no está pensado para su uso en la App Store ni en producción. Se proporciona **tal cual, sin garantía: úsalo bajo tu propia responsabilidad.**

## License

MIT © 2026 hmhv. Consulta [LICENSE](LICENSE).
