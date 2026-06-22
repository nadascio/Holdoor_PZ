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
        subcategorias = {
            {
                id = "medico", nombre = "Medico",
                items = {
                    -- Tier 1: items individuales (5 items basicos)
                    { id="bandage",       nombre="Vendaje del Maestre",     desc="Detiene el sangrado.",
                      contenido="Vendaje x1",
                      precio={bronze=3},                    accion={tipo="item", item="Base.Bandage"} },
                    -- v0.7 #22: venda_steril REEMPLAZADA por Vino del Norte (antidepresivos).
                    { id="vino_norte",    nombre="Vino del Norte",           desc="Reduce la tristeza y depresion.",
                      contenido="Antidepresivos x1",
                      precio={bronze=5},                    accion={tipo="item", item="Base.PillsAntiDep"} },
                    { id="painkillers",   nombre="Polvo del Sueno",          desc="Reduce el dolor.",
                      contenido="Pastillas x1",
                      precio={bronze=4},                    accion={tipo="item", item="Base.Pills"} },
                    -- v0.7 #22: antibiotics REEMPLAZADO por Calmante del Septon (tranquilizantes).
                    { id="calmante_septon", nombre="Calmante del Septon",    desc="Reduce el panico y la ansiedad.",
                      contenido="Tranquilizantes x1",
                      precio={bronze=7},                    accion={tipo="item", item="Base.PillsBeta"} },
                    { id="algodon",       nombre="Algodon con Alcohol",      desc="Desinfecta heridas.",
                      contenido="Algodon con Alcohol x1",
                      precio={bronze=5},                    accion={tipo="item", item="Base.AlcoholedCottonBalls"} },
                    -- Tier 3: kit grande (unico pack premium)
                    -- v0.7 #22: Combo reajustado SIN antibioticos ni venda esteril.
                    -- Ahora incluye: 3 Vendaje + 2 AntiDep + 2 Beta + 2 Pastillas + 1 Algodon = 10 items.
                    { id="botiquin",      nombre="Botiquin del Septon",      desc="Kit completo.",
                      contenido="Vendaje x3 + Antidepresivos x2 + Tranquilizantes x2 + Pastillas x2 + Algodon x1",
                      precio={silver=1},                    accion={tipo="package", items={"Base.AlcoholBandage","Base.AlcoholBandage","Base.AlcoholBandage","Base.PillsAntiDep","Base.PillsAntiDep","Base.PillsBeta","Base.PillsBeta","Base.Pills","Base.Pills","Base.AlcoholedCottonBalls"}} },
                },
            },
            {
                id = "comida", nombre = "Comida",
                items = {
                    -- Tier 1: items individuales
                    { id="sandwich",      nombre="Sandwich del Norte",       desc="Llena el hambre.",
                      contenido="Sandwich x1",
                      precio={bronze=6},                    accion={tipo="item", item="Base.Sandwich"} },
                    { id="estofado",      nombre="Estofado del Norte",       desc="Nutritivo.",
                      contenido="Sopa Enlatada x1",
                      precio={bronze=8},                    accion={tipo="item", item="Base.TinnedSoup"} },
                    -- Tier 2: packs medianos
                    { id="rancion",       nombre="Racion de la Guardia",     desc="Combo balanceado.",
                      contenido="Sandwich + Sopa + Vino",
                      precio={bronze=20},                   accion={tipo="package", items={"Base.Sandwich","Base.TinnedSoup","Base.Wine2"}} },
                    { id="racion_cuervo", nombre="Racion del Cuervo",        desc="Para la tropa.",
                      contenido="Sandwich x3 + Vino x2",
                      precio={bronze=30},                   accion={tipo="package", items={"Base.Sandwich","Base.Sandwich","Base.Sandwich","Base.Wine2","Base.Wine2"}} },
                    -- Tier 3: kit grande
                    { id="kit_comida_3d", nombre="Provisiones de 3 Dias",    desc="Te dura varios dias.",
                      contenido="Sandwich x2 + Sopa + Steak + Vino x2",
                      precio={bronze=55},                   accion={tipo="package", items={"Base.Sandwich","Base.Sandwich","Base.TinnedSoup","Base.Steak","Base.Wine2","Base.Wine2"}} },
                },
            },
            {
                id = "bebidas", nombre = "Bebidas",
                items = {
                    { id="vino_dominio",  nombre="Vino del Dominio",         desc="Reduce sed, sube animo.",
                      contenido="Vino x1",
                      precio={bronze=10},                   accion={tipo="item", item="Base.Wine2"} },
                    { id="cerveza_norte", nombre="Cerveza del Norte",        desc="Hidrata y relaja.",
                      contenido="Cerveza x1",
                      precio={bronze=8},                    accion={tipo="item", item="Base.BeerBottle"} },
                    { id="whisky_river",  nombre="Whisky del Riverlands",    desc="Premium. Sube animo y te emborracha.",
                      contenido="Whisky x1",
                      precio={bronze=25},                   accion={tipo="item", item="Base.Whiskey"} },
                    { id="brebaje_reino", nombre="Brebaje del Reino",        desc="Refresco azucarado. Sube energia.",
                      contenido="Refresco x1",
                      precio={bronze=15},                   accion={tipo="item", item="Base.PopBottleRare"} },
                    { id="jugo_dominio",  nombre="Jugo del Dominio",         desc="Hidrata bien.",
                      contenido="Jugo de Naranja x1",
                      precio={bronze=10},                   accion={tipo="item", item="Base.JuiceOrange"} },
                    { id="leche_norte",   nombre="Leche del Norte",          desc="Nutritiva.",
                      contenido="Leche x1",
                      precio={bronze=6},                    accion={tipo="item", item="Base.MilkBottle"} },
                },
            },
        },
    },
    {
        id     = "armas",
        nombre = "Armas",
        cr=0.95, cg=0.45, cb=0.20,
        subcategorias = {
            {
                id = "melee", nombre = "Melee",
                items = {
                    { id="cuchillo",   nombre="Cuchillo de Caza",        desc="Hoja corta, util de cinturon.",
                      contenido="Cuchillo de Caza x1",
                      precio={silver=5},                       accion={tipo="item", item="Base.HuntingKnife"} },
                    { id="bate",       nombre="Bate de Guerra",          desc="Contundente, alcance medio.",
                      contenido="Bate x1",
                      precio={gold=1},                         accion={tipo="item", item="Base.BaseballBat"} },
                    { id="palanca",    nombre="Palanca del Cuervo",      desc="Resistente y durable.",
                      contenido="Palanca x1",
                      precio={gold=1, hierro=1},               accion={tipo="item", item="Base.Crowbar"} },
                    { id="machete",    nombre="Machete del Vagabundo",   desc="Cuerpo a cuerpo, alto dano.",
                      contenido="Machete x1",
                      precio={gold=2, hierro=1},               accion={tipo="item", item="Base.Machete"} },
                    { id="axe",        nombre="Hacha del Pueblo Libre",  desc="Hacha pesada de doble filo.",
                      contenido="Hacha x1",
                      precio={gold=2, hierro=2},               accion={tipo="item", item="Base.Axe"} },
                    { id="katana",     nombre="Espada Larga del Norte",  desc="Hoja legendaria forjada en Valyrio.",
                      contenido="Katana x1",
                      precio={gold=10, valyrio=3},             accion={tipo="item", item="Base.Katana"} },
                },
            },
            {
                id = "firearms", nombre = "Firearms",
                items = {
                    { id="pistola",      nombre="Pistola del Maestre",       desc="Beretta M92F. Cuerpo a cuerpo NO recomendado.",
                      contenido="Pistola x1",
                      precio={gold=5},                         accion={tipo="item", item="Base.Pistol"} },
                    { id="muni_9mm",     nombre="Municion del Maestre",      desc="Carton de balas 9mm. Para la pistola.",
                      contenido="Caja 9mm x1",
                      precio={gold=1},                         accion={tipo="item", item="Base.Bullets9mmCarton"} },
                    { id="escopeta",     nombre="Escopeta del Norte",        desc="Remington M870. Cluster killer.",
                      contenido="Escopeta x1",
                      precio={gold=8, acero=1},                accion={tipo="item", item="Base.Shotgun"} },
                    { id="cartuchos",    nombre="Cartuchos del Norte",       desc="Caja de cartuchos 12g. Para la escopeta.",
                      contenido="Caja 12g x1",
                      precio={gold=1, hierro=1},               accion={tipo="item", item="Base.ShotgunShellsBox"} },
                    { id="rifle",        nombre="Rifle de Caza",             desc="Remington M788. Largo alcance.",
                      contenido="Rifle x1",
                      precio={gold=8, acero=1},                accion={tipo="item", item="Base.HuntingRifle"} },
                    { id="muni_308",     nombre="Municion de Rifle",         desc="Caja de balas .308. Para el rifle.",
                      contenido="Caja .308 x1",
                      precio={gold=1, hierro=1},               accion={tipo="item", item="Base.308Box"} },
                },
            },
        },
    },
    {
        id     = "vestiduras",
        nombre = "Vestiduras",
        cr=0.55, cg=0.75, cb=0.95,
        subcategorias = {
            {
                id = "casual", nombre = "Casual",
                items = {
                    { id="gorra_vaga",   nombre="Gorra del Vagabundo",     desc="Cubre la cabeza, nada del otro mundo.",
                      contenido="Gorra x1",
                      precio={bronze=5},                       accion={tipo="item", item="Base.Hat_BaseballCap"} },
                    { id="guantes_cuero", nombre="Guantes del Cuervo",      desc="Cuero curtido, mano dura.",
                      contenido="Guantes de Cuero x1",
                      precio={bronze=15, cuero=1},             accion={tipo="item", item="Base.Gloves_LeatherGloves"} },
                    { id="chaqueta_cuero", nombre="Chaqueta de Cuero",       desc="Anti-mordida basica. Resistente.",
                      contenido="Chaqueta de Cuero x1",
                      precio={silver=1},                       accion={tipo="item", item="Base.Jacket_Leather"} },
                    { id="jeans_pueblo",  nombre="Jeans del Pueblo",         desc="Pantalon basico.",
                      contenido="Jeans x1",
                      precio={bronze=10},                      accion={tipo="item", item="Base.Trousers_Denim"} },
                    { id="zapatos_camino", nombre="Zapatos del Camino",      desc="Zapatos negros simples.",
                      contenido="Zapatos x1",
                      precio={bronze=15},                      accion={tipo="item", item="Base.Shoes_Black"} },
                    { id="vest_civil",    nombre="Chaleco Antibalas Civil",  desc="Proteccion anti-bala basica.",
                      contenido="Chaleco Antibalas x1",
                      precio={silver=2, hierro=1},             accion={tipo="item", item="Base.Vest_BulletCivilian"} },
                },
            },
            {
                id = "policia", nombre = "Policia",
                items = {
                    { id="casco_riot",    nombre="Casco Antidisturbios",     desc="Casco con visor, proteccion completa.",
                      contenido="Casco Antidisturbios x1",
                      precio={gold=1, acero=1},                accion={tipo="item", item="Base.Hat_RiotHelmet"} },
                    { id="camisa_pol",    nombre="Camisa de Policia",        desc="Camisa azul oficial.",
                      contenido="Camisa Policia x1",
                      precio={silver=3},                       accion={tipo="item", item="Base.Shirt_PoliceBlue"} },
                    { id="pant_pol",      nombre="Pantalones de Policia",    desc="Pantalon tactico azul.",
                      contenido="Pantalon Policia x1",
                      precio={silver=3},                       accion={tipo="item", item="Base.Trousers_Police"} },
                    { id="zap_neg",       nombre="Zapatos Negros",           desc="Calzado de servicio.",
                      contenido="Zapatos Negros x1",
                      precio={bronze=15},                      accion={tipo="item", item="Base.Shoes_Black"} },
                    { id="vest_pol",      nombre="Chaleco Antibalas Policia", desc="Anti-bala fuerte. Mid-tier.",
                      contenido="Chaleco Antibalas Policia x1",
                      precio={gold=3, acero=2, valyrio=1},      accion={tipo="item", item="Base.Vest_BulletPolice"} },
                },
            },
            {
                id = "bombero", nombre = "Bombero",
                items = {
                    { id="casco_fire",    nombre="Casco de Bombero",         desc="La mejor proteccion anti-mordida de la cabeza.",
                      contenido="Casco Bombero x1",
                      precio={gold=2, cuero=1, obsidiana=1},   accion={tipo="item", item="Base.Hat_Fireman"} },
                    { id="jacket_fire",   nombre="Chaqueta de Bombero",      desc="Aislante. Mejor anti-fuego del juego.",
                      contenido="Chaqueta Bombero x1",
                      precio={gold=3, acero=1, obsidiana=1},   accion={tipo="item", item="Base.Jacket_Fireman"} },
                    { id="pant_fire",     nombre="Pantalones de Bombero",    desc="Mayor proteccion anti-mordida en pantalones.",
                      contenido="Pantalon Bombero x1",
                      precio={gold=2, cuero=1},                accion={tipo="item", item="Base.Trousers_Fireman"} },
                    { id="guantes_fire",  nombre="Guantes del Vigia",        desc="Cuero curtido, agarre firme.",
                      contenido="Guantes de Cuero x1",
                      precio={bronze=15, cuero=1},             accion={tipo="item", item="Base.Gloves_LeatherGloves"} },
                    { id="botas_resist",  nombre="Botas Resistentes",        desc="Botas militares. Anti-mordida pies TOP.",
                      contenido="Botas Militares x1",
                      precio={gold=1, cuero=1, acero=1},       accion={tipo="item", item="Base.Shoes_ArmyBoots"} },
                },
            },
            {
                id = "militar", nombre = "Militar",
                items = {
                    { id="casco_mil",     nombre="Casco Militar",            desc="Casco camo del Norte.",
                      contenido="Casco Militar x1",
                      precio={gold=1, hierro=1},                accion={tipo="item", item="Base.Hat_Army"} },
                    { id="jacket_des",    nombre="Chaqueta Camo Desierto",   desc="Camuflaje de zona seca.",
                      contenido="Chaqueta Desert x1",
                      precio={gold=2, hierro=1, acero=1},       accion={tipo="item", item="Base.Jacket_ArmyCamoDesert"} },
                    { id="jacket_for",    nombre="Chaqueta Camo Bosque",     desc="Camuflaje de zona boscosa.",
                      contenido="Chaqueta Forest x1",
                      precio={gold=2, hierro=1, acero=1},       accion={tipo="item", item="Base.Jacket_ArmyCamoGreen"} },
                    { id="pant_mil",      nombre="Pantalones Tacticos",      desc="Service Trousers del ejercito.",
                      contenido="Pantalon Tactico x1",
                      precio={gold=2, hierro=1},                accion={tipo="item", item="Base.Trousers_ArmyService"} },
                    { id="botas_mil",     nombre="Botas Militares",          desc="Anti-mordida pies TOP.",
                      contenido="Botas Militares x1",
                      precio={gold=1, hierro=2},                accion={tipo="item", item="Base.Shoes_ArmyBoots"} },
                    { id="vest_mil",      nombre="Chaleco Antibalas Militar", desc="Anti-bala TOP. La mejor del juego.",
                      contenido="Chaleco Antibalas Militar x1",
                      precio={gold=5, acero=2, valyrio=2, obsidiana=1}, accion={tipo="item", item="Base.Vest_BulletArmy"} },
                },
            },
        },
    },
    {
        id     = "bolsos",
        nombre = "Bolsos del Reino",
        cr=0.65, cg=0.85, cb=0.55,
        items = {
            { id="morral_aprendiz", nombre="Morral del Aprendiz",      desc="Capacidad 15.",
              contenido="Morral x1",
              precio={silver=3},                       accion={tipo="item", item="Base.Bag_Schoolbag"} },
            { id="bolso_mercader",  nombre="Bolso del Mercader",       desc="Capacidad 18. Reduce 65% el peso.",
              contenido="Bolso x1",
              precio={gold=1},                         accion={tipo="item", item="Base.Bag_DuffelBag"} },
            { id="mochila_viajero", nombre="Mochila del Viajero",      desc="Capacidad 20. Reduce 70% el peso.",
              contenido="Mochila Viajero x1",
              precio={gold=2},                         accion={tipo="item", item="Base.Bag_NormalHikingBag"} },
            { id="mochila_cazador", nombre="Mochila del Cazador",      desc="Capacidad 22. Reduce 80% el peso.",
              contenido="Mochila Cazador x1",
              precio={gold=3, hierro=1},               accion={tipo="item", item="Base.Bag_BigHikingBag"} },
            { id="mochila_vigia",   nombre="Mochila del Vigilante",    desc="Capacidad 28. Reduce 85%. La TOP del juego.",
              contenido="Mochila Militar (ALICE) x1",
              precio={gold=6, acero=1},                accion={tipo="item", item="Base.Bag_ALICEpack"} },
        },
    },
    {
        id     = "habilidades",
        nombre = "Maestrias",
        cr=0.85, cg=0.55, cb=0.95,
        subcategorias = {
            {
                id = "fisico", nombre = "Fisico",
                items = {
                    -- Pasivas: curva 15x mas alta → precio "pasiva"
                    { id="lvl_fitness",  nombre="Sangre de los Primeros Hombres", desc="Sube tu Fitness 1 nivel completo.",
                      accion={tipo="subir_nivel", perk="Fitness",  tier="pasiva"} },
                    { id="lvl_strength", nombre="Doctrina de los Umber",          desc="Sube tu Strength 1 nivel completo.",
                      accion={tipo="subir_nivel", perk="Strength", tier="pasiva"} },
                    -- Regulares
                    { id="lvl_sprint",   nombre="Carrera del Mensajero",          desc="Sube tu Sprinting 1 nivel completo.",
                      accion={tipo="subir_nivel", perk="Sprinting", tier="regular"} },
                    { id="lvl_nimble",   nombre="Danza del Cuervo",               desc="Sube tu Nimble 1 nivel completo.",
                      accion={tipo="subir_nivel", perk="Nimble",    tier="regular"} },
                    { id="lvl_light",    nombre="Pasos del Lobo Huargo",          desc="Sube tu Lightfoot 1 nivel completo.",
                      accion={tipo="subir_nivel", perk="Lightfoot", tier="regular"} },
                    { id="lvl_sneak",    nombre="Sombras de Braavos",             desc="Sube tu Sneaking 1 nivel completo.",
                      accion={tipo="subir_nivel", perk="Sneak",     tier="regular"} },
                },
            },
            {
                id = "armas", nombre = "Armas",
                items = {
                    { id="lvl_lblade",   nombre="Senda del Acero Valyrio",        desc="Sube tu Long Blade 1 nivel completo.",
                      accion={tipo="subir_nivel", perk="LongBlade",  tier="regular"} },
                    { id="lvl_sblade",   nombre="Arte de la Hoja Corta",          desc="Sube tu Short Blade 1 nivel completo.",
                      accion={tipo="subir_nivel", perk="SmallBlade", tier="regular"} },
                    { id="lvl_axe",      nombre="Manual del Hacha de Guerra",     desc="Sube tu Axe 1 nivel completo.",
                      accion={tipo="subir_nivel", perk="Axe",        tier="regular"} },
                    { id="lvl_lblunt",   nombre="Disciplina del Mazo",            desc="Sube tu Long Blunt 1 nivel completo.",
                      accion={tipo="subir_nivel", perk="Blunt",      tier="regular"} },
                    { id="lvl_spear",    nombre="Cronicas de la Lanza",           desc="Sube tu Spear 1 nivel completo.",
                      accion={tipo="subir_nivel", perk="Spear",      tier="regular"} },
                    { id="lvl_maint",    nombre="Doctrina del Acero",             desc="Sube tu Maintenance 1 nivel completo.",
                      accion={tipo="subir_nivel", perk="Maintenance",tier="regular"} },
                },
            },
            {
                id = "soporte", nombre = "Soporte",
                items = {
                    { id="lvl_aim",      nombre="Practica del Arquero",           desc="Sube tu Aiming 1 nivel completo.",
                      accion={tipo="subir_nivel", perk="Aiming",     tier="regular"} },
                    { id="lvl_reload",   nombre="Recargar bajo Asedio",           desc="Sube tu Reloading 1 nivel completo.",
                      accion={tipo="subir_nivel", perk="Reloading",  tier="regular"} },
                    { id="lvl_firstaid", nombre="Sabiduria del Maestre",          desc="Sube tu First Aid 1 nivel completo.",
                      accion={tipo="subir_nivel", perk="Doctor",     tier="regular"} },
                    { id="lvl_sblunt",   nombre="Disciplina del Martillo",        desc="Sube tu Short Blunt 1 nivel completo.",
                      accion={tipo="subir_nivel", perk="SmallBlunt", tier="regular"} },
                },
            },
        },
    },
    {
        id     = "reliquias",
        nombre = "Reliquias del Reino",
        cr=0.95, cg=0.55, cb=0.30,
        items = {
            -- Ordenado de mas barato a mas caro. Todas son curaciones server-authoritative
            -- via sendClientCommand("onHealthCheatCurrentPlayer", action="healthFull").
            { id="balsamo_vidente",  nombre="Balsamo del Vidente",          desc="Cura todos los rasgunyos.",
              contenido="Cura Rasgunyos",
              precio={silver=3},                           accion={tipo="reliquia_cura_rasgunyo"} },
            { id="vendaje_septon",   nombre="Vendaje del Septon",            desc="Detiene TODO sangrado del cuerpo.",
              contenido="Cura Sangrado",
              precio={silver=5},                           accion={tipo="reliquia_cura_sangrado"} },
            { id="astillas_sagradas", nombre="Astillas Sagradas",             desc="Cierra cortes profundos del cuerpo.",
              contenido="Cura Cortes Profundos",
              precio={silver=5},                           accion={tipo="reliquia_cura_corte"} },
            -- v0.7 #21b: Tablilla del Maestre removida del catalogo para que las 6 reliquias
            -- restantes entren en una sola pagina (paginacion de 6 items). Handler server-side
            -- (reliquia_cura_fractura) queda activo por compatibilidad con saves previos.
            { id="vidriagon_bendito", nombre="Vidriagon Bendito",             desc="Cura mordeduras (sin infeccion zombi - eso solo el Beso del Dios).",
              contenido="Cura Mordedura",
              precio={gold=2},                             accion={tipo="reliquia_cura_mordedura"} },
            { id="sanacion_septon",  nombre="Sanacion del Septon",            desc="Cura sangrado, cortes, mordeduras y fracturas. NO cura infeccion zombi.",
              contenido="Cura Heridas Fisicas",
              precio={gold=5},                             accion={tipo="reliquia_cura_completa"} },
        },
    },
    -- v0.8 #1: nueva categoria "Milagros del Maestre" — items endgame "uso unico por vida"
    -- que cambian el juego. Antes vivian dentro de Reliquias del Reino (el Beso del Dios)
    -- pero al sumar el Raise up John Snow no quedaba lugar en Reliquias (6 items para
    -- caber en una pagina). Esta categoria nueva separa los "premium endgame" de las
    -- curaciones especificas, queda mas claro conceptualmente.
    {
        id     = "milagros",
        nombre = "Milagros del Maestre",
        cr=0.95, cg=0.75, cb=0.20,
        items = {
            -- v0.7 #33: Beso del Dios pivot — usa el bug-feature de admin auto-godmode.
            -- Al elevar a admin via /setaccesslevel, PZ activa GodMod + Invisible + NoClip
            -- por default. GodMod cura TODO: mordeduras, hambre, sed, infeccion zombi, fatiga.
            -- Aprovechamos eso: damos admin por 5 segundos, despues volvemos a user.
            -- v0.7 #34: tipo sigue siendo "reliquia_godmode_flash" para mantener la
            -- infraestructura de uso-unico (server _aplicarAccion + validacion compra +
            -- UI marca "ya invocado" + pre-check wounds). El handler interno cambio (ahora
            -- es admin trampoline 5s), pero la "etiqueta" del action es la misma.
            { id="beso_dios",        nombre="Beso del Dios de Muchos Rostros", desc="Cura todo + escudo + invulnerable 5s. Uso unico.",
              contenido="Curacion Total + Escudo 5s",
              precio={gold=9},                             accion={tipo="reliquia_godmode_flash"} },
            -- v0.8 #1: Raise up John Snow — seguro de vida. Si HP llega a 0 con el seguro
            -- activado (toggle en HUD lateral), R'hllor te revive en lugar seguro. Reusa
            -- el admin trampoline del Beso para curar + 5s pantalla negra + teleport.
            -- Deteccion de muerte: A (OnPlayerGetDamage) + B (OnPlayerUpdate polling HP<5)
            -- con guard para no doblar disparo. Ver next_steps.md "RAISE UP JOHN SNOW".
            { id="raise_up_jon",     nombre="Levantate, John Snow",            desc="Resucita en lugar seguro si tu HP llega a 0.",
              contenido="Resurreccion Automatica",
              precio={gold=5, valyrio=3, obsidiana=5},     accion={tipo="raise_up"} },
            -- v0.8 #22: Punto de Retorno — checkpoint personal por player.
            -- Cada jugador marca su propio punto donde quiera (independiente del host).
            -- Reusable (recomprable cada uso). NO da invulnerabilidad durante los 5s de countdown.
            -- Admin trampoline solo el ultimo instante para asegurar el teleport.
            { id="punto_retorno",    nombre="Punto de Retorno",                desc="Marca un lugar y vuelve a el cuando quieras. Te ahorra caminatas largas y peligros del camino.",
              contenido="Marca Personal + Teleport con espera 5s",
              precio={gold=2, silver=1},                   accion={tipo="punto_retorno"} },
        },
    },
    -- v0.7 #33: categoria "Bendiciones del Cuerpo" REMOVIDA. Los items individuales
    -- (Pan del Maestre / Agua Bendita / Sueno del Cuervo / Calma Total / Bendicion del Reino)
    -- causaban el mismo problema que el Beso (godmode auto curaba todo, no solo el stat
    -- pedido). En vez de pelearlo, consolidamos todo en el Beso del Dios premium.
    {
        id     = "materiales",
        nombre = "Materiales",
        cr=0.85, cg=0.65, cb=0.40,
        subcategorias = {
            {
                id = "holdoor", nombre = "Holdoor",
                items = {
                    { id="m_cuero",   nombre="Cuero Curtido",       desc="Para guantes y armaduras ligeras.",
                      contenido="+1 Cuero",
                      precio={bronze=10},  accion={tipo="material", key="Holdoor_Cuero",     amount=1} },
                    { id="m_hierro",  nombre="Hierro del Norte",     desc="Forjado en herrerias del Norte.",
                      contenido="+1 Hierro",
                      precio={bronze=25},  accion={tipo="material", key="Holdoor_Hierro",    amount=1} },
                    { id="m_acero",   nombre="Acero Castellano",     desc="Acero refinado, para armaduras de elite.",
                      contenido="+1 Acero",
                      precio={silver=1},   accion={tipo="material", key="Holdoor_Acero",     amount=1} },
                    { id="m_valyrio", nombre="Acero Valyrio",        desc="Forjado con fuego de dragones. Irrepetible.",
                      contenido="+1 Valyrio",
                      precio={gold=1},     accion={tipo="material", key="Holdoor_Valyrio",   amount=1} },
                    { id="m_obsid",   nombre="Vidrio de Dragon",     desc="La sustancia que cura toda mordida.",
                      contenido="+1 Obsidiana",
                      precio={gold=1},     accion={tipo="material", key="Holdoor_Obsidiana", amount=1} },
                },
            },
            {
                id = "comunes", nombre = "Comunes",
                items = {
                    { id="mc_plank",    nombre="Tabla de Madera",       desc="Para construir paredes y barricar.",
                      contenido="Tabla x1",
                      precio={bronze=5},   accion={tipo="item", item="Base.Plank"} },
                    { id="mc_nails",    nombre="Pack de Clavos",        desc="Clavos para carpinteria. 10 unidades.",
                      contenido="Clavos x10",
                      precio={bronze=8},   accion={tipo="package", items={"Base.Nails","Base.Nails","Base.Nails","Base.Nails","Base.Nails","Base.Nails","Base.Nails","Base.Nails","Base.Nails","Base.Nails"}} },
                    { id="mc_log",      nombre="Tronco",                desc="Material crudo para construccion pesada.",
                      contenido="Tronco x1",
                      precio={bronze=10},  accion={tipo="item", item="Base.Log"} },
                    { id="mc_sheetmetal", nombre="Chapa Metalica",      desc="Para reforzar puertas y ventanas.",
                      contenido="Chapa Metalica x1",
                      precio={bronze=15},  accion={tipo="item", item="Base.SheetMetal"} },
                    { id="mc_wire",     nombre="Cable de Acero",        desc="Para vallas y craft.",
                      contenido="Cable x1",
                      precio={bronze=10},  accion={tipo="item", item="Base.Wire"} },
                    { id="mc_metalbar", nombre="Barra de Metal",        desc="Para forja y construccion pesada.",
                      contenido="Barra Metal x1",
                      precio={bronze=15},  accion={tipo="item", item="Base.MetalBar"} },
                },
            },
        },
    },

    -- ─────────────────────────────────────────────
    -- v0.8.9: Banco de Hierro — conversion de monedas + recetas Valyrio/Obsidiana
    -- El motor de tienda descuenta los recursos del precio (mdKeyMap soporta todos).
    -- El handler "convertir_recurso" en HoldoorServer suma el destino (accion.recibo).
    -- ─────────────────────────────────────────────
    {
        id     = "banco_hierro",
        nombre = "Banco de Hierro",
        descCorta = "Casa de cambio de Braavos. Convierte monedas y forja materiales raros.",
        cr=0.85, cg=0.70, cb=0.30,
        items  = {
            { id="b50_p1", nombre="50 Bronce a 1 Plata",
              desc="Cambistas de Braavos. Tasa 50:1.",
              contenido="1 Plata",
              precio={bronze=50},
              accion={tipo="convertir_recurso", recibo={key="Holdoor_Silver", cantidad=1}} },

            { id="p30_o1", nombre="30 Plata a 1 Oro",
              desc="Maestres del Oro. Tasa 30:1.",
              contenido="1 Oro",
              precio={silver=30},
              accion={tipo="convertir_recurso", recibo={key="Holdoor_Gold", cantidad=1}} },

            { id="forja_valyrio", nombre="Forja Valyria",
              desc="Herreros de Qohor refunden con fuego de dragon.",
              contenido="1 Acero Valyrio",
              precio={cuero=15, hierro=10, acero=10},
              accion={tipo="convertir_recurso", recibo={key="Holdoor_Valyrio", cantidad=1}} },

            { id="forja_obsidiana", nombre="Forja del Vidriagon",
              desc="Tallado en hueso de dragon. Cura mordeduras.",
              contenido="1 Obsidiana",
              precio={cuero=20, hierro=15, acero=12},
              accion={tipo="convertir_recurso", recibo={key="Holdoor_Obsidiana", cantidad=1}} },
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

-- ════════════════════════════════════════════════════════════════════════════
-- PRECIOS POR NIVEL OBJETIVO (sistema "vender niveles" para Libros de Guerra)
-- ════════════════════════════════════════════════════════════════════════════
-- El item del catalogo con accion={tipo="subir_nivel", perk=X, tier="regular"|"pasiva"}
-- NO tiene precio fijo. El precio se calcula en cliente leyendo el nivel actual del
-- player y consultando esta tabla con el nivel OBJETIVO (actual + 1).
--
-- Razon:
--   - Skills regulares (Aiming, LongBlade, etc): total a nivel 10 = 32,775 XP
--   - Skills pasivas (Fitness, Strength):        total a nivel 10 = 487,500 XP (~15x)
--   - Si todo costara lo mismo, comprar Strength seria irrelevante. La tabla "pasiva"
--     refleja el valor real de subir Fitness/Strength (mucho mas dificil de subir).
-- ════════════════════════════════════════════════════════════════════════════

-- Display names en castellano para los perks (igual al panel Habilidades del juego).
-- En la UI de Maestrias mostramos este nombre amigable en lugar del slug tecnico.
HoldoorShopCatalog.perkDisplayName = {
    Fitness     = "Estado Fisico",
    Strength    = "Fuerza",
    Sprinting   = "Carrera",
    Nimble      = "Destreza",
    Lightfoot   = "Pies Ligeros",
    Sneak       = "Sigilo",
    LongBlade   = "Arma de Hoja Larga",
    SmallBlade  = "Arma de Hoja Corta",
    Axe         = "Hacha",
    Blunt       = "Arma Larga Contundente",
    SmallBlunt  = "Arma Corta Contundente",
    Spear       = "Lanza",
    Maintenance = "Mantenimiento",
    Aiming      = "Punteria",
    Reloading   = "Recarga",
    Doctor      = "Primeros Auxilios",
}

function HoldoorShopCatalog.perkLabel(slug)
    if not slug then return "?" end
    return (HoldoorShopCatalog.perkDisplayName and HoldoorShopCatalog.perkDisplayName[slug]) or slug
end

-- Tasa LINEAL precio = funcion(xpFaltante). Ajustada empiricamente.
-- Equivalencias: 50 Bronce = 1 Plata, 30 Plata = 1 Oro.
-- Mostramos precio en Plata por defecto. Si supera ciertos umbrales, mostramos en Oro.
--
-- Tasa regular: 1 Plata por cada 500 XP (Opcion A x2 lockeada 2026-06-16).
-- Tasa pasiva:  1 Plata por cada 250 XP (2x mas caro por unidad porque cada XP
--               pasivo "vale" mas — Fitness/Strength son 15x mas dificiles de subir
--               naturalmente, una unidad XP de ellas es mas valiosa).
HoldoorShopCatalog.tasaPorXP = {
    regular = { xpPorPlata = 500 },
    pasiva  = { xpPorPlata = 250 },
}

-- Calcula el precio para subir 1 nivel dado xpFaltante y tier.
-- Devuelve precio en formato { silver = N, gold = M, ... }
-- Si el precio en plata supera 30, lo convierte automaticamente a oro (1 Oro = 30 Plata).
function HoldoorShopCatalog.precioPorXP(tier, xpFaltante)
    local cfg = HoldoorShopCatalog.tasaPorXP[tier or "regular"]
    if not cfg then return { silver = 3 } end
    local platas = math.max(3, math.ceil((xpFaltante or 0) / cfg.xpPorPlata))
    if platas >= 30 then
        local oros = math.floor(platas / 30)
        local resto = platas - (oros * 30)
        if resto > 0 then
            return { gold = oros, silver = resto }
        end
        return { gold = oros }
    end
    return { silver = platas }
end

-- Busca un item del catalogo por categoria y id.
-- Soporta categorias con items directos (cat.items) o con sub-categorias (cat.subcategorias).
function HoldoorShopCatalog.buscar(categoriaId, itemId)
    for _, cat in ipairs(HoldoorShopCatalog.categorias) do
        if cat.id == categoriaId then
            -- buscar en items directos
            for _, it in ipairs(cat.items or {}) do
                if it.id == itemId then return it end
            end
            -- buscar en sub-categorias
            for _, sub in ipairs(cat.subcategorias or {}) do
                for _, it in ipairs(sub.items or {}) do
                    if it.id == itemId then return it end
                end
            end
        end
    end
    return nil
end
