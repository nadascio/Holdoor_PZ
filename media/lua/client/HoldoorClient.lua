-- ============================================================
--  Holdoor — Sistema de Oleadas  |  Cliente
--  Recibe notificaciones del servidor y maneja el chat/UI
-- ============================================================

require "HoldoorConfig"

HoldoorClient = HoldoorClient or {}

-- ─────────────────────────────────────────────
--  HELPERS DE SONIDO
--  Deshabilitados por defecto en B42 hasta identificar nombres validos.
--  Activar con HoldoorClient.soundsEnabled = true cuando se confirme una API que funcione.
-- ─────────────────────────────────────────────

HoldoorClient.soundsEnabled = false  -- toggle a true cuando sepamos que nombres funcionan en B42

local function playUISound(name)
    if not HoldoorClient.soundsEnabled then return end
    pcall(function() getSoundManager():PlayUISound(name) end)
end

local function playSequence(secuencia)
    if not HoldoorClient.soundsEnabled then return end
    for _, par in ipairs(secuencia) do
        local nombre = par[1]
        local delay  = par[2] or 0
        if delay <= 0 then
            playUISound(nombre)
        else
            local tick = 0
            local targetTicks = math.floor(delay / 16)
            local handler
            handler = function()
                tick = tick + 1
                if tick >= targetTicks then
                    playUISound(nombre)
                    Events.OnTick.Remove(handler)
                end
            end
            Events.OnTick.Add(handler)
        end
    end
end

HoldoorClient._playUISound = playUISound
HoldoorClient._playSequence = playSequence

-- ─────────────────────────────────────────────
--  SALDO DE MONEDAS (lee ModData del jugador local)
-- ─────────────────────────────────────────────

function HoldoorClient.getSaldo()
    local p = getSpecificPlayer(0)
    if not p then return 0, 0, 0 end
    local ok, md = pcall(function() return p:getModData() end)
    if not ok or not md then return 0, 0, 0 end
    return md.Holdoor_Bronze or 0, md.Holdoor_Silver or 0, md.Holdoor_Gold or 0
end

-- Devuelve los 5 materiales (cuero, hierro, acero, valyrio, obsidiana)
function HoldoorClient.getMateriales()
    local p = getSpecificPlayer(0)
    local def = { cuero=0, hierro=0, acero=0, valyrio=0, obsidiana=0 }
    if not p then return def end
    local ok, md = pcall(function() return p:getModData() end)
    if not ok or not md then return def end
    return {
        cuero     = md.Holdoor_Cuero     or 0,
        hierro    = md.Holdoor_Hierro    or 0,
        acero     = md.Holdoor_Acero     or 0,
        valyrio   = md.Holdoor_Valyrio   or 0,
        obsidiana = md.Holdoor_Obsidiana or 0,
    }
end

-- Lista de jugadores conectados EXCLUYENDO al jugador local. Para el dropdown del modal.
function HoldoorClient.jugadoresConectados()
    local lista = {}
    local selfp = getSpecificPlayer(0)
    local selfName = selfp and selfp:getUsername() or ""
    local ok, players = pcall(getOnlinePlayers)
    if ok and players then
        local ok2, n = pcall(function() return players:size() end)
        if ok2 and n then
            for i = 0, n - 1 do
                local ok3, p = pcall(function() return players:get(i) end)
                if ok3 and p then
                    local okU, u = pcall(function() return p:getUsername() end)
                    if okU and u and u ~= "" and u ~= selfName then
                        table.insert(lista, u)
                    end
                end
            end
        end
    end
    return lista
end

-- Estado local del cliente (reflejo del servidor)
HoldoorClient.estado = {
    activo            = false,
    fase              = "inactivo",  -- "inactivo" / "preparacion" / "activa" / "pausa"
    oleadaActual      = 0,
    baseX             = 0,
    baseY             = 0,
    baseZ             = 0,
    baseDefinida      = false,
    config            = {},
    zombiesRestantes  = 0,
    zombiesTotal      = 0,
    srTotal           = 0,
    countdownFinLocal = 0,
    modoId            = "normal",
    numJugadores      = 1,
    playerMultiplier  = 1.0,
    -- Stats personales del jugador local
    killsOleada       = 0,   -- kills en la oleada actual (se resetea cada oleada)
    killsPartida      = 0,   -- kills totales en la partida (se resetea al iniciar)
}

-- ─────────────────────────────────────────────
--  HELPER: ¿es el jugador local admin/host?
--  SP / hosting local → siempre true
--  MP cliente → solo si tiene nivel Admin o Moderator
-- ─────────────────────────────────────────────

function HoldoorClient.esAdmin()
    -- SP puro: siempre admin (isClient=false)
    local ok, client = pcall(isClient)
    if not ok or not client then return true end

    -- MP host de partida HOSTED (cliente que inicio el server desde "Host"):
    -- isCoopHost() devuelve true. PZ B42 reporta al host como AccessLevel="user"
    -- por default → necesitamos este bypass. (isServer() solo es true en dedicated.)
    -- Refs vanilla: media/lua/client/JoyPad/ISJoyPadListBox.lua:12,
    -- media/lua/client/OptionScreens/InviteFriends.lua:338.
    local ok_host, esHost = pcall(isCoopHost)
    if ok_host and esHost then
        print("[Holdoor] esAdmin: detectado como CoopHost → admin OK")
        return true
    end

    -- MP server dedicated (poco comun en este mod, pero por las dudas)
    local ok_srv, srv = pcall(isServer)
    if ok_srv and srv then return true end

    -- MP cliente remoto: depende del AccessLevel
    local player = getSpecificPlayer(0)
    if not player then return false end

    local ok2, level = pcall(function() return player:getAccessLevel() end)
    if not ok2 then return true end  -- API no disponible: permitir (mejor UX)

    if not level then return true end

    -- Case-insensitive: PZ B42 puede devolver "admin" o "Admin" segun version
    local lvl = string.lower(tostring(level))
    print("[Holdoor] AccessLevel detectado: '" .. lvl .. "'")

    -- Cualquier nivel staff cuenta como admin para el mod (Admin/Moderator/GM/Overseer)
    if lvl == "admin" or lvl == "moderator" or lvl == "gm" or lvl == "overseer" then
        return true
    end
    -- Tambien aceptar si la string contiene "admin" (algunas custom levels)
    if string.find(lvl, "admin") then return true end

    -- None / vacio / Player / Observer: no es admin
    return false
end

-- Records: mejor oleada alcanzada por modo (persistido en ModData)
function HoldoorClient.guardarRecord(modoId, oleada)
    local ok, md = pcall(ModData.getOrCreate, "Holdoor")
    if not ok or not md then return end
    local key = "record_" .. (modoId or "normal")
    local prev = md[key] or 0
    if oleada > prev then
        md[key] = oleada
        print("[Holdoor] Nuevo record en " .. modoId .. ": oleada " .. oleada)
    end
end

function HoldoorClient.obtenerRecord(modoId)
    local ok, md = pcall(ModData.getOrCreate, "Holdoor")
    if not ok or not md then return 0 end
    return md["record_" .. (modoId or "normal")] or 0
end

-- Último valor mostrado en el HUD (para evitar repintar cada frame)
HoldoorClient.ultimoSegsHUD = -1

-- ─────────────────────────────────────────────
--  DETECCIÓN SINGLE PLAYER
--  En B42 SP, server y client comparten el mismo estado Lua,
--  por eso HoldoorServer es accesible desde acá.
-- ─────────────────────────────────────────────

local function tieneServidorLocal()
    return type(HoldoorServer) == "table" and type(HoldoorServer.iniciar) == "function"
end

-- ─────────────────────────────────────────────
--  APLICAR / QUITAR TRAITS LOCALMENTE
--  En B42 las APIs de traits viven en contexto CLIENTE, no server.
--  Por eso el server delega a estas funciones via OnServerCommand "aplicarTrait"/"curarTrait".
-- ─────────────────────────────────────────────

-- API REAL B42 (confirmada en media/lua/client/ISUI/PlayerStats/ISPlayerStatsUI.lua:594):
--   local def = CharacterTraitDefinition.getCharacterTraitDefinition("strong")
--   p:getCharacterTraits():add(def:getType())          -- requiere CharacterTrait, NO string
--   p:modifyTraitXPBoost(def:getType(), false)
--   SyncXp(p)
-- IDs B42: minusculas, definidos en media/scripts/generated/characters/character_traits.txt
-- (ej: "strong", "athletic", "out of shape" con espacios literales).

local function _resolverTraitEnum(traitId)
    -- traitId viene como nombre del enum, ej "STRONG" / "OUT_OF_SHAPE" / "EAGLE_EYED".
    -- Acceso directo al campo estatico del enum Java CharacterTrait via indexacion Lua.
    local enum = nil
    pcall(function()
        enum = CharacterTrait[traitId]
    end)
    -- Fallback: si el acceso por indexacion fallo, intentar CharacterTrait.valueOf(...)
    if not enum then
        pcall(function() enum = CharacterTrait.valueOf(traitId) end)
    end
    print("[Holdoor] _resolverTraitEnum('" .. tostring(traitId) .. "') = " .. tostring(enum))
    return enum
end

function HoldoorClient.aplicarTraitLocal(traitId)
    local p = getSpecificPlayer(0)
    if not p then return false end

    local traitEnum = _resolverTraitEnum(traitId)
    if not traitEnum then
        print("[Holdoor] aplicarTraitLocal: no se pudo resolver '" .. tostring(traitId) .. "' (ID invalido)")
        HoldoorClient.chat("[HOLDOOR] Rasgo desconocido: '" .. tostring(traitId) .. "'. Reportar bug.", 1, 0.3, 0.2)
        return false
    end

    local ok = false
    pcall(function()
        p:getCharacterTraits():add(traitEnum)
        pcall(function() p:modifyTraitXPBoost(traitEnum, false) end)
        pcall(function() SyncXp(p) end)
        ok = true
        print("[Holdoor] trait AGREGADO: " .. tostring(traitId))
    end)

    if not ok then
        print("[Holdoor] aplicarTraitLocal FAIL: '" .. tostring(traitId) .. "'")
        HoldoorClient.chat("[HOLDOOR] No se pudo aplicar el rasgo. Reportar bug.", 1, 0.3, 0.2)
    else
        HoldoorClient.chat("[HOLDOOR] Rasgo heroico aplicado!", 0.3, 1, 0.5)
    end
    return ok
end

function HoldoorClient.curarTraitLocal(traitId)
    local p = getSpecificPlayer(0)
    if not p then return false end

    local traitEnum = _resolverTraitEnum(traitId)
    if not traitEnum then
        print("[Holdoor] curarTraitLocal: no se pudo resolver '" .. tostring(traitId) .. "'")
        HoldoorClient.chat("[HOLDOOR] Rasgo desconocido. Reportar bug.", 1, 0.3, 0.2)
        return false
    end

    local ok = false
    pcall(function()
        p:getCharacterTraits():remove(traitEnum)
        pcall(function() p:modifyTraitXPBoost(traitEnum, true) end)
        pcall(function() SyncXp(p) end)
        ok = true
        print("[Holdoor] trait QUITADO: " .. tostring(traitId))
    end)

    if not ok then
        print("[Holdoor] curarTraitLocal FAIL: '" .. tostring(traitId) .. "'")
        HoldoorClient.chat("[HOLDOOR] No se pudo curar el rasgo. Reportar bug.", 1, 0.3, 0.2)
    else
        HoldoorClient.chat("[HOLDOOR] Milagro del Maestre obrado!", 0.5, 1, 0.8)
    end
    return ok
