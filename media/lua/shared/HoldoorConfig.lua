-- ============================================================
--  Holdoor -- Sistema de Oleadas  |  Configuracion compartida
-- ============================================================

HoldoorConfig = HoldoorConfig or {}

-- ─── MODOS DE JUEGO ─────────────────────────────────────────
HoldoorConfig.modos = {
    {
        id               = "facil",
        nombre           = "FACIL",
        maxOleadas       = 5,
        tamanoOleada     = 15,
        escalaPorOleada  = 0.10,
        srPorOleada      = 0.05,
        intervalSegundos = 75,
        radioSpawn       = 30,
        tamanoTanda      = 10,
        tandaIntervalSec = 10,
        descripcion      = "Los muertos aun aprenden a caminar.",
        lore             = "Una prueba para los que recien toman las armas. La noche es larga, pero no interminable.",
        detalle          = "15 base | +10%/oleada | 5% SR | 75s | 5 oleadas",
        cr = 0.30, cg = 0.90, cb = 0.30,
    },
    {
        id               = "normal",
        nombre           = "NORMAL",
        maxOleadas       = 8,
        tamanoOleada     = 25,
        escalaPorOleada  = 0.12,
        srPorOleada      = 0.10,
        intervalSegundos = 60,
        radioSpawn       = 25,
        tamanoTanda      = 12,
        tandaIntervalSec = 8,
        descripcion      = "La horda crece. Los corredores llegan primero.",
        lore             = "Aqui comienza el verdadero desafio. Los que sobreviven la primera noche descubren que la segunda es peor.",
        detalle          = "25 base | +12%/oleada | 10% SR | 60s | 8 oleadas",
        cr = 0.90, cg = 0.80, cb = 0.20,
    },
    {
        id               = "dificil",
        nombre           = "DIFICIL",
        maxOleadas       = 10,
        tamanoOleada     = 35,
        escalaPorOleada  = 0.15,
        srPorOleada      = 0.12,
        intervalSegundos = 45,
        radioSpawn       = 22,
        tamanoTanda      = 12,
        tandaIntervalSec = 6,
        descripcion      = "El Rey de la Noche avanza. No hay misericordia.",
        lore             = "Solo los mejores llegan a la decima oleada. Aqui no hay lugar para la duda.",
        detalle          = "35 base | +15%/oleada | 12% SR | 45s | 10 oleadas",
        cr = 1.00, cg = 0.50, cb = 0.10,
    },
    {
        id               = "pesadilla",
        nombre           = "PESADILLA",
        maxOleadas       = 12,
        tamanoOleada     = 50,
        escalaPorOleada  = 0.20,
        srPorOleada      = 0.15,
        intervalSegundos = 25,
        radioSpawn       = 20,
        tamanoTanda      = 15,
        tandaIntervalSec = 5,
        descripcion      = "No existe misericordia mas alla del Muro.",
        lore             = "La mitad de tus enemigos corren. Completar esto es un titulo que pocos ostentan.",
        detalle          = "50 base | +20%/oleada | 15% SR | 25s | 12 oleadas",
        cr = 1.00, cg = 0.15, cb = 0.15,
    },
    {
        id               = "test",
        nombre           = "TEST",
        maxOleadas       = 3,
        tamanoOleada     = 10,
        escalaPorOleada  = 0,
        srPorOleada      = 0,
        intervalSegundos = 10,
        radioSpawn       = 25,
        tamanoTanda      = 10,
        tandaIntervalSec = 3,
        descripcion      = "3 oleadas para probar tipos de zombie.",
        lore             = "Oleada 1: lentos. Oleada 2: arrastradores. Oleada 3: rapidos.",
        detalle          = "10 fijos x3 | sin escala | sin SR | 10s prep",
        testMode         = true,
        cr = 0.40, cg = 0.60, cb = 1.00,
    },
}

-- ─── HP DEL TRONO POR MODO ──────────────────────────────────
-- HP máximo de la forja (pieza central del Trono). Game over cuando llega a 0.
-- Suben las dificultades altas tienen menos HP — combinan más zombis + Trono más frágil.
HoldoorConfig.tronoHPPorModo = {
    facil     = 1500,
    normal    = 1250,
    dificil   = 1100,
    pesadilla = 1000,
    test      = 1500,
}

-- ─── MULTIPLICADORES GLOBALES DE DROP POR MODO ──────────────
-- Se aplican a TODO: monedas, materiales, items reales.
-- Permite afinar el balance de cada modo sin tocar todas las tablas.
HoldoorConfig.dropMult = {
    facil     = { monedas = 0.7, materiales = 0.6, items = 0.5 },
    normal    = { monedas = 1.0, materiales = 1.0, items = 1.0 },
    dificil   = { monedas = 1.5, materiales = 1.6, items = 1.5 },
    pesadilla = { monedas = 2.2, materiales = 2.5, items = 2.2 },
    test      = { monedas = 0,   materiales = 0,   items = 0   },
}

