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
local PANEL_H = 624  -- +18 por lbl HP Trono + +42 por boton TEST + +24 padding inferior (2026-06-16)

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
    -- CLAVE: ISPanel por default tiene wantMouseEvents=true → el motor Java consume
    -- eventos del mouse aunque los handlers Lua devuelvan false. Hay que apagarlo
    -- explicitamente para que el inventario y otras UIs no se rompan.
    pcall(function() self:setWantMouseEvents(false) end)
end

-- No capturar NINGUN evento de mouse (overlay completamente transparente a input).
-- Importante: ISUIElement por DEFAULT devuelve true en los handlers -> consume eventos.
-- Hay que overridear los 10 handlers para no romper hover/click de otras UIs (inventario, etc).
function HoldoorOverlay:isMouseOver()              return false end
function HoldoorOverlay:onMouseDown(x, y)          return false end
function HoldoorOverlay:onMouseUp(x, y)            return false end
function HoldoorOverlay:onMouseMove(dx, dy)        return false end
function HoldoorOverlay:onMouseMoveOutside(dx, dy) return false end
function HoldoorOverlay:onMouseDownOutside(x, y)   return false end
function HoldoorOverlay:onMouseUpOutside(x, y)     return false end
function HoldoorOverlay:onRightMouseDown(x, y)     return false end
function HoldoorOverlay:onRightMouseUp(x, y)       return false end
function HoldoorOverlay:onMouseWheel(del)          return false end

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

    -- v0.7 #14d: Circulo del radio con puntos VISIBLES.
    -- Antes: 3x3 px / alpha 0.15 / amarillo-verde → invisibles sobre cesped.
    -- Ahora: 8x8 px / alpha 1.0 / naranja brillante con borde negro para contraste.
    -- worldToScreen ya escala con zoom (TW/TH = 32|16 / zoom). El radio en MUNDO
    -- se mantiene fijo; al hacer zoom las pelotitas se separan mas en pantalla.
    -- Tamano en pixeles es fijo (no se achica al alejar camara — siempre legible).
    local STEPS = 48
    for i = 0, STEPS - 1 do
        local angle = (i / STEPS) * math.pi * 2
        local wx = bx + radio * math.cos(angle)
        local wy = by + radio * math.sin(angle)
        local sx, sy = self:worldToScreen(wx, wy, bz)
        if sx and sy then
            -- Borde negro 10x10 (contraste sobre cesped/calle/lo que sea)
            self:drawRect(sx - 5, sy - 5, 10, 10, 1.0, 0.0, 0.0, 0.0)
            -- Punto naranja brillante 8x8 sobre el borde
            self:drawRect(sx - 4, sy - 4, 8, 8, 1.0, 1.0, 0.55, 0.10)
        end
    end

    -- Label del radio (drawText args: text, x, y, r, g, b, a, font — alpha al final)
    local lx, ly = self:worldToScreen(bx + radio * 0.7, by - radio * 0.7, bz)
    if lx and ly then
        -- Sombra negra desplazada 1px (legibilidad sobre cualquier fondo)
        self:drawText(tostring(radio) .. " celdas", lx + 1, ly + 1, 0.0, 0.0, 0.0, 1.0, UIFont.Small)
        -- Texto naranja brillante encima
        self:drawText(tostring(radio) .. " celdas", lx,     ly,     1.0, 0.55, 0.10, 1.0, UIFont.Small)
    end
end

-- Crea el overlay una sola vez al iniciar el juego.
-- v0.6.1: arranca con setVisible(false) — en B42 los panels invisibles SON ignorados
-- por el dispatcher de mouse, los visibles NO (aunque tengan setWantMouseEvents=false).
-- El overlay se activa al abrir el panel admin (HoldoorUI.abrir) y se oculta al cerrar.
function HoldoorOverlay.crear()
    if HoldoorUI.overlay then return end
    local overlay = HoldoorOverlay:new()
    overlay:initialise()
    overlay:addToUIManager()
    overlay:setVisible(false)
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
            -- v0.6.1: panel cerrado → overlay oculto (sino bloquea mouse del inventario)
            if HoldoorUI.overlay then HoldoorUI.overlay:setVisible(false) end
        else
            HoldoorUI.instancia:setVisible(true)
            HoldoorUI.instancia:addToUIManager()
            -- v0.6.1: panel abierto → overlay visible solo si hay base marcada
            if HoldoorUI.overlay and HoldoorClient and HoldoorClient.estado and HoldoorClient.estado.baseDefinida then
                HoldoorUI.overlay:setVisible(true)
            end
        end
        return
    end

    local panel = HoldoorPanel:new(16, 16, PANEL_W, PANEL_H)
    panel:initialise()
    panel:addToUIManager()
    HoldoorUI.instancia = panel
    -- v0.6.1: panel recien abierto → overlay visible si hay base
    if HoldoorUI.overlay and HoldoorClient and HoldoorClient.estado and HoldoorClient.estado.baseDefinida then
        HoldoorUI.overlay:setVisible(true)
    end
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
    self.lblTitulo = ISLabel:new(pad, y, 30, getText("UI_Holdoor_panel_titulo"), 0.95, 0.75, 0.3, 1, UIFont.Medium, true)
    self:addChild(self.lblTitulo)
    self.lblVersion = ISLabel:new(PANEL_W - 55, y + 5, 20, "v" .. HoldoorConfig.VERSION, 0.4, 0.4, 0.3, 1, UIFont.Small, true)
    self:addChild(self.lblVersion)
    y = y + 34

    -- Estado actual
    local lblSecEst = ISLabel:new(pad, y + 3, 18, getText("UI_Holdoor_panel_estadoactual"), 0.7, 0.55, 0.2, 1, UIFont.Small, true)
    self:addChild(lblSecEst)
    y = y + 20

    self.lblEstado = ISLabel:new(pad, y, 18, getText("UI_Holdoor_panel_estadolbl") .. ": " .. getText("UI_Holdoor_fase_inactivo"), 0.7, 0.7, 0.7, 1, UIFont.Small, true)
    self:addChild(self.lblEstado)
    self.lblOleada = ISLabel:new(pad + 210, y, 18, getText("UI_Holdoor_panel_oleadalbl") .. ": -", 0.7, 0.7, 0.7, 1, UIFont.Small, true)
    self:addChild(self.lblOleada)
    y = y + 18

    self.lblBase = ISLabel:new(pad, y, 18, getText("UI_Holdoor_panel_baselbl") .. ": " .. getText("UI_Holdoor_panel_basenodef"), 0.7, 0.7, 0.7, 1, UIFont.Small, true)
    self:addChild(self.lblBase)
    y = y + 28

    -- Modo de juego
    local lblSecModo = ISLabel:new(pad, y + 3, 18, getText("UI_Holdoor_panel_modojuego"), 0.7, 0.55, 0.2, 1, UIFont.Small, true)
    self:addChild(lblSecModo)
    y = y + 20

    local nModos = #HoldoorConfig.modos
    local nbw    = math.floor((PANEL_W - pad * 2 - (nModos - 1) * 4) / nModos)
    self.botonesMode = {}
    self.modoSeleccionado = 2  -- default: Normal

    for i, modo in ipairs(HoldoorConfig.modos) do
        local bx  = pad + (i - 1) * (nbw + 4)
        local btn = ISButton:new(bx, y, nbw, 30, getText("UI_Holdoor_modo_" .. modo.id .. "_nombre"), self, HoldoorPanel.onSeleccionarModo)
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

    -- HP del Trono segun el modo (1500/1250/1100/1000) — info importante para el player
    self.lblModoHP = ISLabel:new(pad, y, 16, "", 0.95, 0.55, 0.35, 1, UIFont.Small, true)
    self:addChild(self.lblModoHP)
    y = y + 18

    self.lblModoRecord = ISLabel:new(pad, y, 16, "", 0.30, 0.85, 0.45, 1, UIFont.Small, true)
    self:addChild(self.lblModoRecord)
    y = y + 22

    -- Radio de spawn customizable (se inicializa con el valor del modo)
    local lblRadio = ISLabel:new(pad, y + 3, 16, getText("UI_Holdoor_panel_radiospawn"), 0.75, 0.65, 0.40, 1, UIFont.Small, true)
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

    self.lblJugadores = ISLabel:new(pad, y, 16, getText("UI_Holdoor_panel_juginit"), 0.65, 0.70, 0.55, 1, UIFont.Small, true)
    self:addChild(self.lblJugadores)
    y = y + 24

    -- Checkbox real: Modo defensa (defender el brasero)
    self.modoDefensa = true   -- ON por defecto: hace el mod mas atractivo (perdes si cae el Trono)
    self.tickDefensa = ISTickBox:new(pad, y, 220, 22, "", self, HoldoorPanel.onToggleDefensa)
    self.tickDefensa:initialise()
    self.tickDefensa:instantiate()
    self.tickDefensa:addOption(getText("UI_Holdoor_panel_defensa"))
    self.tickDefensa.choicesColor = { r=0.95, g=0.85, b=0.55, a=1 }
    self.tickDefensa.selected[1] = true
    self:addChild(self.tickDefensa)

    -- Status label al lado del check
    self.lblDefensaStatus = ISLabel:new(pad + 280, y + 4, 16, getText("UI_Holdoor_panel_activado"), 1.00, 0.40, 0.20, 1, UIFont.Small, true)
    self:addChild(self.lblDefensaStatus)
    y = y + 28

    -- Sub-texto explicativo
    self.lblDefensaDesc = ISLabel:new(pad, y, 14,
        getText("UI_Holdoor_panel_defensadesc"),
        0.55, 0.50, 0.40, 1, UIFont.Small, true)
    self:addChild(self.lblDefensaDesc)
    y = y + 18

    -- Acciones
    local lblSecAcc = ISLabel:new(pad, y + 3, 18, getText("UI_Holdoor_panel_acciones"), 0.7, 0.55, 0.2, 1, UIFont.Small, true)
    self:addChild(lblSecAcc)
    y = y + 20

    local bw = math.floor((PANEL_W - pad * 2 - 8) / 2)
    local bh = 32

    -- FILA 1: Acciones de BASE (Marcar / Quitar)
    self.btnBase = ISButton:new(pad, y, bw, bh, getText("UI_Holdoor_panel_btnmarcar"), self, self.onMarcarBase)
    self.btnBase.backgroundColor = COLOR_BOTON_BASE
    self.btnBase.borderColor = { r=0.3, g=0.5, b=0.8, a=1 }
    self:addChild(self.btnBase)

    self.btnQuitarBase = ISButton:new(pad + bw + 8, y, bw, bh, getText("UI_Holdoor_panel_btnquitar"), self, self.onQuitarBase)
    self.btnQuitarBase.backgroundColor = { r=0.35, g=0.15, b=0.20, a=1 }
    self.btnQuitarBase.borderColor     = { r=0.65, g=0.30, b=0.30, a=1 }
    self:addChild(self.btnQuitarBase)
    y = y + bh + 8

    -- FILA 2: Control de OLEADAS (Iniciar / Detener)
    self.btnIniciar = ISButton:new(pad, y, bw, bh, getText("UI_Holdoor_panel_btniniciar"), self, self.onIniciar)
    self.btnIniciar.backgroundColor = COLOR_BOTON_OK
    self.btnIniciar.borderColor = { r=0.3, g=0.7, b=0.3, a=1 }
    self:addChild(self.btnIniciar)

    self.btnDetener = ISButton:new(pad + bw + 8, y, bw, bh, getText("UI_Holdoor_panel_btndetener"), self, self.onDetener)
    self.btnDetener.backgroundColor = COLOR_BOTON_STOP
    self.btnDetener.borderColor = { r=0.7, g=0.2, b=0.2, a=1 }
    self:addChild(self.btnDetener)
    y = y + bh + 8

    -- FILA 3: Forzar oleada (manual override, secundario → full ancho)
    self.btnOnda = ISButton:new(pad, y, PANEL_W - pad * 2, bh, getText("UI_Holdoor_panel_btnforzar"), self, self.onOleadaManual)
    self.btnOnda.backgroundColor = COLOR_BOTON_ONDA
    self.btnOnda.borderColor = { r=0.7, g=0.4, b=0.1, a=1 }
    self:addChild(self.btnOnda)
    y = y + bh + 8

    -- BOTON TESTING: da monedas + materiales + items a uno mismo (para probar la tienda)
    self.btnTest = ISButton:new(pad, y, PANEL_W - pad * 2, 26,
        getText("UI_Holdoor_panel_btntest"),
        self, self.onTestDarme)
    self.btnTest.backgroundColor = { r=0.30, g=0.15, b=0.40, a=1 }
    self.btnTest.borderColor     = { r=0.7,  g=0.4,  b=0.85, a=1 }
    self:addChild(self.btnTest)
    y = y + 26 + 8

    self.btnCerrar = ISButton:new(pad, y, PANEL_W - pad * 2, 26, getText("UI_Holdoor_panel_btncerrar"), self, self.onCerrar)
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