end

-- ─────────────────────────────────────────────
--  RECIBIR NOTIFICACIONES DEL SERVIDOR
-- ─────────────────────────────────────────────

function HoldoorClient.onComandoServidor(modulo, comando, args)
    if modulo ~= HoldoorConfig.MODULE then return end

    if comando == "oleada" then
        HoldoorClient.mostrarOleada(args)

    elseif comando == "iniciado" then
        HoldoorClient.estado.activo        = true
        HoldoorClient.estado.killsOleada   = 0
        HoldoorClient.estado.killsPartida  = 0
        if args.config    then HoldoorClient.estado.config           = args.config    end
        if args.numPlayers then HoldoorClient.estado.numJugadores    = args.numPlayers end
        if args.multiplier then HoldoorClient.estado.playerMultiplier = args.multiplier end
        HoldoorClient.chat("[HOLDOOR] Sistema de oleadas ACTIVADO! Preparate...", 1, 0.4, 0.1)
        if HoldoorUI then HoldoorUI.actualizarTodo() end

    elseif comando == "detenido" then
        local oleadasAlcanzadas = HoldoorClient.estado.oleadaActual
        if oleadasAlcanzadas > 0 then
            HoldoorClient.guardarRecord(HoldoorClient.estado.modoId, oleadasAlcanzadas)
        end
        HoldoorClient.estado.activo          = false
        HoldoorClient.estado.fase            = "inactivo"
        HoldoorClient.estado.zombiesRestantes = 0
        HoldoorClient.estado.zombiesTotal     = 0
        HoldoorClient.chat("[HOLDOOR] Sistema de oleadas detenido.", 0.7, 0.7, 0.7)
        if HoldoorUI then HoldoorUI.actualizarTodo() end

    elseif comando == "completado" then
        HoldoorClient.estado.activo = false
        HoldoorClient.estado.fase   = "inactivo"
        local oleadas = args.oleadas or 0
        HoldoorClient.guardarRecord(HoldoorClient.estado.modoId, oleadas)

        -- Armar linea de premio final
        local parts = {}
        if (args.silver or 0) > 0 then table.insert(parts, args.silver .. " Plata") end
        if (args.gold   or 0) > 0 then table.insert(parts, args.gold   .. " Oro")   end
        local premioStr = #parts > 0 and ("[ +" .. table.concat(parts, ", ") .. " ]") or ""

        HoldoorClient.chat("[HOLDOOR] Victoria! Sobreviviste " .. oleadas .. " oleadas." .. (premioStr ~= "" and ("  " .. premioStr) or ""), 0.2, 1, 0.4)

        -- Narrativa de fortuna: si el oro era probabilistico Y cayo, destacar
        local goldChance = args.goldChance or 1.0
        if (args.gold or 0) > 0 and goldChance < 1.0 then
            HoldoorClient.chat("[HOLDOOR] *** Los dioses te sonrien: " .. args.gold .. " ORO !!! ***", 1.0, 0.85, 0.15)
        elseif (args.gold or 0) == 0 and goldChance < 1.0 then
            HoldoorClient.chat("[HOLDOOR] La fortuna no estuvo de tu lado esta vez (sin oro).", 0.6, 0.6, 0.55)
        end

        -- Fanfarria de victoria: 3 dings encadenados + alarma final
        playSequence({
            {"LevelPerk", 0},
            {"LevelPerk", 250},
            {"LevelPerk", 500},
            {"BurglarAlarm1", 900},
        })

        -- Anuncio épico de victoria final con ranking total
        if HoldoorAnnounce then
            local killsStr = args.killsStr or ""
            local subLine  = premioStr ~= "" and premioStr or (killsStr ~= "" and ("RANKING -- " .. killsStr) or "")
            HoldoorAnnounce.mostrar(
                "!LA GUARDIA NOCTURNA PREVALECE!",
                "Valar Morghulis.  Hold the door.",
                0.95, 0.80, 0.18,
                420,
                subLine
            )
        end

        if HoldoorUI then HoldoorUI.actualizarTodo() end

    elseif comando == "preparacion" then
        HoldoorClient.estado.fase             = "preparacion"
        HoldoorClient.estado.countdownFinLocal = os.time() + (args.segundos or 60)
        HoldoorClient.ultimoSegsHUD           = -1
        if HoldoorUI then HoldoorUI.actualizarTodo() end

    elseif comando == "oleadaActiva" then
        -- v0.6 modelo C: recibimos duracion + target en vez de zombies fijos
        HoldoorClient.estado.fase             = "activa"
        HoldoorClient.estado.oleadaInicioSec  = os.time()  -- timer local del cliente
        HoldoorClient.estado.oleadaDuracionSec = args.duracion or 180
        HoldoorClient.estado.oleadaTargetKills = args.target or 50
        HoldoorClient.estado.oleadaKills      = 0
        HoldoorClient.estado.killsOleada      = 0  -- resetear contador personal
        -- Compatibilidad: zombies total/restantes ya no se usan, los dejamos en 0
        HoldoorClient.estado.zombiesTotal     = 0
        HoldoorClient.estado.zombiesRestantes = 0
        HoldoorClient.estado.srTotal          = 0
        -- Auto-expandir HUD al inicio de oleada
        if HoldoorHUD and HoldoorHUD.instance and not HoldoorHUD.instance.expandido then
            HoldoorHUD.instance:_setExpandido(true)
        end
        if HoldoorUI then HoldoorUI.actualizarTodo() end

    elseif comando == "killUpdate" then
        -- v0.6 modelo C: el server avisa cuando suben los kills (para refresh HUD en vivo)
        HoldoorClient.estado.oleadaKills      = args.kills or 0
        HoldoorClient.estado.oleadaTargetKills = args.target or HoldoorClient.estado.oleadaTargetKills
        if HoldoorUI then HoldoorUI.actualizarTodo() end

    elseif comando == "dropKill" then
        -- v0.6 drops por kill: notif sobre la cabeza del personaje (player:Say) + toast épico arriba
        local r, g, b = 0.95, 0.85, 0.45   -- amarillo plata por default
        if args.tipo == "gold" then r, g, b = 1.0, 0.85, 0.20             -- dorado épico
        elseif args.tipo == "item" then r, g, b = 0.80, 0.55, 1.0         -- violeta loot
        elseif args.tipo == "bronce" then r, g, b = 0.85, 0.55, 0.30      -- bronce
        elseif args.tipo == "material" then
            -- Colores por tipo de material
            if args.material == "cuero"     then r, g, b = 0.75, 0.55, 0.35
            elseif args.material == "hierro" then r, g, b = 0.65, 0.65, 0.70
            elseif args.material == "acero"  then r, g, b = 0.80, 0.85, 0.95
            elseif args.material == "valyrio" then r, g, b = 0.75, 0.45, 1.0
            elseif args.material == "obsidiana" then r, g, b = 0.65, 0.30, 0.85
            end
        end
        -- Sobre la cabeza del personaje (player:Say) — el user lo quiere asi
        local p = getSpecificPlayer(0)
        if p and args.texto then pcall(function() p:Say(args.texto) end) end
        -- Tambien toast arriba (salvo bronce que es muy frecuente)
        if args.tipo ~= "bronce" and HoldoorToast and args.texto then
            pcall(HoldoorToast.mostrar, args.texto, r, g, b)
        end
        -- Sonido para gold/item/material premium (plata y materiales bajos silenciosos por no spammear).
        -- v0.6 fix: usar helper playUISound — pcall directo a getSoundManager crashea en algunos contextos.
        if args.tipo == "gold" or args.tipo == "item" then
            playUISound("LevelPerk")
        elseif args.tipo == "material" and (args.material == "valyrio" or args.material == "obsidiana") then
            playUISound("LevelPerk")
        end

        -- v0.6.1 MP fix: si el dropKill incluye items + target, entregar via /additem en
        -- cliente-context (mismo patron que tienda y fin de oleada). El server puso
        -- args.target = matadorUsername. Solo el cliente local del matador procesa.
        if args.tipo == "item" and args.target and args.items then
            local me = getSpecificPlayer(0)
            local meUser = me and me:getUsername() or nil
            if meUser == args.target then
                if HoldoorClient.esAdmin() then
                    for _, itemName in ipairs(args.items) do
                        local cmd = string.format('/additem "%s" "%s" 1', meUser, tostring(itemName))
                        pcall(function() SendCommandToServer(cmd) end)
                    end
                    print("[Holdoor] dropKill items entregados via /additem (admin): " .. #args.items)
                else
                    sendClientCommand(HoldoorConfig.MODULE, "delegarAddItem", {
                        target = meUser, items = args.items,
                    })
                    print("[Holdoor] dropKill items delegados al host admin: " .. #args.items)
                end
            end
        end

    elseif comando == "zombiesMuertos" then
        -- LEGACY (v0.5): el server viejo emitía este evento. Modelo C usa killUpdate.
        HoldoorClient.estado.zombiesRestantes = args.restantes or 0
        HoldoorClient.estado.zombiesTotal     = args.total or HoldoorClient.estado.zombiesTotal
        if HoldoorUI then HoldoorUI.actualizarTodo() end

    elseif comando == "oleadaCompletada" then
        HoldoorClient.estado.fase             = "pausa"
        local pausaSeg                         = args.pausa or 10
        HoldoorClient.estado.countdownFinLocal = os.time() + pausaSeg
        HoldoorClient.ultimoSegsHUD           = -1

        -- Armar linea de monedas: bronce siempre, plata/oro solo si hubo lucky drop
        local parts = {}
        if (args.bronze or 0) > 0 then table.insert(parts, args.bronze .. " Bronce") end
        if (args.silver or 0) > 0 then table.insert(parts, args.silver .. " Plata") end
        if (args.gold   or 0) > 0 then table.insert(parts, args.gold   .. " Oro")   end
        local monStr = #parts > 0 and ("[ +" .. table.concat(parts, ", ") .. " ]") or ""

        HoldoorClient.chat("[HOLDOOR] Oleada " .. (args.numero or "?") .. " completada! Proxima en " .. pausaSeg .. "s..." .. (monStr ~= "" and ("  " .. monStr) or ""), 0.2, 1, 0.4)

        -- v0.6.1: resumen de items entregados (antes era silencioso → bug confundia con drops sin notif)
        if args.items and #args.items > 0 then
            local conteos = {}
            local orden = {}
            for _, full in ipairs(args.items) do
                local nm = tostring(full):gsub("^Base%.", "")
                if conteos[nm] == nil then table.insert(orden, nm); conteos[nm] = 0 end
                conteos[nm] = conteos[nm] + 1
            end
            local partsI = {}
            for _, nm in ipairs(orden) do
                local c = conteos[nm]
                table.insert(partsI, (c > 1 and (c .. "x ") or "") .. nm)
            end
            local botinStr = "Botin: " .. table.concat(partsI, ", ")
            HoldoorClient.chat("[HOLDOOR] " .. botinStr, 0.80, 0.55, 1.0)
            if HoldoorToast then
                pcall(HoldoorToast.mostrar, botinStr, 0.80, 0.55, 1.0)
            end

            -- v0.6.1 MP fix: entregar los items via /additem en cliente-context. Si soy admin
            -- (host hosted), ejecuto SendCommandToServer directo. Si NO, delego al host admin
            -- via sendClientCommand (mismo patron que la tienda).
            local me = getSpecificPlayer(0)
            local targetUser = me and me:getUsername() or nil
            if targetUser then
                if HoldoorClient.esAdmin() then
                    for _, itemName in ipairs(args.items) do
                        local cmd = string.format('/additem "%s" "%s" 1', targetUser, tostring(itemName))
                        pcall(function() SendCommandToServer(cmd) end)
                    end
                    print("[Holdoor] Botin oleada entregado via /additem (admin): " .. #args.items .. " items")
                else
                    sendClientCommand(HoldoorConfig.MODULE, "delegarAddItem", {
                        target = targetUser, items = args.items,
                    })
                    print("[Holdoor] Botin oleada delegado al host admin: " .. #args.items .. " items")
                end
            end
        end

        -- Si cayo un drop raro: avisar destacado en chat
        if args.lucky then
            if (args.gold or 0) > 0 then
                HoldoorClient.chat("[HOLDOOR] *** JACKPOT! Cayo " .. args.gold .. " Oro ***", 1.0, 0.85, 0.15)
            elseif (args.silver or 0) > 0 then
                HoldoorClient.chat("[HOLDOOR] !!! SUERTE! Drop extra de " .. args.silver .. " Plata", 0.75, 0.85, 1.0)
            end
        end

        playUISound("LevelPerk")

        -- v0.6: si fue CIERRE LIMPIO (kills >= target antes del timer), toast épico
        if args.cierreLimpio and HoldoorToast then
            HoldoorToast.mostrar(
                string.format("CIERRE LIMPIO! +25%% recompensa  (%d/%d kills)",
                    args.kills or 0, args.target or 0),
                1.0, 0.85, 0.30
            )
            -- v0.6 fix: usar helper playUISound (con guards) en vez de pcall directo a
            -- getSoundManager() — eso crasheaba con "Object tried to call nil" que kahlua
            -- NO atrapa (gotcha #18). La helper tiene check + pcall propio.
            playUISound("LevelPerk")
        end

        -- Anuncio épico con ranking de kills y monedas ganadas
        if HoldoorAnnounce then
            local killsStr = args.killsStr or ""
            local subLine  = killsStr ~= "" and killsStr or monStr
            HoldoorAnnounce.mostrar(
                "OLEADA " .. (args.numero or "?") .. " COMPLETADA",
                "La guardia aguanta. Proxima en " .. pausaSeg .. "s...",
                0.22, 1.0, 0.38,
                210,
                subLine
            )
        end

        if HoldoorUI then HoldoorUI.actualizarTodo() end

    elseif comando == "baseActualizada" then
        HoldoorClient.estado.baseX        = args.x
        HoldoorClient.estado.baseY        = args.y
        HoldoorClient.estado.baseZ        = args.z
        HoldoorClient.estado.baseDefinida = true
        if HoldoorUI then HoldoorUI.actualizarTodo() end

    elseif comando == "baseQuitada" then
        HoldoorClient.estado.baseX, HoldoorClient.estado.baseY, HoldoorClient.estado.baseZ = 0, 0, 0
        HoldoorClient.estado.baseDefinida = false
        HoldoorClient.estado.tronoHP, HoldoorClient.estado.tronoMaxHP = nil, nil
        -- Tambien borrar de ModData del propio jugador (persistencia)
        pcall(function()
            local md = ModData.getOrCreate("Holdoor")
            if md then md.baseX, md.baseY, md.baseZ, md.baseDefinida = nil, nil, nil, false end
        end)
        HoldoorClient.chat("[HOLDOOR] Base quitada. Trono destruido.", 0.6, 0.8, 1)
        if HoldoorUI then HoldoorUI.actualizarTodo() end

    elseif comando == "tronoHP" or comando == "braseroHP" then
        HoldoorClient.estado.tronoHP = args.hp or 0
        HoldoorClient.estado.tronoMaxHP = args.maxHp or 0
        if HoldoorUI then HoldoorUI.actualizarTodo() end

    elseif comando == "warningTrono" then
        local r, g, b = 1.0, 0.85, 0.20  -- amarillo default
        if args.color == "rojo" then r, g, b = 1.0, 0.45, 0.20 end
        if args.color == "critico" then r, g, b = 1.0, 0.15, 0.15 end
        HoldoorClient.chat("[HOLDOOR] !!! " .. (args.msg or "ALERTA") .. " !!!", r, g, b)
        if HoldoorAnnounce then
            HoldoorAnnounce.mostrar(
                "!!! " .. (args.msg or "ALERTA") .. " !!!",
                "HP del Trono al " .. (args.pct or "?") .. "%",
                r, g, b, 240
            )
        end

    elseif comando == "tronoCayo" then
        HoldoorClient.estado.activo = false
        HoldoorClient.estado.fase   = "derrotado"
        HoldoorClient.chat("[HOLDOOR] !!! EL TRONO DE HIERRO HA CAIDO !!!", 1, 0.10, 0.10)
        HoldoorClient.chat("[HOLDOOR] La defensa fue rota. Las oleadas se detienen.", 1, 0.30, 0.20)
        if HoldoorAnnounce then
            -- v0.6.1 fix off-by-one: oleadas-1 porque caiste EN la oleada actual,
            -- no la sobreviviste. Ej: si moriste en la 3ra, sobreviviste 2.
            local sobrevividas = math.max(0, (args.oleadas or 1) - 1)
            local subline
            if sobrevividas == 0 then
                subline = "Caiste en la primera oleada."
            elseif sobrevividas == 1 then
                subline = "Sobreviviste 1 oleada. Caiste en la 2da."
            else
                subline = "Sobreviviste " .. sobrevividas .. " oleadas. Caiste en la " .. (sobrevividas + 1) .. "."
            end
            HoldoorAnnounce.mostrar("EL TRONO HA CAIDO", subline, 1.0, 0.10, 0.10, 480)
        end

    elseif comando == "monedasActualizadas" then
        -- Refresca el HUD para que muestre el saldo nuevo
        if HoldoorUI then HoldoorUI.actualizarTodo() end

    elseif comando == "darItem" then
        -- v0.6.1 fix MP definitivo (2026-06-16): items creados con inv:AddItem en cliente
        -- estan SIN sincronizar al server, lo que cancela cualquier TimedAction sobre ellos
        -- (equipar, dropear, etc — la barra verde se corta a 1/5). Workaround: dropear el
        -- item al SUELO via cell:getGridSquare():AddWorldInventoryItem — PZ B42 sincroniza
        -- world items al server automaticamente (mismo flow que loot vanilla). Despues el
        -- user lo recoge con click derecho → "Levantar" (action vanilla syncea bien).
        local me = getSpecificPlayer(0)
        if not me then return end
        local meUser
        pcall(function() meUser = me:getUsername() end)
        if args.target and meUser ~= args.target then return end

        local sq
        pcall(function() sq = me:getCurrentSquare() end)
        if not sq then return end

        local function dropearItem(itemName)
            local item
            pcall(function() item = InventoryItemFactory.CreateItem(itemName) end)
            if item then
                local ok = pcall(function() sq:AddWorldInventoryItem(item, 0.0, 0.0, 0.0) end)
                print("[Holdoor][darItem] '" .. itemName .. "' dropeado al piso ok=" .. tostring(ok))
                return ok
            else
                print("[Holdoor][darItem] CreateItem fallo para '" .. itemName .. "'")
                return false
            end
        end

        if args.item then dropearItem(args.item) end
        if args.items then
            for _, itemName in ipairs(args.items) do dropearItem(itemName) end
        end
        -- Mensaje al user para que sepa que tiene que levantarlo del piso
        local nItems = (args.item and 1 or 0) + (args.items and #args.items or 0)
        if nItems > 0 then
            HoldoorClient.chat("[HOLDOOR] +" .. nItems .. " item" .. (nItems > 1 and "s" or "") .. " a tus pies (click derecho → Levantar)", 0.5, 1, 0.6)
        end

    elseif comando == "transferOK" then
        local tipoLbl = ({bronze="Bronce", silver="Plata", gold="Oro"})[args.tipo] or args.tipo
        HoldoorClient.chat("[HOLDOOR] Enviaste " .. (args.cantidad or 0) .. " " .. tipoLbl .. " a " .. (args.to or "?") .. ".", 0.4, 1, 0.6)
        playUISound("LevelPerk")

    elseif comando == "compraOK" then
        HoldoorClient.chat("[HOLDOOR] Compraste: " .. (args.nombre or "?"), 0.5, 1, 0.6)
        if HoldoorShop and HoldoorShop.refrescar then HoldoorShop.refrescar() end

    elseif comando == "compraFail" then
        HoldoorClient.chat("[HOLDOOR] " .. (args.motivo or "No se pudo completar la compra."), 1, 0.5, 0.2)


    elseif comando == "transferRecibido" then
        local tipoLbl = ({bronze="Bronce", silver="Plata", gold="Oro"})[args.tipo] or args.tipo
        HoldoorClient.chat("[HOLDOOR] Recibiste " .. (args.cantidad or 0) .. " " .. tipoLbl .. " de " .. (args.from or "?") .. "!", 1, 0.85, 0.3)
        playUISound("LevelPerk")

    elseif comando == "aplicarTrait" then
        HoldoorClient.aplicarTraitLocal(args.trait)

    elseif comando == "ejecutarAddXp" then
        if args.target and args.perk and args.amount then
            local cmd = string.format('/addxp "%s" %s=%d', args.target, tostring(args.perk), args.amount)
            pcall(function() SendCommandToServer(cmd) end)
            print("[Holdoor] ejecutarAddXp: " .. cmd)
        end

    elseif comando == "ejecutarAddItem" then
        if args.target and args.items then
            for _, itemName in ipairs(args.items) do
                local cmd = string.format('/additem "%s" "%s" 1', args.target, tostring(itemName))
                pcall(function() SendCommandToServer(cmd) end)
                print("[Holdoor] ejecutarAddItem: " .. cmd)
            end
        end

    elseif comando == "curarTrait" then
        HoldoorClient.curarTraitLocal(args.trait)

    elseif comando == "zonaLimpiada" then
        local n = args.cantidad or 0
        if n > 0 then
            -- v0.6 fix: ignorar por TIEMPO no por contador. Ventana de 2s para que los
            -- setHealth(0) async procesen y NO confundir con kills reales del user.
            HoldoorClient.estado._killsIgnorarHasta = os.time() + 2
            HoldoorClient.chat("[HOLDOOR] Zona despejada: " .. n .. " caminantes eliminados.", 0.4, 0.8, 1)
        end

    elseif comando == "aviso" then
        HoldoorClient.chat("[HOLDOOR] " .. (args.mensaje or ""), 1, 0.8, 0.2)

    elseif comando == "mensaje" then
        HoldoorClient.chat("[HOLDOOR] " .. (args.texto or ""), 1, 0.6, 0.2)

    elseif comando == "ejecutarHordaAdmin" then
        -- v0.7 #13: bridge para spawnear hordas via /createhorde2 admin.
        -- Mismo patron que ejecutarLimpiezaAdmin: queue + procesamiento en onTick
        -- (client-context garantizado). Solo el host hosted / SP / dedicated admin ejecuta.
        HoldoorClient.estado._pendienteHordaAdmin = HoldoorClient.estado._pendienteHordaAdmin or {}
        table.insert(HoldoorClient.estado._pendienteHordaAdmin, {
            x = args.x or 0,
            y = args.y or 0,
            z = args.z or 0,
            count  = args.count  or 15,
            radius = args.radius or 3,
            label  = args.label  or "?",
        })

    elseif comando == "ejecutarLimpiezaAdmin" then
        -- v0.7 #12 POC: bridge para borrar zombies vivos (incluidos arrastradores en attack
        -- state que setHealth(0) NO mata). El handler queda en queue: se procesa en onTick
        -- (client-context garantizado, no server-context del call directo del gotcha #36).
        -- Solo el host hosted / SP / dedicated admin va a ejecutarlo — los demas clientes
        -- reciben el evento pero ignoran en el procesamiento (evita duplicacion 4x en COOPHOST).
        HoldoorClient.estado._pendienteLimpiezaAdmin = {
            x = args.x or 0,
            y = args.y or 0,
            z = args.z or 0,
            radio = args.radio or 50,
        }
        -- Ventana 2s para que OnZombieDead async no se confunda con kills del player.
        HoldoorClient.estado._killsIgnorarHasta = os.time() + 2

    elseif comando == "estado" then
        for k, v in pairs(args) do
            HoldoorClient.estado[k] = v
        end
        -- Reconstruir countdown local desde los segundos restantes del servidor
        if args.fase == "preparacion" and args.countdownSegsLeft then
            HoldoorClient.estado.countdownFinLocal = os.time() + args.countdownSegsLeft
            HoldoorClient.ultimoSegsHUD = -1
        elseif args.fase == "pausa" and args.countdownSegsLeft then
            HoldoorClient.estado.countdownFinLocal = os.time() + args.countdownSegsLeft
            HoldoorClient.ultimoSegsHUD = -1
        end
        if HoldoorUI then HoldoorUI.actualizarTodo() end
    end
end

function HoldoorClient.mostrarOleada(args)
    HoldoorClient.estado.oleadaActual = args.numero or 0
    local sr       = args.speedrunners or 0
    local total    = args.total or args.cantidad or 0
    local esUltima = args.esUltima or false

    HoldoorClient.chat("=================================", 0.6, 0.3, 0.1)
    if esUltima then
        HoldoorClient.chat("!!! ULTIMA OLEADA !!!", 1, 0.1, 0.05)
        -- Alarma de ultima oleada: sube la tension
        playUISound("BurglarAlarm1")
    end
    -- v0.6: removido chat() "OLEADA N -- X en camino" — en modelo C no hay total fijo,
    -- decia "0 en camino" siempre. El cartel grande centrado de HoldoorAnnounce ya tiene la info.
    -- Frase epica (Valar Morghulis, etc): SOLO al toast superior, no sobre la cabeza
    -- (sino se tapa con el cartel grande centrado y otras UIs).
    if args.frase and HoldoorToast then
        local txt = args.frase
        if args.autor then txt = txt .. "  --  " .. args.autor end
        HoldoorToast.mostrar(txt, 0.95, 0.85, 0.45)
    end
    HoldoorClient.chat("=================================", 0.6, 0.3, 0.1)

    -- Anuncio épico centrado
    if HoldoorAnnounce then
        if esUltima then
            local subText = args.amenaza and ("Amenaza: " .. args.amenaza) or ""
            HoldoorAnnounce.mostrar(
                "!!! ULTIMA OLEADA !!!",
                subText .. "  -- Aguanta la puerta.",
                1.0, 0.08, 0.05,
                360
            )
        else
            local subText = args.amenaza and ("Amenaza: " .. args.amenaza) or ""
            HoldoorAnnounce.mostrar(
                "-- OLEADA " .. args.numero .. " --",
                subText,
                1.0, 0.22, 0.08,
                270
            )
        end
    end

    if HoldoorUI then HoldoorUI.actualizarTodo() end
end

-- ─────────────────────────────────────────────
--  TICK — actualiza el countdown en el HUD (tiempo real)
--  Solo redibuja cuando cambia el segundo visible
-- ─────────────────────────────────────────────

-- Tick para refrescar saldo de monedas en el HUD aun en estado inactivo (cada ~2s)
HoldoorClient._saldoTick = 0

function HoldoorClient.onTick()
    local est = HoldoorClient.estado

    -- v0.7 #13: procesar bridge de hordas admin pendiente (/createhorde2).
    -- Mismo patron que limpiezaAdmin abajo: client-context + solo host ejecuta.
    if est._pendienteHordaAdmin and #est._pendienteHordaAdmin > 0 then
        local esHostH = false
        if not isClient() then esHostH = true end
        if not esHostH then local ok1, r1 = pcall(isCoopHost); if ok1 and r1 then esHostH = true end end
        if not esHostH then local ok2, r2 = pcall(isServer);    if ok2 and r2 then esHostH = true end end
        if esHostH then
            while #est._pendienteHordaAdmin > 0 do
                local h = table.remove(est._pendienteHordaAdmin, 1)
                local cmd = string.format("/createhorde2 -x %d -y %d -z %d -count %d -radius %d", h.x or 0, h.y or 0, h.z or 0, h.count or 15, h.radius or 3)
                pcall(function() SendCommandToServer(cmd) end)
                print("[Holdoor] Bridge /createhorde2 horda=" .. (h.label or "?") .. " disparada: " .. cmd)
            end
        else
            -- No soy host: limpiar queue para no acumular indefinidamente.
            est._pendienteHordaAdmin = nil
        end
    end

    -- v0.7 #12 POC: procesar bridge admin pendiente (garantiza client-context).
    -- Solo el host hosted / SP / dedicated admin dispara /removezombies.
    -- Los demas clientes reciben el evento pero ignoran (evita 4x duplicacion en COOPHOST).
    -- Confirmado empiricamente 2026-06-18: en COOPHOST el host puede ejecutar comandos
    -- admin via SendCommandToServer aunque getAccessLevel() reporte "user".
    if est._pendienteLimpiezaAdmin then
        local p = est._pendienteLimpiezaAdmin
        est._pendienteLimpiezaAdmin = nil
        local esHost = false
        if not isClient() then esHost = true end                       -- SP puro
        if not esHost then local ok1, r1 = pcall(isCoopHost); if ok1 and r1 then esHost = true end end  -- COOPHOST host
        if not esHost then local ok2, r2 = pcall(isServer);    if ok2 and r2 then esHost = true end end  -- dedicated server
        if esHost then
            local cmd = string.format("/removezombies -x %d -y %d -z %d -radius %d", p.x or 0, p.y or 0, p.z or 0, p.radio or 50)
            pcall(function() SendCommandToServer(cmd) end)
            print("[Holdoor] Bridge /removezombies disparado: " .. cmd)
        end
    end

    -- v0.6: Refresh del HUD cada segundo durante fase ACTIVA (para que el Timer corra suave).
    -- Antes solo se refrescaba en eventos del server (cada 2s) → saltaba de a 2 segundos.
    if est.fase == "activa" then
        HoldoorClient._activoTick = (HoldoorClient._activoTick or 0) + 1
        if HoldoorClient._activoTick >= 60 then  -- ~1 segundo a 60fps
            HoldoorClient._activoTick = 0
            if HoldoorHUD and HoldoorHUD.instance and HoldoorHUD.instance.expandido then
                pcall(function() HoldoorHUD.instance:actualizarHUD() end)
            end
        end
    end

    -- Refresh periodico del saldo (independiente de la fase del juego)
    HoldoorClient._saldoTick = (HoldoorClient._saldoTick or 0) + 1
    if HoldoorClient._saldoTick >= 120 then  -- ~2 segundos a 60fps
        HoldoorClient._saldoTick = 0
        if HoldoorHUD and HoldoorHUD.instance and HoldoorHUD.instance.expandido then
            pcall(function() HoldoorHUD.instance:actualizarHUD() end)
        end
    end

    if est.fase ~= "preparacion" and est.fase ~= "pausa" then return end

    local segsLeft = math.max(0, math.ceil(est.countdownFinLocal - os.time()))
    if segsLeft ~= HoldoorClient.ultimoSegsHUD then
        HoldoorClient.ultimoSegsHUD = segsLeft
        if HoldoorUI then HoldoorUI.actualizarTodo() end
    end
end

-- ─────────────────────────────────────────────
--  COMANDOS HACIA EL SERVIDOR
-- ─────────────────────────────────────────────

function HoldoorClient.iniciar(config, modoId)
    HoldoorClient.estado.modoId = modoId or "normal"
    if tieneServidorLocal() then
        print("[Holdoor] SP: llamando HoldoorServer.iniciar directamente")
        local player = getSpecificPlayer(0)
        if player then
            local ok, err = pcall(HoldoorServer.iniciar, player, config)
            if not ok then
                print("[Holdoor] SP iniciar ERROR: " .. tostring(err))
                HoldoorClient.chat("[HOLDOOR] Error al iniciar: " .. tostring(err), 1, 0.2, 0.2)
            end
        end
    else
        sendServerCommand(HoldoorConfig.MODULE, "iniciar", { config = config })
    end
end

function HoldoorClient.detener()
    if tieneServidorLocal() then
        -- SP: llamamos HoldoorServer.detener (que incluye limpieza de zombies cercanos).
        -- Antes mutabamos el estado directo → la limpieza nunca corria. Bug 2026-06-15.
        local player = getSpecificPlayer(0)
        if player then
            local ok, err = pcall(HoldoorServer.detener, player)
            if not ok then
                print("[Holdoor] SP detener ERROR: " .. tostring(err))
            end
        end
    else
        sendServerCommand(HoldoorConfig.MODULE, "detener", {})
    end
end

function HoldoorClient.setBase()
    local player = getSpecificPlayer(0)
    if not player then return end
    local x = math.floor(player:getX())
    local y = math.floor(player:getY())
    local z = math.floor(player:getZ())

    HoldoorClient.estado.baseX        = x
    HoldoorClient.estado.baseY        = y
    HoldoorClient.estado.baseZ        = z
    HoldoorClient.estado.baseDefinida = true

    -- NOTA: la base NO persiste entre sesiones por diseno (2026-06-15).
    -- No guardamos en ModData global. Si esta sesion termina, el Trono fisico
    -- se destruye en HoldoorServer.resetearBaseAlInicio al re-cargar.

    if HoldoorUI and HoldoorUI.instancia then
        HoldoorUI.instancia:actualizarEstado()
    end
    HoldoorClient.chat("[HOLDOOR] Base marcada en " .. x .. ", " .. y, 0.4, 0.8, 1)

    if tieneServidorLocal() then
        -- Llamar HoldoorServer.setBase (incluye plantar bandera + side effects)
        local ok, err = pcall(HoldoorServer.setBase, player, x, y, z)
        if not ok then
            print("[Holdoor] SP setBase ERROR: " .. tostring(err))
            -- Fallback: mutacion directa minima
            HoldoorServer.estado.baseX        = x
            HoldoorServer.estado.baseY        = y
            HoldoorServer.estado.baseZ        = z
            HoldoorServer.estado.baseDefinida = true
        end
    else
        sendServerCommand(HoldoorConfig.MODULE, "setBase", { x=x, y=y, z=z })
    end
end

function HoldoorClient.quitarBase()
    local player = getSpecificPlayer(0)
    if not player then return end

    if tieneServidorLocal() then
        local ok, err = pcall(HoldoorServer.quitarBase, player)
        if not ok then
            print("[Holdoor] SP quitarBase ERROR: " .. tostring(err))
            HoldoorClient.chat("[HOLDOOR] Error al quitar base: " .. tostring(err), 1, 0.3, 0.2)
        end
    else
        sendServerCommand(HoldoorConfig.MODULE, "quitarBase", {})
    end
end

function HoldoorClient.oleadaManual()
    if tieneServidorLocal() then
        if not HoldoorServer.estado.activo then
            HoldoorClient.chat("[HOLDOOR] El sistema de oleadas no esta activo.", 1, 0.3, 0.2)
            return
        end
        if not HoldoorServer.estado.baseDefinida then
            HoldoorClient.chat("[HOLDOOR] Primero marca tu base!", 1, 0.3, 0.2)
            return
        end
        if HoldoorServer.estado.fase == "activa" then
            HoldoorClient.chat("[HOLDOOR] Ya hay una oleada en curso. Termina primero.", 1, 0.6, 0.1)
            return
        end
        local ok, err = pcall(HoldoorServer._lanzarOleada)
        if not ok then
            print("[Holdoor] SP oleadaManual ERROR: " .. tostring(err))
            HoldoorClient.chat("[HOLDOOR] Error al forzar oleada: " .. tostring(err), 1, 0.2, 0.2)
        end
    else
        sendServerCommand(HoldoorConfig.MODULE, "oleadaManual", {})
    end
end

-- Verifica si el player local tiene un trait (usa la API B42 que SI esta disponible en cliente).
-- Devuelve nil si no se pudo verificar (mejor permitir que bloquear todo por error).
function HoldoorClient.tieneTrait(traitId)
    local p = getSpecificPlayer(0)
    if not p then return nil end
    local enum = _resolverTraitEnum(traitId)
    if not enum then return nil end
    local tiene = nil
    pcall(function()
        local ct = p:getCharacterTraits()
        if ct and ct.getKnownTraits then
            local known = ct:getKnownTraits()
            if known and known.contains then
                tiene = known:contains(enum)
            end
        end
    end)
    -- Fallback con HasTrait/hasTrait (ambos en B42, en duda usar el que ande)
    if tiene == nil then pcall(function() tiene = p:HasTrait(traitId) end) end
    if tiene == nil then pcall(function() tiene = p:hasTrait(traitId) end) end
    return tiene
end
local _playerTieneTrait = HoldoorClient.tieneTrait  -- alias local para uso interno abajo

-- ════════════════════════════════════════════════════════════════════════════
-- "Vender niveles" — Libros de Guerra dinamico
-- ════════════════════════════════════════════════════════════════════════════
-- Lee el nivel actual del player en la skill, calcula el XP faltante para el
-- proximo nivel y el precio segun la tabla precioPorNivel.
-- Devuelve:
--   { max=true, nivelActual=N }                                      si esta en nivel 10
--   { max=false, nivelActual, nivelObjetivo, xpFaltante, precio }    si se puede subir
--   nil                                                              si error (perk no resuelve, etc)
-- Resolver robusto del enum Perks. B42 expone los perks de varias formas y la indexacion
-- directa NO funciona uniformemente (gotcha encontrado 2026-06-16: Perks["Maintenance"] OK
-- pero Perks["Sprinting"] devuelve nil aunque /addxp "user" Sprinting=N funciona perfecto).
-- Probamos 4 caminos en cascada.
local function _resolverPerk(perkId)
    if not Perks or not perkId then return nil end
    local p

    -- 1) Acceso directo por indexacion string
    pcall(function() p = Perks[perkId] end)
    if p then return p end

    -- 2) Perks.FromString (algunos perks lo soportan)
    pcall(function() p = Perks.FromString(perkId) end)
    if p then return p end

    -- 3) Iterar pairs(Perks) buscando key igual
    pcall(function()
        for k, v in pairs(Perks) do
            if tostring(k) == perkId then
                p = v
                return
            end
        end
    end)
    if p then return p end

    -- 4) Iterar PerkFactory.PerkList (lista oficial Java) buscando por nombre
    pcall(function()
        if PerkFactory and PerkFactory.PerkList then
            local list = PerkFactory.PerkList
            local size
            pcall(function() size = list:size() end)
            if size then
                for i = 0, size - 1 do
                    local pf = list:get(i)
                    if pf then
                        local id
                        pcall(function() id = tostring(pf:getId()) end)
                        if id == perkId then
                            pcall(function() p = pf:getType() end)
                            if p then return end
                        end
                    end
                end
            end
        end
    end)
    return p
end

function HoldoorClient.calcSubirNivel(perkId, tier)
    local player = getSpecificPlayer(0)
    if not player or not perkId then return nil end

    local perkEnum = _resolverPerk(perkId)
    if not perkEnum then
        print("[Holdoor] calcSubirNivel: NO se pudo resolver perk '" .. tostring(perkId) .. "'")
        return nil
    end

    local nivelActual = 0
    pcall(function() nivelActual = player:getPerkLevel(perkEnum) end)

    if nivelActual >= 10 then
        return { max = true, nivelActual = nivelActual, perkEnum = perkEnum }
    end

    local nivelObjetivo = nivelActual + 1

    -- Calcular XP acumulado para llegar al nivel objetivo.
    -- B42 puede devolver getXpForLevel() como acumulado o por tramo (depende de la version).
    -- Defensivo: sumar todos los tramos 1..nivelObjetivo. Si B42 devuelve acumulado, el resultado
    -- sera mayor que lo real y veremos precios inflados; en ese caso cambiamos a llamada simple.
    local xpObjetivoAcum = 0
    pcall(function()
        local perkDef = PerkFactory.getPerk(perkEnum)
        for lvl = 1, nivelObjetivo do
            local xp = perkDef:getXpForLevel(lvl)
            if xp then xpObjetivoAcum = xpObjetivoAcum + xp end
        end
    end)

    local xpAct = 0
    pcall(function() xpAct = player:getXp():getXP(perkEnum) end)
    -- math.ceil() OBLIGATORIO: B42 devuelve XP como float. Sin redondeo el comando
    -- /addxp recibe decimales y entrega menos XP del esperado (gotcha 2026-06-16:
    -- "Added 1.0 SmallBlunt xp's" cuando faltaban 74.75 → comando ignora decimales).
    local xpFaltante = math.max(1, math.ceil(xpObjetivoAcum - xpAct))

    -- Precio LINEAL con xpFaltante segun tasa por tier
    local precio
    if HoldoorShopCatalog and HoldoorShopCatalog.precioPorXP then
        precio = HoldoorShopCatalog.precioPorXP(tier or "regular", xpFaltante)
    end
    if not precio then precio = { silver = 1 } end

    return {
        max = false,
        nivelActual = nivelActual,
        nivelObjetivo = nivelObjetivo,
        xpFaltante = xpFaltante,
        precio = precio,
        perkEnum = perkEnum,
    }
end

function HoldoorClient.comprar(categoriaId, itemId)
    -- Pre-validacion: encontrar el item en el catalogo y aplicar reglas especificas.
    -- Soporta categorias con items directos (cat.items) y con sub-categorias (cat.subcategorias).
    local itemDef = nil
    if HoldoorShopCatalog and HoldoorShopCatalog.categorias then
        for _, cat in ipairs(HoldoorShopCatalog.categorias) do
            if cat.id == categoriaId then
                -- buscar en items directos
                for _, it in ipairs(cat.items or {}) do
                    if it.id == itemId then itemDef = it; break end
                end
                -- buscar en sub-categorias si no se encontro arriba
                if not itemDef then
                    for _, sub in ipairs(cat.subcategorias or {}) do
                        for _, it in ipairs(sub.items or {}) do
                            if it.id == itemId then itemDef = it; break end
                        end
                        if itemDef then break end
                    end
                end
                break
            end
        end
    end

    if itemDef and itemDef.accion then
        -- Rasgo Heroico: NO comprar si ya tiene ese trait.
        if itemDef.accion.tipo == "trait" then
            local yaLoTiene = _playerTieneTrait(itemDef.accion.trait)
            if yaLoTiene == true then
                HoldoorClient.chat("[HOLDOOR] Ya tenes ese rasgo. No hace falta invocarlo.", 1, 0.6, 0.2)
                return
            end
        end
        -- Milagro: NO comprar si NO tiene el trait negativo (no hay nada que curar).
        if itemDef.accion.tipo == "cura_trait" then
            local loTiene = _playerTieneTrait(itemDef.accion.trait)
            if loTiene == false then
                HoldoorClient.chat("[HOLDOOR] No tenes ese rasgo, no hay nada que curar.", 1, 0.6, 0.2)
                return
            end
        end
        -- Beso del Dios: NO comprar si el player no esta lastimado (no hay nada que curar).
        if itemDef.accion.tipo == "reliquia_godmode_flash" then
            local player = getSpecificPlayer(0)
            local necesitaCura = false
            if player then
                pcall(function()
                    local bd = player:getBodyDamage()
                    if not bd then return end
                    local parts = bd:getBodyParts()
                    if not parts then return end
                    for i = 0, parts:size() - 1 do
                        local bP = parts:get(i)
                        if bP then
                            -- Check HP del body part
                            local hp = 100
                            pcall(function() hp = bP:getHealth() end)
                            if hp < 100 then necesitaCura = true; return end
                            -- Check mordedura
                            local b = false; pcall(function() b = bP:bitten() end)
                            if b then necesitaCura = true; return end
                            -- Check infeccion
                            local inf = false; pcall(function() inf = bP:isInfectedWound() end)
                            if inf then necesitaCura = true; return end
                            -- Check sangrado
                            local bld = false; pcall(function() bld = bP:bleeding() end)
                            if bld then necesitaCura = true; return end
                            -- Check corte
                            local cut = false; pcall(function() cut = bP:isCut() end)
                            if cut then necesitaCura = true; return end
                            -- Check scratch
                            local sc = false; pcall(function() sc = bP:scratched() end)
                            if sc then necesitaCura = true; return end
                        end
                    end
                end)
            end
            if not necesitaCura then
                HoldoorClient.chat("[HOLDOOR] Estas sano. El Beso del Dios no tiene a quien curar.", 1, 0.6, 0.2)
                return
            end
        end
        -- Bendiciones especificas: NO comprar si el player no tiene la condicion concreta.
        local validCura = {
            reliquia_cura_sangrado   = { fn = function(bP) return bP:bleeding() end,                msg = "sangrado" },
            reliquia_cura_fractura   = { fn = function(bP) return bP:getFractureTime() > 0 end,     msg = "fracturas" },
            reliquia_cura_corte      = { fn = function(bP) return bP:isDeepWounded() or bP:isCut() end, msg = "cortes" },
            reliquia_cura_mordedura  = { fn = function(bP) return bP:bitten() end,                  msg = "mordeduras" },
            reliquia_cura_rasgunyo   = { fn = function(bP) return bP:scratched() end,               msg = "rasgunyos" },
        }
        if validCura[itemDef.accion.tipo] then
            local cfg = validCura[itemDef.accion.tipo]
            local player = getSpecificPlayer(0)
            local tiene = false
            if player then
                pcall(function()
                    local bd = player:getBodyDamage()
                    if not bd then return end
                    local parts = bd:getBodyParts()
                    if not parts then return end
                    for i = 0, parts:size() - 1 do
                        local bP = parts:get(i)
                        if bP then
                            local v = false
                            pcall(function() v = cfg.fn(bP) end)
                            if v then tiene = true; return end
                        end
                    end
                end)
            end
            if not tiene then
                HoldoorClient.chat("[HOLDOOR] No tenes " .. cfg.msg .. ". Nada que curar.", 1, 0.6, 0.2)
                return
            end
        end
    end

    -- subir_nivel: calcular precio y XP dinamicamente ANTES de pedir al server cobrar.
    -- Pasamos el precio calculado como override y guardamos xpFaltante para entregar despues.
    local infoNivel = nil
    if itemDef and itemDef.accion and itemDef.accion.tipo == "subir_nivel" then
        infoNivel = HoldoorClient.calcSubirNivel(itemDef.accion.perk, itemDef.accion.tier)
        if not infoNivel then
            HoldoorClient.chat("[HOLDOOR] No se pudo calcular el nivel. Reportar bug.", 1, 0.3, 0.2)
            return
        end
        if infoNivel.max then
            HoldoorClient.chat("[HOLDOOR] Ya tenes esa habilidad al maximo (nivel 10).", 1, 0.6, 0.2)
            return
        end
    end

    local args = { categoria=categoriaId, item=itemId }
    if infoNivel then args.precioOverride = infoNivel.precio end
    if tieneServidorLocal() then
        local p = getSpecificPlayer(0)
        if p then pcall(HoldoorServer._comprar, p, args) end
    else
        sendServerCommand(HoldoorConfig.MODULE, "comprar", args)
    end

    -- v0.6.1 fix MP DEFINITIVO (2026-06-16): comprar via comandos admin vanilla.
    -- /addxp y /additem funcionan en MP B42 porque pasan por el flow autoritario del server
    -- con privilegios admin. Si el comprador es admin → ejecuta directo. Si NO es admin →
    -- delega al host admin via sendClientCommand → server le envia el comando al admin
    -- via sendServerCommand → admin ejecuta el comando con sus privilegios.
    if itemDef and itemDef.accion then
        local accion = itemDef.accion
        local me = getSpecificPlayer(0)
        local targetUser = me and me:getUsername() or nil

        if accion.tipo == "xp" and accion.perk and accion.amount and targetUser then
            local perk, amount = tostring(accion.perk), accion.amount
            if HoldoorClient.esAdmin() then
                local cmd = string.format('/addxp "%s" %s=%d', targetUser, perk, amount)
                pcall(function() SendCommandToServer(cmd) end)
                print("[Holdoor] /addxp local: " .. cmd)
            else
                sendClientCommand(HoldoorConfig.MODULE, "delegarAddXp", {
                    target = targetUser, perk = perk, amount = amount,
                })
                print("[Holdoor] /addxp delegado al host admin")
            end
        end

        -- Reliquias: API Lua directa vanilla (descubierto 2026-06-16 noche tras debug profundo).
        -- NO usamos /godmode admin comando porque su parser B42 esta roto y comportamiento toggle.
        -- En su lugar usamos la misma API que el panel admin "Health Full (Body)" del juego.
        if accion.tipo == "reliquia_godmode_flash" and targetUser then
            -- Beso del Dios: enviar 17 comandos "healthFull" individuales (uno por body part)
            -- al server-side via sendClientCommand("player", "onHealthCheatCurrentPlayer").
            -- Server maneja el comando authoritative y aplica RestoreToFullHealth() sobre
            -- el otherPlayer body part correcto. Cambio persiste, no se revierte.
            --
            -- BUG vanilla: "healthFullBody" en server-side (ClientCommands.lua:557) usa "player"
            -- en vez de "otherPlayer" — capaz tiene inconsistencia. "healthFull" individual SI
            -- usa el bodyPart correcto de otherPlayer (linea 549).
            print("[Holdoor] Reliquia Beso del Dios: INICIO curacion total via server cheat (17 commands)")
            local me = getSpecificPlayer(0)
            if not me then
                print("[Holdoor] Reliquia Beso del Dios: ERROR - getSpecificPlayer(0) devolvio nil")
            else
                local onlineID
                pcall(function() onlineID = me:getOnlineID() end)
                local bd = me:getBodyDamage()
                if not bd then
                    print("[Holdoor] Reliquia Beso del Dios: ERROR - getBodyDamage() nil")
                else
                    local parts = bd:getBodyParts()
                    if not parts then
                        print("[Holdoor] Reliquia Beso del Dios: ERROR - getBodyParts() nil")
                    else
                        local size = parts:size()
                        for i = 0, size - 1 do
                            local args = {
                                bodyPartIndex = i,
                                action = "healthFull",   -- individual, server-side authoritative
                                id = onlineID,
                            }
                            if isClient() then
                                pcall(function() sendClientCommand(me, "player", "onHealthCheatCurrentPlayer", args) end)
                            else
                                -- SP: aplicar directamente
                                local bP = parts:get(i)
                                if bP then pcall(function() bP:RestoreToFullHealth() end) end
                            end
                        end
                        print("[Holdoor] Reliquia Beso del Dios: " .. size .. " comandos enviados (action=healthFull)")
                    end
                end
            end
        end

        -- Bendiciones (curas parciales repetibles - solo cura body parts con la condicion)
        if accion.tipo == "reliquia_cura_sangrado" then
            HoldoorClient._curaParcial(targetUser, function(bP) return bP:bleeding() end, "sangrado")
        elseif accion.tipo == "reliquia_cura_fractura" then
            HoldoorClient._curaParcial(targetUser, function(bP) return bP:getFractureTime() > 0 end, "fractura")
        elseif accion.tipo == "reliquia_cura_corte" then
            HoldoorClient._curaParcial(targetUser, function(bP)
                return bP:isDeepWounded() or bP:isCut()
            end, "corte profundo")
        elseif accion.tipo == "reliquia_cura_mordedura" then
            HoldoorClient._curaParcial(targetUser, function(bP) return bP:bitten() end, "mordedura")
        elseif accion.tipo == "reliquia_cura_rasgunyo" then
            HoldoorClient._curaParcial(targetUser, function(bP) return bP:scratched() end, "rasgunyo")
        end

        -- Hechizos (buffs temporales con setX) eliminados 2026-06-16 noche:
        -- las APIs setZombiesDontAttack/setUnlimitedX/setFastMoveCheat no se aplican
        -- desde codigo mod aunque uses sendPlayerExtraInfo. Solo el panel admin vanilla
        -- los hace efectivos. Investigar Java-side en sprint futuro.
        -- reliquia_teleport_trono se maneja en onComandoServidor "reliquiaTeleport"
        -- porque las coords del Trono las pasa el server (no las tiene el cliente).

        -- subir_nivel: usamos infoNivel.xpFaltante calculado al inicio.
        -- Misma logica que "xp" pero con xp dinamico para completar 1 nivel exacto.
        if accion.tipo == "subir_nivel" and infoNivel and not infoNivel.max and targetUser then
            local perk   = tostring(accion.perk)
            local amount = infoNivel.xpFaltante
            if HoldoorClient.esAdmin() then
                local cmd = string.format('/addxp "%s" %s=%d', targetUser, perk, amount)
                pcall(function() SendCommandToServer(cmd) end)
                print("[Holdoor] /addxp local (nivel " .. infoNivel.nivelActual .. "->" .. infoNivel.nivelObjetivo .. "): " .. cmd)
            else
                sendClientCommand(HoldoorConfig.MODULE, "delegarAddXp", {
                    target = targetUser, perk = perk, amount = amount,
                })
                print("[Holdoor] /addxp delegado al host admin (subir_nivel)")
            end
        end

        if (accion.tipo == "item" or accion.tipo == "package") and targetUser then
            local items = {}
            if accion.tipo == "item" and accion.item then
                table.insert(items, accion.item)
            elseif accion.tipo == "package" and accion.items then
                for _, n in ipairs(accion.items) do table.insert(items, n) end
            end
            if HoldoorClient.esAdmin() then
                for _, itemName in ipairs(items) do
                    local cmd = string.format('/additem "%s" "%s" 1', targetUser, tostring(itemName))
                    pcall(function() SendCommandToServer(cmd) end)
                    print("[Holdoor] /additem local: " .. cmd)
                end
            else
                sendClientCommand(HoldoorConfig.MODULE, "delegarAddItem", {
                    target = targetUser, items = items,
                })
                print("[Holdoor] /additem delegado al host admin (" .. #items .. " items)")
            end
        end
    end

    -- v0.6.2: refresh post-compra.
    -- Pasamos infoNivel para que la funcion decida si usar polling con verificacion
    -- (subir_nivel) o clicks delayed simples (items/packages).
    if HoldoorClient.refreshShopDeferido then
        HoldoorClient.refreshShopDeferido(infoNivel)
    end
end

function HoldoorClient.transferir(toUser, tipo, cantidad)
    local args = { to=toUser, tipo=tipo, cantidad=cantidad }
    if tieneServidorLocal() then
        local p = getSpecificPlayer(0)
        if p then
            pcall(HoldoorServer._transferirMonedas, p, args)
        end
    else
        sendServerCommand(HoldoorConfig.MODULE, "transferir", args)
    end
end

function HoldoorClient.pedirEstado()
    if tieneServidorLocal() then
        local est = HoldoorServer.estado
        local ahora = os.time()
        HoldoorClient.estado.activo           = est.activo
        HoldoorClient.estado.fase             = est.fase
        HoldoorClient.estado.oleadaActual     = est.oleadaActual
        HoldoorClient.estado.zombiesRestantes = est.zombiesRestantes
        HoldoorClient.estado.zombiesTotal     = est.zombiesTotal
        HoldoorClient.estado.baseX            = est.baseX
        HoldoorClient.estado.baseY            = est.baseY
        HoldoorClient.estado.baseZ            = est.baseZ
        HoldoorClient.estado.baseDefinida     = est.baseDefinida
        HoldoorClient.estado.config           = est.config or {}
        -- Reconstruir countdown local
        if est.fase == "preparacion" then
            HoldoorClient.estado.countdownFinLocal = ahora + math.max(0, est.countdownFinSec - ahora)
            HoldoorClient.ultimoSegsHUD = -1
        elseif est.fase == "pausa" then
            HoldoorClient.estado.countdownFinLocal = ahora + math.max(0, est.pausaFinSec - ahora)
            HoldoorClient.ultimoSegsHUD = -1
        end
    else
        sendServerCommand(HoldoorConfig.MODULE, "pedirEstado", {})
    end
end

function HoldoorClient.chat(texto, r, g, b)
    local player = getSpecificPlayer(0)
    if player then
        player:Say(texto)
    end
    -- Toast arriba de la pantalla (visible incluso con la tienda abierta).
    -- NO mostrar separadores decorativos (lineas de "====" o "----") en el toast.
    if HoldoorToast and HoldoorToast.mostrar and texto then
        local soloDecorativo = texto:gsub("[=%-_%s]", "") == ""
        if not soloDecorativo then
            pcall(HoldoorToast.mostrar, texto, r, g, b)
        end
    end
end

-- ─────────────────────────────────────────────
--  ABRIR PANEL CON F10
-- ─────────────────────────────────────────────

-- F10 funciona EXCLUSIVAMENTE en single player.
-- En MULTIPLAYER (tanto host como cliente) F10 es no-op.
-- El unico acceso al panel en MP es el comando /holdoor en el chat, admin-only.
function HoldoorClient.onKeyPressed(key)
    if key ~= Keyboard.KEY_F10 then return end
    -- F10 funciona en SP siempre, y en MP solo si el player es admin (host o staff).
    -- esAdmin() reconoce: SP / host hosted (isServer=true) / accessLevel staff.
    -- Cliente MP random → toast naranja "Solo el host puede".
    if HoldoorClient.esAdmin() then
        HoldoorUI.abrir()
    else
        HoldoorClient.chat("[HOLDOOR] Solo el host del servidor puede abrir el panel.", 1, 0.4, 0.2)
    end
end

-- ─────────────────────────────────────────────
--  COMANDO DE CHAT /holdoor
--  Intercepta el input del chat antes de mandarlo al server.
--  En PZ los comandos con / son admin-only por diseño, asi que
--  esto solo funciona para quien hosteo (que es admin auto en Hosted mode).
-- ─────────────────────────────────────────────

function HoldoorClient.instalarComandoChat()
    if HoldoorClient._comandoInstalado then return end
    -- IMPORTANTE: ISChat copia la referencia del metodo al textEntry al crearse
    -- (ISChat.lua:170: self.textEntry.onCommandEntered = ISChat.onCommandEntered).
    -- Por eso hookear ISChat.onCommandEntered NO funciona (la instancia ya tiene
    -- la referencia al original). Hay que hookear ISChat.instance.textEntry directamente.
    if not ISChat or not ISChat.instance or not ISChat.instance.textEntry then
        return  -- chat no creado todavia, reintentamos en proximo tick
    end

    local textEntry = ISChat.instance.textEntry
    local _origOnCommand = textEntry.onCommandEntered
    if not _origOnCommand then return end

    textEntry.onCommandEntered = function(selfTE)
        -- selfTE es el textEntry, no ISChat. El texto puede leerse de selfTE o de
        -- ISChat.instance.textEntry (que es el mismo objeto).
        local text = nil
        pcall(function() text = selfTE:getText() end)
        if not text then pcall(function() text = selfTE:getInternalText() end) end
        if text then
            local lower = string.lower(text):gsub("^%s+", ""):gsub("%s+$", "")
            if lower == "/holdoor" or lower:sub(1, 9) == "/holdoor " then
                pcall(function() selfTE:setText("") end)
                pcall(function() ISChat.instance:unfocus() end)
                if HoldoorClient.esAdmin() then
                    HoldoorUI.abrir()
                else
                    HoldoorClient.chat("[HOLDOOR] Solo el host del servidor puede usar /holdoor.", 1, 0.4, 0.2)
                end
                return  -- corto el flujo original
            end
        end
        _origOnCommand(selfTE)
    end

    HoldoorClient._comandoInstalado = true
    print("[Holdoor] Comando /holdoor instalado (hook textEntry.onCommandEntered)")
end

-- Reintento periodico: en MP, ISChat puede cargar despues de OnGameStart.
-- Tickear cada ~1s hasta que se instale, despues bajar el listener.
local _instalarChatTickCount = 0
function HoldoorClient._tickInstalarChat()
    if HoldoorClient._comandoInstalado then
        Events.OnTick.Remove(HoldoorClient._tickInstalarChat)
        return
    end
    _instalarChatTickCount = _instalarChatTickCount + 1
    if _instalarChatTickCount < 60 then return end  -- ~1s a 60fps
    _instalarChatTickCount = 0
    HoldoorClient.instalarComandoChat()
end

function HoldoorClient.init()
    HoldoorClient.estado.config = {}
    for k, v in pairs(HoldoorConfig.defaults) do
        HoldoorClient.estado.config[k] = v
    end
    HoldoorClient.pedirEstado()

    -- La base NO persiste entre sesiones — limpiar ModData global del mod por las dudas.
    -- El server (HoldoorServer.resetearBaseAlInicio) ya destruye el Trono fisico al cargar.
    pcall(function()
        local md = ModData.getOrCreate("Holdoor")
        if md then md.baseX, md.baseY, md.baseZ, md.baseDefinida = nil, nil, nil, false end
    end)

    print("[Holdoor] Cliente inicializado v" .. HoldoorConfig.VERSION .. " -- usa /holdoor en el chat para abrir el panel")
    if tieneServidorLocal() then
        print("[Holdoor] Modo: SINGLE PLAYER (acceso directo al servidor)")
    else
        print("[Holdoor] Modo: MULTIPLAYER (comandos via red)")
    end

    -- Instalar el comando /holdoor (override de ISChat).
    -- En MP, ISChat puede no estar disponible aun en OnGameStart, asi que
    -- activamos un tick listener que reintenta cada ~1s hasta que se instale.
    HoldoorClient.instalarComandoChat()
    if not HoldoorClient._comandoInstalado then
        Events.OnTick.Add(HoldoorClient._tickInstalarChat)
        print("[Holdoor] Chat command: ISChat aun no disponible, reintento agendado.")
    end
end

-- ─────────────────────────────────────────────
--  KILL TRACKING LOCAL
--  Cuenta zombies muertos cerca de la base por este cliente.
--  En SP: exacto. En MP: cuenta muertes en el area cargada del jugador.
-- ─────────────────────────────────────────────

function HoldoorClient.onZombieMuertoLocal(zombie)
    local est = HoldoorClient.estado
    if est.fase ~= "activa" or not est.baseDefinida then return end

    -- v0.6 fix: ignorar por TIEMPO (ventana 2s post-limpieza), no por contador.
    if os.time() < (est._killsIgnorarHasta or 0) then return end

    local ok, zx, zy = pcall(function() return zombie:getX(), zombie:getY() end)
    if ok and zx then
        local dx = zx - est.baseX
        local dy = zy - est.baseY
        local radio = (est.config.radioSpawn or 20) + 40
        if (dx * dx + dy * dy) > (radio * radio) then return end
    end

    est.killsOleada  = (est.killsOleada or 0) + 1
    est.killsPartida = (est.killsPartida or 0) + 1

    if HoldoorHUD and HoldoorHUD.instance and HoldoorHUD.instance.expandido then
        HoldoorHUD.instance:actualizarHUD()
    end
end

Events.OnServerCommand.Add(HoldoorClient.onComandoServidor)
Events.OnGameStart.Add(HoldoorClient.init)
Events.OnKeyStartPressed.Add(HoldoorClient.onKeyPressed)
Events.OnTick.Add(HoldoorClient.onTick)
Events.OnZombieDead.Add(HoldoorClient.onZombieMuertoLocal)

-- ════════════════════════════════════════════════════════════════════
-- v0.6.2: REFRESH DIFERIDO DE LA TIENDA POST-COMPRA DE NIVELES
--
-- Bug encontrado 2026-06-16: tras comprar "subir_nivel" via /addxp (async),
-- el HoldoorShop.refrescar() llamado inmediatamente todavia veia el nivel
-- VIEJO porque el comando server no proceso el levelup todavia.
--
-- Fix doble:
-- 1) Hook Events.LevelPerk (idiomatico — dispara cuando level real cambia)
-- 2) Contador OnTick que refresca la tienda durante ~0.5s post-compra
--    (fallback por si LevelPerk no existe en B42 o el timing falla)
-- ════════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════════
-- v0.6.2: TIMERS DE RELIQUIAS (godmode y invisible se apagan tras N ticks)
-- ════════════════════════════════════════════════════════════════════
-- Helper: cura solo body parts que cumplen la condicion (Bendiciones).
-- Itera body parts, envia sendClientCommand al server (action="healthFull") solo para los que tienen
-- la condicion. Server aplica RestoreToFullHealth() authoritative.
function HoldoorClient._curaParcial(targetUser, condicionFn, nombreLog)
    local me = getSpecificPlayer(0)
    if not me then
        print("[Holdoor] Cura parcial (" .. (nombreLog or "?") .. "): ERROR - no player")
        return 0
    end
    local onlineID
    pcall(function() onlineID = me:getOnlineID() end)
    local bd = me:getBodyDamage()
    if not bd then return 0 end
    local parts = bd:getBodyParts()
    if not parts then return 0 end
    local size = parts:size()
    local count = 0
    for i = 0, size - 1 do
        local bP = parts:get(i)
        if bP then
            local tiene = false
            pcall(function() tiene = condicionFn(bP) end)
            if tiene then
                count = count + 1
                if isClient() then
                    pcall(function()
                        sendClientCommand(me, "player", "onHealthCheatCurrentPlayer", {
                            bodyPartIndex = i, action = "healthFull", id = onlineID,
                        })
                    end)
                else
                    pcall(function() bP:RestoreToFullHealth() end)
                end
            end
        end
    end
    print("[Holdoor] Cura parcial (" .. (nombreLog or "?") .. "): " .. count .. " body parts afectados")
    return count
end

-- Timers de Reliquias temporales removidos 2026-06-16:
-- los Hechizos con setX no funcionaban, y el Beso del Dios cura instantaneamente
-- (no requiere timer). Las Bendiciones son one-shot tambien.

-- Refresh post-compra: 2 sistemas distintos segun tipo de accion.
--
-- 1) SUBIR_NIVEL → polling con verificacion empirica.
--    Antes de comprar guardamos nivelPre. Cada tick durante hasta 1s verificamos
--    player:getPerkLevel(). Cuando dispara > nivelPre, server confirmo el cambio →
--    simulamos click + paramos polling. 100% deterministico, dispara EXACTO en el
--    frame que el server procesa el levelup. Sin adivinar timings.
--
-- 2) ITEMS / PACKAGES / OTROS → 2 clicks delayed simples (suficientes porque no
--    necesitamos verificar nivel, solo que la UI muestre stocks/saldos actualizados).
HoldoorClient._levelupPolling = nil   -- { perkEnum, nivelPre, ticksRestantes }
HoldoorClient._refreshSubcatAt = { -1, -1 }

