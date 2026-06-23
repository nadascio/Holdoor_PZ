-- ============================================================
--  Holdoor -- Pantalla de Bienvenida (primera vez por personaje)
--
--  Se muestra una vez al entrar a una partida con Holdoor. El jugador puede
--  marcar "No volver a mostrar" (flag en player modData -> no sale mas para ese
--  personaje; mundo/personaje nuevo vuelve a salir).
--
--  i18n: TODOS los textos estan centralizados en HoldoorWelcome.txt para que la
--  traduccion futura sea trivial (manana esta tabla pasa a getText() + archivos
--  Translate/ES y Translate/EN). NO hay textos hardcodeados en el render.
-- ============================================================

HoldoorWelcome = HoldoorWelcome or {}

HoldoorWelcome.GUIA_URL = "https://nadascio.github.io/Holdoor_PZ/"

-- ── TEXTOS (ES) — punto unico para traducir ───────────────────
HoldoorWelcome.txt = {
    titulo    = "HOLDOOR",
    subtitulo = "Defiende el Trono de Hierro",
    intro = {
        "Defensa por oleadas estilo Game of Thrones.",
        "Marca tu base y aparece el Trono de Hierro:",
        "defendelo de las hordas. Si el Trono cae, perdes.",
    },
    tips = {
        "F10 abre el panel de oleadas (en multiplayer, solo el host).",
        "A la derecha tenes el HUD: oleadas, items y la tienda.",
        "Entre oleada y oleada, gasta tus monedas en la Tienda.",
    },
    btnGuia   = "VER GUIA COMPLETA (ES / EN)",
    btnCerrar = "ENTENDIDO",
    noMostrar = "No volver a mostrar este mensaje",
}

local W, H = 540, 380

-- ──────────────────────────────────────────────────────────────
--  PANEL
-- ──────────────────────────────────────────────────────────────
HoldoorWelcomePanel = ISPanel:derive("HoldoorWelcomePanel")

