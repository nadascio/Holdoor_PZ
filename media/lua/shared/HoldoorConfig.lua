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
        intervalSegundos = 60,
        radioSpawn       = 15,
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
        maxOleadas       = 5,
        tamanoOleada     = 25,
        escalaPorOleada  = 0.12,
        srPorOleada      = 0.10,
        intervalSegundos = 60,
        radioSpawn       = 15,
        tamanoTanda      = 12,
        tandaIntervalSec = 8,
        descripcion      = "La horda crece. La presion se duplica.",
        lore             = "Aqui comienza el verdadero desafio. Los que sobreviven la primera noche descubren que la segunda es peor.",
        detalle          = "3-4 puntos | 4-7 z/punto | cada 20-30s | 5 oleadas",
        cr = 0.90, cg = 0.80, cb = 0.20,
    },
    {
        id               = "dificil",
        nombre           = "DIFICIL",
        maxOleadas       = 5,
        tamanoOleada     = 35,
        escalaPorOleada  = 0.15,
        srPorOleada      = 0.12,
        intervalSegundos = 45,
        radioSpawn       = 15,
        tamanoTanda      = 12,
        tandaIntervalSec = 6,
        descripcion      = "El Rey de la Noche avanza. No hay misericordia.",
        lore             = "Solo los mejores llegan a la quinta oleada. Aqui no hay lugar para la duda.",
        detalle          = "4 puntos | 5-10 z/punto | cada 18-25s | 5 oleadas",
        cr = 1.00, cg = 0.50, cb = 0.10,
    },
    {
        id               = "pesadilla",
        nombre           = "PESADILLA",
        maxOleadas       = 5,
        tamanoOleada     = 50,
        escalaPorOleada  = 0.20,
        srPorOleada      = 0.15,
        intervalSegundos = 25,
        radioSpawn       = 15,
        tamanoTanda      = 15,
        tandaIntervalSec = 5,
        descripcion      = "No existe misericordia mas alla del Muro.",
        lore             = "Cascada constante de muertos. Completar esto es un titulo que pocos ostentan.",
        detalle          = "4 puntos | 6-12 z/punto | cada 15-22s | 5 oleadas",
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
        radioSpawn       = 15,
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
    facil     = 600,
    normal    = 500,
    dificil   = 400,
    pesadilla = 300,
    test      = 600,
}

