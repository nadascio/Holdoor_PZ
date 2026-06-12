-- ============================================================
--  Holdoor — Sistema de Oleadas  |  Configuración compartida
--  Corre en cliente Y servidor
-- ============================================================

HoldoorConfig = HoldoorConfig or {}

-- Valores por defecto (el jugador los cambia desde el panel)
HoldoorConfig.defaults = {
    diaInicio        = 1,    -- Día del juego a partir del cual se pueden iniciar oleadas
    tamanoOleada     = 20,   -- Cantidad de zombis por oleada
    intervalMinutos  = 10,   -- Minutos de juego entre oleadas
    radioSpawn       = 60,   -- Distancia desde la base donde aparecen los zombis (en celdas)
    maxOleadas       = 0,    -- 0 = infinito
    soloAdmin        = false, -- true = solo admins pueden iniciar/detener
}

-- Límites para los sliders del panel
HoldoorConfig.limites = {
    tamanoOleada    = { min = 5,   max = 150 },
    intervalMinutos = { min = 1,   max = 60  },
    radioSpawn      = { min = 20,  max = 200 },
    maxOleadas      = { min = 0,   max = 50  },
    diaInicio       = { min = 1,   max = 365 },
}

-- Frases de Game of Thrones que aparecen entre oleadas
HoldoorConfig.frases = {
    { texto = "\"Hold the door...\"",                                          autor = "— Hodor"             },
    { texto = "\"La noche es oscura y está llena de terrores.\"",              autor = "— Melisandre"        },
    { texto = "\"Winter is coming.\"",                                         autor = "— Casa Stark"        },
    { texto = "\"¿Qué le decimos al Dios de la Muerte? Hoy no.\"",            autor = "— Syrio Forel"       },
    { texto = "\"Soy la espada en la oscuridad. Soy el vigilante de las murallas.\"", autor = "— Guardia de la Noche" },
    { texto = "\"Valar Morghulis.\"",                                          autor = "— Todos los hombres deben morir" },
    { texto = "\"Valar Dohaeris.\"",                                           autor = "— Todos los hombres deben servir" },
    { texto = "\"La guardia nocturna comienza ahora.\"",                       autor = "— Juramento de la Guardia" },
    { texto = "\"Viviré y moriré en mi puesto.\"",                             autor = "— Juramento de la Guardia" },
    { texto = "\"El caos no es un pozo. El caos es una escalera.\"",           autor = "— Littlefinger"      },
    { texto = "\"El lobo solitario muere, pero la manada sobrevive.\"",        autor = "— Ned Stark"         },
    { texto = "\"Cuando caiga la nieve y soplen los vientos blancos... aguantá la puerta.\"", autor = "— Holdoor" },
    { texto = "\"No quiero ser rey. Quiero estar vivo.\"",                     autor = "— Tormund Giantsbane"},
    { texto = "\"Los muertos no descansan.\"",                                 autor = "— Jon Snow"          },
    { texto = "\"Soy el escudo que protege los reinos de los hombres.\"",      autor = "— Guardia de la Noche" },
}

-- Nombre del módulo para comandos cliente<->servidor
HoldoorConfig.MODULE = "Holdoor"

-- Versión del mod
HoldoorConfig.VERSION = "0.1"
