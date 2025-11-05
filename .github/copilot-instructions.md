## Guía para agentes de IA en este repo (AutoFishing_Kamis)

Este proyecto es un script de AutoHotkey v1 para automatizar la pesca de un juego vía detección de píxeles y control de ratón/teclado. Mantén estas pautas para ser productivo desde el primer minuto y no romper el flujo actual.

### Visión general y arquitectura
- Lenguaje/Runtime: AutoHotkey v1 (no v2). El código usa comandos legacy (SetTimer con etiqueta, Click, Send), objetos AHK v1 y hotkeys F9/F10.
- Archivo principal: `AutoFishing_Kamis.ahk`.
- Estructura:
	- `Config` (global): parámetros base (resolución de referencia 1920x1080), tolerancias, colores, puntos base, escala por pantalla, timings centralizados, logging.
	- `Config.Timings`: todos los `Sleep` centralizados (clickDelay, resetMenuOpen, finishBeforeConfirm, etc.) para fácil ajuste sin tocar la lógica.
	- `State` (global): flags de ejecución (toggle, holding), tiempos (holdStart), posición original del ratón, tecla activa del minijuego.
	- `Init()`: calcula `Config.Scale` con la resolución actual y precalcula `Config.Points` escalados desde `Config.PointsBase` (x,y por punto en 1920x1080).
	- Bucle: `SetTimer` llama `CheckPixelsLogic()` cada `Config.TimerInterval` ms.
	- Flujo en `CheckPixelsLogic()` (orden): RESET → START (mantener click) → FINISH (soltar y confirmar) → TIMEOUT de seguridad (verifica botón "continuar pescando" antes de recast) → minijuego de flechas (A/D).
	- Logging: `Log(type, msg)` a `AutoFishing_Kamis.log` (en el mismo directorio), activable con `Config.LoggingEnabled`.

### Atajos y controles
- F9: activar/desactivar automatización (inicia/detiene timer). F10: salida segura (libera estado, apaga timer y cierra).
- El script guarda/restaura la posición del ratón con `SaveMousePositionOnce()`/`RestoreMousePosition()` para minimizar impacto al usuario.

### Flujos y patrones clave del proyecto
- Detección por color: siempre con `ColorCloseEnough(actual, objetivo, toleranciaPorCanal)`. Tolerancias:
	- `Config.Tolerance.primary` para START/FINISH/RESET/continueFishing.
	- `Config.Tolerance.arrow` para flechas A/D.
- Coordenadas: declara en `Config.PointsBase` (en 1920x1080) y deja que `Init()` genere `Config.Points` escalados. Evita usar coordenadas absolutas directas en el flujo.
- Botón "continuar pescando": tras TIMEOUT, antes de recastear, el script verifica si hay botón de continuar (suele aparecer cuando el pez se escapa). Si se detecta, se pulsa; si no, se procede al recast.
- Recast simple: tras timeout sin botón continuar, el script hace UN click de recast y deja que el timer principal siga detectando START normalmente. **No usar bucles bloqueantes** que impidan al timer funcionar.
- Minijuego: usa `SendKeyDown("a"|"d")` y `ReleaseKeyIfAny()` para garantizar que solo una tecla esté pulsada a la vez.
- Timings: todos los `Sleep` están en `Config.Timings` (clickDelay, resetMenuOpen, finishBeforeConfirm, continueCheckDelay, etc.). Modifica ahí para ajustar velocidades sin tocar lógica.

### Ejemplos concretos (cómo extender sin romper)
- Añadir un nuevo punto/color a detectar:
	1) En `Init()`: agrega `Config.Colors.miEvento := 0xRRGGBB` y `Config.PointsBase.miEvento := { x: ..., y: ... }` (en base 1920x1080).
	2) Usa en `CheckPixelsLogic()`:
		 - `miColor := GetColorAtPoint(Config.Points.miEvento)`
		 - `if (ColorCloseEnough(miColor, Config.Colors.miEvento, Config.Tolerance.primary)) { ... }`
	3) Si acciones implican teclas, llama `SendKeyDown()`/`ReleaseKeyIfAny()`; si implican clicks, utiliza `MoveMouseTo()` y `Click` y restaura el ratón luego.
- Ajustar tolerancias cuando haya falsos positivos/negativos: incrementa/decrementa `Config.Tolerance.*` en pasos pequeños (2–5). Recuerda que la tolerancia es por canal RGB.

### Workflows de desarrollo
- Ejecutar el script: abre con AutoHotkey v1 en Windows y usa F9/F10 para controlar. Para diagnósticos, habilita `Config.LoggingEnabled := true` y lee `AutoFishing_Kamis.log`.
- Compilar a EXE (opcional): usa Ahk2Exe para obtener `AutoFishing_Kamis.exe`. Luego ejecuta `generateHash.ps1` para actualizar `hash.txt` con el SHA-256 del EXE.
	- Script: `generateHash.ps1` contiene `(Get-FileHash -Algorithm SHA256 AutoFishing_Kamis.exe).Hash > hash.txt`.

### Convenciones y decisiones importantes
- Mantener v1: no migrar a AHK v2 ni mezclar estilos (las etiquetas/timers y `Send,` son v1).
- Escalado por pantalla: `Config.Scale.x` y `.y` se calculan independientemente. Las posiciones base deben definirse en 1920x1080.
- No bloquear el timer: evita bucles/esperas largas en `CheckPixelsLogic()`. Usa `Sleep` cortos y helpers existentes (p. ej., `WaitForStartPixel()` para sondeo con pausa).
- Timings centralizados: NUNCA usar `Sleep` con valores literales en la lógica; todos deben referir a `Config.Timings.*` para facilitar ajuste.
- Limpieza de estado: antes de salir o desactivar, llama a `SafeReleaseAll()` (libera click, suelta teclas, restaura ratón).

### Precauciones (lo que suele fallar)
- Permisos: si el juego corre elevado, ejecuta AHK como administrador para que `PixelGetColor` funcione.
- Variaciones de color/post-procesado/HDR: si los colores no coinciden, ajusta tolerancias y considera desactivar filtros del juego o usar modo fullscreen/borderless consistente.
- DPI/escala de Windows: el script usa coordenadas de pantalla; mantener la referencia de 1920x1080 y el escalado interno minimiza problemas, pero puntos/colores pueden requerir reajuste si cambia la UI del juego.

### Archivos relevantes
- `AutoFishing_Kamis.ahk`: lógica completa (config, timer, flujos, utilidades, logs).
- `generateHash.ps1`: genera `hash.txt` con hash SHA-256 del EXE compilado.
- `hash.txt`: salida de hash publicada.
