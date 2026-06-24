-- ============================================================
--  Holdoor -- Catalogo del Mercader Oscuro (sistema de VENTA)
--
--  Whitelist curada de items que el Mercader compra. Cada item:
--    { fullType = "Base.X", venta = { bronze=N, silver=N, gold=N } }
--  El NOMBRE mostrado en la UI sale del JUEGO (getItemNameFromFullType)
--  para que coincida exacto con lo que el jugador ve en su inventario.
--  Por eso NO guardamos nombre aca (se evita mantener 57 nombres a mano).
--
--  Robustez: si un fullType no existiera en el juego, getItemCountRecurse
--  devuelve 0 y el item NUNCA aparece en la lista -> sin crash (a diferencia
--  del drop pool, que SI da items; vender es READ-ONLY contra el inventario).
--
--  Economia (verificada en HoldoorShopCatalog.lua): 50 Bronce = 1 Plata,
--  30 Plata = 1 Oro  ->  1 Oro = 1500 Bronce.
--
--  Fee de venta (sink economico, plan clinico 2026-06-24):
--    fee = FEE_FIJO_BRONCE (siempre) + pctVolumen * brutoBronceEquiv (variable)
--    pctVolumen BAJA con la cantidad de unidades del carrito (descuento por lote):
--      1-4 u = 15% | 5-9 u = 13% | 10-19 u = 11% | 20+ u = 9%
--    El neto se paga en el split mas alto posible (Oro -> Plata -> Bronce).
--
--  MP-safe: el cliente lee/remueve SU propio inventario (autoritario en su
--  contexto, evita el bug de contextos de CoopHost), el server SOLO acredita
--  monedas. Ver holdoor_mod_design.md (idea madre 2026-06-23).
-- ============================================================

HoldoorVentaCatalog = HoldoorVentaCatalog or {}

-- Tasa de cambio (todo se normaliza a bronce-equivalente para el %)
HoldoorVentaCatalog.BRONCE_POR_PLATA = 50
HoldoorVentaCatalog.PLATA_POR_ORO    = 30
HoldoorVentaCatalog.BRONCE_POR_ORO   = 1500   -- 50 * 30

-- Fee fijo por transaccion (siempre, salvo carrito vacio)
HoldoorVentaCatalog.FEE_FIJO_BRONCE = 10

-- Descuento por volumen: pct variable segun unidades TOTALES del carrito.
-- Se evalua de arriba hacia abajo (mayor minUnidades primero).
HoldoorVentaCatalog.tiersVolumen = {
    { minUnidades = 20, pct = 0.09 },
    { minUnidades = 10, pct = 0.11 },
    { minUnidades = 5,  pct = 0.13 },
    { minUnidades = 1,  pct = 0.15 },
}

