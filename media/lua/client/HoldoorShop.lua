-- ============================================================
--  Holdoor -- Tienda (modal)
--  Catalogo en HoldoorShopCatalog (shared). Compras via cliente -> server.
-- ============================================================

require "HoldoorShopCatalog"
require "HoldoorClient"

HoldoorShop = HoldoorShop or {}
HoldoorShop.instance = nil

local SHOP_W = 820   -- ampliado para que entre el header completo de materiales
local SHOP_H = 540

local PAD       = 14
local SIDEBAR_W = 170
local HEADER_H  = 70  -- ampliado para incluir linea de materiales
local ROW_H     = 64  -- alto de cada fila de item

local COLOR_FONDO_S    = { r=0.05, g=0.04, b=0.03, a=0.97 }
local COLOR_BORDE_S    = { r=0.6,  g=0.4,  b=0.1,  a=1    }
local COLOR_BTN_OK_S   = { r=0.18, g=0.45, b=0.20, a=1    }
local COLOR_BTN_BAD_S  = { r=0.35, g=0.10, b=0.10, a=1    }
local COLOR_BTN_DIS_S  = { r=0.18, g=0.18, b=0.20, a=1    }
local COLOR_BRONCE     = { r=0.72, g=0.45, b=0.20, a=1    }
local COLOR_PLATA      = { r=0.78, g=0.78, b=0.80, a=1    }
local COLOR_ORO        = { r=0.89, g=0.65, b=0.28, a=1    }
local COLOR_CUERO      = { r=0.55, g=0.35, b=0.18, a=1    }
local COLOR_HIERRO     = { r=0.65, g=0.65, b=0.65, a=1    }
local COLOR_ACERO      = { r=0.60, g=0.78, b=0.92, a=1    }
local COLOR_VALYRIO    = { r=0.70, g=0.40, b=0.85, a=1    }
local COLOR_OBSIDIANA  = { r=0.45, g=0.20, b=0.50, a=1    }
local COLOR_HEADER_LBL = { r=0.95, g=0.85, b=0.55, a=1    }   -- label "Saldo:" / "Materiales:"

-- ─────────────────────────────────────────────
--  ENTRY POINT
-- ─────────────────────────────────────────────

function HoldoorShop.abrir()
    if HoldoorShop.instance then
        HoldoorShop.instance:removeFromUIManager()
        HoldoorShop.instance = nil
    end
    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    local p  = HoldoorShopPanel:new((sw - SHOP_W) / 2, (sh - SHOP_H) / 2, SHOP_W, SHOP_H)
    p:initialise()
    p:addToUIManager()
    HoldoorShop.instance = p
end

-- Llamada desde HoldoorClient cuando una compra OK actualiza saldo/etc.
function HoldoorShop.refrescar()
    if HoldoorShop.instance then HoldoorShop.instance:_renderCategoria() end
end

-- ─────────────────────────────────────────────
--  PANEL PRINCIPAL
-- ─────────────────────────────────────────────

HoldoorShopPanel = ISPanel:derive("HoldoorShopPanel")

