-- ============================================================
--  Holdoor — Sistema de Oleadas  |  Lógica del servidor
--  SOLO corre en el servidor
-- ============================================================

require "HoldoorConfig"
require "HoldoorShopCatalog"

HoldoorServer = HoldoorServer or {}

local PAUSA_SEGS = 10  -- segundos de pausa entre oleadas (tiempo real)

-- Estado en tiempo real del sistema
HoldoorServer.estado = {
    activo           = false,
    fase             = "inactivo",
    oleadaActual     = 0,
    baseX            = 0,
    baseY            = 0,
    baseZ            = 0,
    zombiesRestantes = 0,
    zombiesTotal     = 0,
    countdownFinSec  = 0,
    pausaFinSec      = 0,
    avisoDado        = false,
    config           = {},
    baseDefinida     = false,
    ultimoSonidoSec  = 0,
    -- Staggered spawn
    encoladosTiers   = {},
    proximaTandaSec  = 0,
    tamanoTanda      = 12,
    tandaIntervalSec = 8,
    -- Kill tracking
    killsOleada      = {},          -- { [username] = count } — se resetea cada oleada
    killsTotal       = {},          -- { [username] = count } — acumula toda la partida
}

-- ─────────────────────────────────────────────
--  INICIALIZACIÓN
-- ─────────────────────────────────────────────

function HoldoorServer.init()
    HoldoorServer.estado.config = {}
    for k, v in pairs(HoldoorConfig.defaults) do
        HoldoorServer.estado.config[k] = v
    end
    print("[Holdoor] Servidor inicializado v" .. HoldoorConfig.VERSION)
    print("[Holdoor] addZombiesInOutfit disponible: " .. tostring(type(addZombiesInOutfit) == "function"))
    local sandboxOK = SandboxVars ~= nil and SandboxVars.ZombieConfig ~= nil
    print("[Holdoor] Control velocidad zombies: " .. (sandboxOK and ("DISPONIBLE (Speed=" .. tostring(SandboxVars.ZombieConfig.Speed) .. ")") or "NO DISPONIBLE"))
end

-- ─────────────────────────────────────────────
--  CONTROL DE OLEADAS
-- ─────────────────────────────────────────────

function HoldoorServer.iniciar(jugador, config)
    local estado = HoldoorServer.estado

    -- Bloquear si ya hay oleadas en curso
    if estado.activo then
        local quien = estado.ownerUsername or "otro jugador"
        HoldoorServer.enviarMensaje(jugador, "Ya hay oleadas activas iniciadas por " .. quien .. ". Espera a que terminen.")
        return
    end

    if not estado.baseDefinida then
        HoldoorServer.enviarMensaje(jugador, "ERROR: Primero defini la posicion de tu base desde el panel.")
        return
    end

    if config then
        for k, v in pairs(config) do
            estado.config[k] = v
        end
    end

    -- Registrar al iniciador como dueño de esta sesion (solo el puede detenerla)
    estado.ownerUsername = jugador:getUsername() or "?"

    -- Detectar jugadores conectados y calcular multiplicador
    local numPlayers = 1
    local ok, players = pcall(getOnlinePlayers)
    if ok and players then
        local ok2, n = pcall(function() return players:size() end)
        if ok2 and n and n > 0 then numPlayers = n end
    end
    local multMap = { 1.0, 1.5, 2.0, 2.5 }
    local mult = multMap[math.min(numPlayers, 4)] or 2.5
    estado.config.playerMultiplier = mult
    estado.config.numPlayers       = numPlayers

    estado.activo       = true
    estado.oleadaActual = 0
    estado.killsOleada  = {}
    estado.killsTotal   = {}

    print("[Holdoor] Iniciado por " .. jugador:getUsername() .. " | Jugadores: " .. numPlayers .. " | Mult: x" .. mult)
    HoldoorServer.notificarTodos("iniciado", {
        config     = estado.config,
        numPlayers = numPlayers,
        multiplier = mult,
    })

    HoldoorServer._iniciarPreparacion(5)
end

-- Construye string de ranking a partir de tabla { [name]=kills }
local function buildKillsStr(killsTable)
    local entries = {}
    for name, kills in pairs(killsTable) do
        table.insert(entries, { name = name, kills = kills })
    end
    table.sort(entries, function(a, b) return a.kills > b.kills end)
    local parts = {}
    for i, e in ipairs(entries) do
        table.insert(parts, "#" .. i .. " " .. e.name .. ": " .. e.kills .. " bajas")
        if i >= 4 then break end
    end
    return table.concat(parts, "  |  ")
end

-- ─────────────────────────────────────────────
--  MONEDAS — distribución al fin de oleada
-- ─────────────────────────────────────────────

-- Monedas como contadores en ModData del jugador.
-- Persiste entre sesiones (PZ guarda ModData del jugador con el save).
-- Mas robusto que items.txt en B42 y se integra directo con la tienda futura.
local function darMonedasA(p, bronze, silver, gold)
    local ok, md = pcall(function() return p:getModData() end)
    if not ok or not md then return false end
    md.Holdoor_Bronze = (md.Holdoor_Bronze or 0) + (bronze or 0)
    md.Holdoor_Silver = (md.Holdoor_Silver or 0) + (silver or 0)
    md.Holdoor_Gold   = (md.Holdoor_Gold   or 0) + (gold   or 0)
    return true
end

-- Transferencia jugador→jugador. Validaciones server-side (anti-cheat).
-- Si el receptor no esta conectado, bloquea (sin buzon offline).
function HoldoorServer._transferirMonedas(emisor, args)
    local fromUser = emisor:getUsername() or "?"
    local toUser   = args and args.to
    local tipo     = args and args.tipo
    local cantidad = tonumber(args and args.cantidad) or 0

    -- Validaciones basicas
    if cantidad <= 0 then
        HoldoorServer.enviarMensaje(emisor, "La cantidad debe ser mayor a 0.")
        return
    end
    if not toUser or toUser == "" then
        HoldoorServer.enviarMensaje(emisor, "Destinatario invalido.")
        return
    end
    if toUser == fromUser then
        HoldoorServer.enviarMensaje(emisor, "No podes transferirte monedas a vos mismo.")
        return
    end
    local keyMap = { bronze="Holdoor_Bronze", silver="Holdoor_Silver", gold="Holdoor_Gold" }
    local mdKey = keyMap[tipo]
    if not mdKey then
        HoldoorServer.enviarMensaje(emisor, "Tipo de moneda invalido.")
        return
    end

    -- Buscar al receptor entre los jugadores online
    local target = nil
    local ok, players = pcall(getOnlinePlayers)
    if ok and players then
        local ok2, n = pcall(function() return players:size() end)
        if ok2 and n then
            for i = 0, n - 1 do
                local ok3, p = pcall(function() return players:get(i) end)
                if ok3 and p then
                    local okU, u = pcall(function() return p:getUsername() end)
                    if okU and u == toUser then target = p; break end
                end
            end
        end
    end
    if not target then
        HoldoorServer.enviarMensaje(emisor, "El jugador '" .. toUser .. "' no esta conectado.")
        return
    end

    -- Validar saldo del emisor
    local mdFrom = emisor:getModData()
    local saldoFrom = mdFrom[mdKey] or 0
    if saldoFrom < cantidad then
        HoldoorServer.enviarMensaje(emisor, "Saldo insuficiente. Tenes " .. saldoFrom .. ", pediste " .. cantidad .. ".")
        return
    end

    -- Ejecutar
    local mdTo = target:getModData()
    mdFrom[mdKey] = saldoFrom - cantidad
    mdTo[mdKey]   = (mdTo[mdKey] or 0) + cantidad
    print("[Holdoor] Transfer: " .. fromUser .. " -> " .. toUser .. " | " .. cantidad .. " " .. tipo)

    -- Notificar a ambos
    pcall(sendClientCommand, emisor, HoldoorConfig.MODULE, "monedasActualizadas", {})
    pcall(sendClientCommand, target, HoldoorConfig.MODULE, "monedasActualizadas", {})
    pcall(sendClientCommand, emisor, HoldoorConfig.MODULE, "transferOK",
        { to=toUser, tipo=tipo, cantidad=cantidad })
    pcall(sendClientCommand, target, HoldoorConfig.MODULE, "transferRecibido",
        { from=fromUser, tipo=tipo, cantidad=cantidad })

    -- SP fallback (no hay sendClientCommand efectivo)
    if type(HoldoorClient) == "table" and HoldoorClient.onComandoServidor then
        pcall(HoldoorClient.onComandoServidor, HoldoorConfig.MODULE, "monedasActualizadas", {})
    end
