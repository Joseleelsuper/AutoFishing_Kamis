#NoEnv
SendMode Input
SetWorkingDir %A_ScriptDir%
#SingleInstance Force

; ==============================================
;  AutoFishing
; ----------------------------------------------
;   @name: AutoFishing.ahk
;   @description: Automatiza la pesca en un juego mediante detección de píxeles y manejo del ratón/teclado.
;   @author: Haru
;   @author: Joseleelsuper
;   @bpsr_guild: HusaresAlados [1818]
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
    Config.TimeoutMs := 30000             ; ms para cancelar si no aparece el segundo píxel
    Config.Tolerance := { primary: 12     ; tolerancia para colores principales (inicio/fin/reset)
        , arrow: 15 }     ; tolerancia para colores del minijuego (flechas)

    ; -- Tiempos de espera (centralizados para fácil ajuste)
    Config.Timings := {}
    Config.Timings.clickDelay := 10              ; espera antes/después de clicks críticos
    Config.Timings.resetMenuOpen := 500          ; espera antes de enviar 'm' en reset
    Config.Timings.resetMenuWait := 1000         ; espera tras 'm' antes del primer clic
    Config.Timings.resetMenuConfirm := 1500      ; espera entre clics del menú reset
    Config.Timings.finishBeforeConfirm := 1000   ; espera tras soltar antes de confirmar
    Config.Timings.finishBetweenClicks := 500    ; espera entre confirmaciones finales
    Config.Timings.continueCheckDelay := 1500    ; espera antes de comprobar botón continuar
    Config.Timings.continueBeforeClick := 1000   ; espera después de detectar botón continuar antes de pulsar
    Config.Timings.continueFishingWait := 1000   ; espera tras pulsar botón continuar antes de recast
    Config.Timings.rewardPopupWait := 500        ; espera tras cerrar popup de recompensa
    Config.Timings.tensionRelease := 1000        ; tiempo de release cuando tensión llega al 100%

    ; -- Colores objetivo (0xRRGGBB)
    Config.Colors := { start: 0xFF5501           ; Píxel que indica que hay que mantener click
        , finish: 0xE8E8E8          ; Píxel que indica que hay que soltar y confirmar
        , reset:  0x767C82          ; Píxel que activa flujo de reinicio
        , continueFishing: 0xE8E8E8 ; Botón "continuar pescando"
        , tensionMax: 0xFFFFFF      ; Barra de tensión al 100% (blanco puro)
        , rewardBorder: 0xC6A777    ; Borde dorado del popup de recompensa mensual
        , arrowA: [0xFE6C06, 0xFAB916, 0xFF5601]  ; Colores para flecha A
        , arrowD: [0xFF5A01, 0xFAB916, 0xFF5601] } ; Colores para flecha D

    ; -- Lista de posibles ejecutables del juego
    Config.GameWindowExecutables := ["BPSR_STEAM.exe", "BPSR_EPIC.exe", "BPSR.exe", "BPSR"]

    ; -- Coordenadas base (en 1920x1080). Todas se escalarán al iniciar.
    Config.PointsBase := {}
    Config.PointsBase.centerHold      := { x:  954, y:  562 }  ; Dónde mantener click para iniciar
    Config.PointsBase.finish          := { x: 1463, y:  974 }  ; Píxel y botón de confirmación final
    Config.PointsBase.continueFishing := { x: 1463, y:  974 }  ; Botón "continuar pescando"
    Config.PointsBase.resetCheck      := { x: 1650, y: 1029 }  ; Píxel que indica necesidad de reinicio
    Config.PointsBase.menuConfirm1    := { x: 1788, y:  609 }  ; Botón a pulsar tras 'm' (dos clics)
    Config.PointsBase.tensionBar      := { x: 1248, y:  897 }  ; Final de la barra de tensión (extremo derecho)
    Config.PointsBase.rewardLeft      := { x:  649, y:  383 }  ; Lado izquierdo del popup de recompensa
    Config.PointsBase.rewardRight     := { x: 1221, y:  383 }  ; Lado derecho del popup de recompensa
    Config.PointsBase.rewardClose     := { x:  945, y:  972 }  ; Botón para cerrar popup de recompensa
    Config.PointsBase.arrowA          := { x:  851, y:  528 }  ; Detección flecha A
    Config.PointsBase.arrowD          := { x: 1054, y:  536 }  ; Detección flecha D

    ; -- Detectar ventana del juego y obtener dimensiones
    DetectGameWindow()

    ; -- Calcular escala basada en el tamaño de la ventana del juego
    Config.Scale := { x: (Config.GameWindow.w + 0.0) / Config.Base.w
        , y: (Config.GameWindow.h + 0.0) / Config.Base.h }

    ; -- Precalcular coordenadas escaladas relativas a la ventana del juego
    Config.Points := {}
    for key, pt in Config.PointsBase {
        ; Coordenadas escaladas + offset de la ventana
        sx := Round(pt.x * Config.Scale.x) + Config.GameWindow.x
        sy := Round(pt.y * Config.Scale.y) + Config.GameWindow.y
        Config.Points[key] := { x: sx, y: sy }
    }

    ; -- Flag para habilitar/deshabilitar logs
    Config.LoggingEnabled := true
    ; -- Ruta de log
    Config.LogPath := A_ScriptDir . "\AutoFishing.log"

    ; -- Estado en memoria
    State.toggle := false          ; Automatización activa/inactiva
    State.holding := false         ; ¿Se está manteniendo el click?
    State.holdStart := 0           ; Marca de tiempo en ms cuando se inició el hold
    State.origX := 0               ; Posición original del ratón (X)
    State.origY := 0               ; Posición original del ratón (Y)
    State.currentKey := ""         ; "a" o "d" según minijuego; vacío si nada
    State.tensionReleasing := false ; ¿Está en proceso de release temporal por tensión 100%?
    State.tensionReleaseStart := 0  ; Marca de tiempo cuando se soltó por tensión
    State.lastCastAttempt := 0      ; Se reinicia cuando pica (START) o termina de pescar (FINISH)

    Log("INFO", "Init completado | Ventana del juego: " . Config.GameWindow.w . "x" . Config.GameWindow.h . " en (" . Config.GameWindow.x . "," . Config.GameWindow.y . ") | ScaleX=" . Config.Scale.x . ", ScaleY=" . Config.Scale.y)
}