-- ─── PERFORMANCE BONUS ──────────────────────────────────────
-- Si el player mato >= performanceThreshold % de los zombis de la oleada,
-- recibe +performanceCoinBonus en monedas (NO en items/materiales).
HoldoorConfig.performanceThreshold  = 0.70   -- 70% de kills
HoldoorConfig.performanceCoinBonus  = 0.10   -- +10% solo monedas

-- ─── PERFECT RUN BONUS ──────────────────────────────────────
-- Si el Trono termina la oleada con HP completo (no recibio daño), bonus extra.
-- Indica al jugador que defendio impecablemente.
HoldoorConfig.perfectRunCoinBonus   = 0.25   -- +25% en monedas si HP del Trono = 100% al fin de oleada
HoldoorConfig.perfectRunMatBonus    = 0.15   -- +15% en chances de materiales

-- ─── TABLA DE RECOMPENSAS POR MODO (monedas) ─────────────────
-- Cada oleada: bronce garantizado + tirada por plata/oro extra (drop raro)
-- Final de modo: plata garantizada + tirada por oro final
-- 2026-06-13: Bronce base 2x (floor(zombis/2)) + chances +50%.
HoldoorConfig.rewardTable = {
    facil = {
        bonusSilverChance = 0.08,   -- 8% (antes 5%)
        bonusGoldChance   = 0.00,
        endGoldChance     = 0.55,
        endGoldMin        = 1,
        endGoldMax        = 1,
    },
    normal = {
        bonusSilverChance = 0.18,   -- 18% (antes 12%)
        bonusGoldChance   = 0.03,   -- 3% (antes 2%)
        endGoldChance     = 0.75,
        endGoldMin        = 1,
        endGoldMax        = 1,
    },
    dificil = {
        bonusSilverChance = 0.30,   -- 30% (antes 20%)
        bonusGoldChance   = 0.08,   -- 8% (antes 5%)
        endGoldChance     = 0.95,
        endGoldMin        = 1,
        endGoldMax        = 2,
    },
    pesadilla = {
        bonusSilverChance = 0.45,   -- 45% (antes 30%)
        bonusGoldChance   = 0.15,   -- 15% (antes 10%)
        endGoldChance     = 1.00,
        endGoldMin        = 2,
        endGoldMax        = 3,
    },
    test = {
        bonusSilverChance = 0,
        bonusGoldChance   = 0,
        endGoldChance     = 0,
        endGoldMin        = 0,
        endGoldMax        = 0,
    },
}

-- ─── TABLA DE DROP DE MATERIALES POR MODO ───────────────────
-- Cada material tiene {chance, minQty, maxQty} por modo.
-- Chance final = chance_base * dropMult.materiales[modo].
HoldoorConfig.materialDropTable = {
    facil = {
        cuero     = { chance = 0.30, min = 1, max = 2 },
        hierro    = { chance = 0.15, min = 1, max = 1 },
        acero     = { chance = 0.05, min = 1, max = 1 },
        valyrio   = { chance = 0.00, min = 0, max = 0 },
        obsidiana = { chance = 0.00, min = 0, max = 0 },
    },
    normal = {
        cuero     = { chance = 0.50, min = 1, max = 3 },
        hierro    = { chance = 0.30, min = 1, max = 2 },
        acero     = { chance = 0.12, min = 1, max = 1 },
        valyrio   = { chance = 0.03, min = 1, max = 1 },
        obsidiana = { chance = 0.01, min = 1, max = 1 },
    },
    dificil = {
        cuero     = { chance = 0.70, min = 2, max = 3 },
        hierro    = { chance = 0.50, min = 1, max = 2 },
        acero     = { chance = 0.25, min = 1, max = 2 },
        valyrio   = { chance = 0.08, min = 1, max = 1 },
        obsidiana = { chance = 0.04, min = 1, max = 1 },
    },
    pesadilla = {
        cuero     = { chance = 0.90, min = 2, max = 4 },
        hierro    = { chance = 0.70, min = 2, max = 3 },
        acero     = { chance = 0.45, min = 1, max = 2 },
        valyrio   = { chance = 0.18, min = 1, max = 1 },
        obsidiana = { chance = 0.12, min = 1, max = 1 },
    },
    test = {  -- todo 0 para que test no inunde de drops
        cuero     = { chance = 0, min = 0, max = 0 },
        hierro    = { chance = 0, min = 0, max = 0 },
        acero     = { chance = 0, min = 0, max = 0 },
        valyrio   = { chance = 0, min = 0, max = 0 },
        obsidiana = { chance = 0, min = 0, max = 0 },
    },
}

