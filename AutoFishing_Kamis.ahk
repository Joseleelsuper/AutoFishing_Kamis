#NoEnv
SendMode Input
SetWorkingDir %A_ScriptDir%
#SingleInstance Force

; ==============================================
;  AutoFishing
; ----------------------------------------------
;   @name: AutoFishing_Kamis.ahk
;   @description: Automatiza la pesca en un juego mediante detección de píxeles y manejo del ratón/teclado.
;   @author: Haru
;   @author: Joseleelsuper
;   @bpsr_guild: Kamis [78542]
;   @use
;       - Ve a pescar, tira el cebo y pulsa la tecla F9 para activar/desactivar la automatización.
;       - Pulsa la tecla F10 para detener el script completamente.
;       - El script detecta:
;           · Píxel de inicio (comenzar a mantener click).
;           · Píxel de finalización (soltar click y confirmar).
;           · Píxel de reinicio (flujo para reintentar manualmente).
;           · Minijuego de flechas (mantiene A o D mientras corresponda).
;       - Todos los puntos y colores se escalan automáticamente partiendo de una base 1920x1080.
; ==============================================

CoordMode, Pixel, Screen
CoordMode, Mouse, Screen

; ----------------------------
;  Configuración y Estado
; ----------------------------
global Config := {}
global State := {}

; ============================
;  Inicialización
; ============================
Init() {
    global Config, State

    ; -- Parámetros base de referencia
    Config.Base := { w: 1920, h: 1080 }

    ; -- Temporizadores y tolerancias
    Config.TimerInterval := 20            ; ms entre ciclos de comprobación
    Config.TimeoutMs := 20000             ; ms para cancelar si no aparece el segundo píxel
    Config.Tolerance := { primary: 12     ; tolerancia para colores principales (inicio/fin/reset)
                        , arrow: 15 }     ; tolerancia para colores del minijuego (flechas)

    ; -- Parámetros de recasteo (reintento tras timeout)
    Config.Recast := {}
    Config.Recast.maxAttempts := 8            ; número máximo de intentos de recasteo
    Config.Recast.waitAfterCastMs := 1200     ; espera tras lanzar la caña antes de buscar START
    Config.Recast.detectionWindowMs := 10000  ; ventana para detectar START por intento
    Config.Recast.pollIntervalMs := 30        ; intervalo de sondeo de color
    Config.Recast.interAttemptDelayMs := 400  ; pausa entre intentos

    ; -- Colores objetivo (0xRRGGBB)
    Config.Colors := { start: 0xFF5501    ; Píxel que indica que hay que mantener click
                     , finish: 0xE8E8E8   ; Píxel que indica que hay que soltar y confirmar
                     , reset:  0x767C82   ; Píxel que activa flujo de reinicio
                     , arrowA: 0xFE6C06   ; Color para flecha A
                     , arrowD: 0xFF5A01 } ; Color para flecha D

    ; -- Coordenadas base (en 1920x1080). Todas se escalarán al iniciar.
    Config.PointsBase := {}
    Config.PointsBase.centerHold   := { x:  954, y:  562 }  ; Dónde mantener click para iniciar
    Config.PointsBase.finish       := { x: 1463, y:  974 }  ; Píxel y botón de confirmación final
    Config.PointsBase.resetCheck   := { x: 1650, y: 1029 }  ; Píxel que indica necesidad de reinicio
    Config.PointsBase.menuConfirm1 := { x: 1788, y:  609 }  ; Botón a pulsar tras 'm' (dos clics)
    Config.PointsBase.arrowA       := { x:  851, y:  528 }  ; Detección flecha A
    Config.PointsBase.arrowD       := { x: 1054, y:  536 }  ; Detección flecha D

    ; -- Medir pantalla actual y calcular escala X/Y de forma independiente
    Config.Screen := { w: A_ScreenWidth, h: A_ScreenHeight }
    Config.Scale := { x: (Config.Screen.w + 0.0) / Config.Base.w
                    , y: (Config.Screen.h + 0.0) / Config.Base.h }

    ; -- Precalcular coordenadas escaladas para evitar recomputar en cada ciclo
    Config.Points := {}
    for key, pt in Config.PointsBase {
        sx := Round(pt.x * Config.Scale.x)
        sy := Round(pt.y * Config.Scale.y)
        Config.Points[key] := { x: sx, y: sy }
    }

    
    ; -- Flag para habilitar/deshabilitar logs
    Config.LoggingEnabled := true
    ; -- Ruta de log
    Config.LogPath := A_ScriptDir . "\AutoFishing_Kamis.log"

    ; -- Estado en memoria
    State.toggle := false          ; Automatización activa/inactiva
    State.holding := false         ; ¿Se está manteniendo el click?
    State.holdStart := 0           ; Marca de tiempo en ms cuando se inició el hold
    State.origX := 0               ; Posición original del ratón (X)
    State.origY := 0               ; Posición original del ratón (Y)
    State.currentKey := ""         ; "a" o "d" según minijuego; vacío si nada

    Log("INFO", "Init completado | Screen=" . Config.Screen.w . "x" . Config.Screen.h . ", ScaleX=" . Config.Scale.x . ", ScaleY=" . Config.Scale.y)
}