-- [TEST ONLY] Auto-darse monedas + materiales + items para probar la tienda.
-- Solo funciona en SP/host. Es trampa intencional pensada para testeo del balance.
function HoldoorPanel:onTestDarme()
    local p
    pcall(function() p = getSpecificPlayer(0) end)
    if not p then return end

    local md
    pcall(function() md = p:getModData() end)
    if not md then return end

    -- Monedas: 500 bronce, 100 plata, 100 oro
    md.Holdoor_Bronze = (md.Holdoor_Bronze or 0) + 500
    md.Holdoor_Silver = (md.Holdoor_Silver or 0) + 100
    md.Holdoor_Gold   = (md.Holdoor_Gold   or 0) + 100

    -- Materiales: 50 de cada uno
    md.Holdoor_Cuero     = (md.Holdoor_Cuero     or 0) + 50
    md.Holdoor_Hierro    = (md.Holdoor_Hierro    or 0) + 50
    md.Holdoor_Acero     = (md.Holdoor_Acero     or 0) + 50
    md.Holdoor_Valyrio   = (md.Holdoor_Valyrio   or 0) + 50
    md.Holdoor_Obsidiana = (md.Holdoor_Obsidiana or 0) + 50

    -- Persistir ModData server-side (gotcha #51)
    pcall(function() p:transmitModData() end)

    -- NO se agregan items al inventario por pedido del user (solo monedas y materiales)
    pcall(function() p:setHaloNote("[TEST] +500B +100P +100O +50 c/u de materiales", 200, 220, 255, 360) end)
    print("[Holdoor] TEST DARME: monedas + materiales entregados a " .. p:getUsername())

    -- Refrescar el HUD/tienda si está abierta
    if HoldoorShop and HoldoorShop.refrescar then HoldoorShop.refrescar() end
    if HoldoorUI and HoldoorUI.actualizarTodo then HoldoorUI.actualizarTodo() end
end

function HoldoorPanel:onToggleDefensa(idx, selected)
    -- ISTickBox callback: idx=1, selected=true/false
    self.modoDefensa = (selected == true)
    if self.lblDefensaStatus then
        if self.modoDefensa then
            self.lblDefensaStatus:setName(getText("UI_Holdoor_panel_activado"))
            self.lblDefensaStatus:setColor(1.00, 0.40, 0.20, 1)
        else
            self.lblDefensaStatus:setName(getText("UI_Holdoor_panel_desactivado"))
            self.lblDefensaStatus:setColor(0.55, 0.55, 0.45, 1)
        end
    end
end

function HoldoorPanel:onRadioMenos(button)
    local v = math.max(10, (self.radioSpawnVal or 20) - 2)
    self.radioSpawnVal = v
    -- v0.7 #18: el user ajusto manualmente → NO sobrescribir en refresh siguientes.
    self.radioAjustadoManual = true
    if self.lblRadioVal then self.lblRadioVal:setTitle(tostring(v)) end
end

function HoldoorPanel:onRadioMas(button)
    local v = math.min(80, (self.radioSpawnVal or 20) + 2)
    self.radioSpawnVal = v
    -- v0.7 #18: el user ajusto manualmente → NO sobrescribir en refresh siguientes.
    self.radioAjustadoManual = true
    if self.lblRadioVal then self.lblRadioVal:setTitle(tostring(v)) end
end

function HoldoorPanel:onSeleccionarModo(button)
    self.modoSeleccionado = button.holdoorModoIdx
    -- v0.7 #18: al cambiar de modo, resetear el ajuste manual (cada modo tiene su default).
    self.radioAjustadoManual = false
    self:_actualizarInfoModo(self.modoSeleccionado, true)  -- forzar = true
end

function HoldoorPanel:_actualizarInfoModo(idx, forzarRadio)
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

    self.lblModoNombre:setName(getText("UI_Holdoor_modo_" .. modo.id .. "_nombre"))
    self.lblModoNombre:setColor(modo.cr, modo.cg, modo.cb, 1)
    self.lblModoDesc:setName(getText("UI_Holdoor_modo_" .. modo.id .. "_desc"))

    -- v0.7 #18: Sincronizar radioSpawn con el default del modo SOLO si:
    --   a) forzarRadio=true (llamada explicita: cambio de modo o init), o
    --   b) el user nunca toco + / - manualmente (radioAjustadoManual != true).
    -- Antes esto sobrescribia SIEMPRE → al hacer un refresh del panel post-iniciar,
    -- borraba el ajuste manual y mostraba el default (mientras el server SI usaba 19).
    if self.lblRadioVal and modo.radioSpawn and (forzarRadio or not self.radioAjustadoManual) then
        self.radioSpawnVal = modo.radioSpawn
        self.lblRadioVal:setTitle(tostring(modo.radioSpawn))
    end

    local l1, l2 = splitLoreText(getText("UI_Holdoor_modo_" .. modo.id .. "_lore"))
    self.lblLore1:setName(l1)
    self.lblLore2:setName(l2)

    self.lblModoDetalle:setName(getText("UI_Holdoor_modo_" .. modo.id .. "_detalle"))

    -- Mostrar HP del Trono para este modo
    if self.lblModoHP then
        local hpModo = (HoldoorConfig.tronoHPPorModo or {})[modo.id] or 1500
        self.lblModoHP:setName(getText("UI_Holdoor_panel_vidatrono", tostring(hpModo)))
    end

    local record = HoldoorClient.obtenerRecord(modo.id)
    local maxOl  = modo.maxOleadas or 0
    if record > 0 then
        self.lblModoRecord:setName(getText("UI_Holdoor_panel_recordfmt", tostring(record), tostring(maxOl)))
        if record >= maxOl then
            self.lblModoRecord:setColor(1.0, 0.85, 0.20, 1)
        else
            self.lblModoRecord:setColor(0.30, 0.85, 0.45, 1)
        end
    else
        self.lblModoRecord:setName(getText("UI_Holdoor_panel_recordnone"))
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
                faseLabel = getText("UI_Holdoor_fase_preparacion", segsLeft)
            elseif fase == "activa" then
                faseLabel = getText("UI_Holdoor_fase_combate")
            elseif fase == "pausa" then
                faseLabel = getText("UI_Holdoor_fase_pausa")
            else
                faseLabel = getText("UI_Holdoor_fase_activo")
            end
            self.lblEstado:setName(getText("UI_Holdoor_panel_estadolbl") .. ": " .. faseLabel)
            self.lblEstado:setColor(COLOR_VERDE.r, COLOR_VERDE.g, COLOR_VERDE.b, 1)
        else
            self.lblEstado:setName(getText("UI_Holdoor_panel_estadolbl") .. ": " .. getText("UI_Holdoor_fase_inactivo"))
            self.lblEstado:setColor(0.7, 0.7, 0.7, 1)
        end
    end

    if self.lblOleada then
        local cfg    = est.config or {}
        local maxOl  = cfg.maxOleadas or 0
        local oleada = est.oleadaActual or 0
        if oleada > 0 then
            self.lblOleada:setName(getText("UI_Holdoor_panel_oleadalbl") .. ": " .. oleada .. "/" .. maxOl)
        else
            self.lblOleada:setName(getText("UI_Holdoor_panel_oleadalbl") .. ": - / " .. maxOl)
        end
    end

    if self.lblBase then
        if est.baseDefinida then
            self.lblBase:setName(getText("UI_Holdoor_panel_baselbl") .. ": " .. est.baseX .. ", " .. est.baseY)
            self.lblBase:setColor(0.4, 0.8, 1, 1)
        else
            self.lblBase:setName(getText("UI_Holdoor_panel_baselbl") .. ": " .. getText("UI_Holdoor_panel_basenodef"))
            self.lblBase:setColor(COLOR_ROJO.r, COLOR_ROJO.g, COLOR_ROJO.b, 1)
        end
    end

    if self.lblJugadores then
        local nj  = est.numJugadores or 1
        local mx  = est.playerMultiplier or 1.0
        if est.activo then
            self.lblJugadores:setName(getText("UI_Holdoor_panel_jugfmt", tostring(nj), tostring(mx)))
            self.lblJugadores:setColor(0.75, 0.95, 0.55, 1)
        else
            self.lblJugadores:setName(getText("UI_Holdoor_panel_juginit"))
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