function HoldoorClient.refreshShopDeferido(infoNivel)
    -- Si es compra de subir_nivel y tenemos infoNivel valido → polling con verificacion
    if infoNivel and not infoNivel.max and infoNivel.perkEnum then
        local player = getSpecificPlayer(0)
        if player then
            local nivelPre = 0
            pcall(function() nivelPre = player:getPerkLevel(infoNivel.perkEnum) end)
            HoldoorClient._levelupPolling = {
                perkEnum = infoNivel.perkEnum,
                nivelPre = nivelPre,
                ticksRestantes = 60,   -- max 1s a 60 FPS
            }
            return
        end
    end
    -- Para items/packages: 2 clicks delayed simples (no necesitamos verificar nivel)
    HoldoorClient._refreshSubcatAt = { 15, 30 }
end

local function _tickRefreshSubcat()
    -- Polling activo para subir_nivel (verifica si el nivel realmente cambio)
    local pol = HoldoorClient._levelupPolling
    if pol then
        pol.ticksRestantes = pol.ticksRestantes - 1
        local player = getSpecificPlayer(0)
        local nivelActual = pol.nivelPre   -- default si no podemos leer
        if player then
            pcall(function() nivelActual = player:getPerkLevel(pol.perkEnum) end)
        end
        if nivelActual > pol.nivelPre or pol.ticksRestantes <= 0 then
            -- Server confirmo el cambio O timeout 1s → dispara refresh + cierra polling
            if HoldoorShop and HoldoorShop.simularClickSubcategoriaActual then
                pcall(HoldoorShop.simularClickSubcategoriaActual)
            end
            HoldoorClient._levelupPolling = nil
        end
    end

    -- Slots delayed para items/packages
    local arr = HoldoorClient._refreshSubcatAt
    if arr then
        for i = 1, #arr do
            if arr[i] > 0 then
                arr[i] = arr[i] - 1
                if arr[i] == 0 then
                    if HoldoorShop and HoldoorShop.simularClickSubcategoriaActual then
                        pcall(HoldoorShop.simularClickSubcategoriaActual)
                    end
                end
            end
        end
    end
