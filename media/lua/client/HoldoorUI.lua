-- ============================================================
--  Holdoor — Sistema de Oleadas  |  Panel + Overlay + HUD
--  F10 para abrir/cerrar el panel de configuracion
-- ============================================================

require "HoldoorConfig"
require "HoldoorClient"
require "HoldoorShop"

HoldoorUI = HoldoorUI or {}
HoldoorUI.instancia = nil
HoldoorUI.overlay   = nil


local PANEL_W = 500
local PANEL_H = 540  -- vuelta al alto original sin botones de test

local COLOR_FONDO      = { r=0.05, g=0.04, b=0.03, a=0.97 }
local COLOR_BORDE      = { r=0.6,  g=0.4,  b=0.1,  a=1    }
local COLOR_BOTON_OK   = { r=0.15, g=0.45, b=0.15, a=1    }
local COLOR_BOTON_STOP = { r=0.45, g=0.10, b=0.10, a=1    }
local COLOR_BOTON_BASE = { r=0.15, g=0.30, b=0.50, a=1    }
local COLOR_BOTON_ONDA = { r=0.45, g=0.25, b=0.05, a=1    }
local COLOR_TEXTO      = { r=0.95, g=0.85, b=0.60, a=1    }
local COLOR_TEXTO_DIM  = { r=0.55, g=0.50, b=0.35, a=1    }
local COLOR_ROJO       = { r=1.0,  g=0.3,  b=0.2,  a=1    }
local COLOR_VERDE      = { r=0.3,  g=1.0,  b=0.3,  a=1    }

-- ─────────────────────────────────────────────
--  OVERLAY DE RADIO
--  Vive siempre en pantalla cuando hay una base definida.
--  INDEPENDIENTE del panel F10 — no se destruye al cerrar el panel.
-- ─────────────────────────────────────────────

HoldoorOverlay = ISPanel:derive("HoldoorOverlay")

function HoldoorOverlay:new()
    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    local o = ISPanel.new(self, 0, 0, sw, sh)
    setmetatable(o, self)
    self.__index = self
    o.backgroundColor = { r=0, g=0, b=0, a=0 }
    o.borderColor     = { r=0, g=0, b=0, a=0 }
    o.moveWithMouse   = false
    return o
end

function HoldoorOverlay:initialise()
    ISPanel.initialise(self)
end

-- No capturar ningun evento de mouse (overlay completamente transparente a input)
function HoldoorOverlay:isMouseOver()            return false end
function HoldoorOverlay:onMouseDown(x, y)        return false end
function HoldoorOverlay:onMouseUp(x, y)          return false end
function HoldoorOverlay:onMouseMove(dx, dy)      return false end
function HoldoorOverlay:onRightMouseDown(x, y)   return false end
function HoldoorOverlay:onRightMouseUp(x, y)     return false end

-- Conversion mundo -> pantalla (calculo manual, jugador como centro).
-- Puede tener leve drift durante movimiento por el camera lead de PZ, pero garantiza
-- que no haya crashes accediendo a campos Java privados.
function HoldoorOverlay:worldToScreen(wx, wy, wz)
    local player = getSpecificPlayer(0)
    if not player then return nil, nil end

    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()

    local camX = player:getX()
    local camY = player:getY()
    local camZ = player:getZ()

    local zoom = 1.0
    local okZ, zv = pcall(function() return getCore():getZoom(0) end)
    if okZ and zv and zv > 0 then zoom = zv end

    local TW = 32 / zoom
    local TH = 16 / zoom

    local dx = wx - camX
    local dy = wy - camY
    local dz = (wz or camZ) - camZ

    local sx = sw / 2 + (dx - dy) * TW
    local sy = sh / 2 + (dx + dy) * TH - dz * (TW * 2)
    return sx, sy
end

function HoldoorOverlay:render()
    ISPanel.render(self)

    local est = HoldoorClient.estado

    -- Hasta que el jugador no marque la base, el overlay no muestra NADA.
    if not est.baseDefinida then return end

    -- Solo renderizar cruz/puntos cuando el panel esta abierto (modo configuracion).
    -- Cuando se cierra el panel, la base queda marcada por la BANDERA (objeto fisico).
    local panelAbierto = HoldoorUI.instancia ~= nil
        and HoldoorUI.instancia.isVisible
        and HoldoorUI.instancia:isVisible()
    if not panelAbierto then return end

    local bx = est.baseX + 0.5
    local by = est.baseY + 0.5
    local bz = est.baseZ

    -- Radio: leer del panel abierto (radioSpawnVal) si esta, sino del estado actual
    local radio = HoldoorConfig.defaults.radioSpawn
    if HoldoorUI.instancia and HoldoorUI.instancia.radioSpawnVal then
        radio = HoldoorUI.instancia.radioSpawnVal
    elseif HoldoorClient.estado.config and HoldoorClient.estado.config.radioSpawn then
        radio = HoldoorClient.estado.config.radioSpawn
    end

    local cx, cy = self:worldToScreen(bx, by, bz)
    if not cx or not cy then return end

    -- Cruz en la base
    self:drawRect(cx - 8, cy - 1, 16, 2, 0.9, 0.3, 0.8, 1.0)
    self:drawRect(cx - 1, cy - 8, 2, 16, 0.9, 0.3, 0.8, 1.0)
    self:drawText("BASE", cx + 10, cy - 8, 0.9, 0.3, 0.8, 1.0, UIFont.Small)

    -- Circulo del radio con puntos
    local STEPS = 48
    for i = 0, STEPS - 1 do
        local angle = (i / STEPS) * math.pi * 2
        local wx = bx + radio * math.cos(angle)
        local wy = by + radio * math.sin(angle)
        local sx, sy = self:worldToScreen(wx, wy, bz)
        if sx and sy then
            self:drawRect(sx - 1, sy - 1, 3, 3, 0.85, 1.0, 0.5, 0.15)
        end
    end

    -- Label del radio
    local lx, ly = self:worldToScreen(bx + radio * 0.7, by - radio * 0.7, bz)
    if lx and ly then
        self:drawText(tostring(radio) .. " celdas", lx, ly, 0.9, 1.0, 0.8, 0.2, UIFont.Small)
    end
end

-- Crea el overlay una sola vez al iniciar el juego
function HoldoorOverlay.crear()
    if HoldoorUI.overlay then return end
    local overlay = HoldoorOverlay:new()
    overlay:initialise()
    overlay:addToUIManager()
    HoldoorUI.overlay = overlay
end

-- ─────────────────────────────────────────────
--  ABRIR / CERRAR (solo el panel — el overlay es independiente)
-- ─────────────────────────────────────────────

function HoldoorUI.abrir()
    if HoldoorUI.instancia then
        if HoldoorUI.instancia:isVisible() then
            HoldoorUI.instancia:setVisible(false)
            HoldoorUI.instancia:removeFromUIManager()
        else
            HoldoorUI.instancia:setVisible(true)
            HoldoorUI.instancia:addToUIManager()
        end
        return
    end

    local panel = HoldoorPanel:new(16, 16, PANEL_W, PANEL_H)
    panel:initialise()
    panel:addToUIManager()
    HoldoorUI.instancia = panel
end

-- ─────────────────────────────────────────────
--  PANEL PRINCIPAL
-- ─────────────────────────────────────────────

HoldoorPanel = ISPanel:derive("HoldoorPanel")