; Ejecutar inicialización al cargar el script
Init()

; Registrar manejador de salida para saber por qué se cerró el script
OnExit("OnExitHandler")

; ============================
;  Hotkey de activación
; ============================
F9::
ToggleAutomation()
return

ToggleAutomation() {
    global Config, State
    State.toggle := !State.toggle
    if (State.toggle) {
        Log("INFO", "Toggle ON -> Iniciando timer (" . Config.TimerInterval . " ms)")
        Click, left
        SetTimer, CheckPixels, % Config.TimerInterval
    } else {
        Log("INFO", "Toggle OFF -> Deteniendo timer y liberando estado")
        SetTimer, CheckPixels, Off
        SafeReleaseAll()
    }
}

; ============================
;  Bucle principal (timer)
; ============================
CheckPixels:
    CheckPixelsLogic()
return

CheckPixelsLogic() {
    global Config, State

    ; -- Leer colores actuales en puntos clave
    startRead  := GetColorAtPoint(Config.Points.centerHold)
    finishRead := GetColorAtPoint(Config.Points.finish)
    resetRead  := GetColorAtPoint(Config.Points.resetCheck)

    ; -- 1) Flujo de reinicio si detecta el color de reset
    if (ColorCloseEnough(resetRead, Config.Colors.reset, Config.Tolerance.primary)) {
        Log("INFO", "RESET detectado -> Iniciando flujo de reinicio")
        if (State.holding)
            ReleaseHoldAt("centerHold")

        State.holdStart := 0
        ReleaseKeyIfAny()

        Sleep, 100
        Send, m
        Sleep, 300
        MoveMouseTo("menuConfirm1")
        Click, left
        Sleep, 500
        Click, left

        RestoreMousePosition()
        Log("INFO", "Flujo de reinicio completado")
        return
    }

    ; -- 2) Detectar primer píxel (empezar a mantener click)
    if (!State.holding && ColorCloseEnough(startRead, Config.Colors.start, Config.Tolerance.primary)) {
        SaveMousePositionOnce()
        MoveMouseTo("centerHold")
        Sleep, 10
        Click, down, left
        State.holding := true
        State.holdStart := A_TickCount
        Log("INFO", "START detectado -> Manteniendo click en centerHold")
    }

    ; -- 3) Detectar segundo píxel (soltar y confirmar)
    if (State.holding && ColorCloseEnough(finishRead, Config.Colors.finish, Config.Tolerance.primary)) {
        MoveMouseTo("finish")
        Sleep, 10
        Click, up, left
        State.holding := false
        State.holdStart := 0

        ReleaseKeyIfAny()

        ; Confirmaciones posteriores
        Sleep, 1000
        ClickAt("finish")
        Sleep, 500
        ClickAt("finish")

        RestoreMousePosition()
        Log("INFO", "FINISH detectado -> Soltado y confirmaciones enviadas")
    }

    ; -- 4) Timeout de seguridad si no aparece el segundo píxel
    if (State.holding && (A_TickCount - State.holdStart > Config.TimeoutMs)) {
        ReleaseHoldAt("centerHold")
        State.holding := false
        elapsed := A_TickCount - State.holdStart
        State.holdStart := 0

        ReleaseKeyIfAny()

        ; Reintentar tirar la caña hasta detectar START
        Log("WARN", "TIMEOUT sin FINISH tras " . elapsed . " ms -> Reintentando tirar la caña")
        success := RecastUntilStart()
        if (!success) {
            RestoreMousePosition()
            Log("ERROR", "No se pudo detectar START tras reintentos de recasteo")
        }
    }

    ; -- 5) Minijuego de flechas (solo mientras se mantiene el click)
    if (State.holding) {
        colorA := GetColorAtPoint(Config.Points.arrowA)
        colorD := GetColorAtPoint(Config.Points.arrowD)

        if (ColorCloseEnough(colorD, Config.Colors.arrowD, Config.Tolerance.arrow)) {
            SendKeyDown("d")
        } else if (ColorCloseEnough(colorA, Config.Colors.arrowA, Config.Tolerance.arrow)) {
            SendKeyDown("a")
        }
        ; Si ninguna flecha está presente, se mantiene la tecla actual (si la hubiera)
    }
}