function HoldoorShopPanel:new(x, y, w, h)
    local o = ISPanel.new(self, x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.backgroundColor = COLOR_FONDO_S
    o.borderColor     = COLOR_BORDE_S
    o.moveWithMouse   = true
    o.categoriaActual = 1
    o.scrollOffset    = 0   -- indice del primer item visible (paginacion)
    o.filasItems      = {}  -- guarda referencias a las filas para destruirlas al cambiar de cat
    return o
end

-- Maximo de items visibles a la vez en la lista (resto se ve con scroll)
local MAX_FILAS_VISIBLES = 6

function HoldoorShopPanel:initialise()
    ISPanel.initialise(self)
    self:_crearContenido()
end

function HoldoorShopPanel:_crearContenido()
    local pad = PAD

    -- Header: titulo + saldo + close
    self.lblTit = ISLabel:new(pad, 12, 24, "TIENDA HOLDOOR", 0.95, 0.78, 0.30, 1, UIFont.Medium, true)
    self:addChild(self.lblTit)

    -- Saldo y materiales se dibujan en :render() con colores por moneda/material.
    -- Posicion Y: 14 (saldo) y 38 (materiales). X base: 220 (despues del titulo).
    self._yMonedasHeader   = 14
    self._yMaterialesHeader = 38

    self.btnClose = ISButton:new(SHOP_W - 36, 12, 24, 22, "X", self, HoldoorShopPanel.onClose)
    self.btnClose.backgroundColor = { r=0.35, g=0.10, b=0.10, a=1 }
    self.btnClose.borderColor     = { r=0.6,  g=0.2,  b=0.2,  a=1 }
    self:addChild(self.btnClose)

    -- Linea divisoria bajo header
    self:_addDivider(pad, HEADER_H, SHOP_W - pad*2, 1)

    -- Sidebar: botones de categoria
    self.botonesCat = {}
    local cy = HEADER_H + 12
    for i, cat in ipairs(HoldoorShopCatalog.categorias) do
        local lbl = cat.nombre .. (cat.proximamente and "  (proximamente)" or "")
        local btn = ISButton:new(pad, cy, SIDEBAR_W, 30, lbl, self, HoldoorShopPanel.onSelectCat)
        btn.holdoorCatIdx    = i
        btn.backgroundColor  = { r=cat.cr*0.20, g=cat.cg*0.20, b=cat.cb*0.20, a=1 }
        btn.borderColor      = { r=cat.cr*0.55, g=cat.cg*0.55, b=cat.cb*0.55, a=1 }
        self:addChild(btn)
        self.botonesCat[i] = btn
        cy = cy + 34
    end

    -- Linea divisoria vertical
    self:_addDivider(pad + SIDEBAR_W + 6, HEADER_H + 6, 1, SHOP_H - HEADER_H - 20)

    -- Footer info
    self.lblFooter = ISLabel:new(pad, SHOP_H - 22, 14,
        "Las monedas son personales -- las compras se entregan al inventario al instante.",
        0.55, 0.50, 0.40, 1, UIFont.Small, true)
    self:addChild(self.lblFooter)

    self:_refrescarSaldo()
    self:_renderCategoria()
end

function HoldoorShopPanel:_addDivider(x, y, w, h)
    -- Helper visual: divisores via drawRect en render()
    self._divs = self._divs or {}
    table.insert(self._divs, { x=x, y=y, w=w, h=h })
end

function HoldoorShopPanel:render()
    ISPanel.render(self)
    if self._divs then
        for _, d in ipairs(self._divs) do
            self:drawRect(d.x, d.y, d.w, d.h, 0.5, 0.6, 0.4, 0.15)
        end
    end

    -- Linea de SALDO con colores por moneda
    if HoldoorClient and HoldoorClient.getSaldo then
        local b, s, g = HoldoorClient.getSaldo()
        local y = self._yMonedasHeader or 14
        local x = 220
        self:drawText("Saldo: ",      x,        y, COLOR_HEADER_LBL.r, COLOR_HEADER_LBL.g, COLOR_HEADER_LBL.b, 1, UIFont.Small)
        x = x + 50
        self:drawText(b .. " Bronce", x,        y, COLOR_BRONCE.r,     COLOR_BRONCE.g,     COLOR_BRONCE.b,     1, UIFont.Small)
        x = x + 110
        self:drawText(s .. " Plata",  x,        y, COLOR_PLATA.r,      COLOR_PLATA.g,      COLOR_PLATA.b,      1, UIFont.Small)
        x = x + 100
        self:drawText(g .. " Oro",    x,        y, COLOR_ORO.r,        COLOR_ORO.g,        COLOR_ORO.b,        1, UIFont.Small)
    end

    -- Linea de MATERIALES con colores por material
    if HoldoorClient and HoldoorClient.getMateriales then
        local m = HoldoorClient.getMateriales()
        local y = self._yMaterialesHeader or 38
        local x = 220
        self:drawText("Materiales: ",        x,         y, COLOR_HEADER_LBL.r, COLOR_HEADER_LBL.g, COLOR_HEADER_LBL.b, 1, UIFont.Small)
        x = x + 80
        self:drawText(m.cuero .. " Cuero",    x,         y, COLOR_CUERO.r,      COLOR_CUERO.g,      COLOR_CUERO.b,      1, UIFont.Small)
        x = x + 90
        self:drawText(m.hierro .. " Hierro",  x,         y, COLOR_HIERRO.r,     COLOR_HIERRO.g,     COLOR_HIERRO.b,     1, UIFont.Small)
        x = x + 95
        self:drawText(m.acero .. " Acero",    x,         y, COLOR_ACERO.r,      COLOR_ACERO.g,      COLOR_ACERO.b,      1, UIFont.Small)
        x = x + 90
        self:drawText(m.valyrio .. " Valyrio", x,        y, COLOR_VALYRIO.r,    COLOR_VALYRIO.g,    COLOR_VALYRIO.b,    1, UIFont.Small)
        x = x + 95
        self:drawText(m.obsidiana .. " Obsidiana", x,    y, COLOR_OBSIDIANA.r,  COLOR_OBSIDIANA.g,  COLOR_OBSIDIANA.b,  1, UIFont.Small)
    end
end

function HoldoorShopPanel:_refrescarSaldo()
    -- El render custom en :render() se encarga de leer getSaldo/getMateriales cada frame.
end

function HoldoorShopPanel:onSelectCat(button)
    self.categoriaActual = button.holdoorCatIdx
    self.scrollOffset    = 0   -- reset al cambiar de categoria
    self:_renderCategoria()
end

function HoldoorShopPanel:onScrollUp()
    self.scrollOffset = math.max(0, (self.scrollOffset or 0) - MAX_FILAS_VISIBLES)
    self:_renderCategoria()
end

function HoldoorShopPanel:onScrollDown()
    self.scrollOffset = (self.scrollOffset or 0) + MAX_FILAS_VISIBLES
    self:_renderCategoria()
end

-- ─────────────────────────────────────────────
--  RENDER DE FILAS DE ITEMS
-- ─────────────────────────────────────────────

function HoldoorShopPanel:_destruirFilas()
    for _, fila in ipairs(self.filasItems or {}) do
        for _, hijo in ipairs(fila._hijos or {}) do
            if hijo then pcall(function() self:removeChild(hijo) end) end
        end
    end
    self.filasItems = {}
end

function HoldoorShopPanel:_renderCategoria()
    self:_destruirFilas()
    self:_refrescarSaldo()

    -- Marcar boton activo
    for i, btn in ipairs(self.botonesCat) do
        local cat = HoldoorShopCatalog.categorias[i]
        if i == self.categoriaActual then
            btn.borderColor = { r=0.95, g=0.82, b=0.20, a=1 }
        else
            btn.borderColor = { r=cat.cr*0.55, g=cat.cg*0.55, b=cat.cb*0.55, a=1 }
        end
    end

    local cat = HoldoorShopCatalog.categorias[self.categoriaActual]
    if not cat then return end

    local areaX = PAD + SIDEBAR_W + 18
    local areaY = HEADER_H + 12

    -- Header de categoria
    local lblTitCat = ISLabel:new(areaX, areaY, 22, cat.nombre, cat.cr, cat.cg, cat.cb, 1, UIFont.Medium, true)
    self:addChild(lblTitCat)
    table.insert(self.filasItems, { _hijos = { lblTitCat } })
    areaY = areaY + 30

    -- Caso especial: categoria proximamente
    if cat.proximamente or #cat.items == 0 then
        local lblSoon = ISLabel:new(areaX, areaY + 30, 18,
            "Esta seccion abre en un proximo update.",
            0.60, 0.60, 0.55, 1, UIFont.Medium, true)
        self:addChild(lblSoon)
        local lblSoon2 = ISLabel:new(areaX, areaY + 56, 16,
            "Los materiales seran necesarios para craftear armaduras y armas mejoradas.",
            0.45, 0.45, 0.42, 1, UIFont.Small, true)
        self:addChild(lblSoon2)
        table.insert(self.filasItems, { _hijos = { lblSoon, lblSoon2 } })
        return
    end

    local saldoB, saldoS, saldoG = HoldoorClient.getSaldo()
    local mats = HoldoorClient.getMateriales and HoldoorClient.getMateriales() or
                 { cuero=0, hierro=0, acero=0, valyrio=0, obsidiana=0 }

    -- Clamp del scroll para que no se vaya de rango
    local totalItems = #cat.items
    local maxScroll = math.max(0, totalItems - MAX_FILAS_VISIBLES)
    if self.scrollOffset > maxScroll then self.scrollOffset = maxScroll end
    if self.scrollOffset < 0 then self.scrollOffset = 0 end

    local startIdx = (self.scrollOffset or 0) + 1
    local endIdx   = math.min(totalItems, startIdx + MAX_FILAS_VISIBLES - 1)

    -- Indicador "viendo X-Y de Z" arriba a la derecha del area de items
    if totalItems > MAX_FILAS_VISIBLES then
        local lblPag = ISLabel:new(SHOP_W - PAD - 110, areaY - 26, 14,
            "(" .. startIdx .. "-" .. endIdx .. " de " .. totalItems .. ")",
            0.65, 0.65, 0.60, 1, UIFont.Small, true)
        self:addChild(lblPag)
        table.insert(self.filasItems, { _hijos = { lblPag } })

        -- Botones ARRIBA/ABAJO al final del area
        local btnUp = ISButton:new(SHOP_W - PAD - 52, areaY - 28, 24, 22, "^",
            self, HoldoorShopPanel.onScrollUp)
        btnUp.backgroundColor = { r=0.20, g=0.25, b=0.35, a=1 }
        btnUp.borderColor     = { r=0.5, g=0.7, b=0.9, a=1 }
        self:addChild(btnUp)
        table.insert(self.filasItems, { _hijos = { btnUp } })

        local btnDn = ISButton:new(SHOP_W - PAD - 26, areaY - 28, 24, 22, "v",
            self, HoldoorShopPanel.onScrollDown)
        btnDn.backgroundColor = { r=0.20, g=0.25, b=0.35, a=1 }
        btnDn.borderColor     = { r=0.5, g=0.7, b=0.9, a=1 }
        self:addChild(btnDn)
        table.insert(self.filasItems, { _hijos = { btnDn } })
    end

    for i = startIdx, endIdx do
        local item = cat.items[i]
        local hijos = {}

        -- Nombre
        local lblN = ISLabel:new(areaX, areaY + 4, 18, item.nombre, 0.95, 0.85, 0.55, 1, UIFont.Medium, true)
        self:addChild(lblN); table.insert(hijos, lblN)

        -- Descripcion
        local lblD = ISLabel:new(areaX, areaY + 26, 14, item.desc or "", 0.70, 0.65, 0.50, 1, UIFont.Small, true)
        self:addChild(lblD); table.insert(hijos, lblD)

        -- Precio (color segun moneda mas alta involucrada)
        local precioTxt = HoldoorShopCatalog.precioStr(item.precio)
        local precioColor = COLOR_BRONCE
        if (item.precio.gold or 0) > 0 or (item.precio.valyrio or 0) > 0 or (item.precio.obsidiana or 0) > 0 then
            precioColor = COLOR_ORO
        elseif (item.precio.silver or 0) > 0 or (item.precio.acero or 0) > 0 then
            precioColor = COLOR_PLATA
        end

        -- Precio: solo se muestra si NO esta consumido. Si esta consumido,
        -- se reemplaza por la leyenda "Ya invocado / Limite alcanzado" para no
        -- pisar la fila siguiente (ROW_H=64 deja un solo slot bajo el nombre+desc).
        local lblP = nil  -- se crea recien despues del check de consumido

        -- Validar si puede pagar: monedas + materiales
        local puede = (saldoB >= (item.precio.bronze or 0))
                  and (saldoS >= (item.precio.silver or 0))
                  and (saldoG >= (item.precio.gold   or 0))
                  and (mats.cuero     >= (item.precio.cuero     or 0))
                  and (mats.hierro    >= (item.precio.hierro    or 0))
                  and (mats.acero     >= (item.precio.acero     or 0))
                  and (mats.valyrio   >= (item.precio.valyrio   or 0))
                  and (mats.obsidiana >= (item.precio.obsidiana or 0))

        -- Restriccion "1 por vida": activa para Rasgos Heroicos y Milagros.
        local consumido = false
        local consumidoTxt = nil
        if item.accion then
            local player
            pcall(function() player = getSpecificPlayer(0) end)
            if player then
                local md
                pcall(function() md = player:getModData() end)
                if md then
                    if item.accion.tipo == "trait" and md.Holdoor_TraitComprado then
                        consumido = true
                        if tostring(item.accion.trait) == tostring(md.Holdoor_TraitComprado) then
                            consumidoTxt = "Ya invocado por este personaje"
                        else
                            consumidoTxt = "Limite 1 por vida alcanzado"
                        end
                    elseif item.accion.tipo == "cura_trait" and md.Holdoor_TraitCurado then
                        consumido = true
                        if tostring(item.accion.trait) == tostring(md.Holdoor_TraitCurado) then
                            consumidoTxt = "Ya curado por este personaje"
                        else
                            consumidoTxt = "Limite 1 por vida alcanzado"
                        end
                    end
                end
            end
        end

        -- Render del slot inferior: si consumido → leyenda en rojo apagado;
        -- si no → el precio normal.
        if consumido and consumidoTxt then
            local lblConsum = ISLabel:new(areaX, areaY + 44, 14, consumidoTxt, 1.0, 0.5, 0.4, 1, UIFont.Small, true)
            self:addChild(lblConsum); table.insert(hijos, lblConsum)
        else
            lblP = ISLabel:new(areaX, areaY + 44, 14, precioTxt,
                precioColor.r, precioColor.g, precioColor.b, 1, UIFont.Small, true)
            self:addChild(lblP); table.insert(hijos, lblP)
        end

        -- Boton: prioridad 1) consumido => YA USADO  2) sin saldo  3) COMPRAR
        local btnTexto, btnHandler, btnBg, btnBorder, btnTextColor
        if consumido then
            btnTexto     = "YA USADO"
            btnHandler   = HoldoorShopPanel.doNothing
            btnBg        = COLOR_BTN_DIS_S
            btnBorder    = { r=0.50, g=0.25, b=0.25, a=1 }
            btnTextColor = { r=0.85, g=0.45, b=0.45, a=1 }
        elseif puede then
            btnTexto     = "COMPRAR"
            btnHandler   = HoldoorShopPanel.onComprar
            btnBg        = COLOR_BTN_OK_S
            btnBorder    = { r=0.4, g=0.75, b=0.4, a=1 }
            btnTextColor = nil
        else
            btnTexto     = "Sin saldo"
            btnHandler   = HoldoorShopPanel.doNothing
            btnBg        = COLOR_BTN_DIS_S
            btnBorder    = { r=0.3, g=0.3, b=0.3, a=1 }
            btnTextColor = { r=0.55, g=0.55, b=0.5, a=1 }
        end

        local btn = ISButton:new(SHOP_W - PAD - 110, areaY + 16, 105, 30, btnTexto, self, btnHandler)
        btn.holdoorItem     = { categoriaId = cat.id, itemId = item.id }
        btn.backgroundColor = btnBg
        btn.borderColor     = btnBorder
        if btnTextColor then btn.textColor = btnTextColor end
        self:addChild(btn); table.insert(hijos, btn)

        table.insert(self.filasItems, { _hijos = hijos })
        areaY = areaY + ROW_H
    end
