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
    -- En SP o cuando hostea, isClient() es false → siempre admin
    local ok, client = pcall(isClient)
    if not ok or not client then return true end

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
        HoldoorClient.estado.fase             = "activa"
        HoldoorClient.estado.zombiesTotal     = args.zombies or 0
        HoldoorClient.estado.zombiesRestantes = args.zombies or 0
        HoldoorClient.estado.srTotal          = args.speedrunners or 0
        HoldoorClient.estado.killsOleada      = 0  -- resetear contador personal de oleada
        -- Auto-expandir HUD al inicio de oleada
        if HoldoorHUD and HoldoorHUD.instance and not HoldoorHUD.instance.expandido then
            HoldoorHUD.instance:_setExpandido(true)
        end
        if HoldoorUI then HoldoorUI.actualizarTodo() end

    elseif comando == "zombiesMuertos" then
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

        -- Si cayo un drop raro: avisar destacado en chat
        if args.lucky then
            if (args.gold or 0) > 0 then
                HoldoorClient.chat("[HOLDOOR] *** JACKPOT! Cayo " .. args.gold .. " Oro ***", 1.0, 0.85, 0.15)
            elseif (args.silver or 0) > 0 then
                HoldoorClient.chat("[HOLDOOR] !!! SUERTE! Drop extra de " .. args.silver .. " Plata", 0.75, 0.85, 1.0)
            end
        end

        playUISound("LevelPerk")

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
            HoldoorAnnounce.mostrar(
                "EL TRONO HA CAIDO",
                "Sobreviviste " .. (args.oleadas or 0) .. " oleadas antes de la derrota.",
                1.0, 0.10, 0.10, 480
            )
        end

    elseif comando == "monedasActualizadas" then
        -- Refresca el HUD para que muestre el saldo nuevo
        if HoldoorUI then HoldoorUI.actualizarTodo() end

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

    elseif comando == "zonaLimpiada" then
        local n = args.cantidad or 0
        if n > 0 then
            HoldoorClient.chat("[HOLDOOR] Zona despejada: " .. n .. " caminantes eliminados.", 0.4, 0.8, 1)
        end

    elseif comando == "aviso" then
        HoldoorClient.chat("[HOLDOOR] " .. (args.mensaje or ""), 1, 0.8, 0.2)

    elseif comando == "mensaje" then
        HoldoorClient.chat("[HOLDOOR] " .. (args.texto or ""), 1, 0.6, 0.2)

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
    if sr > 0 then
        HoldoorClient.chat("OLEADA " .. args.numero .. " -- " .. (args.cantidad or 0) .. " + " .. sr .. " corredores en camino", 1, 0.3, 0.1)
    else
        HoldoorClient.chat("OLEADA " .. args.numero .. " -- " .. total .. " en camino", 1, 0.3, 0.1)
    end
    if args.frase then HoldoorClient.chat(args.frase, 0.9, 0.8, 0.5) end
    if args.autor then HoldoorClient.chat("    " .. args.autor, 0.5, 0.5, 0.4) end
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
        -- SP: reset de estado directamente en ambos lados
        HoldoorServer.estado.activo           = false
        HoldoorServer.estado.fase             = "inactivo"
        HoldoorServer.estado.zombiesRestantes = 0
        HoldoorServer.estado.zombiesTotal     = 0
        HoldoorClient.estado.activo           = false
        HoldoorClient.estado.fase             = "inactivo"
        HoldoorClient.estado.zombiesRestantes = 0
        HoldoorClient.estado.zombiesTotal     = 0
        HoldoorClient.chat("[HOLDOOR] Sistema de oleadas detenido.", 0.7, 0.7, 0.7)
        if HoldoorUI then HoldoorUI.actualizarTodo() end
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

    -- Persist across sessions
    local ok, md = pcall(ModData.getOrCreate, "Holdoor")
    if ok and md then
        md.baseX = x
        md.baseY = y
        md.baseZ = z
        md.baseDefinida = true
    end

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

function HoldoorClient.comprar(categoriaId, itemId)
    local args = { categoria=categoriaId, item=itemId }
    if tieneServidorLocal() then
        local p = getSpecificPlayer(0)
        if p then pcall(HoldoorServer._comprar, p, args) end
    else
        sendServerCommand(HoldoorConfig.MODULE, "comprar", args)
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
end

-- ─────────────────────────────────────────────
--  ABRIR PANEL CON F10
-- ─────────────────────────────────────────────

-- F10 funciona EXCLUSIVAMENTE en single player.
-- En MULTIPLAYER (tanto host como cliente) F10 es no-op.
-- El unico acceso al panel en MP es el comando /holdoor en el chat, admin-only.
function HoldoorClient.onKeyPressed(key)
    if key ~= Keyboard.KEY_F10 then return end

    -- Detectar contexto MP: isClient()=true (cliente conectado) O isServer()=true (host).
    -- En SP puro (offline) ambas devuelven false.
    local esCliente, esServer = false, false
    pcall(function() esCliente = isClient() end)
    pcall(function() esServer  = isServer() end)
    if esCliente or esServer then return end   -- cualquier MP: F10 no hace nada

    -- SP puro: abrir directo
    HoldoorUI.abrir()