-- ════════════════════════════════════════════════════════════════
--  WHITELIST (agrupada por TIPO). Todos los fullType verificados contra
--  los scripts reales del juego (B42) -- cero IDs inventados.
--  Precios = lo que el Mercader PAGA (40-60% de compra en items que tambien
--  estan en la tienda; anti-arbitraje verificado).
-- ════════════════════════════════════════════════════════════════
HoldoorVentaCatalog.categorias = {
    {
        id = "medicinas", nombre = "Medicinas",
        items = {
            { fullType = "Base.Antibiotics",          venta = { bronze = 6 } },
            { fullType = "Base.SutureNeedleHolder",   venta = { bronze = 8 } },
            { fullType = "Base.SutureNeedle",         venta = { bronze = 5 } },
            { fullType = "Base.Disinfectant",         venta = { bronze = 4 } },
            { fullType = "Base.Bandage",              venta = { bronze = 1 } },
            { fullType = "Base.PillsBeta",            venta = { bronze = 3 } },
            { fullType = "Base.AlcoholedCottonBalls", venta = { bronze = 2 } },
            { fullType = "Base.Pills",                venta = { bronze = 2 } },
        },
    },
    {
        id = "comida", nombre = "Comida",
        items = {
            { fullType = "Base.CannedCornedBeef", venta = { bronze = 3 } },
            { fullType = "Base.CannedBolognese",  venta = { bronze = 2 } },
            { fullType = "Base.TunaTin",          venta = { bronze = 2 } },
            { fullType = "Base.TinnedBeans",      venta = { bronze = 1 } },
            { fullType = "Base.WaterRationCan",   venta = { bronze = 2 } },
            { fullType = "Base.Crisps",           venta = { bronze = 1 } },
            { fullType = "Base.Coffee2",          venta = { bronze = 1 } },
        },
    },
    {
        id = "melee", nombre = "Armas Melee",
        items = {
            { fullType = "Base.HuntingKnife", venta = { silver = 2 } },
            { fullType = "Base.BaseballBat",  venta = { silver = 14 } },
            { fullType = "Base.Machete",      venta = { gold = 1 } },
            { fullType = "Base.LargeKnife",   venta = { silver = 3 } },
            { fullType = "Base.HandAxe",      venta = { silver = 8 } },
            { fullType = "Base.Sword",        venta = { gold = 1 } },
        },
    },
    {
        id = "fuego", nombre = "Armas de Fuego",
        items = {
            { fullType = "Base.Pistol",            venta = { gold = 3 } },
            { fullType = "Base.Shotgun",           venta = { gold = 4 } },
            { fullType = "Base.HuntingRifle",      venta = { gold = 4 } },
            { fullType = "Base.ShotgunSawnoff",    venta = { gold = 2 } },
            { fullType = "Base.Bullets9mmCarton",  venta = { silver = 15 } },
            { fullType = "Base.ShotgunShellsBox",  venta = { silver = 12 } },
            { fullType = "Base.308Box",            venta = { silver = 12 } },
            { fullType = "Base.Bullets9mmBox",     venta = { bronze = 30 } },
        },
    },
    {
        id = "herramientas", nombre = "Herramientas",
        items = {
            { fullType = "Base.Sledgehammer", venta = { gold = 1 } },
            { fullType = "Base.WoodAxe",      venta = { silver = 5 } },
            { fullType = "Base.BlowTorch",    venta = { silver = 6 } },
            { fullType = "Base.Saw",          venta = { bronze = 18 } },
            { fullType = "Base.Hammer",       venta = { bronze = 15 } },
            { fullType = "Base.Shovel",       venta = { bronze = 14 } },
            { fullType = "Base.Screwdriver",  venta = { bronze = 8 } },
        },
    },
    {
        id = "ropa", nombre = "Ropa y Armadura",
        items = {
            { fullType = "Base.Vest_BulletSWAT",   venta = { gold = 1, silver = 2 } },
            { fullType = "Base.Vest_BulletPolice", venta = { gold = 1 } },
            { fullType = "Base.Hat_Fireman",       venta = { silver = 1 } },
            { fullType = "Base.Bag_ALICEpack",     venta = { gold = 3 } },
            { fullType = "Base.Bag_BigHikingBag",  venta = { gold = 1 } },
            { fullType = "Base.Shoes_ArmyBoots",   venta = { bronze = 30 } },
        },
    },
    {
        id = "componentes", nombre = "Componentes",
        items = {
            { fullType = "Base.Screws",          venta = { bronze = 3 } },
            { fullType = "Base.SheetMetal",      venta = { bronze = 7 } },
            { fullType = "Base.ElectronicsScrap", venta = { bronze = 4 } },
            { fullType = "Base.DuctTape",        venta = { bronze = 10 } },
            { fullType = "Base.PropaneTank",     venta = { silver = 1 } },
            { fullType = "Base.CarBattery2",     venta = { silver = 1 } },
            { fullType = "Base.WalkieTalkie5",   venta = { silver = 1 } },
        },
    },
    {
        id = "valiosos", nombre = "Valiosos",
        items = {
            { fullType = "Base.GoldBar",                    venta = { gold = 2 } },
            { fullType = "Base.Diamond",                    venta = { gold = 1 } },
            { fullType = "Base.SilverBar",                  venta = { gold = 1 } },
            { fullType = "Base.Ruby",                       venta = { silver = 20 } },
            { fullType = "Base.Goblet_Gold",                venta = { silver = 20 } },
            { fullType = "Base.Necklace_GoldDiamond",       venta = { silver = 20 } },
            { fullType = "Base.WristWatch_Right_Expensive", venta = { silver = 10 } },
            { fullType = "Base.Pocketwatch",                venta = { silver = 6 } },
        },
    },
}

-- ════════════════════════════════════════════════════════════════
--  INDEX por fullType -> { item, categoriaId }  (lookup O(1) en client/server)
--  Se construye al cargar el archivo (boot del juego).
-- ════════════════════════════════════════════════════════════════
HoldoorVentaCatalog.byFullType = {}
for _, cat in ipairs(HoldoorVentaCatalog.categorias) do
    for _, it in ipairs(cat.items or {}) do
        HoldoorVentaCatalog.byFullType[it.fullType] = { item = it, categoriaId = cat.id }
    end
