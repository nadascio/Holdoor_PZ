-- ============================================================
--  Holdoor — Sistema de Oleadas  |  Lógica del servidor
--  SOLO corre en el servidor
-- ============================================================

require "HoldoorConfig"

HoldoorServer = HoldoorServer or {}

-- Estado en tiempo real del sistema
HoldoorServer.estado = {
    activo            = false,
    oleadaActual      = 0,
    baseX             = 0,
    baseY             = 0,
    baseZ             = 0,
    minutosRestantes  = 0,
    config            = {},
    baseDefinida      = false,
}

-- ─────────────────────────────────────────────
--  INICIALIZACIÓN
-- ─────────────────────────────────────────────

function HoldoorServer.init()
    -- Copia la config por defecto al estado
    HoldoorServer.estado.config = {}
    for k, v in pairs(HoldoorConfig.defaults) do
        HoldoorServer.estado.config[k] = v
    end
    print("[Holdoor] Servidor inicializado v" .. HoldoorConfig.VERSION)
end

-- ─────────────────────────────────────────────
--  CONTROL DE OLEADAS
-- ─────────────────────────────────────────────

function HoldoorServer.iniciar(jugador, config)
    local estado = HoldoorServer.estado

    if not estado.baseDefinida then
        HoldoorServer.enviarMensaje(jugador, "ERROR: Primero definí la posición de tu base desde el panel.")
        return
    end

    -- Aplicar config recibida del cliente
    if config then
        for k, v in pairs(config) do
            estado.config[k] = v
        end
    end

    estado.activo           = true
    estado.oleadaActual     = 0
    estado.minutosRestantes = 0

    HoldoorServer.notificarTodos("iniciado", { config = estado.config })
    print("[Holdoor] Sistema de oleadas iniciado por " .. jugador:getUsername())

    -- Primera oleada inmediata
    HoldoorServer.spawnOleada()
    estado.minutosRestantes = estado.config.intervalMinutos
end

function HoldoorServer.detener(jugador)
    HoldoorServer.estado.activo = false
    HoldoorServer.notificarTodos("detenido", {})
    print("[Holdoor] Sistema detenido por " .. jugador:getUsername())
end

function HoldoorServer.oleadaManual(jugador)
    if not HoldoorServer.estado.activo then
        HoldoorServer.enviarMensaje(jugador, "El sistema de oleadas no está activo.")
        return
    end
    HoldoorServer.spawnOleada()
    -- Resetear el timer de la próxima oleada automática
    HoldoorServer.estado.minutosRestantes = HoldoorServer.estado.config.intervalMinutos
end

-- ─────────────────────────────────────────────
--  TIMER — se ejecuta cada minuto de juego
-- ─────────────────────────────────────────────

function HoldoorServer.onCadaMinuto()
    local estado = HoldoorServer.estado
    if not estado.activo then return end

    estado.minutosRestantes = estado.minutosRestantes - 1

    -- Avisar cuando falta 1 minuto
    if estado.minutosRestantes == 1 then
        HoldoorServer.notificarTodos("aviso", { mensaje = "¡La próxima oleada llega en 1 minuto!" })
    end

    if estado.minutosRestantes <= 0 then
        -- Verificar límite de oleadas
        local maxOleadas = estado.config.maxOleadas
        if maxOleadas > 0 and estado.oleadaActual >= maxOleadas then
            HoldoorServer.detenerPorLimite()
            return
        end
        HoldoorServer.spawnOleada()
        estado.minutosRestantes = estado.config.intervalMinutos
    end
end

function HoldoorServer.detenerPorLimite()
    HoldoorServer.estado.activo = false
    HoldoorServer.notificarTodos("completado", {
        oleadas = HoldoorServer.estado.oleadaActual
    })
    print("[Holdoor] Todas las oleadas completadas.")
end

-- ─────────────────────────────────────────────
--  SPAWN DE OLEADA
-- ─────────────────────────────────────────────