end

function HoldoorShopPanel:doNothing() end

-- Helper para encontrar la definicion del item por (categoriaId, itemId).
local function _findItemDef(categoriaId, itemId)
    if not HoldoorShopCatalog or not HoldoorShopCatalog.categorias then return nil end
    for _, cat in ipairs(HoldoorShopCatalog.categorias) do
        if cat.id == categoriaId then
            for _, it in ipairs(cat.items) do
                if it.id == itemId then return it end
            end
            return nil
        end
    end
    return nil
end

function HoldoorShopPanel:onComprar(button)
    if not button.holdoorItem then return end
    local categoriaId, itemId = button.holdoorItem.categoriaId, button.holdoorItem.itemId

    local itemDef = _findItemDef(categoriaId, itemId)
    if itemDef and itemDef.accion and (itemDef.accion.tipo == "trait" or itemDef.accion.tipo == "cura_trait") then
        -- 1) Verificar si el player puede REALMENTE comprar este item.
        --    Si la validacion devuelve nil (API fallo) → dejamos pasar al modal.
        local tieneTrait = nil
        if HoldoorClient and HoldoorClient.tieneTrait then
            tieneTrait = HoldoorClient.tieneTrait(itemDef.accion.trait)
        end
        if itemDef.accion.tipo == "trait" and tieneTrait == true then
            HoldoorClient.chat("[HOLDOOR] Ya tenes ese rasgo. No hace falta invocarlo.", 1, 0.6, 0.2)
            return
        end
        if itemDef.accion.tipo == "cura_trait" and tieneTrait == false then
            HoldoorClient.chat("[HOLDOOR] No tenes ese rasgo, no hay nada que curar.", 1, 0.6, 0.2)
            return
        end

        -- 2) Validacion pasada → pedir confirmacion antes de gastar las monedas.
        local etiqueta = itemDef.accion.tipo == "trait" and "RASGO HEROICO" or "MILAGRO DEL MAESTRE"
        local txt = "ATENCION: solo podes invocar UN " .. etiqueta .. " por vida del personaje.\n\n"
                 .. "Vas a comprar: " .. (itemDef.nombre or "?") .. "\n\n"
                 .. "Pensalo bien. Confirmas?"
        local modal = ISModalDialog:new(0, 0, 380, 200, txt, true, self,
            HoldoorShopPanel.onConfirmComprar, 0, categoriaId, itemId)
        modal:initialise()
        modal:addToUIManager()
        local sw = getCore():getScreenWidth()
        local sh = getCore():getScreenHeight()
        modal:setX((sw - modal.width) / 2)
        modal:setY((sh - modal.height) / 2)
        return
    end

    HoldoorClient.comprar(categoriaId, itemId)
end

-- Callback del modal de confirmacion para traits/milagros.
function HoldoorShopPanel:onConfirmComprar(button, categoriaId, itemId)
    if button.internal == "YES" then
        HoldoorClient.comprar(categoriaId, itemId)
    end
end

function HoldoorShopPanel:onClose()
    -- Limpiar hijos dinamicos antes de eliminar el panel raiz
    self:_destruirFilas()
    self:setVisible(false)
    self:removeFromUIManager()
    HoldoorShop.instance = nil
end

function HoldoorShopPanel:onKeyPressed(key)
    if key == Keyboard.KEY_ESCAPE then self:onClose() end
end