end

-- Devuelve la tabla de precio de venta de un fullType, o nil si no es vendible.
function HoldoorVentaCatalog.ventaDe(fullType)
    local e = HoldoorVentaCatalog.byFullType[fullType]
    return e and e.item.venta or nil
end

-- True si el Mercader compra ese fullType.
function HoldoorVentaCatalog.esVendible(fullType)
    return HoldoorVentaCatalog.byFullType[fullType] ~= nil
end

-- Valor de una venta en bronce-equivalente.
function HoldoorVentaCatalog.valorBronceEquiv(venta)
    if not venta then return 0 end
    return (venta.bronze or 0)
        + (venta.silver or 0) * HoldoorVentaCatalog.BRONCE_POR_PLATA
        + (venta.gold   or 0) * HoldoorVentaCatalog.BRONCE_POR_ORO
end

-- Convierte un total en bronce-equiv al split mas alto posible {gold, silver, bronze}.
function HoldoorVentaCatalog.splitBronce(total)
    total = math.max(0, math.floor(total or 0))
    local oro    = math.floor(total / HoldoorVentaCatalog.BRONCE_POR_ORO)
    local resto  = total - oro * HoldoorVentaCatalog.BRONCE_POR_ORO
    local plata  = math.floor(resto / HoldoorVentaCatalog.BRONCE_POR_PLATA)
    local bronce = resto - plata * HoldoorVentaCatalog.BRONCE_POR_PLATA
    return { gold = oro, silver = plata, bronze = bronce }
end