end

-- ─────────────────────────────────────────────
--  COMANDO DE CHAT /holdoor
--  Intercepta el input del chat antes de mandarlo al server.
--  En PZ los comandos con / son admin-only por diseño, asi que
--  esto solo funciona para quien hosteo (que es admin auto en Hosted mode).
-- ─────────────────────────────────────────────

function HoldoorClient.instalarComandoChat()
    if HoldoorClient._comandoInstalado then return end
    if not ISChat or not ISChat.sendCurrentInputText then return end

    local _origSend = ISChat.sendCurrentInputText
    function ISChat:sendCurrentInputText()
        local text = nil
        local ok = pcall(function()
            text = self.textEntry and self.textEntry:getInternalText()
        end)
        if ok and text then
            local lower = string.lower(text):gsub("^%s+", ""):gsub("%s+$", "")
            if lower == "/holdoor" or lower:sub(1, 9) == "/holdoor " then
                pcall(function() self.textEntry:setText("") end)
                if HoldoorClient.esAdmin() then
                    HoldoorUI.abrir()
                else
                    HoldoorClient.chat("[HOLDOOR] Solo el host del servidor puede usar /holdoor.", 1, 0.4, 0.2)
                end
                return
            end
        end
        _origSend(self)
    end

    HoldoorClient._comandoInstalado = true
    print("[Holdoor] Comando de chat /holdoor instalado")
end

function HoldoorClient.init()
    HoldoorClient.estado.config = {}
    for k, v in pairs(HoldoorConfig.defaults) do
        HoldoorClient.estado.config[k] = v
    end
    HoldoorClient.pedirEstado()

    -- Restore base from ModData if server reset it (e.g. after reload)
    if not HoldoorClient.estado.baseDefinida then
        local ok, md = pcall(ModData.getOrCreate, "Holdoor")
        if ok and md and md.baseX then
            HoldoorClient.estado.baseX        = md.baseX
            HoldoorClient.estado.baseY        = md.baseY
            HoldoorClient.estado.baseZ        = md.baseZ or 0
            HoldoorClient.estado.baseDefinida = true
            if tieneServidorLocal() then
                HoldoorServer.estado.baseX        = md.baseX
                HoldoorServer.estado.baseY        = md.baseY
                HoldoorServer.estado.baseZ        = md.baseZ or 0
                HoldoorServer.estado.baseDefinida = true
            end
            print("[Holdoor] Base restaurada desde ModData: " .. md.baseX .. ", " .. md.baseY)
        end
    end

    print("[Holdoor] Cliente inicializado v" .. HoldoorConfig.VERSION .. " -- usa /holdoor en el chat para abrir el panel")
    if tieneServidorLocal() then
        print("[Holdoor] Modo: SINGLE PLAYER (acceso directo al servidor)")
    else
        print("[Holdoor] Modo: MULTIPLAYER (comandos via red)")
    end

    -- Instalar el comando /holdoor (override de ISChat)
    HoldoorClient.instalarComandoChat()
end

-- ─────────────────────────────────────────────
--  KILL TRACKING LOCAL
--  Cuenta zombies muertos cerca de la base por este cliente.
--  En SP: exacto. En MP: cuenta muertes en el area cargada del jugador.
-- ─────────────────────────────────────────────

function HoldoorClient.onZombieMuertoLocal(zombie)
    local est = HoldoorClient.estado
    if est.fase ~= "activa" or not est.baseDefinida then return end

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
    if not HoldoorOverlayTrono.textura then return end
    if not HoldoorServer or not HoldoorServer.estado then return end
    local trono = HoldoorServer.estado.trono
    if not trono or not trono.piezaCentral then return end

    local hp = 0
    pcall(function() hp = trono.piezaCentral.obj:getHealth() end)
    if hp <= 0 then return end

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

    -- En B42, varios métodos de render pueden NO estar implementados.
    -- Si todos fallan, deshabilitamos el overlay para no spammear errores cada frame.
    local ok = false
    pcall(function()
        self:drawTextureScaled(HoldoorOverlayTrono.textura, drawX, drawY, W, H, alpha)
        ok = true
    end)
    if not ok then
        pcall(function()
            self:drawTexture(HoldoorOverlayTrono.textura, drawX, drawY, 1.0, 1.0, 1.0, alpha)
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
    ui:addToUIManager()
    HoldoorOverlayTrono._uiInstance = ui
    print("[Holdoor] Overlay Trono: UI element creado")
end

Events.OnGameStart.Add(HoldoorOverlayTrono.cargar)
Events.OnGameStart.Add(HoldoorOverlayTrono.crearUI)