; ============================
;  Utilidades (globales)
; ============================

; Guarda la posición del ratón sólo una vez (si no se ha guardado).
SaveMousePositionOnce() {
    global State
    if (State.origX = 0 && State.origY = 0) {
        MouseGetPos, _x, _y
        State.origX := _x
        State.origY := _y
        Log("DEBUG", "Posición original guardada: x=" . State.origX . ", y=" . State.origY)
    }
}

; Restaura la posición del ratón si existe una almacenada.
RestoreMousePosition() {
    global State
    if (State.origX || State.origY) {
        MouseMove, % State.origX, % State.origY, 0
        State.origX := 0
        State.origY := 0
        Log("DEBUG", "Posición del ratón restaurada")
    }
}

; Mueve el ratón a un punto con nombre y hace clic si se requiere.
MoveMouseTo(pointName) {
    global Config
    pt := Config.Points[pointName]
    MouseMove, % pt.x, % pt.y, 0
}

ClickAt(pointName) {
    MoveMouseTo(pointName)
    Click, left
}

; Suelta el click en un punto determinado (por seguridad antes de soltar).
ReleaseHoldAt(pointName) {
    MoveMouseTo(pointName)
    Sleep, 10
    Click, up, left
    Log("INFO", "Hold liberado en " . pointName)
}

; Envía una tecla en modo "down" y levanta la anterior si cambia.
SendKeyDown(key) {
    global State
    if (State.currentKey != key) {
        if (State.currentKey) {
            prev := State.currentKey
            Send, {%prev% up}
            Log("INFO", "Tecla liberada: " . prev)
        }
        Send, {%key% down}
        State.currentKey := key
        Log("INFO", "Tecla presionada: " . key)
    }
}

; Levanta cualquier tecla que esté siendo mantenida para el minijuego.
ReleaseKeyIfAny() {
    global State
    if (State.currentKey) {
        prev := State.currentKey      ; Usar variable temporal para Send
        Send, {%prev% up}
        State.currentKey := ""
        Log("INFO", "Tecla liberada (limpieza): " . prev)
    }
}

; Obtiene el color en un punto (objeto {x,y}). Devuelve 0xRRGGBB.
GetColorAtPoint(pt) {
    return GetColorAtXY(pt.x, pt.y)
}

