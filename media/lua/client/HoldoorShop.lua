-- ============================================================
--  Holdoor -- Tienda (modal)
--  Catalogo en HoldoorShopCatalog (shared). Compras via cliente -> server.
-- ============================================================

require "HoldoorShopCatalog"
require "HoldoorClient"

HoldoorShop = HoldoorShop or {}
HoldoorShop.instance = nil

local SHOP_W = 720
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
local COLOR_BRONCE     = { r=0.85, g=0.55, b=0.30, a=1    }
local COLOR_PLATA      = { r=0.80, g=0.85, b=0.95, a=1    }
local COLOR_ORO        = { r=0.95, g=0.78, b=0.20, a=1    }

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
    o.filasItems      = {}  -- guarda referencias a las filas para destruirlas al cambiar de cat
    return o
end

function HoldoorShopPanel:initialise()
    ISPanel.initialise(self)
    self:_crearContenido()
end

function HoldoorShopPanel:_crearContenido()
    local pad = PAD

    -- Header: titulo + saldo + close
    self.lblTit = ISLabel:new(pad, 12, 24, "TIENDA HOLDOOR", 0.95, 0.78, 0.30, 1, UIFont.Medium, true)
    self:addChild(self.lblTit)

    self.lblSaldo = ISLabel:new(SHOP_W - 380, 14, 16, "", 1, 1, 1, 1, UIFont.Small, true)
    self:addChild(self.lblSaldo)

    self.lblMateriales = ISLabel:new(SHOP_W - 380, 38, 14, "", 0.85, 0.75, 0.45, 1, UIFont.Small, true)
    self:addChild(self.lblMateriales)

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
end

function HoldoorShopPanel:_refrescarSaldo()
    if self.lblSaldo then
        local b, s, g = HoldoorClient.getSaldo()
        self.lblSaldo:setName("Saldo:  " .. b .. " Bronce   " .. s .. " Plata   " .. g .. " Oro")
    end
    if self.lblMateriales and HoldoorClient.getMateriales then
        local m = HoldoorClient.getMateriales()
        self.lblMateriales:setName(
            "Materiales:  " .. m.cuero .. " Cuero   " .. m.hierro .. " Hierro   " ..
            m.acero .. " Acero   " .. m.valyrio .. " Valyrio   " .. m.obsidiana .. " Obsidiana"
        )
    end
end

function HoldoorShopPanel:onSelectCat(button)
    self.categoriaActual = button.holdoorCatIdx
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

    for _, item in ipairs(cat.items) do
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

        local lblP = ISLabel:new(areaX, areaY + 44, 14, precioTxt,
            precioColor.r, precioColor.g, precioColor.b, 1, UIFont.Small, true)
        self:addChild(lblP); table.insert(hijos, lblP)

        -- Validar si puede pagar: monedas + materiales
        local puede = (saldoB >= (item.precio.bronze or 0))
                  and (saldoS >= (item.precio.silver or 0))
                  and (saldoG >= (item.precio.gold   or 0))
                  and (mats.cuero     >= (item.precio.cuero     or 0))
                  and (mats.hierro    >= (item.precio.hierro    or 0))
                  and (mats.acero     >= (item.precio.acero     or 0))
                  and (mats.valyrio   >= (item.precio.valyrio   or 0))
                  and (mats.obsidiana >= (item.precio.obsidiana or 0))

        local btn = ISButton:new(SHOP_W - PAD - 110, areaY + 16, 105, 30,
            puede and "COMPRAR" or "Sin saldo",
            self, puede and HoldoorShopPanel.onComprar or HoldoorShopPanel.doNothing)
        btn.holdoorItem = { categoriaId = cat.id, itemId = item.id }
        btn.backgroundColor = puede and COLOR_BTN_OK_S or COLOR_BTN_DIS_S
        btn.borderColor     = puede and { r=0.4, g=0.75, b=0.4, a=1 } or { r=0.3, g=0.3, b=0.3, a=1 }
        if not puede then btn.textColor = { r=0.55, g=0.55, b=0.5, a=1 } end
        self:addChild(btn); table.insert(hijos, btn)

        table.insert(self.filasItems, { _hijos = hijos })
        areaY = areaY + ROW_H
    end
end

function HoldoorShopPanel:doNothing() end

function HoldoorShopPanel:onComprar(button)
    if not button.holdoorItem then return end
    HoldoorClient.comprar(button.holdoorItem.categoriaId, button.holdoorItem.itemId)
    -- La respuesta del server llamara a HoldoorShop.refrescar() que vuelve a pintar las filas con el nuevo saldo
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