function HoldoorWelcomePanel:new(x, y, w, h)
    local o = ISPanel.new(self, x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.backgroundColor = { r = 0.06, g = 0.06, b = 0.08, a = 0.97 }
    o.borderColor     = { r = 0.83, g = 0.69, b = 0.22, a = 1 }
    o.moveWithMouse   = true
    return o
end

function HoldoorWelcomePanel:initialise()
    ISPanel.initialise(self)
    self:createChildren()
end

function HoldoorWelcomePanel:createChildren()
    local pad = 22
    local bh  = 34
    local innerW = self.width - pad * 2

    -- Checkbox "No volver a mostrar"
    self.tick = ISTickBox:new(pad, self.height - 92, innerW, 22, "", self, nil)
    self.tick:initialise()
    self.tick:instantiate()
    self.tick:addOption(HoldoorWelcome.txt.noMostrar)
    self.tick.choicesColor = { r = 0.85, g = 0.82, b = 0.7, a = 1 }
    self:addChild(self.tick)

    -- Botones (Ver guia / Entendido), lado a lado
    local halfW = math.floor((innerW - 10) / 2)
    self.btnGuia = ISButton:new(pad, self.height - 54, halfW, bh, HoldoorWelcome.txt.btnGuia, self, HoldoorWelcomePanel.onGuia)
    self.btnGuia.backgroundColor = { r = 0.18, g = 0.14, b = 0.05, a = 1 }
    self.btnGuia.borderColor     = { r = 0.83, g = 0.69, b = 0.22, a = 1 }
    self:addChild(self.btnGuia)

    self.btnCerrar = ISButton:new(pad + halfW + 10, self.height - 54, halfW, bh, HoldoorWelcome.txt.btnCerrar, self, HoldoorWelcomePanel.onCerrar)
    self.btnCerrar.backgroundColor = { r = 0.12, g = 0.20, b = 0.12, a = 1 }
    self.btnCerrar.borderColor     = { r = 0.30, g = 0.60, b = 0.30, a = 1 }
    self:addChild(self.btnCerrar)
end

function HoldoorWelcomePanel:render()
    ISPanel.render(self)
    local cx = self.width / 2

    self:drawTextCentre(HoldoorWelcome.txt.titulo,    cx, 22, 0.83, 0.69, 0.22, 1, UIFont.Title)
    self:drawTextCentre(HoldoorWelcome.txt.subtitulo, cx, 64, 0.70, 0.65, 0.50, 1, UIFont.Medium)

    local y = 110
    for _, linea in ipairs(HoldoorWelcome.txt.intro) do
        self:drawTextCentre(linea, cx, y, 0.88, 0.86, 0.80, 1, UIFont.Small)
        y = y + 22
    end

    y = y + 16
    for _, linea in ipairs(HoldoorWelcome.txt.tips) do
        self:drawText("-  " .. linea, 26, y, 0.82, 0.80, 0.64, 1, UIFont.Small)
        y = y + 24
    end

    -- URL visible (respaldo si el boton no abre el navegador en este equipo)
    self:drawTextCentre("Guia completa:  nadascio.github.io/Holdoor_PZ", self.width / 2, self.height - 120, 0.55, 0.68, 0.90, 1, UIFont.Small)
end

function HoldoorWelcomePanel:onGuia()
    local url = HoldoorWelcome.GUIA_URL
    -- 1) COPIAR al portapapeles (siempre funciona) -> el usuario la pega (Ctrl+V) en su navegador.
    pcall(function() Clipboard.setClipboard(url) end)
    -- 2) Intentar ABRIR el navegador: con Steam overlay -> navegador interno de Steam;
    --    sin overlay -> navegador del sistema (patron del juego base, ISTermsOfServiceUI).
    pcall(function()
        if isSteamOverlayEnabled and isSteamOverlayEnabled() then
            activateSteamOverlayToWebPage(url)
        else
            openUrl(url)
        end
    end)
    -- 3) Avisar en el chat: si no abrio el navegador, igual ya esta copiada para pegar.
    pcall(function()
        if HoldoorClient and HoldoorClient.chat then
            HoldoorClient.chat("[HOLDOOR] Guia copiada al portapapeles. Pegala (Ctrl+V) en tu navegador: " .. url, 0.85, 0.70, 0.25)
        end
    end)
    print("[Holdoor] Welcome: abrir/copiar guia -> " .. tostring(url))
end

function HoldoorWelcomePanel:onCerrar()
    -- Si marco "No volver a mostrar", persistir el flag en SU player modData.
    local marcado = self.tick and self.tick.selected and self.tick.selected[1] == true
    if marcado then
        pcall(function()
            local p = getSpecificPlayer(0)
            if p then
                local md = p:getModData()
                md.Holdoor_WelcomeSeen = true
                p:transmitModData()
            end
        end)
    end
    self:setVisible(false)
    self:removeFromUIManager()
    HoldoorWelcome.instancia = nil
end

-- ──────────────────────────────────────────────────────────────
--  MOSTRAR + TRIGGER
-- ──────────────────────────────────────────────────────────────
function HoldoorWelcome.mostrar()
    if HoldoorWelcome.instancia then return end
    local sw, sh = 800, 600
    pcall(function() sw = getCore():getScreenWidth() end)
    pcall(function() sh = getCore():getScreenHeight() end)
    local panel = HoldoorWelcomePanel:new(math.floor((sw - W) / 2), math.floor((sh - H) / 2), W, H)
    panel:initialise()
    panel:addToUIManager()
    HoldoorWelcome.instancia = panel
end

-- Corre cada tick al iniciar el juego hasta que el player exista; ahi decide
-- si mostrar la bienvenida (segun el flag) y se desregistra.
function HoldoorWelcome._tickInicio()
    local p = getSpecificPlayer(0)
    if not p then return end          -- player todavia no listo, reintentar proximo tick
    Events.OnTick.Remove(HoldoorWelcome._tickInicio)

    local md
    pcall(function() md = p:getModData() end)
    if md and md.Holdoor_WelcomeSeen then return end   -- ya la vio / marco no mostrar
    HoldoorWelcome.mostrar()
end

Events.OnGameStart.Add(function()
    Events.OnTick.Add(HoldoorWelcome._tickInicio)
end)