end
Events.OnTick.Add(_tickRefreshSubcat)

-- ════════════════════════════════════════════════════════════════════
-- OVERLAY VISUAL DEL TRONO DE HIERRO (C0)
-- Dibuja la PNG real del Trono como imagen flotante encima del tile de la forja.
-- La forja real (crafted_01_16) sigue debajo con HP, atacable, etc. — esto es PURAMENTE visual.
-- 
-- Setup: poner la PNG en media/textures/Holdoor_TronoHierro.png
-- ════════════════════════════════════════════════════════════════════

HoldoorOverlayTrono = HoldoorOverlayTrono or {}
HoldoorOverlayTrono.textura = nil
HoldoorOverlayTrono._intentado = false

function HoldoorOverlayTrono.cargar()
    if HoldoorOverlayTrono._intentado then return end
    HoldoorOverlayTrono._intentado = true
    -- Probar varios paths posibles (depende de como PZ resuelve el nombre)
    local candidatos = {
        "media/textures/Holdoor_TronoHierro.png",
        "media/textures/Holdoor_TronoHierro",
        "Holdoor_TronoHierro",
        "Holdoor_TronoHierro.png",
    }
    for _, name in ipairs(candidatos) do
        local tex
        pcall(function() tex = getTexture(name) end)
        if tex then
            HoldoorOverlayTrono.textura = tex
            print("[Holdoor] Overlay Trono: textura cargada como '" .. name .. "'")
            return
        end
    end
    print("[Holdoor] Overlay Trono: textura NO encontrada. Pone la PNG en Documents/Holdoor_PZ/media/textures/Holdoor_TronoHierro.png")
