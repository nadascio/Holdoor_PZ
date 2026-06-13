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

-- ─── TABLA DE RECOMPENSAS POR MODO ───────────────────────────
-- Cada oleada: bronce garantizado + tirada por plata/oro extra (drop raro)
-- Final de modo: plata garantizada + tirada por oro final
HoldoorConfig.rewardTable = {
    facil = {
        bonusSilverChance = 0.05,   -- 5% chance de +1 plata por oleada (drop raro)
        bonusGoldChance   = 0.00,   -- en facil nunca cae oro mid-run
        endGoldChance     = 0.50,   -- 50% de chance al ganar todo el modo
        endGoldMin        = 1,
        endGoldMax        = 1,
    },
    normal = {
        bonusSilverChance = 0.12,
        bonusGoldChance   = 0.02,   -- 2% por oleada (jackpot inesperado)
        endGoldChance     = 0.70,
        endGoldMin        = 1,
        endGoldMax        = 1,
    },
    dificil = {
        bonusSilverChance = 0.20,
        bonusGoldChance   = 0.05,
        endGoldChance     = 0.90,
        endGoldMin        = 1,
        endGoldMax        = 2,
    },
    pesadilla = {
        bonusSilverChance = 0.30,
        bonusGoldChance   = 0.10,
        endGoldChance     = 1.00,   -- garantizado por la dificultad
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
HoldoorConfig.VERSION = "0.3"
