-- ============================================================
--  Holdoor -- Catalogo de la Tienda
--
--  precio (todas las claves opcionales, solo entran las que tienen valor > 0):
--    Monedas:   { bronze, silver, gold }
--    Materiales: { cuero, hierro, acero, valyrio, obsidiana }
--
--  Accion tipos:
--    { tipo="item",     item="Base.X" }                  -> 1 item al inventario
--    { tipo="package",  items={"Base.X","Base.Y"} }      -> varios items
--    { tipo="xp",       perk="Aiming", amount=500 }      -> XP en un skill
--    { tipo="restore",  stats={"hunger","thirst",...} }  -> rellena stats
--    { tipo="cure_bite" }                                -> cura mordida zombi
--    { tipo="material", key="Holdoor_Cuero", amount=1 }  -> +N en contador de material
-- ============================================================

HoldoorShopCatalog = HoldoorShopCatalog or {}

-- Mapeo precio key -> ModData key (centralizado para reuso server/client)
HoldoorShopCatalog.mdKeyMap = {
    bronze    = "Holdoor_Bronze",
    silver    = "Holdoor_Silver",
    gold      = "Holdoor_Gold",
    cuero     = "Holdoor_Cuero",
    hierro    = "Holdoor_Hierro",
    acero     = "Holdoor_Acero",
    valyrio   = "Holdoor_Valyrio",
    obsidiana = "Holdoor_Obsidiana",
}

-- Etiquetas humanas para mostrar
HoldoorShopCatalog.labels = {
    bronze    = "Bronce",
    silver    = "Plata",
    gold      = "Oro",
    cuero     = "Cuero",
    hierro    = "Hierro",
    acero     = "Acero",
    valyrio   = "Valyrio",
    obsidiana = "Obsidiana",
}

-- Orden de display (en precio y en saldo header)
HoldoorShopCatalog.monedasOrden    = { "bronze", "silver", "gold" }
HoldoorShopCatalog.materialesOrden = { "cuero", "hierro", "acero", "valyrio", "obsidiana" }

