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
                                    -- Path a punto aleatorio cerca de la base (no directo a la forja)
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

-- ─────────────────────────────────────────────
-- COLCHÓN DE ZOMBIS: garantiza una densidad mínima durante la oleada
-- Si los zombis vivos cerca de la base bajan del umbral Y todavía hay zombis
-- en cola, spawnea refuerzos inmediatos. Evita que el user tenga que ir
-- a buscar zombis lejanos en medio de una oleada.
-- ─────────────────────────────────────────────
HoldoorServer._colchonMinimo = 5  -- zombis vivos minimos en el radio durante fase activa

function HoldoorServer._asegurarColchon()
    local estado = HoldoorServer.estado
    if estado.fase ~= "activa" then return end

    -- Si no quedan zombis pendientes en cola, no spawnear refuerzo
    local pendientes = 0
    for _, t in ipairs(estado.encoladosTiers or {}) do pendientes = pendientes + t.count end
    if pendientes == 0 then return end

    -- Contar zombis vivos en el radio cerca de la base
    local bx, by, bz = estado.baseX, estado.baseY, estado.baseZ
    local radio = math.floor((estado.config.radioSpawn or 20) + 10)

    local ok_cell, cell = pcall(getCell)
    if not ok_cell or not cell then return end

    local vivos = 0
    for dx = -radio, radio do
        for dy = -radio, radio do
            if dx * dx + dy * dy <= radio * radio then
                local sq
                pcall(function() sq = cell:getGridSquare(bx + dx, by + dy, bz) end)
                if sq then
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
                                if not muerto then vivos = vivos + 1 end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Si los vivos bajaron del colchon minimo, forzar la proxima tanda YA
    -- (en vez de esperar al timing normal de tandaIntervalSec)
    local minimo = HoldoorServer._colchonMinimo or 5
    if vivos < minimo then
        local faltan = math.min(minimo - vivos, pendientes)
        print(string.format("[Holdoor] Colchon: solo %d vivos (min %d), forzando refuerzo de %d", vivos, minimo, faltan))
        -- Adelantar el timing de la proxima tanda
        estado.proximaTandaSec = os.time() - 1
        -- Reducir el tamano de tanda al refuerzo necesario (temporal)
        local origTamanoTanda = estado.tamanoTanda
        estado.tamanoTanda = faltan
        HoldoorServer._spawnTanda()
        estado.tamanoTanda = origTamanoTanda
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

    -- Limpiar zombis vivos del radio antes de pausa: evita que queden vagando
    -- y obliguen al user a salir a buscarlos durante el descanso.
    local eliminadosFinOleada = HoldoorServer._limpiarZona()
    if eliminadosFinOleada > 0 then
        print("[Holdoor] Fin de oleada: " .. eliminadosFinOleada .. " zombis residuales limpiados")
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
        -- HP del Trono = SOLO el HP de la pieza central (forja).
        -- Las barricadas se rompen individualmente pero NO afectan al HP del Trono.
        if ahora >= (estado.ultimoHPTick or 0) + 1 then
            estado.ultimoHPTick = ahora
            local centro = estado.trono.piezaCentral
            local hpCentro = 0
            if centro and centro.obj then
                pcall(function() hpCentro = centro.obj:getHealth() end)
                hpCentro = math.max(0, hpCentro)
            end
            local maxHp = estado.trono.maxHP or 1500
            if hpCentro ~= estado.tronoHP or maxHp ~= estado.tronoMaxHP then
                HoldoorServer._checkWarningsHP(estado.tronoHP or maxHp, hpCentro, maxHp)

                estado.tronoHP = hpCentro
                estado.tronoMaxHP = maxHp
                HoldoorServer.notificarTodos("tronoHP", { hp = hpCentro, maxHp = maxHp })

                -- Game Over: forja a 0 = Trono caido
                if hpCentro <= 0 and estado.config.modoDefensa and estado.fase ~= "derrotado" then
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

        -- Colchón de densidad cada 3s: si los zombis vivos cerca bajan demasiado
        -- y todavía hay encolados, forzamos un refuerzo inmediato.
        if ahora >= (estado.ultimoColchonSec or 0) + 3 then
            estado.ultimoColchonSec = ahora
            HoldoorServer._asegurarColchon()
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
-- IMPORTANTE: en B42, los sprites INDOOR requieren estar dentro de un IsoRoom para
-- renderizar bien. Por eso usamos SOLO outdoor / furniture exterior / crafted / fences.
HoldoorServer._tronoSprites = {
    -- ────────────────────────────────────────
    -- SILLAS / ASIENTOS OUTDOOR (mejor look para trono)
    -- ────────────────────────────────────────
    "furniture_seating_outdoor_01_0",
    "furniture_seating_outdoor_01_4",
    "furniture_seating_outdoor_01_8",
    "furniture_seating_outdoor_01_12",
    "furniture_seating_outdoor_01_16",
    "furniture_seating_outdoor_01_20",
    "furniture_seating_outdoor_01_24",
    "furniture_seating_outdoor_01_28",
    "furniture_seating_outdoor_01_32",
    "furniture_seating_outdoor_01_36",
    "furniture_seating_outdoor_01_40",
    -- ────────────────────────────────────────
    -- FURNITURE OUTDOOR GENERAL
    -- ────────────────────────────────────────
    "furniture_outdoor_01_0",
    "furniture_outdoor_01_4",
    "furniture_outdoor_01_8",
    "furniture_outdoor_01_12",
    "furniture_outdoor_01_16",
    "furniture_outdoor_01_20",
    "furniture_outdoor_01_24",
    "furniture_outdoor_01_28",
    "furniture_outdoor_general_01_0",
    "furniture_outdoor_general_01_4",
    "furniture_outdoor_general_01_8",
    "furniture_outdoor_general_01_12",
    -- ────────────────────────────────────────
    -- CONSTRUCTED OBJECTS (sandbags, barricadas, cosas crafteadas grandes)
    -- ────────────────────────────────────────
    "constructedobjects_01_0",
    "constructedobjects_01_4",
    "constructedobjects_01_8",
    "constructedobjects_01_12",
    "constructedobjects_01_16",
    "constructedobjects_01_20",
    "constructedobjects_01_24",
    "constructedobjects_01_28",
    "constructedobjects_01_32",
    -- ────────────────────────────────────────
    -- CRAFTED (hogueras, items construidos a mano)
    -- ────────────────────────────────────────
    "crafted_01_0",
    "crafted_01_4",
    "crafted_01_8",
    "crafted_01_12",
    "crafted_01_16",
    "crafted_01_20",
    "crafted_01_24",
    "crafted_01_28",
    "crafted_01_32",
    "crafted_01_40",
    "crafted_01_48",
    "crafted_01_56",
    -- ────────────────────────────────────────
    -- CAMPING (campfires, carpas, equipo exterior)
    -- ────────────────────────────────────────
    "camping_01_0",
    "camping_01_4",
    "camping_01_8",
    "camping_01_12",
    "camping_01_16",
    "camping_01_20",
    "camping_01_24",
    "camping_01_28",
    "camping_01_32",
    -- ────────────────────────────────────────
    -- INDUSTRIAL OUTDOOR (cosas grandes, metálicas, imponentes)
    -- ────────────────────────────────────────
    "industry_railroad_01_0",
    "industry_railroad_01_4",
    "industry_railroad_01_8",
    "industry_railroad_01_12",
    "industry_railroad_01_16",
    "industry_railroad_01_20",
    "industry_railroad_01_24",
    "industry_railroad_01_28",
    "industry_railroad_01_32",
    "industry_01_0",
    "industry_01_4",
    "industry_01_8",
    "industry_01_12",
    "industry_01_16",
    "industry_01_20",
    "industry_01_24",
    -- ────────────────────────────────────────
    -- LIGHTING OUTDOOR (postes, faroles — verticales imponentes)
    -- ────────────────────────────────────────
    "lighting_outdoor_01_0",
    "lighting_outdoor_01_4",
    "lighting_outdoor_01_8",
    "lighting_outdoor_01_12",
    "lighting_outdoor_01_16",
    "lighting_outdoor_01_20",
    "lighting_outdoor_01_24",
    "lighting_outdoor_01_28",
    -- ────────────────────────────────────────
    -- VEHICLES / DECORATIVO (partes de auto, estatuas)
    -- ────────────────────────────────────────
    "vehicles_01_0",
    "vehicles_01_4",
    "vehicles_01_8",
    "vehicles_01_12",
    "recreational_sports_01_0",
    "recreational_sports_01_4",
    "recreational_sports_01_8",
    "recreational_sports_01_12",
    -- ────────────────────────────────────────
    -- WALLS / FENCES (paredes exteriores, cercas — para "trono de cien espadas")
    -- ────────────────────────────────────────
    "walls_exterior_brick_01_0",
    "walls_exterior_brick_01_4",
    "walls_exterior_brick_01_8",
    "walls_exterior_brick_01_12",
    "walls_exterior_wooden_01_0",
    "walls_exterior_wooden_01_4",
    "walls_exterior_wooden_01_8",
    "fencing_01_0",
    "fencing_01_4",
    "fencing_01_8",
    "fencing_01_12",
    "fencing_01_16",
    "fencing_01_20",
    "fencing_01_24",
    "fencing_01_28",
    "fencing_01_32",
    -- ────────────────────────────────────────
    -- CARPENTRY (cosas construidas con carpinteria — fallback ultimo)
    -- ────────────────────────────────────────
    "carpentry_01_0",
    "carpentry_01_4",
    "carpentry_01_8",
    "carpentry_01_12",
    "carpentry_01_16",
    "carpentry_02_0",
    "carpentry_02_8",
    "carpentry_02_16",
    "carpentry_02_24",
    "carpentry_02_32",
    "carpentry_02_40",
    "carpentry_02_48",
    "carpentry_02_56",
    "carpentry_02_64",
}

