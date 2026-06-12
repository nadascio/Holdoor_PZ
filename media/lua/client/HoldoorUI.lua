-- ============================================================
--  Holdoor — Sistema de Oleadas  |  Panel de configuración
--  UI completa en español, accesible con /holdoor o /hd
-- ============================================================

require "HoldoorConfig"
require "HoldoorClient"

HoldoorUI = HoldoorUI or {}
HoldoorUI.instancia = nil

-- Dimensiones del panel
local PANEL_W = 480
local PANEL_H = 560

-- Colores del tema (gótico/medieval, guiño a GoT)
local COLOR_FONDO      = { r=0.05, g=0.04, b=0.03, a=0.97 }
local COLOR_BORDE      = { r=0.6,  g=0.4,  b=0.1,  a=1    }
local COLOR_SECCION    = { r=0.12, g=0.10, b=0.06, a=1    }
local COLOR_BOTON_OK   = { r=0.15, g=0.45, b=0.15, a=1    }
local COLOR_BOTON_STOP = { r=0.45, g=0.10, b=0.10, a=1    }
local COLOR_BOTON_BASE = { r=0.15, g=0.30, b=0.50, a=1    }
local COLOR_BOTON_ONDA = { r=0.45, g=0.25, b=0.05, a=1    }
local COLOR_TEXTO      = { r=0.95, g=0.85, b=0.60, a=1    }
local COLOR_TEXTO_DIM  = { r=0.55, g=0.50, b=0.35, a=1    }
local COLOR_ROJO       = { r=1.0,  g=0.3,  b=0.2,  a=1    }
local COLOR_VERDE      = { r=0.3,  g=1.0,  b=0.3,  a=1    }

-- ─────────────────────────────────────────────
--  ABRIR / CERRAR
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

    local sx = getCore():getScreenWidth()
    local sy = getCore():getScreenHeight()
    local x  = math.floor((sx - PANEL_W) / 2)
    local y  = math.floor((sy - PANEL_H) / 2)

    local panel = HoldoorPanel:new(x, y, PANEL_W, PANEL_H)
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
--  CREAR TODOS LOS CONTROLES
-- ─────────────────────────────────────────────

