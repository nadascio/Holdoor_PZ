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
    -- v0.6.2: reset COMPLETO del estado en cada carga de mundo. Sin esto, si el usuario juega
    -- SP y despues abre MP hosted en el mismo proceso PZ (sin cerrar el cliente), el estado
    -- residual del SP previo (estado.activo=true, ownerUsername=X) hace que el server real
    -- rechace el iniciar con "Ya hay oleadas activas iniciadas por X".
    -- HoldoorServer.estado es global del modulo Lua → persiste entre cargas de mundo dentro
    -- del mismo proceso PZ. OnGameStart se dispara en cada mundo pero antes init() solo
    -- reseteaba config.
    HoldoorServer.estado.activo         = false
    HoldoorServer.estado.fase           = "inactivo"
    HoldoorServer.estado.ownerUsername  = nil
    HoldoorServer.estado.oleadaActual   = 0
    HoldoorServer.estado.killsOleada    = {}
    HoldoorServer.estado.killsTotal     = {}
    HoldoorServer.estado.baseDefinida   = false
    HoldoorServer.estado.encoladosTiers = {}
    print("[Holdoor] Servidor inicializado v" .. HoldoorConfig.VERSION .. " — estado reseteado")
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

    -- v0.6.1: registrar participantes activos (vivos + en zona) para detectar derrota
    -- por muerte total. Cuando todos mueren / se desconectan → oleada se da por perdida.
    estado.participantes = {}   -- { [username] = true }
    pcall(function()
        local ok, ps = pcall(getOnlinePlayers)
        if ok and ps then
            local oks, np = pcall(function() return ps:size() end)
            if oks and np then
                for i = 0, np - 1 do
                    local okp, p = pcall(function() return ps:get(i) end)
                    if okp and p then
                        local u
                        pcall(function() u = p:getUsername() end)
                        if u then estado.participantes[u] = true end
                    end
                end
            end
        end
    end)

    -- v0.6 fix: resetear HP del Trono al iniciar nueva instancia. Sino conserva HP
    -- residual de la sesion anterior (ej. termina test con 1200/1500 → arranca normal con 1200).
    if estado.trono and estado.trono.piezas then
        local maxHpTrono = estado.trono.maxHP or 1500
        for _, p in ipairs(estado.trono.piezas) do
            if p and p.obj then
                pcall(function() p.obj:setHealth(maxHpTrono) end)
            end
        end
        estado.tronoHP = maxHpTrono
        HoldoorServer.notificarTodos("tronoHP", { hp = maxHpTrono, maxHp = maxHpTrono })
        print(string.format("[Holdoor] HP Trono reseteado a %d/%d al iniciar nueva instancia", maxHpTrono, maxHpTrono))
    end

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
-- Persistencia MP B42: cualquier modificacion server-side de getModData() requiere
-- player:transmitModData() despues para que el server marque el cambio como dirty,
-- lo sincronice al cliente y lo persista en el save al shutdown. Sin esta llamada
-- las monedas vuelven a 0 al cerrar/abrir el server (gotcha #51 lockeado 2026-06-16).
local function _persistirModData(p)
    pcall(function() p:transmitModData() end)
end

local function darMonedasA(p, bronze, silver, gold)
    local ok, md = pcall(function() return p:getModData() end)
    if not ok or not md then return false end
    md.Holdoor_Bronze = (md.Holdoor_Bronze or 0) + (bronze or 0)
    md.Holdoor_Silver = (md.Holdoor_Silver or 0) + (silver or 0)
    md.Holdoor_Gold   = (md.Holdoor_Gold   or 0) + (gold   or 0)
    _persistirModData(p)
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
    _persistirModData(emisor)
    _persistirModData(target)
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
-- v0.6.1: en MP los items se entregan via comando al cliente "darItem" porque
-- InventoryItemFactory.CreateItem es null en server-side context (gotcha 2026-06-16) y
-- AddItem(string) server-side crea items "fantasma" no equipables. El cliente local
-- hace el AddItem con su propio inventario sincronizado.
local function ejecutarAccion(jugador, accion)
    if not accion or not accion.tipo then return false end

    if accion.tipo == "item" then
        -- v0.6.1 fix MP definitivo: en MP hosted, sendClientCommand al host local NO llega
        -- (PZ engine no rutea loopback). Y llamar onComandoServidor directo ejecuta en
        -- server-context donde InventoryItemFactory es null. Solucion: ejecutarAccion solo
        -- COBRA (las monedas/materiales ya se restaron antes de llamar a esta funcion).
        -- La ENTREGA del item la hace HoldoorClient.comprar despues de que server confirme,
        -- en cliente-context puro donde InventoryItemFactory existe.
        return true

    elseif accion.tipo == "package" then
        -- Idem: el cliente entrega el package despues del cobro server-side.
        return true

    elseif accion.tipo == "xp" then
        -- En B42, Perks.FromString puede devolver nil para algunos nombres (Strength, etc).
        -- Fallback: probar acceso directo Perks[name].
        local ok = false
        -- v0.6.1 fix MP: el AddXP server-side se sobreescribe por el cliente cada vez que
        -- syncea (XP sube 1 nivel y vuelve a bajar). Solucion: NO hacer AddXP aca, dejar
        -- que HoldoorClient.comprar lo haga en cliente-context puro despues del cobro.
        -- Mismo patron que items (drop al piso) — el AddXP cliente-side sincroniza al
        -- server automaticamente sin ser sobreescrito.
        return true

    elseif accion.tipo == "subir_nivel" then
        -- v0.6.2: "vender niveles" para Libros de Guerra. Mismo patron que "xp":
        -- el server cobra (con precioOverride calculado en cliente), el cliente
        -- entrega el XP exacto para completar 1 nivel via /addxp admin.
        return true

    elseif accion.tipo == "reliquia_godmode_flash" then
        -- Beso del Dios: cliente ejecuta el flow de curacion. Marca ModData unico-por-vida.
        local md = jugador:getModData()
        if md then md.Holdoor_BesoDios = true end
        _persistirModData(jugador)
        return true

    elseif accion.tipo == "reliquia_cura_sangrado"
        or accion.tipo == "reliquia_cura_fractura"
        or accion.tipo == "reliquia_cura_corte"
        or accion.tipo == "reliquia_cura_mordedura"
        or accion.tipo == "reliquia_cura_rasgunyo" then
        -- Bendiciones: cliente ejecuta sendClientCommand("onHealthCheatCurrentPlayer")
        -- con action="healthFull" para los body parts que tienen la condicion.
        return true

    elseif accion.tipo == "restore" then
        -- En B42 los stats se setean via getStats():set(CharacterStat.X, value).
        -- Los setters individuales (setFatigue, setEndurance, etc) NO existen → tiran
        -- "Object tried to call nil" que kahlua NO atrapa con pcall (gotcha #18).
        -- Patron real confirmado en media/lua/shared/Foraging/forageSystem.lua.
        local stats = jugador:getStats()
        local bd    = jugador:getBodyDamage()
        local nutr
        pcall(function() nutr = jugador:getNutrition() end)

        -- Mapeo nombre interno -> { enum, valor objetivo }
        -- Endurance es el unico que se "carga" (valor 1.0 = full); el resto se "resetea" a 0.
        local statMap = nil
        if CharacterStat then
            statMap = {
                hunger    = { CharacterStat.HUNGER,       0.0 },
                thirst    = { CharacterStat.THIRST,       0.0 },
                fatigue   = { CharacterStat.FATIGUE,      0.0 },
                sleep     = { CharacterStat.FATIGUE,      0.0 },  -- alias de fatigue
                endurance = { CharacterStat.ENDURANCE,    1.0 },
                stress    = { CharacterStat.STRESS,       0.0 },
                boredom   = { CharacterStat.BOREDOM,      0.0 },
                panic     = { CharacterStat.PANIC,        0.0 },
                unhappy   = { CharacterStat.UNHAPPINESS,  0.0 },
                drunk     = { CharacterStat.INTOXICATION, 0.0 },
                pain      = { CharacterStat.PAIN,         0.0 },
            }
        end

        for _, s in ipairs(accion.stats or {}) do
            if statMap and statMap[s] and statMap[s][1] then
                local enum, val = statMap[s][1], statMap[s][2]
                pcall(function() stats:set(enum, val) end)
            end
            -- Hunger especial: actualizar nutrition tambien
            if s == "hunger" and nutr then
                pcall(function() nutr:setCalories(2200) end)
            end
        end
        return true

    elseif accion.tipo == "material" then
        local md = jugador:getModData()
        if not md or not accion.key then return false end
        md[accion.key] = (md[accion.key] or 0) + (accion.amount or 1)
        _persistirModData(jugador)
        return true

    elseif accion.tipo == "cure_bite" then
        -- API real B42 confirmada en server/ClientCommands.lua:495+ (cheat de body part).
        -- Solo usamos SetBitten/SetInfected/SetFakeInfected en cada body part.
        -- NO usar bd:setInfected global (no existe en B42, crashea fuera de pcall).
        local bd = jugador:getBodyDamage()
        if not bd then return false end
        pcall(function()
            local parts = bd:getBodyParts()
            if parts then
                for i = 0, parts:size() - 1 do
                    local part = parts:get(i)
                    if part then
                        pcall(function() part:SetBitten(false) end)
                        pcall(function() part:SetInfected(false) end)
                        pcall(function() part:SetFakeInfected(false) end)
                        pcall(function() part:SetScratched(false) end)
                        pcall(function() part:SetDeepWounded(false) end)
                    end
                end
            end
        end)
        return true

    elseif accion.tipo == "trait" then
        -- En B42, TraitFactory y los metodos de traits NO estan disponibles en el server.
        -- Por eso mandamos comando al CLIENTE que aplica el trait localmente.
        if not accion.trait then return false end
        local md = jugador:getModData()
        local traitId = tostring(accion.trait)

        -- Marcar en ModData que el player compro este trait (para el limite "1 por vida")
        if md then md.Holdoor_TraitComprado = accion.trait end
        _persistirModData(jugador)

        -- Mandar comando al cliente para que aplique el trait
        pcall(function()
            sendServerCommand(jugador, HoldoorConfig.MODULE, "aplicarTrait", { trait = traitId })
        end)
        -- En SP el server y cliente comparten VM, pero el namespace de TraitFactory
        -- esta del lado cliente. Fallback: llamada directa a la funcion del cliente.
        if type(HoldoorClient) == "table" and type(HoldoorClient.aplicarTraitLocal) == "function" then
            pcall(function() HoldoorClient.aplicarTraitLocal(traitId) end)
        end

        print("[Holdoor] trait: comando aplicarTrait enviado al cliente para '" .. traitId .. "'")
        return true

    elseif accion.tipo == "cura_trait" then
        -- Igual que "trait": delegamos al cliente
        if not accion.trait then return false end
        local md = jugador:getModData()
        local traitId = tostring(accion.trait)

        if md then md.Holdoor_TraitCurado = accion.trait end
        _persistirModData(jugador)

        pcall(function()
            sendServerCommand(jugador, HoldoorConfig.MODULE, "curarTrait", { trait = traitId })
        end)
        if type(HoldoorClient) == "table" and type(HoldoorClient.curarTraitLocal) == "function" then
            pcall(function() HoldoorClient.curarTraitLocal(traitId) end)
        end

        print("[Holdoor] cura_trait: comando curarTrait enviado al cliente para '" .. traitId .. "'")
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

    -- v0.6.2: precioOverride para acciones dinamicas (tipo "subir_nivel" en Libros de Guerra).
    -- El cliente calcula el precio segun nivel actual del player y lo manda aca.
    -- Server confia en el cliente (acceptable para wave defense mod, no es economia competitiva).
    local precioEfectivo = (args and args.precioOverride) or item.precio

    -- Restriccion "1 por vida del personaje" para Rasgos Heroicos y Milagros.
    if item.accion and item.accion.tipo == "trait" and md and md.Holdoor_TraitComprado then
        pcall(sendClientCommand, jugador, HoldoorConfig.MODULE, "compraFail",
              { motivo = "Ya invocaste tu Rasgo Heroico en esta vida. Solo uno por personaje." })
        return
    end
    if item.accion and item.accion.tipo == "cura_trait" and md and md.Holdoor_TraitCurado then
        pcall(sendClientCommand, jugador, HoldoorConfig.MODULE, "compraFail",
              { motivo = "Ya usaste tu Milagro del Maestre. Solo uno por personaje." })
        return
    end
    -- Reliquia Beso del Dios: 1 por vida del personaje
    if item.accion and item.accion.tipo == "reliquia_godmode_flash" and md and md.Holdoor_BesoDios then
        pcall(sendClientCommand, jugador, HoldoorConfig.MODULE, "compraFail",
              { motivo = "Ya invocaste el Beso del Dios de Muchos Rostros en esta vida." })
        return
    end
    -- Para cura_trait: la validacion "tiene el trait?" se hace EN EL CLIENTE
    -- (las APIs de traits son cliente-only en B42). Aca solo verificamos el limite
    -- "1 por vida" via ModData Holdoor_TraitCurado (ya validado arriba).
    -- Para cure_bite: validar que el player tenga mordedura.
    -- API real B42: iterar body parts y chequear bodyPart:bitten() (minuscula, sin cascada).
    -- Cascada con variantes (bd:isInfected, bd:IsInfected, part:IsBitten) tira errores
    -- "Object tried to call nil" que kahlua NO atrapa con pcall → escapa al log.
    if item.accion and item.accion.tipo == "cure_bite" then
        local esta_mordido = false
        local valido_check = false
        pcall(function()
            local bd = jugador:getBodyDamage()
            if not bd then return end
            local parts = bd:getBodyParts()
            if not parts then return end
            valido_check = true
            for i = 0, parts:size() - 1 do
                local part = parts:get(i)
                if part and part:bitten() then
                    esta_mordido = true
                    break
                end
            end
        end)
        if valido_check and not esta_mordido then
            pcall(sendClientCommand, jugador, HoldoorConfig.MODULE, "compraFail",
                  { motivo = "No estas mordido. No hay nada que curar." })
            return
        end
    end

    -- Validar que tenga saldo suficiente para CADA componente del precio
    for k, costo in pairs(precioEfectivo or {}) do
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

    -- Cobrar: descontar TODAS las componentes del precio EFECTIVO
    for k, costo in pairs(precioEfectivo or {}) do
        if costo and costo > 0 then
            local mdKey = mdKeyMap[k]
            md[mdKey] = (md[mdKey] or 0) - costo
        end
    end
    _persistirModData(jugador)

    print("[Holdoor] Compra: " .. jugador:getUsername() .. " -> " .. catId .. "/" .. itemId ..
          " | " .. HoldoorShopCatalog.precioStr(precioEfectivo))

    pcall(sendClientCommand, jugador, HoldoorConfig.MODULE, "monedasActualizadas", {})
    pcall(sendClientCommand, jugador, HoldoorConfig.MODULE, "compraOK", {
        nombre = item.nombre,
        precio = precioEfectivo,
    })

    if type(HoldoorClient) == "table" and HoldoorClient.onComandoServidor then
        pcall(HoldoorClient.onComandoServidor, HoldoorConfig.MODULE, "monedasActualizadas", {})
        pcall(HoldoorClient.onComandoServidor, HoldoorConfig.MODULE, "compraOK", { nombre=item.nombre, precio=precioEfectivo })
    end
end

-- Entrega monedas a todos los jugadores y les avisa por cliente para que actualicen el HUD.
-- v0.6.1: helper reutilizable. Busca a un player con privilegios admin online.
-- Comprueba: (1) accessLevel "admin" explicito, (2) en SP/MP hosted, el primer player
-- online (que es el host) tiene privilegios admin implicitos via CoopHost.
-- Devuelve IsoPlayer o nil.
function HoldoorServer._buscarHostAdmin()
    local ok, players = pcall(getOnlinePlayers)
    if not ok or not players then return nil end
    local ok2, n = pcall(function() return players:size() end)
    if not ok2 or not n or n == 0 then return nil end

    -- Pasada 1: buscar accessLevel "admin" explicito
    for i = 0, n - 1 do
        local ok3, p = pcall(function() return players:get(i) end)
        if ok3 and p then
            local lvl
            pcall(function() lvl = p:getAccessLevel() end)
            if lvl == "admin" then return p end
        end
    end

    -- Pasada 2 (fallback hosted): devolver el primer player online.
    -- En MP hosted ES el host (que tiene privilegios admin via CoopHost aunque
    -- getAccessLevel devuelva "" o "none"). En dedicated sin admin real, el comando
    -- /additem fallara, pero al menos no devolvemos nil sin intentarlo.
    local ok3, p = pcall(function() return players:get(0) end)
    if ok3 and p then return p end
    return nil
end

-- v0.6.1: helper para entregar items via comando /additem admin (mismo patron que tienda).
-- El item entra DIRECTO al inventario del target, equipable y legitimo. Usar para drops
-- por kill / recompensa fin oleada / cualquier flow que entregue items en MP.
function HoldoorServer._entregarItemsViaAdmin(targetUsername, items)
    if not targetUsername or not items or #items == 0 then return false end
    local hostAdmin = HoldoorServer._buscarHostAdmin()
    if not hostAdmin then
        print("[Holdoor] _entregarItemsViaAdmin WARN: no hay admin online para " .. tostring(targetUsername))
        return false
    end
    pcall(function()
        sendServerCommand(hostAdmin, HoldoorConfig.MODULE, "ejecutarAddItem", {
            target = targetUsername, items = items,
        })
    end)
    return true
end

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

    -- Limpiar zombies cercanos a la base — igual que al terminar oleada normal.
    -- Evita que queden hordas residuales rodeando el Trono despues de un detener manual.
    if estado.baseDefinida then
        local eliminados = HoldoorServer._limpiarZona()
        if eliminados and eliminados > 0 then
            HoldoorServer.notificarTodos("zonaLimpiada", { cantidad = eliminados })
        end
    end

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

    -- v0.6: limpiar zombies cercanos al ganar la partida (sino siguen viniendo los
    -- spawneados durante la ultima oleada y se acumulan ~40 zombies encima del player).
    if estado.baseDefinida then
        local eliminados = HoldoorServer._limpiarZona()
        if eliminados and eliminados > 0 then
            HoldoorServer.notificarTodos("zonaLimpiada", { cantidad = eliminados })
        end
    end

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

-- ════════════════════════════════════════════════════════════════════
-- v0.6 — _spawnTick: spawn continuo modelo C (timer + target).
-- Se ejecuta desde onTick. Spawnea 1 zombi cuando toca según intervalo
-- lerp(spawnInicio → spawnFin) según progreso temporal de la oleada.
-- ════════════════════════════════════════════════════════════════════

function HoldoorServer._spawnTick()
    -- v0.6 fix #1: SPAWN DE CÚMULOS (no perdigonado 1 zombi a la vez).
    -- Cada tick que toque, spawneamos un GRUPO de 2-5 zombies juntos en tiles
    -- adyacentes. Comparten destino. Se sienten como horda real, no como hilera.
    local estado = HoldoorServer.estado
    if estado.fase ~= "activa" then return end
    if not estado.baseDefinida then return end

    local ahora = os.time()
    if (estado.proximoSpawnSec or 0) > ahora then return end

    -- Calcular intervalo actual (lerp lineal entre spawnInicio y spawnFin según progreso)
    local elapsed  = ahora - (estado.oleadaInicioSec or ahora)
    local total    = estado.oleadaDuracionSec or 180
    local progreso = math.min(1.0, math.max(0.0, elapsed / total))
    local intervalo = (estado.spawnInicio or 8.0) * (1.0 - progreso)
                    + (estado.spawnFin    or 4.0) * progreso

    -- Decidir velocidad del cúmulo entero (todos los del grupo van iguales).
    -- speed 2 = Fast Shamblers (caminan rápido, lo correcto).
    -- speed 1 = Sprinters (BUGGY en B42, no se pathea bien — NO usar).
    -- speed 3 = Slow Shamblers (muy lentos).
    local esCorredorCumulo = ZombRand(1000) < math.floor((estado.pctCorredores or 0) * 1000)
    local speed = esCorredorCumulo and 3 or 2

    -- Tamaño del cúmulo: 2-5 zombies. Random por tick para que cada cúmulo se sienta distinto.
    local tamCumulo = 2 + ZombRand(4)   -- 2, 3, 4 o 5

    -- Posición base del cúmulo: ángulo random, distancia = radioConfigurado + 5 (fijo).
    local bx, by, bz = estado.baseX, estado.baseY, estado.baseZ
    local radio = (estado.config and estado.config.radioSpawn) or 25
    local dist  = radio + 5

    -- SandboxVar Speed (todos los zombies del cúmulo lo heredan)
    local origSpeed = SandboxVars and SandboxVars.ZombieConfig and SandboxVars.ZombieConfig.Speed
    if origSpeed ~= nil then SandboxVars.ZombieConfig.Speed = speed end

    -- Intentar hasta 6 ángulos para encontrar uno exterior válido
    local spawnX, spawnY = nil, nil
    for try = 1, 6 do
        local ang  = ZombRand(360)
        local sx   = math.floor(bx + math.cos(math.rad(ang)) * dist)
        local sy   = math.floor(by + math.sin(math.rad(ang)) * dist)

        local ok_sq, spawnSq = pcall(function() return getCell():getGridSquare(sx, sy, bz) end)
        if ok_sq and spawnSq then
            local ok_out, esExterior = pcall(function() return spawnSq:isOutside() end)
            if ok_out and esExterior then
                spawnX, spawnY = sx, sy
                break
            end
        end
    end

    -- Spawnear el cúmulo entero en tiles adyacentes alrededor del centro encontrado
    local spawneados = 0
    if spawnX and spawnY then
        -- Destino compartido: tile aleatoria CERCA del Trono (no en el centro exacto)
        local angD = ZombRand(360)
        local dD   = ZombRand(math.max(1, math.floor(radio * 0.4)))
        local destX = math.floor(bx + math.cos(math.rad(angD)) * dD)
        local destY = math.floor(by + math.sin(math.rad(angD)) * dD)

        for i = 1, tamCumulo do
            -- Offset random -2..+2 alrededor del centro del cúmulo
            local offX = ZombRand(5) - 2
            local offY = ZombRand(5) - 2
            local zx, zy = spawnX + offX, spawnY + offY
            if HoldoorServer._spawnUno(zx, zy, bz, destX, destY, bz, 0) then
                spawneados = spawneados + 1
            end
        end

        -- addSound localizado en el centro del cúmulo (los empuja a la base)
        if spawneados > 0 then
            pcall(addSound, nil, spawnX, spawnY, bz, 50, 150)
        end
    end

    -- Restaurar SandboxVar Speed
    if origSpeed ~= nil and SandboxVars and SandboxVars.ZombieConfig then
        SandboxVars.ZombieConfig.Speed = origSpeed
    end

    if spawneados > 0 then
        estado.zombiesSpawneados = (estado.zombiesSpawneados or 0) + spawneados
        print(string.format("[Holdoor] Cumulo: +%d zombies (speed=%d) @ radio %d, intervalo=%.1fs",
            spawneados, speed, dist, intervalo))
    end

    -- Schedule próximo cúmulo
    estado.proximoSpawnSec = ahora + intervalo
end

-- v0.6 — Aggro sostenido: addSound + re-path explicito.
-- 1) addSound para atraer zombies lejanos.
-- 2) _reAggroZombies para path EXPLICITO de los cercanos (pathToLocation directo).
--    Si addSound falla por alguna razon, el path explicito garantiza que vengan.
function HoldoorServer._aggroSostenido()
    local estado = HoldoorServer.estado
    if estado.fase ~= "activa" then return end
    if not estado.baseDefinida then return end

    local ahora = os.time()
    local interval = HoldoorConfig.aggroIntervalSec or 4
    if ahora < (estado.aggroUltimoSec or 0) + interval then return end
    estado.aggroUltimoSec = ahora

    -- 1) Sonido amplio desde la base
    local radio = HoldoorConfig.aggroRadio or 120
    local vol   = HoldoorConfig.aggroVolumen or 200
    local sndOk = pcall(addSound, nil, estado.baseX, estado.baseY, estado.baseZ, radio, vol)
    print(string.format("[Holdoor] AGGRO sound radio=%d vol=%d ok=%s",
        radio, vol, tostring(sndOk)))

    -- 2) Re-path EXPLICITO: forzar pathToLocation en todos los zombies cercanos.
    --    Es el fallback que en modelo viejo funcionaba (los zombies seguian su path
    --    aunque addSound no los aggreara). Cada 4s mantiene los paths frescos.
    HoldoorServer._reAggroZombies()