function HoldoorPanel:onQuitarBase()
    if not HoldoorClient.estado.baseDefinida then
        HoldoorClient.chat(getText("UI_Holdoor_chat_nobase"), 1, 0.6, 0.2)
        return
    end
    -- v0.9.x: no permitir quitar base con oleadas en curso. Hay que detenerlas primero
    -- (STOP WAVES) para poder quitar la base / destruir el Trono.
    if HoldoorClient.estado.activo then
        HoldoorClient.chat(getText("UI_Holdoor_chat_quitaroleadaactiva"), 1, 0.6, 0.2)
        return
    end
    -- Confirmacion — destruye el Trono fisico, no es reversible
    local txt = getText("UI_Holdoor_modal_quitarbase")
    local modal = ISModalDialog:new(0, 0, 380, 220, txt, true, self, HoldoorPanel.onConfirmQuitarBase)
    modal:initialise()
    modal:addToUIManager()
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    modal:setX((sw - modal.width) / 2)
    modal:setY((sh - modal.height) / 2)
end

function HoldoorPanel:onConfirmQuitarBase(button)
    if button.internal == "YES" then
        HoldoorClient.quitarBase()
    end
end

function HoldoorPanel:onMarcarBase()
    HoldoorClient.setBase()
end

function HoldoorPanel:onIniciar()
    if not HoldoorClient.estado.baseDefinida then
        if self.lblBase then
            self.lblBase:setName(getText("UI_Holdoor_panel_primeromarca"))
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
    -- v0.7 #23 / gotcha #29 LOCKEADO: el overlay con rect fullscreen + setVisible(true)
    -- BLOQUEA el scroll del inventario y los tooltips de items. Hay que esconderlo
    -- explicitamente al cerrar el panel (botón Cerrar o ESC, no solo el F10 toggle).
    if HoldoorUI.overlay then HoldoorUI.overlay:setVisible(false) end
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

local HUD_W          = 265   -- +10 para que entren los simbolos de materiales
local HUD_H_HEAD     = 28
local HUD_H_BODY     = 354   -- v0.8 #22 +30 (boton Retorno al Trono)
local HUD_H_BODY_EXT = 474   -- v0.8 #22 +30 con radar

-- Paleta de colores por moneda/material (símbolos + colores temáticos)
local COL_BRONCE    = { r=0.72, g=0.45, b=0.20, a=1 }
local COL_PLATA     = { r=0.78, g=0.78, b=0.80, a=1 }
local COL_ORO       = { r=0.89, g=0.65, b=0.28, a=1 }
local COL_CUERO     = { r=0.55, g=0.35, b=0.18, a=1 }
local COL_HIERRO    = { r=0.65, g=0.65, b=0.65, a=1 }
local COL_ACERO     = { r=0.60, g=0.78, b=0.92, a=1 }
local COL_VALYRIO   = { r=0.70, g=0.40, b=0.85, a=1 }
local COL_OBSIDIANA = { r=0.45, g=0.20, b=0.50, a=1 }

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

-- v0.6.1: Sub-zona del HUD que SÍ captura mouse. El HUD principal es PASSTHROUGH total
-- (setWantMouseEvents=false), entonces los botones / header viven DENTRO de estas zonas
-- para que reciban clicks. Sin estas zonas, todo el HUD seria click-through y los botones
-- (TIENDA, Enviar monedas, toggle +/-) no funcionarian.
-- El refactor del 2026-06-15 separa el HUD en:
--   - HUD root (passthrough — no captura nada, no rompe inventario/hover detras)
--   - headerZone (sub-zona arriba — labels titulo + boton toggle)
--   - btnZone (sub-zona abajo — botones Enviar / TIENDA)
-- Los labels del body del HUD viven en el root porque solo se renderizan (no necesitan mouse).
HoldoorHUDInputZone = ISPanel:derive("HoldoorHUDInputZone")
function HoldoorHUDInputZone:new(x, y, w, h)
    local o = ISPanel.new(self, x, y, w, h)
    setmetatable(o, self); self.__index = self
    o.background  = false   -- transparente — deja ver el fondo del HUD padre
    o.borderColor = { r=0, g=0, b=0, a=0 }
    return o
end
-- Default setWantMouseEvents=true → captura clicks de los botones hijos.

-- v0.6.1: Sub-zona ESPECIAL con drag custom. Cuando el user arrastra el mouse sobre
-- esta zona, se mueve el PADRE (HoldoorHUD entero). Se usa para el headerZone para
-- que el HUD lateral siga siendo movible despues del refactor de sub-zonas.
-- Los hijos clickeables (ej. btnToggle) consumen sus propios clicks antes de llegar
-- aca, por lo que no se rompe el flujo de botones.
HoldoorHUDDragZone = HoldoorHUDInputZone:derive("HoldoorHUDDragZone")
function HoldoorHUDDragZone:new(x, y, w, h)
    local o = HoldoorHUDInputZone.new(self, x, y, w, h)
    setmetatable(o, self); self.__index = self
    o._dragging = false
    return o
end
function HoldoorHUDDragZone:onMouseDown(x, y)
    if not self.parent then return false end
    self._dragging = true
    self._dragOffX = getMouseX() - self.parent:getX()
    self._dragOffY = getMouseY() - self.parent:getY()
    return true
end
function HoldoorHUDDragZone:onMouseUp(x, y)
    self._dragging = false
    return true
end
function HoldoorHUDDragZone:onMouseUpOutside(x, y)
    self._dragging = false
    return true
end
function HoldoorHUDDragZone:onMouseMove(dx, dy)
    if self._dragging and self.parent then
        self.parent:setX(getMouseX() - self._dragOffX)
        self.parent:setY(getMouseY() - self._dragOffY)
    end
    return true
end
function HoldoorHUDDragZone:onMouseMoveOutside(dx, dy)
    if self._dragging and self.parent then
        self.parent:setX(getMouseX() - self._dragOffX)
        self.parent:setY(getMouseY() - self._dragOffY)
    end
    return true
end