HoldoorShopCatalog.categorias = {
    {
        id     = "consumibles",
        nombre = "Consumibles",
        cr=0.35, cg=0.85, cb=0.45,
        items = {
            { id="bandage",     nombre="Vendajes del Maestre",  desc="Detiene el sangrado.",
              precio={bronze=5},   accion={tipo="item", item="Base.Bandage"} },
            { id="painkillers", nombre="Polvo del Sueño",        desc="Reduce el dolor severamente.",
              precio={bronze=8},   accion={tipo="item", item="Base.Pills"} },
            { id="antibiotics", nombre="Hierba del Maestre",      desc="Combate infecciones (no zombi).",
              precio={bronze=15},  accion={tipo="item", item="Base.Antibiotics"} },
            { id="rancion",     nombre="Racion de la Guardia",    desc="Sandwich + agua llena.",
              precio={bronze=20},  accion={tipo="package", items={"Base.Sandwich","Base.WaterBottleFull"}} },
        },
    },
    {
        id     = "armas",
        nombre = "Armas",
        cr=0.95, cg=0.45, cb=0.20,
        items = {
            { id="machete", nombre="Machete del Vagabundo",   desc="Cuerpo a cuerpo, alto daño.",
              precio={bronze=20, hierro=1},        accion={tipo="item", item="Base.Machete"} },
            { id="axe",     nombre="Hacha del Pueblo Libre",  desc="Hacha pesada de doble filo.",
              precio={silver=1, hierro=1},         accion={tipo="item", item="Base.Axe"} },
            { id="katana",  nombre="Espada Larga del Norte",  desc="Hoja legendaria forjada en Valyrio.",
              precio={silver=3, valyrio=1},        accion={tipo="item", item="Base.Katana"} },
        },
    },
    {
        id     = "armadura",
        nombre = "Armadura",
        cr=0.55, cg=0.75, cb=0.95,
        items = {
            { id="gloves", nombre="Guantes del Cuervo",         desc="Cuero curtido, mano dura.",
              precio={bronze=15, cuero=1},         accion={tipo="item", item="Base.Gloves_LeatherGloves"} },
            { id="helm",   nombre="Casco del Vigilante Nocturno", desc="Acero del Norte sobre la frente.",
              precio={silver=1, acero=1},          accion={tipo="item", item="Base.Hat_ArmyHelmet"} },
            { id="vest",   nombre="Chaleco del Muro",           desc="Armadura anti-mordida del Muro.",
              precio={silver=2, acero=2},          accion={tipo="item", item="Base.Vest_BulletKevlar"} },
        },
    },
    {
        id     = "habilidades",
        nombre = "Habilidades",
        cr=0.85, cg=0.55, cb=0.95,
        items = {
            { id="xp_aim",   nombre="Leccion del Maestro de Armas", desc="+500 XP en Aiming.",
              precio={silver=2},   accion={tipo="xp", perk="Aiming", amount=500} },
            { id="xp_str",   nombre="Doctrina de los Umber",        desc="+500 XP en Strength.",
              precio={silver=2},   accion={tipo="xp", perk="Strength", amount=500} },
            { id="xp_fit",   nombre="Sangre de los Primeros Hombres", desc="+500 XP en Fitness.",
              precio={silver=3},   accion={tipo="xp", perk="Fitness", amount=500} },
            { id="xp_blade", nombre="Senda del Acero Valyrio",        desc="+1000 XP en Long Blade.",
              precio={gold=1},     accion={tipo="xp", perk="LongBlade", amount=1000} },
        },
    },
    {
        id     = "lujos",
        nombre = "Lujos",
        cr=1.0, cg=0.85, cb=0.30,
        items = {
            { id="banquete", nombre="Festin de Invernalia",     desc="Rellena hambre, sed y descanso.",
              precio={silver=3},                  accion={tipo="restore", stats={"hunger","thirst","fatigue","stress"}} },
            { id="cure",     nombre="Magia de Asshai",           desc="Cura una mordida zombi.",
              precio={gold=1, obsidiana=1},       accion={tipo="cure_bite"} },
        },
    },
    {
        id     = "materiales",
        nombre = "Materiales",
        cr=0.85, cg=0.65, cb=0.40,
        items = {
            { id="m_cuero",   nombre="Cuero Curtido",       desc="Para guantes y armaduras ligeras.",
              precio={bronze=10},  accion={tipo="material", key="Holdoor_Cuero",     amount=1} },
            { id="m_hierro",  nombre="Hierro del Norte",     desc="Forjado en herrerias del Norte.",
              precio={bronze=25},  accion={tipo="material", key="Holdoor_Hierro",    amount=1} },
            { id="m_acero",   nombre="Acero Castellano",     desc="Acero refinado, para armaduras de elite.",
              precio={silver=1},   accion={tipo="material", key="Holdoor_Acero",     amount=1} },
            { id="m_valyrio", nombre="Acero Valyrio",        desc="Forjado con fuego de dragones. Irrepetible.",
              precio={gold=1},     accion={tipo="material", key="Holdoor_Valyrio",   amount=1} },
            { id="m_obsid",   nombre="Vidrio de Dragon",     desc="La sustancia que cura toda mordida.",
              precio={gold=1},     accion={tipo="material", key="Holdoor_Obsidiana", amount=1} },
        },
    },
}

-- Construye string de precio formateado en el orden monedas + materiales
function HoldoorShopCatalog.precioStr(precio)
    if not precio then return "" end
    local parts = {}
    for _, k in ipairs(HoldoorShopCatalog.monedasOrden) do
        if (precio[k] or 0) > 0 then
            table.insert(parts, precio[k] .. " " .. HoldoorShopCatalog.labels[k])
        end
    end
    for _, k in ipairs(HoldoorShopCatalog.materialesOrden) do
        if (precio[k] or 0) > 0 then
            table.insert(parts, precio[k] .. " " .. HoldoorShopCatalog.labels[k])
        end
    end
    return table.concat(parts, " + ")
end

-- Busca un item del catalogo por categoria y id
function HoldoorShopCatalog.buscar(categoriaId, itemId)
    for _, cat in ipairs(HoldoorShopCatalog.categorias) do
        if cat.id == categoriaId then
            for _, it in ipairs(cat.items) do
                if it.id == itemId then return it end
            end
        end
    end
    return nil
end