function HoldoorPanel:new(x, y, w, h)
    local o = ISPanel.new(self, x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.backgroundColor = COLOR_FONDO
    o.borderColor     = COLOR_BORDE
    o.moveWithMouse   = true
    return o
end

function HoldoorPanel:initialise()
    ISPanel.initialise(self)
    self:crearContenido()
end

-- ─────────────────────────────────────────────
--  LORE SPLIT HELPER
-- ─────────────────────────────────────────────

local function splitLoreText(text)
    if not text or #text == 0 then return "", "" end
    local best = 0
    for i = 30, math.min(#text, 72) do
        if text:sub(i, i) == "." then
            best = i
            break
        end
    end
    if best > 0 and best < #text then
        return text:sub(1, best), text:sub(best + 2)
    end
    local mid = math.min(60, #text)
    while mid > 10 and text:sub(mid, mid) ~= " " do mid = mid - 1 end
    return text:sub(1, mid), text:sub(mid + 1)
end

-- ─────────────────────────────────────────────
--  CREAR CONTROLES
-- ─────────────────────────────────────────────

function HoldoorPanel:crearContenido()
    local pad = 14
    local y   = 10

    -- Titulo
    self.lblTitulo = ISLabel:new(pad, y, 30, "HOLDOOR -- Sistema de Oleadas", 0.95, 0.75, 0.3, 1, UIFont.Medium, true)
    self:addChild(self.lblTitulo)
    self.lblVersion = ISLabel:new(PANEL_W - 55, y + 5, 20, "v" .. HoldoorConfig.VERSION, 0.4, 0.4, 0.3, 1, UIFont.Small, true)
    self:addChild(self.lblVersion)
    y = y + 34

    -- Estado actual
    local lblSecEst = ISLabel:new(pad, y + 3, 18, "Estado actual", 0.7, 0.55, 0.2, 1, UIFont.Small, true)
    self:addChild(lblSecEst)
    y = y + 20

    self.lblEstado = ISLabel:new(pad, y, 18, "Estado: Inactivo", 0.7, 0.7, 0.7, 1, UIFont.Small, true)
    self:addChild(self.lblEstado)
    self.lblOleada = ISLabel:new(pad + 210, y, 18, "Oleada: -", 0.7, 0.7, 0.7, 1, UIFont.Small, true)
    self:addChild(self.lblOleada)
    y = y + 18

    self.lblBase = ISLabel:new(pad, y, 18, "Base: No definida", 0.7, 0.7, 0.7, 1, UIFont.Small, true)
    self:addChild(self.lblBase)
    y = y + 28

    -- Modo de juego
    local lblSecModo = ISLabel:new(pad, y + 3, 18, "Modo de juego", 0.7, 0.55, 0.2, 1, UIFont.Small, true)
    self:addChild(lblSecModo)
    y = y + 20

    local nModos = #HoldoorConfig.modos
    local nbw    = math.floor((PANEL_W - pad * 2 - (nModos - 1) * 4) / nModos)
    self.botonesMode = {}
    self.modoSeleccionado = 2  -- default: Normal

    for i, modo in ipairs(HoldoorConfig.modos) do
        local bx  = pad + (i - 1) * (nbw + 4)
        local btn = ISButton:new(bx, y, nbw, 30, modo.nombre, self, HoldoorPanel.onSeleccionarModo)
        btn.holdoorModoIdx    = i
        btn.backgroundColor   = { r = modo.cr * 0.22, g = modo.cg * 0.22, b = modo.cb * 0.22, a = 1 }
        btn.borderColor       = { r = modo.cr * 0.60, g = modo.cg * 0.60, b = modo.cb * 0.60, a = 1 }
        self:addChild(btn)
        self.botonesMode[i] = btn
    end
    y = y + 38

    -- Descripcion del modo seleccionado
    self.lblModoNombre = ISLabel:new(pad, y, 20, "", 1, 0.8, 0.4, 1, UIFont.Medium, true)
    self:addChild(self.lblModoNombre)
    y = y + 24

    self.lblModoDesc = ISLabel:new(pad, y, 16, "", 0.85, 0.65, 0.30, 1, UIFont.Small, true)
    self:addChild(self.lblModoDesc)
    y = y + 18

    self.lblLore1 = ISLabel:new(pad, y, 16, "", 0.55, 0.50, 0.38, 1, UIFont.Small, true)
    self:addChild(self.lblLore1)
    y = y + 16

    self.lblLore2 = ISLabel:new(pad, y, 16, "", 0.55, 0.50, 0.38, 1, UIFont.Small, true)
    self:addChild(self.lblLore2)
    y = y + 18

    self.lblModoDetalle = ISLabel:new(pad, y, 16, "", 0.50, 0.50, 0.35, 1, UIFont.Small, true)
    self:addChild(self.lblModoDetalle)
    y = y + 18

    self.lblModoRecord = ISLabel:new(pad, y, 16, "", 0.30, 0.85, 0.45, 1, UIFont.Small, true)
    self:addChild(self.lblModoRecord)
    y = y + 22

    -- Radio de spawn customizable (se inicializa con el valor del modo)
    local lblRadio = ISLabel:new(pad, y + 3, 16, "Radio de spawn:", 0.75, 0.65, 0.40, 1, UIFont.Small, true)
    self:addChild(lblRadio)

    self.radioSpawnVal = 20

    self.btnRadioM = ISButton:new(PANEL_W - 114, y, 28, 22, "-", self, HoldoorPanel.onRadioMenos)
    self.btnRadioM.backgroundColor = { r=0.25, g=0.10, b=0.10, a=1 }
    self.btnRadioM.borderColor     = { r=0.55, g=0.20, b=0.10, a=1 }
    self:addChild(self.btnRadioM)

    self.lblRadioVal = ISButton:new(PANEL_W - 82, y, 38, 22, "20", self, HoldoorPanel.doNothing)
    self.lblRadioVal.backgroundColor = { r=0.05, g=0.05, b=0.05, a=0.9 }
    self.lblRadioVal.borderColor     = { r=0.35, g=0.30, b=0.10, a=0.7 }
    self:addChild(self.lblRadioVal)

    self.btnRadioP = ISButton:new(PANEL_W - 40, y, 28, 22, "+", self, HoldoorPanel.onRadioMas)
    self.btnRadioP.backgroundColor = { r=0.10, g=0.25, b=0.10, a=1 }
    self.btnRadioP.borderColor     = { r=0.20, g=0.55, b=0.10, a=1 }
    self:addChild(self.btnRadioP)
    y = y + 28

    self.lblJugadores = ISLabel:new(pad, y, 16, "Jugadores: 1  (multiplicador x1.0)", 0.65, 0.70, 0.55, 1, UIFont.Small, true)
    self:addChild(self.lblJugadores)
    y = y + 24

    -- Checkbox real: Modo defensa (defender el brasero)
    self.modoDefensa = false
    self.tickDefensa = ISTickBox:new(pad, y, 220, 22, "", self, HoldoorPanel.onToggleDefensa)
    self.tickDefensa:initialise()
    self.tickDefensa:instantiate()
    self.tickDefensa:addOption("Modo Defensa: defender el Trono de Hierro")
    self.tickDefensa.choicesColor = { r=0.95, g=0.85, b=0.55, a=1 }
    self.tickDefensa.selected[1] = false
    self:addChild(self.tickDefensa)

    -- Status label al lado del check
    self.lblDefensaStatus = ISLabel:new(pad + 280, y + 4, 16, "DESACTIVADO", 0.55, 0.55, 0.45, 1, UIFont.Small, true)
    self:addChild(self.lblDefensaStatus)
    y = y + 28

    -- Sub-texto explicativo
    self.lblDefensaDesc = ISLabel:new(pad, y, 14,
        "Si esta activado, el Trono cae si los zombis lo rompen. Perdes la partida.",
        0.55, 0.50, 0.40, 1, UIFont.Small, true)
    self:addChild(self.lblDefensaDesc)
    y = y + 18

    -- Acciones
    local lblSecAcc = ISLabel:new(pad, y + 3, 18, "Acciones", 0.7, 0.55, 0.2, 1, UIFont.Small, true)
    self:addChild(lblSecAcc)
    y = y + 20

    local bw = math.floor((PANEL_W - pad * 2 - 8) / 2)
    local bh = 32

    self.btnBase = ISButton:new(pad, y, bw, bh, "Marcar mi base", self, self.onMarcarBase)
    self.btnBase.backgroundColor = COLOR_BOTON_BASE
    self.btnBase.borderColor = { r=0.3, g=0.5, b=0.8, a=1 }
    self:addChild(self.btnBase)

    self.btnOnda = ISButton:new(pad + bw + 8, y, bw, bh, "Forzar oleada", self, self.onOleadaManual)
    self.btnOnda.backgroundColor = COLOR_BOTON_ONDA
    self.btnOnda.borderColor = { r=0.7, g=0.4, b=0.1, a=1 }
    self:addChild(self.btnOnda)
    y = y + bh + 8

    self.btnIniciar = ISButton:new(pad, y, bw, bh, "INICIAR OLEADAS", self, self.onIniciar)
    self.btnIniciar.backgroundColor = COLOR_BOTON_OK
    self.btnIniciar.borderColor = { r=0.3, g=0.7, b=0.3, a=1 }
    self:addChild(self.btnIniciar)

    self.btnDetener = ISButton:new(pad + bw + 8, y, bw, bh, "DETENER OLEADAS", self, self.onDetener)
    self.btnDetener.backgroundColor = COLOR_BOTON_STOP
    self.btnDetener.borderColor = { r=0.7, g=0.2, b=0.2, a=1 }
    self:addChild(self.btnDetener)
    y = y + bh + 8


    self.btnCerrar = ISButton:new(pad, y, PANEL_W - pad * 2, 26, "Cerrar  (F10)", self, self.onCerrar)
    self.btnCerrar.backgroundColor = { r=0.1, g=0.1, b=0.1, a=1 }
    self.btnCerrar.borderColor = { r=0.3, g=0.3, b=0.3, a=1 }
    self:addChild(self.btnCerrar)

    self:_actualizarInfoModo(self.modoSeleccionado)
    self:actualizarEstado()
end

-- ─────────────────────────────────────────────
--  SELECTOR DE MODO
-- ─────────────────────────────────────────────

function HoldoorPanel:doNothing(button) end

function HoldoorPanel:onToggleDefensa(idx, selected)
    -- ISTickBox callback: idx=1, selected=true/false
    self.modoDefensa = (selected == true)
    if self.lblDefensaStatus then
        if self.modoDefensa then
            self.lblDefensaStatus:setName("ACTIVADO")
            self.lblDefensaStatus:setColor(1.00, 0.40, 0.20, 1)
        else
            self.lblDefensaStatus:setName("DESACTIVADO")
            self.lblDefensaStatus:setColor(0.55, 0.55, 0.45, 1)
        end
    end
end

function HoldoorPanel:onRadioMenos(button)
    local v = math.max(10, (self.radioSpawnVal or 20) - 2)
    self.radioSpawnVal = v
    if self.lblRadioVal then self.lblRadioVal:setTitle(tostring(v)) end
end

function HoldoorPanel:onRadioMas(button)
    local v = math.min(80, (self.radioSpawnVal or 20) + 2)
    self.radioSpawnVal = v
    if self.lblRadioVal then self.lblRadioVal:setTitle(tostring(v)) end
end

function HoldoorPanel:onSeleccionarModo(button)
    self.modoSeleccionado = button.holdoorModoIdx
    self:_actualizarInfoModo(self.modoSeleccionado)
end

function HoldoorPanel:_actualizarInfoModo(idx)
    local modo = HoldoorConfig.modos[idx]
    if not modo then return end

    -- Resaltar boton seleccionado con borde dorado
    for i, btn in ipairs(self.botonesMode or {}) do
        local m = HoldoorConfig.modos[i]
        if i == idx then
            btn.borderColor = { r=0.95, g=0.82, b=0.20, a=1 }
        else
            btn.borderColor = { r=m.cr*0.60, g=m.cg*0.60, b=m.cb*0.60, a=1 }
        end
    end

    self.lblModoNombre:setName(modo.nombre)
    self.lblModoNombre:setColor(modo.cr, modo.cg, modo.cb, 1)
    self.lblModoDesc:setName(modo.descripcion or "")

    -- Sincronizar radioSpawn con el default del modo (si no fue tocado manualmente)
    if self.lblRadioVal and modo.radioSpawn then
        self.radioSpawnVal = modo.radioSpawn
        self.lblRadioVal:setTitle(tostring(modo.radioSpawn))
    end

    local l1, l2 = splitLoreText(modo.lore or "")
    self.lblLore1:setName(l1)
    self.lblLore2:setName(l2)

    self.lblModoDetalle:setName(modo.detalle or "")

    local record = HoldoorClient.obtenerRecord(modo.id)
    local maxOl  = modo.maxOleadas or 0
    if record > 0 then
        self.lblModoRecord:setName("Record: oleada " .. record .. " / " .. maxOl)
        if record >= maxOl then
            self.lblModoRecord:setColor(1.0, 0.85, 0.20, 1)
        else
            self.lblModoRecord:setColor(0.30, 0.85, 0.45, 1)
        end
    else
        self.lblModoRecord:setName("Record: ninguno todavia")
        self.lblModoRecord:setColor(0.50, 0.50, 0.40, 1)
    end
end

-- ─────────────────────────────────────────────
--  ESTADO VISUAL DEL PANEL
-- ─────────────────────────────────────────────

function HoldoorPanel:actualizarEstado()
    local est = HoldoorClient.estado

    if self.lblEstado then
        if est.activo then
            local fase = est.fase or "activo"
            local faseLabel
            if fase == "preparacion" then
                local segsLeft = math.max(0, math.ceil(est.countdownFinLocal - os.time()))
                faseLabel = "PREPARACION (" .. segsLeft .. "s)"
            elseif fase == "activa" then
                faseLabel = "EN COMBATE"
            elseif fase == "pausa" then
                faseLabel = "PAUSA"
            else
                faseLabel = "ACTIVO"
            end
            self.lblEstado:setName("Estado: " .. faseLabel)
            self.lblEstado:setColor(COLOR_VERDE.r, COLOR_VERDE.g, COLOR_VERDE.b, 1)
        else
            self.lblEstado:setName("Estado: Inactivo")
            self.lblEstado:setColor(0.7, 0.7, 0.7, 1)
        end
    end

    if self.lblOleada then
        local cfg    = est.config or {}
        local maxOl  = cfg.maxOleadas or 0
        local oleada = est.oleadaActual or 0
        if oleada > 0 then
            self.lblOleada:setName("Oleada: " .. oleada .. "/" .. maxOl)
        else
            self.lblOleada:setName("Oleada: - / " .. maxOl)
        end
    end

    if self.lblBase then
        if est.baseDefinida then
            self.lblBase:setName("Base: " .. est.baseX .. ", " .. est.baseY)
            self.lblBase:setColor(0.4, 0.8, 1, 1)
        else
            self.lblBase:setName("Base: No definida -- marcala primero")
            self.lblBase:setColor(COLOR_ROJO.r, COLOR_ROJO.g, COLOR_ROJO.b, 1)
        end
    end

    if self.lblJugadores then
        local nj  = est.numJugadores or 1
        local mx  = est.playerMultiplier or 1.0
        if est.activo then
            self.lblJugadores:setName("Jugadores: " .. nj .. "  (multiplicador x" .. mx .. ")")
            self.lblJugadores:setColor(0.75, 0.95, 0.55, 1)
        else
            self.lblJugadores:setName("Jugadores: se detectan al iniciar")
            self.lblJugadores:setColor(0.55, 0.55, 0.45, 1)
        end
    end

    -- Refrescar record del modo actual (puede haber cambiado)
    if self.modoSeleccionado then
        self:_actualizarInfoModo(self.modoSeleccionado)
    end
end

-- ─────────────────────────────────────────────
--  LEER CONFIG
-- ─────────────────────────────────────────────

function HoldoorPanel:leerConfig()
    local idx  = self.modoSeleccionado or 2
    local modo = HoldoorConfig.modos[idx]
    if not modo then
        local config = {}
        for k, v in pairs(HoldoorConfig.defaults) do config[k] = v end
        return config
    end
    return {
        modoId           = modo.id,
        tamanoOleada     = modo.tamanoOleada,
        escalaPorOleada  = modo.escalaPorOleada,
        srPorOleada      = modo.srPorOleada,
        intervalSegundos = modo.intervalSegundos,
        radioSpawn       = self.radioSpawnVal or modo.radioSpawn,
        maxOleadas       = modo.maxOleadas,
        tamanoTanda      = modo.tamanoTanda,
        tandaIntervalSec = modo.tandaIntervalSec,
        testMode         = modo.testMode or false,
        modoDefensa      = self.modoDefensa or false,
        diaInicio        = 1,
        soloAdmin        = false,
    }
end

-- ─────────────────────────────────────────────
--  HANDLERS DE BOTONES
-- ─────────────────────────────────────────────

function HoldoorPanel:onMarcarBase()
    HoldoorClient.setBase()
end

function HoldoorPanel:onIniciar()
    if not HoldoorClient.estado.baseDefinida then
        if self.lblBase then
            self.lblBase:setName("Primero marca tu base!")
            self.lblBase:setColor(1, 0.3, 0.2, 1)
        end
        return
    end
    local idx  = self.modoSeleccionado or 2
    local modo = HoldoorConfig.modos[idx]
    local modoId = modo and modo.id or "normal"
    HoldoorClient.iniciar(self:leerConfig(), modoId)
end

function HoldoorPanel:onDetener()
    HoldoorClient.detener()
end

function HoldoorPanel:onOleadaManual()
    HoldoorClient.oleadaManual()
end

function HoldoorPanel:onCerrar()
    self:setVisible(false)
    self:removeFromUIManager()
    HoldoorUI.instancia = nil  -- clear ref para que el overlay sepa que el panel se cerro
end

function HoldoorPanel:onKeyPressed(key)
    if key == Keyboard.KEY_ESCAPE then
        self:onCerrar()
    end
end

-- ─────────────────────────────────────────────
--  ACTUALIZAR TODO (panel + HUD en una llamada)
-- ─────────────────────────────────────────────

function HoldoorUI.actualizarTodo()
    if HoldoorUI.instancia then HoldoorUI.instancia:actualizarEstado() end
    if HoldoorHUD and HoldoorHUD.instance then HoldoorHUD.instance:actualizarHUD() end
end

-- ─────────────────────────────────────────────
--  HUD FLOTANTE COLAPSABLE
--  Siempre visible en pantalla (esquina sup-derecha).
--  Se auto-expande cuando arranca la primera oleada.
-- ─────────────────────────────────────────────

HoldoorHUD = ISPanel:derive("HoldoorHUD")
HoldoorHUD.instance = nil

local HUD_W          = 255
local HUD_H_HEAD     = 28
local HUD_H_BODY     = 304  -- +20 por HP del brasero
local HUD_H_BODY_EXT = 424  -- altura con radar activo

local COLOR_HUD_BG   = { r=0.05, g=0.04, b=0.03, a=0.93 }
local COLOR_HUD_ORO  = { r=0.85, g=0.65, b=0.25, a=1    }
local COLOR_HUD_DIM  = { r=0.50, g=0.40, b=0.20, a=1    }
local COLOR_HUD_OK   = { r=0.30, g=1.00, b=0.35, a=1    }
local COLOR_HUD_WARN = { r=1.00, g=0.70, b=0.10, a=1    }
local COLOR_HUD_RED  = { r=1.00, g=0.25, b=0.15, a=1    }

local function amenazaInfo(oleada)
    local prox = (oleada or 0) + 1
    if prox <= 3 then
        return "Muertos vivientes", 0.70, 0.70, 0.70, "I"
    elseif prox <= 5 then
        return "Muertos + Arrastradores", 0.80, 0.75, 0.30, "II"
    elseif prox <= 8 then
        return "Mixto + Rapidos", 1.00, 0.65, 0.15, "III"
    else
        return "Horda completa", 1.00, 0.20, 0.15, "!!!"
    end
end

function HoldoorHUD:new(x, y)
    local o = ISPanel.new(self, x, y, HUD_W, HUD_H_HEAD)
    setmetatable(o, self)
    self.__index = self
    o.backgroundColor = COLOR_HUD_BG
    o.borderColor     = COLOR_BORDE
    o.moveWithMouse   = true
    o.expandido       = false
    return o
end

function HoldoorHUD:initialise()
    ISPanel.initialise(self)
    self:_crearContenido()
end

function HoldoorHUD:_crearContenido()
    local pad = 8

    -- Header
    self.lblTit = ISLabel:new(pad, 7, 16, "HOLDOOR", COLOR_HUD_ORO.r, COLOR_HUD_ORO.g, COLOR_HUD_ORO.b, 1, UIFont.Small, true)
    self:addChild(self.lblTit)

    self.lblHeadInfo = ISLabel:new(pad + 78, 7, 16, "", 0.90, 0.85, 0.55, 1, UIFont.Small, true)
    self:addChild(self.lblHeadInfo)

    self.btnToggle = ISButton:new(HUD_W - 32, 3, 28, 22, "+", self, HoldoorHUD.onToggle)
    self.btnToggle.backgroundColor = { r=0.10, g=0.09, b=0.07, a=1 }
    self.btnToggle.borderColor     = { r=0.50, g=0.35, b=0.10, a=0.7 }
    self:addChild(self.btnToggle)

    -- Body
    local y = HUD_H_HEAD + 8

    self.lblEstHUD = ISLabel:new(pad, y, 16, "Inactivo", 0.55, 0.55, 0.55, 1, UIFont.Small, true)
    self:addChild(self.lblEstHUD); y = y + 20

    self.lblOlHUD = ISLabel:new(pad, y, 16, "Oleada: --", COLOR_HUD_ORO.r, COLOR_HUD_ORO.g, COLOR_HUD_ORO.b, 1, UIFont.Small, true)
    self:addChild(self.lblOlHUD); y = y + 20

    self.lblTimHUD = ISLabel:new(pad, y, 16, "Proxima: --", 0.55, 0.55, 0.55, 1, UIFont.Small, true)
    self:addChild(self.lblTimHUD); y = y + 20

    self.lblFzaHUD = ISLabel:new(pad, y, 16, "Siguiente: --", 0.85, 0.70, 0.40, 1, UIFont.Small, true)
    self:addChild(self.lblFzaHUD); y = y + 20

    self.lblAmenHUD = ISLabel:new(pad, y, 16, "Amenaza: --", 0.55, 0.55, 0.55, 1, UIFont.Small, true)
    self:addChild(self.lblAmenHUD); y = y + 20

    -- Brujula a la base (direccion cardinal + distancia categorica)
    self.lblBaseDir = ISLabel:new(pad, y, 16, "Base: no marcada", 0.55, 0.55, 0.50, 1, UIFont.Small, true)
    self:addChild(self.lblBaseDir); y = y + 20

    -- HP del Trono de Hierro
    self.lblTronoHP = ISLabel:new(pad, y, 16, "Trono: --", 0.55, 0.55, 0.50, 1, UIFont.Small, true)
    self:addChild(self.lblTronoHP); y = y + 20

    self.lblNotifHUD = ISLabel:new(pad, y, 16, "", 1, 0.85, 0.3, 1, UIFont.Small, true)
    self:addChild(self.lblNotifHUD)
    self.notifExpireSec = 0
    y = y + 22

    -- Separador visual
    y = y + 4

    -- Stats personales del jugador
    self.lblKillsHUD = ISLabel:new(pad, y, 16, "Mis bajas: --", 0.70, 0.90, 0.55, 1, UIFont.Small, true)
    self:addChild(self.lblKillsHUD)
    y = y + 18

    self.lblKillsPartidaHUD = ISLabel:new(pad, y, 16, "Total partida: --", 0.55, 0.70, 0.45, 1, UIFont.Small, true)
    self:addChild(self.lblKillsPartidaHUD)
    y = y + 22

    -- Saldo de monedas
    self.lblMonedasHUD = ISLabel:new(pad, y, 16, "Monedas: -- B  -- P  -- O", 0.95, 0.78, 0.30, 1, UIFont.Small, true)
    self:addChild(self.lblMonedasHUD)
    y = y + 22

    -- Boton enviar monedas a otro jugador
    self.btnEnviar = ISButton:new(pad, y, HUD_W - pad * 2, 24, "Enviar monedas a otro jugador", self, HoldoorHUD.onEnviar)
    self.btnEnviar.backgroundColor = { r=0.20, g=0.30, b=0.18, a=1 }
    self.btnEnviar.borderColor     = { r=0.40, g=0.65, b=0.25, a=1 }
    self:addChild(self.btnEnviar)
    y = y + 30

    -- Boton tienda
    self.btnTienda = ISButton:new(pad, y, HUD_W - pad * 2, 26, "TIENDA", self, HoldoorHUD.onTienda)
    self.btnTienda.backgroundColor = { r=0.25, g=0.12, b=0.35, a=1 }
    self.btnTienda.borderColor     = { r=0.70, g=0.30, b=0.95, a=1 }
    self:addChild(self.btnTienda)
    y = y + 34

    -- Radar — visible solo cuando quedan <= 5 zombies en oleada activa
    self.lblRadarTit = ISLabel:new(pad, y, 16, "RADAR  -- zombis restantes", 1.0, 0.30, 0.18, 1, UIFont.Small, true)
    self:addChild(self.lblRadarTit)
    y = y + 18

    self.lblRadarCount = ISLabel:new(pad, y, 16, "", 0.8, 0.6, 0.6, 1, UIFont.Small, true)
    self:addChild(self.lblRadarCount)

    -- Estado interno del radar
    self.radarVisible  = false
    self.radarZombies  = {}
    self.radarRadio    = 60
    self.radarTick     = 0

    self:_setExpandido(false)
    self:actualizarHUD()
end

function HoldoorHUD:onEnviar()
    HoldoorTransferModal.abrir()
end

function HoldoorHUD:onTienda()
    if HoldoorShop and HoldoorShop.abrir then HoldoorShop.abrir() end
end

function HoldoorHUD:onToggle()
    self:_setExpandido(not self.expandido)
end

function HoldoorHUD:_setExpandido(v)
    self.expandido = v
    local hijos = {
        self.lblEstHUD, self.lblOlHUD, self.lblTimHUD,
        self.lblFzaHUD, self.lblAmenHUD, self.lblBaseDir, self.lblTronoHP,
        self.lblNotifHUD,
        self.lblKillsHUD, self.lblKillsPartidaHUD,
        self.lblMonedasHUD, self.btnEnviar, self.btnTienda,
    }
    for _, c in ipairs(hijos) do if c then c:setVisible(v) end end
    -- Radar: visible solo si expandido Y radarVisible
    local showRadar = v and (self.radarVisible or false)
    if self.lblRadarTit   then self.lblRadarTit:setVisible(showRadar)   end
    if self.lblRadarCount then self.lblRadarCount:setVisible(showRadar) end
    local bodyH = showRadar and HUD_H_BODY_EXT or HUD_H_BODY
    self:setHeight(v and (HUD_H_HEAD + bodyH) or HUD_H_HEAD)
    if self.btnToggle then self.btnToggle:setTitle(v and "-" or "+") end
    -- Al expandir, refrescar todos los labels (saldo de monedas incluido)
    if v then self:actualizarHUD() end
end

function HoldoorHUD:mostrarNotif(texto, r, g, b)
    if not self.lblNotifHUD then return end
    self.lblNotifHUD:setName(texto)
    self.lblNotifHUD:setColor(r or 1, g or 0.85, b or 0.3, 1)
    self.notifExpireSec = os.time() + 6
    if not self.expandido then self:_setExpandido(true) end
end

function HoldoorHUD:actualizarHUD()
    -- Limpiar notificación temporal si expiró
    if self.lblNotifHUD and self.notifExpireSec and os.time() >= self.notifExpireSec and self.notifExpireSec > 0 then
        self.lblNotifHUD:setName("")
        self.notifExpireSec = 0
    end

    local est    = HoldoorClient.estado
    local activo = est.activo
    local fase   = est.fase or "inactivo"
    local oleada = est.oleadaActual or 0

    -- === HEADER (siempre visible) ===
    -- Calcular modoLbl corto (3 letras)
    local modoCorto = ""
    if est.config and est.config.modoId then
        local map = { facil="FAC", normal="NOR", dificil="DIF", pesadilla="PES", test="TST" }
        modoCorto = map[est.config.modoId] or ""
    end

    if fase == "preparacion" then
        local segsLeft = math.max(0, math.ceil(est.countdownFinLocal - os.time()))
        self.lblHeadInfo:setName("PREP " .. segsLeft .. "s " .. modoCorto)
        self.lblHeadInfo:setColor(0.90, 0.85, 0.55, 1)
    elseif fase == "activa" then
        local rest = est.zombiesRestantes or 0
        local tot  = est.zombiesTotal or 0
        local sr   = est.srTotal or 0
        local suffix = sr > 0 and ("+" .. sr .. "SR") or ""
        self.lblHeadInfo:setName("OL." .. oleada .. " " .. modoCorto .. " " .. rest .. "/" .. tot .. " " .. suffix)
        self.lblHeadInfo:setColor(COLOR_HUD_RED.r, COLOR_HUD_RED.g, COLOR_HUD_RED.b, 1)
    elseif fase == "pausa" then
        local segsLeft = math.max(0, math.ceil(est.countdownFinLocal - os.time()))
        self.lblHeadInfo:setName("OL." .. oleada .. " OK " .. segsLeft .. "s " .. modoCorto)
        self.lblHeadInfo:setColor(COLOR_HUD_OK.r, COLOR_HUD_OK.g, COLOR_HUD_OK.b, 1)
    else
        self.lblHeadInfo:setName("")
    end

    if not self.expandido then return end

    -- === BODY (solo si expandido) ===

    -- Estado (sin caracteres Unicode — solo ASCII)
    if activo then
        if fase == "activa" then
            self.lblEstHUD:setName("[EN COMBATE]")
            self.lblEstHUD:setColor(COLOR_HUD_RED.r, COLOR_HUD_RED.g, COLOR_HUD_RED.b, 1)
        elseif fase == "preparacion" then
            self.lblEstHUD:setName("[PREPARACION]")
            self.lblEstHUD:setColor(COLOR_HUD_OK.r, COLOR_HUD_OK.g, COLOR_HUD_OK.b, 1)
        elseif fase == "pausa" then
            self.lblEstHUD:setName("[PAUSA]")
            self.lblEstHUD:setColor(COLOR_HUD_OK.r, COLOR_HUD_OK.g, COLOR_HUD_OK.b, 1)
        else
            self.lblEstHUD:setName("[ACTIVO]")
            self.lblEstHUD:setColor(COLOR_HUD_OK.r, COLOR_HUD_OK.g, COLOR_HUD_OK.b, 1)
        end
    else
        self.lblEstHUD:setName("[ Inactivo ]")
        self.lblEstHUD:setColor(0.55, 0.55, 0.55, 1)
    end

    -- Oleada con dificultad
    local modoLbl = nil
    if est.config and est.config.modoId then
        for _, m in ipairs(HoldoorConfig.modos) do
            if m.id == est.config.modoId then modoLbl = m.nombre; break end
        end
    end
    if oleada > 0 then
        local maxOl = (est.config and est.config.maxOleadas) or "?"
        if modoLbl then
            self.lblOlHUD:setName("Oleada " .. oleada .. "/" .. maxOl .. "  -- " .. modoLbl)
        else
            self.lblOlHUD:setName("Oleada " .. oleada .. "/" .. maxOl)
        end
    else
        if modoLbl then
            self.lblOlHUD:setName("Modo: " .. modoLbl)
        else
            self.lblOlHUD:setName("Oleada: --")
        end
    end

    -- Timer / Kill counter (depende de la fase)
    if fase == "preparacion" then
        local segsLeft = math.max(0, math.ceil(est.countdownFinLocal - os.time()))
        if segsLeft <= 10 then
            self.lblTimHUD:setName("Proxima en: " .. segsLeft .. "s !")
            self.lblTimHUD:setColor(COLOR_HUD_RED.r, COLOR_HUD_RED.g, COLOR_HUD_RED.b, 1)
        elseif segsLeft <= 30 then
            self.lblTimHUD:setName("Proxima en: " .. segsLeft .. "s")
            self.lblTimHUD:setColor(COLOR_HUD_WARN.r, COLOR_HUD_WARN.g, COLOR_HUD_WARN.b, 1)
        else
            self.lblTimHUD:setName("Proxima en: " .. segsLeft .. "s")
            self.lblTimHUD:setColor(COLOR_HUD_OK.r, COLOR_HUD_OK.g, COLOR_HUD_OK.b, 1)
        end
    elseif fase == "activa" then
        local rest = est.zombiesRestantes or 0
        local tot  = est.zombiesTotal or 0
        local sr   = est.srTotal or 0
        local norm = tot - sr
        if sr > 0 then
            self.lblTimHUD:setName("Zombis: " .. rest .. "/" .. tot .. "  (" .. norm .. "Z + " .. sr .. " SR)")
        else
            self.lblTimHUD:setName("Zombis: " .. rest .. " / " .. tot)
        end
        if rest > 0 then
            self.lblTimHUD:setColor(COLOR_HUD_RED.r, COLOR_HUD_RED.g, COLOR_HUD_RED.b, 1)
        else
            self.lblTimHUD:setColor(COLOR_HUD_OK.r, COLOR_HUD_OK.g, COLOR_HUD_OK.b, 1)
        end
    elseif fase == "pausa" then
        local segsLeft = math.max(0, math.ceil(est.countdownFinLocal - os.time()))
        self.lblTimHUD:setName("Oleada " .. oleada .. " completada! (" .. segsLeft .. "s)")
        self.lblTimHUD:setColor(COLOR_HUD_OK.r, COLOR_HUD_OK.g, COLOR_HUD_OK.b, 1)
    else
        self.lblTimHUD:setName("Proxima: --")
        self.lblTimHUD:setColor(0.55, 0.55, 0.55, 1)
    end

    -- Fuerza de la próxima oleada
    if activo then
        local cfg    = est.config or {}
        local tam    = cfg.tamanoOleada or 20
        local prox   = oleada + 1
        local escala = math.min(1 + (prox - 1) * 0.1, 3.0)
        local nZom   = math.floor(tam * escala)
        self.lblFzaHUD:setName("Siguiente: ~" .. nZom .. " zombis")
        self.lblFzaHUD:setColor(0.85, 0.70, 0.40, 1)
    else
        self.lblFzaHUD:setName("Siguiente: --")
        self.lblFzaHUD:setColor(0.55, 0.55, 0.55, 1)
    end

    -- Amenaza
    if activo then
        local texto, r, g, b, nivel = amenazaInfo(oleada)
        self.lblAmenHUD:setName("[" .. nivel .. "] " .. texto)
        self.lblAmenHUD:setColor(r, g, b, 1)
    else
        self.lblAmenHUD:setName("Amenaza: --")
        self.lblAmenHUD:setColor(0.55, 0.55, 0.55, 1)
    end

    -- Brujula a la base
    if self.lblBaseDir then
        if est.baseDefinida then
            local p = getSpecificPlayer(0)
            if p then
                local px = p:getX()
                local py = p:getY()
                local dx = est.baseX - px
                local dy = est.baseY - py
                local dist = math.sqrt(dx * dx + dy * dy)

                -- Direccion cardinal en 8 sectores (comparando dx/dy)
                local absX = math.abs(dx)
                local absY = math.abs(dy)
                local dir
                if dist < 1.5 then
                    dir = "AQUI"
                elseif absX > absY * 2 then
                    dir = (dx > 0) and "Este" or "Oeste"
                elseif absY > absX * 2 then
                    dir = (dy > 0) and "Sur" or "Norte"
                else
                    if dx > 0 and dy > 0 then dir = "Sureste"
                    elseif dx > 0 and dy < 0 then dir = "Noreste"
                    elseif dx < 0 and dy > 0 then dir = "Suroeste"
                    else dir = "Noroeste" end
                end

                -- Distancia categorica (umbrales absolutos para que matchee la intuicion).
                -- "En zona spawn" se muestra extra cuando estas dentro del radio del juego.
                local radio = (est.config and est.config.radioSpawn) or 20
                local cat, cr, cg, cb
                if dist < 2 then
                    cat = "EN LA BASE"; cr, cg, cb = 0.30, 1.00, 0.40
                elseif dist < 8 then
                    cat = "Muy Cerca";  cr, cg, cb = 0.50, 0.95, 0.50
                elseif dist < 20 then
                    cat = "Cerca";      cr, cg, cb = 0.75, 0.95, 0.50
                elseif dist < 50 then
                    cat = "Media";      cr, cg, cb = 0.95, 0.85, 0.40
                elseif dist < 120 then
                    cat = "Lejos";      cr, cg, cb = 0.95, 0.55, 0.20
                else
                    cat = "Muy Lejos";  cr, cg, cb = 0.90, 0.30, 0.20
                end
                -- Sufijo opcional si estas dentro del radio de spawn (zona donde aparecen zombis)
                if dist > 2 and dist <= radio then
                    cat = cat .. "  (en zona)"
                end

                self.lblBaseDir:setName("Base: " .. dir .. "  --  " .. cat)
                self.lblBaseDir:setColor(cr, cg, cb, 1)
            end
        else
            self.lblBaseDir:setName("Base: no marcada")
            self.lblBaseDir:setColor(0.55, 0.55, 0.50, 1)
        end
    end

    -- HP del Trono de Hierro
    if self.lblTronoHP then
        local hp = est.tronoHP or 0
        local maxHp = est.tronoMaxHP or 0
        if maxHp > 0 then
            local pct = hp / maxHp
            local cr, cg, cb
            if pct > 0.60 then cr, cg, cb = 0.30, 1.00, 0.40
            elseif pct > 0.30 then cr, cg, cb = 0.95, 0.85, 0.30
            else cr, cg, cb = 1.00, 0.30, 0.20 end
            self.lblTronoHP:setName("Trono: " .. hp .. " / " .. maxHp .. "  HP")
            self.lblTronoHP:setColor(cr, cg, cb, 1)
        else
            self.lblTronoHP:setName("Trono: --")
            self.lblTronoHP:setColor(0.55, 0.55, 0.50, 1)
        end
    end

    -- Radar: activar/desactivar segun zombies restantes
    local zombiesLeft = est.zombiesRestantes or 0
    local mostrarRadar = (est.fase == "activa" and zombiesLeft > 0 and zombiesLeft <= 5)
    if mostrarRadar ~= self.radarVisible then
        self.radarVisible = mostrarRadar
        self.radarTick    = 89  -- forzar escaneo inmediato al activarse
        if mostrarRadar then self:_scanZombies() end
        -- Reajustar altura del HUD
        if self.expandido then
            local bodyH = mostrarRadar and HUD_H_BODY_EXT or HUD_H_BODY
            self:setHeight(HUD_H_HEAD + bodyH)
        end
        if self.lblRadarTit   then self.lblRadarTit:setVisible(self.expandido and mostrarRadar)   end
        if self.lblRadarCount then self.lblRadarCount:setVisible(self.expandido and mostrarRadar) end
    end
    if mostrarRadar and self.lblRadarCount then
        self.lblRadarCount:setName("Buscando: " .. zombiesLeft .. " zombie" .. (zombiesLeft > 1 and "s" or ""))
    end

    -- Stats personales
    local ko = est.killsOleada  or 0
    local kp = est.killsPartida or 0
    if self.lblKillsHUD then
        if activo then
            self.lblKillsHUD:setName("Mis bajas (oleada): " .. ko)
            self.lblKillsHUD:setColor(0.70, 0.95, 0.55, 1)
        else
            self.lblKillsHUD:setName("Mis bajas (oleada): --")
            self.lblKillsHUD:setColor(0.50, 0.55, 0.40, 1)
        end
    end
    if self.lblKillsPartidaHUD then
        if kp > 0 then
            self.lblKillsPartidaHUD:setName("Total partida: " .. kp)
            self.lblKillsPartidaHUD:setColor(0.55, 0.75, 0.45, 1)
        else
            self.lblKillsPartidaHUD:setName("Total partida: --")
            self.lblKillsPartidaHUD:setColor(0.45, 0.45, 0.38, 1)
        end
    end

    -- Saldo de monedas (lee ModData del jugador)
    if self.lblMonedasHUD and HoldoorClient.getSaldo then
        local b, s, g = HoldoorClient.getSaldo()
        self.lblMonedasHUD:setName("Monedas: " .. b .. " B   " .. s .. " P   " .. g .. " O")
    end
end

-- Escanea tiles alrededor del JUGADOR buscando IsoZombies vivos.
-- Los dx/dy guardados son relativos al jugador (no a la base).
function HoldoorHUD:_scanZombies()
    local ok_p, player = pcall(getSpecificPlayer, 0)
    if not ok_p or not player then self.radarZombies = {}; return end
    local px = math.floor(player:getX())
    local py = math.floor(player:getY())
    local pz = math.floor(player:getZ())
    local radio = 35  -- tiles alrededor del jugador
    self.radarRadio = radio

    local ok_cell, cell = pcall(getCell)
    if not ok_cell or not cell then self.radarZombies = {}; return end

    local found = {}
    for dx = -radio, radio do
        for dy = -radio, radio do
            if dx * dx + dy * dy <= radio * radio then
                local ok_sq, sq = pcall(function() return cell:getGridSquare(px+dx, py+dy, pz) end)
                if ok_sq and sq then
                    local ok_mo, objs = pcall(function() return sq:getMovingObjects() end)
                    if ok_mo and objs then
                        local ok_sz, sz = pcall(function() return objs:size() end)
                        if ok_sz and sz then
                            for i = 0, sz - 1 do
                                local ok_g, obj = pcall(function() return objs:get(i) end)
                                if ok_g and obj and instanceof(obj, "IsoZombie") then
                                    table.insert(found, {dx=dx, dy=dy})
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    self.radarZombies = found
end

function HoldoorHUD:render()
    ISPanel.render(self)
    self:drawRect(0, HUD_H_HEAD - 1, HUD_W, 1, 0.6, 0.4, 0.1, 0.6)
    if self.expandido then
        self:drawRect(0, HUD_H_HEAD, HUD_W, self.height - HUD_H_HEAD, 0.0, 0.0, 0.0, 0.15)
        -- Separador entre info de oleada y stats personales
        local sepY = HUD_H_HEAD + 148
        self:drawRect(8, sepY, HUD_W - 16, 1, 0.35, 0.45, 0.25, 0.7)
    end

    -- Radar: escanear cada ~90 frames y dibujar cuando es visible
    if self.expandido and self.radarVisible then
        self.radarTick = (self.radarTick or 0) + 1
        if self.radarTick % 90 == 0 then
            self:_scanZombies()
        end

        local RADAR_W = HUD_W - 20
        local RADAR_H = 90
        local rx      = 10
        local ry      = HUD_H_HEAD + 228  -- debajo del separador de kills + TIENDA

        -- Fondo + borde del radar
        self:drawRect(rx, ry, RADAR_W, RADAR_H, 0.92, 0.02, 0.02, 0.02)
        self:drawRect(rx, ry,          RADAR_W, 1,       0.9, 1.0, 0.3, 0.2)
        self:drawRect(rx, ry+RADAR_H-1, RADAR_W, 1,      0.9, 1.0, 0.3, 0.2)
        self:drawRect(rx,          ry, 1, RADAR_H,       0.9, 1.0, 0.3, 0.2)
        self:drawRect(rx+RADAR_W-1, ry, 1, RADAR_H,      0.9, 1.0, 0.3, 0.2)

        -- Cruz central = posicion del JUGADOR
        local cx = rx + RADAR_W / 2
        local cy = ry + RADAR_H / 2
        self:drawRect(cx - 4, cy - 1, 8, 2, 1, 0.3, 1.0, 0.5)
        self:drawRect(cx - 1, cy - 4, 2, 8, 1, 0.3, 1.0, 0.5)

        local radio = self.radarRadio or 35
        local scaleX = (RADAR_W / 2 - 5) / radio
        local scaleY = (RADAR_H / 2 - 5) / radio

        -- Punto azul = posicion de la base relativa al jugador
        local ok_pr, playerR = pcall(getSpecificPlayer, 0)
        if ok_pr and playerR then
            local estR = HoldoorClient.estado
            if estR.baseDefinida then
                local bDx = estR.baseX - math.floor(playerR:getX())
                local bDy = estR.baseY - math.floor(playerR:getY())
                local bX  = math.max(rx + 2, math.min(rx + RADAR_W - 5, cx + bDx * scaleX - 2))
                local bY  = math.max(ry + 2, math.min(ry + RADAR_H - 5, cy + bDy * scaleY - 2))
                self:drawRect(bX, bY, 5, 5, 1, 0.2, 0.55, 1.0)
            end
        end

        -- Puntos rojos = zombies relativos al jugador
        for _, z in ipairs(self.radarZombies or {}) do
            local dotX = cx + z.dx * scaleX - 2
            local dotY = cy + z.dy * scaleY - 2
            dotX = math.max(rx + 2, math.min(rx + RADAR_W - 5, dotX))
            dotY = math.max(ry + 2, math.min(ry + RADAR_H - 5, dotY))
            self:drawRect(dotX, dotY, 4, 4, 1, 1.0, 0.18, 0.18)
        end
    end
end

-- ─────────────────────────────────────────────
--  Lifecycle del HUD
-- ─────────────────────────────────────────────

function HoldoorHUD.crear()
    if HoldoorHUD.instance then return end
    local sw = getCore():getScreenWidth()
    local hud = HoldoorHUD:new(sw - HUD_W - 16, 16)
    hud:initialise()
    hud:addToUIManager()
    HoldoorHUD.instance = hud
    HoldoorOverlay.crear()
    HoldoorAnnounce.crear()
end

Events.OnGameStart.Add(HoldoorHUD.crear)

-- ─────────────────────────────────────────────
--  ANUNCIO ÉPICO CENTRADO
--  Aparece en el centro de la pantalla con fade in/out.
--  No bloquea input — overlay transparente a mouse.
-- ─────────────────────────────────────────────

HoldoorAnnounce = ISPanel:derive("HoldoorAnnounce")
HoldoorAnnounce.instance = nil

function HoldoorAnnounce:new()
    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    local o  = ISPanel.new(self, 0, 0, sw, sh)
    setmetatable(o, self)
    self.__index      = self
    o.backgroundColor = {r=0, g=0, b=0, a=0}
    o.borderColor     = {r=0, g=0, b=0, a=0}
    o.moveWithMouse   = false
    o.anuncioTitulo   = ""
    o.anuncioSub      = ""
    o.anuncioKills    = ""
    o.anuncioR        = 1
    o.anuncioG        = 0.8
    o.anuncioB        = 0.2
    o.anuncioTick     = 99999
    o.anuncioMaxTicks = 240
    return o
end

function HoldoorAnnounce:initialise()
    ISPanel.initialise(self)
end

function HoldoorAnnounce:isMouseOver()          return false end
function HoldoorAnnounce:onMouseDown(x, y)      return false end
function HoldoorAnnounce:onMouseUp(x, y)        return false end
function HoldoorAnnounce:onRightMouseDown(x, y) return false end
function HoldoorAnnounce:onRightMouseUp(x, y)   return false end

-- titulo: texto grande | sub: texto chico | kills: ranking (puede ser "") | duracionTicks ~60fps
function HoldoorAnnounce.mostrar(titulo, sub, r, g, b, duracionTicks, kills)
    local inst = HoldoorAnnounce.instance
    if not inst then return end
    inst.anuncioTitulo   = titulo or ""
    inst.anuncioSub      = sub or ""
    inst.anuncioKills    = kills or ""
    inst.anuncioR        = r or 1
    inst.anuncioG        = g or 0.8
    inst.anuncioB        = b or 0.2
    inst.anuncioTick     = 0
    inst.anuncioMaxTicks = duracionTicks or 240
    inst:setVisible(true)
end

function HoldoorAnnounce.crear()
    if HoldoorAnnounce.instance then return end
    local inst = HoldoorAnnounce:new()
    inst:initialise()
    inst:addToUIManager()
    inst:setVisible(false)
    HoldoorAnnounce.instance = inst
end

function HoldoorAnnounce:render()
    ISPanel.render(self)

    local maxTicks = self.anuncioMaxTicks or 240
    self.anuncioTick = (self.anuncioTick or maxTicks) + 1

    if self.anuncioTick >= maxTicks or not self.anuncioTitulo or self.anuncioTitulo == "" then
        self:setVisible(false)
        return
    end

    -- Alpha fade in (15 ticks) / fade out (25 ticks)
    local alpha
    local fadeIn  = 15
    local fadeOut = 25
    if self.anuncioTick < fadeIn then
        alpha = self.anuncioTick / fadeIn
    elseif self.anuncioTick > maxTicks - fadeOut then
        alpha = (maxTicks - self.anuncioTick) / fadeOut
    else
        alpha = 1.0
    end
    alpha = math.max(0, math.min(1, alpha))

    local sw = self.width
    local sh = self.height
    local cy = sh / 2
    local hasKills = self.anuncioKills and self.anuncioKills ~= ""
    local barH = hasKills and 160 or 110

    -- Fondo oscuro con líneas de color
    self:drawRect(0, cy - barH/2, sw, barH, 0.70 * alpha, 0, 0, 0)
    self:drawRect(0, cy - barH/2,      sw, 2, alpha, self.anuncioR, self.anuncioG, self.anuncioB)
    self:drawRect(0, cy + barH/2 - 2,  sw, 2, alpha, self.anuncioR, self.anuncioG, self.anuncioB)

    local tm = getTextManager()

    -- Título grande
    local titleW = tm:MeasureStringX(UIFont.Large, self.anuncioTitulo)
    local titleH = tm:MeasureStringY(UIFont.Large, self.anuncioTitulo)
    local titleY = cy - titleH - (hasKills and 20 or 8)
    self:drawText(self.anuncioTitulo, sw/2 - titleW/2, titleY,
                  self.anuncioR, self.anuncioG, self.anuncioB, alpha, UIFont.Large)

    -- Subtítulo
    if self.anuncioSub and self.anuncioSub ~= "" then
        local subW = tm:MeasureStringX(UIFont.Medium, self.anuncioSub)
        self:drawText(self.anuncioSub, sw/2 - subW/2, cy + 8,
                      0.90, 0.82, 0.55, alpha * 0.92, UIFont.Medium)
    end

    -- Kills ranking (opcional, debajo del subtítulo)
    if hasKills then
        local kW = tm:MeasureStringX(UIFont.Small, self.anuncioKills)
        self:drawText(self.anuncioKills, sw/2 - kW/2, cy + 36,
                      0.65, 0.95, 0.55, alpha * 0.88, UIFont.Small)
    end
end

-- ─────────────────────────────────────────────
--  MODAL DE TRANSFERENCIA DE MONEDAS
-- ─────────────────────────────────────────────

HoldoorTransferModal = ISPanel:derive("HoldoorTransferModal")
HoldoorTransferModal.instance = nil

local TM_W = 380
local TM_H = 300

function HoldoorTransferModal.abrir()
    if HoldoorTransferModal.instance then
        HoldoorTransferModal.instance:removeFromUIManager()
        HoldoorTransferModal.instance = nil
    end
    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    local m = HoldoorTransferModal:new((sw - TM_W) / 2, (sh - TM_H) / 2, TM_W, TM_H)
    m:initialise()
    m:addToUIManager()
    HoldoorTransferModal.instance = m
end

function HoldoorTransferModal:new(x, y, w, h)
    local o = ISPanel.new(self, x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.backgroundColor  = COLOR_FONDO
    o.borderColor      = COLOR_BORDE
    o.moveWithMouse    = true
    o.tipoSeleccionado = "bronze"
    return o
end

function HoldoorTransferModal:initialise()
    ISPanel.initialise(self)
    local pad = 14
    local y   = 12

    self.lblTit = ISLabel:new(pad, y, 24, "Enviar Monedas", 0.95, 0.78, 0.30, 1, UIFont.Medium, true)
    self:addChild(self.lblTit); y = y + 30

    -- Destinatario
    self.lblDest = ISLabel:new(pad, y, 16, "Destinatario:", 0.85, 0.75, 0.40, 1, UIFont.Small, true)
    self:addChild(self.lblDest); y = y + 18

    local jugadores = HoldoorClient.jugadoresConectados()
    self.sinJugadores = (#jugadores == 0)
    self.combo = ISComboBox:new(pad, y, TM_W - pad * 2, 24, self, HoldoorTransferModal.doNothing)
    self:addChild(self.combo)
    if self.sinJugadores then
        self.combo:addOption("(no hay jugadores conectados)")
    else
        for _, name in ipairs(jugadores) do self.combo:addOption(name) end
    end
    y = y + 34

    -- Tipo
    self.lblTipo = ISLabel:new(pad, y, 16, "Tipo de moneda:", 0.85, 0.75, 0.40, 1, UIFont.Small, true)
    self:addChild(self.lblTipo); y = y + 18

    local btnW = math.floor((TM_W - pad * 2 - 8) / 3)
    self.btnBronze = ISButton:new(pad, y, btnW, 28, "Bronce", self, HoldoorTransferModal.onSelectTipo)
    self.btnBronze.tipo = "bronze"
    self.btnBronze.backgroundColor = { r=0.45, g=0.25, b=0.05, a=1 }
    self:addChild(self.btnBronze)

    self.btnSilver = ISButton:new(pad + btnW + 4, y, btnW, 28, "Plata", self, HoldoorTransferModal.onSelectTipo)
    self.btnSilver.tipo = "silver"
    self.btnSilver.backgroundColor = { r=0.40, g=0.40, b=0.45, a=1 }
    self:addChild(self.btnSilver)

    self.btnGold = ISButton:new(pad + (btnW + 4) * 2, y, btnW, 28, "Oro", self, HoldoorTransferModal.onSelectTipo)
    self.btnGold.tipo = "gold"
    self.btnGold.backgroundColor = { r=0.55, g=0.40, b=0.10, a=1 }
    self:addChild(self.btnGold)
    y = y + 38

    -- Saldo
    self.lblSaldo = ISLabel:new(pad, y, 16, "Saldo disponible: --", 0.65, 0.85, 0.50, 1, UIFont.Small, true)
    self:addChild(self.lblSaldo); y = y + 22

    -- Cantidad
    self.lblCant = ISLabel:new(pad, y, 16, "Cantidad:", 0.85, 0.75, 0.40, 1, UIFont.Small, true)
    self:addChild(self.lblCant); y = y + 18

    self.txtCantidad = ISTextEntryBox:new("", pad, y, TM_W - pad * 2, 24)
    self.txtCantidad:initialise()
    self.txtCantidad:instantiate()
    self.txtCantidad:setOnlyNumbers(true)
    self:addChild(self.txtCantidad)
    y = y + 34

    -- Acciones
    local bw = math.floor((TM_W - pad * 2 - 8) / 2)
    self.btnEnviar = ISButton:new(pad, y, bw, 30, "ENVIAR", self, HoldoorTransferModal.onEnviar)
    self.btnEnviar.backgroundColor = COLOR_BOTON_OK
    self.btnEnviar.borderColor     = { r=0.3, g=0.7, b=0.3, a=1 }
    self:addChild(self.btnEnviar)

    self.btnCancel = ISButton:new(pad + bw + 8, y, bw, 30, "Cancelar", self, HoldoorTransferModal.onCancel)
    self.btnCancel.backgroundColor = COLOR_BOTON_STOP
    self.btnCancel.borderColor     = { r=0.7, g=0.2, b=0.2, a=1 }
    self:addChild(self.btnCancel)

    self:_refreshTipo()
end

function HoldoorTransferModal:doNothing() end

function HoldoorTransferModal:_refreshTipo()
    local map = { bronze=self.btnBronze, silver=self.btnSilver, gold=self.btnGold }
    for k, b in pairs(map) do
        if b then
            if k == self.tipoSeleccionado then
                b.borderColor = { r=0.95, g=0.82, b=0.20, a=1 }
            else
                b.borderColor = { r=0.30, g=0.30, b=0.30, a=1 }
            end
        end
    end
    if self.lblSaldo and HoldoorClient.getSaldo then
        local bz, sl, gd = HoldoorClient.getSaldo()
        local saldo, lbl
        if self.tipoSeleccionado == "bronze" then saldo, lbl = bz, "Bronce"
        elseif self.tipoSeleccionado == "silver" then saldo, lbl = sl, "Plata"
        else saldo, lbl = gd, "Oro" end
        self.lblSaldo:setName("Saldo disponible: " .. saldo .. " " .. lbl)
    end
end

function HoldoorTransferModal:onSelectTipo(button)
    self.tipoSeleccionado = button.tipo
    self:_refreshTipo()
end

function HoldoorTransferModal:onEnviar()
    if self.sinJugadores then
        HoldoorClient.chat("[HOLDOOR] No hay otros jugadores conectados.", 1, 0.6, 0.2)
        return
    end
    local target = self.combo:getOptionText(self.combo.selected)
    if not target or target == "" then
        HoldoorClient.chat("[HOLDOOR] Elegi un destinatario.", 1, 0.4, 0.2)
        return
    end
    local cantidad = tonumber(self.txtCantidad:getInternalText()) or 0
    if cantidad <= 0 then
        HoldoorClient.chat("[HOLDOOR] Ingresa una cantidad valida.", 1, 0.4, 0.2)
        return
    end
    HoldoorClient.transferir(target, self.tipoSeleccionado, cantidad)
    self:onCancel()
end

function HoldoorTransferModal:onCancel()
    self:setVisible(false)
    self:removeFromUIManager()
    HoldoorTransferModal.instance = nil
end

function HoldoorTransferModal:onKeyPressed(key)
    if key == Keyboard.KEY_ESCAPE then self:onCancel() end
end