function HoldoorPanel:crearContenido()
    local w   = self.width
    local pad = 16
    local y   = 0

    -- ── TÍTULO ──────────────────────────────
    y = y + 10
    self.lblTitulo = ISLabel:new(pad, y, 30, "⚔  HOLDOOR — Sistema de Oleadas", 0.95, 0.75, 0.3, 1, UIFont.Medium, true)
    self:addChild(self.lblTitulo)

    self.lblVersion = ISLabel:new(w - 55, y + 5, 20, "v" .. HoldoorConfig.VERSION, 0.4, 0.4, 0.3, 1, UIFont.Small, true)
    self:addChild(self.lblVersion)

    y = y + 32

    -- ── ESTADO ACTUAL ───────────────────────
    self:dibujarSeparador(y, "Estado actual")
    y = y + 22

    self.lblEstado = ISLabel:new(pad, y, 20, "Estado: Inactivo", 0.7, 0.7, 0.7, 1, UIFont.Small, true)
    self:addChild(self.lblEstado)

    self.lblOleada = ISLabel:new(pad + 180, y, 20, "Oleada: —", 0.7, 0.7, 0.7, 1, UIFont.Small, true)
    self:addChild(self.lblOleada)

    self.lblBase = ISLabel:new(pad, y + 18, 20, "Base: No definida", 0.7, 0.7, 0.7, 1, UIFont.Small, true)
    self:addChild(self.lblBase)

    y = y + 46

    -- ── CONFIGURACIÓN ───────────────────────
    self:dibujarSeparador(y, "Configuración")
    y = y + 22

    -- Tamaño de oleada
    y = self:crearSlider(y, pad,
        "Tamaño de oleada",
        "Cantidad de zombis que aparecen por oleada (escala +10% por oleada)",
        "tamanoOleada",
        HoldoorConfig.limites.tamanoOleada.min,
        HoldoorConfig.limites.tamanoOleada.max,
        HoldoorConfig.defaults.tamanoOleada
    )

    -- Intervalo entre oleadas
    y = self:crearSlider(y, pad,
        "Intervalo entre oleadas (minutos)",
        "Tiempo en minutos de juego entre cada oleada",
        "intervalMinutos",
        HoldoorConfig.limites.intervalMinutos.min,
        HoldoorConfig.limites.intervalMinutos.max,
        HoldoorConfig.defaults.intervalMinutos
    )

    -- Radio de spawn
    y = self:crearSlider(y, pad,
        "Radio de spawn (celdas)",
        "Distancia desde tu base donde aparecen los zombis. Más grande = más tiempo para prepararte",
        "radioSpawn",
        HoldoorConfig.limites.radioSpawn.min,
        HoldoorConfig.limites.radioSpawn.max,
        HoldoorConfig.defaults.radioSpawn
    )

    -- Máximo de oleadas
    y = self:crearSlider(y, pad,
        "Máximo de oleadas (0 = infinito)",
        "Cantidad total de oleadas antes de que el sistema se detenga solo",
        "maxOleadas",
        HoldoorConfig.limites.maxOleadas.min,
        HoldoorConfig.limites.maxOleadas.max,
        HoldoorConfig.defaults.maxOleadas
    )

    -- Día de inicio (solo informativo, la lógica la maneja el server)
    y = self:crearSlider(y, pad,
        "Día mínimo para activar",
        "No se pueden iniciar oleadas antes de este día del juego",
        "diaInicio",
        HoldoorConfig.limites.diaInicio.min,
        HoldoorConfig.limites.diaInicio.max,
        HoldoorConfig.defaults.diaInicio
    )

    y = y + 8

    -- ── BOTONES DE CONTROL ──────────────────
    self:dibujarSeparador(y, "Acciones")
    y = y + 22

    local bw  = math.floor((w - pad * 2 - 8) / 2)
    local bh  = 34

    -- Botón: Marcar base
    self.btnBase = ISButton:new(pad, y, bw, bh, "📍  Marcar mi posición como base", self, self.onMarcarBase)
    self.btnBase.backgroundColor = COLOR_BOTON_BASE
    self.btnBase.borderColor     = { r=0.3, g=0.5, b=0.8, a=1 }
    self:addChild(self.btnBase)

    -- Botón: Oleada manual
    self.btnOnda = ISButton:new(pad + bw + 8, y, bw, bh, "⚡  Forzar oleada ahora", self, self.onOleadaManual)
    self.btnOnda.backgroundColor = COLOR_BOTON_ONDA
    self.btnOnda.borderColor     = { r=0.7, g=0.4, b=0.1, a=1 }
    self:addChild(self.btnOnda)

    y = y + bh + 8

    -- Botón: Iniciar
    self.btnIniciar = ISButton:new(pad, y, bw, bh, "▶  INICIAR OLEADAS", self, self.onIniciar)
    self.btnIniciar.backgroundColor = COLOR_BOTON_OK
    self.btnIniciar.borderColor     = { r=0.3, g=0.7, b=0.3, a=1 }
    self:addChild(self.btnIniciar)

    -- Botón: Detener
    self.btnDetener = ISButton:new(pad + bw + 8, y, bw, bh, "■  DETENER OLEADAS", self, self.onDetener)
    self.btnDetener.backgroundColor = COLOR_BOTON_STOP
    self.btnDetener.borderColor     = { r=0.7, g=0.2, b=0.2, a=1 }
    self:addChild(self.btnDetener)

    y = y + bh + 14

    -- ── CERRAR ──────────────────────────────
    self.btnCerrar = ISButton:new(pad, y, w - pad * 2, 28, "Cerrar", self, self.onCerrar)
    self.btnCerrar.backgroundColor = { r=0.1, g=0.1, b=0.1, a=1 }
    self.btnCerrar.borderColor     = { r=0.3, g=0.3, b=0.3, a=1 }
    self:addChild(self.btnCerrar)

    -- Nota al pie
    y = y + 34
    self.lblNota = ISLabel:new(pad, y, 18, "\"Hold the door...\"  —  /holdoor o /hd para abrir este panel", 0.35, 0.30, 0.20, 1, UIFont.Small, true)
    self:addChild(self.lblNota)

    -- Actualizar estado visual inicial
    self:actualizarEstado()
end

-- ─────────────────────────────────────────────
--  HELPER: CREAR SLIDER CON LABEL + DESCRIPCIÓN
-- ─────────────────────────────────────────────