-- ─── MULTIPLICADORES GLOBALES DE DROP POR MODO ──────────────
-- Se aplican a TODO: monedas, materiales, items reales.
-- Permite afinar el balance de cada modo sin tocar todas las tablas.
HoldoorConfig.dropMult = {
    facil     = { monedas = 0.7, materiales = 0.6, items = 0.5 },
    normal    = { monedas = 1.0, materiales = 1.0, items = 1.0 },
    dificil   = { monedas = 1.5, materiales = 1.6, items = 1.5 },
    pesadilla = { monedas = 2.2, materiales = 2.5, items = 2.2 },
    -- v0.7: TEST con drops Normal (era 2.0/2.0/3.0). Probar mecanicas, no farmear.
    test      = { monedas = 1.0, materiales = 1.0, items = 1.0 },
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
    -- v0.8.11 rebalance: subir bonus fin oleada y cantidad cierre final para compensar
    -- la baja de drops por kill. El cierre final es el premio gordo (al ganar las 5 oleadas).
    facil = {
        bonusSilverChance = 0.08,
        bonusGoldChance   = 0.001,  -- v0.8.11: 0% → 0.1% (chance de pegarla, premio raro en Facil)
        endGoldChance     = 0.55,
        endGoldMin        = 1,
        endGoldMax        = 1,
    },
    normal = {
        bonusSilverChance = 0.20,   -- v0.8.11: 18% → 20%
        bonusGoldChance   = 0.04,   -- v0.8.11: 3% → 4%
        endGoldChance     = 0.75,
        endGoldMin        = 1,
        endGoldMax        = 2,      -- v0.8.11: 1 → 1-2 oros al ganar Normal
    },
    dificil = {
        bonusSilverChance = 0.35,   -- v0.8.11: 30% → 35%
        bonusGoldChance   = 0.10,   -- v0.8.11: 8% → 10%
        endGoldChance     = 0.95,
        endGoldMin        = 2,      -- v0.8.11: 1 → 2
        endGoldMax        = 3,      -- v0.8.11: 2 → 3
    },
    pesadilla = {
        bonusSilverChance = 0.50,   -- v0.8.11: 45% → 50%
        bonusGoldChance   = 0.18,   -- v0.8.11: 15% → 18%
        endGoldChance     = 1.00,
        endGoldMin        = 3,      -- v0.8.11: 2 → 3
        endGoldMax        = 5,      -- v0.8.11: 3 → 5
    },
    -- v0.7: TEST con bonus Normal.
    test = {
        bonusSilverChance = 0.20,
        bonusGoldChance   = 0.04,
        endGoldChance     = 0.75,
        endGoldMin        = 1,
        endGoldMax        = 2,
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
    -- v0.7: TEST chances Normal (era 0.50/0.40/0.30/0.20/0.15).
    test = {
        cuero     = { chance = 0.50, min = 1, max = 3 },
        hierro    = { chance = 0.30, min = 1, max = 2 },
        acero     = { chance = 0.12, min = 1, max = 1 },
        valyrio   = { chance = 0.03, min = 1, max = 1 },
        obsidiana = { chance = 0.01, min = 1, max = 1 },
    },
}

-- ─── POOL DE ITEMS REALES DEL JUEGO (random drop por oleada) ─
-- Extensible: agregar items nuevos en cualquier pool sin tocar la lógica.
-- Pool "tesorosGoT" vacío esperando items de Game of Thrones cuando los agreguemos.
--
-- Cada item: { item="Base.X", rareza="comun|poco_comun|raro|epico", qty={min,max} }
-- v0.6: pool AMPLIADO con items confirmados de B42. Validación anti-crash en runtime:
-- HoldoorServer al cargar valida cada item con InventoryItemFactory.CreateItem dentro de pcall.
-- Items que crashean al spawnear se sacan del pool automáticamente.
-- v0.6.1: pool 100% VALIDADO contra B42 vanilla (scripts/generated/items/*.txt grep manual).
-- Cada Base.X grepeado uno por uno en los .txt del juego. No hay items inventados.
-- Si en update futuro de PZ algun nombre se renombra, FindItem en server lo detecta y saltea sin crash.
HoldoorConfig.itemDropPool = {
    medico = {
        nombre = "Médico",
        items = {
            { item = "Base.Bandage",                rareza = "comun",      qty = {1, 2} },
            { item = "Base.AlcoholBandage",         rareza = "comun",      qty = {1, 1} },
            { item = "Base.AlcoholedCottonBalls",   rareza = "comun",      qty = {1, 2} },
            { item = "Base.Bandaid",                rareza = "comun",      qty = {1, 2} },
            { item = "Base.Pills",                  rareza = "comun",      qty = {1, 1} },
            { item = "Base.PillsBeta",              rareza = "poco_comun", qty = {1, 1} },
            { item = "Base.Antibiotics",            rareza = "poco_comun", qty = {1, 1} },
            { item = "Base.SutureNeedle",           rareza = "poco_comun", qty = {1, 1} },
            { item = "Base.Tweezers",               rareza = "poco_comun", qty = {1, 1} },
            { item = "Base.FirstAidKit",            rareza = "raro",       qty = {1, 1} },
        },
    },
    comida = {
        nombre = "Comida",
        items = {
            { item = "Base.Sandwich",               rareza = "comun",      qty = {1, 1} },
            { item = "Base.TinnedSoup",             rareza = "comun",      qty = {1, 2} },
            { item = "Base.TinnedBeans",            rareza = "comun",      qty = {1, 2} },
            { item = "Base.TunaTin",                rareza = "comun",      qty = {1, 1} },
            { item = "Base.Cereal",                 rareza = "comun",      qty = {1, 1} },
            { item = "Base.Crisps",                 rareza = "comun",      qty = {1, 2} },
            { item = "Base.Chocolate",              rareza = "comun",      qty = {1, 1} },
            { item = "Base.Steak",                  rareza = "poco_comun", qty = {1, 1} },
            { item = "Base.WaterBottle",            rareza = "comun",      qty = {1, 1} },
            { item = "Base.Wine",                   rareza = "poco_comun", qty = {1, 1} },
        },
    },
    herramientas = {
        nombre = "Herramientas",
        items = {
            { item = "Base.Hammer",                 rareza = "comun",      qty = {1, 1} },
            { item = "Base.Screwdriver",            rareza = "comun",      qty = {1, 1} },
            { item = "Base.Saw",                    rareza = "poco_comun", qty = {1, 1} },
            { item = "Base.Wrench",                 rareza = "poco_comun", qty = {1, 1} },
            { item = "Base.Crowbar",                rareza = "poco_comun", qty = {1, 1} },
            { item = "Base.Nails",                  rareza = "comun",      qty = {5, 10} },
            { item = "Base.Rope",                   rareza = "poco_comun", qty = {1, 1} },
        },
    },
    municion = {
        nombre = "Munición",
        items = {
            { item = "Base.Bullets9mmBox",          rareza = "poco_comun", qty = {1, 1} },
            { item = "Base.ShotgunShellsBox",       rareza = "poco_comun", qty = {1, 1} },
            { item = "Base.Bullets44Box",           rareza = "poco_comun", qty = {1, 1} },
            { item = "Base.Bullets357Box",          rareza = "poco_comun", qty = {1, 1} },
            { item = "Base.556Bullets",             rareza = "raro",       qty = {5, 10} },
        },
    },
    libros = {
        nombre = "Libros / Papel",
        items = {
            { item = "Base.Magazine",               rareza = "comun",      qty = {1, 2} },
            { item = "Base.Newspaper",              rareza = "comun",      qty = {1, 2} },
            { item = "Base.Book",                   rareza = "comun",      qty = {1, 1} },
            { item = "Base.CookingMag1",            rareza = "poco_comun", qty = {1, 1} },
            { item = "Base.FarmingMag1",            rareza = "poco_comun", qty = {1, 1} },
            { item = "Base.BookCarpentry1",         rareza = "raro",       qty = {1, 1} },
        },
    },
    ropa = {
        nombre = "Ropa / Armadura",
        items = {
            { item = "Base.Hat_HardHat",            rareza = "poco_comun", qty = {1, 1} },
            { item = "Base.Hat_Army",               rareza = "poco_comun", qty = {1, 1} },
            { item = "Base.Hat_Police",             rareza = "poco_comun", qty = {1, 1} },
            { item = "Base.Vest_BulletCivilian",    rareza = "raro",       qty = {1, 1} },
            { item = "Base.Gloves_LeatherGloves",   rareza = "comun",      qty = {1, 1} },
            { item = "Base.Bag_Schoolbag",          rareza = "poco_comun", qty = {1, 1} },
        },
    },
    -- TesorosGoT: armas vanilla con estetica GoT-friendly hasta que tengamos items custom.
    tesorosGoT = {
        nombre = "Tesoros de Westeros",
        items = {
            { item = "Base.MeatCleaver",            rareza = "comun",      qty = {1, 1} },
            { item = "Base.HandAxe",                rareza = "poco_comun", qty = {1, 1} },
            { item = "Base.CrudeShortSword",        rareza = "poco_comun", qty = {1, 1} },
            { item = "Base.CrudeSword",             rareza = "poco_comun", qty = {1, 1} },
            { item = "Base.ShortSword",             rareza = "raro",       qty = {1, 1} },
            { item = "Base.Sword",                  rareza = "raro",       qty = {1, 1} },
            { item = "Base.WoodAxe",                rareza = "raro",       qty = {1, 1} },
            { item = "Base.Katana",                 rareza = "epico",      qty = {1, 1} },
        },
    },
}

-- ─── CHANCES BASE POR RAREZA ────────────────────────────────
-- Probabilidad de que SE ROLE un item de esta rareza en una oleada.
-- Chance final = chance_base * dropMult.items[modo].
-- v0.6.1: BAJADAS drasticamente. Antes se rolaba por CADA item del pool independiente,
-- y al ampliar el pool a 52 items dejaba ~14 items silenciosos por oleada (bug encontrado).
-- Targets con pool actual: ~3-5 items por oleada en Normal.
HoldoorConfig.rarezaChances = {
    comun       = 0.10,   -- 10%  (27 items * 10% = 2.7 esperados)
    poco_comun  = 0.05,   --  5%  (18 items * 5% = 0.9)
    raro        = 0.02,   --  2%  (6 items * 2% = 0.12)
    epico       = 0.005,  --  0.5% (1 item * 0.5% = 0.005)
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
HoldoorConfig.VERSION = "0.8.19"

-- ════════════════════════════════════════════════════════════════════
-- SPRINT v0.6 — MODELO C HÍBRIDO (timer + target kills)
-- Cada oleada dura T segundos. Durante ese tiempo spawnea zombies en stream
-- creciente. Cierre por LO QUE PASE PRIMERO: kills >= target (CIERRE LIMPIO,
-- +25% recompensa) | timer vence (SOBREVIVISTE, recompensa base) | Trono cae
-- (game over). Elimina el "zombie hunting" final del modelo viejo.
-- ════════════════════════════════════════════════════════════════════

-- ─── MULTIPLICADORES POR MODO ───────────────────────────────
-- Aplicados sobre oleadasV6 base. Pesadilla = más spawn (mult menor), más
-- target kills, mucha más recompensa.
HoldoorConfig.modosV6 = {
    facil = {
        maxOleadas      = 5,
        multDuracion    = 2.0,   -- v0.7: 5 min por oleada (era 0.8 = 2 min)
        multSpawn       = 1.3,   -- intervalo MAYOR (más lento)
        multKills       = 0.7,   -- target menor
        multRecompensa  = 0.6,
        pausaSeg        = 30,    -- v0.7: 30s pausa + 75s preparacion = 1:45 entre oleadas
    },
    normal = {
        maxOleadas      = 8,
        multDuracion    = 1.0,
        multSpawn       = 1.0,
        multKills       = 1.0,
        multRecompensa  = 1.0,
    },
    dificil = {
        maxOleadas      = 10,
        multDuracion    = 1.1,
        multSpawn       = 0.7,   -- spawn más rápido
        multKills       = 1.3,
        multRecompensa  = 1.5,
    },
    pesadilla = {
        maxOleadas      = 12,
        multDuracion    = 1.2,
        multSpawn       = 0.5,   -- spawn BRUTAL
        multKills       = 1.6,
        multRecompensa  = 2.5,
    },
    test = {
        maxOleadas      = 3,
        multDuracion    = 0.4,   -- oleadas de ~60s (antes 0.2=30s, faltaba tiempo para testear)
        multSpawn       = 1.0,
        multKills       = 0.3,
        multRecompensa  = 0,     -- sin recompensa en test
        pausaSeg        = 5,     -- pausa corta entre oleadas (testing rapido)
    },
}

-- ─── CURVA BASE DE OLEADAS (Normal, mult 1.0×) ──────────────
-- Cada entrada define una oleada. El motor multiplica por modosV6 según el modo activo.
-- spawnInicio/Fin: intervalo entre CÚMULOS en segundos (cada cúmulo = 2-5 zombies).
-- pctCorredores: probabilidad que un cúmulo sea de corredores (speed=3) en vez de fast shamblers.
-- v0.6 fix: targets +70% y intervalos más espaciados (cúmulos son grandes, vienen menos seguido).
HoldoorConfig.oleadasV6 = {
    -- # | duración | target | spawn inicio→fin | % corredores
    { duracionSeg = 150, targetKills = 50,  spawnInicio = 8.0, spawnFin = 4.0, pctCorredores = 0.00 },
    { duracionSeg = 150, targetKills = 60,  spawnInicio = 7.5, spawnFin = 3.8, pctCorredores = 0.05 },
    { duracionSeg = 165, targetKills = 75,  spawnInicio = 7.0, spawnFin = 3.5, pctCorredores = 0.10 },
    { duracionSeg = 165, targetKills = 90,  spawnInicio = 6.5, spawnFin = 3.2, pctCorredores = 0.15 },
    { duracionSeg = 180, targetKills = 110, spawnInicio = 6.0, spawnFin = 3.0, pctCorredores = 0.20 },
    { duracionSeg = 180, targetKills = 135, spawnInicio = 5.5, spawnFin = 2.8, pctCorredores = 0.22 },
    { duracionSeg = 195, targetKills = 160, spawnInicio = 5.0, spawnFin = 2.5, pctCorredores = 0.25 },
    { duracionSeg = 210, targetKills = 200, spawnInicio = 4.5, spawnFin = 2.2, pctCorredores = 0.30 },
    -- Más allá de oleada 8: usar la última (para modos Difícil/Pesadilla)
    { duracionSeg = 225, targetKills = 235, spawnInicio = 4.0, spawnFin = 2.0, pctCorredores = 0.32 },
    { duracionSeg = 240, targetKills = 270, spawnInicio = 3.5, spawnFin = 1.8, pctCorredores = 0.35 },
    { duracionSeg = 255, targetKills = 305, spawnInicio = 3.0, spawnFin = 1.6, pctCorredores = 0.38 },
    { duracionSeg = 270, targetKills = 340, spawnInicio = 2.5, spawnFin = 1.4, pctCorredores = 0.40 },
}

-- ─── CURVA ESPECIFICA FACIL (v0.7) ──────────────────────────
-- Duracion fija 5 min/oleada + targets/intervalos del plan v3.0.
-- Intervalos constantes por oleada (spawnInicio == spawnFin, sin lerp).
-- Si modoId=="facil" en _lanzarOleada, usa esta curva en vez de oleadasV6
-- + multipliers. Valores absolutos, sin escalado por modo.
HoldoorConfig.curvaFacilV7 = {
    -- # | duración | target | cúmulo cada Xs (constante) | % corredores
    { duracionSeg = 300, targetKills = 50,  spawnInicio = 15.0, spawnFin = 15.0, pctCorredores = 0.00 },
    { duracionSeg = 300, targetKills = 65,  spawnInicio = 14.0, spawnFin = 14.0, pctCorredores = 0.00 },
    { duracionSeg = 300, targetKills = 80,  spawnInicio = 13.0, spawnFin = 13.0, pctCorredores = 0.00 },
    { duracionSeg = 300, targetKills = 95,  spawnInicio = 12.0, spawnFin = 12.0, pctCorredores = 0.05 },
    { duracionSeg = 300, targetKills = 115, spawnInicio = 11.0, spawnFin = 11.0, pctCorredores = 0.10 },
}

-- ─── PAUSA ENTRE OLEADAS ─────────────────────────────────────
HoldoorConfig.pausaOleadasSegV6 = 30   -- 30s para tienda/curación sin apurar

-- ─── BONUS CIERRE LIMPIO ─────────────────────────────────────
-- Multiplicador a monedas + materiales cuando matás target ANTES del timer.
HoldoorConfig.cierreLimpioBonus = 0.25   -- +25%

-- ─── AGGRO SOSTENIDO ─────────────────────────────────────────
-- Disparar addSound desde la base cada N segundos durante oleada activa.
-- Atrae todos los zombies del area hacia la base (evita comportamiento pasivo).
HoldoorConfig.aggroIntervalSec = 4       -- cada 4s
HoldoorConfig.aggroRadio       = 150     -- v0.7: 120 -> 150 tiles
HoldoorConfig.aggroVolumen     = 300     -- v0.7: 200 -> 300 (tope vanilla LastStand)

-- ─── v0.7 #14: HORDAS MP CONTINUAS — flow definitivo por modo ──
-- Spawn CONTINUO durante toda la oleada: cada intervaloSeg dispara
-- N hordas (rotacion random de cardinales N/E/S/O) con zombiesPorPunto.
-- Si modoId esta en esta tabla → usa este flow.
-- Si NO esta → usa flow legacy (_spawnTick + curvaFacilV7/oleadasV6).
-- TEST queda con testHordasMP separado (mas abajo) para no romper testing.
-- ─── v0.7 #17: SUBTITULOS EPICOS POR OLEADA (ASCII puro — gotcha tildes/ñ B42) ──
-- Reemplaza el "Amenaza: X -- Aguanta la puerta" del flow legacy por una linea
-- tematica por oleada. El server elige random y la manda al cliente como
-- subtituloEpico. Solo aplica a modos que usan hordasMP (Facil, futuros).
-- Se eligen 5 variantes por oleada para que no se repita siempre lo mismo.
HoldoorConfig.subtitulosOleada = {
    facil = {
        [1] = {
            "La marea empieza a moverse",
            "Los primeros muertos huelen el Trono",
            "El bosque despierta",
            "Un susurro del Norte llega",
            "Manchas en el horizonte",
        },
        [2] = {
            "El sonido los atrae desde el bosque",
            "Tres direcciones, mismo destino",
            "El Cuervo trae malas noticias",
            "La oscuridad se mueve",
            "Mas voces sin alma",
        },
        [3] = {
            "Vienen de todas direcciones",
            "Cuatro vientos, cuatro hordas",
            "El cerco se cierra",
            "Rodeados, pero firmes",
            "Norte, Sur, Este, Oeste",
        },
        [4] = {
            "El muro se sacude",
            "La presion crece como las olas",
            "El bosque entero se mueve",
            "Mas ojos sin alma en la oscuridad",
            "El Trono escucha sus golpes",
        },
        [5] = {
            "El invierno mas largo se acerca",
            "Resistir o caer",
            "El ultimo canto del Cuervo",
            "Hold the door",
            "La oscuridad final",
        },
    },
    normal = {
        [1] = {
            "El mundo se sacude",
            "Las primeras lineas avanzan",
            "El silencio se rompe",
            "El Norte envia mas",
            "Caminantes en el horizonte",
        },
        [2] = {
            "La marea no para",
            "Los caidos se levantan",
            "Mas voces sin alma",
            "El frio trae mas muertos",
            "Hordas dispersas convergen",
        },
        [3] = {
            "El bosque entero se mueve",
            "Cuatro vientos, cuatro frentes",
            "El cerco se cierra rapido",
            "Los muertos huelen sangre",
            "El Trono escucha sus golpes",
        },
        [4] = {
            "La muralla cruje",
            "Mas muertos que vivos",
            "El terreno se vuelve negro",
            "La presion se duplica",
            "Un mar de cuerpos avanza",
        },
        [5] = {
            "La noche mas oscura",
            "El ultimo aliento",
            "Resistir, por la Guardia",
            "Hold the door, por el Reino",
            "La sentencia final",
        },
    },
    dificil = {
        [1] = {
            "La oscuridad despierta",
            "El Otro Lado se abre",
            "Mas que muertos, una marea",
            "El bosque entero ruge",
            "Los Caminantes Blancos llegan",
        },
        [2] = {
            "La tierra tiembla bajo sus pies",
            "Cada arbol los oculta",
            "El cielo se vuelve gris",
            "Los muertos se multiplican",
            "El asedio ha comenzado",
        },
        [3] = {
            "Mas alla del muro",
            "Las hordas no descansan",
            "El miedo invade el bosque",
            "Cuatro hordas, cuatro infiernos",
            "El Trono tiembla",
        },
        [4] = {
            "El infierno se desata",
            "El acero se rompe",
            "Mas voces, menos esperanza",
            "El bosque entero esta muerto",
            "La furia del Norte",
        },
        [5] = {
            "El final de la Guardia",
            "La oscuridad infinita",
            "Por los Caidos",
            "El precio de la fortaleza",
            "Hold the door, hasta el final",
        },
    },
    pesadilla = {
        [1] = {
            "El mundo termina",
            "Los Dioses olvidaron este lugar",
            "Mas alla de toda esperanza",
            "El abismo se abre",
            "Apocalipsis",
        },
        [2] = {
            "Cuatro vientos, cuatro tormentas",
            "El cielo se cae",
            "Los Dioses Antiguos despiertan",
            "Sangre, fuego y oscuridad",
            "El precio de la fe",
        },
        [3] = {
            "La hora mas oscura",
            "La fortaleza tiembla",
            "Mas alla del Trono",
            "El bosque entero se muere",
            "Cuervos sin cantar",
        },
        [4] = {
            "El acero se quiebra",
            "El Trono llora sangre",
            "El Reino esta perdido",
            "La furia del invierno eterno",
            "Mas muertos que estrellas",
        },
        [5] = {
            "El final de todo",
            "La gran extincion",
            "Valar Morghulis",
            "Que el Cuervo cante el final",
            "Hold the door, hasta el fin del mundo",
        },
    },
}

HoldoorConfig.hordasMP = {
    facil = {
        -- v0.7 #14c: distanciaTrono ELIMINADO. Ahora usa estado.config.radioSpawn (panel).
        -- El usuario controla la distancia de spawn con los botones - / + del panel HOLDOOR.
        -- El circulo amarillo de pelotitas refleja EXACTAMENTE donde van a aparecer las hordas.
        radiusSpawnInterno = 3,         -- dispersion interna de cada horda (-radius del comando)
        pausaSeg           = 30,        -- pausa entre oleadas + 30s preparacion = 1 min total
        oleadas = {
            -- Opcion A "Facil comodo" — total 630 zombies / 270 target = 43%
            -- # | cantPuntos | zomb/punto | cada | duracion | target
            { cantPuntos = 2, zombiesPorPunto = 3, intervaloSeg = 30, duracionSeg = 300, targetKills = 25 },
            { cantPuntos = 3, zombiesPorPunto = 3, intervaloSeg = 30, duracionSeg = 300, targetKills = 35 },
            { cantPuntos = 4, zombiesPorPunto = 3, intervaloSeg = 30, duracionSeg = 300, targetKills = 45 },
            { cantPuntos = 4, zombiesPorPunto = 4, intervaloSeg = 30, duracionSeg = 300, targetKills = 60 },
            { cantPuntos = 4, zombiesPorPunto = 5, intervaloSeg = 30, duracionSeg = 300, targetKills = 75 },
        },
    },
    normal = {
        -- Mismo flow que Facil. 5 oleadas x 5 min cada una.
        radiusSpawnInterno = 3,
        pausaSeg           = 30,
        oleadas = {
            -- # | puntos | z/punto | cada | duracion | target
            { cantPuntos = 3, zombiesPorPunto = 4, intervaloSeg = 30, duracionSeg = 300, targetKills = 35 },
            { cantPuntos = 4, zombiesPorPunto = 4, intervaloSeg = 30, duracionSeg = 300, targetKills = 50 },
            { cantPuntos = 4, zombiesPorPunto = 5, intervaloSeg = 25, duracionSeg = 300, targetKills = 70 },
            { cantPuntos = 4, zombiesPorPunto = 6, intervaloSeg = 25, duracionSeg = 300, targetKills = 90 },
            { cantPuntos = 4, zombiesPorPunto = 7, intervaloSeg = 20, duracionSeg = 300, targetKills = 110 },
        },
    },
    dificil = {
        -- Mismo flow. 5 oleadas x 5 min. Mas zombies + intervalos cortos.
        radiusSpawnInterno = 3,
        pausaSeg           = 30,
        oleadas = {
            { cantPuntos = 4, zombiesPorPunto = 5,  intervaloSeg = 25, duracionSeg = 300, targetKills = 50  },
            { cantPuntos = 4, zombiesPorPunto = 6,  intervaloSeg = 25, duracionSeg = 300, targetKills = 70  },
            { cantPuntos = 4, zombiesPorPunto = 7,  intervaloSeg = 22, duracionSeg = 300, targetKills = 95  },
            { cantPuntos = 4, zombiesPorPunto = 8,  intervaloSeg = 20, duracionSeg = 300, targetKills = 120 },
            { cantPuntos = 4, zombiesPorPunto = 10, intervaloSeg = 18, duracionSeg = 300, targetKills = 150 },
        },
    },
    pesadilla = {
        -- Mismo flow. 5 oleadas x 5 min. Brutal — cascada constante.
        radiusSpawnInterno = 3,
        pausaSeg           = 30,
        oleadas = {
            { cantPuntos = 4, zombiesPorPunto = 6,  intervaloSeg = 22, duracionSeg = 300, targetKills = 70  },
            { cantPuntos = 4, zombiesPorPunto = 8,  intervaloSeg = 20, duracionSeg = 300, targetKills = 100 },
            { cantPuntos = 4, zombiesPorPunto = 9,  intervaloSeg = 18, duracionSeg = 300, targetKills = 130 },
            { cantPuntos = 4, zombiesPorPunto = 11, intervaloSeg = 16, duracionSeg = 300, targetKills = 170 },
            { cantPuntos = 4, zombiesPorPunto = 12, intervaloSeg = 15, duracionSeg = 300, targetKills = 220 },
        },
    },
}

-- ─── v0.7 #13: TEST FLOW PARALELO con hordas MP ──────────────
-- Solo aplica si modoId == "test" Y testHordasMP.activo == true.
-- NO afecta otros modos. NO toca _spawnTick original.
-- 3 primitivas vanilla MP-safe validadas empiricamente 2026-06-18:
--   1) /createhorde2 admin via SendCommandToServer → spawn server-side
--   2) addSound(nil, x, y, z, radio, vol) → aggro hacia base (ya en _aggroSostenido)
--   3) /removezombies admin → limpieza al cierre (ya en v0.7 #12b)
-- Patrones por oleada: simultaneo / escalonado / hibrido.
HoldoorConfig.testHordasMP = {
    activo            = true,
    cantHordas        = 4,        -- 4 puntos cardinales (N/E/S/O)
    zombiesPorHorda   = 15,       -- 4 x 15 = 60 zombies por oleada
    distanciaTrono    = 22,       -- 20-25 tiles del Trono (dentro del chunk loaded)
    radiusSpawnInterno = 3,       -- dispersion interna de cada horda (-radius del comando)
    -- Patrones por oleada (string)
    --   "simultaneo": las 4 al T=0
    --   "escalonado": una cada N seg
    --   "hibrido":    2 al T=0 + 2 al T=hibridoSegundaTandaSeg
    patronPorOleada = {
        [1] = "simultaneo",
        [2] = "escalonado",
        [3] = "hibrido",
        -- Por default sigue siendo "simultaneo" para oleada 4+
    },
    escalonadoIntervaloSeg  = 30,   -- en oleada 2: una horda cada 30s
    hibridoSegundaTandaSeg  = 60,   -- en oleada 3: segunda tanda al T=60s
}

-- ─── DROPS POR KILL ──────────────────────────────────────────
-- Chances BASE (Normal). Se multiplican por dropMultPorModoV6 según dificultad.
-- v0.8.11: Opción B rebalance — plata y oro mas raros para que la economia
-- por kill no sea trivial. El Banco de Hierro pasa a ser via principal de oro.
HoldoorConfig.dropPorKillBase = {
    bronceChance = 0.25,   -- 25% chance por kill (sin cambios)
    bronceMin    = 1,
    bronceMax    = 3,      -- random entre 1-3 bronces
    plataChance  = 0.03,   -- v0.8.11: 5% → 3% (1 cada 33 kills aprox)
    oroChance    = 0.0015, -- v0.8.11: 0.5% → 0.15% (1 cada 666 kills aprox)
    itemChance   = 0.007,  -- 0.7% (sin cambios)
}

-- Multiplicadores por modo sobre las chances base
HoldoorConfig.dropMultPorModoV6 = {
    facil     = { bronce = 0.8, plata = 0.4, oro = 0.2, item = 0.4 },
    normal    = { bronce = 1.0, plata = 1.0, oro = 1.0, item = 1.0 },
    dificil   = { bronce = 1.2, plata = 1.6, oro = 3.0, item = 1.7 },
    pesadilla = { bronce = 1.4, plata = 2.4, oro = 6.0, item = 2.8 },
    -- v0.7: TEST drops Normal (era 4.0/10.0/20.0/20.0).
    test      = { bronce = 1.0, plata = 1.0, oro = 1.0, item = 1.0 },
}
-- v0.8.11 Tabla resultante (chance final por modo = base x mult):
--   Fácil:     bronce 20% | plata 1.2%  | oro 0.03%  | item 0.3%
--   Normal:    bronce 25% | plata 3.0%  | oro 0.15%  | item 0.7%
--   Difícil:   bronce 30% | plata 4.8%  | oro 0.45%  | item 1.2%
--   Pesadilla: bronce 35% | plata 7.2%  | oro 0.90%  | item 2.0%

-- ─── DROPS DE MATERIALES POR KILL ───────────────────────────
-- Chances bajas (decreasen exponencialmente con la rareza). Aplica mult del modo.
-- v0.6: agregado para que el player vea materiales caer durante combate (antes solo fin oleada).
HoldoorConfig.dropMaterialesPorKillBase = {
    cueroChance     = 0.05,    -- 5%
    hierroChance    = 0.02,    -- 2%
    aceroChance     = 0.01,    -- 1%
    valyrioChance   = 0.001,   -- 0.1%
    obsidianaChance = 0.001,   -- 0.1%
}

-- ─── REBALANCE RECOMPENSA FIN DE OLEADA ──────────────────────
-- Como ahora los kills dan monedas, la base de fin de oleada se reduce.
-- Aplica multiplicador sobre la recompensa calculada por el motor viejo.
HoldoorConfig.recompensaFinOleadaMultV6 = 0.60   -- 60% de v0.5