end

-- En B42, getRenderer():render(...) con 9 args NO existe.
-- Usamos un ISUIElement fullscreen que dibuja con drawTextureScaledColor (API que sí anda).
HoldoorOverlayUI = ISUIElement:derive("HoldoorOverlayUI")

function HoldoorOverlayUI:new()
    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    local o = ISUIElement.new(self, 0, 0, sw, sh)
    o.background = false
    return o
end

-- Flag para desactivar el overlay si ninguna API de render funciona en B42.
-- Evita spammear errores cada frame.
HoldoorOverlayTrono._renderDeshabilitado = false

function HoldoorOverlayUI:render()
    if HoldoorOverlayTrono._renderDeshabilitado then return end
    if not HoldoorOverlayTrono.textura then
        pcall(function() self:setVisible(false) end); return
    end
    if not HoldoorServer or not HoldoorServer.estado then
        pcall(function() self:setVisible(false) end); return
    end
    local trono = HoldoorServer.estado.trono
    if not trono or not trono.piezaCentral then
        pcall(function() self:setVisible(false) end); return
    end

    local hp = 0
    pcall(function() hp = trono.piezaCentral.obj:getHealth() end)
    if hp <= 0 then
        pcall(function() self:setVisible(false) end); return
    end

    local forja = trono.piezaCentral
    local fx, fy, fz = forja.x, forja.y, forja.z

    local sx, sy
    pcall(function() sx = IsoUtils.XToScreenExact(fx, fy, fz, 0) end)
    pcall(function() sy = IsoUtils.YToScreenExact(fx, fy, fz, 0) end)
    if not sx or not sy then
        pcall(function() sx = IsoUtils.XToScreen(fx, fy, fz, 0) end)
        pcall(function() sy = IsoUtils.YToScreen(fx, fy, fz, 0) end)
    end
    if not sx or not sy then return end

    local zoom = 1.0
    pcall(function() zoom = getCore():getZoom(0) end)
    local zdiv = (zoom > 0) and zoom or 1.0

    -- Tamaño base del Trono en pixels a zoom 1.0.
    -- W=180, H=270.  offset 0.72 → bajado un poquito para tapar la base de la forja.
    local W = 180 / zdiv
    local H = 270 / zdiv
    local drawX = (sx / zdiv) - W / 2
    local drawY = (sy / zdiv) - H * 0.72

    -- Z-order workaround: si HAY player o zombi cerca del Trono, bajamos alpha.
    -- Imita el comportamiento nativo de PZ con muebles altos.
    -- Cache de 100ms para no iterar zombis cada frame (60fps = caro).
    local ms = 0
    pcall(function() ms = getTimestampMs() end)
    if ms == 0 then ms = os.time() * 1000 end

    if ms - (HoldoorOverlayTrono._cacheAlphaMs or 0) > 100 then
        HoldoorOverlayTrono._cacheAlphaMs = ms
        local distMin = 999

        -- Player local
        local p
        pcall(function() p = getSpecificPlayer(0) end)
        if p then
            local px, py
            pcall(function() px = p:getX(); py = p:getY() end)
            if px and py then
                local d = math.sqrt((px-fx)*(px-fx) + (py-fy)*(py-fy))
                if d < distMin then distMin = d end
            end
        end

        -- Zombis cercanos al Trono (iteramos la lista del cell, no los tiles)
        pcall(function()
            local cell = getCell()
            if not cell then return end
            local zombies = cell:getZombieList()
            if not zombies then return end
            local sz = zombies:size()
            for i = 0, sz - 1 do
                local z = zombies:get(i)
                if z then
                    local zx, zy = z:getX(), z:getY()
                    if zx and zy then
                        local zdx = zx - fx
                        local zdy = zy - fy
                        local d2 = zdx*zdx + zdy*zdy
                        if d2 <= 16 then  -- pre-filtro radio 4 tiles
                            local d = math.sqrt(d2)
                            if d < distMin then distMin = d end
                        end
                    end
                end
            end
        end)

        if distMin <= 4 then
            HoldoorOverlayTrono._cacheAlpha = math.max(0.3, distMin / 4)
        else
            HoldoorOverlayTrono._cacheAlpha = 1.0
        end
    end
    local alpha = HoldoorOverlayTrono._cacheAlpha or 1.0

    -- v0.6.1: CRITICAL — reposicionar el RECT del panel cada frame para que coincida
    -- EXACTAMENTE con el area del trono en pantalla (180x270 px aprox).
    -- Sin esto el rect 1920x1080 fullscreen bloquea scroll/hover del inventario incluso
    -- con setWantMouseEvents(false). En B42 el hit-test del mouse usa el RECT del panel
    -- ignorando setWantMouseEvents si setVisible(true).
    local rx = math.floor(drawX)
    local ry = math.floor(drawY)
    local rw = math.max(1, math.floor(W))
    local rh = math.max(1, math.floor(H))

    -- v0.6.1: si el trono esta fuera del viewport, achicar rect a 1x1 en (0,0) y no
    -- dibujar. Sin esto, PZ clampea las coordenadas al borde y el sprite queda "pegado"
    -- a la esquina (bug visual del 2026-06-15: trono aparecia flotando arriba-derecha
    -- cuando el player se alejaba).
    local sw_view = getCore():getScreenWidth()
    local sh_view = getCore():getScreenHeight()
    local fueraViewport = (rx + rw < 0) or (ry + rh < 0) or (rx > sw_view) or (ry > sh_view)
    if fueraViewport then
        pcall(function() self:setX(0) end)
        pcall(function() self:setY(0) end)
        pcall(function() self:setWidth(1) end)
        pcall(function() self:setHeight(1) end)
        return
    end

    pcall(function() self:setX(rx) end)
    pcall(function() self:setY(ry) end)
    pcall(function() self:setWidth(rw) end)
    pcall(function() self:setHeight(rh) end)

    -- En B42, varios métodos de render pueden NO estar implementados.
    -- Si todos fallan, deshabilitamos el overlay para no spammear errores cada frame.
    -- Coordenadas RELATIVAS al panel ahora (0,0) porque el panel ya esta posicionado en drawX,drawY.
    local ok = false
    pcall(function()
        self:drawTextureScaled(HoldoorOverlayTrono.textura, 0, 0, rw, rh, alpha)
        ok = true
    end)
    if not ok then
        pcall(function()
            self:drawTexture(HoldoorOverlayTrono.textura, 0, 0, 1.0, 1.0, 1.0, alpha)
            ok = true
        end)
    end
    if not ok then
        HoldoorOverlayTrono._renderDeshabilitado = true
        print("[Holdoor] Overlay Trono: ninguna API de render funciona en B42. Overlay deshabilitado.")
    end