end

-- ─────────────────────────────────────────────
--  TIENDA — compras server-side
-- ─────────────────────────────────────────────

-- Ejecuta la accion del item (item, package, xp, restore, cure_bite).
-- Devuelve true si pudo ejecutar, false si hubo error.
local function ejecutarAccion(jugador, accion)
    if not accion or not accion.tipo then return false end

    if accion.tipo == "item" then
        local inv = jugador:getInventory()
        if not inv then return false end
        local ok = pcall(function() inv:AddItem(accion.item) end)
        return ok

    elseif accion.tipo == "package" then
        local inv = jugador:getInventory()
        if not inv then return false end
        local any = false
        for _, itemName in ipairs(accion.items or {}) do
            local ok = pcall(function() inv:AddItem(itemName) end)
            if ok then any = true end
        end
        return any

    elseif accion.tipo == "xp" then
        local ok = pcall(function()
            local perk = Perks.FromString(accion.perk)
            if perk then jugador:getXp():AddXP(perk, accion.amount or 0) end
        end)
        return ok

    elseif accion.tipo == "restore" then
        local stats = jugador:getStats()
        local bd    = jugador:getBodyDamage()
        for _, s in ipairs(accion.stats or {}) do
            pcall(function()
                if     s == "hunger"   then stats:setHunger(0)
                elseif s == "thirst"   then stats:setThirst(0)
                elseif s == "fatigue"  then stats:setFatigue(0)
                elseif s == "stress"   then stats:setStress(0)
                elseif s == "endurance" then stats:setEndurance(1)
                elseif s == "sleep"    then bd:setFatigue(0)
                end
            end)
        end
        return true

    elseif accion.tipo == "material" then
        local md = jugador:getModData()
        if not md or not accion.key then return false end
        md[accion.key] = (md[accion.key] or 0) + (accion.amount or 1)
        return true

    elseif accion.tipo == "cure_bite" then
        local bd = jugador:getBodyDamage()
        if not bd then return false end
        pcall(function() bd:setInfected(false) end)
        pcall(function() bd:setIsFakeInfected(false) end)
        -- Quitar mordeduras de todas las partes del cuerpo
        pcall(function()
            local parts = bd:getBodyParts()
            if parts then
                for i = 0, parts:size() - 1 do
                    local part = parts:get(i)
                    if part then
                        pcall(function() part:SetBitten(false) end)
                        pcall(function() part:setBiteTime(0) end)
                        pcall(function() part:setHaveBullet(false, 0) end)
                    end
                end
            end
        end)
        return true
    end

    return false
end

-- Validacion y ejecucion de compra. Trata monedas y materiales con la misma logica
-- usando el mapeo HoldoorShopCatalog.mdKeyMap.
function HoldoorServer._comprar(jugador, args)
    local catId  = args and args.categoria
    local itemId = args and args.item

    local item = HoldoorShopCatalog.buscar(catId, itemId)
    if not item then
        pcall(sendClientCommand, jugador, HoldoorConfig.MODULE, "compraFail", { motivo = "Producto no encontrado." })
        return
    end

    local md = jugador:getModData()
    local mdKeyMap = HoldoorShopCatalog.mdKeyMap

    -- Validar que tenga saldo suficiente para CADA componente del precio
    for k, costo in pairs(item.precio or {}) do
        if costo and costo > 0 then
            local mdKey = mdKeyMap[k]
            if not mdKey then
                pcall(sendClientCommand, jugador, HoldoorConfig.MODULE, "compraFail",
                      { motivo = "Precio invalido en catalogo: " .. tostring(k) })
                return
            end
            if (md[mdKey] or 0) < costo then
                local lbl = (HoldoorShopCatalog.labels and HoldoorShopCatalog.labels[k]) or k
                pcall(sendClientCommand, jugador, HoldoorConfig.MODULE, "compraFail",
                      { motivo = "Te falta " .. lbl .. " (tenes " .. (md[mdKey] or 0) .. ", necesitas " .. costo .. ")." })
                return
            end
        end
    end

    -- Ejecutar accion ANTES de cobrar (si falla, no perdes nada)
    local ok = ejecutarAccion(jugador, item.accion)
    if not ok then
        pcall(sendClientCommand, jugador, HoldoorConfig.MODULE, "compraFail", { motivo = "Error al entregar el producto." })
        return
    end

    -- Cobrar: descontar TODAS las componentes del precio
    for k, costo in pairs(item.precio or {}) do
        if costo and costo > 0 then
            local mdKey = mdKeyMap[k]
            md[mdKey] = (md[mdKey] or 0) - costo
        end
    end

    print("[Holdoor] Compra: " .. jugador:getUsername() .. " -> " .. catId .. "/" .. itemId ..
          " | " .. HoldoorShopCatalog.precioStr(item.precio))

    pcall(sendClientCommand, jugador, HoldoorConfig.MODULE, "monedasActualizadas", {})
    pcall(sendClientCommand, jugador, HoldoorConfig.MODULE, "compraOK", {
        nombre = item.nombre,
        precio = item.precio,
    })

    if type(HoldoorClient) == "table" and HoldoorClient.onComandoServidor then
        pcall(HoldoorClient.onComandoServidor, HoldoorConfig.MODULE, "monedasActualizadas", {})
        pcall(HoldoorClient.onComandoServidor, HoldoorConfig.MODULE, "compraOK", { nombre=item.nombre, precio=item.precio })
    end
end

-- Entrega monedas a todos los jugadores y les avisa por cliente para que actualicen el HUD.
function HoldoorServer._distribuirMonedas(bronze, silver, gold)
    if (bronze or 0) <= 0 and (silver or 0) <= 0 and (gold or 0) <= 0 then return end

    local entregado = false
    local ok, players = pcall(getOnlinePlayers)
    if ok and players then
        local ok2, n = pcall(function() return players:size() end)
        if ok2 and n and n > 0 then
            for i = 0, n - 1 do
                local ok3, p = pcall(function() return players:get(i) end)
                if ok3 and p then darMonedasA(p, bronze, silver, gold); entregado = true end
            end
        end
    end
    if not entregado then
        local ok2, p = pcall(getSpecificPlayer, 0)
        if ok2 and p then darMonedasA(p, bronze, silver, gold) end
    end

    -- Notificar a clientes para refrescar el HUD del saldo
    HoldoorServer.notificarTodos("monedasActualizadas", {})
    print("[Holdoor] Monedas entregadas: " .. (bronze or 0) .. "B " .. (silver or 0) .. "S " .. (gold or 0) .. "G")