-- ─────────────────────────────────────────────
-- TESTER de sprite en vivo
-- Uso desde Lua Command Line del debugger:
--   HoldoorServer.testSprite("furniture_seating_indoor_couches_01_12")
-- Quita el Trono actual y lo replanta con ESE sprite en la misma posicion.
-- Si no hay Trono plantado, lo planta en la base actual.
-- ─────────────────────────────────────────────
function HoldoorServer.testSprite(nombreSprite)
    if type(nombreSprite) ~= "string" or nombreSprite == "" then
        print("[Holdoor] testSprite: pasame un nombre de sprite como string")
        return false
    end

    -- Validar que el sprite existe
    local s = nil
    pcall(function() s = IsoSpriteManager.instance:getSprite(nombreSprite) end)
    if not s then
        pcall(function() s = getSprite(nombreSprite) end)
    end
    if not s then
        print("[Holdoor] testSprite: '" .. nombreSprite .. "' NO EXISTE en este build.")
        return false
    end

    -- Posicion: si hay trono actual, reusar. Si no, base actual.
    local estado = HoldoorServer.estado
    local x, y, z
    if estado.trono and estado.trono.x then
        x, y, z = estado.trono.x, estado.trono.y, estado.trono.z
    elseif estado.baseX then
        x, y, z = estado.baseX, estado.baseY, estado.baseZ or 0
    else
        print("[Holdoor] testSprite: marca la base primero (F10 -> Marcar mi base).")
        return false
    end

    -- Forzar este sprite al frente de la lista y replantar
    HoldoorServer._tronoSprites_backup = HoldoorServer._tronoSprites_backup or HoldoorServer._tronoSprites
    HoldoorServer._tronoSprites = { nombreSprite }
    local ok = HoldoorServer._plantarTrono(x, y, z)
    -- Restaurar lista normal (para que un siguiente test use lista completa si falla este)
    HoldoorServer._tronoSprites = HoldoorServer._tronoSprites_backup
    if ok then
        print("[Holdoor] testSprite: Trono replantado con '" .. nombreSprite .. "' en (" .. x .. "," .. y .. "," .. z .. ")")
    else
        print("[Holdoor] testSprite: fallo al plantar con '" .. nombreSprite .. "'")
    end
    return ok
end

-- ─────────────────────────────────────────────
-- PRESETS de TRONO COMPUESTO (para el boton "DEJAR TRONO COMPUESTO AQUI")
-- Cada click avanza al siguiente preset, ciclando.
-- Si un sprite no existe en este build, el plantado va a fallar — en ese caso
-- ajustar el preset o probar manualmente con testTronoCompuesto.
-- ─────────────────────────────────────────────
-- ─────────────────────────────────────────────
-- MODO BUILDER MANUAL: el user planta tile por tile y despues exporta su diseño.
--
-- Workflow:
--   1) Pararse donde queres la PRIMER pieza del Trono.
--   2) Tipear en Lua Command Line:
--        HoldoorServer.dejarTile("furniture_seating_outdoor_01_32")
--      Esto planta UN solo tile en tu posicion con ese sprite.
--   3) Avanzar 1 tile (o donde quieras la siguiente pieza).
--   4) Tipear:
--        HoldoorServer.dejarTile("carpentry_02_40")
--   5) Repetir cuantas piezas quieras (no hay limite, ni tamaño fijo, ni forma fija).
--   6) Cuando termines, tipear:
--        HoldoorServer.dumpTrono()
--      Esto imprime en consola el codigo Lua exacto de tu Trono, que copio
--      al preset para usarlo de default.
--   7) (Opcional) LIMPIAR DEMOS para borrar lo construido.
-- ─────────────────────────────────────────────

