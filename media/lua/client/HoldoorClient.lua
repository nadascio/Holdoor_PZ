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

-- v0.7 #35: ACTIVAR Beso del Dios (admin trampoline 5s).
-- Llamada desde el boton del HUD lateral cuando el jugador tiene Beso en bolsa.
-- - SendCommandToServer "/setaccesslevel admin" → PZ activa godmode auto (cura todo)
-- - Watchdog cada frame por 30 frames: setNoClip(false) selectivo (GhostMode se queda ON)
-- - 150 frames despues (~5s): apaga GodMod/Invisible/NoClip + revert a "user"
-- - sendClientCommand "activarBeso" → server marca usado-por-vida + limpia bolsa
function HoldoorClient._activarBesoDelDios()
    local me = getSpecificPlayer(0)
    if not me then
        print("[Holdoor] Beso del Dios: ERROR - getSpecificPlayer(0) devolvio nil")
        return
    end
    local username = me:getUsername()
    if not username then return end

    -- v0.7 #37: validar que el jugador tenga ALGO que curar antes de quemar el uso unico.
    -- Cubre todo lo que el Beso cura: heridas fisicas (sangrado/cortes/mordeduras/fracturas/scratch),
    -- HP de body parts, zombificacion (ZOMBIE_INFECTION/FEVER) y stats vitales (hunger/thirst/fatigue).
    local necesitaCura = false
    pcall(function()
        local bd = me:getBodyDamage()
        if bd then
            local parts = bd:getBodyParts()
            if parts then
                for i = 0, parts:size() - 1 do
                    local bP = parts:get(i)
                    if bP then
                        local hp = 100; pcall(function() hp = bP:getHealth() end)
                        if hp < 100 then necesitaCura = true; return end
                        local b = false; pcall(function() b = bP:bitten() end)
                        if b then necesitaCura = true; return end
                        local inf = false; pcall(function() inf = bP:isInfectedWound() end)
                        if inf then necesitaCura = true; return end
                        local bld = false; pcall(function() bld = bP:bleeding() end)
                        if bld then necesitaCura = true; return end
                        local cut = false; pcall(function() cut = bP:isCut() end)
                        if cut then necesitaCura = true; return end
                        local dw = false; pcall(function() dw = bP:isDeepWounded() end)
                        if dw then necesitaCura = true; return end
                        local sc = false; pcall(function() sc = bP:scratched() end)
                        if sc then necesitaCura = true; return end
                        local frac = 0; pcall(function() frac = bP:getFractureTime() end)
                        if frac > 0 then necesitaCura = true; return end
                    end
                end
            end
        end
    end)
    -- Tambien zombificacion y stats vitales (umbral 0.15 para evitar disparo por minima sed)
    if not necesitaCura and CharacterStat then
        pcall(function()
            local s = me:getStats()
            if s then
                if s:get(CharacterStat.ZOMBIE_INFECTION) > 0 then necesitaCura = true end
                if s:get(CharacterStat.ZOMBIE_FEVER) > 0 then necesitaCura = true end
                if s:get(CharacterStat.HUNGER)  > 0.30 then necesitaCura = true end
                if s:get(CharacterStat.THIRST)  > 0.30 then necesitaCura = true end
                if s:get(CharacterStat.FATIGUE) > 0.30 then necesitaCura = true end
            end
        end)
    end
    if not necesitaCura then
        HoldoorClient.chat(getText("UI_Holdoor_chat_beso_sano"), 1, 0.6, 0.2)
        return
    end

    -- 1) Notificar al server que active el flag usado-por-vida + limpie la bolsa
    pcall(function() sendClientCommand(HoldoorConfig.MODULE, "activarBeso", {}) end)

    -- 2) Elevar a admin (godmode auto activa → cura todo + escudo + invulnerabilidad)
    -- v0.8 #23: si soy cliente remoto, delegar al host admin.
    HoldoorClient._setAccessLevelDelegado(username, "admin")
    HoldoorClient.chat(getText("UI_Holdoor_chat_beso_invocado"), 0.85, 0.55, 0.95)

    -- 3) Watchdog: apagar SOLO NoClip cada frame por 150 frames (toda la duracion del Beso).
    -- Antes era 30 frames pero el admin dura 5s = 150 frames; entre frame 30 y 150 PZ podia
    -- reactivar NoClip y trabarte entre objetos. Ahora cubre los 5s completos.
    -- No tocamos GhostMode (preferencia explicita de Nahuel).
    local watchdogFrames = 150
    local watchdogHandler
    watchdogHandler = function()
        if me then
            pcall(function() me:setNoClip(false) end)
        end
        watchdogFrames = watchdogFrames - 1
        if watchdogFrames <= 0 then
            Events.OnTick.Remove(watchdogHandler)
        end
    end
    Events.OnTick.Add(watchdogHandler)

    -- 4) 150 frames despues (~5s): apagar flags + revert a user
    local frames = 150
    local revertHandler
    revertHandler = function()
        frames = frames - 1
        if frames <= 0 then
            pcall(function() me:setGodMod(false) end)
            pcall(function() me:setInvisible(false) end)
            pcall(function() me:setNoClip(false) end)
            -- GhostMode NO se toca (preferencia explicita de Nahuel 2026-06-20)
            -- v0.8 #23: delegar al host admin si soy cliente remoto
            HoldoorClient._setAccessLevelDelegado(username, "user")
            print("[Holdoor] Beso del Dios: 5s terminados")
            Events.OnTick.Remove(revertHandler)
        end
    end
    Events.OnTick.Add(revertHandler)

    -- 5) Refrescar HUD para que desaparezca el boton (ya consumimos el Beso)
    if HoldoorHUD and HoldoorHUD.instance and HoldoorHUD.instance.actualizarHUD then
        HoldoorHUD.instance:actualizarHUD()
    end
end

-- v0.8 #4: RAISE UP JOHN SNOW (seguro de vida) — disparado automaticamente desde el server
-- cuando el HP del player llega a <15 Y tiene md.Holdoor_RaiseUp_Activo = true.
-- A diferencia del Beso (manual, click), este se dispara solo. Flow:
-- 1) Pantalla negra fade epica con texto "Levanten a John Snow" (5s)
-- 2) SendCommandToServer "/setaccesslevel admin" → godmode auto cura TODO de raiz
-- 3) Buscar tile seguro cerca del Trono (radio 3→15) o 20-25 tiles del lugar actual
-- 4) Teleport al tile encontrado
-- 5) Watchdog NoClip OFF durante todo el admin (igual que Beso del Dios)
-- 6) 5s post-revive con admin activo (invulnerabilidad para reposicionarse)
-- 7) Apagar GodMod/Invisible/NoClip + /setaccesslevel user
-- v0.8 #22: PUNTO DE RETORNO — teleport personal con countdown 5s sobre la cabeza.
-- CLAVE: NO se le da admin hasta el ultimo instante. Durante los 5s el player es vulnerable
-- (zombies pueden atacarlo, puede morir → pierde el item). Esto evita "beso mejorado".
-- Solo cuando el countdown llega a 0: admin trampoline + teleport + 3s post-teleport admin.
function HoldoorClient._ejecutarPuntoRetorno(coordsObjetivo)
    if not coordsObjetivo or not coordsObjetivo.x then return end
    local me = getSpecificPlayer(0)
    if not me then return end
    local username = me:getUsername()
    if not username then return end

    print(string.format("[Holdoor][PuntoRetorno] Iniciando countdown 5s -> (%d,%d,%d)",
        coordsObjetivo.x, coordsObjetivo.y, coordsObjetivo.z))
    HoldoorClient.chat(getText("UI_Holdoor_chat_tp_iniciado"), 0.95, 0.75, 0.20)

    -- Countdown 5s visible sobre la cabeza (setHaloNote validado en B42)
    local segundosRestantes = 5
    pcall(function() me:setHaloNote(getText("UI_Holdoor_tp_contador", tostring(segundosRestantes)), 255, 200, 80, 1200) end)

    local FRAMES_POR_SEG = 30
    local frameCounter = 0
    local countdownHandler
    countdownHandler = function()
        frameCounter = frameCounter + 1
        if frameCounter < FRAMES_POR_SEG then return end
        frameCounter = 0
        segundosRestantes = segundosRestantes - 1
        if segundosRestantes > 0 then
            pcall(function() me:setHaloNote(getText("UI_Holdoor_tp_contador", tostring(segundosRestantes)), 255, 200, 80, 1200) end)
        else
            -- ===== FIN COUNTDOWN: admin + teleport + 3s post-teleport admin =====
            Events.OnTick.Remove(countdownHandler)
            pcall(function() me:setHaloNote(getText("UI_Holdoor_tp_hecho"), 100, 255, 150, 1500) end)

            -- v0.8 #23: si soy cliente remoto, delegar al host admin. Si soy host, ejecutar directo.
            HoldoorClient._setAccessLevelDelegado(username, "admin")
            pcall(function() me:setZombiesDontAttack(true) end)

            -- v0.8 #23: 30 frames (~1s) en lugar de 5 — el delegate de setaccesslevel
            -- hace roundtrip amigo→server→host en MP. Necesita tiempo extra.
            local tpFrames = 30
            local tpHandler
            tpHandler = function()
                tpFrames = tpFrames - 1
                if tpFrames <= 0 then
                    Events.OnTick.Remove(tpHandler)
                    local tpCmd = string.format("/teleportto %d,%d,%d",
                        coordsObjetivo.x, coordsObjetivo.y, coordsObjetivo.z)
                    pcall(function() SendCommandToServer(tpCmd) end)
                    print("[Holdoor][PuntoRetorno] " .. tpCmd)
                end
            end
            Events.OnTick.Add(tpHandler)

            local watchdogFrames = 90
            local watchdogHandler
            watchdogHandler = function()
                if me then pcall(function() me:setNoClip(false) end) end
                watchdogFrames = watchdogFrames - 1
                if watchdogFrames <= 0 then Events.OnTick.Remove(watchdogHandler) end
            end
            Events.OnTick.Add(watchdogHandler)

            local revertFrames = 90
            local revertHandler
            revertHandler = function()
                revertFrames = revertFrames - 1
                if revertFrames <= 0 then
                    pcall(function() me:setGodMod(false) end)
                    pcall(function() me:setInvisible(false) end)
                    pcall(function() me:setNoClip(false) end)
                    pcall(function() me:setZombiesDontAttack(false) end)
                    -- v0.8 #23: delegar al host admin si soy cliente remoto
                    HoldoorClient._setAccessLevelDelegado(username, "user")
                    print("[Holdoor][PuntoRetorno] 3s terminados")
                    Events.OnTick.Remove(revertHandler)
                end
            end
            Events.OnTick.Add(revertHandler)
        end
    end
    Events.OnTick.Add(countdownHandler)
end