end

-- v0.6 — Check de cierre de oleada (timer Y/O target kills, lo que pase primero).
function HoldoorServer._chequearCierreOleada()
    local estado = HoldoorServer.estado
    if estado.fase ~= "activa" then return end

    local ahora     = os.time()
    local elapsed   = ahora - (estado.oleadaInicioSec or ahora)
    local duracion  = estado.oleadaDuracionSec or 180
    local kills     = estado.oleadaKills or 0
    local target    = estado.oleadaTargetKills or 50

    -- CIERRE LIMPIO: matas target antes del timer → bonus +25%
    if kills >= target and not estado.cierreLimpio then
        estado.cierreLimpio = true
        print(string.format("[Holdoor] CIERRE LIMPIO! Oleada %d cerrada en %ds (%d/%d kills)",
            estado.oleadaActual, elapsed, kills, target))
        HoldoorServer._oleadaCompletada()
        return
    end

    -- CIERRE POR TIMER: oleada agotó duración → recompensa estándar
    if elapsed >= duracion then
        print(string.format("[Holdoor] Cierre por timer. Oleada %d (%d/%d kills, no logro target)",
            estado.oleadaActual, kills, target))
        HoldoorServer._oleadaCompletada()
        return
    end
end

function HoldoorServer._lanzarOleada()
    -- ════════════════════════════════════════════════════════════════
    -- Sprint v0.6 — modelo C híbrido (timer + target kills)
    -- Sin "total fijo" de zombies. Sin tandas. Sin cola. Spawn continuo
    -- vía _spawnTick que se ejecuta desde _tickServidor. Cierre por
    -- timer Y/O target kills (lo que pase primero).
    -- ════════════════════════════════════════════════════════════════
    local estado = HoldoorServer.estado
    estado.oleadaActual = estado.oleadaActual + 1
    local oleada = estado.oleadaActual
    -- Fix v0.6: estado.modoId nunca se asigna directo, vive en estado.config.modoId
    local modoId = (estado.config and estado.config.modoId) or "normal"

    -- Limpiar zona antes de cada oleada (igual que v0.5)
    local eliminados = HoldoorServer._limpiarZona()
    if eliminados and eliminados > 0 then
        HoldoorServer.notificarTodos("zonaLimpiada", { cantidad = eliminados })
    end

    -- Obtener config del modo V6 (fallback a normal)
    local modoCfg = (HoldoorConfig.modosV6 or {})[modoId] or HoldoorConfig.modosV6.normal

    -- Obtener config de la oleada actual (clamp al último entry de la curva)
    local oleadaIdx = math.min(oleada, #(HoldoorConfig.oleadasV6 or {}))
    local oleadaCfg = HoldoorConfig.oleadasV6[oleadaIdx] or {
        duracionSeg = 180, targetKills = 50,
        spawnInicio = 4.0, spawnFin = 2.0,
        pctCorredores = 0.10,
    }

    -- Calcular parametros con multiplicadores del modo
    local duracion      = math.floor((oleadaCfg.duracionSeg or 180) * (modoCfg.multDuracion or 1.0))
    local target        = math.floor((oleadaCfg.targetKills or 50) * (modoCfg.multKills or 1.0))
    local spawnInicio   = (oleadaCfg.spawnInicio or 4.0) * (modoCfg.multSpawn or 1.0)
    local spawnFin      = (oleadaCfg.spawnFin or 2.0)    * (modoCfg.multSpawn or 1.0)
    local pctCorredores = oleadaCfg.pctCorredores or 0.10

    -- Setear estado del modelo C
    estado.fase                = "activa"
    estado.oleadaInicioSec     = os.time()
    estado.oleadaDuracionSec   = duracion
    estado.oleadaTargetKills   = target
    estado.oleadaKills         = 0
    estado.spawnInicio         = spawnInicio
    estado.spawnFin            = spawnFin
    estado.pctCorredores       = pctCorredores
    estado.proximoSpawnSec     = os.time() + spawnInicio  -- primer spawn al final del intervalo inicial
    estado.zombiesSpawneados   = 0
    estado.cierreLimpio        = false
    estado.aggroUltimoSec      = 0

    -- Compatibilidad: codigo viejo lee zombiesTotal/Restantes. En modelo C no hay
    -- total fijo. Los seteamos a 0 (no se usan para counter de oleada).
    estado.zombiesTotal     = 0
    estado.zombiesRestantes = 0

    -- Frases épicas + flag de ultima oleada
    local frase    = HoldoorConfig.frases[ZombRand(#HoldoorConfig.frases) + 1]
    local esUltima = (oleada >= (modoCfg.maxOleadas or 8))

    print(string.format(
        "[Holdoor] OLEADA %d %s — modo=%s duracion=%ds target=%d kills | spawn %.1fs->%.1fs | %.0f%% corredores",
        oleada, esUltima and "[ULTIMA]" or "", modoId,
        duracion, target, spawnInicio, spawnFin, pctCorredores * 100
    ))

    -- Notificar al cliente (formato modelo C)
    HoldoorServer.notificarTodos("oleada", {
        numero        = oleada,
        duracion      = duracion,
        target        = target,
        spawnInicio   = spawnInicio,
        spawnFin      = spawnFin,
        pctCorredores = pctCorredores,
        frase         = frase.texto,
        autor         = frase.autor,
        amenaza       = pctCorredores > 0 and "Muertos + corredores" or "Muertos vivientes",
        esUltima      = esUltima,
    })

    -- Estado "activa" para el HUD del cliente
    HoldoorServer.notificarTodos("oleadaActiva", {
        numero   = oleada,
        duracion = duracion,
        target   = target,
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

    local pendientes = 0
    for _, t in ipairs(estado.encoladosTiers or {}) do pendientes = pendientes + t.count end
    -- Contamos zombis vivos cerca SIEMPRE (incluso si pendientes==0) para detectar
    -- el caso "perdidos al final" → si quedan < 3 vivos y la cola esta vacia,
    -- spawneamos refuerzo de cierre para evitar que el user tenga que cazar zombis lejanos.

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

    -- Caso A: oleada en curso con pendientes en cola → mantener densidad minima cerca de la base.
    -- Caso B: cola vacia pero zombiesRestantes (TOTAL real) < 3 → spawnear "refuerzo de cierre"
    --         para que la oleada termine pronto. SOLO se dispara UNA VEZ por oleada (flag).
    local minimo = HoldoorServer._colchonMinimo or 5
    local FINAL_MIN = 3
    local FINAL_REFUERZO = 3

    if pendientes > 0 and vivos < minimo then
        local faltan = math.min(minimo - vivos, pendientes)
        print(string.format("[Holdoor] Colchon: solo %d vivos cerca (min %d), refuerzo de %d", vivos, minimo, faltan))
        estado.proximaTandaSec = os.time() - 1
        local origTamanoTanda = estado.tamanoTanda
        estado.tamanoTanda = faltan
        HoldoorServer._spawnTanda()
        estado.tamanoTanda = origTamanoTanda

    elseif pendientes == 0
           and (estado.zombiesRestantes or 0) > 0
           and (estado.zombiesRestantes or 0) < FINAL_MIN
           and not estado._colchonFinalDisparado then
        -- BUG FIX (2026-06-15): antes usaba `vivos` (cerca del radio). Si quedaban 4 zombies
        -- pero 2 estaban lejos, vivos=2 → disparaba refuerzo. Y al chequear cada 3s entraba
        -- en bucle. Ahora uso zombiesRestantes (total real del mod) + flag de single-shot.
        estado._colchonFinalDisparado = true
        print(string.format("[Holdoor] Colchon FINAL: %d zombis totales restantes < %d → refuerzo unico +%d",
            estado.zombiesRestantes, FINAL_MIN, FINAL_REFUERZO))
        estado.zombiesTotal = (estado.zombiesTotal or 0) + FINAL_REFUERZO
        estado.zombiesRestantes = (estado.zombiesRestantes or 0) + FINAL_REFUERZO
        table.insert(estado.encoladosTiers or {}, { tier = "normal", count = FINAL_REFUERZO })
        estado.proximaTandaSec = os.time() - 1
        local origTamanoTanda = estado.tamanoTanda
        estado.tamanoTanda = FINAL_REFUERZO
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
                    -- v0.6 fix: ignorar muertes por TIEMPO no por contador.
                    -- Antes contabamos N muertes a ignorar pero los onZombieDead son async →
                    -- si user mataba zombies mientras los de limpieza estaban procesandose,
                    -- sus kills se "absorbian" por el contador. Ahora ventana fija de 2s.
                    for _, z in ipairs(toRemove) do
                        local ok_kill = false
                        pcall(function() z:setHealth(0.0); ok_kill = true end)
                        if not ok_kill then pcall(function() z:setHealth(0); ok_kill = true end) end
                        if ok_kill then eliminados = eliminados + 1 end
                    end
                    -- Setear ventana de gracia: 2s para que el motor procese los setHealth(0) async
                    if eliminados > 0 then
                        HoldoorServer.estado._zombiesIgnorarHasta = os.time() + 2
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


-- ─────────────────────────────────────────────
-- DISTRIBUCION DE RECOMPENSAS - funcion unica
-- Orquesta: monedas + materiales + items reales.
-- Inputs: modoId (string), numOleada (int), statsJugador (tabla de kills por player).
-- Output: tabla resumen con lo entregado (bronze, silver, gold, materiales, items).
-- ─────────────────────────────────────────────
function HoldoorServer._distribuirRecompensaOleada(modoId, numOleada, statsJugador)
    local cfg = HoldoorServer.estado.config or {}
    -- v0.6 modelo C: no hay `zombisTotalOleada`. Usamos `oleadaKills` reales.
    local oleadaKills  = HoldoorServer.estado.oleadaKills or 0
    local oleadaTarget = HoldoorServer.estado.oleadaTargetKills or 1
    local cierreLimpio = HoldoorServer.estado.cierreLimpio or false

    local mult = HoldoorConfig.dropMult[modoId] or HoldoorConfig.dropMult.normal
    local rewardTbl = HoldoorConfig.rewardTable[modoId] or HoldoorConfig.rewardTable.normal

    -- ── 1) Performance bonus: ratio kills vs target ──
    local ratioKills = (oleadaKills > 0 and oleadaTarget > 0) and (oleadaKills / oleadaTarget) or 0
    local hayPerformanceBonus = ratioKills >= (HoldoorConfig.performanceThreshold or 0.70)

    -- Perfect run: Trono termino la oleada con HP COMPLETO (no recibio daño)
    local hayPerfectRun = false
    local trono = HoldoorServer.estado.trono
    if trono and trono.piezaCentral and trono.maxHP then
        local hpActual = 0
        pcall(function() hpActual = trono.piezaCentral.obj:getHealth() end)
        if hpActual >= trono.maxHP then
            hayPerfectRun = true
        end
    end

    -- ── 2) MONEDAS ──
    -- v0.6: base por kills REALES de la oleada (no por "total fijo" que ya no existe).
    -- Rebalance: como ahora los kills dan monedas durante la oleada, bajamos la base
    -- de fin de oleada al 60% (recompensaFinOleadaMultV6) para no doblar el ingreso.
    local rebalanceFin = HoldoorConfig.recompensaFinOleadaMultV6 or 0.60
    local bronzeBase = math.max(1, math.floor(oleadaKills / 2)) + ZombRand(5)
    bronzeBase = math.floor(bronzeBase * rebalanceFin)

    -- Bonus oleada tardia: +5% por oleada despues de la 3a
    local bonusTardio = math.max(0, (numOleada - 3)) * 0.05
    -- Multiplicador final monedas
    local multMonedas = (mult.monedas or 1.0) * (1.0 + bonusTardio)
    if hayPerformanceBonus then
        multMonedas = multMonedas * (1.0 + (HoldoorConfig.performanceCoinBonus or 0.10))
    end
    if hayPerfectRun then
        multMonedas = multMonedas * (1.0 + (HoldoorConfig.perfectRunCoinBonus or 0.25))
    end
    -- v0.6 BONUS CIERRE LIMPIO: +25% si mataste >= target antes del timer
    if cierreLimpio then
        multMonedas = multMonedas * (1.0 + (HoldoorConfig.cierreLimpioBonus or 0.25))
    end
    local bronze = math.floor(bronzeBase * multMonedas + 0.5)

    -- Plata bonus (chance%): tirada modificada por mult
    local silverChance = (rewardTbl.bonusSilverChance or 0) * multMonedas
    local silver = (ZombRand(1000) < math.floor(silverChance * 1000)) and 1 or 0

    -- Oro bonus (chance%)
    local goldChance = (rewardTbl.bonusGoldChance or 0) * multMonedas
    local gold = (ZombRand(1000) < math.floor(goldChance * 1000)) and 1 or 0

    HoldoorServer._distribuirMonedas(bronze, silver, gold)

    -- ── 3) MATERIALES ──
    local matTbl = HoldoorConfig.materialDropTable[modoId] or HoldoorConfig.materialDropTable.normal
    local multMat = mult.materiales or 1.0
    if hayPerfectRun then
        multMat = multMat * (1.0 + (HoldoorConfig.perfectRunMatBonus or 0.15))
    end
    local matsEntregados = {}
    for _, matKey in ipairs(HoldoorShopCatalog.materialesOrden or {"cuero","hierro","acero","valyrio","obsidiana"}) do
        local def = matTbl[matKey]
        if def and def.chance > 0 then
            local chanceFinal = def.chance * multMat
            if ZombRand(1000) < math.floor(chanceFinal * 1000) then
                local qty = def.min
                if def.max > def.min then qty = qty + ZombRand(def.max - def.min + 1) end
                matsEntregados[matKey] = qty
            end
        end
    end
    -- next() puede ser nil si otro mod sobreescribio el global → usar pairs defensivo.
    local _hayMats = false
    for _k, _ in pairs(matsEntregados) do _hayMats = true; break end
    if _hayMats then
        HoldoorServer._distribuirMateriales(matsEntregados)
    end

    -- ── 4) ITEMS REALES ──
    local multItems = mult.items or 1.0
    local rarezasChances = HoldoorConfig.rarezaChances or {}
    local itemsEntregados = {}   -- lista de strings "Base.X" para el resumen

    for _, pool in pairs(HoldoorConfig.itemDropPool or {}) do
        if pool.items and #pool.items > 0 then
            -- Por cada item del pool, tirar dado segun su rareza
            for _, def in ipairs(pool.items) do
                local chanceBase = rarezasChances[def.rareza or "comun"] or 0
                local chanceFinal = chanceBase * multItems
                if ZombRand(1000) < math.floor(chanceFinal * 1000) then
                    local qty = def.qty and def.qty[1] or 1
                    local maxQ = def.qty and def.qty[2] or qty
                    if maxQ > qty then qty = qty + ZombRand(maxQ - qty + 1) end
                    for _ = 1, qty do
                        table.insert(itemsEntregados, def.item)
                    end
                end
            end
        end
    end
    -- v0.6.1 MP fix: NO entregamos los items aca server-side. _entregarItemsViaAdmin
    -- usa sendServerCommand que NO llega al host local hosted (gotcha #36 aplicado al
    -- caso de items). En vez, mandamos la lista en el comando "oleadaCompletada" y el
    -- cliente del host ejecuta /additem en cliente-context (reusa flow tienda).
    -- itemsEntregados se pasa via "oleadaCompletada" mas abajo en la llamada a notificarTodos.

    print(string.format("[Holdoor] Recompensa oleada %d (%s): %dB %dP %dO | mats=%s | items=%d | perf=%.0f%% (%s) | perfectRun=%s",
        numOleada, modoId, bronze, silver, gold,
        _hayMats and "si" or "no",
        #itemsEntregados,
        ratioKills * 100,
        hayPerformanceBonus and "BONUS" or "no",
        hayPerfectRun and "BONUS" or "no"
    ))

    return {
        bronze = bronze, silver = silver, gold = gold,
        materiales = matsEntregados, items = itemsEntregados,
        performanceBonus = hayPerformanceBonus,
        perfectRun = hayPerfectRun,
    }
end

-- Distribuye materiales a todos los players online (en MP) o al player local (en SP).
-- materiales: tabla {cuero=N, hierro=N, acero=N, valyrio=N, obsidiana=N}
function HoldoorServer._distribuirMateriales(materiales)
    if not materiales then return end
    local _hay = false
    for _k, _ in pairs(materiales) do _hay = true; break end
    if not _hay then return end
    local mdKeyMap = HoldoorShopCatalog.mdKeyMap or {}

    local function darMatsA(p)
        if not p then return end
        local ok, md = pcall(function() return p:getModData() end)
        if not ok or not md then return end
        for matKey, qty in pairs(materiales) do
            local mdKey = mdKeyMap[matKey]
            if mdKey then
                md[mdKey] = (md[mdKey] or 0) + qty
            end
        end
        _persistirModData(p)
    end

    local entregado = false
    local ok, players = pcall(getOnlinePlayers)
    if ok and players then
        local ok2, n = pcall(function() return players:size() end)
        if ok2 and n and n > 0 then
            for i = 0, n - 1 do
                local ok3, p = pcall(function() return players:get(i) end)
                if ok3 and p then darMatsA(p); entregado = true end
            end
        end
    end
    if not entregado then
        local ok2, p = pcall(getSpecificPlayer, 0)
        if ok2 and p then darMatsA(p) end
    end

    HoldoorServer.notificarTodos("materialesActualizados", {})
end

-- Distribuye items reales al inventario del player.
-- items: lista de strings "Base.X" (puede haber duplicados).
-- En B42 InventoryItemFactory puede fallar; fallback: dropear al suelo en el tile del player.
function HoldoorServer._distribuirItems(items)
    if not items or #items == 0 then return end

    local function darItemA(p, itemFullName)
        if not p then return false end
        local inv
        pcall(function() inv = p:getInventory() end)
        if not inv then return false end
        local ok = pcall(function() inv:AddItem(itemFullName) end)
        return ok
    end

    local entregado = false
    local ok, players = pcall(getOnlinePlayers)
    if ok and players then
        local ok2, n = pcall(function() return players:size() end)
        if ok2 and n and n > 0 then
            for i = 0, n - 1 do
                local ok3, p = pcall(function() return players:get(i) end)
                if ok3 and p then
                    for _, itemName in ipairs(items) do
                        if darItemA(p, itemName) then entregado = true end
                    end
                end
            end
        end
    end
    if not entregado then
        local ok2, p = pcall(getSpecificPlayer, 0)
        if ok2 and p then
            for _, itemName in ipairs(items) do
                darItemA(p, itemName)
            end
        end
    end
end

function HoldoorServer._oleadaCompletada()
    local estado = HoldoorServer.estado
    if estado.fase ~= "activa" then return end

    -- Llamada a la funcion UNICA que distribuye TODO (monedas + materiales + items).
    -- Devuelve un resumen con lo que se entrego (para notificar al cliente).
    local resumen = HoldoorServer._distribuirRecompensaOleada(
        estado.config.modoId or "normal",
        estado.oleadaActual or 1,
        estado.killsOleada or {}
    )

    -- Si fue la ultima oleada: ir directo a victoria, sin los 10s de pausa
    local esUltima = (estado.oleadaActual >= (estado.config.maxOleadas or 0))
    if esUltima then
        estado.killsOleada = {}
        HoldoorServer.detenerPorLimite(resumen.silver or 0, resumen.gold or 0)
        return
    end

    -- Limpiar zombis vivos del radio antes de pausa
    local eliminadosFinOleada = HoldoorServer._limpiarZona()
    if eliminadosFinOleada > 0 then
        print("[Holdoor] Fin de oleada: " .. eliminadosFinOleada .. " zombis residuales limpiados")
    end

    -- v0.6: pausa de 30s default, override por modo (TEST usa 5s para testing rapido)
    local modoIdAct = (estado.config and estado.config.modoId) or "normal"
    local modoCfg   = (HoldoorConfig.modosV6 or {})[modoIdAct] or {}
    local pausaSeg  = modoCfg.pausaSeg or HoldoorConfig.pausaOleadasSegV6 or PAUSA_SEGS or 30
    estado.fase        = "pausa"
    estado.pausaFinSec = os.time() + pausaSeg

    local killsStr = buildKillsStr(estado.killsOleada)
    HoldoorServer.notificarTodos("oleadaCompletada", {
        numero       = estado.oleadaActual,
        pausa        = pausaSeg,
        killsStr     = killsStr,
        killsData    = estado.killsOleada,
        bronze       = resumen.bronze or 0,
        silver       = resumen.silver or 0,
        gold         = resumen.gold or 0,
        materiales   = resumen.materiales or {},
        items        = resumen.items or {},
        lucky        = (resumen.silver or 0) + (resumen.gold or 0) > 0,
        cierreLimpio = estado.cierreLimpio or false,   -- v0.6: si fue CIERRE LIMPIO (kills >= target)
        kills        = estado.oleadaKills or 0,
        target       = estado.oleadaTargetKills or 0,
    })

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
        -- v0.6 modelo C: spawn continuo + aggro sostenido + cierre por timer/target.
        -- Reemplaza la lógica vieja de _spawnTanda + _reAggroZombies + _asegurarColchon.
        HoldoorServer._spawnTick()           -- spawn 1 zombi si toca según intervalo lerp
        HoldoorServer._aggroSostenido()      -- addSound cada 4s desde base (radio 120)
        HoldoorServer._chequearCierreOleada() -- cierre por target kills o timer

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
--  v0.6 DROPS POR KILL (escalados por modo)
--  Bronce: silencioso. Plata/Oro/Item: toast épico al cliente.
-- ─────────────────────────────────────────────

function HoldoorServer._rollDropsPorKill(zombie, matadorUsername)
    local estado  = HoldoorServer.estado
    local modoId  = (estado.config and estado.config.modoId) or "normal"
    local mults   = (HoldoorConfig.dropMultPorModoV6 or {})[modoId]
                 or HoldoorConfig.dropMultPorModoV6.normal
    local base    = HoldoorConfig.dropPorKillBase or {}

    -- Calcular chances finales con multiplicadores del modo
    local cBronce = (base.bronceChance or 0.25) * (mults.bronce or 1.0)
    local cPlata  = (base.plataChance  or 0.05) * (mults.plata  or 1.0)
    local cOro    = (base.oroChance    or 0.005) * (mults.oro   or 1.0)
    local cItem   = (base.itemChance   or 0.007) * (mults.item  or 1.0)

    local bronze, silver, gold = 0, 0, 0

    -- Roll bronce (silencioso, sin toast)
    if ZombRand(10000) < math.floor(cBronce * 10000) then
        local bMin = base.bronceMin or 1
        local bMax = base.bronceMax or 3
        bronze = bMin + ZombRand(math.max(1, bMax - bMin + 1))
    end

    -- Roll plata (toast amarillo)
    if ZombRand(10000) < math.floor(cPlata * 10000) then
        silver = 1
    end

    -- Roll oro (toast dorado épico + sonido)
    if ZombRand(10000) < math.floor(cOro * 10000) then
        gold = 1
    end

    -- Distribuir monedas (si hubo algo)
    if bronze > 0 or silver > 0 or gold > 0 then
        HoldoorServer._distribuirMonedas(bronze, silver, gold)
        -- Notif al cliente: el cliente decide si poner toast/sonido segun el tipo.
        -- El cliente SIEMPRE pone player:Say sobre la cabeza (incluso para bronce).
        if gold > 0 then
            HoldoorServer.notificarTodos("dropKill", {
                tipo = "gold", cantidad = gold, texto = "+" .. gold .. " ORO !!!",
            })
        elseif silver > 0 then
            HoldoorServer.notificarTodos("dropKill", {
                tipo = "silver", cantidad = silver, texto = "+" .. silver .. " Plata",
            })
        elseif bronze > 0 then
            HoldoorServer.notificarTodos("dropKill", {
                tipo = "bronce", cantidad = bronze, texto = "+" .. bronze .. " Br",
            })
        end
    end

    -- Roll item raro
    if ZombRand(10000) < math.floor(cItem * 10000) then
        -- Elegir pool random del itemDropPool y un item común de ese pool
        local pools = {}
        for poolName, poolData in pairs(HoldoorConfig.itemDropPool or {}) do
            if poolData.items and #poolData.items > 0 then
                table.insert(pools, poolData)
            end
        end
        if #pools > 0 then
            local pool = pools[ZombRand(#pools) + 1]
            -- Filtrar items comunes y poco comunes (no raros/épicos en drops por kill)
            local candidatos = {}
            for _, def in ipairs(pool.items) do
                if def.rareza == "comun" or def.rareza == "poco_comun" then
                    table.insert(candidatos, def)
                end
            end
            if #candidatos > 0 then
                local def = candidatos[ZombRand(#candidatos) + 1]
                -- v0.6: validar que el item EXISTA en B42 antes de notificar drop.
                -- IMPORTANTE: usar getScriptManager():FindItem() (devuelve nil limpio).
                -- InventoryItemFactory.CreateItem() TIRA excepcion Java atrapada por Break On Error
                -- aunque este dentro de pcall (gotcha PZ B42 — pcall no atrapa exceptions Java).
                local itemValido = false
                local sm = getScriptManager and getScriptManager() or nil
                if sm then
                    local scr = sm:FindItem(def.item)
                    itemValido = (scr ~= nil)
                end
                if itemValido then
                    local qtyMin = (def.qty and def.qty[1]) or 1
                    local qtyMax = (def.qty and def.qty[2]) or 1
                    local qty = qtyMin + ZombRand(math.max(1, qtyMax - qtyMin + 1))
                    local items = {}
                    for _ = 1, qty do table.insert(items, def.item) end
                    -- v0.6.1 MP fix: NO entregamos aca (sendServerCommand al host local no
                    -- llega via loopback - gotcha #36 aplicado a items). Mandamos items+target
                    -- en el notificarTodos "dropKill" y el cliente del matador ejecuta /additem.
                    local nombreItem = def.item:gsub("^Base%.", "")
                    HoldoorServer.notificarTodos("dropKill", {
                        tipo = "item",
                        cantidad = qty,
                        texto = "Loot raro: " .. (qty > 1 and (qty .. "x ") or "") .. nombreItem,
                        target = matadorUsername,
                        items = items,
                    })
                else
                    -- Item no válido en este build de B42 — saltear silencioso (no crashear ni mostrar toast fantasma)
                    print("[Holdoor] dropKill: item '" .. tostring(def.item) .. "' no existe en B42, saltado")
                end
            end
        end
    end

    -- v0.6: drops de materiales por kill. Chances muy bajas (Cuero 5% → Obsidiana 0.1%).
    -- Aplica mult del modo (Pesadilla casi triplica las chances).
    local matsBase = HoldoorConfig.dropMaterialesPorKillBase or {}
    local matCfgs = {
        { key = "Holdoor_Cuero",     chance = (matsBase.cueroChance     or 0) * (mults.bronce or 1), nombre = "Cuero",     col = "cuero" },
        { key = "Holdoor_Hierro",    chance = (matsBase.hierroChance    or 0) * (mults.plata  or 1), nombre = "Hierro",    col = "hierro" },
        { key = "Holdoor_Acero",     chance = (matsBase.aceroChance     or 0) * (mults.plata  or 1), nombre = "Acero",     col = "acero" },
        { key = "Holdoor_Valyrio",   chance = (matsBase.valyrioChance   or 0) * (mults.oro    or 1), nombre = "Valyrio",   col = "valyrio" },
        { key = "Holdoor_Obsidiana", chance = (matsBase.obsidianaChance or 0) * (mults.oro    or 1), nombre = "Obsidiana", col = "obsidiana" },
    }
    for _, m in ipairs(matCfgs) do
        if ZombRand(10000) < math.floor(m.chance * 10000) then
            -- Distribuir 1 material directamente al ModData del player
            local materiales = { [m.col] = 1 }
            HoldoorServer._distribuirMateriales(materiales)
            HoldoorServer.notificarTodos("dropKill", {
                tipo = "material",
                cantidad = 1,
                texto = "+1 " .. m.nombre,
                material = m.col,
            })
            -- Solo 1 material por kill (si cayó cuero, no testeamos los más raros)
            break
        end
    end
end

-- ─────────────────────────────────────────────
--  KILL COUNTER — avanza cuando se mata un zombi
-- ─────────────────────────────────────────────

function HoldoorServer.onZombieMuerto(zombie)
    local estado = HoldoorServer.estado
    if estado.fase ~= "activa" then return end

    -- v0.6 fix: ignorar muertes durante ventana de 2s post-limpieza (no por contador).
    -- Los setHealth(0) async de _limpiarZona se procesan en <2s. Despues todo cuenta.
    if os.time() < (estado._zombiesIgnorarHasta or 0) then return end

    -- Ignorar muertes de zombies que mueren lejos de la base (mundo normal, no del mod)
    local ok, zx, zy = pcall(function() return zombie:getX(), zombie:getY() end)
    if ok and zx then
        local dx = zx - estado.baseX
        local dy = zy - estado.baseY
        local radioFiltro = (estado.config.radioSpawn or 20) + 40
        if (dx * dx + dy * dy) > (radioFiltro * radioFiltro) then return end
    end

    -- v0.6 modelo C: incrementar kills (sin "zombies restantes" porque no hay total fijo).
    estado.oleadaKills = (estado.oleadaKills or 0) + 1

    -- Notificar al cliente del kill (para HUD: actualiza "Kills X/Y" en tiempo real)
    HoldoorServer.notificarTodos("killUpdate", {
        kills  = estado.oleadaKills,
        target = estado.oleadaTargetKills or 0,
    })

    -- v0.6.1 MP: identificar al matador para dropear solo a el (no a todos).
    -- Si no se identifica, fallback al primer player online (SP / hosted solo).
    local matadorUsername = nil
    pcall(function()
        local atk = zombie:getAttackedBy()
        if atk then matadorUsername = atk:getUsername() end
    end)
    if not matadorUsername then
        local ok, p = pcall(getSpecificPlayer, 0)
        if ok and p then pcall(function() matadorUsername = p:getUsername() end) end
    end

    -- Drops por kill (v0.6: escalados por modo). El cierre por target se chequea
    -- en _chequearCierreOleada (llamado desde onTick), no aca.
    HoldoorServer._rollDropsPorKill(zombie, matadorUsername)
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

-- Quita la base: destruye el Trono y resetea el estado. Bloquea si hay oleada activa.
function HoldoorServer.quitarBase(jugador)
    local estado = HoldoorServer.estado
    if not estado.baseDefinida then
        pcall(sendClientCommand, jugador, HoldoorConfig.MODULE, "aviso",
              { mensaje = "No hay base marcada todavia." })
        return
    end
    if estado.activo and estado.fase == "activa" then
        pcall(sendClientCommand, jugador, HoldoorConfig.MODULE, "aviso",
              { mensaje = "No podes quitar la base con una oleada en curso. Deten las oleadas primero." })
        return
    end

    HoldoorServer._quitarTrono()
    estado.baseDefinida = false
    estado.baseX, estado.baseY, estado.baseZ = 0, 0, 0

    -- Borrar de ModData del jugador para que no reaparezca al re-loguear
    pcall(function()
        local md = jugador:getModData()
        if md then
            md.baseDefinida = false
            md.baseX, md.baseY, md.baseZ = nil, nil, nil
        end
    end)

    HoldoorServer.notificarTodos("baseQuitada", {})
    print("[Holdoor] Base quitada por " .. jugador:getUsername())
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
-- Layout del Trono: 1 sola pieza (la forja). HP se calcula por modo en _plantarTrono.
-- El sprite real queda tapado por el overlay PNG del Trono de Hierro.
HoldoorServer._tronoLayoutForja = {
    -- {dx, dy, sprite, esCentro}  -- HP se asigna por modo, no hardcoded
    { 0, 0, "crafted_01_16", true },
}

-- Devuelve el HP del Trono para un modo dado. Default = facil (1500) si no se encuentra.
function HoldoorServer._getHPTronoPorModo(modoId)
    local tabla = HoldoorConfig.tronoHPPorModo or {}
    return tabla[modoId or "normal"] or 1500
end

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

    -- HP del modo actual (1500 facil, 1250 normal, 1100 dificil, 1000 pesadilla)
    local modoId = (HoldoorServer.estado.config and HoldoorServer.estado.config.modoId) or "normal"
    local hpModo = HoldoorServer._getHPTronoPorModo(modoId)
    HoldoorServer._tronoHPTotal = hpModo

    local piezas = {}
    local piezaCentral = nil
    local allOk = true

    for _, pieza in ipairs(HoldoorServer._tronoLayoutForja) do
        local dx, dy, sprite, esCentro = pieza[1], pieza[2], pieza[3], pieza[4]
        local hpAbs = hpModo   -- la pieza central usa el HP del modo (es la única pieza)
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

        -- v0.6.1: sync MP del IsoThumpable a clientes remotos (gotcha #8 fix).
        -- Test 2026-06-16: probamos 5 APIs candidatas con pcall y solo 2 existen en B42:
        --   transmitUpdatedSprite   → OK, esta es la que se mantiene
        --   transmitCompleteItemToServer → existe pero DEPRECATED en MP (warn explicito)
        -- Las otras 3 (syncIsoObject / sendObjectChange / sq:transmitObjectChange) tiran
        -- "Object tried to call nil" porque NO existen en B42, y pcall no atrapa esa
        -- excepcion Java (gotcha #30). Por eso solo dejamos transmitUpdatedSprite.
        -- Si tu amigo en MP no ve el Trono, este sync no fue suficiente — buscar otra API.
        pcall(function() thumpable:transmitUpdatedSprite() end)

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
-- RESET DE BASE AL CARGAR PARTIDA — la base NO persiste entre sesiones
-- Si habia base persistida (ModData del player + IsoThumpable en el mundo),
-- destruimos el Trono fisico y limpiamos el flag. El user marca base de nuevo.
-- ─────────────────────────────────────────────

local function _spritesDelTrono()
    local set = {}
    for _, pieza in ipairs(HoldoorServer._tronoLayoutForja or {}) do
        if pieza and pieza[3] then set[pieza[3]] = true end
    end
    return set
end

function HoldoorServer._limpiarTronoEnPosicion(x, y, z)
    if not x or not y then return 0 end
    local ok_cell, cell = pcall(getCell)
    if not ok_cell or not cell then return 0 end

    local spritesValidos = _spritesDelTrono()
    local eliminados = 0

    -- Buscamos en una grid 5x5 alrededor de (x,y) para cubrir el layout en Cruz
    for dx = -2, 2 do
        for dy = -2, 2 do
            local sq
            pcall(function() sq = cell:getGridSquare(x + dx, y + dy, z or 0) end)
            if sq then
                local objs
                pcall(function() objs = sq:getObjects() end)
                if objs then
                    local toRemove = {}
                    local sz = 0
                    pcall(function() sz = objs:size() end)
                    for i = 0, sz - 1 do
                        local obj
                        pcall(function() obj = objs:get(i) end)
                        if obj then
                            local spriteName
                            pcall(function()
                                local sp = obj:getSprite()
                                if sp then spriteName = sp:getName() end
                            end)
                            if spriteName and spritesValidos[spriteName] then
                                table.insert(toRemove, obj)
                            end
                        end
                    end
                    for _, obj in ipairs(toRemove) do
                        pcall(function() obj:removeFromSquare() end)
                        pcall(function() obj:removeFromWorld() end)
                        eliminados = eliminados + 1
                    end
                end
            end
        end
    end
    return eliminados
end

function HoldoorServer.resetearBaseAlInicio()
    local p
    pcall(function() p = getSpecificPlayer(0) end)
    if not p then return end

    local md
    pcall(function() md = p:getModData() end)
    if not md then return end

    if md.baseDefinida and md.baseX and md.baseY then
        local n = HoldoorServer._limpiarTronoEnPosicion(md.baseX, md.baseY, md.baseZ or 0)
        print(string.format("[Holdoor] Base no persiste entre sesiones — Trono destruido en (%d,%d), %d piezas eliminadas",
            md.baseX, md.baseY, n))
        md.baseDefinida = false
        md.baseX, md.baseY, md.baseZ = nil, nil, nil
    end

    HoldoorServer.estado.baseDefinida = false
    HoldoorServer.estado.baseX, HoldoorServer.estado.baseY, HoldoorServer.estado.baseZ = 0, 0, 0
end

Events.OnGameStart.Add(HoldoorServer.resetearBaseAlInicio)

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
    -- v0.6.1 fix final: en MP hosted, sendServerCommand al host local NO llega via
    -- loopback (mismo proceso). Por eso llamamos onComandoServidor directo PRIMERO para
    -- que el HUD del host se sincronize. Esto se ejecuta en server-context, donde APIs
    -- como InventoryItemFactory son null — PERO ahora los items se entregan via /additem
    -- (cliente-side, fuera de notificarTodos), entonces no hay choque de context.
    -- Para clientes remotos, sendServerCommand SÍ llega (van por la red).
    if type(HoldoorClient) == "table" and HoldoorClient.onComandoServidor then
        pcall(HoldoorClient.onComandoServidor, HoldoorConfig.MODULE, tipo, datos)
    end

    -- Broadcast a clientes remotos (excluye al host local que ya manejamos arriba)
    local localUser
    pcall(function()
        local lp = getSpecificPlayer(0)
        if lp then localUser = lp:getUsername() end
    end)

    local ok, players = pcall(getOnlinePlayers)
    if ok and players then
        local ok2, n = pcall(function() return players:size() end)
        if ok2 and n and n > 0 then
            for i = 0, n - 1 do
                local ok3, p = pcall(function() return players:get(i) end)
                if ok3 and p then
                    local pUser
                    pcall(function() pUser = p:getUsername() end)
                    if pUser ~= localUser then
                        pcall(sendServerCommand, p, HoldoorConfig.MODULE, tipo, datos)
                    end
                end
            end
        end
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
    elseif comando == "quitarBase" then
        HoldoorServer.quitarBase(jugador)

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

    elseif comando == "delegarAddXp" or comando == "delegarAddItem" then
        -- v0.6.1: cliente NO admin pidio entregar XP/items. Delegamos al host admin.
        local hostAdmin = HoldoorServer._buscarHostAdmin()
        if hostAdmin then
            local nextCmd = (comando == "delegarAddXp") and "ejecutarAddXp" or "ejecutarAddItem"
            pcall(function()
                sendServerCommand(hostAdmin, HoldoorConfig.MODULE, nextCmd, args)
            end)
            print("[Holdoor] " .. comando .. ": delegado a " .. tostring(hostAdmin:getUsername()) .. " para " .. tostring(args.target))
        else
            print("[Holdoor] " .. comando .. " WARN: no hay admin online")
        end

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

-- v0.6.1: handler de muerte de player. Si todos los participantes de la oleada activa
-- mueren o se desconectan → oleada se da por perdida.
function HoldoorServer._onPlayerMuerto(jugador)
    local estado = HoldoorServer.estado
    if not estado.activo then return end
    if not estado.participantes then return end

    local username
    pcall(function() username = jugador:getUsername() end)
    if not username then return end

    print("[Holdoor] Player muerto: " .. tostring(username))
    estado.participantes[username] = nil  -- removerlo del registro

    -- Chequear si quedan participantes vivos y conectados
    local quedanVivos = 0
    pcall(function()
        local ok, ps = pcall(getOnlinePlayers)
        if ok and ps then
            local oks, np = pcall(function() return ps:size() end)
            if oks and np then
                for i = 0, np - 1 do
                    local okp, p = pcall(function() return ps:get(i) end)
                    if okp and p then
                        local u, dead
                        pcall(function() u = p:getUsername() end)
                        pcall(function() dead = p:isDead() end)
                        if u and not dead and estado.participantes[u] then
                            quedanVivos = quedanVivos + 1
                        end
                    end
                end
            end
        end
    end)

    if quedanVivos == 0 then
        print("[Holdoor] TODOS los participantes muertos/desconectados → oleada perdida")
        HoldoorServer.notificarTodos("derrotaColectiva", {
            oleadas = estado.oleadaActual or 0,
            mensaje = "El Trono ha caido. Todos los defensores han caido.",
        })
        -- Reusar la logica de derrota del Trono
        HoldoorServer._tronoCayo()
    else
        HoldoorServer.notificarTodos("playerCaido", {
            username = username,
            vivos = quedanVivos,
        })
        print("[Holdoor] Quedan " .. quedanVivos .. " defensores vivos")
    end
end

Events.OnGameStart.Add(HoldoorServer.init)
Events.OnTick.Add(HoldoorServer.onTick)
Events.OnZombieDead.Add(HoldoorServer.onZombieMuerto)
Events.OnClientCommand.Add(HoldoorServer.onComandoCliente)
Events.OnPlayerDeath.Add(HoldoorServer._onPlayerMuerto)

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