function HoldoorHUD:new(x, y)
    local o = ISPanel.new(self, x, y, HUD_W, HUD_H_HEAD)
    setmetatable(o, self)
    self.__index = self
    o.backgroundColor = COLOR_HUD_BG
    o.borderColor     = COLOR_BORDE
    -- v0.6.1: moveWithMouse REMOVIDO. El HUD root no recibe eventos por ser passthrough.
    -- Para drag necesitariamos sub-zona dedicada — se hace en otro sprint si Nahuel lo quiere.
    o.expandido       = false
    return o
end

-- v0.6.1: HUD root PASSTHROUGH total. PZ no le envia ningun evento del mouse.
-- Los clicks de los botones llegan via las sub-zonas (headerZone, btnZone) que SI capturan.
-- Esto resuelve el bug critico donde el HUD bloqueaba scroll/hover/tooltips del inventario
-- vanilla detras (encontrado 2026-06-15, plan A con guards fallo, este es plan B definitivo).
function HoldoorHUD:isMouseOver()              return false end
function HoldoorHUD:onMouseDown(x, y)          return false end
function HoldoorHUD:onMouseUp(x, y)            return false end
function HoldoorHUD:onMouseMove(dx, dy)        return false end
function HoldoorHUD:onMouseMoveOutside(dx, dy) return false end
function HoldoorHUD:onMouseDownOutside(x, y)   return false end
function HoldoorHUD:onMouseUpOutside(x, y)     return false end
function HoldoorHUD:onRightMouseDown(x, y)     return false end
function HoldoorHUD:onRightMouseUp(x, y)       return false end
function HoldoorHUD:onMouseWheel(del)          return false end

function HoldoorHUD:initialise()
    ISPanel.initialise(self)
    -- CLAVE: passthrough total. Sin esto el rect del HUD bloquea inventario detras.
    pcall(function() self:setWantMouseEvents(false) end)
    self:_crearContenido()
end