GetColorAtXY(x, y) {
    PixelGetColor, color, %x%, %y%, RGB
    return color
}

; Espera hasta que aparezca el píxel START durante un tiempo máximo.
; Devuelve true si se detecta, false si expira.
WaitForStartPixel(timeoutMs) {
    global Config
    startTick := A_TickCount
    loop {
        ; leer color actual en el punto de START
        color := GetColorAtPoint(Config.Points.centerHold)
        if (ColorCloseEnough(color, Config.Colors.start, Config.Tolerance.primary))
            return true

        if (A_TickCount - startTick >= timeoutMs)
            break

        Sleep, % Config.Recast.pollIntervalMs
    }
    return false
}

; Repite el lanzamiento de la caña hasta detectar el píxel START.
; Si detecta START, comienza a mantener el click y devuelve true. Si no, devuelve false.
RecastUntilStart() {
    global Config, State

    SaveMousePositionOnce()

    attempts := Config.Recast.maxAttempts
    Loop, %attempts% {
        i := A_Index
        Log("INFO", "Reintento de lanzamiento #" . i)

        ; Lanzar la caña (clic simple)
        MoveMouseTo("centerHold")
        Click, left

        ; Esperar un poco tras el lanzamiento antes de buscar START
        Sleep, % Config.Recast.waitAfterCastMs

        ; Ventana de detección para START en este intento
        if (WaitForStartPixel(Config.Recast.detectionWindowMs)) {
            ; En cuanto veamos START, comenzamos el hold si aún no lo estamos
            if (!State.holding) {
                MoveMouseTo("centerHold")
                Sleep, 10
                Click, down, left
                State.holding := true
                State.holdStart := A_TickCount
                Log("INFO", "START detectado tras recasteo -> Manteniendo click")
            }
            return true
        }

        ; Si no se detectó, pequeña pausa y reintento
        Sleep, % Config.Recast.interAttemptDelayMs
    }

    return false
}

; Comparación de colores con tolerancia por canal (R, G, B).
ColorCloseEnough(color1, color2, tolerance := 10) {
    c1r := (color1 >> 16)   & 0xFF
    c1g := (color1 >> 8)    & 0xFF
    c1b :=  color1          & 0xFF
    c2r := (color2 >> 16)   & 0xFF
    c2g := (color2 >> 8)    & 0xFF
    c2b :=  color2          & 0xFF
    return ( Abs(c1r - c2r) <= tolerance
          && Abs(c1g - c2g) <= tolerance
          && Abs(c1b - c2b) <= tolerance )
}

; Libera todos los recursos de estado al desactivar.
SafeReleaseAll() {
    global State
    if (State.holding) {
        ReleaseHoldAt("centerHold")
        State.holding := false
        Log("INFO", "SafeReleaseAll: hold activo liberado")
    }
    State.holdStart := 0
    ReleaseKeyIfAny()
    RestoreMousePosition()
    Log("INFO", "SafeReleaseAll: estado limpiado")
}

F10::
    Log("EXIT", "F10 presionado -> Saliendo")
    SetTimer, CheckPixels, Off
    SafeReleaseAll()
    ExitApp
return

; ============================
;  Sistema de Logs
; ============================

Log(type, msg) {
    global Config
    ; Si el logging está deshabilitado, no hacer nada
    if (!Config.LoggingEnabled)
        return
    ; Asegurar tipo en mayúsculas por consistencia
    StringUpper, type, type
    FormatTime, _date, , yy-MM-dd
    FormatTime, _time, , HH-mm-ss
    line := "[" . _date . "] [" . _time . "] [" . type . "] <" . msg . ">`r`n"
    FileAppend, % line, % Config.LogPath, UTF-8
}

OnExitHandler(reason) {
    Log("EXIT", "OnExit -> Razón=" . reason)
}