end

function HoldoorServer.detener(jugador)
    local estado = HoldoorServer.estado

    -- Solo el dueno de la sesion puede detener (o un admin real)
    if jugador and estado.ownerUsername and estado.ownerUsername ~= jugador:getUsername() then
        local lvl = ""
        local ok, accessLvl = pcall(function() return jugador:getAccessLevel() end)
        if ok and accessLvl then lvl = string.lower(tostring(accessLvl)) end
        local esStaff = lvl == "admin" or lvl == "moderator" or lvl == "gm" or lvl == "overseer"
        if not esStaff then
            HoldoorServer.enviarMensaje(jugador, "Solo " .. estado.ownerUsername .. " puede detener estas oleadas.")
            return
        end
    end

    estado.activo            = false
    estado.fase              = "inactivo"
    estado.zombiesRestantes  = 0
    estado.zombiesTotal      = 0
    estado.ownerUsername     = nil
    HoldoorServer.notificarTodos("detenido", {})
    if jugador then
        print("[Holdoor] Sistema detenido por " .. jugador:getUsername())
    else
        print("[Holdoor] Sistema detenido")
    end
end

-- Args opcionales: bronce/plata/oro de la ULTIMA oleada (ya distribuidos).
-- Solo se usan para mostrarlos al jugador como "bonus de ultima oleada".
function HoldoorServer.detenerPorLimite(ultBonusSilver, ultBonusGold)
    local estado             = HoldoorServer.estado
    estado.activo            = false
    estado.fase              = "inactivo"
    estado.zombiesRestantes  = 0

    local oleadas = estado.oleadaActual

    -- Plata final: garantizada por oleadas completadas (1 por cada 3)
    local silver = math.floor(oleadas / 3)

    -- Oro final: tirada probabilistica segun el modo
    local rewardTbl = HoldoorConfig.rewardTable[estado.config.modoId or "normal"]
                    or HoldoorConfig.rewardTable.normal
    local goldRoll = (ZombRand(100) < math.floor(rewardTbl.endGoldChance * 100))
    local gold = 0
    if goldRoll then
        local range = math.max(0, (rewardTbl.endGoldMax or 1) - (rewardTbl.endGoldMin or 1))
        gold = (rewardTbl.endGoldMin or 1) + ZombRand(range + 1)
    end

    HoldoorServer._distribuirMonedas(0, silver, gold)

    local killsStr = buildKillsStr(estado.killsTotal)
    HoldoorServer.notificarTodos("completado", {
        oleadas       = oleadas,
        killsStr      = killsStr,
        killsData     = estado.killsTotal,
        bronze        = 0,
        silver        = silver,
        gold          = gold,
        goldChance    = rewardTbl.endGoldChance,  -- el cliente lo usa para narrar si fue suerte o garantizado
        modoId        = estado.config.modoId or "normal",
        ultBonusSilver = ultBonusSilver or 0,
        ultBonusGold   = ultBonusGold or 0,
    })
    estado.killsTotal    = {}
    estado.killsOleada   = {}
    estado.ownerUsername = nil
    print("[Holdoor] Modo completado. Premio final: " .. silver .. "S + " .. gold .. "G (chance " ..
          math.floor(rewardTbl.endGoldChance * 100) .. "%) | " .. (killsStr ~= "" and killsStr or "sin datos"))
end

-- ─────────────────────────────────────────────
--  MAQUINA DE ESTADOS
-- ─────────────────────────────────────────────

function HoldoorServer._iniciarPreparacion(override_segs)
    local estado         = HoldoorServer.estado
    local segs           = override_segs or (estado.config.intervalSegundos or 60)
    estado.fase          = "preparacion"
    estado.countdownFinSec = os.time() + segs
    estado.avisoDado     = false

    HoldoorServer.notificarTodos("preparacion", {
        segundos  = segs,
        oleadaSig = estado.oleadaActual + 1,
    })
    print("[Holdoor] Preparacion: oleada " .. (estado.oleadaActual + 1) .. " en " .. segs .. "s reales")
end

-- Spawnea 1 zombie y le da pathfinding. SandboxVars de Speed/Crawl se manejan a nivel
-- de tier en _spawnTanda. crawl aqui solo sirve para el override manual post-spawn.
function HoldoorServer._spawnUno(sx, sy, sz, destX, destY, destZ, crawl)
    local spawned = pcall(addZombiesInOutfit, sx, sy, sz, 1, nil, nil)
    if not spawned then return false end

    local ok, sq = pcall(function() return getCell():getGridSquare(sx, sy, sz) end)
    if ok and sq then
        local objs = sq:getMovingObjects()
        for i = 1, objs:size() do
            local obj = objs:get(i - 1)
            if instanceof(obj, "IsoZombie") then
                pcall(function() obj:pathToLocation(destX, destY, destZ) end)
                -- Override manual: forzar crawler aunque SandboxVar no sea suficiente
                if crawl and crawl >= 100 then
                    pcall(function() obj:setCrawler(true) end)
                end
                break
            end
        end
    end
    return true
end

-- Spawnea la siguiente tanda de la cola escalonada
function HoldoorServer._spawnTanda()
    local estado = HoldoorServer.estado
    local cfg    = estado.config
    local bx, by, bz = estado.baseX, estado.baseY, estado.baseZ
    local radio  = cfg.radioSpawn or 20
    local tanda  = estado.tamanoTanda or 12

    local totalEncolado = 0
    for _, t in ipairs(estado.encoladosTiers) do totalEncolado = totalEncolado + t.count end
    if totalEncolado <= 0 then return end

    local aSpawnear = math.min(tanda, totalEncolado)
    local origSpeed = SandboxVars and SandboxVars.ZombieConfig and SandboxVars.ZombieConfig.Speed
    local origCrawl = SandboxVars and SandboxVars.ZombieConfig and SandboxVars.ZombieConfig.Crawl
    local spawnadosTanda = 0

    for _, tier in ipairs(estado.encoladosTiers) do
        if spawnadosTanda < aSpawnear and tier.count > 0 then
            local fromTier = math.max(1, math.floor(aSpawnear * tier.count / totalEncolado))
            fromTier = math.min(fromTier, tier.count, aSpawnear - spawnadosTanda)
            if origSpeed ~= nil then SandboxVars.ZombieConfig.Speed = tier.speed end
            if origCrawl ~= nil then SandboxVars.ZombieConfig.Crawl = tier.crawl or 0 end
            local spawned = 0
            for j = 1, fromTier * 4 do
                if spawned >= fromTier then break end
                local ang  = ZombRand(360)
                local dist = radio + ZombRand(8)
                local sx   = math.floor(bx + math.cos(math.rad(ang)) * dist)
                local sy   = math.floor(by + math.sin(math.rad(ang)) * dist)

                -- Verificar que la tile de spawn es exterior (no dentro de un edificio)
                local ok_sq, spawnSq = pcall(function() return getCell():getGridSquare(sx, sy, bz) end)
                if ok_sq and spawnSq then
                    local ok_out, esExterior = pcall(function() return spawnSq:isOutside() end)
                    if ok_out and not esExterior then
                        -- Tile interior — saltar, probar otro angulo
                    else
                        local angD = ZombRand(360)
                        local dD   = ZombRand(math.max(1, math.floor(radio * 0.4)))
                        local tx   = math.floor(bx + math.cos(math.rad(angD)) * dD)
                        local ty   = math.floor(by + math.sin(math.rad(angD)) * dD)
                        if HoldoorServer._spawnUno(sx, sy, bz, tx, ty, bz, tier.crawl or 0) then
                            spawned = spawned + 1
                        end
                    end
                end
            end
            tier.count = math.max(0, tier.count - spawned)
            spawnadosTanda = spawnadosTanda + spawned
        end
    end

    if origSpeed ~= nil and SandboxVars and SandboxVars.ZombieConfig then
        SandboxVars.ZombieConfig.Speed = origSpeed
    end
    if origCrawl ~= nil and SandboxVars and SandboxVars.ZombieConfig then
        SandboxVars.ZombieConfig.Crawl = origCrawl
    end

    -- Ruido fuerte al spawnear: atrae a los nuevos zombis hacia la base
    local sndR = math.floor(radio * 2 + 30)
    pcall(addSound, nil, bx, by, bz, sndR, 180)

    local remaining = 0
    for _, t in ipairs(estado.encoladosTiers) do remaining = remaining + t.count end
    if remaining > 0 then
        estado.proximaTandaSec = os.time() + (estado.tandaIntervalSec or 8)
    end
    print("[Holdoor] Tanda: +" .. spawnadosTanda .. " | En cola: " .. remaining)