end

-- Overlay fullscreen invisible — NO debe capturar NINGÚN evento de mouse.
-- Si falta cualquiera de estos overrides, el click derecho del mundo deja de funcionar
-- porque ISUIElement los devuelve true por defecto (consume el evento).
function HoldoorOverlayUI:onMouseDown(x, y)        return false end
function HoldoorOverlayUI:onMouseUp(x, y)          return false end
function HoldoorOverlayUI:onMouseMove(dx, dy)      return false end
function HoldoorOverlayUI:onMouseMoveOutside(dx,dy) return false end
function HoldoorOverlayUI:onMouseDownOutside(x,y)  return false end
function HoldoorOverlayUI:onMouseUpOutside(x,y)    return false end
function HoldoorOverlayUI:onRightMouseDown(x, y)   return false end
function HoldoorOverlayUI:onRightMouseUp(x, y)     return false end
function HoldoorOverlayUI:onMouseWheel(del)        return false end
function HoldoorOverlayUI:isMouseOver()            return false end

HoldoorOverlayTrono._uiInstance = nil

function HoldoorOverlayTrono.crearUI()
    if HoldoorOverlayTrono._uiInstance then return end
    local ui = HoldoorOverlayUI:new()
    ui:initialise()
    -- v0.6.1: setWantMouseEvents(false) SOLO no alcanza en B42. Necesita ADEMAS setVisible(false)
    -- para que el dispatcher de mouse ignore el rect fullscreen. Activamos visibility via tick.
    pcall(function() ui:setWantMouseEvents(false) end)
    ui:addToUIManager()
    ui:setVisible(false)
    HoldoorOverlayTrono._uiInstance = ui
    print("[Holdoor] Overlay Trono: UI element creado (oculto hasta que haya trono visible)")