; Detecta la ventana del juego y guarda su posición y tamaño
DetectGameWindow() {
    global Config

    hwnd := 0
    detectedExe := ""

    ; Intentar detectar la ventana con cada ejecutable posible
    for index, exeName in Config.GameWindowExecutables {
        WinGet, hwnd, ID, % "ahk_exe " . exeName
        if (hwnd) {
            detectedExe := exeName
            Log("INFO", "Ventana del juego encontrada: " . exeName)
            break
        }
    }

    if (hwnd) {
        ; Obtener posición y tamaño de la ventana
        WinGetPos, wx, wy, ww, wh, % "ahk_id " . hwnd

        ; Obtener el área cliente (sin bordes de ventana)
        VarSetCapacity(rect, 16, 0)
        DllCall("GetClientRect", "Ptr", hwnd, "Ptr", &rect)
        clientW := NumGet(rect, 8, "Int")
        clientH := NumGet(rect, 12, "Int")

        ; Obtener offset del área cliente respecto a la ventana
        VarSetCapacity(point, 8, 0)
        DllCall("ClientToScreen", "Ptr", hwnd, "Ptr", &point)
        clientX := NumGet(point, 0, "Int")
        clientY := NumGet(point, 4, "Int")

        Config.GameWindow := { x: clientX, y: clientY, w: clientW, h: clientH, exe: detectedExe }
        Log("INFO", "Ventana del juego detectada (" . detectedExe . "): " . clientW . "x" . clientH . " en posición (" . clientX . "," . clientY . ")")
    } else {
        ; Si no se encuentra ninguna ventana, usar pantalla completa como fallback
        Config.GameWindow := { x: 0, y: 0, w: A_ScreenWidth, h: A_ScreenHeight, exe: "ninguno" }

        ; Construir lista de ejecutables buscados para el mensaje de log
        exeList := ""
        for index, exeName in Config.GameWindowExecutables {
            exeList .= exeName
            if (index < Config.GameWindowExecutables.Length())
                exeList .= ", "
        }

        Log("WARN", "No se detectó la ventana del juego. Ejecutables buscados: " . exeList . " -> Usando pantalla completa como fallback")
    }
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
        State.lastCastAttempt := A_TickCount
        SetTimer, CheckPixels, % Config.TimerInterval
    } else {
        Log("INFO", "Toggle OFF -> Deteniendo timer y liberando estado")
        SetTimer, CheckPixels, Off
        SafeReleaseAll()
        State.lastCastAttempt := 0
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

    ; -- 0) Detectar popup de recompensa mensual y cerrarlo
    rewardLeftColor := GetColorAtPoint(Config.Points.rewardLeft)
    rewardRightColor := GetColorAtPoint(Config.Points.rewardRight)
    if (ColorCloseEnough(rewardLeftColor, Config.Colors.rewardBorder, Config.Tolerance.primary)
        && ColorCloseEnough(rewardRightColor, Config.Colors.rewardBorder, Config.Tolerance.primary)) {
        Log("INFO", "Popup de recompensa mensual detectado -> Cerrando")
        ClickAt("rewardClose")
        Sleep, % Config.Timings.rewardPopupWait
        Log("INFO", "Popup de recompensa cerrado")
        return
    }

    ; -- 1) Flujo de reinicio si detecta el color de reset
    if (ColorCloseEnough(resetRead, Config.Colors.reset, Config.Tolerance.primary)) {
        Log("INFO", "RESET detectado -> Iniciando flujo de reinicio")
        if (State.holding)
            ReleaseHoldAt("centerHold")

        ; Resetear TODOS los estados relacionados con holding/timeout
        State.holding := false
        State.holdStart := 0
        State.tensionReleasing := false
        State.tensionReleaseStart := 0
        ReleaseKeyIfAny()

        Sleep, % Config.Timings.resetMenuOpen
        Send, m
        Sleep, % Config.Timings.resetMenuWait
        MoveMouseTo("menuConfirm1")
        Click, left
        Sleep, % Config.Timings.resetMenuConfirm
        Click, left

        RestoreMousePosition()
        Log("INFO", "Flujo de reinicio completado")
        return
    }

    ; -- 2) Watchdog: si han pasado 20s sin pescar ningún pez, lanzar caña
    if (!State.holding && State.lastCastAttempt && (A_TickCount - State.lastCastAttempt > Config.TimeoutMs)) {
        Log("WARN", "Watchdog: 20s sin actividad de pesca -> lanzando caña")
        SaveMousePositionOnce()
        MoveMouseTo("centerHold")
        Sleep, % Config.Timings.clickDelay
        Click, left
        State.lastCastAttempt := A_TickCount
        RestoreMousePosition()
    }

    ; -- 3) Detectar primer píxel (empezar a mantener click = pica el pez)
    if (!State.holding && ColorCloseEnough(startRead, Config.Colors.start, Config.Tolerance.primary)) {
        SaveMousePositionOnce()
        MoveMouseTo("centerHold")
        Sleep, % Config.Timings.clickDelay
        Click, down, left

        State.holding := true
        State.holdStart := A_TickCount
        State.lastCastAttempt := A_TickCount

        Log("INFO", "START detectado -> Manteniendo click en centerHold")
    }

    ; -- 4) Detectar segundo píxel (soltar y confirmar = termina de pescar)
    if (State.holding && ColorCloseEnough(finishRead, Config.Colors.finish, Config.Tolerance.primary)) {
        MoveMouseTo("finish")
        Sleep, % Config.Timings.clickDelay
        Click, up, left
        State.holding := false
        State.holdStart := 0

        ReleaseKeyIfAny()

        ; Confirmaciones posteriores
        Sleep, % Config.Timings.finishBeforeConfirm
        ClickAt("finish")
        Sleep, % Config.Timings.finishBetweenClicks
        ClickAt("finish")

        State.lastCastAttempt := A_TickCount
        RestoreMousePosition()

        Log("INFO", "FINISH detectado -> Soltado y confirmaciones enviadas")
    }

    ; -- 5) Timeout de seguridad si no aparece el segundo píxel
    if (State.holding && (A_TickCount - State.holdStart > Config.TimeoutMs)) {
        ReleaseHoldAt("centerHold")
        State.holding := false
        elapsed := A_TickCount - State.holdStart
        State.holdStart := 0

        ReleaseKeyIfAny()

        ; Antes de recastear, verificar si hay botón "continuar pescando"
        Log("WARN", "TIMEOUT sin FINISH tras " . elapsed . " ms -> Verificando botón continuar")
        Sleep, % Config.Timings.continueCheckDelay

        ; Intentar detectar el botón varias veces (hasta 3 intentos)
        continueDetected := false
        Loop, 10 {
            continueColor := GetColorAtPoint(Config.Points.continueFishing)
            Log("DEBUG", "Intento " . A_Index . "/3 - Color detectado en continueFishing: " . Format("0x{:06X}", continueColor) . " | Esperado: 0xE8E8E8")

            if (ColorCloseEnough(continueColor, Config.Colors.continueFishing, Config.Tolerance.primary)) {
                continueDetected := true
                break
            }
            Sleep, % Config.Timings.continueCheckDelay
        }

        if (continueDetected) {
            Log("INFO", "Botón 'continuar pescando' detectado -> Esperando antes de pulsar")
            Sleep, % Config.Timings.continueBeforeClick
            Log("INFO", "Pulsando botón 'continuar pescando'")
            ClickAt("continueFishing")
            Sleep, % Config.Timings.finishBetweenClicks
            Log("INFO", "Esperando tras pulsar 'continuar pescando' antes de lanzar caña")
            Sleep, % Config.Timings.continueFishingWait
            RestoreMousePosition()
            return
        }

        ; Si no hay botón continuar, hacer recast
        Log("WARN", "No se detectó botón continuar después de 3 intentos -> Haciendo recast")
        MoveMouseTo("centerHold")
        Click, left
        RestoreMousePosition()
        Log("INFO", "Recast ejecutado -> El timer detectará START en próximos ciclos")
        return
    }

    ; -- 6) Gestión de tensión al 100% (release temporal)
    if (State.tensionReleasing) {
        ; Esperando a que pase el tiempo de release para volver a pulsar
        if (A_TickCount - State.tensionReleaseStart >= Config.Timings.tensionRelease) {
            MoveMouseTo("centerHold")
            Sleep, % Config.Timings.clickDelay
            Click, down, left
            State.holding := true
            State.holdStart := A_TickCount
            State.tensionReleasing := false
            State.tensionReleaseStart := 0
            Log("INFO", "Tensión normalizada -> Click reanudado tras release temporal")
        }
    }

    ; -- 7) Detectar tensión al 100% mientras se mantiene el click
    if (State.holding && !State.tensionReleasing) {
        tensionColor := GetColorAtPoint(Config.Points.tensionBar)
        if (ColorCloseEnough(tensionColor, Config.Colors.tensionMax, Config.Tolerance.primary)) {
            Log("WARN", "Tensión al 100% detectada -> Soltando click temporalmente")
            MoveMouseTo("centerHold")
            Sleep, % Config.Timings.clickDelay
            Click, up, left
            State.holding := false
            State.tensionReleasing := true
            State.tensionReleaseStart := A_TickCount
            return
        }
    }

    ; -- 8) Minijuego de flechas
    if (State.holding || State.tensionReleasing) {
        colorA := GetColorAtPoint(Config.Points.arrowA)
        colorD := GetColorAtPoint(Config.Points.arrowD)

        ; Probar todos los colores posibles para flecha D
        arrowDDetected := false
        for index, targetColor in Config.Colors.arrowD {
            if (ColorCloseEnough(colorD, targetColor, Config.Tolerance.arrow)) {
                arrowDDetected := true
                break
            }
        }

        ; Probar todos los colores posibles para flecha A
        arrowADetected := false
        for index, targetColor in Config.Colors.arrowA {
            if (ColorCloseEnough(colorA, targetColor, Config.Tolerance.arrow)) {
                arrowADetected := true
                break
            }
        }

        if (arrowDDetected) {
            SendKeyDown("d")
        } else if (arrowADetected) {
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
    global Config
    MoveMouseTo(pointName)
    Sleep, % Config.Timings.clickDelay
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
    State.tensionReleasing := false
    State.tensionReleaseStart := 0
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
    FormatTime, _time, , HH:mm:ss
    line := "[" . _date . "] [" . _time . "] [" . type . "] <" . msg . ">`r`n"
    FileAppend, % line, % Config.LogPath, UTF-8
}

OnExitHandler(reason) {
    Log("EXIT", "OnExit -> Razón=" . reason)
}