function HoldoorClient._activarRaiseUpJohnSnow(coordsObjetivo)
    -- v0.8 #21: flujo de REVIVE post-muerte. Si coordsObjetivo viene, el char nuevo se
    -- teletransporta al lugar donde murio el viejo + matamos zombies 15 tiles alrededor
    -- (sin limpiar cadaveres → el cuerpo del muerto queda intacto para lootear).
    -- Si coordsObjetivo NO viene (legacy), busca tile seguro generico.
    local me = getSpecificPlayer(0)
    if not me then
        print("[Holdoor] RaiseUp: ERROR - getSpecificPlayer(0) devolvio nil")
        return
    end
    local username = me:getUsername()
    if not username then return end

    local esRevive = coordsObjetivo and coordsObjetivo.x and true or false
    print(string.format("[Holdoor] RaiseUp ACTIVADO para %s — esRevive=%s coords=%s",
        username, tostring(esRevive),
        esRevive and string.format("(%d,%d,%d)", coordsObjetivo.x, coordsObjetivo.y, coordsObjetivo.z) or "lugar-seguro"))
    if HoldoorServer and HoldoorServer._raiseDbg then HoldoorServer._raiseDbg("CLIENT-ANIMACION", username, "esRevive="..tostring(esRevive)) end

    -- 1) Pantalla negra fade epica
    if HoldoorRaiseUpFade and HoldoorRaiseUpFade.mostrar then
        pcall(function() HoldoorRaiseUpFade.mostrar() end)
    end
    if esRevive then
        HoldoorClient.chat(getText("UI_Holdoor_chat_jon_cadaver"), 0.95, 0.75, 0.20)
    else
        HoldoorClient.chat(getText("UI_Holdoor_chat_jon_simple"), 0.95, 0.75, 0.20)
    end

    -- 2) Elevar a admin (godmode auto activa → cura todo + escudo + invulnerabilidad)
    -- v0.8 #23: si soy cliente remoto, delegar al host admin
    HoldoorClient._setAccessLevelDelegado(username, "admin")
    print("[Holdoor] RaiseUp: admin enviado (20s)")

    -- ZombiesDontAttack: refuerza proteccion durante los 20s
    pcall(function() me:setZombiesDontAttack(true) end)

    -- 3) TELEPORT a 5 frames (~80ms — admin ya se aplico).
    -- NOTA v0.8 #21: el matar-zombies NO se hace aca, lo hizo el server ANTES del dispatch
    -- (via HoldoorServer._matarZombiesEnArea que usa setHealth(0) sin tocar cadaveres).
    -- /removezombies en cliente era contraproducente: borra cuerpos incluido el del player.
    -- v0.8 #23: 30 frames (~1s) — necesario para que el delegate setaccesslevel roundtrip en MP.
    -- v0.8.10: subimos a 120 frames (~4s) para friend remoto. El delegate setaccesslevel toma
    -- mas tiempo en cliente remoto (host admin recibe pedido + ejecuta + replica admin status).
    -- En SP/host local es instantaneo (igual funciona con 4s — no rompe nada).
    -- Ademas el server tambien dispatcha ejecutarTeleportTargetAdmin como redundancia.
    local teleportFrames = 120
    local teleportHandler
    teleportHandler = function()
        teleportFrames = teleportFrames - 1
        if teleportFrames <= 0 then
            if esRevive then
                local tpCmd = string.format("/teleportto %d,%d,%d",
                    coordsObjetivo.x, coordsObjetivo.y, coordsObjetivo.z)
                pcall(function() SendCommandToServer(tpCmd) end)
                print("[Holdoor] RaiseUp Revive: " .. tpCmd .. " enviado")
            else
                HoldoorClient._teleportLugarSeguro(me)
            end
            Events.OnTick.Remove(teleportHandler)
        end
    end
    Events.OnTick.Add(teleportHandler)

    -- 4) Watchdog NoClip OFF cada frame durante 600 frames (~20s total admin, v0.8 #20)
    local watchdogFrames = 600
    local watchdogHandler
    watchdogHandler = function()
        if me then pcall(function() me:setNoClip(false) end) end
        watchdogFrames = watchdogFrames - 1
        if watchdogFrames <= 0 then Events.OnTick.Remove(watchdogHandler) end
    end
    Events.OnTick.Add(watchdogHandler)

    -- 5) 600 frames (~20s = 10s animacion + 10s reacomodarse post-teleport) → apagar flags + revert (v0.8 #20)
    local frames = 600
    local revertHandler
    revertHandler = function()
        frames = frames - 1
        if frames <= 0 then
            pcall(function() me:setGodMod(false) end)
            pcall(function() me:setInvisible(false) end)
            pcall(function() me:setNoClip(false) end)
            pcall(function() me:setZombiesDontAttack(false) end)  -- v0.8 #12: tambien apagar
            -- GhostMode NO se toca (preferencia de Nahuel — igual que Beso del Dios)
            -- v0.8 #23: delegar al host admin si soy cliente remoto
            HoldoorClient._setAccessLevelDelegado(username, "user")
            print("[Holdoor] RaiseUp: 20s terminados")
            Events.OnTick.Remove(revertHandler)
        end
    end
    Events.OnTick.Add(revertHandler)

    -- 6) Refrescar HUD para que desaparezca el boton del Raise
    if HoldoorHUD and HoldoorHUD.instance and HoldoorHUD.instance.actualizarHUD then
        HoldoorHUD.instance:actualizarHUD()
    end
end

-- Helper: buscar tile sin zombies cerca del Trono o del lugar de muerte.
-- Approach C hibrido (decidido en next_steps.md):
-- 1) Buscar cerca del Trono primero (radio 3→15)
-- 2) Si no encuentra, buscar 20-25 tiles del lugar actual del jugador
-- 3) Fallback: posicion original (no teleportar)
function HoldoorClient._teleportLugarSeguro(jugador)
    if not jugador then return end

    -- Posicion del Trono via estado.baseX/baseY del cliente (si esta marcada)
    local baseX, baseY, baseZ
    pcall(function()
        if HoldoorClient.estado and HoldoorClient.estado.baseDefinida then
            baseX = HoldoorClient.estado.baseX
            baseY = HoldoorClient.estado.baseY
            baseZ = HoldoorClient.estado.baseZ
        end
    end)

    local destX, destY, destZ

    -- 1) Intentar cerca del Trono (radio 3, 6, 10, 15)
    if baseX and baseY then
        for _, radio in ipairs({3, 6, 10, 15}) do
            for _, angulo in ipairs({0, math.pi*0.5, math.pi, math.pi*1.5, math.pi*0.25, math.pi*0.75}) do
                local tx = math.floor(baseX + radio * math.cos(angulo))
                local ty = math.floor(baseY + radio * math.sin(angulo))
                if HoldoorClient._tileEsSeguro(tx, ty, baseZ or 0) then
                    destX, destY, destZ = tx, ty, baseZ or 0
                    print(string.format("[Holdoor] RaiseUp: tile seguro cerca del Trono (%d,%d) radio=%d", destX, destY, radio))
                    break
                end
            end
            if destX then break end
        end
    end

    -- 2) Si no encontro, buscar 20-25 tiles del lugar actual del jugador
    if not destX then
        local px = jugador:getX()
        local py = jugador:getY()
        local pz = jugador:getZ()
        for _, radio in ipairs({20, 22, 25}) do
            for _, angulo in ipairs({0, math.pi*0.5, math.pi, math.pi*1.5}) do
                local tx = math.floor(px + radio * math.cos(angulo))
                local ty = math.floor(py + radio * math.sin(angulo))
                if HoldoorClient._tileEsSeguro(tx, ty, pz) then
                    destX, destY, destZ = tx, ty, pz
                    print(string.format("[Holdoor] RaiseUp: tile seguro lejos del lugar (%d,%d) radio=%d", destX, destY, radio))
                    break
                end
            end
            if destX then break end
        end
    end

    -- 3) v0.8 #13: ejecutar teleport via /teleportto comando vanilla.
    -- El setX/setY/setZ directo no funciona bien en MP (sync issues). El comando admin
    -- /teleportto x,y,z funciona 100% porque el jugador es admin temporal en este momento.
    if destX and destY then
        local cmd = string.format("/teleportto %d,%d,%d", destX, destY, destZ or 0)
        pcall(function() SendCommandToServer(cmd) end)
        print(string.format("[Holdoor] RaiseUp: %s enviado", cmd))
    else
        print("[Holdoor] RaiseUp: no se encontro tile seguro — quedando en lugar original con invulnerabilidad")
    end
end

-- Helper: chequea si un tile esta "seguro" (sin zombies cercanos).
function HoldoorClient._tileEsSeguro(x, y, z)
    if not x or not y then return false end
    -- Chequeo basico: pedir al world un IsoGridSquare valido
    local sq
    pcall(function() sq = getCell():getGridSquare(x, y, z or 0) end)
    if not sq then return false end
    -- Chequear que no haya zombies en el tile ni en los 8 adyacentes
    for dx = -1, 1 do
        for dy = -1, 1 do
            local nsq
            pcall(function() nsq = getCell():getGridSquare(x+dx, y+dy, z or 0) end)
            if nsq then
                local movingObjs
                pcall(function() movingObjs = nsq:getMovingObjects() end)
                if movingObjs then
                    local size = 0; pcall(function() size = movingObjs:size() end)
                    for i = 0, size - 1 do
                        local mo; pcall(function() mo = movingObjs:get(i) end)
                        if mo and instanceof(mo, "IsoZombie") then
                            return false  -- zombie cerca, descartar este tile
                        end
                    end
                end
            end
        end
    end
    return true
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

-- v0.8 #23: detectar si SOY el host (SP, CoopHost host, dedicated server).
-- En B42 el codigo del server se carga en TODOS los clientes, asi que el check viejo
-- (type(HoldoorServer)) siempre devolvia true → todos los clientes ejecutaban codigo
-- del server LOCAL y nunca enviaban sendServerCommand al server real → broadcast roto.
-- Patron validado en este mismo archivo lineas 1438-1465 (bridges admin).
local function tieneServidorLocal()
    -- SP puro: isClient() devuelve false (no soy cliente, soy "todo en uno")
    if not isClient() then return true end
    -- CoopHost host: isCoopHost() == true
    local r1; pcall(function() r1 = isCoopHost() end); if r1 then return true end
    -- Dedicated server (no aplica en cliente pero defensivo)
    local r2; pcall(function() r2 = isServer() end); if r2 then return true end
    -- Cliente remoto: no tengo acceso al server real, debo usar sendServerCommand
    return false
end

-- v0.8.15: distingue SINGLE PLAYER de cualquier forma de MP (CoopHost host O remoto).
-- DIFERENTE de tieneServidorLocal(): ese sigue usandose en los handlers CAT 2 para saber si
-- ejecutar las world APIs (true para SP y CoopHost host). esSinglePlayer() decide si una ACCION
-- del panel corre directo (SP) o se manda por sendClientCommand para que la logica corra en
-- SERVER context. Medido en v0.8.14 DIAG: en server-ctx el broadcast por red alcanza al host
-- (via estado.hostPlayer) Y al friend → ambos ven el HUD. En SP no hay red, corre directo.
local function esSinglePlayer()
    local ic = false
    pcall(function() ic = isClient() end)
    return not ic
end

-- v0.8 #23: helper para ejecutar /setaccesslevel via delegate al host admin si soy cliente remoto.
-- En MP los clientes NO admin no pueden ejecutar /setaccesslevel a si mismos. El amigo manda
-- una solicitud al server, el server le pide al host admin que ejecute el comando.
-- Mismo patron que delegarAddXp / delegarAddItem ya validado en el mod.
function HoldoorClient._setAccessLevelDelegado(targetUsername, level)
    if not targetUsername or not level then return end
    if tieneServidorLocal() then
        -- Soy host: ejecuto directo (como hasta ahora)
        pcall(function() SendCommandToServer('/setaccesslevel "' .. targetUsername .. '" ' .. level) end)
        print("[Holdoor] /setaccesslevel " .. targetUsername .. " " .. level .. " — ejecutado local (host)")
    else
        -- Soy cliente remoto: delego al host admin
        pcall(function()
            sendClientCommand(HoldoorConfig.MODULE, "delegarSetAccessLevel", {
                target = targetUsername, level = level,
            })
        end)
        print("[Holdoor] /setaccesslevel " .. targetUsername .. " " .. level .. " — DELEGADO al host admin")
    end
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
        HoldoorClient.chat(getText("UI_Holdoor_chat_rasgo_desc_id", tostring(traitId)), 1, 0.3, 0.2)
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
        HoldoorClient.chat(getText("UI_Holdoor_chat_rasgo_falla"), 1, 0.3, 0.2)
    else
        HoldoorClient.chat(getText("UI_Holdoor_chat_rasgo_ok"), 0.3, 1, 0.5)
    end
    return ok