function HoldoorServer.dejarTile(nombreSprite)
    if type(nombreSprite) ~= "string" or nombreSprite == "" then
        print("[Holdoor] dejarTile: pasame el nombre del sprite como string")
        return false
    end

    local p
    pcall(function() p = getSpecificPlayer(0) end)
    if not p then
        print("[Holdoor] dejarTile: no encontre al player local")
        return false
    end

    local x, y, z
    pcall(function()
        x = math.floor(p:getX())
        y = math.floor(p:getY())
        z = math.floor(p:getZ())
    end)
    if not x then return false end

    local cell
    pcall(function() cell = getCell() end)
    if not cell then return false end

    local function spriteExiste(name)
        local s
        pcall(function() s = IsoSpriteManager.instance:getSprite(name) end)
        if s then return s end
        pcall(function() s = getSprite(name) end)
        if s then return s end
        return nil
    end
    local spriteObj = spriteExiste(nombreSprite)
    if not spriteObj then
        print("[Holdoor] dejarTile: sprite '" .. nombreSprite .. "' NO EXISTE en este build")
        return false
    end

    local sq
    pcall(function() sq = cell:getGridSquare(x, y, z) end)
    if not sq then
        print("[Holdoor] dejarTile: no hay GridSquare en (" .. x .. "," .. y .. "," .. z .. ")")
        return false
    end

    local HP = 99999
    local cfg = {
        name                = "Builder: " .. nombreSprite,
        thumpDmg            = 0,
        health              = HP,
        maxHealth           = HP,
        canBarricade        = false,
        isBlockAllTheSquare = true,
        isCorner            = false,
        isThumpable         = false,
        canPassThrough      = false,
        Material            = "Metal",
        MaterialEng         = "Metal",
    }

    local thumpable
    pcall(function() thumpable = IsoThumpable.new(cell, sq, nombreSprite, false, cfg) end)
    if not thumpable then
        pcall(function() thumpable = IsoThumpable:new(cell, sq, nombreSprite, false, cfg) end)
    end
    if not thumpable then
        print("[Holdoor] dejarTile: no pude crear IsoThumpable con sprite '" .. nombreSprite .. "'")
        return false
    end

    pcall(function() thumpable:setSprite(spriteObj) end)
    local added = false
    pcall(function() sq:AddSpecialObject(thumpable); added = true end)
    if not added then pcall(function() sq:AddObject(thumpable); added = true end) end
    if not added then return false end

    pcall(function() thumpable:setMaxHealth(HP) end)
    pcall(function() thumpable:setHealth(HP) end)
    pcall(function() sq:RecalcAllWithNeighbours(true) end)

    -- Registrar como construccion manual (separado de los presets compuestos)
    HoldoorServer._builderTiles = HoldoorServer._builderTiles or {}
    table.insert(HoldoorServer._builderTiles, {
        sprite = nombreSprite, x = x, y = y, z = z, obj = thumpable,
    })

    -- Tambien agregar a galeriaTest para que LIMPIAR DEMOS lo borre
    HoldoorServer.estado.galeriaTest = HoldoorServer.estado.galeriaTest or {}
    table.insert(HoldoorServer.estado.galeriaTest, {
        idx = -1, sprite = "BUILDER: " .. nombreSprite,
        piezas = { { obj = thumpable, x = x, y = y, z = z } },
        x = x, y = y, z = z,
    })

    print(string.format("[Holdoor] BUILDER tile #%d  pos=(%d,%d)  sprite='%s'",
        #HoldoorServer._builderTiles, x, y, nombreSprite))
    return true
end

-- Mata todos los zombis dentro de un radio (default 25 tiles) alrededor del player.
-- Util cuando estas construyendo/testeando y los zombis joden.
-- Uso:  HoldoorServer.matarZombiesCerca()       -- radio 25
--       HoldoorServer.matarZombiesCerca(50)     -- radio 50
function HoldoorServer.matarZombiesCerca(radio)
    radio = radio or 25
    local p
    pcall(function() p = getSpecificPlayer(0) end)
    if not p then
        print("[Holdoor] matarZombiesCerca: no encontre al player local")
        return 0
    end

    local px = math.floor(p:getX())
    local py = math.floor(p:getY())
    local cell
    pcall(function() cell = getCell() end)
    if not cell then return 0 end

    local zombies
    pcall(function() zombies = cell:getZombieList() end)
    if not zombies then
        print("[Holdoor] matarZombiesCerca: cell sin zombieList")
        return 0
    end

    local n = 0
    pcall(function() n = zombies:size() end)

    local r2 = radio * radio
    local matados = 0
    for i = n - 1, 0, -1 do
        local z
        pcall(function() z = zombies:get(i) end)
        if z then
            local zx, zy
            pcall(function() zx = z:getX(); zy = z:getY() end)
            if zx and zy then
                local dx = zx - px
                local dy = zy - py
                if (dx*dx + dy*dy) <= r2 then
                    pcall(function() z:setHealth(0) end)
                    pcall(function() z:Kill(p) end)  -- fallback por si setHealth no alcanza
                    matados = matados + 1
                end
            end
        end
    end
    print(string.format("[Holdoor] matarZombiesCerca: %d zombis muertos en radio %d", matados, radio))
    return matados
end

-- APILAR un sprite en TU POSICION ACTUAL sin bloquear el tile.
-- Permite tener varios sprites en el MISMO (x, y, z), uno renderizado sobre el otro.
-- A diferencia de dejarTile (que usa isBlockAllTheSquare=true), esta version deja
-- el square "abierto" para que se pueda agregar otro objeto despues.
-- Uso:  HoldoorServer.apilarTile("crates_01_8")
function HoldoorServer.apilarTile(nombreSprite)
    if type(nombreSprite) ~= "string" or nombreSprite == "" then
        print("[Holdoor] apilarTile: pasame el nombre del sprite como string")
        return false
    end

    local p
    pcall(function() p = getSpecificPlayer(0) end)
    if not p then return false end

    local x, y, z
    pcall(function()
        x = math.floor(p:getX())
        y = math.floor(p:getY())
        z = math.floor(p:getZ())
    end)
    if not x then return false end

    local cell
    pcall(function() cell = getCell() end)
    if not cell then return false end

    local spriteObj
    pcall(function() spriteObj = IsoSpriteManager.instance:getSprite(nombreSprite) end)
    if not spriteObj then
        pcall(function() spriteObj = getSprite(nombreSprite) end)
    end
    if not spriteObj then
        print("[Holdoor] apilarTile: sprite '" .. nombreSprite .. "' NO EXISTE")
        return false
    end

    local sq
    pcall(function() sq = cell:getGridSquare(x, y, z) end)
    if not sq then return false end

    local HP = 99999
    local cfg = {
        name                = "Apilado: " .. nombreSprite,
        thumpDmg            = 0,
        health              = HP,
        maxHealth           = HP,
        canBarricade        = false,
        isBlockAllTheSquare = false,   -- CLAVE: permitir mas objetos en este square
        isCorner            = false,
        isThumpable         = false,
        canPassThrough      = true,    -- no bloquear movimiento del player
        Material            = "Wood",
        MaterialEng         = "Wood",
    }

    local thumpable
    pcall(function() thumpable = IsoThumpable.new(cell, sq, nombreSprite, false, cfg) end)
    if not thumpable then
        pcall(function() thumpable = IsoThumpable:new(cell, sq, nombreSprite, false, cfg) end)
    end
    if not thumpable then
        print("[Holdoor] apilarTile: no pude crear IsoThumpable")
        return false
    end

    pcall(function() thumpable:setSprite(spriteObj) end)
    local added = false
    pcall(function() sq:AddSpecialObject(thumpable); added = true end)
    if not added then pcall(function() sq:AddObject(thumpable); added = true end) end
    if not added then return false end

    pcall(function() thumpable:setMaxHealth(HP) end)
    pcall(function() thumpable:setHealth(HP) end)
    pcall(function() sq:RecalcAllWithNeighbours(true) end)

    HoldoorServer._builderTiles = HoldoorServer._builderTiles or {}

    -- Contar cuantos objetos APILADOS ya hay en este mismo tile (antes de agregar el actual)
    local apiladosPrevios = 0
    for _, t in ipairs(HoldoorServer._builderTiles) do
        if t.x == x and t.y == y and t.z == z then apiladosPrevios = apiladosPrevios + 1 end
    end

    -- Aplicar offset visual hacia ARRIBA proporcional a la altura del stack.
    -- Cada "piso" sube ~32 pixeles en pantalla (que en mundo iso = una caja de altura).
    -- setOffsetY con valor NEGATIVO mueve el sprite hacia arriba en pantalla.
    local OFFSET_POR_PISO = 32
    local offsetVisual = apiladosPrevios * OFFSET_POR_PISO
    if offsetVisual > 0 then
        local apliado = false
        pcall(function() thumpable:setRenderYOffset(-offsetVisual); apliado = true end)
        if not apliado then
            pcall(function() thumpable:setOffsetY(-offsetVisual); apliado = true end)
        end
        if not apliado then
            -- Fallback: tratar de hacerlo sobre el IsoSprite directamente
            pcall(function() thumpable:getSprite():setOffsetY(-offsetVisual) end)
        end
    end

    table.insert(HoldoorServer._builderTiles, {
        sprite = nombreSprite, x = x, y = y, z = z, obj = thumpable, apilado = true,
        offsetVisual = offsetVisual,
    })

    HoldoorServer.estado.galeriaTest = HoldoorServer.estado.galeriaTest or {}
    table.insert(HoldoorServer.estado.galeriaTest, {
        idx = -2, sprite = "APILADO: " .. nombreSprite,
        piezas = { { obj = thumpable, x = x, y = y, z = z } },
        x = x, y = y, z = z,
    })

    print(string.format("[Holdoor] APILADO en (%d,%d): '%s'  piso=%d  offsetY=-%d",
        x, y, nombreSprite, apiladosPrevios + 1, offsetVisual))
    return true
end

-- Borra el ULTIMO tile que plantaste (Ctrl+Z del builder).
-- Uso:  HoldoorServer.deshacerTile()
function HoldoorServer.deshacerTile()
    local tiles = HoldoorServer._builderTiles
    if not tiles or #tiles == 0 then
        print("[Holdoor] deshacerTile: no hay tiles plantados para deshacer")
        return false
    end
    local ultimo = table.remove(tiles)
    pcall(function() ultimo.obj:removeFromSquare() end)
    pcall(function() ultimo.obj:removeFromWorld() end)
    -- Limpiar tambien de galeriaTest
    local gt = HoldoorServer.estado.galeriaTest or {}
    for i = #gt, 1, -1 do
        local g = gt[i]
        if g.piezas and #g.piezas == 1 and g.piezas[1].x == ultimo.x and g.piezas[1].y == ultimo.y then
            table.remove(gt, i)
            break
        end
    end
    print(string.format("[Holdoor] deshacerTile: borrado tile en (%d,%d) sprite='%s' (quedan %d)",
        ultimo.x, ultimo.y, ultimo.sprite, #tiles))
    return true
end

-- Borra el tile builder que este EN TU POSICION ACTUAL (si hay uno).
-- Util para corregir un tile especifico sin perder los demas.
-- Uso:  pararse encima del tile que quieras borrar, despues:
--       HoldoorServer.borrarTileAqui()
function HoldoorServer.borrarTileAqui()
    local p
    pcall(function() p = getSpecificPlayer(0) end)
    if not p then return false end
    local x, y
    pcall(function()
        x = math.floor(p:getX())
        y = math.floor(p:getY())
    end)
    if not x then return false end

    local tiles = HoldoorServer._builderTiles or {}
    for i = #tiles, 1, -1 do
        if tiles[i].x == x and tiles[i].y == y then
            local tile = table.remove(tiles, i)
            pcall(function() tile.obj:removeFromSquare() end)
            pcall(function() tile.obj:removeFromWorld() end)
            local gt = HoldoorServer.estado.galeriaTest or {}
            for j = #gt, 1, -1 do
                local g = gt[j]
                if g.piezas and #g.piezas == 1 and g.piezas[1].x == tile.x and g.piezas[1].y == tile.y then
                    table.remove(gt, j)
                    break
                end
            end
            print(string.format("[Holdoor] borrarTileAqui: borrado tile en (%d,%d) sprite='%s' (quedan %d)",
                x, y, tile.sprite, #tiles))
            return true
        end
    end
    print(string.format("[Holdoor] borrarTileAqui: no hay tile builder en (%d,%d). Caminate encima del tile a borrar primero.", x, y))
    return false
end

-- Mover el ULTIMO tile plantado a tu posicion actual (= deshacer + dejar con mismo sprite donde estas).
-- Util si te equivocaste de tile por uno o si lo querés correr a otro lado sin perder el sprite.
-- Uso:  HoldoorServer.moverUltimoAqui()
function HoldoorServer.moverUltimoAqui()
    local tiles = HoldoorServer._builderTiles
    if not tiles or #tiles == 0 then
        print("[Holdoor] moverUltimoAqui: no hay tiles plantados")
        return false
    end
    local sprite = tiles[#tiles].sprite
    HoldoorServer.deshacerTile()
    return HoldoorServer.dejarTile(sprite)
end

-- Imprime el codigo Lua del Trono construido manualmente.
-- Coordenadas relativas a la esquina superior izquierda (min x, min y).
function HoldoorServer.dumpTrono()
    local tiles = HoldoorServer._builderTiles or {}
    if #tiles == 0 then
        print("[Holdoor] dumpTrono: no hay tiles construidos. Usa dejarTile() primero.")
        return
    end

    -- Esquina superior izquierda (min x, min y)
    local minX, minY = tiles[1].x, tiles[1].y
    local maxX, maxY = tiles[1].x, tiles[1].y
    for _, t in ipairs(tiles) do
        if t.x < minX then minX = t.x end
        if t.y < minY then minY = t.y end
        if t.x > maxX then maxX = t.x end
        if t.y > maxY then maxY = t.y end
    end
    local ancho = (maxX - minX) + 1
    local alto  = (maxY - minY) + 1

    print("================================================================")
    print(string.format("[Holdoor] DUMP del Trono manual: %d tiles, area %dx%d", #tiles, ancho, alto))
    print(string.format("    desde (%d,%d) hasta (%d,%d)", minX, minY, maxX, maxY))
    print("================================================================")
    print("-- Pega esto al final de HoldoorServer._tronosCompuestos como un preset nuevo:")
    print("")
    print("    {")
    print('        nombre = "MI TRONO CUSTOM (' .. ancho .. 'x' .. alto .. ')",')
    print("        tiles = {")
    -- Imprime tile por tile con dx, dy y sprite
    for _, t in ipairs(tiles) do
        local dx = t.x - minX
        local dy = t.y - minY
        print(string.format('            { sprite = "%s", dx = %d, dy = %d },', t.sprite, dx, dy))
    end
    print("        },")
    print("    },")
    print("")
    print("================================================================")
    print("    O pasame este dump y yo lo agrego al preset.")
    print("================================================================")
end

HoldoorServer._tronosCompuestos = {
    {
        nombre = "TRONO FORJA CRUZ metal (forja + 4 rejas)",
        sprites = {
            "",              "fencing_01_28", "",
            "fencing_01_28", "crafted_01_16", "fencing_01_28",
            "",              "fencing_01_28", "",
        },
        ancho = 3,
    },
    {
        nombre = "TRONO FORJA CRUZ rejilla (fencing_01_32)",
        sprites = {
            "",              "fencing_01_32", "",
            "fencing_01_32", "crafted_01_16", "fencing_01_32",
            "",              "fencing_01_32", "",
        },
        ancho = 3,
    },
    {
        nombre = "TRONO FORJA CRUZ con respaldo (fencing 24/28)",
        sprites = {
            "",              "fencing_01_24", "",
            "fencing_01_24", "crafted_01_16", "fencing_01_24",
            "",              "fencing_01_24", "",
        },
        ancho = 3,
    },
    {
        nombre = "Bancas de parque (3x2)",
        sprites = {
            "furniture_seating_outdoor_01_32", "furniture_seating_outdoor_01_32", "furniture_seating_outdoor_01_32",
            "furniture_seating_outdoor_01_8",  "furniture_seating_outdoor_01_8",  "furniture_seating_outdoor_01_8",
        },
        ancho = 3,
    },
    {
        nombre = "Cajas apiladas (3x2)",
        sprites = {
            "carpentry_02_40", "carpentry_02_40", "carpentry_02_40",
            "carpentry_02_16", "carpentry_02_16", "carpentry_02_16",
        },
        ancho = 3,
    },
    {
        nombre = "Trono Imponente (4x2)",
        sprites = {
            "carpentry_02_40", "carpentry_02_40", "carpentry_02_40", "carpentry_02_40",
            "carpentry_02_16", "carpentry_02_16", "carpentry_02_16", "carpentry_02_16",
        },
        ancho = 4,
    },
    {
        nombre = "Mini compacto (2x2)",
        sprites = {
            "carpentry_02_40", "carpentry_02_40",
            "carpentry_02_16", "carpentry_02_16",
        },
        ancho = 2,
    },
    {
        nombre = "Trono mixto 3x3 (cajas + banca)",
        sprites = {
            "carpentry_02_40", "carpentry_02_40", "carpentry_02_40",
            "carpentry_02_24", "furniture_seating_outdoor_01_32", "carpentry_02_24",
            "carpentry_02_16", "carpentry_02_16", "carpentry_02_16",
        },
        ancho = 3,
    },
    {
        nombre = "King's Landing (5x2)",
        sprites = {
            "carpentry_02_40", "carpentry_02_40", "carpentry_02_40", "carpentry_02_40", "carpentry_02_40",
            "furniture_seating_outdoor_01_32", "furniture_seating_outdoor_01_32", "furniture_seating_outdoor_01_32", "furniture_seating_outdoor_01_32", "furniture_seating_outdoor_01_32",
        },
        ancho = 5,
    },
    {
        nombre = "Industrial 3x2 (metal)",
        sprites = {
            "industry_railroad_01_8", "industry_railroad_01_8", "industry_railroad_01_8",
            "constructedobjects_01_8", "constructedobjects_01_8", "constructedobjects_01_8",
        },
        ancho = 3,
    },
    {
        nombre = "Crafted 3x2 (improvisado)",
        sprites = {
            "crafted_01_8",  "crafted_01_8",  "crafted_01_8",
            "crafted_01_16", "crafted_01_16", "crafted_01_16",
        },
        ancho = 3,
    },
}
HoldoorServer._tronoCompuestoIdx = 0

-- Llamada desde el boton "DEJAR TRONO COMPUESTO AQUI" del panel F10.
-- Avanza al siguiente preset y lo planta en la posicion del player.
-- Devuelve nombre, idx para que el cliente pueda mostrarlo en HaloNote.
function HoldoorServer.dejarTronoCompuestoAqui()
    local n = #HoldoorServer._tronosCompuestos
    if n == 0 then return nil, 0 end
    HoldoorServer._tronoCompuestoIdx = (HoldoorServer._tronoCompuestoIdx % n) + 1
    local preset = HoldoorServer._tronosCompuestos[HoldoorServer._tronoCompuestoIdx]
    local ok = HoldoorServer.testTronoCompuesto(preset.sprites, preset.ancho)
    if ok then
        return preset.nombre, HoldoorServer._tronoCompuestoIdx
    else
        print("[Holdoor] Preset '" .. preset.nombre .. "' fallo al plantar (algun sprite no existe).")
        return preset.nombre .. " (FALLO)", HoldoorServer._tronoCompuestoIdx
    end
end

-- TESTER de "TRONO COMPUESTO": N piezas con sprites DISTINTOS en grilla AxB.
-- Plantea un Trono donde estás parado, asignando un sprite distinto a cada pieza.
-- Layout: las piezas se plantan en filas. La PRIMERA fila es la TRASERA (alta/respaldo)
-- y la ULTIMA fila es la DELANTERA (asiento).
--
-- Uso desde Lua Command Line:
--
--   -- 2x2 clasico (4 sprites):
--   HoldoorServer.testTronoCompuesto({"s1","s2","s3","s4"}, 2)
--   --   [s1 s2]   <- fila trasera (respaldo)
--   --   [s3 s4]   <- fila delantera (asiento)
--
--   -- 3x2 (6 sprites, mas ancho):
--   HoldoorServer.testTronoCompuesto({
--     "carpentry_02_40", "carpentry_02_40", "carpentry_02_40",  -- trasera (respaldo alto)
--     "carpentry_02_16", "carpentry_02_16", "carpentry_02_16",  -- delantera (asiento)
--   }, 3)
--
--   -- 4x2 (8 sprites, super ancho):
--   HoldoorServer.testTronoCompuesto({s1,s2,s3,s4, s5,s6,s7,s8}, 4)
--
--   -- 2x3 (6 sprites, mas profundo):
--   HoldoorServer.testTronoCompuesto({s1,s2, s3,s4, s5,s6}, 2)
--
-- ancho default: 2 (si no lo pasas, asume 2 columnas)
function HoldoorServer.testTronoCompuesto(sprites, ancho)
    ancho = ancho or 2
    if type(sprites) ~= "table" or #sprites < 1 then
        print("[Holdoor] testTronoCompuesto: pasame tabla con N sprites + ancho. Ej: {s1,s2,s3,s4,s5,s6}, 3")
        return false
    end
    if ancho < 1 or #sprites % ancho ~= 0 then
        print("[Holdoor] testTronoCompuesto: #sprites (" .. #sprites .. ") debe ser divisible por ancho (" .. ancho .. ")")
        return false
    end
    local alto = #sprites / ancho

    local p
    pcall(function() p = getSpecificPlayer(0) end)
    if not p then
        print("[Holdoor] testTronoCompuesto: no encontre al player local")
        return false
    end

    local x, y, z
    pcall(function()
        x = math.floor(p:getX())
        y = math.floor(p:getY())
        z = math.floor(p:getZ())
    end)
    if not x then return false end

    local cell
    pcall(function() cell = getCell() end)
    if not cell then return false end

    -- Validar los 4 sprites
    local function spriteExiste(name)
        local s
        pcall(function() s = IsoSpriteManager.instance:getSprite(name) end)
        if s then return s end
        pcall(function() s = getSprite(name) end)
        if s then return s end
        return nil
    end

    -- Validar sprites. Si una celda es "" o nil = HUECO (no plantar nada ahi).
    local spriteObjs = {}
    for i = 1, #sprites do
        local nombre = sprites[i]
        if nombre == nil or nombre == "" or nombre == false then
            spriteObjs[i] = false   -- marcador de hueco
        else
            local s = spriteExiste(nombre)
            if not s then
                print("[Holdoor] testTronoCompuesto: sprite #" .. i .. " no existe: '" .. tostring(nombre) .. "'")
                return false
            end
            spriteObjs[i] = s
        end
    end

    HoldoorServer.estado.galeriaTest = HoldoorServer.estado.galeriaTest or {}
    HoldoorServer._galeriaIndice = (HoldoorServer._galeriaIndice or 0) + 1

    local HP = 99999
    local cfgBase = {
        thumpDmg            = 0,
        health              = HP,
        maxHealth           = HP,
        canBarricade        = false,
        isBlockAllTheSquare = true,
        isCorner            = false,
        isThumpable         = false,
        canPassThrough      = false,
        Material            = "Metal",
        MaterialEng         = "Metal",
    }

    -- Plantar en grilla ancho x alto, fila por fila a partir de (x, y).
    -- pieza i va a posicion: col = (i-1) % ancho, fila = floor((i-1) / ancho)
    -- Si spriteObjs[i] == false, salteamos esa celda (hueco).
    local piezas = {}
    local allOk = true
    local esperadas = 0
    for i = 1, #sprites do
        if spriteObjs[i] then esperadas = esperadas + 1 end
    end

    for i = 1, #sprites do
        if spriteObjs[i] then  -- skip si es hueco
            local col = (i - 1) % ancho
            local fila = math.floor((i - 1) / ancho)
            local px = x + col
            local py = y + fila

            local sq
            pcall(function() sq = cell:getGridSquare(px, py, z) end)
            if not sq then allOk = false; break end

            local cfg = {}
            for k,v in pairs(cfgBase) do cfg[k] = v end
            cfg.name = "Compuesto #" .. HoldoorServer._galeriaIndice .. " pieza " .. i

            local thumpable
            pcall(function() thumpable = IsoThumpable.new(cell, sq, sprites[i], false, cfg) end)
            if not thumpable then
                pcall(function() thumpable = IsoThumpable:new(cell, sq, sprites[i], false, cfg) end)
            end
            if not thumpable then allOk = false; break end

            pcall(function() thumpable:setSprite(spriteObjs[i]) end)

            local added = false
            pcall(function() sq:AddSpecialObject(thumpable); added = true end)
            if not added then pcall(function() sq:AddObject(thumpable); added = true end) end
            if not added then allOk = false; break end

            pcall(function() thumpable:setMaxHealth(HP) end)
            pcall(function() thumpable:setHealth(HP) end)
            pcall(function() sq:RecalcAllWithNeighbours(true) end)
            table.insert(piezas, { obj = thumpable, x = px, y = py, z = z })
        end
    end

    if allOk and #piezas == esperadas then
        table.insert(HoldoorServer.estado.galeriaTest, {
            idx = HoldoorServer._galeriaIndice,
            sprite = "COMPUESTO " .. ancho .. "x" .. alto .. ": " .. table.concat(sprites, ", "),
            piezas = piezas, x = x, y = y, z = z,
        })
        print("[Holdoor] TRONO COMPUESTO #" .. HoldoorServer._galeriaIndice .. " (" .. ancho .. "x" .. alto .. ") plantado en (" .. x .. "," .. y .. ")")
        for i = 1, #sprites do
            local col = (i - 1) % ancho
            local fila = math.floor((i - 1) / ancho)
            print(string.format("    pieza %d  fila=%d col=%d  sprite='%s'", i, fila, col, sprites[i]))
        end
        return true
    else
        for _, pp in ipairs(piezas) do
            pcall(function() pp.obj:removeFromSquare() end)
        end
        print("[Holdoor] testTronoCompuesto: no pude plantar las " .. #sprites .. " piezas")
        return false
    end
end

-- Variante que planta el Trono en la posicion donde esta parado el jugador local.
-- Util para probar sprites sin tener que volver a la base ni re-marcar.
-- Uso: HoldoorServer.testSpriteAqui("furniture_seating_indoor_couches_01_12")
-- ACLARACION: solo funciona en SP/host (necesita acceso a getSpecificPlayer).
function HoldoorServer.testSpriteAqui(nombreSprite)
    if type(nombreSprite) ~= "string" or nombreSprite == "" then
        print("[Holdoor] testSpriteAqui: pasame un nombre de sprite como string")
        return false
    end

    local p
    pcall(function() p = getSpecificPlayer(0) end)
    if not p then
        print("[Holdoor] testSpriteAqui: no encontre al player (solo SP/host)")
        return false
    end

    local x, y, z
    pcall(function()
        x = math.floor(p:getX())
        y = math.floor(p:getY())
        z = math.floor(p:getZ())
    end)
    if not x then
        print("[Holdoor] testSpriteAqui: no pude leer posicion del player")
        return false
    end

    print("[Holdoor] testSpriteAqui: plantando en posicion del player (" .. x .. "," .. y .. "," .. z .. ")")

    -- Forzar este sprite + plantar en la posicion del player
    HoldoorServer._tronoSprites_backup = HoldoorServer._tronoSprites_backup or HoldoorServer._tronoSprites
    HoldoorServer._tronoSprites = { nombreSprite }
    local ok = HoldoorServer._plantarTrono(x, y, z)
    HoldoorServer._tronoSprites = HoldoorServer._tronoSprites_backup

    return ok
end

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
-- LAYOUT del Trono: forja + respaldo de madera detrás (2 piezas).
--   - Forja al frente (la pieza con vida real del Trono): 1500 HP, game over si llega a 0.
--   - Respaldo de madera detrás: 300 HP propio. Destructible pero no afecta al HP del Trono.
--   - Como solo bloquea por un lado, los zombis pueden rodear y atacar la forja directamente.
--   - El _reAggroZombies les setea path DIRECTO a la forja para forzar el comportamiento.
HoldoorServer._tronoLayoutForja = {
    -- {dx, dy, sprite, hpAbsoluto, esCentro}
    -- Forja: alta y maciza. Los zombis la atacan SI o SI (no la saltan).
    -- El overlay PNG del Trono de Hierro la cubre visualmente.
    { 0, 0, "crafted_01_16", 1500, true },   -- FORJA (vida del Trono)
}
HoldoorServer._tronoHPTotal = 1500

function HoldoorServer._plantarTrono(x, y, z)
    HoldoorServer._quitarTrono()

    print("[Holdoor] === _plantarTrono === (" .. x .. "," .. y .. "," .. z .. ")")

    local ok_cell, cell = pcall(getCell)
    if not ok_cell or not cell then
        print("[Holdoor] FAIL: no cell")
        return false
    end

    -- Helper: verifica que el sprite EXISTE en este build de B42.
    local function spriteExiste(name)
        local s
        pcall(function() s = IsoSpriteManager.instance:getSprite(name) end)
        if s then return s end
        pcall(function() s = getSprite(name) end)
        if s then return s end
        return nil
    end

    -- Validar que TODOS los sprites del layout existen
    for _, pieza in ipairs(HoldoorServer._tronoLayoutForja) do
        if not spriteExiste(pieza[3]) then
            print("[Holdoor] FAIL: sprite del layout no existe: '" .. pieza[3] .. "'")
            return false
        end
    end

    local piezas = {}
    local piezaCentral = nil   -- referencia a la forja (la que define el HP del Trono)
    local allOk = true

    for _, pieza in ipairs(HoldoorServer._tronoLayoutForja) do
        local dx, dy, sprite, hpAbs, esCentro = pieza[1], pieza[2], pieza[3], pieza[4], pieza[5]
        local px = x + dx
        local py = y + dy
        local spriteObj = spriteExiste(sprite)

        local ok_sq, sq = pcall(function() return cell:getGridSquare(px, py, z) end)
        if not ok_sq or not sq then allOk = false; break end

        local cfg = {
            name                = (esCentro and "Trono (forja)" or "Trono (barricada)") .. ": " .. sprite,
            modData             = {},
            thumpDmg            = 0,
            health              = hpAbs,
            maxHealth           = hpAbs,
            canBarricade        = false,
            isBlockAllTheSquare = true,
            isCorner            = false,
            isThumpable         = true,
            canBePlastered      = false,
            canPassThrough      = false,
            isDismantable       = false,
            Material            = esCentro and "Stone" or "Sandbag",
            MaterialEng         = esCentro and "Stone" or "Sandbag",
        }

        local thumpable
        pcall(function() thumpable = IsoThumpable.new(cell, sq, sprite, false, cfg) end)
        if not thumpable then
            pcall(function() thumpable = IsoThumpable:new(cell, sq, sprite, false, cfg) end)
        end
        if not thumpable then allOk = false; break end

        pcall(function() thumpable:setSprite(spriteObj) end)

        local added = false
        pcall(function() sq:AddSpecialObject(thumpable); added = true end)
        if not added then pcall(function() sq:AddObject(thumpable); added = true end) end
        if not added then allOk = false; break end

        pcall(function() thumpable:setMaxHealth(hpAbs) end)
        pcall(function() thumpable:setHealth(hpAbs) end)
        pcall(function() sq:RecalcAllWithNeighbours(true) end)

        local registro = { obj = thumpable, x = px, y = py, z = z, sprite = sprite, hpMax = hpAbs, esCentro = esCentro }
        table.insert(piezas, registro)
        if esCentro then piezaCentral = registro end
    end

    if allOk and #piezas == #HoldoorServer._tronoLayoutForja and piezaCentral then
        HoldoorServer.estado.trono = {
            piezas = piezas,
            piezaCentral = piezaCentral,   -- la forja: su HP = HP del Trono
            sprite = "FORJA_CRUZ",
            x = x, y = y, z = z,
            maxHP = piezaCentral.hpMax,    -- maxHP del Trono = maxHP de la forja
        }
        HoldoorServer.estado.brasero = piezaCentral.obj
        HoldoorServer.estado.banderaTile = { x = piezaCentral.x, y = piezaCentral.y, z = z, sprite = piezaCentral.sprite, isTrono = true }
        print("[Holdoor] OK Trono Forja Cruz plantado en (" .. x .. "," .. y .. "). HP del Trono = forja " .. piezaCentral.hpMax .. " (+ " .. (#piezas - 1) .. " barricadas)")
        return true
    else
        for _, p in ipairs(piezas) do
            pcall(function() p.obj:removeFromSquare() end)
        end
        print("[Holdoor] FAIL: no se pudo plantar el Trono Forja Cruz")
        return false
    end
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

    -- Limpiar zombis del radio al perder: no tiene sentido que sigan vagando
    local eliminados = HoldoorServer._limpiarZona()
    if eliminados > 0 then
        print("[Holdoor] Game Over: " .. eliminados .. " zombis residuales limpiados")
    end

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

-- ─────────────────────────────────────────────
-- GALERIA DE TRONOS (modo diagnóstico visual)
-- Planta N Tronos "demo" en fila al lado del player, cada uno con un sprite
-- distinto, para que se vean todos al mismo tiempo y se pueda elegir.
-- Las piezas son IsoThumpable con HP alto y NO atacables (isThumpable=false)
-- asi los zombis las ignoran durante el test.
--
-- Uso desde Lua Command Line:
--   HoldoorServer.testGaleria()        — planta TODOS los sprites de _tronoSprites
--   HoldoorServer.testGaleria(10)      — planta los primeros 10
--   HoldoorServer.testGaleria(10, 5)   — primeros 10, separados 5 tiles cada uno
--   HoldoorServer.quitarGaleria()      — limpia toda la galería
-- ─────────────────────────────────────────────

function HoldoorServer.testGaleria(maxN, spacing)
    spacing = spacing or 4   -- Trono ocupa 2x2 + 2 tiles libres entre uno y otro
    local lista = HoldoorServer._tronoSprites or {}
    if maxN and maxN > 0 and maxN < #lista then
        local sub = {}
        for i = 1, maxN do sub[i] = lista[i] end
        lista = sub
    end

    local p
    pcall(function() p = getSpecificPlayer(0) end)
    if not p then
        print("[Holdoor] testGaleria: no encontre al player local (necesita SP/host)")
        return false
    end

    HoldoorServer.quitarGaleria()
    HoldoorServer.estado.galeriaTest = {}

    local startX = math.floor(p:getX()) + 2   -- 2 tiles al este del player
    local baseY = math.floor(p:getY())
    local z = math.floor(p:getZ())

    local cell
    pcall(function() cell = getCell() end)
    if not cell then
        print("[Holdoor] testGaleria: no hay cell, abortando")
        return false
    end

    local HP = 99999  -- inerte para la demo
    local offsets = { {0,0}, {1,0}, {0,1}, {1,1} }
    local cfgBase = {
        thumpDmg            = 0,
        health              = HP,
        maxHealth           = HP,
        canBarricade        = false,
        isBlockAllTheSquare = true,
        isCorner            = false,
        isThumpable         = false,   -- NO atacable durante el test
        canBePlastered      = false,
        canPassThrough      = false,
        isDismantable       = false,
        Material            = "Metal",
        MaterialEng         = "Metal",
    }

    local function spriteExiste(name)
        local s
        pcall(function() s = IsoSpriteManager.instance:getSprite(name) end)
        if s then return s end
        pcall(function() s = getSprite(name) end)
        if s then return s end
        return nil
    end

    local plantados = 0
    for i, sprite in ipairs(lista) do
        local spriteObj = spriteExiste(sprite)
        if spriteObj then
            local x0 = startX + plantados * spacing
            local piezas = {}
            local allOk = true
            for _, off in ipairs(offsets) do
                local px = x0 + off[1]
                local py = baseY + off[2]
                local sq
                pcall(function() sq = cell:getGridSquare(px, py, z) end)
                if not sq then allOk = false; break end

                local cfg = {}
                for k,v in pairs(cfgBase) do cfg[k] = v end
                cfg.name = "Test #" .. (plantados + 1) .. ": " .. sprite

                -- Firma correcta en B42: IsoThumpable.new(cell, sq, sprite, false, cfg)
                local thumpable
                pcall(function() thumpable = IsoThumpable.new(cell, sq, sprite, false, cfg) end)
                if not thumpable then
                    pcall(function() thumpable = IsoThumpable:new(cell, sq, sprite, false, cfg) end)
                end
                if not thumpable then allOk = false; break end

                pcall(function() thumpable:setSprite(spriteObj) end)

                local added = false
                pcall(function() sq:AddSpecialObject(thumpable); added = true end)
                if not added then pcall(function() sq:AddObject(thumpable); added = true end) end
                if not added then allOk = false; break end

                pcall(function() thumpable:setMaxHealth(HP) end)
                pcall(function() thumpable:setHealth(HP) end)
                pcall(function() sq:RecalcAllWithNeighbours(true) end)
                table.insert(piezas, { obj = thumpable, x = px, y = py, z = z })
            end

            if allOk and #piezas == 4 then
                plantados = plantados + 1
                table.insert(HoldoorServer.estado.galeriaTest, {
                    idx = plantados, sprite = sprite, piezas = piezas, x = x0, y = baseY, z = z,
                })
                print(string.format("[Holdoor] Galeria #%d  x=%d  sprite='%s'", plantados, x0, sprite))
            else
                for _, pp in ipairs(piezas) do
                    pcall(function() pp.obj:removeFromSquare() end)
                end
            end
        else
            print(string.format("[Holdoor] Galeria: sprite '%s' NO EXISTE en este build", sprite))
        end
    end

    print(string.format("[Holdoor] === Galeria lista: %d Tronos plantados desde X=%d, baseY=%d, spacing=%d ===", plantados, startX, baseY, spacing))
    print("[Holdoor] Pasea al ESTE del player. Cada Trono ocupa 2x2 tiles, con 2 tiles libres entre uno y otro.")
    print("[Holdoor] Para identificar uno, mira el listado de arriba: index #N = sprite usado.")
    print("[Holdoor] Para limpiar: HoldoorServer.quitarGaleria()")
    return true
end

function HoldoorServer.quitarGaleria()
    if not HoldoorServer.estado.galeriaTest then
        HoldoorServer.estado.galeriaTest = {}
        return
    end
    local n = 0
    for _, demo in ipairs(HoldoorServer.estado.galeriaTest) do
        for _, pp in ipairs(demo.piezas or {}) do
            pcall(function() pp.obj:removeFromSquare() end)
            pcall(function() pp.obj:removeFromWorld() end)
        end
        n = n + 1
    end
    HoldoorServer.estado.galeriaTest = {}
    HoldoorServer._galeriaIndice = 0      -- reset al limpiar
    HoldoorServer._builderTiles = {}      -- reset del builder manual
    print("[Holdoor] Galeria limpiada (" .. n .. " Tronos removidos)")
end

-- ─────────────────────────────────────────────
-- DEJAR PROXIMO SPRITE AQUI (modo interactivo)
-- Llamada desde el boton del panel F10. Cada invocacion:
--   1) avanza el indice de sprite (rotando al inicio si llega al final)
--   2) planta un Trono demo en la posicion del player con ESE sprite
--   3) lo agrega a la galeria (NO toca el Trono principal de las oleadas)
-- Devuelve el nombre del sprite usado (string) o nil si fallo.
-- ─────────────────────────────────────────────
HoldoorServer._galeriaIndice = HoldoorServer._galeriaIndice or 0

function HoldoorServer.dejarSpriteAqui()
    local lista = HoldoorServer._tronoSprites or {}
    if #lista == 0 then
        print("[Holdoor] dejarSpriteAqui: lista de sprites vacia")
        return nil
    end

    local p
    pcall(function() p = getSpecificPlayer(0) end)
    if not p then
        print("[Holdoor] dejarSpriteAqui: no encontre al player local")
        return nil
    end

    local x, y, z
    pcall(function()
        x = math.floor(p:getX())
        y = math.floor(p:getY())
        z = math.floor(p:getZ())
    end)
    if not x then return nil end

    local cell
    pcall(function() cell = getCell() end)
    if not cell then return nil end

    HoldoorServer.estado.galeriaTest = HoldoorServer.estado.galeriaTest or {}

    -- Buscar el proximo sprite VALIDO en la lista (skipea los que no existen)
    local function spriteExiste(name)
        local s
        pcall(function() s = IsoSpriteManager.instance:getSprite(name) end)
        if s then return s end
        pcall(function() s = getSprite(name) end)
        if s then return s end
        return nil
    end

    local intentos = 0
    local sprite, spriteObj
    while intentos < #lista do
        HoldoorServer._galeriaIndice = (HoldoorServer._galeriaIndice % #lista) + 1
        sprite = lista[HoldoorServer._galeriaIndice]
        spriteObj = spriteExiste(sprite)
        if spriteObj then break end
        intentos = intentos + 1
        sprite = nil
    end

    if not sprite then
        print("[Holdoor] dejarSpriteAqui: ningun sprite de la lista existe en este build")
        return nil
    end

    -- Plantar 4 piezas en 2x2 a partir de (x, y)
    local HP = 99999
    local offsets = { {0,0}, {1,0}, {0,1}, {1,1} }
    local cfgBase = {
        thumpDmg            = 0,
        health              = HP,
        maxHealth           = HP,
        canBarricade        = false,
        isBlockAllTheSquare = true,
        isCorner            = false,
        isThumpable         = false,
        canPassThrough      = false,
        Material            = "Metal",
        MaterialEng         = "Metal",
    }

    local piezas = {}
    local allOk = true
    for _, off in ipairs(offsets) do
        local px = x + off[1]
        local py = y + off[2]
        local sq
        pcall(function() sq = cell:getGridSquare(px, py, z) end)
        if not sq then allOk = false; break end

        local cfg = {}
        for k,v in pairs(cfgBase) do cfg[k] = v end
        cfg.name = "Demo #" .. HoldoorServer._galeriaIndice .. ": " .. sprite

        -- Firma correcta en B42: IsoThumpable.new(cell, sq, sprite, false, cfg)
        local thumpable
        pcall(function() thumpable = IsoThumpable.new(cell, sq, sprite, false, cfg) end)
        if not thumpable then
            pcall(function() thumpable = IsoThumpable:new(cell, sq, sprite, false, cfg) end)
        end
        if not thumpable then allOk = false; break end

        -- Forzar el sprite directamente
        pcall(function() thumpable:setSprite(spriteObj) end)

        -- AddSpecialObject (primario), fallback AddObject
        local added = false
        pcall(function() sq:AddSpecialObject(thumpable); added = true end)
        if not added then pcall(function() sq:AddObject(thumpable); added = true end) end
        if not added then allOk = false; break end

        pcall(function() thumpable:setMaxHealth(HP) end)
        pcall(function() thumpable:setHealth(HP) end)
        pcall(function() sq:RecalcAllWithNeighbours(true) end)
        table.insert(piezas, { obj = thumpable, x = px, y = py, z = z })
    end

    if allOk and #piezas == 4 then
        table.insert(HoldoorServer.estado.galeriaTest, {
            idx = HoldoorServer._galeriaIndice, sprite = sprite, piezas = piezas, x = x, y = y, z = z,
        })
        print(string.format("[Holdoor] DEMO #%d plantado en (%d,%d): sprite='%s'", HoldoorServer._galeriaIndice, x, y, sprite))
        return sprite
    else
        for _, pp in ipairs(piezas) do
            pcall(function() pp.obj:removeFromSquare() end)
        end
        print("[Holdoor] dejarSpriteAqui: no pude plantar las 4 piezas en (" .. x .. "," .. y .. ")")
        return nil
    end
end