function HoldoorHUD:_crearContenido()
    local pad = 8

    -- v0.6.1: headerZone captura clicks del header (btnToggle) Y permite DRAG del HUD.
    -- Usa HoldoorHUDDragZone (extiende InputZone) que mueve al padre al arrastrar.
    self.headerZone = HoldoorHUDDragZone:new(0, 0, HUD_W, HUD_H_HEAD)
    self.headerZone:initialise()
    self:addChild(self.headerZone)

    -- Header — adentro de la zona interactiva (NO directo en self)
    self.lblTit = ISLabel:new(pad, 7, 16, "HOLDOOR", COLOR_HUD_ORO.r, COLOR_HUD_ORO.g, COLOR_HUD_ORO.b, 1, UIFont.Small, true)
    self.headerZone:addChild(self.lblTit)

    self.lblHeadInfo = ISLabel:new(pad + 78, 7, 16, "", 0.90, 0.85, 0.55, 1, UIFont.Small, true)
    self.headerZone:addChild(self.lblHeadInfo)

    self.btnToggle = ISButton:new(HUD_W - 32, 3, 28, 22, "+", self, HoldoorHUD.onToggle)
    self.btnToggle.backgroundColor = { r=0.10, g=0.09, b=0.07, a=1 }
    self.btnToggle.borderColor     = { r=0.50, g=0.35, b=0.10, a=0.7 }
    self.headerZone:addChild(self.btnToggle)

    -- Body
    local y = HUD_H_HEAD + 8

    self.lblEstHUD = ISLabel:new(pad, y, 16, "Inactivo", 0.55, 0.55, 0.55, 1, UIFont.Small, true)
    self:addChild(self.lblEstHUD); y = y + 15

    self.lblOlHUD = ISLabel:new(pad, y, 16, "Oleada: --", COLOR_HUD_ORO.r, COLOR_HUD_ORO.g, COLOR_HUD_ORO.b, 1, UIFont.Small, true)
    self:addChild(self.lblOlHUD); y = y + 15

    self.lblTimHUD = ISLabel:new(pad, y, 16, "Proxima: --", 0.55, 0.55, 0.55, 1, UIFont.Small, true)
    self:addChild(self.lblTimHUD); y = y + 15

    self.lblFzaHUD = ISLabel:new(pad, y, 16, "Siguiente: --", 0.85, 0.70, 0.40, 1, UIFont.Small, true)
    self:addChild(self.lblFzaHUD); y = y + 15

    self.lblAmenHUD = ISLabel:new(pad, y, 16, "Amenaza: --", 0.55, 0.55, 0.55, 1, UIFont.Small, true)
    self:addChild(self.lblAmenHUD); y = y + 15

    -- Brujula a la base (direccion cardinal + distancia categorica)
    self.lblBaseDir = ISLabel:new(pad, y, 16, "Base: no marcada", 0.55, 0.55, 0.50, 1, UIFont.Small, true)
    self:addChild(self.lblBaseDir); y = y + 15

    -- HP del Trono de Hierro
    self.lblTronoHP = ISLabel:new(pad, y, 16, "Trono: --", 0.55, 0.55, 0.50, 1, UIFont.Small, true)
    self:addChild(self.lblTronoHP); y = y + 15

    self.lblNotifHUD = ISLabel:new(pad, y, 16, "", 1, 0.85, 0.3, 1, UIFont.Small, true)
    self:addChild(self.lblNotifHUD)
    self.notifExpireSec = 0
    y = y + 16

    -- v0.8.8 (revisado): stats kills formato compacto 1 linea.
    -- SP: "Bajas (oleada): 5"
    -- MP: "Bajas (oleada): 5 / 8"  (yo / equipo)
    self.lblKillsHUD = ISLabel:new(pad, y, 16, "Bajas (oleada): --", 0.70, 0.90, 0.55, 1, UIFont.Small, true)
    self:addChild(self.lblKillsHUD)
    y = y + 14

    self.lblKillsPartidaHUD = ISLabel:new(pad, y, 16, "Total partida: --", 0.55, 0.70, 0.45, 1, UIFont.Small, true)
    self:addChild(self.lblKillsPartidaHUD)
    y = y + 16

    -- Saldo de monedas y materiales — render custom en :render() con simbolos+colores
    self.yMonedasHUD    = y
    y = y + 14
    self.yMaterialesHUD = y
    y = y + 14
    y = y + 2

    -- v0.6.1: btnZone captura clicks de Enviar+TIENDA. Coords de los botones son
    -- RELATIVAS a btnZone (no a self). Sin esta zona los botones no recibirian clicks
    -- porque el HUD root es passthrough.
    local btnZoneH = 30 + 26 + 4   -- alto Enviar + alto TIENDA + padding
    self.btnZone = HoldoorHUDInputZone:new(0, y, HUD_W, btnZoneH)
    self.btnZone:initialise()
    self:addChild(self.btnZone)

    -- Boton enviar monedas a otro jugador — coords RELATIVAS a btnZone (y=0)
    self.btnEnviar = ISButton:new(pad, 0, HUD_W - pad * 2, 24, "Enviar monedas a otro jugador", self, HoldoorHUD.onEnviar)
    self.btnEnviar.backgroundColor = { r=0.20, g=0.30, b=0.18, a=1 }
    self.btnEnviar.borderColor     = { r=0.40, g=0.65, b=0.25, a=1 }
    self.btnZone:addChild(self.btnEnviar)

    -- Boton tienda — coords RELATIVAS a btnZone (y=30)
    self.btnTienda = ISButton:new(pad, 30, HUD_W - pad * 2, 26, "TIENDA", self, HoldoorHUD.onTienda)
    self.btnTienda.backgroundColor = { r=0.25, g=0.12, b=0.35, a=1 }
    self.btnTienda.borderColor     = { r=0.70, g=0.30, b=0.95, a=1 }
    self.btnZone:addChild(self.btnTienda)

    y = y + btnZoneH + 4

    -- v0.7 #35: ZONA SEPARADA para el boton "INVOCAR BESO DEL DIOS" (botonera Fase A).
    -- Es una input zone INDEPENDIENTE: se muestra/oculta entera. Cuando setVisible(false)
    -- NO captura clicks (cf. gotcha #29 del overlay del Trono). Asi evitamos que un
    -- rectangulo invisible bloquee el inventario o cualquier otra UI cuando el jugador
    -- no tiene Beso en bolsa.
    self.besoZone = HoldoorHUDInputZone:new(0, y, HUD_W, 26)
    self.besoZone:initialise()
    self:addChild(self.besoZone)
    self.btnBeso = ISButton:new(pad, 0, HUD_W - pad * 2, 26, "INVOCAR BESO DEL DIOS", self, HoldoorHUD.onBesoDelDios)
    self.btnBeso.backgroundColor = { r=0.55, g=0.45, b=0.10, a=1 }
    self.btnBeso.borderColor     = { r=0.95, g=0.85, b=0.30, a=1 }
    self.besoZone:addChild(self.btnBeso)
    self.besoZone:setVisible(false)  -- oculto por default; actualizarHUD lo muestra si hay bolsa

    y = y + 26 + 4

    -- v0.8 #5: ZONA SEPARADA para el boton "RAISE UP JOHN SNOW" (toggle activo/desactivado).
    -- Mismo patron anti-gotcha #29 que besoZone — independiente, setVisible(false) NO captura clicks.
    -- A diferencia del Beso (click=activa), este boton TOGGLE activado/desactivado.
    -- El revive es automatico cuando HP<15 y esta activado. NO consume al click.
    self.raiseZone = HoldoorHUDInputZone:new(0, y, HUD_W, 26)
    self.raiseZone:initialise()
    self:addChild(self.raiseZone)
    self.btnRaiseUp = ISButton:new(pad, 0, HUD_W - pad * 2, 26, "RAISE: ACTIVO", self, HoldoorHUD.onRaiseUpToggle)
    self.btnRaiseUp.backgroundColor = { r=0.10, g=0.45, b=0.15, a=1 }   -- verde default (activo)
    self.btnRaiseUp.borderColor     = { r=0.30, g=0.95, b=0.40, a=1 }
    self.raiseZone:addChild(self.btnRaiseUp)
    self.raiseZone:setVisible(false)  -- oculto por default; actualizarHUD lo muestra si hay bolsa

    y = y + 26 + 4

    -- v0.8 #22: ZONA SEPARADA para "Punto de Retorno" (checkpoint personal + teleport).
    -- Mismo patron anti-gotcha #29 que besoZone/raiseZone — independiente.
    -- Dos botones lado a lado: izquierda "Marcar/Reemplazar Punto", derecha "Teletransportar".
    self.teleportZone = HoldoorHUDInputZone:new(0, y, HUD_W, 26)
    self.teleportZone:initialise()
    self:addChild(self.teleportZone)
    -- Cada boton ocupa la mitad menos un gap interno
    local btnGap = 4
    local btnW   = math.floor((HUD_W - pad * 2 - btnGap) / 2)
    -- Boton IZQUIERDO: Marcar / Reemplazar punto
    self.btnMarcarPunto = ISButton:new(pad, 0, btnW, 26, "Marcar Punto", self, HoldoorHUD.onMarcarPuntoClick)
    self.btnMarcarPunto.backgroundColor = { r=0.30, g=0.30, b=0.50, a=1 }
    self.btnMarcarPunto.borderColor     = { r=0.55, g=0.55, b=0.85, a=1 }
    self.teleportZone:addChild(self.btnMarcarPunto)
    -- Boton DERECHO: Teletransportar
    self.btnTeleportBase = ISButton:new(pad + btnW + btnGap, 0, btnW, 26, "Teletransportar", self, HoldoorHUD.onTeleportBaseClick)
    self.btnTeleportBase.backgroundColor = { r=0.10, g=0.30, b=0.55, a=1 }
    self.btnTeleportBase.borderColor     = { r=0.30, g=0.60, b=0.95, a=1 }
    self.teleportZone:addChild(self.btnTeleportBase)
    self.teleportZone:setVisible(false)

    y = y + 26 + 4

    -- Radar — visible solo cuando quedan <= 5 zombies en oleada activa
    self.lblRadarTit = ISLabel:new(pad, y, 16, "RADAR  -- zombis restantes", 1.0, 0.30, 0.18, 1, UIFont.Small, true)
    self:addChild(self.lblRadarTit)
    y = y + 18

    self.lblRadarCount = ISLabel:new(pad, y, 16, "", 0.8, 0.6, 0.6, 1, UIFont.Small, true)
    self:addChild(self.lblRadarCount)
    y = y + 20

    -- Y inicial del cuadrado del radar (calculado dinamicamente, no hardcoded)
    self.yRadarBox = y

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

-- v0.7 #35: click en "INVOCAR BESO DEL DIOS" en el HUD lateral. Solo dispara el efecto si
-- el jugador realmente tiene el item en bolsa (chequeo defensivo — el boton no deberia
-- estar visible sin ello, pero por las dudas).
function HoldoorHUD:onBesoDelDios()
    local me = getSpecificPlayer(0)
    if not me then return end
    local md = me:getModData()
    -- v0.8 #9: si esta grisado (no comprado), avisar donde comprarlo
    if not (md and md.Holdoor_BesoDios_Bolsa) then
        HoldoorClient.chat("[HOLDOOR] No tenes Beso del Dios. Compralo en TIENDA → Milagros del Maestre.", 0.85, 0.65, 0.30)
        return
    end
    if HoldoorClient and HoldoorClient._activarBesoDelDios then
        HoldoorClient._activarBesoDelDios()
    end
end

-- v0.8 #5: click en "RAISE: ACTIVO/OFF" — toggle del seguro Raise up John Snow.
-- NO consume el item. Solo cambia el flag md.Holdoor_RaiseUp_Activo.
-- El revive automatico se dispara cuando HP<15 Y este flag esta en true.
function HoldoorHUD:onRaiseUpToggle()
    local me = getSpecificPlayer(0)
    if not me then return end
    local md = me:getModData()
    -- v0.8.17: si hay LEGADO disponible (murio con Raise activo y revivio) → recuperar (prioridad).
    -- Dispara el flujo completo on-demand: animacion + godmode + restore + teleport + matar zombies.
    if md and md.Holdoor_RaiseUp_LegadoDisponible then
        HoldoorClient.chat("[HOLDOOR] Levantate, Jon Snow. El R'hllor te devuelve a la vida...", 0.95, 0.75, 0.20)
        -- v0.8.19: ejecutar EN CLIENT-CTX (donde _onPlayerMuerto guardó el snapshot al morir).
        -- Mandarlo a server-ctx via sendClientCommand NO veria el snapshot (contextos separados en
        -- CoopHost — medido 2026-06-22). El host ejecuta directo en su client-ctx. Remoto delega
        -- (TODO friend: su snapshot vive en su propio client-ctx).
        local esHost = false
        pcall(function() esHost = (not isClient()) or isCoopHost() end)
        if HoldoorServer and HoldoorServer._raiseDbg then
            local u = (getSpecificPlayer(0) and getSpecificPlayer(0):getUsername()) or "?"
            HoldoorServer._raiseDbg("BOTON-CLICK", u, "esHost="..tostring(esHost).." -> "..(esHost and "ejecuta-directo-client-ctx" or "sendClientCommand-a-server-ctx"))
        end
        if esHost and HoldoorServer and HoldoorServer._ejecutarRecuperarLegado then
            local p = getSpecificPlayer(0)
            if p then pcall(function() HoldoorServer._ejecutarRecuperarLegado(p) end) end
        else
            pcall(function() sendClientCommand(HoldoorConfig.MODULE, "recuperarLegado", {}) end)
        end
        return
    end
    -- v0.8 #9: si esta grisado (no comprado), avisar donde comprarlo
    if not (md and md.Holdoor_RaiseUp_Bolsa) then
        HoldoorClient.chat("[HOLDOOR] No tenes Raise up John Snow. Compralo en TIENDA → Milagros del Maestre.", 0.85, 0.65, 0.30)
        return
    end
    -- Enviar toggle al server (server cambia el flag y devuelve confirmacion)
    pcall(function() sendClientCommand(HoldoorConfig.MODULE, "toggleRaiseUp", {}) end)
end

-- v0.8 #22: click en "Marcar Punto / Reemplazar Punto" — guarda coords actuales del player.
-- No requiere tener el item en bolsa para marcar (es accion gratis).
function HoldoorHUD:onMarcarPuntoClick()
    local me = getSpecificPlayer(0)
    if not me then return end
    local x, y, z = 0, 0, 0
    pcall(function() x = me:getX() end)
    pcall(function() y = me:getY() end)
    pcall(function() z = me:getZ() end)
    pcall(function()
        sendClientCommand(HoldoorConfig.MODULE, "marcarPuntoRetorno", {
            x = math.floor(x), y = math.floor(y), z = math.floor(z),
        })
    end)
end

-- v0.8 #22: click en "Teletransportar" — inicia countdown 5s + teleport al Punto de Retorno.
-- Requiere: item en bolsa + punto previamente marcado.
function HoldoorHUD:onTeleportBaseClick()
    local me = getSpecificPlayer(0)
    if not me then return end
    local md = me:getModData()
    if not (md and md.Holdoor_PuntoRetorno_Bolsa) then
        HoldoorClient.chat("[HOLDOOR] No tenes Punto de Retorno. Compralo en TIENDA → Milagros del Maestre.", 0.85, 0.65, 0.30)
        return
    end
    if not (md.Holdoor_PuntoRetorno_X and md.Holdoor_PuntoRetorno_Y) then
        HoldoorClient.chat("[HOLDOOR] No marcaste ningun punto todavia. Usa 'Marcar Punto' primero.", 1.00, 0.55, 0.20)
        return
    end
    pcall(function() sendClientCommand(HoldoorConfig.MODULE, "activarPuntoRetorno", {}) end)
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
        -- v0.6.1: en lugar de btnEnviar/btnTienda directos, ocultamos su zona
        -- (los botones viven dentro de btnZone tras el refactor). Monedas/materiales
        -- siguen dibujandose en :render() del HUD root, no son ISLabel.
        self.btnZone,
    }
    for _, c in ipairs(hijos) do if c then c:setVisible(v) end end
    -- v0.8.8: formato compacto, sin labels extra. El texto "yo / equipo" se arma en
    -- actualizarTodo y se renderiza en lblKillsHUD y lblKillsPartidaHUD.
    -- v0.7 #35: besoZone es independiente: si HUD colapsa, ocultar SIEMPRE (no captura
    -- clicks asi). Si HUD expande, actualizarHUD decide si mostrarla segun bolsa.
    if self.besoZone then
        if not v then self.besoZone:setVisible(false) end
        -- al expandir lo deja en false hasta que actualizarHUD lo prenda si hay bolsa
    end
    -- v0.8 #22: teleportZone — anti-gotcha #29.
    if self.teleportZone then
        if not v then self.teleportZone:setVisible(false) end
    end
    -- v0.8 #5: raiseZone igual que besoZone — anti-gotcha #29.
    if self.raiseZone then
        if not v then self.raiseZone:setVisible(false) end
    end
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

    -- v0.8 #9: BESO DEL DIOS — siempre visible (con HUD expandido). Color segun estado:
    --   - Sin comprar  → GRISADO (texto "BESO DEL DIOS (no comprado)")
    --   - En bolsa     → DORADO ACTIVO (texto "INVOCAR BESO DEL DIOS")
    --   - Ya usado     → no se muestra (consumido por vida)
    if self.besoZone and self.btnBeso then
        local me = getSpecificPlayer(0)
        local enBolsa, usado = false, false
        if me then
            local md = me:getModData()
            if md then
                enBolsa = md.Holdoor_BesoDios_Bolsa and true or false
                usado   = md.Holdoor_BesoDios       and true or false
            end
        end
        -- Siempre visible si HUD expandido (incluso sin comprar), excepto si ya lo usaste
        self.besoZone:setVisible(self.expandido and not usado)
        if enBolsa then
            self.btnBeso:setTitle("INVOCAR BESO DEL DIOS")
            self.btnBeso.backgroundColor = { r=0.55, g=0.45, b=0.10, a=1 }  -- dorado activo
            self.btnBeso.borderColor     = { r=0.95, g=0.85, b=0.30, a=1 }
            self.btnBeso.textColor       = { r=1, g=1, b=1, a=1 }
        else
            -- v0.8 #10: mismo estilo que "Sin saldo" de la tienda
            self.btnBeso:setTitle("Beso del Dios — no comprado")
            self.btnBeso.backgroundColor = { r=0.18, g=0.18, b=0.20, a=1 }
            self.btnBeso.borderColor     = { r=0.30, g=0.30, b=0.30, a=1 }
            self.btnBeso.textColor       = { r=0.55, g=0.55, b=0.50, a=1 }
        end
    end

    -- v0.8 #9: RAISE UP JOHN SNOW — siempre visible (con HUD expandido). Color segun estado:
    --   - Sin comprar  → GRISADO (texto "RAISE UP (no comprado)")
    --   - En bolsa + activo → VERDE (texto "RAISE: ACTIVO")
    --   - En bolsa + desactivado → ROJO (texto "RAISE: OFF")
    if self.raiseZone and self.btnRaiseUp then
        local me = getSpecificPlayer(0)
        local enBolsa, activo = false, false
        local snapshotTs = 0
        local legadoDisp = false   -- v0.8.17: murio con Raise activo y revivio → boton para recuperar
        if me then
            local md = me:getModData()
            if md then
                legadoDisp = md.Holdoor_RaiseUp_LegadoDisponible and true or false
                if md.Holdoor_RaiseUp_Bolsa then
                    enBolsa = true
                    activo = md.Holdoor_RaiseUp_Activo and true or false
                    snapshotTs = md.Holdoor_RaiseSnapshotTs or 0
                end
            end
        end

        -- v0.8 #21: tag de tiempo "(hace Nm)" o "(hace Nm ⟲)" si pasaron 5+ min (renovable)
        -- Se mete dentro del titulo del boton para no romper layout (cero pixels extra).
        local tagTiempo = ""
        if snapshotTs > 0 then
            local minutos = math.floor((os.time() - snapshotTs) / 60)
            if minutos < 1 then
                tagTiempo = " (recien)"
            elseif minutos >= 5 then
                tagTiempo = " (" .. minutos .. "m ⟲)"  -- listo para renovar
            else
                tagTiempo = " (" .. minutos .. "m)"
            end
        end

        self.raiseZone:setVisible(self.expandido)  -- siempre visible cuando HUD expandido
        if legadoDisp then
            -- v0.8.17: PRIORIDAD MAXIMA. Murio con Raise activo y revivio → ofrecer recuperar legado.
            self.btnRaiseUp:setTitle("RAISE UP — RECUPERA TU LEGADO")
            self.btnRaiseUp.backgroundColor = { r=0.55, g=0.42, b=0.10, a=1 }  -- dorado
            self.btnRaiseUp.borderColor     = { r=1.0, g=0.82, b=0.30, a=1 }
            self.btnRaiseUp.textColor       = { r=1, g=0.95, b=0.70, a=1 }
        elseif not enBolsa then
            -- v0.8 #10: mismo estilo que "Sin saldo" de la tienda
            self.btnRaiseUp:setTitle("Raise up Snow — no comprado")
            self.btnRaiseUp.backgroundColor = { r=0.18, g=0.18, b=0.20, a=1 }
            self.btnRaiseUp.borderColor     = { r=0.30, g=0.30, b=0.30, a=1 }
            self.btnRaiseUp.textColor       = { r=0.55, g=0.55, b=0.50, a=1 }
        elseif activo then
            self.btnRaiseUp:setTitle("RAISE: ACTIVO" .. tagTiempo)
            self.btnRaiseUp.backgroundColor = { r=0.10, g=0.45, b=0.15, a=1 }  -- verde
            self.btnRaiseUp.borderColor     = { r=0.30, g=0.95, b=0.40, a=1 }
            self.btnRaiseUp.textColor       = { r=1, g=1, b=1, a=1 }
        else
            self.btnRaiseUp:setTitle("RAISE: OFF" .. tagTiempo)
            self.btnRaiseUp.backgroundColor = { r=0.45, g=0.15, b=0.10, a=1 }  -- rojo
            self.btnRaiseUp.borderColor     = { r=0.95, g=0.40, b=0.30, a=1 }
            self.btnRaiseUp.textColor       = { r=1, g=1, b=1, a=1 }
        end
    end

    -- v0.8 #22: estados de los 2 botones del Punto de Retorno
    -- Boton MARCAR:
    --   - Sin punto guardado → "Marcar Punto" (violeta claro)
    --   - Con punto guardado → "Reemplazar Punto" (violeta + indicacion de reemplazo)
    -- Boton TELETRANSPORTAR:
    --   - Sin item comprado → "Teletransportar — no comprado" (gris)
    --   - Comprado + sin punto → "Marca un Punto primero" (amarillo warning)
    --   - Comprado + con punto → "Teletransportar" (azul activo)
    if self.teleportZone and self.btnMarcarPunto and self.btnTeleportBase then
        local me = getSpecificPlayer(0)
        local enBolsaTp = false
        local hayPunto  = false
        if me then
            local md = me:getModData()
            if md then
                enBolsaTp = md.Holdoor_PuntoRetorno_Bolsa and true or false
                hayPunto  = (md.Holdoor_PuntoRetorno_X and md.Holdoor_PuntoRetorno_Y) and true or false
            end
        end
        self.teleportZone:setVisible(self.expandido)

        -- BOTON IZQUIERDO: Marcar / Cambiar
        if not hayPunto then
            self.btnMarcarPunto:setTitle("Marcar Punto")
            self.btnMarcarPunto.backgroundColor = { r=0.30, g=0.30, b=0.50, a=1 }
            self.btnMarcarPunto.borderColor     = { r=0.55, g=0.55, b=0.85, a=1 }
            self.btnMarcarPunto.textColor       = { r=1, g=1, b=1, a=1 }
        else
            self.btnMarcarPunto:setTitle("Cambiar Punto")
            self.btnMarcarPunto.backgroundColor = { r=0.40, g=0.30, b=0.55, a=1 }
            self.btnMarcarPunto.borderColor     = { r=0.70, g=0.55, b=0.95, a=1 }
            self.btnMarcarPunto.textColor       = { r=1, g=1, b=1, a=1 }
        end

        -- BOTON DERECHO: Teleport (texto corto para entrar en la mitad del HUD)
        if not enBolsaTp then
            self.btnTeleportBase:setTitle("Teleport — no comp.")
            self.btnTeleportBase.backgroundColor = { r=0.18, g=0.18, b=0.20, a=1 }
            self.btnTeleportBase.borderColor     = { r=0.30, g=0.30, b=0.30, a=1 }
            self.btnTeleportBase.textColor       = { r=0.55, g=0.55, b=0.50, a=1 }
        elseif not hayPunto then
            self.btnTeleportBase:setTitle("Marca un Punto")
            self.btnTeleportBase.backgroundColor = { r=0.55, g=0.45, b=0.10, a=1 }
            self.btnTeleportBase.borderColor     = { r=0.95, g=0.85, b=0.30, a=1 }
            self.btnTeleportBase.textColor       = { r=1, g=1, b=1, a=1 }
        else
            self.btnTeleportBase:setTitle("Teleport")
            self.btnTeleportBase.backgroundColor = { r=0.10, g=0.30, b=0.55, a=1 }
            self.btnTeleportBase.borderColor     = { r=0.30, g=0.60, b=0.95, a=1 }
            self.btnTeleportBase.textColor       = { r=1, g=1, b=1, a=1 }
        end
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
        -- v0.6 modelo C: header muestra "OL.N MODO 23/45" (kills vs target)
        local kills  = est.oleadaKills or 0
        local target = est.oleadaTargetKills or 0
        self.lblHeadInfo:setName("OL." .. oleada .. " " .. modoCorto .. " " .. kills .. "/" .. target)
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
            if m.id == est.config.modoId then modoLbl = getText("UI_Holdoor_modo_" .. m.id .. "_nombre"); break end
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
        -- v0.6 modelo C: Timer + Kills (en vez de Zombis X/Y).
        local inicio = est.oleadaInicioSec or os.time()
        local total  = est.oleadaDuracionSec or 180
        local restante = math.max(0, total - (os.time() - inicio))
        local mm = math.floor(restante / 60)
        local ss = restante % 60
        self.lblTimHUD:setName(string.format("Tiempo: %d:%02d", mm, ss))
        if restante <= 15 then
            self.lblTimHUD:setColor(COLOR_HUD_RED.r, COLOR_HUD_RED.g, COLOR_HUD_RED.b, 1)
        elseif restante <= 45 then
            self.lblTimHUD:setColor(COLOR_HUD_WARN.r, COLOR_HUD_WARN.g, COLOR_HUD_WARN.b, 1)
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

    -- v0.6 modelo C: en fase activa mostramos KILLS X/Y. En otras fases, target de la oleada siguiente.
    if fase == "activa" then
        local kills  = est.oleadaKills or 0
        local target = est.oleadaTargetKills or 0
        self.lblFzaHUD:setName(string.format("Kills: %d / %d", kills, target))
        if target > 0 and kills >= target then
            self.lblFzaHUD:setColor(COLOR_HUD_OK.r, COLOR_HUD_OK.g, COLOR_HUD_OK.b, 1)   -- target alcanzado = cierre limpio
        else
            self.lblFzaHUD:setColor(0.85, 0.70, 0.40, 1)
        end
    elseif activo then
        -- v0.6: target real de la oleada SIGUIENTE (lee oleadasV6 + mult del modo)
        local modoId = (est.config and est.config.modoId) or "normal"
        local modoCfg = (HoldoorConfig.modosV6 or {})[modoId] or HoldoorConfig.modosV6.normal or {}
        local prox   = oleada + 1
        local idx    = math.min(prox, #(HoldoorConfig.oleadasV6 or {}))
        local oleadaCfg = HoldoorConfig.oleadasV6 and HoldoorConfig.oleadasV6[idx]
        if oleadaCfg then
            local targetProx = math.floor((oleadaCfg.targetKills or 50) * (modoCfg.multKills or 1.0))
            self.lblFzaHUD:setName("Siguiente: ~" .. targetProx .. " kills")
        else
            self.lblFzaHUD:setName("Siguiente: --")
        end
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

    -- v0.6 modelo C: el radar queda DESHABILITADO permanentemente. En modelo C
    -- nunca quedan "pocos zombies al final" porque el spawn es continuo hasta el timer.
    -- El código del radar sigue presente comentado (preservación intencional) por si
    -- en futuro se reactiva (ej. para boss fights o eventos especiales).
    local zombiesLeft = est.zombiesRestantes or 0
    local mostrarRadar = false  -- v0.6: false hardcoded (era: fase==activa and zombiesLeft<=5)
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

    -- v0.8.8: stats kills formato compacto "yo / equipo" en MP, "yo" en SP.
    local miOleada   = est.misKills        or 0
    local miPartida  = est.misKillsPartida or 0
    local eqOleada   = est.killsOleada     or 0
    local eqPartida  = est.killsPartida    or 0
    local esMP = false
    pcall(function() esMP = isClient() == true end)

    -- Oleada
    if self.lblKillsHUD then
        if activo then
            local txt = esMP
                and ("Bajas (oleada): " .. miOleada .. " / " .. eqOleada)
                or  ("Bajas (oleada): " .. miOleada)
            self.lblKillsHUD:setName(txt)
            self.lblKillsHUD:setColor(0.70, 0.95, 0.55, 1)
        else
            self.lblKillsHUD:setName("Bajas (oleada): --")
            self.lblKillsHUD:setColor(0.50, 0.55, 0.40, 1)
        end
    end

    -- Partida
    if self.lblKillsPartidaHUD then
        if miPartida > 0 or eqPartida > 0 then
            local txt = esMP
                and ("Total partida: " .. miPartida .. " / " .. eqPartida)
                or  ("Total partida: " .. miPartida)
            self.lblKillsPartidaHUD:setName(txt)
            self.lblKillsPartidaHUD:setColor(0.55, 0.75, 0.45, 1)
        else
            self.lblKillsPartidaHUD:setName("Total partida: --")
            self.lblKillsPartidaHUD:setColor(0.45, 0.45, 0.38, 1)
        end
    end

    -- Las monedas y materiales se dibujan en el render principal con simbolos+colores
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

        -- Linea de MONEDAS con prefijos ASCII + colores: B / P / O
        -- Nota: PZ B42 (kahlua) no procesa escapes \xHH en strings, asi que usamos letras planas.
        if self.yMonedasHUD and HoldoorClient and HoldoorClient.getSaldo then
            local b, s, g = HoldoorClient.getSaldo()
            local x = 8
            local y = self.yMonedasHUD
            self:drawText("Bronce: " .. b, x,       y, COL_BRONCE.r, COL_BRONCE.g, COL_BRONCE.b, 1, UIFont.Small)
            self:drawText("Plata: "  .. s, x + 86,  y, COL_PLATA.r,  COL_PLATA.g,  COL_PLATA.b,  1, UIFont.Small)
            self:drawText("Oro: "    .. g, x + 158, y, COL_ORO.r,    COL_ORO.g,    COL_ORO.b,    1, UIFont.Small)
        end

        -- Linea de MATERIALES: Cu / Hi / Ac / Va / Ob (abreviaturas de 2 letras)
        if self.yMaterialesHUD and HoldoorClient and HoldoorClient.getMateriales then
            local m = HoldoorClient.getMateriales()
            local x = 8
            local y = self.yMaterialesHUD
            self:drawText("Cu " .. (m.cuero     or 0), x,       y, COL_CUERO.r,     COL_CUERO.g,     COL_CUERO.b,     1, UIFont.Small)
            self:drawText("Hi " .. (m.hierro    or 0), x + 48,  y, COL_HIERRO.r,    COL_HIERRO.g,    COL_HIERRO.b,    1, UIFont.Small)
            self:drawText("Ac " .. (m.acero     or 0), x + 96,  y, COL_ACERO.r,     COL_ACERO.g,     COL_ACERO.b,     1, UIFont.Small)
            self:drawText("Va " .. (m.valyrio   or 0), x + 144, y, COL_VALYRIO.r,   COL_VALYRIO.g,   COL_VALYRIO.b,   1, UIFont.Small)
            self:drawText("Ob " .. (m.obsidiana or 0), x + 192, y, COL_OBSIDIANA.r, COL_OBSIDIANA.g, COL_OBSIDIANA.b, 1, UIFont.Small)
        end
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
        -- Y calculado dinamicamente segun lo que creo _crearContenido (debajo de los
        -- labels "RADAR" / "Buscando: X zombies"). Antes era hardcoded a +228 y se desfasaba.
        local ry      = self.yRadarBox or (HUD_H_HEAD + 280)

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
    HoldoorToast.crear()
    HoldoorRaiseUpFade.crear()  -- v0.8 #6
end

Events.OnGameStart.Add(HoldoorHUD.crear)

-- v0.6.1: las funciones diagnosticas de toggle UI (F6/F7/F8/F9/F11/F12) fueron removidas
-- antes del release. Se usaron para cazar el bug de mouse passthrough (gotcha #29).
-- Si en el futuro se necesitan, restaurar desde git history del sprint v0.6.1.

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
    pcall(function() self:setWantMouseEvents(false) end)
end

function HoldoorAnnounce:isMouseOver()              return false end
function HoldoorAnnounce:onMouseDown(x, y)          return false end
function HoldoorAnnounce:onMouseUp(x, y)            return false end
function HoldoorAnnounce:onMouseMove(dx, dy)        return false end
function HoldoorAnnounce:onMouseMoveOutside(dx, dy) return false end
function HoldoorAnnounce:onMouseDownOutside(x, y)   return false end
function HoldoorAnnounce:onMouseUpOutside(x, y)     return false end
function HoldoorAnnounce:onRightMouseDown(x, y)     return false end
function HoldoorAnnounce:onRightMouseUp(x, y)       return false end
function HoldoorAnnounce:onMouseWheel(del)          return false end

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

-- ════════════════════════════════════════════════════════════════════
-- HoldoorToast: notificacion compacta arriba de la pantalla
-- Se renderiza por encima de la tienda y demas paneles. Una sola linea.
-- Uso: HoldoorToast.mostrar("Compraste: X", 0.3, 1, 0.5)
-- ════════════════════════════════════════════════════════════════════

HoldoorToast = ISPanel:derive("HoldoorToast")
HoldoorToast.instance = nil

function HoldoorToast:new()
    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    local o  = ISPanel.new(self, 0, 0, sw, sh)
    setmetatable(o, self)
    self.__index      = self
    o.backgroundColor = {r=0, g=0, b=0, a=0}
    o.borderColor     = {r=0, g=0, b=0, a=0}
    o.moveWithMouse   = false
    o.toastTexto      = ""
    o.toastR          = 1
    o.toastG          = 0.9
    o.toastB          = 0.4
    o.toastTick       = 99999
    o.toastMaxTicks   = 180   -- ~3 segundos a 60fps
    return o
end

function HoldoorToast:initialise()
    ISPanel.initialise(self)
    pcall(function() self:setWantMouseEvents(false) end)
end

function HoldoorToast:isMouseOver()              return false end
function HoldoorToast:onMouseDown(x, y)          return false end
function HoldoorToast:onMouseUp(x, y)            return false end
function HoldoorToast:onMouseMove(dx, dy)        return false end
function HoldoorToast:onMouseMoveOutside(dx, dy) return false end
function HoldoorToast:onMouseDownOutside(x, y)   return false end
function HoldoorToast:onMouseUpOutside(x, y)     return false end
function HoldoorToast:onRightMouseDown(x, y)     return false end
function HoldoorToast:onRightMouseUp(x, y)       return false end
function HoldoorToast:onMouseWheel(del)          return false end

function HoldoorToast.mostrar(texto, r, g, b)
    local inst = HoldoorToast.instance
    if not inst then return end
    inst.toastTexto    = tostring(texto or "")
    inst.toastR        = r or 1
    inst.toastG        = g or 0.9
    inst.toastB        = b or 0.4
    inst.toastTick     = 0
    inst:setVisible(true)
end

function HoldoorToast.crear()
    if HoldoorToast.instance then return end
    local inst = HoldoorToast:new()
    inst:initialise()
    inst:addToUIManager()
    inst:setVisible(false)
    HoldoorToast.instance = inst
end

function HoldoorToast:render()
    ISPanel.render(self)

    local maxTicks = self.toastMaxTicks or 180
    self.toastTick = (self.toastTick or maxTicks) + 1

    if self.toastTick >= maxTicks or not self.toastTexto or self.toastTexto == "" then
        self:setVisible(false)
        return
    end

    -- Fade in (10 ticks) / fade out (25 ticks)
    local alpha
    local fadeIn  = 10
    local fadeOut = 25
    if self.toastTick < fadeIn then
        alpha = self.toastTick / fadeIn
    elseif self.toastTick > maxTicks - fadeOut then
        alpha = (maxTicks - self.toastTick) / fadeOut
    else
        alpha = 1.0
    end
    alpha = math.max(0, math.min(1, alpha))

    local sw  = self.width
    local tm  = getTextManager()
    local txt = self.toastTexto
    local txtW = tm:MeasureStringX(UIFont.Medium, txt)
    local txtH = tm:MeasureStringY(UIFont.Medium, txt)

    local boxW = txtW + 60
    local boxH = txtH + 24
    local boxX = (sw - boxW) / 2
    local boxY = 90   -- 90px desde el top de la pantalla

    -- Fondo oscuro con borde de color
    self:drawRect(boxX, boxY, boxW, boxH, 0.78 * alpha, 0, 0, 0)
    self:drawRect(boxX, boxY, boxW, 2, alpha, self.toastR, self.toastG, self.toastB)
    self:drawRect(boxX, boxY + boxH - 2, boxW, 2, alpha, self.toastR, self.toastG, self.toastB)
    self:drawRect(boxX, boxY, 2, boxH, alpha, self.toastR, self.toastG, self.toastB)
    self:drawRect(boxX + boxW - 2, boxY, 2, boxH, alpha, self.toastR, self.toastG, self.toastB)

    -- Texto centrado
    self:drawText(txt, boxX + (boxW - txtW) / 2, boxY + (boxH - txtH) / 2,
                  self.toastR, self.toastG, self.toastB, alpha, UIFont.Medium)
end

-- ════════════════════════════════════════════════════════════════════
-- v0.8 #6: HoldoorRaiseUpFade — animacion epica pantalla negra con fade
-- para el revive del Raise up John Snow (HP<15 → resurreccion).
-- Flow: fade in 1s → sostenido 3s con texto + subtexto → fade out 1s.
-- Total ~5 segundos. NO captura clicks (setWantMouseEvents=false).
-- Uso: HoldoorRaiseUpFade.mostrar()
-- ════════════════════════════════════════════════════════════════════

HoldoorRaiseUpFade = ISPanel:derive("HoldoorRaiseUpFade")
HoldoorRaiseUpFade.instance = nil

function HoldoorRaiseUpFade:new()
    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    local o  = ISPanel.new(self, 0, 0, sw, sh)
    setmetatable(o, self)
    self.__index      = self
    o.backgroundColor = {r=0, g=0, b=0, a=0}
    o.borderColor     = {r=0, g=0, b=0, a=0}
    o.moveWithMouse   = false
    o.tick            = 99999
    o.maxTicks        = 600  -- v0.8 #12: 10 segundos a 60fps (era 5s, ampliado a peticion)
    return o
end

function HoldoorRaiseUpFade:initialise()
    ISPanel.initialise(self)
    pcall(function() self:setWantMouseEvents(false) end)
end

function HoldoorRaiseUpFade:isMouseOver()              return false end
function HoldoorRaiseUpFade:onMouseDown(x, y)          return false end
function HoldoorRaiseUpFade:onMouseUp(x, y)            return false end
function HoldoorRaiseUpFade:onMouseMove(dx, dy)        return false end
function HoldoorRaiseUpFade:onMouseMoveOutside(dx, dy) return false end
function HoldoorRaiseUpFade:onMouseDownOutside(x, y)   return false end
function HoldoorRaiseUpFade:onMouseUpOutside(x, y)     return false end
function HoldoorRaiseUpFade:onRightMouseDown(x, y)     return false end
function HoldoorRaiseUpFade:onRightMouseUp(x, y)       return false end
function HoldoorRaiseUpFade:onMouseWheel(del)          return false end

function HoldoorRaiseUpFade.mostrar()
    local inst = HoldoorRaiseUpFade.instance
    if not inst then return end
    inst.tick = 0
    inst:setVisible(true)
end

function HoldoorRaiseUpFade.crear()
    if HoldoorRaiseUpFade.instance then return end
    local inst = HoldoorRaiseUpFade:new()
    inst:initialise()
    inst:addToUIManager()
    inst:setVisible(false)
    HoldoorRaiseUpFade.instance = inst
end

function HoldoorRaiseUpFade:render()
    ISPanel.render(self)

    local maxTicks = self.maxTicks or 600
    self.tick = (self.tick or maxTicks) + 1

    if self.tick >= maxTicks then
        self:setVisible(false)
        return
    end

    -- 3-phase alpha (v0.8 #12 ampliado a 10s total):
    -- 0-60 frames (1s): fade in (alpha 0→1)
    -- 60-540 frames (8s): sostenido (alpha 1)
    -- 540-600 frames (1s): fade out (alpha 1→0)
    local alpha
    local fadeIn  = 60
    local fadeOut = 60
    if self.tick < fadeIn then
        alpha = self.tick / fadeIn
    elseif self.tick > maxTicks - fadeOut then
        alpha = (maxTicks - self.tick) / fadeOut
    else
        alpha = 1.0
    end
    alpha = math.max(0, math.min(1, alpha))

    local sw = self.width
    local sh = self.height
    local cy = sh / 2

    -- 1) Fondo negro fullscreen — alpha 1.0 (v0.8 #15: completamente negro, no gris)
    self:drawRect(0, 0, sw, sh, alpha, 0, 0, 0)

    -- 2) Texto principal — v0.8 #15: sin ¡ inicial (fuente PZ lo renderiza como "?")
    local tm = getTextManager()
    local txt = "John Snow ha sido levantado por el R'hllor!"
    local txtW = tm:MeasureStringX(UIFont.Large, txt)
    local txtH = tm:MeasureStringY(UIFont.Large, txt)
    self:drawText(txt, sw/2 - txtW/2, cy - txtH/2 - 20,
                  0.95, 0.75, 0.20, alpha, UIFont.Large)

    -- 3) Subtexto en fuente mas chica
    local sub = "El Senor de Luz te devuelve a la vida"
    local subW = tm:MeasureStringX(UIFont.Medium, sub)
    self:drawText(sub, sw/2 - subW/2, cy + 16,
                  0.85, 0.65, 0.30, alpha * 0.85, UIFont.Medium)
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