function HoldoorPanel:crearSlider(y, pad, titulo, descripcion, clave, valMin, valMax, valDefault)
    local w = self.width

    -- Label con nombre
    local lbl = ISLabel:new(pad, y, 20, titulo, COLOR_TEXTO.r, COLOR_TEXTO.g, COLOR_TEXTO.b, 1, UIFont.Small, true)
    self:addChild(lbl)

    -- Valor actual (a la derecha)
    local lblVal = ISLabel:new(w - 55, y, 20, tostring(valDefault), 1, 0.8, 0.3, 1, UIFont.Small, true)
    self:addChild(lblVal)
    if not self.sliderLabels then self.sliderLabels = {} end
    self.sliderLabels[clave] = lblVal

    y = y + 18

    -- Descripción en gris pequeño
    local lblDesc = ISLabel:new(pad + 4, y, 16, descripcion, COLOR_TEXTO_DIM.r, COLOR_TEXTO_DIM.g, COLOR_TEXTO_DIM.b, 1, UIFont.Small, true)
    self:addChild(lblDesc)

    y = y + 16

    -- Slider
    local slider = ISScrollBar:new(pad, y, w - pad * 2, 18, nil, nil)
    -- Como alternativa más simple, usar ISHorzScrollBar
    -- En PZ el componente de slider disponible es el scrollbar horizontal
    if ISHorzScrollBar then
        slider = ISHorzScrollBar:new(pad, y, w - pad * 2, 18, nil, nil)
    end

    if slider then
        slider.minVal   = valMin
        slider.maxVal   = valMax
        slider.currentVal = valDefault
        slider.holdoorClave = clave
        slider.holdoorPanel = self
        slider.onChange = function(target, val)
            local v = math.floor(val)
            if target.holdoorPanel and target.holdoorPanel.sliderLabels then
                target.holdoorPanel.sliderLabels[target.holdoorClave]:setName(tostring(v))
            end
        end
        self:addChild(slider)
        if not self.sliders then self.sliders = {} end
        self.sliders[clave] = slider
    end

    y = y + 24

    return y
end

-- ─────────────────────────────────────────────
--  HELPER: SEPARADOR VISUAL
-- ─────────────────────────────────────────────

function HoldoorPanel:dibujarSeparador(y, texto)
    -- Solo el label de sección (la línea se dibuja en render)
    local lbl = ISLabel:new(16, y + 4, 18, "▸  " .. texto, 0.7, 0.55, 0.2, 1, UIFont.Small, true)
    self:addChild(lbl)
    if not self.separadores then self.separadores = {} end
    table.insert(self.separadores, y)
end

-- ─────────────────────────────────────────────
--  RENDER CUSTOM (líneas separadoras)
-- ─────────────────────────────────────────────

function HoldoorPanel:render()
    ISPanel.render(self)
    -- Dibujar líneas de separación
    if self.separadores then
        for _, sy in ipairs(self.separadores) do
            self:drawRect(0, sy, self.width, 1, 0.4, 0.6, 0.4, 0.1)
            self:drawRect(0, sy, self.width, 18, 0.12, 0.10, 0.06, 1)
        end
    end
end

-- ─────────────────────────────────────────────
--  ACTUALIZAR ESTADO VISUAL
-- ─────────────────────────────────────────────

function HoldoorPanel:actualizarEstado()
    local est = HoldoorClient.estado

    if self.lblEstado then
        if est.activo then
            self.lblEstado:setName("Estado: ACTIVO")
            self.lblEstado:setColor(COLOR_VERDE.r, COLOR_VERDE.g, COLOR_VERDE.b, 1)
        else
            self.lblEstado:setName("Estado: Inactivo")
            self.lblEstado:setColor(0.7, 0.7, 0.7, 1)
        end
    end

    if self.lblOleada then
        if est.oleadaActual and est.oleadaActual > 0 then
            self.lblOleada:setName("Oleada: #" .. est.oleadaActual)
        else
            self.lblOleada:setName("Oleada: —")
        end
    end

    if self.lblBase then
        if est.baseDefinida then
            self.lblBase:setName("Base: " .. est.baseX .. ", " .. est.baseY)
            self.lblBase:setColor(0.4, 0.8, 1, 1)
        else
            self.lblBase:setName("Base: ⚠ No definida — marcá tu posición antes de iniciar")
            self.lblBase:setColor(COLOR_ROJO.r, COLOR_ROJO.g, COLOR_ROJO.b, 1)
        end
    end
end

-- ─────────────────────────────────────────────
--  LEER VALORES DE LOS SLIDERS
-- ─────────────────────────────────────────────

function HoldoorPanel:leerConfig()
    local config = {}
    for k, v in pairs(HoldoorConfig.defaults) do
        config[k] = v
    end
    if self.sliders then
        for clave, slider in pairs(self.sliders) do
            if slider and slider.currentVal then
                config[clave] = math.floor(slider.currentVal)
            end
        end
    end
    return config
end

-- ─────────────────────────────────────────────
--  HANDLERS DE BOTONES
-- ─────────────────────────────────────────────

function HoldoorPanel:onMarcarBase()
    HoldoorClient.setBase()
end

function HoldoorPanel:onIniciar()
    if not HoldoorClient.estado.baseDefinida then
        -- Advertencia visible
        if self.lblBase then
            self.lblBase:setName("⚠ ¡Primero marcá tu base!")
            self.lblBase:setColor(1, 0.3, 0.2, 1)
        end
        return
    end
    local config = self:leerConfig()
    HoldoorClient.iniciar(config)
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
end

function HoldoorPanel:onKeyPressed(key)
    -- Cerrar con Escape
    if key == Keyboard.KEY_ESCAPE then
        self:onCerrar()
    end
end
