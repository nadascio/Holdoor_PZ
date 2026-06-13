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
            -- ════════════ MEDICO ════════════
            -- Tier 1: items individuales baratos (de bolsillo)
            { id="bandage",       nombre="Vendaje del Maestre",     desc="Detiene el sangrado.",
              precio={bronze=3},                    accion={tipo="item", item="Base.Bandage"} },
            { id="venda_steril",  nombre="Venda Esterilizada",       desc="Vendaje desinfectado. Cura mas rapido.",
              precio={bronze=6},                    accion={tipo="item", item="Base.AlcoholBandage"} },
            { id="painkillers",   nombre="Polvo del Sueno",          desc="Analgesico. Reduce el dolor.",
              precio={bronze=4},                    accion={tipo="item", item="Base.Pills"} },
            { id="antibiotics",   nombre="Hierba del Maestre",       desc="Antibiotico. Combate infecciones (no zombi).",
              precio={bronze=8},                    accion={tipo="item", item="Base.Antibiotics"} },
            { id="algodon",       nombre="Algodon con Alcohol",      desc="Desinfecta heridas.",
              precio={bronze=5},                    accion={tipo="item", item="Base.AlcoholedCottonBalls"} },
            -- Tier 2: packs medianos (mejor relacion precio/cantidad)
            { id="polvo3",        nombre="Polvo del Sueno Profundo", desc="3 dosis de Pastillas.",
              precio={bronze=10},                   accion={tipo="package", items={"Base.Pills","Base.Pills","Base.Pills"}} },
            { id="vendas5",       nombre="Rollo de Vendas",          desc="5 Vendajes basicos.",
              precio={bronze=12},                   accion={tipo="package", items={"Base.Bandage","Base.Bandage","Base.Bandage","Base.Bandage","Base.Bandage"}} },
            { id="hoja_cuervo",   nombre="Hoja del Cuervo",          desc="2x Antibiotico + 2x Venda esterilizada. Cura emergencia.",
              precio={bronze=25},                   accion={tipo="package", items={"Base.Antibiotics","Base.Antibiotics","Base.AlcoholBandage","Base.AlcoholBandage"}} },
            -- Tier 3: kit grande (inversion para preparacion)
            { id="botiquin",      nombre="Botiquin del Septon",      desc="3x Vendas esterilizadas + 3x Antibioticos + 3x Pastillas + 2x Algodon con alcohol.",
              precio={silver=1, hierro=1},          accion={tipo="package", items={"Base.AlcoholBandage","Base.AlcoholBandage","Base.AlcoholBandage","Base.Antibiotics","Base.Antibiotics","Base.Antibiotics","Base.Pills","Base.Pills","Base.Pills","Base.AlcoholedCottonBalls","Base.AlcoholedCottonBalls"}} },
            -- ════════════ COMIDA / BEBIDA ════════════
            -- Tier 1: items individuales
            { id="sandwich",      nombre="Sandwich del Norte",       desc="Llena el hambre.",
              precio={bronze=6},                    accion={tipo="item", item="Base.Sandwich"} },
            { id="estofado",      nombre="Estofado del Norte",       desc="Sopa nutritiva.",
              precio={bronze=8},                    accion={tipo="item", item="Base.TinnedSoup"} },
            { id="vino_dominio",  nombre="Vino del Dominio",         desc="Reduce sed, sube animo.",
              precio={bronze=10},                   accion={tipo="item", item="Base.WineBottle"} },
            -- Tier 2: packs medianos
            { id="rancion",       nombre="Racion de la Guardia",     desc="Sandwich + Estofado + Vino.",
              precio={bronze=20},                   accion={tipo="package", items={"Base.Sandwich","Base.TinnedSoup","Base.WineBottle"}} },
            { id="racion_cuervo", nombre="Racion del Cuervo",        desc="3x Sandwich + 2x Vino. Para la tropa.",
              precio={bronze=30},                   accion={tipo="package", items={"Base.Sandwich","Base.Sandwich","Base.Sandwich","Base.WineBottle","Base.WineBottle"}} },
            -- Tier 3: kit grande
            { id="kit_comida_3d", nombre="Provisiones de 3 Dias",    desc="2x Sandwich + Sopa + Steak + 2x Vino. Te dura.",
              precio={bronze=55},                   accion={tipo="package", items={"Base.Sandwich","Base.Sandwich","Base.TinnedSoup","Base.Steak","Base.WineBottle","Base.WineBottle"}} },
        },
    },
    {
        id     = "armas",
        nombre = "Armas",
        cr=0.95, cg=0.45, cb=0.20,
        items = {
            { id="machete", nombre="Machete del Vagabundo",   desc="Cuerpo a cuerpo, alto dano.",
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
            { id="helm",   nombre="Casco del Vigilante Nocturno", desc="Casco protector de cabeza.",
              precio={silver=1, acero=1},          accion={tipo="item", item="Base.Hat_Hardhat"} },
            { id="vest",   nombre="Chaleco del Muro",           desc="Armadura ligera anti-mordida.",
              precio={silver=2, acero=2},          accion={tipo="item", item="Base.Vest_HighVis_Blue"} },
        },
    },
    {
        id     = "habilidades",
        nombre = "Libros de Guerra",
        cr=0.85, cg=0.55, cb=0.95,
        items = {
            -- TIER MEDIO ("lite") — 250 XP, 80 bronces, accesibles
            { id="xp_lite_aim",    nombre="Practica del Arquero",          desc="+250 XP en Aiming.",
              precio={bronze=80, hierro=1},        accion={tipo="xp", perk="Aiming",     amount=250} },
            { id="xp_lite_str",   nombre="Entrenamiento del Herrero",     desc="+250 XP en Strength.",
              precio={bronze=80, hierro=1},        accion={tipo="xp", perk="Strength",   amount=250} },
            { id="xp_lite_fit",   nombre="Carrera del Mensajero",         desc="+250 XP en Fitness.",
              precio={bronze=80, hierro=1},        accion={tipo="xp", perk="Fitness",    amount=250} },
            { id="xp_lite_blade", nombre="Manejo Basico del Filo",        desc="+250 XP en Long Blade.",
              precio={bronze=80, hierro=1},        accion={tipo="xp", perk="LongBlade",  amount=250} },
            { id="xp_lite_axe",   nombre="Lecciones del Lenador",         desc="+250 XP en Axe.",
              precio={bronze=80, hierro=1},        accion={tipo="xp", perk="Axe",        amount=250} },
            -- TIER FULL — 500 XP, plata + hierro
            { id="xp_aim",       nombre="Leccion del Maestro de Armas",   desc="+500 XP en Aiming.",
              precio={silver=1, hierro=2},         accion={tipo="xp", perk="Aiming",      amount=500} },
            { id="xp_str",       nombre="Doctrina de los Umber",          desc="+500 XP en Strength.",
              precio={silver=1, hierro=2},         accion={tipo="xp", perk="Strength",    amount=500} },
            { id="xp_fit",       nombre="Sangre de los Primeros Hombres", desc="+500 XP en Fitness.",
              precio={silver=1, hierro=2},         accion={tipo="xp", perk="Fitness",     amount=500} },
            { id="xp_blade",     nombre="Tratado de la Espada Larga",     desc="+500 XP en Long Blade.",
              precio={silver=1, hierro=2},         accion={tipo="xp", perk="LongBlade",   amount=500} },
            { id="xp_axe",       nombre="Manual del Hacha de Guerra",     desc="+500 XP en Axe.",
              precio={silver=1, hierro=2},         accion={tipo="xp", perk="Axe",         amount=500} },
            { id="xp_short",     nombre="Arte de la Hoja Corta",          desc="+500 XP en Short Blade.",
              precio={silver=1, hierro=2},         accion={tipo="xp", perk="ShortBlade",  amount=500} },
            { id="xp_spear",     nombre="Cronicas de la Lanza",           desc="+500 XP en Spear.",
              precio={silver=1, hierro=2},         accion={tipo="xp", perk="Spear",       amount=500} },
            { id="xp_reload",    nombre="Recargar bajo Asedio",           desc="+500 XP en Reloading.",
              precio={silver=1, hierro=2},         accion={tipo="xp", perk="Reloading",   amount=500} },
            { id="xp_maint",     nombre="Doctrina del Acero",             desc="+500 XP en Maintenance.",
              precio={silver=1, hierro=2},         accion={tipo="xp", perk="Maintenance", amount=500} },
            -- LEGENDARIO — 1000 XP, oro
            { id="xp_blade_leg", nombre="Senda del Acero Valyrio",        desc="+1000 XP en Long Blade.",
              precio={gold=1, valyrio=1},          accion={tipo="xp", perk="LongBlade",   amount=1000} },
        },
    },
    {
        id     = "rasgos",
        nombre = "Rasgos Heroicos",
        cr=0.95, cg=0.85, cb=0.35,
        items = {
            -- MAXIMO 1 POR VIDA del personaje
            { id="trait_strong",   nombre="Bendicion del Gigante",   desc="Da el rasgo STRONG (+fuerza+dano). 1 por vida.",
              precio={gold=3, valyrio=2, acero=5},  accion={tipo="trait", trait="Strong"} },
            { id="trait_athletic", nombre="Sangre del Martir",       desc="Da el rasgo ATHLETIC (+stamina). 1 por vida.",
              precio={gold=3, valyrio=2, acero=3},  accion={tipo="trait", trait="Athletic"} },
            { id="trait_brave",    nombre="Espiritu Indomable",      desc="Da el rasgo BRAVE (resistencia al panico). 1 por vida.",
              precio={gold=2, valyrio=1, hierro=4}, accion={tipo="trait", trait="Brave"} },
            { id="trait_eagle",    nombre="Ojo de Halcon",           desc="Da el rasgo EAGLE EYED (+vision). 1 por vida.",
              precio={gold=2, valyrio=1, hierro=3}, accion={tipo="trait", trait="EagleEyed"} },
            { id="trait_cats",     nombre="Vista de Gato Salvaje",   desc="Da el rasgo CATS EYES (mejor vision nocturna). 1 por vida.",
              precio={gold=1, acero=3, hierro=5},   accion={tipo="trait", trait="CatsEyes"} },
            { id="trait_irongut",  nombre="Tripa de Hierro",         desc="Da el rasgo IRON GUT (digestion mejorada). 1 por vida.",
              precio={gold=1, acero=2, hierro=5},   accion={tipo="trait", trait="IronGut"} },
        },
    },
    {
        id     = "milagros",
        nombre = "Milagros del Maestre",
        cr=0.95, cg=0.45, cb=0.95,
        items = {
            -- MAXIMO 1 POR VIDA del personaje. Solo se compra si el player TIENE ese trait.
            { id="cura_weak",     nombre="Elixir del Vigor",        desc="Cura el rasgo WEAK. 1 por vida.",
              precio={gold=3, valyrio=2},           accion={tipo="cura_trait", trait="Weak"} },
            { id="cura_obese",    nombre="Cura de los Siete",       desc="Cura el rasgo OBESE. 1 por vida.",
              precio={gold=2, acero=3, hierro=8},   accion={tipo="cura_trait", trait="Obese"} },
            { id="cura_smoker",   nombre="Aliento del Druida",      desc="Cura el rasgo SMOKER. 1 por vida.",
              precio={gold=1, acero=5},             accion={tipo="cura_trait", trait="Smoker"} },
            { id="cura_outshape", nombre="Camino del Guerrero",     desc="Cura el rasgo OUT OF SHAPE. 1 por vida.",
              precio={gold=2, valyrio=1},           accion={tipo="cura_trait", trait="OutOfShape"} },
            { id="cura_thinskin", nombre="Piel del Dragon",         desc="Cura el rasgo THIN-SKINNED. 1 por vida.",
              precio={gold=2, valyrio=2},           accion={tipo="cura_trait", trait="ThinSkinned"} },
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