end

function HoldoorClient.curarTraitLocal(traitId)
    local p = getSpecificPlayer(0)
    if not p then return false end

    local traitEnum = _resolverTraitEnum(traitId)
    if not traitEnum then
        print("[Holdoor] curarTraitLocal: no se pudo resolver '" .. tostring(traitId) .. "'")
        HoldoorClient.chat(getText("UI_Holdoor_chat_rasgo_desc"), 1, 0.3, 0.2)
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
        HoldoorClient.chat(getText("UI_Holdoor_chat_rasgo_curar_falla"), 1, 0.3, 0.2)
    else
        HoldoorClient.chat(getText("UI_Holdoor_chat_milagro_obrado"), 0.5, 1, 0.8)
    end
    return ok
end

-- ─────────────────────────────────────────────
--  RECIBIR NOTIFICACIONES DEL SERVIDOR
-- ─────────────────────────────────────────────

function HoldoorClient.onComandoServidor(modulo, comando, args)
    if modulo ~= HoldoorConfig.MODULE then return end

    -- v0.8.14 DIAG: si esto se imprime en el console del HOST, significa que sendServerCommand
    -- al host local SI llega por red en CoopHost -> el fix real puede usar OPCION B (logica en
    -- server context + world APIs por red al host). Si NUNCA aparece -> la red al host no llega
    -- y el fix debe usar onTick client-side leyendo el estado compartido.
    if comando == "diagPongHost" then
        local via = tostring(args and args.via or "?")
        print("[Holdoor][DIAG] *** PONG RECIBIDO POR RED EN CLIENT *** via=" .. via)
        if HoldoorClient.chat then
            pcall(HoldoorClient.chat, "[DIAG] PONG recibido por red (via " .. via .. ")", 0.3, 1.0, 0.3)
        end
        return
    end

    -- v0.8.17: el server avisa que moriste con Raise activo y revuelves a la vida → tenes legado
    -- pendiente. El boton del HUD ya se activo (via md sincronizado). Avisamos por chat + refresh HUD.
    if comando == "legadoDisponible" then
        if HoldoorClient.chat then
            pcall(HoldoorClient.chat, "[HOLDOOR] El R'hllor te ofrece volver. Apreta RAISE UP en el panel lateral para recuperar tu legado.", 0.95, 0.75, 0.20)
        end
        if HoldoorUI and HoldoorUI.actualizarTodo then pcall(HoldoorUI.actualizarTodo) end
        return
    end

    -- v0.7 #39: SEGURO DE MONEDAS — server avisa que el seguro esta activo al iniciar oleada.
    -- Snapshot del saldo se hace AL MORIR (no aca), asi que aca solo es un aviso generico.
    if comando == "seguroActivado" then
        local msg = getText("UI_Holdoor_toast_seguro")
        if HoldoorToast and HoldoorToast.mostrar then
            pcall(function() HoldoorToast.mostrar(msg, 0.4, 0.9, 1.0) end)
        end
        HoldoorClient.chat(getText("UI_Holdoor_chat_seguroon"), 0.4, 0.9, 1.0)
        return
    end

    -- v0.7 #38: SEGURO DE MONEDAS — server avisa al respawn que se restauraron monedas.
    if comando == "seguroRestaurado" then
        local b = args.bronze or 0
        local s = args.silver or 0
        local g = args.gold   or 0
        local besoStr = args.beso_bolsa and " + Beso del Dios preservado" or ""
        local msg = "EL BANCO TE DEVUELVE: " .. b .. "B / " .. s .. "P / " .. g .. "O" .. besoStr
        if HoldoorToast and HoldoorToast.mostrar then
            pcall(function() HoldoorToast.mostrar(msg, 1.0, 0.85, 0.3) end)
        end
        HoldoorClient.chat(getText("UI_Holdoor_chat_banco_devuelve", tostring(b), tostring(s), tostring(g), besoStr), 1.0, 0.85, 0.3)
        return
    end

    -- v0.7 #40: PAGO PENDIENTE COBRADO — al reconectarse, el jugador recibe recompensas
    -- acumuladas mientras estaba offline (oleadas terminadas en su ausencia).
    if comando == "pagoPendienteCobrado" then
        local b = args.bronze or 0
        local s = args.silver or 0
        local g = args.gold   or 0
        local mats = args.materiales or {}
        local hayMats = false
        local matStr = {}
        for k, v in pairs(mats) do
            if v and v > 0 then
                hayMats = true
                table.insert(matStr, v .. " " .. k)
            end
        end
        local msg = "RECOMPENSAS PENDIENTES: " .. b .. "B / " .. s .. "P / " .. g .. "O"
        if hayMats then msg = msg .. " + materiales" end
        if HoldoorToast and HoldoorToast.mostrar then
            pcall(function() HoldoorToast.mostrar(msg, 1.0, 0.85, 0.3) end)
        end
        local matsTxt = hayMats and (" + " .. table.concat(matStr, ", ")) or ""
        HoldoorClient.chat(getText("UI_Holdoor_chat_recompensas_offline", tostring(b), tostring(s), tostring(g), matsTxt), 1.0, 0.85, 0.3)
        return
    end

    -- v0.8 #22: Punto de Retorno — checkpoint personal por player.
    -- Flow: 1) Player apreta "Marcar" → server guarda coords actuales → confirma con "puntoRetornoMarcado"
    --       2) Player apreta "Teletransportar" → server consume bolsa + dispatch "puntoRetornoDisparado"
    --          → cliente ejecuta countdown 5s + admin trampoline + teleport al final.
    if comando == "puntoRetornoMarcado" then
        if args and args.esReemplazo then
            HoldoorClient.chat(getText("UI_Holdoor_chat_punto_reemplazado"), 0.40, 0.85, 0.95)
        else
            HoldoorClient.chat(getText("UI_Holdoor_chat_punto_marcado"), 0.40, 0.85, 0.95)
        end
        if HoldoorHUD and HoldoorHUD.instance and HoldoorHUD.instance.actualizarHUD then
            pcall(function() HoldoorHUD.instance:actualizarHUD() end)
        end
        return
    end
    if comando == "puntoRetornoDisparado" then
        if not (args and args.x and args.y) then return end
        local coords = { x = args.x, y = args.y, z = args.z or 0 }
        if HoldoorClient._ejecutarPuntoRetorno then
            HoldoorClient._ejecutarPuntoRetorno(coords)
        end
        if HoldoorHUD and HoldoorHUD.instance and HoldoorHUD.instance.actualizarHUD then
            pcall(function() HoldoorHUD.instance:actualizarHUD() end)
        end
        return
    end

    -- v0.8 #21: RAISE UP REVIVE — el char nuevo spawnea con needsRevive en el server.
    -- Server ya restauro skills/recetas/monedas/materiales. Cliente hace el flow visual:
    -- pantalla negra → admin → matar zombies en 15 tiles → teleport a coords muerte.
    if comando == "raiseUpRevive" then
        local coords = nil
        if args and args.x and args.y and args.z then
            coords = { x = args.x, y = args.y, z = args.z }
        end
        -- v0.8 #21 fix: limpiar md flags LOCAL inmediatamente (el server tambien lo hace pero
        -- transmitModData puede llegar tarde → bug visual "RAISE: ACTIVO (Xm)" post-revive).
        local me = getSpecificPlayer(0)
        if me then
            local md = me:getModData()
            if md then
                md.Holdoor_RaiseUp_Bolsa   = nil
                md.Holdoor_RaiseUp_Activo  = nil
                md.Holdoor_RaiseSnapshotTs = nil
            end
        end
        if HoldoorClient._activarRaiseUpJohnSnow then
            HoldoorClient._activarRaiseUpJohnSnow(coords)
        end
        -- Refrescar HUD inmediatamente para que el boton vuelva a "no comprado"
        if HoldoorHUD and HoldoorHUD.instance and HoldoorHUD.instance.actualizarHUD then
            pcall(function() HoldoorHUD.instance:actualizarHUD() end)
        end
        return
    end

    -- v0.8 #4: server confirmó el toggle del Raise up (activo/desactivado). Refrescar HUD.
    if comando == "raiseUpToggleConfirmado" then
        local activo = args.activo and true or false
        if activo then
            HoldoorClient.chat(getText("UI_Holdoor_chat_raise_activo"), 0.30, 1.00, 0.40)
        else
            HoldoorClient.chat(getText("UI_Holdoor_chat_raise_off"), 1.00, 0.55, 0.20)
        end
        if HoldoorHUD and HoldoorHUD.instance and HoldoorHUD.instance.actualizarHUD then
            HoldoorHUD.instance:actualizarHUD()
        end
        return
    end

    -- v0.7 #33: COMENTADO — la categoria "Bendiciones del Cuerpo" se elimino porque
    -- la elevacion a admin/moderator/gm/overseer activaba godmode auto que curaba TODO
    -- (no solo el stat especifico). El Beso del Dios consolido toda esta logica.
    -- Se deja comentado por si en el futuro encontramos forma de bypass del godmode auto.
    --[[
    if comando == "ejecutar_stats_reset" then
        local me = getSpecificPlayer(0)
        if me and args and args.target == me:getUsername() then
            local stats = me:getStats()
            local nutr; pcall(function() nutr = me:getNutrition() end)
            local nombres = args.stats or {}
            local valores = args.valores or {}
            local applied = 0
            for i, statName in ipairs(nombres) do
                local enum = CharacterStat and CharacterStat[statName]
                if enum then
                    local val = valores[i] or 0
                    pcall(function() stats:set(enum, val) end)
                    if isClient() then
                        pcall(function() sendPlayerStat(me, enum) end)
                    end
                    if statName == "HUNGER" and nutr then
                        pcall(function() nutr:setCalories(2200) end)
                    end
                    applied = applied + 1
                else
                    print("[Holdoor] ejecutar_stats_reset: enum CharacterStat." .. tostring(statName) .. " no existe (ignorado)")
                end
            end
            print("[Holdoor] Bendicion del Cuerpo aplicada: " .. applied .. " stats reseteadas (" .. table.concat(nombres, ",") .. ")")

            local username = me:getUsername()
            local frames = 30
            local revertHandler
            revertHandler = function()
                frames = frames - 1
                if frames <= 0 then
                    pcall(function() SendCommandToServer('/setaccesslevel "' .. username .. '" user') end)
                    print("[Holdoor] Bendiciones: /setaccesslevel \"" .. username .. "\" user enviado (revert)")
                    Events.OnTick.Remove(revertHandler)
                end
            end
            Events.OnTick.Add(revertHandler)
        end
        return
    end
    ]]--

    if comando == "oleada" then
        HoldoorClient.mostrarOleada(args)

    elseif comando == "iniciado" then
        HoldoorClient.estado.activo            = true
        HoldoorClient.estado.killsOleada       = 0
        HoldoorClient.estado.killsPartida      = 0
        HoldoorClient.estado.misKills          = 0  -- v0.8.8: contador individual oleada
        HoldoorClient.estado.misKillsPartida   = 0  -- v0.8.8: contador individual total partida
        if args.config    then HoldoorClient.estado.config           = args.config    end
        if args.numPlayers then HoldoorClient.estado.numJugadores    = args.numPlayers end
        if args.multiplier then HoldoorClient.estado.playerMultiplier = args.multiplier end
        HoldoorClient.chat(getText("UI_Holdoor_chat_sistemaon"), 1, 0.4, 0.1)
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
        HoldoorClient.chat(getText("UI_Holdoor_chat_sistemaoff"), 0.7, 0.7, 0.7)
        if HoldoorUI then HoldoorUI.actualizarTodo() end

    elseif comando == "completado" then
        HoldoorClient.estado.activo = false
        HoldoorClient.estado.fase   = "inactivo"
        local oleadas = args.oleadas or 0
        HoldoorClient.guardarRecord(HoldoorClient.estado.modoId, oleadas)

        -- Armar linea de premio final
        local parts = {}
        if (args.silver or 0) > 0 then table.insert(parts, args.silver .. " " .. getText("UI_Holdoor_moneda_plata")) end
        if (args.gold   or 0) > 0 then table.insert(parts, args.gold   .. " " .. getText("UI_Holdoor_moneda_oro")) end
        local premioStr = #parts > 0 and ("[ +" .. table.concat(parts, ", ") .. " ]") or ""

        HoldoorClient.chat(getText("UI_Holdoor_chat_victoria", tostring(oleadas)) .. (premioStr ~= "" and ("  " .. premioStr) or ""), 0.2, 1, 0.4)

        -- Narrativa de fortuna: si el oro era probabilistico Y cayo, destacar
        local goldChance = args.goldChance or 1.0
        if (args.gold or 0) > 0 and goldChance < 1.0 then
            HoldoorClient.chat(getText("UI_Holdoor_chat_diossonrien", tostring(args.gold)), 1.0, 0.85, 0.15)
        elseif (args.gold or 0) == 0 and goldChance < 1.0 then
            HoldoorClient.chat(getText("UI_Holdoor_chat_fortuna"), 0.6, 0.6, 0.55)
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
                getText("UI_Holdoor_anuncio_victoria_tit"),
                getText("UI_Holdoor_anuncio_victoria_sub"),
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
        HoldoorClient.estado.killsOleada      = 0  -- contador equipo oleada
        HoldoorClient.estado.misKills         = 0  -- v0.8.8: reset individual al arrancar oleada
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
        -- v0.8.8: agregamos contadores INDIVIDUALES (misKills, misKillsPartida) en base a
        -- args.matador. Los contadores de EQUIPO existentes (killsOleada/killsPartida) se
        -- siguen incrementando en onZombieMuertoLocal (cliente local). NO los duplicamos acá.
        HoldoorClient.estado.oleadaKills      = args.kills or 0
        HoldoorClient.estado.oleadaTargetKills = args.target or HoldoorClient.estado.oleadaTargetKills
        -- Si el matador soy yo → incrementar mis contadores individuales.
        local miUsername = nil
        pcall(function()
            local p = getSpecificPlayer(0)
            if p then miUsername = p:getUsername() end
        end)
        local fueMio = (args.matador and miUsername and args.matador == miUsername)
        -- Fallback: si el server no identificó al matador, asumimos que fui yo (SP / host solo).
        if not args.matador then fueMio = true end
        if fueMio then
            HoldoorClient.estado.misKills        = (HoldoorClient.estado.misKills or 0) + 1
            HoldoorClient.estado.misKillsPartida = (HoldoorClient.estado.misKillsPartida or 0) + 1
        end
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
        -- i18n: el texto flotante se arma en el CLIENTE (cada quien en su idioma).
        -- El server manda tipo/cantidad/material; fallback a args.texto (ES) si tipo desconocido.
        local cant = args.cantidad or 1
        local txt = args.texto
        if args.tipo == "gold" then
            txt = "+" .. cant .. " " .. getText("UI_Holdoor_moneda_oro") .. " !!!"
        elseif args.tipo == "silver" then
            txt = "+" .. cant .. " " .. getText("UI_Holdoor_moneda_plata")
        elseif args.tipo == "bronce" then
            txt = "+" .. cant .. " Br"
        elseif args.tipo == "material" and args.material and HoldoorShopCatalog then
            txt = "+" .. cant .. " " .. HoldoorShopCatalog.labelOf(args.material)
        elseif args.tipo == "item" then
            local nm = (args.items and args.items[1] and getItemNameFromFullType and getItemNameFromFullType(args.items[1]))
                       or (args.items and args.items[1] and tostring(args.items[1]):gsub("^Base%.", ""))
                       or ""
            txt = getText("UI_Holdoor_drop_lootraro") .. ": " .. ((cant > 1) and (cant .. "x ") or "") .. nm
        end
        -- Sobre la cabeza del personaje (player:Say) — el user lo quiere asi
        -- v0.8.8: solo el cliente del matador hace Say + toast. Si args.matador no viene,
        -- fallback al comportamiento viejo (todos hacen Say) por safety.
        local p = getSpecificPlayer(0)
        local miUsername = p and p:getUsername() or nil
        local esParaMi = (not args.matador) or (miUsername and args.matador == miUsername)
        if esParaMi then
            if p and txt then pcall(function() p:Say(txt) end) end
            -- Tambien toast arriba (salvo bronce que es muy frecuente)
            if args.tipo ~= "bronce" and HoldoorToast and txt then
                pcall(HoldoorToast.mostrar, txt, r, g, b)
            end
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
        if (args.bronze or 0) > 0 then table.insert(parts, args.bronze .. " " .. getText("UI_Holdoor_moneda_bronce")) end
        if (args.silver or 0) > 0 then table.insert(parts, args.silver .. " " .. getText("UI_Holdoor_moneda_plata")) end
        if (args.gold   or 0) > 0 then table.insert(parts, args.gold   .. " " .. getText("UI_Holdoor_moneda_oro")) end
        local monStr = #parts > 0 and ("[ +" .. table.concat(parts, ", ") .. " ]") or ""

        HoldoorClient.chat(getText("UI_Holdoor_chat_oleadacompletada", tostring(args.numero or "?"), tostring(pausaSeg)) .. (monStr ~= "" and ("  " .. monStr) or ""), 0.2, 1, 0.4)

        -- v0.6.1: resumen de items entregados (antes era silencioso → bug confundia con drops sin notif)
        if args.items and #args.items > 0 then
            local conteos = {}
            local orden = {}
            for _, full in ipairs(args.items) do
                -- i18n: nombre legible/traducido del item (antes salia el tipo crudo "Gloves_LeatherGloves")
                local nm = getItemNameFromFullType(full) or (tostring(full):gsub("^Base%.", ""))
                if conteos[nm] == nil then table.insert(orden, nm); conteos[nm] = 0 end
                conteos[nm] = conteos[nm] + 1
            end
            local partsI = {}
            for _, nm in ipairs(orden) do
                local c = conteos[nm]
                table.insert(partsI, (c > 1 and (c .. "x ") or "") .. nm)
            end
            local botinStr = getText("UI_Holdoor_chat_botin", table.concat(partsI, ", "))
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
                HoldoorClient.chat(getText("UI_Holdoor_chat_jackpot", tostring(args.gold)), 1.0, 0.85, 0.15)
            elseif (args.silver or 0) > 0 then
                HoldoorClient.chat(getText("UI_Holdoor_chat_suerte", tostring(args.silver)), 0.75, 0.85, 1.0)
            end
        end

        playUISound("LevelPerk")

        -- v0.6: si fue CIERRE LIMPIO (kills >= target antes del timer), toast épico
        if args.cierreLimpio and HoldoorToast then
            HoldoorToast.mostrar(
                getText("UI_Holdoor_toast_cierrelimpio", tostring(args.kills or 0), tostring(args.target or 0)),
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
                getText("UI_Holdoor_anuncio_olcompleta_tit", tostring(args.numero or "?")),
                getText("UI_Holdoor_anuncio_olcompleta_sub", tostring(pausaSeg)),
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
        -- v0.7 #16: activar overlay del radio si el panel esta abierto (MP flow).
        if HoldoorUI and HoldoorUI.overlay and HoldoorUI.instancia and HoldoorUI.instancia:isVisible() then
            HoldoorUI.overlay:setVisible(true)
        end
        -- v0.8.16: CADA cliente planta su propia copia local del Trono (IsoThumpable). En MP
        -- CoopHost, crear el objeto client-side SOLO en el host NO se propaga al friend
        -- (transmitUpdatedSprite actualiza el sprite de un objeto EXISTENTE, no lo crea) y
        -- server-side no renderiza. Por eso el friend ahora planta su instancia local con las
        -- coords del broadcast (que le llegan gracias a OPCION B). HP/destruccion los maneja la
        -- logica del server por broadcasts. Ver gotchas "Objetos del mundo en MP CoopHost".
        if HoldoorServer and HoldoorServer._plantarTrono then
            pcall(function() HoldoorServer._plantarTrono(args.x, args.y, args.z) end)
        end

    elseif comando == "baseQuitada" then
        HoldoorClient.estado.baseX, HoldoorClient.estado.baseY, HoldoorClient.estado.baseZ = 0, 0, 0
        HoldoorClient.estado.baseDefinida = false
        HoldoorClient.estado.tronoHP, HoldoorClient.estado.tronoMaxHP = nil, nil
        -- v0.7 #16: esconder overlay al quitar base (no hay nada que mostrar).
        if HoldoorUI and HoldoorUI.overlay then HoldoorUI.overlay:setVisible(false) end
        -- v0.8.16: cada cliente quita SU copia local del Trono (mismo razonamiento que baseActualizada).
        if HoldoorServer and HoldoorServer._quitarTrono then
            pcall(function() HoldoorServer._quitarTrono() end)
        end
        -- Tambien borrar de ModData del propio jugador (persistencia)
        pcall(function()
            local md = ModData.getOrCreate("Holdoor")
            if md then md.baseX, md.baseY, md.baseZ, md.baseDefinida = nil, nil, nil, false end
        end)
        HoldoorClient.chat(getText("UI_Holdoor_chat_basequitada"), 0.6, 0.8, 1)
        if HoldoorUI then HoldoorUI.actualizarTodo() end

    elseif comando == "tronoHP" or comando == "braseroHP" then
        HoldoorClient.estado.tronoHP = args.hp or 0
        HoldoorClient.estado.tronoMaxHP = args.maxHp or 0
        if HoldoorUI then HoldoorUI.actualizarTodo() end

    elseif comando == "warningTrono" then
        local r, g, b = 1.0, 0.85, 0.20  -- amarillo default
        if args.color == "rojo" then r, g, b = 1.0, 0.45, 0.20 end
        if args.color == "critico" then r, g, b = 1.0, 0.15, 0.15 end
        local msgT = args.msgKey and getText(args.msgKey) or (args.msg or "ALERTA")
        HoldoorClient.chat("[HOLDOOR] !!! " .. msgT .. " !!!", r, g, b)
        if HoldoorAnnounce then
            HoldoorAnnounce.mostrar(
                "!!! " .. msgT .. " !!!",
                getText("UI_Holdoor_anuncio_trono_hp", tostring(args.pct or "?")),
                r, g, b, 240
            )
        end

    elseif comando == "tronoCayo" then
        HoldoorClient.estado.activo = false
        HoldoorClient.estado.fase   = "derrotado"
        HoldoorClient.chat(getText("UI_Holdoor_chat_tronocayo1"), 1, 0.10, 0.10)
        HoldoorClient.chat(getText("UI_Holdoor_chat_tronocayo2"), 1, 0.30, 0.20)
        if HoldoorAnnounce then
            -- v0.6.1 fix off-by-one: oleadas-1 porque caiste EN la oleada actual,
            -- no la sobreviviste. Ej: si moriste en la 3ra, sobreviviste 2.
            local sobrevividas = math.max(0, (args.oleadas or 1) - 1)
            local subline
            if sobrevividas == 0 then
                subline = getText("UI_Holdoor_derrota_sub0")
            elseif sobrevividas == 1 then
                subline = getText("UI_Holdoor_derrota_sub1")
            else
                subline = getText("UI_Holdoor_derrota_subN", tostring(sobrevividas), tostring(sobrevividas + 1))
            end
            HoldoorAnnounce.mostrar(getText("UI_Holdoor_anuncio_tronocayo"), subline, 1.0, 0.10, 0.10, 480)
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
            HoldoorClient.chat(getText("UI_Holdoor_chat_items_pies", tostring(nItems)), 0.5, 1, 0.6)
        end

    elseif comando == "transferOK" then
        local tipoMap = { bronze="UI_Holdoor_moneda_bronce", silver="UI_Holdoor_moneda_plata", gold="UI_Holdoor_moneda_oro" }
        local tipoLbl = (tipoMap[args.tipo] and getText(tipoMap[args.tipo])) or args.tipo
        HoldoorClient.chat(getText("UI_Holdoor_chat_enviaste", tostring(args.cantidad or 0), tipoLbl, tostring(args.to or "?")), 0.4, 1, 0.6)
        playUISound("LevelPerk")

    elseif comando == "compraOK" then
        HoldoorClient.chat(getText("UI_Holdoor_chat_compraste", tostring(args.nombre or "?")), 0.5, 1, 0.6)
        if HoldoorShop and HoldoorShop.refrescar then HoldoorShop.refrescar() end

    elseif comando == "compraFail" then
        HoldoorClient.chat("[HOLDOOR] " .. (args.motivo or "No se pudo completar la compra."), 1, 0.5, 0.2)


    elseif comando == "transferRecibido" then
        local tipoMap = { bronze="UI_Holdoor_moneda_bronce", silver="UI_Holdoor_moneda_plata", gold="UI_Holdoor_moneda_oro" }
        local tipoLbl = tipoMap[args.tipo] and getText(tipoMap[args.tipo]) or tostring(args.tipo)
        local cantR   = args.cantidad or 0
        local fromR   = args.from or "?"
        HoldoorClient.chat(getText("UI_Holdoor_tm_chat_recibiste", tostring(cantR), tipoLbl, fromR), 1, 0.85, 0.3)
        playUISound("LevelPerk")
        -- v0.8.x: feedback VISIBLE (el chat solo no se notaba). Texto flotante arriba de la cabeza
        -- + toast, como pidio Nahuel.
        local meR = getSpecificPlayer(0)
        if meR then pcall(function() meR:Say("+" .. cantR .. " " .. tipoLbl) end) end
        if HoldoorToast and HoldoorToast.mostrar then
            pcall(function() HoldoorToast.mostrar(getText("UI_Holdoor_tm_recibido", fromR, tostring(cantR), tipoLbl), 1.0, 0.85, 0.3) end)
        end

    elseif comando == "aplicarTrait" then
        HoldoorClient.aplicarTraitLocal(args.trait)

    elseif comando == "ejecutarAddXp" then
        if args.target and args.perk and args.amount then
            local cmd = string.format('/addxp "%s" %s=%d', args.target, tostring(args.perk), args.amount)
            pcall(function() SendCommandToServer(cmd) end)
            print("[Holdoor] ejecutarAddXp: " .. cmd)
        end

    elseif comando == "ejecutarSetAccessLevel" then
        -- v0.8 #23: el host admin recibe la solicitud de un cliente NO admin para que
        -- ejecute /setaccesslevel <target> <level>. Solo el host con permisos admin puede.
        if args.target and args.level then
            local cmd = string.format('/setaccesslevel "%s" %s', args.target, tostring(args.level))
            pcall(function() SendCommandToServer(cmd) end)
            print("[Holdoor] ejecutarSetAccessLevel: " .. cmd)
        end

    elseif comando == "ejecutarRestoreProgresoBatch" then
        -- v0.8 #21: lista de XP-deltas para restaurar en el char nuevo via /addxp admin.
        -- El player ya es admin durante los 20s del revive. Itera con 2 frames entre cada uno
        -- para no flood el server.
        if not args.xpDeltas then return end
        local me = getSpecificPlayer(0)
        if not me then return end
        local username = me:getUsername()
        if not username then return end
        print("[Holdoor][Restore] ejecutando " .. #args.xpDeltas .. " comandos /addxp...")
        local i = 1
        local framesEntre = 2
        local frameCounter = 0
        local restoreHandler
        restoreHandler = function()
            frameCounter = frameCounter + 1
            if frameCounter < framesEntre then return end
            frameCounter = 0
            if i > #args.xpDeltas then
                print("[Holdoor][Restore] " .. #args.xpDeltas .. " skills restauradas via /addxp")
                Events.OnTick.Remove(restoreHandler)
                return
            end
            local d = args.xpDeltas[i]
            if d and d.perk and d.amount and d.amount > 0 then
                local cmd = string.format('/addxp "%s" %s=%d', username, tostring(d.perk), d.amount)
                pcall(function() SendCommandToServer(cmd) end)
                print("[Holdoor][Restore] /addxp: " .. cmd)
            end
            i = i + 1
        end
        Events.OnTick.Add(restoreHandler)

    elseif comando == "ejecutarAddItem" then
        if args.target and args.items then
            for _, itemName in ipairs(args.items) do
                local cmd = string.format('/additem "%s" "%s" 1', args.target, tostring(itemName))
                pcall(function() SendCommandToServer(cmd) end)
                print("[Holdoor] ejecutarAddItem: " .. cmd)
            end
        end

    elseif comando == "ejecutarMatarZombiesLocal" then
        -- v0.8.10: matar zombies en CLIENT context del target (Raise up para friend remoto).
        -- Solo el target lo procesa. Usa setHealth(0) que NO toca cadaveres (preserva loot).
        local me = getSpecificPlayer(0)
        local miUsername = me and me:getUsername() or nil
        if miUsername and args.target == miUsername and args.x and args.y then
            local n = 0
            pcall(function()
                n = HoldoorServer._matarZombiesEnArea(args.x, args.y, args.z or 0, args.radio or 15) or 0
            end)
            print(string.format("[Holdoor] ejecutarMatarZombiesLocal (target=%s): %d zombies eliminados en (%d,%d,%d) radio=%d",
                miUsername, n, args.x, args.y, args.z or 0, args.radio or 15))
            if HoldoorServer and HoldoorServer._raiseDbg then HoldoorServer._raiseDbg("CLIENT-MATAR-ZOMBIES", miUsername, n.." eliminados radio="..(args.radio or 15)) end
        end

    elseif comando == "ejecutarLimpiarZonaLocal" then
        -- v0.8.13: ejecutar _limpiarZona en CLIENT context del HOST (para que setHealth(0) impacte
        -- los IsoZombies que el host VE en pantalla). En MP CoopHost, server context no impacta
        -- visualmente. Solo el host local lo procesa (filtra por tieneServidorLocal).
        -- _limpiarZona() lee HoldoorServer.estado (mismo VM Lua en CoopHost host). Coords se
        -- pasan en args como diagnostico (logs) y por si en futuro se refactoriza la funcion.
        if tieneServidorLocal() then
            local n = 0
            -- v0.8.15: pasar coords EXPLICITAS de args. Bajo OPCION B esto corre en el client-ctx
            -- del host, donde HoldoorServer.estado NO esta sincronizado con el server-ctx (contextos
            -- separados). Sin args, _limpiarZona limpiaria en 0,0,0.
            pcall(function()
                n = HoldoorServer._limpiarZona(args.bx, args.by, args.bz, args.radio) or 0
            end)
            print(string.format("[Holdoor] ejecutarLimpiarZonaLocal: %d eliminados (bx=%s, by=%s, radio=%s)",
                n, tostring(args.bx), tostring(args.by), tostring(args.radio)))
        elseif args.bx and args.by then
            -- v0.8.x FIX FRIEND: el friend tambien limpia, pero SOLO mata zombies vivos que VE
            -- (setHealth via _matarZombiesEnArea, que NO toca cadaveres → no borra su cuerpo).
            -- Resuelve los zombies "fantasma" que el host no ve pero el friend si, y que lo mordian
            -- al cerrar la oleada. El removeCorpse queda SOLO en el host (arriba): no lo hacemos en
            -- el friend para evitar riesgo del cuerpo + bugs por el delay 2-3s del server (Nahuel).
            local n = 0
            pcall(function()
                n = HoldoorServer._matarZombiesEnArea(args.bx, args.by, args.bz, args.radio) or 0
            end)
            print(string.format("[Holdoor] ejecutarLimpiarZonaLocal (FRIEND): %d zombies vivos eliminados (setHealth, sin cadaveres) radio=%s",
                n, tostring(args.radio)))
        end

    elseif comando == "ejecutarAddSoundLocal" then
        -- v0.8.13: ejecutar addSound en CLIENT context del HOST (AI de zombies es client-side
        -- en MP CoopHost). Coords EXPLICITAS en args. Solo el host local lo procesa.
        if tieneServidorLocal() and args.x and args.y then
            local ok = pcall(addSound, nil, args.x, args.y, args.z or 0,
                             args.radio or 100, args.vol or 150)
            print(string.format("[Holdoor] ejecutarAddSoundLocal: ok=%s (x=%d, y=%d, radio=%d, vol=%d)",
                tostring(ok), args.x, args.y, args.radio or 100, args.vol or 150))
        end

    elseif comando == "ejecutarReAggroLocal" then
        -- v0.8.15: pathToLocation sobre los IsoZombie que el host VE (client-ctx). En server-ctx
        -- no impacta el render del host (gotcha #62). Coords EXPLICITAS en args porque el estado
        -- del client-ctx no esta sincronizado bajo OPCION B. Solo el host local lo procesa.
        if tieneServidorLocal() and args.bx and args.by then
            local vistos = 0
            pcall(function()
                vistos = HoldoorServer._reAggroZombies(args.bx, args.by, args.bz, args.radioSpawn) or 0
            end)
            -- DIAG (v0.9.x): cuenta REAL de zombies que el host VE (client-ctx = la verdad).
            -- La verificacion del server cuenta server-ctx y ve fantasmas; ESTE es el numero real.
            print(string.format("[Holdoor][DIAG] host VE %d zombies en radio (bx=%s by=%s)",
                vistos, tostring(args.bx), tostring(args.by)))

            -- RESEGURO (v0.9.x): si el host NO ve un solo zombie durante una oleada activa por
            -- ~16s, el spawn fallo silencioso (/createhorde2 logueo "Spawning" pero no materializo
            -- en el cliente). Forzamos un spawn en los 4 cardinales para que nunca haya gaps muertos.
            local e = HoldoorClient.estado
            if vistos > 0 then
                e._reaseguroTicks = 0
            else
                e._reaseguroTicks = (e._reaseguroTicks or 0) + 1
                -- v0.9.x: cooldown 60s para que el reaseguro sea red de seguridad, no una bomba de
                -- acumulacion (antes podia disparar cada 16s y apilar backlog -> bursts gigantes).
                if e._reaseguroTicks >= 4 and os.time() >= (e._reaseguroUltimoSec or 0) + 60 then
                    e._reaseguroTicks = 0
                    e._reaseguroUltimoSec = os.time()
                    local dist = args.radioSpawn or 15
                    local bz   = args.bz or 0
                    local pts = {
                        { x = args.bx,        y = args.by - dist, l = "N" },
                        { x = args.bx + dist, y = args.by,        l = "E" },
                        { x = args.bx,        y = args.by + dist, l = "S" },
                        { x = args.bx - dist, y = args.by,        l = "O" },
                    }
                    e._pendienteHordaAdmin = e._pendienteHordaAdmin or {}
                    for _, p in ipairs(pts) do
                        table.insert(e._pendienteHordaAdmin, {
                            x = p.x, y = p.y, z = bz, count = 4, radius = 3, label = "RESEGURO-" .. p.l,
                        })
                    end
                    print("[Holdoor][RESEGURO] 0 zombies vistos por ~16s en oleada activa -> forzando spawn en 4 cardinales")
                end
            end

            print(string.format("[Holdoor] ejecutarReAggroLocal ejecutado (bx=%s, by=%s, radioSpawn=%s)",
                tostring(args.bx), tostring(args.by), tostring(args.radioSpawn)))
        end

    elseif comando == "ejecutarDanoTronoLocal" then
        -- v0.8.x FIX TRONO MP: el HOST aplica el daño a su Trono local (cuenta zombies adyacentes
        -- + setHealth) y reporta el HP de la forja al server. El Trono vive en el client-ctx del
        -- host (no en server-ctx), por eso el daño/HP se calculan aca. Solo el host (tieneServidorLocal).
        if tieneServidorLocal() then
            -- asegurar modoId en el client-ctx del host (vive en server-ctx) para que el daño por
            -- zombi de _aplicarDanoBoost use el valor del modo correcto, no el default "normal".
            pcall(function()
                HoldoorServer.estado.config = HoldoorServer.estado.config or {}
                if args.modoId then HoldoorServer.estado.config.modoId = args.modoId end
            end)
            pcall(function() HoldoorServer._aplicarDanoBoost() end)
            local trono = HoldoorServer.estado and HoldoorServer.estado.trono
            if trono and trono.piezaCentral and trono.piezaCentral.obj then
                local hp = 0
                pcall(function() hp = trono.piezaCentral.obj:getHealth() end)
                hp = math.max(0, hp)
                local maxHp = trono.maxHP or 1500
                pcall(function()
                    sendClientCommand(HoldoorConfig.MODULE, "reportarTronoHP", { hp = hp, maxHp = maxHp })
                end)
            end
        end

    elseif comando == "ajustarHPTronoLocal" then
        -- v0.8.x FIX TRONO MP: el host fija el HP de su Trono fisico al valor del modo (enviado por
        -- el server al iniciar). Corrige el plantado, que usa el default "normal" porque al marcar
        -- base el client-ctx aun no conocia el modoId. Solo el host (tieneServidorLocal).
        if tieneServidorLocal() then
            local hp = tonumber(args and args.hp) or 0
            local trono = HoldoorServer.estado and HoldoorServer.estado.trono
            if hp > 0 and trono and trono.piezas then
                trono.maxHP = hp
                if trono.piezaCentral then trono.piezaCentral.hpMax = hp end
                for _, p in ipairs(trono.piezas) do
                    if p and p.obj then pcall(function() p.obj:setHealth(hp) end) end
                end
            end
        end

    elseif comando == "ejecutarTeleportTargetAdmin" then
        -- v0.8.10: el HOST admin teletransporta al target con /teleportto "target" X,Y,Z.
        -- Solo el cliente del host (tieneServidorLocal) lo ejecuta. Si target == miUsername
        -- (host se teleporta a sí mismo), skip — ya lo hizo _activarRaiseUpJohnSnow.
        if tieneServidorLocal() and args.target and args.x and args.y then
            local me = getSpecificPlayer(0)
            local miUsername = me and me:getUsername() or nil
            if miUsername == args.target then
                print("[Holdoor] ejecutarTeleportTargetAdmin: target soy yo (host), skip (ya teleportado por _activarRaiseUpJohnSnow)")
            else
                local cmd = string.format('/teleportto "%s" %d,%d,%d',
                    args.target, args.x, args.y, args.z or 0)
                pcall(function() SendCommandToServer(cmd) end)
                print("[Holdoor] ejecutarTeleportTargetAdmin: " .. cmd)
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
            HoldoorClient.chat(getText("UI_Holdoor_chat_zona_despejada", tostring(n)), 0.4, 0.8, 1)
        end

    elseif comando == "aviso" then
        -- i18n: el server manda clave+args (no texto armado) → el cliente traduce a SU idioma.
        -- Fallback a args.mensaje crudo por si algún aviso legacy no manda clave.
        local txt
        if args.clave then
            txt = getText(args.clave, tostring(args.segs or ""))
        else
            txt = "[HOLDOOR] " .. (args.mensaje or "")
        end
        HoldoorClient.chat(txt, 1, 0.8, 0.2)

    elseif comando == "mensaje" then
        HoldoorClient.chat("[HOLDOOR] " .. (args.texto or ""), 1, 0.6, 0.2)

    elseif comando == "hordaSorpresa" then
        -- v0.9.x: evento Horda Sorpresa. Reusa HoldoorAnnounce (mismo cartel que las oleadas,
        -- MP-safe -> tu friend lo ve) + chat. SIN sonido. Cada cliente lo muestra en su idioma.
        if args.fase == "aviso" then
            if HoldoorAnnounce then
                HoldoorAnnounce.mostrar(getText("UI_Holdoor_sorpresa_tit"),
                    getText("UI_Holdoor_sorpresa_sub"), 1.0, 0.45, 0.05, 360)
            end
        elseif args.fase == "impacto" then
            if HoldoorAnnounce then
                HoldoorAnnounce.mostrar(getText("UI_Holdoor_sorpresa_impacto_tit"),
                    getText("UI_Holdoor_sorpresa_impacto_sub"), 1.0, 0.15, 0.05, 300)
            end
        elseif args.fase == "premio" then
            HoldoorClient.chat(getText("UI_Holdoor_sorpresa_premio", tostring(args.oro or 0)), 1, 0.85, 0.2)
        end

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

    -- v0.9.x: los separadores "=====" van SOLO en la ultima oleada (envuelven el texto
    -- ULTIMA OLEADA). En oleadas normales se quitaron: dejaban un marco verde vacio (el
    -- cartel central ya informa) — bug visual reportado por Nahuel.
    if esUltima then
        HoldoorClient.chat("=================================", 0.6, 0.3, 0.1)
        HoldoorClient.chat(getText("UI_Holdoor_anuncio_ultima"), 1, 0.1, 0.05)
        HoldoorClient.chat("=================================", 0.6, 0.3, 0.1)
        -- Alarma de ultima oleada: sube la tension
        playUISound("BurglarAlarm1")
    end
    -- v0.6: removido chat() "OLEADA N -- X en camino" — en modelo C no hay total fijo,
    -- decia "0 en camino" siempre. El cartel grande centrado de HoldoorAnnounce ya tiene la info.
    -- Frase epica (Valar Morghulis, etc): SOLO al toast superior, no sobre la cabeza
    -- (sino se tapa con el cartel grande centrado y otras UIs).
    if args.fraseIdx and HoldoorToast then
        local txt = getText("UI_Holdoor_frase_" .. args.fraseIdx)
        local autor = getText("UI_Holdoor_frase_" .. args.fraseIdx .. "_autor")
        if autor and autor ~= "" then txt = txt .. "   " .. autor end
        HoldoorToast.mostrar(txt, 0.95, 0.85, 0.45)
    end

    -- Anuncio épico centrado
    -- v0.7 #17: si el server mando subtituloEpico (flow hordasMP), usarlo tal cual.
    -- Sino caer al texto viejo "Amenaza: X -- Aguanta la puerta" (flow legacy).
    if HoldoorAnnounce then
        -- i18n: subtitulo traducido segun los indices que mando el server (o fallback si subVariante=0)
        local subText
        if args.subVariante and args.subVariante > 0 and args.subModo then
            subText = getText("UI_Holdoor_sub_" .. args.subModo .. "_" .. tostring(args.subOleada) .. "_" .. tostring(args.subVariante))
        else
            subText = getText("UI_Holdoor_sub_fallback")
        end
        if esUltima then
            HoldoorAnnounce.mostrar(
                getText("UI_Holdoor_anuncio_ultima"),
                subText,
                1.0, 0.08, 0.05,
                360
            )
        else
            HoldoorAnnounce.mostrar(
                getText("UI_Holdoor_anuncio_oleada", tostring(args.numero)),
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

    -- v0.7 #26: Beso del Dios — apagar godmode al pasar 5s del activado.
    -- Item uso unico (9 oro): la curacion en si la hacen las capas 2/3/4 (SetBitten/Infected,
    -- healthFull, stats ZOMBIE_INFECTION=0 server-auth). Godmode 5s da MARGEN para que el
    -- player escape del peligro inmediato que lo iba a matar (ej. rodeado por zombies).
    if est._besoDiosApagarEn and os.time() >= est._besoDiosApagarEn then
        est._besoDiosApagarEn = nil
        local me = getSpecificPlayer(0)
        if me then
            pcall(function() me:setGodMod(false) end)
            print("[Holdoor] Beso del Dios: godmode OFF (5s) — curacion total completada")
        end
    end

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
    -- v0.8.7: host local (SP / CoopHost host) llama HoldoorServer directo → corre en client
    -- context, donde setHealth(0) y addSound impactan los IsoZombie visibles. Solo cliente
    -- remoto usa sendClientCommand (correcto MP). Patron v0.7 restaurado.
    if esSinglePlayer() then
        local player = getSpecificPlayer(0)
        if player then
            local ok, err = pcall(HoldoorServer.iniciar, player, config)
            if not ok then
                print("[Holdoor] iniciar ERROR: " .. tostring(err))
                HoldoorClient.chat(getText("UI_Holdoor_chat_error_iniciar", tostring(err)), 1, 0.2, 0.2)
            end
        end
    else
        sendClientCommand(HoldoorConfig.MODULE, "iniciar", { config = config })
    end
end

function HoldoorClient.detener()
    -- v0.8.7: ver iniciar.
    if esSinglePlayer() then
        local player = getSpecificPlayer(0)
        if player then
            local ok, err = pcall(HoldoorServer.detener, player)
            if not ok then print("[Holdoor] detener ERROR: " .. tostring(err)) end
        end
    else
        sendClientCommand(HoldoorConfig.MODULE, "detener", {})
    end
end

function HoldoorClient.setBase()
    local player = getSpecificPlayer(0)
    if not player then return end
    local x = math.floor(player:getX())
    local y = math.floor(player:getY())
    local z = math.floor(player:getZ())

    -- v0.8.x ANTI-EXPLOIT: el Trono debe plantarse a nivel del suelo (planta baja, Z=0). Sin esto
    -- el jugador lo pone en un piso superior y rompe la escalera -> los zombis nunca pathean -> gana
    -- gratis. La validacion va ACA (cliente), ANTES de marcar local/optimista: si validamos solo en
    -- el server, el cliente ya seteo baseDefinida + mostro el toast "Base marcada" antes de que el
    -- server alcance a rechazar. (La validacion del server queda igual como respaldo.)
    if z ~= 0 then
        HoldoorClient.chat(getText("UI_Holdoor_aviso_nivelsuelo"), 1, 0.45, 0.45)
        return
    end

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
    -- v0.7 #16: activar overlay del radio inmediatamente al marcar base.
    -- Antes el overlay solo se hacia visible al RE-abrir el panel (bug: pelotitas invisibles
    -- hasta cerrar+abrir F10 de nuevo).
    if HoldoorUI and HoldoorUI.overlay and HoldoorUI.instancia and HoldoorUI.instancia:isVisible() then
        HoldoorUI.overlay:setVisible(true)
    end
    HoldoorClient.chat(getText("UI_Holdoor_chat_basemarcada", tostring(x), tostring(y)), 0.4, 0.8, 1)

    -- v0.8.7: ver iniciar.
    if esSinglePlayer() then
        local ok, err = pcall(HoldoorServer.setBase, player, x, y, z)
        if not ok then
            print("[Holdoor] setBase ERROR: " .. tostring(err))
            HoldoorServer.estado.baseX        = x
            HoldoorServer.estado.baseY        = y
            HoldoorServer.estado.baseZ        = z
            HoldoorServer.estado.baseDefinida = true
        end
    else
        sendClientCommand(HoldoorConfig.MODULE, "setBase", { x=x, y=y, z=z })
    end
end

function HoldoorClient.quitarBase()
    local player = getSpecificPlayer(0)
    if not player then return end

    -- v0.8.7: ver iniciar.
    if esSinglePlayer() then
        local ok, err = pcall(HoldoorServer.quitarBase, player)
        if not ok then print("[Holdoor] quitarBase ERROR: " .. tostring(err)) end
    else
        sendClientCommand(HoldoorConfig.MODULE, "quitarBase", {})
    end
end

function HoldoorClient.oleadaManual()
    -- v0.8.7: ver iniciar. Validaciones v0.7.
    if esSinglePlayer() then
        if not HoldoorServer.estado.activo then
            HoldoorClient.chat(getText("UI_Holdoor_chat_sistema_no_activo"), 1, 0.3, 0.2)
            return
        end
        if not HoldoorServer.estado.baseDefinida then
            HoldoorClient.chat(getText("UI_Holdoor_chat_primero_marca"), 1, 0.3, 0.2)
            return
        end
        if HoldoorServer.estado.fase == "activa" then
            HoldoorClient.chat(getText("UI_Holdoor_chat_ya_oleada"), 1, 0.6, 0.1)
            return
        end
        local ok, err = pcall(HoldoorServer._lanzarOleada)
        if not ok then
            print("[Holdoor] oleadaManual ERROR: " .. tostring(err))
            HoldoorClient.chat(getText("UI_Holdoor_chat_error_forzar", tostring(err)), 1, 0.2, 0.2)
        end
    else
        sendClientCommand(HoldoorConfig.MODULE, "oleadaManual", {})
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
                HoldoorClient.chat(getText("UI_Holdoor_chat_ya_tenes_rasgo"), 1, 0.6, 0.2)
                return
            end
        end
        -- Milagro: NO comprar si NO tiene el trait negativo (no hay nada que curar).
        if itemDef.accion.tipo == "cura_trait" then
            local loTiene = _playerTieneTrait(itemDef.accion.trait)
            if loTiene == false then
                HoldoorClient.chat(getText("UI_Holdoor_chat_no_tenes_rasgo"), 1, 0.6, 0.2)
                return
            end
        end
        -- v0.7 #36: Sanacion del Septon — NO comprar si el player no tiene heridas fisicas
        -- (sangrado / cortes / mordeduras / fracturas). El item cura esas 4 condiciones,
        -- no tiene sentido comprarlo healthy.
        if itemDef.accion.tipo == "reliquia_cura_completa" then
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
                            local b = false; pcall(function() b = bP:bleeding() end)
                            if b then necesitaCura = true; return end
                            local cut = false; pcall(function() cut = bP:isCut() end)
                            if cut then necesitaCura = true; return end
                            local dw = false; pcall(function() dw = bP:isDeepWounded() end)
                            if dw then necesitaCura = true; return end
                            local mord = false; pcall(function() mord = bP:bitten() end)
                            if mord then necesitaCura = true; return end
                            local frac = 0; pcall(function() frac = bP:getFractureTime() end)
                            if frac > 0 then necesitaCura = true; return end
                        end
                    end
                end)
            end
            if not necesitaCura then
                HoldoorClient.chat(getText("UI_Holdoor_chat_no_heridas"), 1, 0.6, 0.2)
                return
            end
        end

        -- v0.7 #35: Beso del Dios — ya NO bloqueamos por "no estas lastimado".
        -- Ahora el item va a una bolsa (HUD lateral) y el jugador decide cuando activarlo.
        -- Caso de uso del HUD: comprar tranquilo entre oleadas, activar en emergencia.
        -- Pre-check de wounds desactivado intencionalmente (comentado abajo).
        --[[
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
                HoldoorClient.chat(getText("UI_Holdoor_chat_beso_sano"), 1, 0.6, 0.2)
                return
            end
        end
        ]]--
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
                HoldoorClient.chat(getText("UI_Holdoor_chat_no_tenes_x", cfg.msg), 1, 0.6, 0.2)
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
            HoldoorClient.chat(getText("UI_Holdoor_chat_no_calcular_nivel"), 1, 0.3, 0.2)
            return
        end
        if infoNivel.max then
            HoldoorClient.chat(getText("UI_Holdoor_chat_ya_maximo"), 1, 0.6, 0.2)
            return
        end
    end

    local args = { categoria=categoriaId, item=itemId }
    if infoNivel then args.precioOverride = infoNivel.precio end
    -- v0.8.7: host local directo, remoto via sendClientCommand (ver iniciar).
    if esSinglePlayer() then
        local p = getSpecificPlayer(0)
        if p then
            local ok, err = pcall(HoldoorServer._comprar, p, args)
            if not ok then print("[Holdoor] comprar ERROR: " .. tostring(err)) end
        end
    else
        sendClientCommand(HoldoorConfig.MODULE, "comprar", args)
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

        -- v0.7 #35: Beso del Dios — COMPRA va a BOLSA, NO activa inmediato.
        -- La activacion real la hace el jugador click en el boton del HUD lateral,
        -- via HoldoorClient._activarBesoDelDios() (definida abajo).
        -- El server ya marco md.Holdoor_BesoDios_Bolsa = true al cobrar.
        -- Aca solo confirmamos visualmente que la compra entro a la bolsa.
        if accion.tipo == "reliquia_godmode_flash" and targetUser then
            HoldoorClient.chat(getText("UI_Holdoor_chat_beso_guardado"), 0.85, 0.55, 0.95)
            -- Refrescar HUD para que aparezca el boton nuevo
            if HoldoorHUD and HoldoorHUD.instance and HoldoorHUD.instance.actualizarHUD then
                HoldoorHUD.instance:actualizarHUD()
            end
        end

        -- v0.8 #4: Raise up John Snow — guardado en bolsa con seguro ACTIVO por default.
        -- El jugador puede togglearlo desde el HUD lateral (boton verde/rojo).
        if accion.tipo == "raise_up" and targetUser then
            HoldoorClient.chat(getText("UI_Holdoor_chat_raise_guardado"), 0.95, 0.75, 0.20)
            if HoldoorHUD and HoldoorHUD.instance and HoldoorHUD.instance.actualizarHUD then
                HoldoorHUD.instance:actualizarHUD()
            end
        end

        --[[
        -- v0.7 #33 (DEPRECADO en v0.7 #35): activacion inmediata al comprar.
        -- Reemplazado por el flow de bolsa. Codigo viejo abajo por si hace falta.
        if accion.tipo == "reliquia_godmode_flash" and targetUser then
            local me = getSpecificPlayer(0)
            if not me then
                print("[Holdoor] Beso del Dios: ERROR - getSpecificPlayer(0) devolvio nil")
            else
                pcall(function() SendCommandToServer('/setaccesslevel "' .. targetUser .. '" admin') end)
                local frames = 150
                local revertHandler
                revertHandler = function()
                    frames = frames - 1
                    if frames <= 0 then
                        pcall(function() me:setGodMod(false) end)
                        pcall(function() me:setInvisible(false) end)
                        pcall(function() me:setNoClip(false) end)
                        pcall(function() me:setGhostMode(false) end)
                        pcall(function() SendCommandToServer('/setaccesslevel "' .. targetUser .. '" user') end)
                        Events.OnTick.Remove(revertHandler)
                    end
                end
                Events.OnTick.Add(revertHandler)
            end
        end
        ]]--

        -- v0.7 #33: COMENTADO — Beso del Dios viejo (4 capas: setGodMod + SetBitten/Infected
        -- + healthFull + ZOMBIE_INFECTION stats). Funcionaba parcial: curaba heridas fisicas
        -- pero la zombificacion volvia. Reemplazado por el admin trampoline arriba que es
        -- mas confiable (godmode auto del admin cura TODO de raiz).
        -- Se deja comentado por si en el futuro hace falta volver a esto.
        --[[
        if accion.tipo == "reliquia_godmode_flash" and targetUser then
            local me = getSpecificPlayer(0)
            if not me then
                print("[Holdoor] Beso del Dios: ERROR - getSpecificPlayer(0) devolvio nil")
            else
                local onlineID
                pcall(function() onlineID = me:getOnlineID() end)
                local okGm = pcall(function() me:setGodMod(true) end)
                if okGm then
                    HoldoorClient.estado._besoDiosApagarEn = os.time() + 5
                end
                local bd = me:getBodyDamage()
                if bd then
                    local parts = bd:getBodyParts()
                    if parts then
                        local size = parts:size()
                        for i = 0, size - 1 do
                            local bP = parts:get(i)
                            if bP then
                                pcall(function() bP:SetBitten(false) end)
                                pcall(function() bP:SetInfected(false) end)
                                pcall(function() bP:SetFakeInfected(false) end)
                            end
                            if isClient() then
                                pcall(function() sendClientCommand(me, "player", "onHealthCheatCurrentPlayer", {
                                    bodyPartIndex = i, action = "healthFull", id = onlineID
                                }) end)
                            else
                                if bP then pcall(function() bP:RestoreToFullHealth() end) end
                            end
                        end
                    end
                end
                local stats = me:getStats()
                if stats and CharacterStat then
                    pcall(function() stats:set(CharacterStat.ZOMBIE_INFECTION, 0) end)
                    pcall(function() stats:set(CharacterStat.ZOMBIE_FEVER, 0) end)
                    if isClient() then
                        pcall(function() sendPlayerStat(me, CharacterStat.ZOMBIE_INFECTION) end)
                        pcall(function() sendPlayerStat(me, CharacterStat.ZOMBIE_FEVER) end)
                    end
                end
            end
        end
        ]]--

        -- v0.7 #33: COMENTADO — stats_reset inline (Bendiciones del Cuerpo).
        -- Eliminado junto con la categoria del shop. Se deja comentado por si en el futuro
        -- encontramos forma de hacer stats:set sin disparar el godmode auto.
        --[[
        if accion.tipo == "stats_reset" and targetUser then
            local nombres = accion.stats or {}
            local me = getSpecificPlayer(0)
            if me then
                pcall(function() me:setInvisible(false) end)
                pcall(function() me:setGodMod(false) end)
                pcall(function() me:setNoClip(false) end)
                pcall(function() me:setGhostMode(false) end)
            end
            pcall(function() SendCommandToServer('/setaccesslevel "' .. targetUser .. '" moderator') end)
            local watchdogFrames = 60
            local watchdogHandler
            watchdogHandler = function()
                if me then
                    pcall(function() me:setInvisible(false) end)
                    pcall(function() me:setGodMod(false) end)
                    pcall(function() me:setNoClip(false) end)
                    pcall(function() me:setGhostMode(false) end)
                end
                watchdogFrames = watchdogFrames - 1
                if watchdogFrames <= 0 then
                    Events.OnTick.Remove(watchdogHandler)
                end
            end
            Events.OnTick.Add(watchdogHandler)
        end
        ]]--

        -- v0.7 #21: Sanacion del Septon — 17 sendClientCommand "healthFull" por body part.
        -- API vanilla del panel admin "Health Full (Body)". Cura heridas fisicas (sangrado,
        -- cortes, mordeduras, fracturas) pero NO toca el flag global de infeccion zombi.
        -- Para zombificacion existe el Beso del Dios (godmode flash).
        if accion.tipo == "reliquia_cura_completa" and targetUser then
            print("[Holdoor] Sanacion del Septon: INICIO curacion fisica (17 healthFull individuales)")
            local me = getSpecificPlayer(0)
            if not me then
                print("[Holdoor] Sanacion del Septon: ERROR - getSpecificPlayer(0) devolvio nil")
            else
                local onlineID
                pcall(function() onlineID = me:getOnlineID() end)
                local bd = me:getBodyDamage()
                if not bd then
                    print("[Holdoor] Sanacion del Septon: ERROR - getBodyDamage() nil")
                else
                    local parts = bd:getBodyParts()
                    if not parts then
                        print("[Holdoor] Sanacion del Septon: ERROR - getBodyParts() nil")
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
                                local bP = parts:get(i)
                                if bP then pcall(function() bP:RestoreToFullHealth() end) end
                            end
                        end
                        print("[Holdoor] Sanacion del Septon: " .. size .. " comandos enviados (action=healthFull)")
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

-- ════════════════════════════════════════════════════════════════════════════
-- VENTA (Mercader Oscuro). REMOCION SERVER-AUTORITATIVA (fix dupe CoopHost):
-- el client-ctx del HOST NO es autoritario sobre el inventario -> remover ahi NO
-- persiste en el save (las monedas si, por ModData+transmitModData) -> dupe. Por
-- eso el cliente NO remueve: solo arma la lista de IDs EXACTOS a vender (instancias
-- NO equipadas, via scanVendibles) y se la manda al SERVER, que las resuelve por ID
-- (patron vanilla getItemById(it:getID())) y las remueve en SU contexto autoritario
-- (persiste) + acredita sobre lo realmente removido. Anti-footgun: scanVendibles
-- excluye mano + ropa puesta. Anti-dupe: el server remueve PRIMERO y paga DESPUES,
-- y no hay remocion client-side que pueda doblar. cart = { {fullType, cantidad}, ... }.
-- ════════════════════════════════════════════════════════════════════════════
function HoldoorClient.vender(cart)
    if not cart or #cart == 0 then return end
    local p = getSpecificPlayer(0)
    if not p then return end

    -- Barrido de VENDIBLES (excluye equipado en mano + ropa puesta; incluye mochilas).
    local vend = HoldoorVentaCatalog.scanVendibles(p)

    -- Armamos la lista de IDs EXACTOS a vender (no removemos nada aca). El server
    -- los resuelve y remueve en su contexto autoritario -> persiste en CoopHost.
    local items       = {}   -- { {id=N, fullType="Base.X"}, ... }
    local brutoBronce = 0
    local unidades    = 0
    for _, linea in ipairs(cart) do
        local ft    = linea.fullType
        local pedir = math.floor(tonumber(linea.cantidad) or 0)
        local venta = ft and HoldoorVentaCatalog.ventaDe(ft) or nil
        local lista = vend[ft]
        if venta and lista and pedir > 0 then
            if pedir > #lista then pedir = #lista end
            for k = 1, pedir do
                local it = lista[k]
                local id = nil
                if it then pcall(function() id = it:getID() end) end
                if id then
                    table.insert(items, { id = id, fullType = ft })
                    brutoBronce = brutoBronce + HoldoorVentaCatalog.valorBronceEquiv(venta)
                    unidades    = unidades + 1
                end
            end
        end
    end

    if unidades <= 0 or brutoBronce <= 0 then
        HoldoorClient.chat(getText("UI_Holdoor_venta_sinitem"), 1, 0.6, 0.2)
        return
    end

    -- El SERVER remueve los items (autoritario -> PERSISTE en CoopHost) y acredita
    -- sobre lo realmente removido. Sin remocion client-side -> imposible dupe.
    local args = { items = items }
    if esSinglePlayer() then
        local ok, err = pcall(HoldoorServer._vender, p, args)
        if not ok then print("[Holdoor] vender ERROR: " .. tostring(err)) end
    else
        sendClientCommand(HoldoorConfig.MODULE, "vender", args)
    end

    -- Feedback (preview): el saldo REAL lo confirma el server via monedasActualizadas.
    local r = HoldoorVentaCatalog.calcularVenta(brutoBronce, unidades)
    HoldoorClient.chat(getText("UI_Holdoor_venta_ok", tostring(unidades), HoldoorShopCatalog.precioStr(r.credito)), 0.55, 0.85, 0.45)
    if HoldoorUI and HoldoorUI.actualizarTodo then pcall(HoldoorUI.actualizarTodo) end

    return r
end

function HoldoorClient.transferir(toUser, tipo, cantidad)
    local args = { to=toUser, tipo=tipo, cantidad=cantidad }
    -- v0.8.7: host local directo, remoto via sendClientCommand.
    if esSinglePlayer() then
        local p = getSpecificPlayer(0)
        if p then pcall(HoldoorServer._transferirMonedas, p, args) end
    else
        sendClientCommand(HoldoorConfig.MODULE, "transferir", args)
    end
end

function HoldoorClient.pedirEstado()
    -- v0.8.7: host local lee estado directo (v0.7), remoto via sendClientCommand.
    if tieneServidorLocal() then
        local est = HoldoorServer.estado
        HoldoorClient.estado.activo           = est.activo
        HoldoorClient.estado.fase             = est.fase
        HoldoorClient.estado.oleadaActual     = est.oleadaActual
        HoldoorClient.estado.zombiesRestantes = est.zombiesRestantes
        HoldoorClient.estado.zombiesTotal     = est.zombiesTotal
        HoldoorClient.estado.baseX            = est.baseX
        HoldoorClient.estado.baseY            = est.baseY
        HoldoorClient.estado.baseZ            = est.baseZ
        HoldoorClient.estado.baseDefinida     = est.baseDefinida
    else
        sendClientCommand(HoldoorConfig.MODULE, "pedirEstado", {})
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

-- F10 abre el panel si el player es admin. esAdmin() reconoce: SP / host hosted
-- (isServer=true) / accessLevel staff. Funciona en SP siempre y en MP para el host/admin.
-- /holdoor (comando de chat) hace exactamente lo mismo, es una alternativa. Cliente MP
-- no-admin: ni F10 ni /holdoor abren el panel (toast naranja "solo el host").
function HoldoorClient.onKeyPressed(key)
    if key ~= Keyboard.KEY_F10 then return end
    -- F10 funciona en SP siempre, y en MP solo si el player es admin (host o staff).
    -- esAdmin() reconoce: SP / host hosted (isServer=true) / accessLevel staff.
    -- Cliente MP random → toast naranja "Solo el host puede".
    if HoldoorClient.esAdmin() then
        HoldoorUI.abrir()
    else
        HoldoorClient.chat(getText("UI_Holdoor_chat_solo_host_panel"), 1, 0.4, 0.2)
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
                -- Todo /holdoor es admin/host only.
                if not HoldoorClient.esAdmin() then
                    HoldoorClient.chat(getText("UI_Holdoor_chat_solo_host_comando"), 1, 0.4, 0.2)
                    return
                end
                -- Subcomando despues de "/holdoor " (vacio = abrir panel).
                local resto = lower:sub(10):gsub("^%s+", ""):gsub("%s+$", "")
                if resto == "" then
                    HoldoorUI.abrir()
                else
                    local sub, num = resto:match("^(%a+)%s*(%d*)")
                    local cant = (num and num ~= "") and tonumber(num) or nil
                    if sub == "addall" or sub == "addbronce" or sub == "addsilver" or sub == "addgold" then
                        HoldoorClient.adminDarRecurso(sub, cant)
                    else
                        HoldoorClient.chat(getText("UI_Holdoor_cmd_usage"), 1, 0.7, 0.3)
                    end
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

-- v0.10: comandos admin de monedas (reemplazan el viejo boton TEST de la UI).
-- Solo admin/host (el gate esAdmin esta en el parser del chat). Escribe md +
-- transmitModData (persiste, gotcha #51). 'sub' = addall|addbronce|addsilver|addgold.
-- Los individuales aceptan [N] opcional (default 50/10/10); addall = bundle reducido.
function HoldoorClient.adminDarRecurso(sub, cantidad)
    local p = getSpecificPlayer(0)
    if not p then return false end
    local md = nil
    pcall(function() md = p:getModData() end)
    if not md then return false end
    local function add(key, n) md[key] = (md[key] or 0) + n end

    local detalle = nil
    if sub == "addall" then
        add("Holdoor_Bronze", 50); add("Holdoor_Silver", 10); add("Holdoor_Gold", 10)
        add("Holdoor_Cuero", 10); add("Holdoor_Hierro", 10); add("Holdoor_Acero", 10)
        add("Holdoor_Valyrio", 10); add("Holdoor_Obsidiana", 10)
        detalle = getText("UI_Holdoor_cmd_all")
    elseif sub == "addbronce" then
        local n = cantidad or 50; add("Holdoor_Bronze", n); detalle = n .. " " .. HoldoorShopCatalog.labelOf("bronze")
    elseif sub == "addsilver" then
        local n = cantidad or 10; add("Holdoor_Silver", n); detalle = n .. " " .. HoldoorShopCatalog.labelOf("silver")
    elseif sub == "addgold" then
        local n = cantidad or 10; add("Holdoor_Gold", n); detalle = n .. " " .. HoldoorShopCatalog.labelOf("gold")
    else
        return false
    end

    pcall(function() p:transmitModData() end)
    HoldoorClient.chat(getText("UI_Holdoor_cmd_added", detalle), 0.55, 0.85, 0.45)
    if HoldoorUI and HoldoorUI.actualizarTodo then pcall(HoldoorUI.actualizarTodo) end
    if HoldoorShop and HoldoorShop.refrescar then pcall(HoldoorShop.refrescar) end
    print("[Holdoor] cmd admin: " .. tostring(sub) .. " -> " .. tostring(detalle))
    return true
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
    print("[Holdoor v0.8.19 MARKER] Raise up fix contextos: muerte detecta raise via md.Bolsa (player modData, SI sincroniza entre contextos), y el boton ejecuta recuperarLegado EN CLIENT-CTX (donde _onPlayerMuerto guardo el snapshot). Medido: el GlobalModData NO cruza contextos en CoopHost. Prints DIAG activos.")
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