-- pct variable segun unidades totales del carrito (descuento por volumen).
function HoldoorVentaCatalog.pctPorVolumen(unidades)
    unidades = unidades or 0
    for _, t in ipairs(HoldoorVentaCatalog.tiersVolumen) do
        if unidades >= t.minUnidades then return t.pct end
    end
    -- fallback: el tier mas bajo
    return HoldoorVentaCatalog.tiersVolumen[#HoldoorVentaCatalog.tiersVolumen].pct
end

-- Calcula el resultado de una venta. Pura: sirve tanto para el PREVIEW en vivo
-- de la UI como para acreditar al confirmar.
--   brutoBronce = suma del valor (bronce-equiv) de TODO lo vendido
--   unidades    = cantidad total de items del carrito (define el % por volumen)
-- Devuelve tabla completa con el desglose y el credito final en monedas.
function HoldoorVentaCatalog.calcularVenta(brutoBronce, unidades)
    brutoBronce = math.max(0, math.floor(brutoBronce or 0))
    unidades = unidades or 0
    local pct      = HoldoorVentaCatalog.pctPorVolumen(unidades)
    local feeFijo  = (brutoBronce > 0) and HoldoorVentaCatalog.FEE_FIJO_BRONCE or 0
    local feeVar   = math.ceil(brutoBronce * pct)
    local feeTotal = feeFijo + feeVar
    local neto     = math.max(0, brutoBronce - feeTotal)
    return {
        bruto    = brutoBronce,
        unidades = unidades,
        pct      = pct,
        feeFijo  = feeFijo,
        feeVar   = feeVar,
        feeTotal = feeTotal,
        neto     = neto,
        credito  = HoldoorVentaCatalog.splitBronce(neto),
    }
end

-- Label i18n de una sub-categoria (con FALLBACK al nombre ES del catalogo).
function HoldoorVentaCatalog.subtabLabel(cat)
    if not cat then return "" end
    local key = "UI_Holdoor_venta_subtab_" .. tostring(cat.id)
    local v = getText(key)
    if v ~= key then return v end
    return cat.nombre or cat.id
end

-- String legible de un precio de venta. Reusa labelOf de la tienda para la
-- i18n de las monedas (Bronce/Plata/Oro). Orden: bronce -> plata -> oro.
function HoldoorVentaCatalog.precioStr(venta)
    if not venta then return "" end
    local parts = {}
    for _, k in ipairs(HoldoorShopCatalog.monedasOrden) do
        if (venta[k] or 0) > 0 then
            table.insert(parts, venta[k] .. " " .. HoldoorShopCatalog.labelOf(k))
        end
    end
    return table.concat(parts, " + ")
end

-- ════════════════════════════════════════════════════════════════
--  SCAN DE VENDIBLES (anti-footgun): recorre TODO el inventario del jugador
--  incluyendo mochilas anidadas (sueltas o PUESTAS), pero EXCLUYE lo que esta
--  equipado: arma/item en la mano (primaria/secundaria) y ropa/armadura PUESTA.
--  Asi nunca se vende sin querer la katana en mano ni el casco puesto.
--  El contenido DE las mochilas (incluida la puesta) SI es vendible.
--
--  Devuelve un mapa { [fullType] = { InventoryItem, ... } } SOLO de fullTypes
--  de la whitelist. Un solo barrido (lo usan tanto el conteo de la UI como la
--  remocion del cliente, mismo criterio -> sin desincronizacion).
--
--  APIs verificadas en el codigo del juego B42:
--    getInventory():getItems():size()/get(i)  (FireFighting.lua:79-80)
--    item:getFullType()                        (forageSystem.lua:2354)
--    player:getPrimaryHandItem()/getSecondaryHandItem()  (OnBreak.lua:21-22, ref-equality)
--    player:isEquippedClothing(item)           (ISTakeWaterAction.lua:187)
--    item:isEquipped()                         (red de seguridad: true para mano O ropa)
--    item:getInventory()                       (container anidado o nil)
-- ════════════════════════════════════════════════════════════════
function HoldoorVentaCatalog.scanVendibles(p)
    local res = {}
    if not p then return res end
    local prim, scnd
    pcall(function() prim = p:getPrimaryHandItem() end)
    pcall(function() scnd = p:getSecondaryHandItem() end)

    local function estaEquipado(it)
        if it == prim or it == scnd then return true end
        local worn = false
        pcall(function() worn = p:isEquippedClothing(it) end)
        if worn then return true end
        local eq = false
        pcall(function() eq = it:isEquipped() end)   -- red de seguridad (mano O ropa)
        return eq
    end

    local function scan(container)
        if not container then return end
        local items = nil
        pcall(function() items = container:getItems() end)
        if not items then return end
        local n = 0
        pcall(function() n = items:size() end)
        for i = 0, n - 1 do
            local it = nil
            pcall(function() it = items:get(i) end)
            if it then
                local ft = nil
                pcall(function() ft = it:getFullType() end)
                if ft and HoldoorVentaCatalog.byFullType[ft] and not estaEquipado(it) then
                    res[ft] = res[ft] or {}
                    table.insert(res[ft], it)
                end
                -- Descender al contenido de la mochila (suelta o puesta). OJO:
                -- getInventory() SOLO existe en items-contenedor (InventoryContainer);
                -- llamarlo en un item normal tira "attempt to call nil" (atrapado por
                -- pcall pero PZ lo loguea y suma al contador de errores). Por eso el
                -- guard instanceof ANTES de llamar. (ISCampingMenu.lua:36, ISBuildUtil.lua:111)
                if instanceof(it, "InventoryContainer") then
                    local sub = nil
                    pcall(function() sub = it:getInventory() end)
                    if sub then scan(sub) end
                end
            end
        end
    end

    pcall(function() scan(p:getInventory()) end)
    return res
end

-- ════════════════════════════════════════════════════════════════
--  RESOLVER ITEMS POR ID (server-side autoritario).
--  El cliente eligio QUE vender (instancias NO equipadas, via scanVendibles) y
--  manda sus IDs. El SERVER re-resuelve esos IDs contra SU inventario autoritario
--  (recursivo, incluye mochilas) — patron vanilla getItemById(it:getID()) — para
--  remover las instancias EXACTAS (sin tocar equipados) en el contexto que SI
--  persiste en CoopHost. idSet = { [id]=true }. Devuelve lista de { item, cont }
--  capturando el CONTENEDOR real donde vive cada item (asi no dependemos de
--  it:getContainer() para items dentro de mochilas anidadas).
-- ════════════════════════════════════════════════════════════════
function HoldoorVentaCatalog.resolverPorId(p, idSet)
    local out = {}
    if not p or not idSet then return out end
    local function scan(container)
        if not container then return end
        local items = nil
        pcall(function() items = container:getItems() end)
        if not items then return end
        local n = 0
        pcall(function() n = items:size() end)
        for i = 0, n - 1 do
            local it = nil
            pcall(function() it = items:get(i) end)
            if it then
                local id = nil
                pcall(function() id = it:getID() end)
                if id and idSet[id] then table.insert(out, { item = it, cont = container }) end
                if instanceof(it, "InventoryContainer") then
                    local sub = nil
                    pcall(function() sub = it:getInventory() end)
                    if sub then scan(sub) end
                end
            end
        end
    end
    pcall(function() scan(p:getInventory()) end)
    return out
end

-- ════════════════════════════════════════════════════════════════
--  AUTO-MERGE: TODO lo que se COMPRA en la tienda tambien se VENDE.
--  Precio de venta = PCT_REVENTA_TIENDA (40%) del valor en MONEDAS del precio
--  de compra (los materiales raros NO se reembolsan). Si el item ya estaba en
--  la whitelist (loot + tienda), se SOBREESCRIBE su precio al 40% para que la
--  regla sea uniforme. Los items solo-loot (no estan en la tienda) quedan
--  intactos con su precio curado a mano.
--  Idempotente (flag _shopMerged + check byFullType). Se llama al cargar y,
--  defensivo, desde la UI por si el orden de carga shared dejara la tienda sin
--  cargar al momento de este archivo.
-- ════════════════════════════════════════════════════════════════
HoldoorVentaCatalog.PCT_REVENTA_TIENDA = 0.40
HoldoorVentaCatalog._shopMerged = false

-- Mapeo sub-categoria de la TIENDA -> tipo (sub-tab) de la VENTA.
local SHOP_SUBCAT_A_TIPO = {
    medico   = "medicinas",
    comida   = "comida",
    bebidas  = "comida",
    melee    = "melee",
    firearms = "fuego",
    casual   = "ropa",
    policia  = "ropa",
    bombero  = "ropa",
    militar  = "ropa",
    comunes  = "componentes",
}
-- Para categorias de la tienda con items DIRECTOS (sin sub-categorias).
local SHOP_CAT_A_TIPO = {
    bolsos = "ropa",
}

function HoldoorVentaCatalog.mergeShopItems()
    if HoldoorVentaCatalog._shopMerged then return end
    if not (HoldoorShopCatalog and HoldoorShopCatalog.categorias) then return end

    local catPorId = {}
    for _, c in ipairs(HoldoorVentaCatalog.categorias) do catPorId[c.id] = c end

    -- Valor en MONEDAS del precio de compra (ignora materiales: no se reembolsan).
    local function valorMonedas(precio)
        if not precio then return 0 end
        return (precio.bronze or 0)
            + (precio.silver or 0) * HoldoorVentaCatalog.BRONCE_POR_PLATA
            + (precio.gold   or 0) * HoldoorVentaCatalog.BRONCE_POR_ORO
    end

    local function addOrUpdate(fullType, precio, tipoVenta)
        if not fullType then return end
        local bruto = valorMonedas(precio)
        if bruto <= 0 then return end
        local ventaBronce = math.max(1, math.floor(bruto * HoldoorVentaCatalog.PCT_REVENTA_TIENDA + 0.5))
        local venta = HoldoorVentaCatalog.splitBronce(ventaBronce)
        local existing = HoldoorVentaCatalog.byFullType[fullType]
        if existing then
            -- Ya listado (loot + tienda): uniformar el precio al 40%.
            existing.item.venta = venta
        else
            local destino = catPorId[tipoVenta]
            if not destino then return end
            local it = { fullType = fullType, venta = venta, _fromShop = true }
            table.insert(destino.items, it)
            HoldoorVentaCatalog.byFullType[fullType] = { item = it, categoriaId = destino.id }
        end
    end

    for _, cat in ipairs(HoldoorShopCatalog.categorias) do
        local tipoDirecto = SHOP_CAT_A_TIPO[cat.id]
        if tipoDirecto then
            for _, it in ipairs(cat.items or {}) do
                if it.accion and it.accion.tipo == "item" then
                    addOrUpdate(it.accion.item, it.precio, tipoDirecto)
                end
            end
        end
        for _, sub in ipairs(cat.subcategorias or {}) do
            local tipoSub = SHOP_SUBCAT_A_TIPO[sub.id]
            if tipoSub then
                for _, it in ipairs(sub.items or {}) do
                    if it.accion and it.accion.tipo == "item" then
                        addOrUpdate(it.accion.item, it.precio, tipoSub)
                    end
                end
            end
        end
    end

    HoldoorVentaCatalog._shopMerged = true
end

-- Intento al cargar (la tienda suele cargar antes: "Shop" < "Venta" alfabetico).
HoldoorVentaCatalog.mergeShopItems()