function HoldoorServer.spawnOleada()
    local estado  = HoldoorServer.estado
    estado.oleadaActual = estado.oleadaActual + 1

    local cantidad = estado.config.tamanoOleada
    -- Las oleadas escalan levemente con el número (10% más por oleada, tope x3)
    local escala   = math.min(1 + (estado.oleadaActual - 1) * 0.1, 3.0)
    cantidad       = math.floor(cantidad * escala)

    -- Elegir frase aleatoria de GoT
    local frases = HoldoorConfig.frases
    local idx    = ZombRand(#frases) + 1
    local frase  = frases[idx]

    -- Notificar oleada a todos los jugadores
    HoldoorServer.notificarTodos("oleada", {
        numero   = estado.oleadaActual,
        cantidad = cantidad,
        frase    = frase.texto,
        autor    = frase.autor,
    })

    -- Spawnear zombis en el perímetro de la base
    local spawnados = 0
    local intentos  = 0
    local radio     = estado.config.radioSpawn
    local bx        = estado.baseX
    local by        = estado.baseY
    local bz        = estado.baseZ

    while spawnados < cantidad and intentos < cantidad * 4 do
        intentos = intentos + 1

        -- Posición aleatoria en el perímetro (anillo exterior)
        local angulo   = ZombRand(360)
        local dist     = radio + ZombRand(30) -- algo de variación en la distancia
        local sx       = bx + math.floor(math.cos(math.rad(angulo)) * dist)
        local sy       = by + math.floor(math.sin(math.rad(angulo)) * dist)

        if HoldoorServer.spawnZombie(sx, sy, bz) then
            spawnados = spawnados + 1
        end
    end

    print("[Holdoor] Oleada " .. estado.oleadaActual .. " — " .. spawnados .. "/" .. cantidad .. " zombis spawneados")
end

-- ─────────────────────────────────────────────
--  SPAWN DE ZOMBIE INDIVIDUAL
-- ─────────────────────────────────────────────

function HoldoorServer.spawnZombie(x, y, z)
    local cell = getCell()
    if not cell then return false end

    -- Intentar obtener o crear la celda en esa posición
    local sq = cell:getGridSquare(x, y, z)
    if not sq then return false end

    -- No spawnear en agua ni en interiores cerrados
    if sq:isWater() then return false end

    -- Crear el zombie (compatible con B41 y B42)
    local ok, zombie = pcall(function()
        return IsoZombie.new(cell, sq, false)
    end)

    if not ok or not zombie then return false end

    cell:addObject(zombie)

    -- DoZombieStats inicializa las stats del zombie
    if zombie.DoZombieStats then
        zombie:DoZombieStats()
    end

    return true
end

-- ─────────────────────────────────────────────
--  POSICIÓN DE LA BASE
-- ─────────────────────────────────────────────

function HoldoorServer.setBase(jugador, x, y, z)
    local estado      = HoldoorServer.estado
    estado.baseX      = math.floor(x)
    estado.baseY      = math.floor(y)
    estado.baseZ      = math.floor(z)
    estado.baseDefinida = true

    HoldoorServer.notificarTodos("baseActualizada", { x = estado.baseX, y = estado.baseY, z = estado.baseZ })
    print("[Holdoor] Base definida en " .. estado.baseX .. "," .. estado.baseY .. " por " .. jugador:getUsername())
end

-- ─────────────────────────────────────────────
--  COMUNICACIÓN CON CLIENTES
-- ─────────────────────────────────────────────

function HoldoorServer.notificarTodos(tipo, datos)
    local players = getOnlinePlayers()
    for i = 0, players:size() - 1 do
        sendClientCommand(players:get(i), HoldoorConfig.MODULE, tipo, datos)
    end
end

function HoldoorServer.enviarMensaje(jugador, texto)
    sendClientCommand(jugador, HoldoorConfig.MODULE, "mensaje", { texto = texto })
end

-- ─────────────────────────────────────────────
--  RECIBIR COMANDOS DE LOS CLIENTES
-- ─────────────────────────────────────────────

function HoldoorServer.onComandoCliente(modulo, comando, jugador, args)
    if modulo ~= HoldoorConfig.MODULE then return end

    local config = HoldoorServer.estado.config
    local soloAdmin = config.soloAdmin

    -- Verificar permisos si está configurado soloAdmin
    local esAdmin = jugador:getAccessLevel() ~= "" and jugador:getAccessLevel() ~= "None"
    if soloAdmin and not esAdmin then
        HoldoorServer.enviarMensaje(jugador, "Solo los admins pueden controlar las oleadas.")
        return
    end

    if comando == "iniciar" then
        HoldoorServer.iniciar(jugador, args.config)

    elseif comando == "detener" then
        HoldoorServer.detener(jugador)

    elseif comando == "setBase" then
        HoldoorServer.setBase(jugador, args.x, args.y, args.z)

    elseif comando == "oleadaManual" then
        HoldoorServer.oleadaManual(jugador)

    elseif comando == "pedirEstado" then
        -- El cliente pide el estado actual (por ejemplo al reconectarse)
        local estado = HoldoorServer.estado
        sendClientCommand(jugador, HoldoorConfig.MODULE, "estado", {
            activo          = estado.activo,
            oleadaActual    = estado.oleadaActual,
            minutosRestantes = estado.minutosRestantes,
            baseX           = estado.baseX,
            baseY           = estado.baseY,
            baseZ           = estado.baseZ,
            baseDefinida    = estado.baseDefinida,
            config          = estado.config,
        })
    end
end

-- ─────────────────────────────────────────────
--  REGISTRO DE EVENTOS
-- ─────────────────────────────────────────────

Events.OnServerStarted.Add(HoldoorServer.init)
Events.EveryOneMinute.Add(HoldoorServer.onCadaMinuto)
Events.OnClientCommand.Add(HoldoorServer.onComandoCliente)