-- ─── POOL DE ITEMS REALES DEL JUEGO (random drop por oleada) ─
-- Extensible: agregar items nuevos en cualquier pool sin tocar la lógica.
-- Pool "tesorosGoT" vacío esperando items de Game of Thrones cuando los agreguemos.
--
-- Cada item: { item="Base.X", rareza="comun|poco_comun|raro|epico", qty={min,max} }
HoldoorConfig.itemDropPool = {
    medico = {
        nombre = "Médico",
        items = {
            { item = "Base.Bandage",          rareza = "comun",      qty = {1, 2} },
            { item = "Base.Pills",            rareza = "comun",      qty = {1, 1} },
            { item = "Base.Antibiotics",      rareza = "poco_comun", qty = {1, 1} },
            { item = "Base.FirstAidKit",      rareza = "raro",       qty = {1, 1} },
        },
    },
    comida = {
        nombre = "Comida",
        items = {
            { item = "Base.Sandwich",         rareza = "comun",      qty = {1, 1} },
            { item = "Base.WaterBottleFull",  rareza = "comun",      qty = {1, 1} },
            { item = "Base.TinnedSoup",       rareza = "comun",      qty = {1, 2} },
            { item = "Base.Steak",            rareza = "poco_comun", qty = {1, 1} },
        },
    },
    armas = {
        nombre = "Armas",
        items = {
            { item = "Base.HuntingKnife",     rareza = "poco_comun", qty = {1, 1} },
            { item = "Base.Crowbar",          rareza = "poco_comun", qty = {1, 1} },
            { item = "Base.Pistol",           rareza = "raro",       qty = {1, 1} },
            { item = "Base.Bullets9mm",       rareza = "poco_comun", qty = {1, 1} },  -- caja
            { item = "Base.HuntingRifle",     rareza = "epico",      qty = {1, 1} },
        },
    },
    -- Placeholder para items GoT custom — vacio por ahora, se agregan despues
    tesorosGoT = {
        nombre = "Tesoros de Westeros",
        items = {
            -- ejemplo cuando agreguemos items GoT:
            -- { item = "Holdoor.CuernoDelInvierno", rareza = "epico", qty = {1, 1} },
        },
    },
}

-- ─── CHANCES BASE POR RAREZA ────────────────────────────────
-- Probabilidad de que SE ROLE un item de esta rareza en una oleada.
-- Chance final = chance_base * dropMult.items[modo].
HoldoorConfig.rarezaChances = {
    comun       = 0.40,   -- 40% de rolear un comun
    poco_comun  = 0.18,
    raro        = 0.06,
    epico       = 0.015,
}

-- ─── MODO CUSTOM (sliders libres) ───────────────────────────
HoldoorConfig.defaults = {
    diaInicio        = 1,
    tamanoOleada     = 20,
    intervalSegundos = 60,
    radioSpawn       = 20,
    maxOleadas       = 10,
    escalaPorOleada  = 0.10,
    srPorOleada      = 0.10,
    tamanoTanda      = 12,
    tandaIntervalSec = 8,
    soloAdmin        = false,
}

HoldoorConfig.limites = {
    tamanoOleada     = { min = 5,   max = 150 },
    intervalSegundos = { min = 10,  max = 600 },
    radioSpawn       = { min = 10,  max = 100 },
    maxOleadas       = { min = 1,   max = 30  },
    tamanoTanda      = { min = 5,   max = 40  },
    tandaIntervalSec = { min = 3,   max = 30  },
}

-- ─── FRASES GOT ─────────────────────────────────────────────
HoldoorConfig.frases = {
    { texto = "\"Hold the door...\"",                                          autor = "-- Hodor"              },
    { texto = "\"La noche es oscura y esta llena de terrores.\"",              autor = "-- Melisandre"         },
    { texto = "\"Winter is coming.\"",                                         autor = "-- Casa Stark"         },
    { texto = "\"Que le decimos al Dios de la Muerte? Hoy no.\"",             autor = "-- Syrio Forel"        },
    { texto = "\"Soy la espada en la oscuridad.\"",                            autor = "-- Guardia de la Noche"},
    { texto = "\"Valar Morghulis.\"",                                          autor = "-- Todos los hombres mueren" },
    { texto = "\"Valar Dohaeris.\"",                                           autor = "-- Todos los hombres sirven" },
    { texto = "\"La guardia nocturna comienza ahora.\"",                       autor = "-- Juramento"          },
    { texto = "\"Vivire y morire en mi puesto.\"",                             autor = "-- Juramento"          },
    { texto = "\"El caos no es un pozo. El caos es una escalera.\"",           autor = "-- Littlefinger"       },
    { texto = "\"El lobo solitario muere, pero la manada sobrevive.\"",        autor = "-- Ned Stark"          },
    { texto = "\"Cuando caiga la nieve... aguanta la puerta.\"",               autor = "-- Holdoor"            },
    { texto = "\"No quiero ser rey. Quiero estar vivo.\"",                     autor = "-- Tormund Giantsbane" },
    { texto = "\"Los muertos no descansan.\"",                                 autor = "-- Jon Snow"           },
    { texto = "\"Soy el escudo que protege los reinos de los hombres.\"",      autor = "-- Guardia de la Noche"},
}

HoldoorConfig.MODULE  = "Holdoor"
HoldoorConfig.VERSION = "0.5"