end

-- v0.6.1: tick que activa/desactiva visibility segun haya un trono renderizable.
-- Sin esto el overlay full-screen bloquea scroll/hover del inventario.
HoldoorOverlayTrono._tickCounter = 0
function HoldoorOverlayTrono._tickVisibilidad()
    HoldoorOverlayTrono._tickCounter = (HoldoorOverlayTrono._tickCounter or 0) + 1
    -- Chequear cada 30 ticks (~0.5s a 60fps) — no necesita ser tiempo real
    if HoldoorOverlayTrono._tickCounter < 30 then return end
    HoldoorOverlayTrono._tickCounter = 0

    local ui = HoldoorOverlayTrono._uiInstance
    if not ui then return end

    -- Verificar si hay un trono renderizable (mismas condiciones que render())
    local hayTrono = false
    if HoldoorOverlayTrono.textura and HoldoorServer and HoldoorServer.estado then
        local trono = HoldoorServer.estado.trono
        if trono and trono.piezaCentral and trono.piezaCentral.obj then
            local hp = 0
            pcall(function() hp = trono.piezaCentral.obj:getHealth() end)
            if hp > 0 then hayTrono = true end
        end
    end

    local visibleAhora = false
    pcall(function() visibleAhora = ui:isVisible() end)
    if hayTrono and not visibleAhora then
        pcall(function() ui:setVisible(true) end)
    elseif not hayTrono and visibleAhora then
        pcall(function() ui:setVisible(false) end)
    end
end

Events.OnGameStart.Add(HoldoorOverlayTrono.cargar)
Events.OnGameStart.Add(HoldoorOverlayTrono.crearUI)
Events.OnTick.Add(HoldoorOverlayTrono._tickVisibilidad)