end

function HoldoorServer._lanzarOleada()
    local estado = HoldoorServer.estado
    estado.oleadaActual = estado.oleadaActual + 1
    local oleada = estado.oleadaActual
    local cfg    = estado.config

    -- Limpiar zona antes de cada oleada: elimina world-zombies que contaminaron la pausa
    local eliminados = HoldoorServer._limpiarZona()
    if eliminados > 0 then
        HoldoorServer.notificarTodos("zonaLimpiada", { cantidad = eliminados })
    end

    -- Cantidad con escala por oleada y multiplicador de jugadores
    local escala  = math.min(1 + (oleada - 1) * (cfg.escalaPorOleada or 0.10), 3.0)
    local mult    = cfg.playerMultiplier or 1.0
    local cantidad = math.floor((cfg.tamanoOleada or 20) * mult * escala)

    -- Speedrunners
    local srPct   = math.min(oleada * (cfg.srPorOleada or 0.10), 1.0)
    local srCount = math.floor(cantidad * srPct)
    local srSpeed = 3  -- capped: sin speed 4 (sprinters buggy)
    local total   = cantidad + srCount

    -- Construir tiers para spawn escalonado
    local composicion = HoldoorServer.calcularComposicion(oleada, cantidad)
    if srCount > 0 then
        table.insert(composicion, { count = srCount, speed = srSpeed, crawl = 0, texto = "Corredores extras" })
    end
    estado.encoladosTiers   = composicion
    estado.tamanoTanda      = cfg.tamanoTanda or 12
    estado.tandaIntervalSec = cfg.tandaIntervalSec or 8

    if total <= 0 then
        estado.fase = "activa"; estado.zombiesTotal = 0; estado.zombiesRestantes = 0
        HoldoorServer.notificarTodos("oleadaActiva", { numero=oleada, zombies=0, normales=0, speedrunners=0 })
        HoldoorServer._oleadaCompletada()
        return
    end

    local amenazaTexto = composicion[#composicion].texto
    local frase     = HoldoorConfig.frases[ZombRand(#HoldoorConfig.frases) + 1]
    local esUltima  = (oleada >= (cfg.maxOleadas or 0))

    print("[Holdoor] OLEADA " .. oleada .. (esUltima and " [ULTIMA]" or "") .. ": " .. cantidad .. "N + " .. srCount .. "SR = " .. total)

    HoldoorServer.notificarTodos("oleada", {
        numero=oleada, cantidad=cantidad, speedrunners=srCount,
        total=total, frase=frase.texto, autor=frase.autor, amenaza=amenazaTexto,
        esUltima=esUltima,
    })

    estado.fase             = "activa"
    estado.zombiesTotal     = total
    estado.zombiesRestantes = total
    estado.ultimoSonidoSec  = os.time()

    HoldoorServer._spawnTanda()

    HoldoorServer.notificarTodos("oleadaActiva", {
        numero=oleada, zombies=total, normales=cantidad, speedrunners=srCount,
    })
end

-- ─────────────────────────────────────────────
--  LIMPIEZA DE ZONA — elimina zombies vivos del mapa en el area de la base
-- ─────────────────────────────────────────────

-- ─────────────────────────────────────────────
--  RE-AGGRO — refresca el target de zombis cercanos a la base
--  Para que los que se quedaron quietos o se distrajeron vuelvan al combate
-- ─────────────────────────────────────────────

function HoldoorServer._reAggroZombies()
    local estado = HoldoorServer.estado
    if estado.fase ~= "activa" then return end

    local bx = estado.baseX
    local by = estado.baseY
    local bz = estado.baseZ
    local radio = math.floor((estado.config.radioSpawn or 20) + 15)

    local ok_cell, cell = pcall(getCell)
    if not ok_cell or not cell then return end

    local repathed = 0
    local destRadio = math.max(2, math.floor((estado.config.radioSpawn or 20) * 0.3))

    for dx = -radio, radio do
        for dy = -radio, radio do
            if dx * dx + dy * dy <= radio * radio then
                local ok_sq, sq = pcall(function() return cell:getGridSquare(bx + dx, by + dy, bz) end)
                if ok_sq and sq then
                    local ok_mo, objs = pcall(function() return sq:getMovingObjects() end)
                    if ok_mo and objs then
                        local ok_sz, sz = pcall(function() return objs:size() end)
                        if ok_sz and sz then
                            for i = 0, sz - 1 do
                                local ok_g, obj = pcall(function() return objs:get(i) end)
                                if ok_g and obj and instanceof(obj, "IsoZombie") then
                                    -- Nuevo objetivo aleatorio cerca de la base
                                    local angD = ZombRand(360)
                                    local dD   = ZombRand(destRadio + 1)
                                    local tx   = math.floor(bx + math.cos(math.rad(angD)) * dD)
                                    local ty   = math.floor(by + math.sin(math.rad(angD)) * dD)
                                    pcall(function() obj:pathToLocation(tx, ty, bz) end)
                                    repathed = repathed + 1
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if repathed > 0 then
        print("[Holdoor] Re-aggro: " .. repathed .. " zombies re-pathed hacia la base")
    end
end

function HoldoorServer._limpiarZona()
    local estado = HoldoorServer.estado
    local bx = estado.baseX
    local by = estado.baseY
    local bz = estado.baseZ
    local radio = math.floor((estado.config.radioSpawn or 20) + 12)

    local ok_cell, cell = pcall(getCell)
    if not ok_cell or not cell then return 0 end

    local eliminados = 0
    for dx = -radio, radio do
        for dy = -radio, radio do
            if dx * dx + dy * dy <= radio * radio then
                local ok_sq, sq = pcall(function() return cell:getGridSquare(bx + dx, by + dy, bz) end)
                if ok_sq and sq then
                    local toRemove = {}
                    local ok_mo, objs = pcall(function() return sq:getMovingObjects() end)
                    if ok_mo and objs then
                        local ok_sz, sz = pcall(function() return objs:size() end)
                        if ok_sz and sz then
                            for i = 0, sz - 1 do
                                local ok_get, obj = pcall(function() return objs:get(i) end)
                                if ok_get and obj and instanceof(obj, "IsoZombie") then
                                    table.insert(toRemove, obj)
                                end
                            end
                        end
                    end
                    for _, z in ipairs(toRemove) do
                        local ok_rm = pcall(function() z:removeFromWorld() end)
                        if ok_rm then eliminados = eliminados + 1 end
                    end
                end
            end
        end
    end

    if eliminados > 0 then
        print("[Holdoor] Zona limpiada antes de oleada: " .. eliminados .. " caminantes eliminados")
    end
    return eliminados
end


function HoldoorServer._oleadaCompletada()
    local estado = HoldoorServer.estado
    if estado.fase ~= "activa" then return end

    -- Bronce garantizado: base por zombies eliminados
    local bronze = math.max(1, math.floor((estado.zombiesTotal or 0) / 4)) + ZombRand(3)

    -- Tirada de drops extra segun el modo
    local rewardTbl = HoldoorConfig.rewardTable[estado.config.modoId or "normal"]
                    or HoldoorConfig.rewardTable.normal
    local bonusSilver = (ZombRand(100) < math.floor(rewardTbl.bonusSilverChance * 100)) and 1 or 0
    local bonusGold   = (ZombRand(100) < math.floor(rewardTbl.bonusGoldChance   * 100)) and 1 or 0

    HoldoorServer._distribuirMonedas(bronze, bonusSilver, bonusGold)

    -- Si fue la ultima oleada: ir directo a victoria, sin los 10s de pausa
    local esUltima = (estado.oleadaActual >= (estado.config.maxOleadas or 0))
    if esUltima then
        estado.killsOleada = {}
        HoldoorServer.detenerPorLimite(bonusSilver, bonusGold)
        return
    end

    estado.fase        = "pausa"
    estado.pausaFinSec = os.time() + PAUSA_SEGS

    local killsStr = buildKillsStr(estado.killsOleada)
    HoldoorServer.notificarTodos("oleadaCompletada", {
        numero    = estado.oleadaActual,
        pausa     = PAUSA_SEGS,
        killsStr  = killsStr,
        killsData = estado.killsOleada,
        bronze    = bronze,
        silver    = bonusSilver,
        gold      = bonusGold,
        lucky     = (bonusSilver + bonusGold) > 0,
    })

    -- Reset kills de oleada (pero no del total)
    estado.killsOleada = {}

    print("[Holdoor] Oleada " .. estado.oleadaActual .. " completada. Kills: " .. (killsStr ~= "" and killsStr or "sin datos"))
end

-- ─────────────────────────────────────────────
--  TICK — timer de tiempo real (no depende de game speed)
-- ─────────────────────────────────────────────

function HoldoorServer.onTick()
    local estado = HoldoorServer.estado

    -- Polling del HP del Trono + warnings + game over
    if estado.trono and estado.trono.piezas then
        local ahora = os.time()

        -- Damage boost server-side cada 2s en fase activa
        -- (compensa el daño muy bajo que hacen los zombis vanilla a thumpables)
        if estado.fase == "activa" and ahora >= (estado.ultimoDmgBoost or 0) + 2 then
            estado.ultimoDmgBoost = ahora
            HoldoorServer._aplicarDanoBoost()
        end

        -- HP polling cada 1s
        if ahora >= (estado.ultimoHPTick or 0) + 1 then
            estado.ultimoHPTick = ahora
            local totalHp = 0
            for _, p in ipairs(estado.trono.piezas) do
                local hp = 0
                pcall(function() hp = p.obj:getHealth() end)
                totalHp = totalHp + math.max(0, hp)
            end
            local maxHp = estado.trono.maxHP or 1500
            if totalHp ~= estado.tronoHP or maxHp ~= estado.tronoMaxHP then
                -- Warnings: avisar al pasar umbrales hacia abajo
                HoldoorServer._checkWarningsHP(estado.tronoHP or maxHp, totalHp, maxHp)

                estado.tronoHP = totalHp
                estado.tronoMaxHP = maxHp
                HoldoorServer.notificarTodos("tronoHP", { hp = totalHp, maxHp = maxHp })

                -- Game Over si modo defensa activado y trono cayo
                if totalHp <= 0 and estado.config.modoDefensa and estado.fase ~= "derrotado" then
                    HoldoorServer._tronoCayo()
                end
            end
        end
    end

    if not estado.activo then return end

    if estado.fase == "preparacion" then
        local ahora    = os.time()
        local restante = estado.countdownFinSec - ahora

        -- Aviso cuando quedan 30 segundos
        if not estado.avisoDado and restante <= 30 and restante > 0 then
            estado.avisoDado = true
            HoldoorServer.notificarTodos("aviso", {
                mensaje = "Proxima oleada en " .. math.ceil(restante) .. " segundos!"
            })
        end

        if restante <= 0 then
            HoldoorServer._lanzarOleada()
        end

    elseif estado.fase == "activa" then
        local ahora = os.time()

        -- Spawn de siguientes tandas escalonadas
        local remaining = 0
        for _, t in ipairs(estado.encoladosTiers or {}) do remaining = remaining + t.count end
        if remaining > 0 and ahora >= estado.proximaTandaSec then
            HoldoorServer._spawnTanda()
        end

        -- Pulso de sonido cada 7s: atrae zombis lejanos y los mantiene activos
        if ahora >= (estado.ultimoSonidoSec or 0) + 7 then
            estado.ultimoSonidoSec = ahora
            local bx = estado.baseX
            local by = estado.baseY
            local bz = estado.baseZ
            local r  = math.floor((estado.config.radioSpawn or 20) * 2 + 30)
            pcall(addSound, nil, bx, by, bz, r, 150)
        end

        -- Re-aggro cada 12s: re-path zombis cercanos hacia la base
        -- Refresca el objetivo de zombis que se distrajeron o llegaron y se quedaron quietos
        if ahora >= (estado.ultimoAggroSec or 0) + 12 then
            estado.ultimoAggroSec = ahora
            HoldoorServer._reAggroZombies()
        end

    elseif estado.fase == "pausa" then
        if os.time() >= estado.pausaFinSec then
            local maxOleadas = estado.config.maxOleadas or 0
            if maxOleadas > 0 and estado.oleadaActual >= maxOleadas then
                HoldoorServer.detenerPorLimite()
            else
                HoldoorServer._iniciarPreparacion()
            end
        end
    end
end

-- ─────────────────────────────────────────────
--  KILL COUNTER — avanza cuando se mata un zombi
-- ─────────────────────────────────────────────

function HoldoorServer.onZombieMuerto(zombie)
    local estado = HoldoorServer.estado
    if estado.fase ~= "activa" then return end

    -- Ignorar muertes de zombies que mueren lejos de la base (mundo normal)
    local ok, zx, zy = pcall(function() return zombie:getX(), zombie:getY() end)
    if ok and zx then
        local dx = zx - estado.baseX
        local dy = zy - estado.baseY
        local radioFiltro = (estado.config.radioSpawn or 20) + 40
        if (dx * dx + dy * dy) > (radioFiltro * radioFiltro) then return end
    end

    estado.zombiesRestantes = math.max(0, estado.zombiesRestantes - 1)

    HoldoorServer.notificarTodos("zombiesMuertos", {
        restantes = estado.zombiesRestantes,
        total     = estado.zombiesTotal,
    })

    if estado.zombiesRestantes <= 0 then
        HoldoorServer._oleadaCompletada()
    end
end

-- ─────────────────────────────────────────────
--  COMPOSICION — progresión de velocidad por oleada
-- ─────────────────────────────────────────────

function HoldoorServer.calcularComposicion(oleada, total)
    -- TEST MODE: composicion fija por oleada para facilitar pruebas
    if HoldoorServer.estado.config.testMode then
        if oleada == 1 then
            return {{count=total, speed=1, crawl=0,   texto="[TEST] Lentos"}}
        elseif oleada == 2 then
            return {{count=total, speed=1, crawl=100, texto="[TEST] Arrastradores"}}
        else
            return {{count=total, speed=3, crawl=0,   texto="[TEST] Rapidos"}}
        end
    end

    -- speed 4 (sprinters) eliminado — demasiado buggy e injugable
    -- Tiers: Muertos (s1,c0) | Arrastradores (s1,c100) | Rapidos (s3,c0)
    local tiers
    if oleada <= 3 then
        -- Solo muertos lentos
        tiers = { {count=total, speed=1, crawl=0,   texto="Muertos vivientes"} }
    elseif oleada <= 5 then
        -- Aparecen arrastradores (bajos, dificiles de ver)
        local c = math.floor(total * 0.15)
        tiers = { {count=total-c, speed=1, crawl=0,   texto="Muertos vivientes"},
                  {count=c,       speed=1, crawl=100,  texto="Arrastradores"} }
    elseif oleada <= 8 then
        -- Suman rapidos
        local c = math.floor(total * 0.15)
        local r = math.floor(total * 0.25)
        tiers = { {count=total-c-r, speed=1, crawl=0,   texto="Muertos vivientes"},
                  {count=c,         speed=1, crawl=100,  texto="Arrastradores"},
                  {count=r,         speed=3, crawl=0,    texto="Rapidos"} }
    else
        -- Oleadas finales: mas arrastradores, mas rapidos
        local c = math.floor(total * 0.20)
        local r = math.floor(total * 0.35)
        local sh = math.max(0, total - c - r)
        tiers = { {count=sh, speed=1, crawl=0,   texto="Muertos vivientes"},
                  {count=c,  speed=1, crawl=100,  texto="Arrastradores"},
                  {count=r,  speed=3, crawl=0,    texto="Rapidos"} }
    end
    local result = {}
    for _, t in ipairs(tiers) do
        if t.count > 0 then table.insert(result, t) end
    end
    return result
end

-- ─────────────────────────────────────────────
--  SPAWN — B42: addZombiesInOutfit (API nativa)
-- ─────────────────────────────────────────────

function HoldoorServer.spawnZombie(x, y, z)
    local ok = pcall(addZombiesInOutfit, x, y, z, 1, nil, nil)
    return ok
end

-- ─────────────────────────────────────────────
--  POSICION DE LA BASE
-- ─────────────────────────────────────────────

function HoldoorServer.setBase(jugador, x, y, z)
    local estado        = HoldoorServer.estado
    estado.baseX        = math.floor(x)
    estado.baseY        = math.floor(y)
    estado.baseZ        = math.floor(z)
    estado.baseDefinida = true
    HoldoorServer._plantarTrono(estado.baseX, estado.baseY, estado.baseZ)
    HoldoorServer.notificarTodos("baseActualizada", { x = estado.baseX, y = estado.baseY, z = estado.baseZ })
    print("[Holdoor] Base definida en " .. estado.baseX .. "," .. estado.baseY .. " por " .. jugador:getUsername())
end

-- ─────────────────────────────────────────────
--  BANDERA — objeto fisico en el suelo que marca la base
-- ─────────────────────────────────────────────

-- Items candidatos: foco en barriles/braseros/objetos visibles.
-- Probamos una lista AMPLIA porque B42 cambio nombres respecto a B41.
HoldoorServer._banderaItems = {
    -- Braseros / fuego (preferidos por tematica)
    "Base.BBQ",
    "Base.BarbecueLight",
    "Base.Barbecue",
    "Base.CampfireKit",
    "Base.Campfire",
    "Base.BurningTorch",
    "Base.LampOnPillar",
    "Base.OldStove",
    -- Barriles / contenedores grandes
    "Base.BarrelFire",
    "Base.OilBarrel",
    "Base.MetalDrum",
    "Base.PetrolCan",
    "Base.PaintbucketEmpty",
    "Base.Generator",
    -- Vanilla 100% seguros (fallback)
    "Base.Hammer",
    "Base.Plank",
    "Base.Newspaper",
    "Base.WoodenStick",
    "Base.Bandage",
}

-- Desactivada: usar _plantarBrasero en su lugar
function HoldoorServer._plantarBandera(x, y, z)
    return false  -- no-op
end

-- ─────────────────────────────────────────────
--  TRONO DE HIERRO — estructura 2x2 (4 piezas) con HP combinado
--  Los zombis pueden golpearlo desde cualquier lado. HP total = suma de las 4 piezas.
-- ─────────────────────────────────────────────

-- Sprites candidatos para las piezas del Trono.
-- PRIORIDAD: sillas/sofas (look "asiento real"), luego muebles, luego fallbacks.
HoldoorServer._tronoSprites = {
    -- Sofas / asientos grandes (look "trono")
    "furniture_seating_indoor_couches_01_8",
    "furniture_seating_indoor_couches_01_16",
    "furniture_seating_indoor_couches_01_24",
    "furniture_seating_indoor_couches_01_32",
    "furniture_seating_indoor_couches_01_40",
    -- Sillas indoor (chair-like)
    "furniture_seating_indoor_general_01_8",
    "furniture_seating_indoor_general_01_16",
    "furniture_seating_indoor_general_01_24",
    "furniture_seating_indoor_general_01_32",
    "furniture_seating_indoor_general_01_40",
    -- Sillas outdoor
    "furniture_seating_outdoor_01_8",
    "furniture_seating_outdoor_01_16",
    "furniture_seating_outdoor_01_24",
    -- Postes de luz (PROBADO visible, fallback intermedio)
    "lighting_outdoor_01_8",
    "lighting_outdoor_01_16",
    "lighting_outdoor_01_24",
    -- Muros exteriores
    "walls_exterior_brick_01_8",
    "walls_exterior_brick_01_16",
    -- Industrial / metal
    "industry_railroad_01_8",
    "industry_01_8",
    -- Muros de carpinteria (fallback garantizado de renderizar)
    "carpentry_02_56",
    "carpentry_02_64",
}

-- Sprites legacy (compat - apunta a la nueva variable)
HoldoorServer._braseroSprites = {
    -- Postes de luz outdoor (altos como un brasero sobre poste)
    "lighting_outdoor_01_8",
    "lighting_outdoor_01_16",
    "lighting_outdoor_01_24",
    "lighting_outdoor_01_32",
    -- Crafted (hogueras, sandbags, items construidos)
    "crafted_01_8",
    "crafted_01_16",
    "crafted_01_24",
    "crafted_01_40",
    "crafted_01_48",
    "crafted_01_56",
    -- Camping (campfires y similares)
    "camping_01_8",
    "camping_01_16",
    "camping_01_24",
    "camping_01_32",
    -- Barriles / objetos industriales
    "industry_railroad_01_8",
    "industry_railroad_01_24",
    "industry_railroad_01_32",
    "industry_01_8",
    "industry_01_24",
    -- Construcciones (sandbags, etc.)
    "constructedobjects_01_8",
    "constructedobjects_01_24",
    -- FALLBACK garantizado: muros de carpinteria
    "carpentry_02_56",
    "carpentry_02_64",
}

-- TRONO DE HIERRO: estructura 2x2 (4 piezas) con HP combinado.
-- Cada pieza es un IsoThumpable. HP total = suma de las 4 piezas (1500 = 375 c/u).
-- Zombis pueden golpearlo desde cualquier lado.
function HoldoorServer._plantarTrono(x, y, z)
    HoldoorServer._quitarTrono()

    print("[Holdoor] === _plantarTrono === (" .. x .. "," .. y .. "," .. z .. ")")

    local ok_cell, cell = pcall(getCell)
    if not ok_cell or not cell then
        print("[Holdoor] FAIL: no cell")
        return false
    end

    -- 4 posiciones en 2x2 ancladas en (x, y)
    local offsets = { {0,0}, {1,0}, {0,1}, {1,1} }
    local HP_POR_PIEZA = 375

    local cfg = {
        name                = "Trono de Hierro",
        modData             = {},
        thumpDmg            = 0,
        health              = HP_POR_PIEZA,
        maxHealth           = HP_POR_PIEZA,
        canBarricade        = false,
        isBlockAllTheSquare = true,
        isCorner            = false,
        isThumpable         = true,
        canBePlastered      = false,
        canPassThrough      = false,
        isDismantable       = false,
        Material            = "Metal",
        MaterialEng         = "Metal",
    }

    -- Helper: verifica que el sprite EXISTE en este build de B42 antes de usarlo.
    -- Sin esto, IsoThumpable.new acepta nombres inventados y crea objetos invisibles.
    local function spriteExiste(name)
        local s
        pcall(function() s = IsoSpriteManager.instance:getSprite(name) end)
        if s then return s end
        pcall(function() s = getSprite(name) end)
        if s then return s end
        return nil
    end

    for _, sprite in ipairs(HoldoorServer._tronoSprites) do
        local spriteObj = spriteExiste(sprite)
        if spriteObj then
            print("[Holdoor] Trono: sprite valido encontrado: " .. sprite)
            local piezas = {}
            local allOk = true

            for _, off in ipairs(offsets) do
                local px = x + off[1]
                local py = y + off[2]
                local ok_sq, sq = pcall(function() return cell:getGridSquare(px, py, z) end)
                if not ok_sq or not sq then allOk = false; break end

                local thumpable
                pcall(function() thumpable = IsoThumpable.new(cell, sq, sprite, false, cfg) end)
                if not thumpable then
                    pcall(function() thumpable = IsoThumpable:new(cell, sq, sprite, false, cfg) end)
                end
                if not thumpable then allOk = false; break end

                -- Forzar el sprite directamente sobre el objeto (no solo por nombre)
                pcall(function() thumpable:setSprite(spriteObj) end)

                local added = false
                pcall(function() sq:AddSpecialObject(thumpable); added = true end)
                if not added then pcall(function() sq:AddObject(thumpable); added = true end) end
                if not added then allOk = false; break end

                pcall(function() thumpable:setMaxHealth(HP_POR_PIEZA) end)
                pcall(function() thumpable:setHealth(HP_POR_PIEZA) end)
                pcall(function() sq:RecalcAllWithNeighbours(true) end)

                table.insert(piezas, { obj = thumpable, x = px, y = py, z = z })
            end  -- for off

            if allOk and #piezas == 4 then
                HoldoorServer.estado.trono = {
                    piezas = piezas,
                    sprite = sprite,
                    x = x, y = y, z = z,
                    maxHP = HP_POR_PIEZA * 4,
                }
                HoldoorServer.estado.brasero = piezas[1].obj
                HoldoorServer.estado.banderaTile = { x = x, y = y, z = z, sprite = sprite, isTrono = true }
                print("[Holdoor] OK Trono de Hierro plantado en " .. x .. "," .. y .. " (sprite: " .. sprite .. ")")
                return true
            else
                -- Rollback: limpiar piezas parciales si alguna fallo
                for _, p in ipairs(piezas) do
                    pcall(function() p.obj:removeFromSquare() end)
                end
            end
        end  -- if spriteObj
    end  -- for sprite

    print("[Holdoor] FAIL: ningun sprite valido encontrado para el Trono en este build de B42")
    return false
end

function HoldoorServer._quitarTrono()
    local t = HoldoorServer.estado.trono
    HoldoorServer.estado.trono = nil
    HoldoorServer.estado.brasero = nil
    HoldoorServer.estado.banderaTile = nil
    HoldoorServer.estado.tronoHP = nil
    HoldoorServer.estado.tronoMaxHP = nil

    if not t then return end
    for _, p in ipairs(t.piezas or {}) do
        pcall(function() p.obj:removeFromSquare() end)
        pcall(function() p.obj:removeFromWorld() end)
    end
end

-- Aliases legacy: si algun codigo viejo llama _plantarBrasero/_quitarBrasero, redirige
HoldoorServer._plantarBrasero = HoldoorServer._plantarTrono
HoldoorServer._quitarBrasero = HoldoorServer._quitarTrono

-- ─────────────────────────────────────────────
--  DAÑO BOOST — aplica daño extra a las piezas del Trono por cada zombi adyacente.
--  Compensa el daño bajo que zombis vanilla hacen a IsoThumpables.
--  Se llama cada 2s desde onTick durante fase activa.
-- ─────────────────────────────────────────────

-- Daño por zombi adyacente por ciclo (cada 2s), escalado por modo
HoldoorServer._damagePerZombi = {
    facil = 1, normal = 2, dificil = 4, pesadilla = 8, test = 5,
}

function HoldoorServer._aplicarDanoBoost()
    local estado = HoldoorServer.estado
    if not estado.trono or not estado.trono.piezas then return end

    local dmgPerZombi = HoldoorServer._damagePerZombi[estado.config.modoId or "normal"] or 2

    local ok_cell, cell = pcall(getCell)
    if not ok_cell or not cell then return end

    local totalDmg = 0
    for _, p in ipairs(estado.trono.piezas) do
        local hp = 0
        pcall(function() hp = p.obj:getHealth() end)
        if hp > 0 then
            -- Contar zombis en tiles adyacentes (8 alrededor)
            local nZombis = 0
            for dx = -1, 1 do
                for dy = -1, 1 do
                    if not (dx == 0 and dy == 0) then
                        local ok_sq, sq = pcall(function() return cell:getGridSquare(p.x + dx, p.y + dy, p.z) end)
                        if ok_sq and sq then
                            local objs
                            pcall(function() objs = sq:getMovingObjects() end)
                            if objs then
                                local sz = 0
                                pcall(function() sz = objs:size() end)
                                for i = 0, sz - 1 do
                                    local obj
                                    pcall(function() obj = objs:get(i) end)
                                    if obj and instanceof(obj, "IsoZombie") then
                                        local muerto = false
                                        pcall(function() muerto = obj:isDead() end)
                                        if not muerto then
                                            nZombis = nZombis + 1
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end

            if nZombis > 0 then
                local dmg = nZombis * dmgPerZombi
                local nuevoHp = math.max(0, hp - dmg)
                pcall(function() p.obj:setHealth(nuevoHp) end)
                totalDmg = totalDmg + dmg
            end
        end
    end

    if totalDmg > 0 then
        print("[Holdoor] Damage boost: -" .. totalDmg .. " HP al Trono")
    end
end

-- ─────────────────────────────────────────────
--  WARNINGS HP — avisa al pasar umbrales hacia abajo (60%, 30%, 10%)
-- ─────────────────────────────────────────────

HoldoorServer._warningThresholds = {
    { pct = 60, msg = "EL TRONO ESTA SIENDO ATACADO",          color = "amarillo" },
    { pct = 30, msg = "PELIGRO! EL TRONO ESTA POR CAER",       color = "rojo" },
    { pct = 10, msg = "ULTIMA LINEA DE DEFENSA! EL TRONO RESISTE", color = "critico" },
}

function HoldoorServer._checkWarningsHP(prevHp, currentHp, maxHp)
    if not maxHp or maxHp <= 0 then return end
    local prevPct = (prevHp / maxHp) * 100
    local currPct = (currentHp / maxHp) * 100

    for _, t in ipairs(HoldoorServer._warningThresholds) do
        if prevPct > t.pct and currPct <= t.pct then
            HoldoorServer.notificarTodos("warningTrono", {
                msg = t.msg,
                pct = t.pct,
                color = t.color,
                hp = currentHp,
                maxHp = maxHp,
            })
        end
    end
end

-- ─────────────────────────────────────────────
--  TRONO CAIDO — Game Over al llegar HP 0 con modo defensa activo
-- ─────────────────────────────────────────────

function HoldoorServer._tronoCayo()
    local estado = HoldoorServer.estado
    if estado.fase == "derrotado" then return end

    estado.activo           = false
    estado.fase             = "derrotado"
    estado.zombiesRestantes = 0
    estado.zombiesTotal     = 0
    estado.encoladosTiers   = {}

    print("[Holdoor] !!! EL TRONO HA CAIDO !!! Game Over (modo defensa)")

    HoldoorServer.notificarTodos("tronoCayo", {
        oleadas = estado.oleadaActual or 0,
    })

    estado.ownerUsername = nil
end

function HoldoorServer._quitarBandera()
    local b = HoldoorServer.estado.banderaTile
    if not b then return end
    HoldoorServer.estado.banderaTile = nil

    local ok_cell, cell = pcall(getCell)
    if not ok_cell or not cell then return end
    local ok_sq, sq = pcall(function() return cell:getGridSquare(b.x, b.y, b.z) end)
    if not ok_sq or not sq then return end

    -- Iterar inventario del tile y remover el item que matchee
    pcall(function()
        local objs = sq:getWorldObjects()
        if not objs then return end
        for i = objs:size() - 1, 0, -1 do
            local obj = objs:get(i)
            if obj and obj.getItem then
                local ok2, it = pcall(function() return obj:getItem() end)
                if ok2 and it then
                    local ok3, ft = pcall(function() return it:getFullType() end)
                    if ok3 and ft == b.item then
                        pcall(function() sq:transmitRemoveItemFromSquare(obj) end)
                    end
                end
            end
        end
    end)
end

-- ─────────────────────────────────────────────
--  COMUNICACION CON CLIENTES
-- ─────────────────────────────────────────────

function HoldoorServer.notificarTodos(tipo, datos)
    local ok, players = pcall(getOnlinePlayers)
    if ok and players then
        local ok2, n = pcall(function() return players:size() end)
        if ok2 and n and n > 0 then
            for i = 0, n - 1 do
                local ok3, p = pcall(function() return players:get(i) end)
                if ok3 and p then
                    pcall(sendClientCommand, p, HoldoorConfig.MODULE, tipo, datos)
                end
            end
            return
        end
    end
    -- Fallback single player: llamar al cliente directamente
    if type(HoldoorClient) == "table" and HoldoorClient.onComandoServidor then
        pcall(HoldoorClient.onComandoServidor, HoldoorConfig.MODULE, tipo, datos)
    end
end

function HoldoorServer.enviarMensaje(jugador, texto)
    pcall(sendClientCommand, jugador, HoldoorConfig.MODULE, "mensaje", { texto = texto })
    if type(HoldoorClient) == "table" and HoldoorClient.chat then
        pcall(HoldoorClient.chat, "[HOLDOOR] " .. texto, 1, 0.6, 0.2)
    end
end

-- ─────────────────────────────────────────────
--  COMANDOS DE CLIENTES (multiplayer)
-- ─────────────────────────────────────────────

function HoldoorServer.onComandoCliente(modulo, comando, jugador, args)
    if modulo ~= HoldoorConfig.MODULE then return end
    print("[Holdoor] Servidor recibio comando: " .. tostring(comando))

    -- Nota: removimos el gate de admin general. Cualquier jugador puede usar el mod.
    -- Las restricciones aplican por accion:
    -- - iniciar/detener: solo si esta libre (iniciar) / solo el dueno (detener)
    -- - setBase / oleadaManual / pedirEstado / transferir / comprar: cualquiera

    if comando == "iniciar" then
        HoldoorServer.iniciar(jugador, args.config)

    elseif comando == "detener" then
        HoldoorServer.detener(jugador)

    elseif comando == "setBase" then
        HoldoorServer.setBase(jugador, args.x, args.y, args.z)

    elseif comando == "oleadaManual" then
        local est = HoldoorServer.estado
        if est.activo and est.fase ~= "activa" then
            HoldoorServer._lanzarOleada()
        elseif est.activo and est.fase == "activa" then
            HoldoorServer.enviarMensaje(jugador, "Ya hay una oleada en curso. Termina primero.")
        end

    elseif comando == "transferir" then
        HoldoorServer._transferirMonedas(jugador, args)

    elseif comando == "comprar" then
        HoldoorServer._comprar(jugador, args)

    elseif comando == "pedirEstado" then
        local estado = HoldoorServer.estado
        local ahora  = os.time()
        pcall(sendClientCommand, jugador, HoldoorConfig.MODULE, "estado", {
            activo            = estado.activo,
            fase              = estado.fase,
            oleadaActual      = estado.oleadaActual,
            zombiesRestantes  = estado.zombiesRestantes,
            zombiesTotal      = estado.zombiesTotal,
            countdownSegsLeft = math.max(0, estado.countdownFinSec - ahora),
            baseX             = estado.baseX,
            baseY             = estado.baseY,
            baseZ             = estado.baseZ,
            baseDefinida      = estado.baseDefinida,
            config            = estado.config,
        })
    end
end

-- ─────────────────────────────────────────────
--  REGISTRO DE EVENTOS
-- ─────────────────────────────────────────────

Events.OnGameStart.Add(HoldoorServer.init)
Events.OnTick.Add(HoldoorServer.onTick)
Events.OnZombieDead.Add(HoldoorServer.onZombieMuerto)
Events.OnClientCommand.Add(HoldoorServer.onComandoCliente)
