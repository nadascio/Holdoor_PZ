-- ============================================================
--  Holdoor — Sistema de Oleadas  |  Cliente
--  Recibe notificaciones del servidor y maneja el chat/UI
-- ============================================================

require "HoldoorConfig"

HoldoorClient = HoldoorClient or {}

-- Estado local del cliente (reflejo del servidor)
HoldoorClient.estado = {
    activo           = false,
    oleadaActual     = 0,
    minutosRestantes = 0,
    baseX            = 0,
    baseY            = 0,
    baseZ            = 0,
    baseDefinida     = false,
    config           = {},
}

-- ─────────────────────────────────────────────
--  RECIBIR NOTIFICACIONES DEL SERVIDOR
-- ─────────────────────────────────────────────

function HoldoorClient.onComandoServidor(modulo, comando, args)
    if modulo ~= HoldoorConfig.MODULE then return end

    if comando == "oleada" then
        HoldoorClient.mostrarOleada(args)

    elseif comando == "iniciado" then
        HoldoorClient.estado.activo = true
        if args.config then
            HoldoorClient.estado.config = args.config
        end
        HoldoorClient.chat("[HOLDOOR] ¡Sistema de oleadas ACTIVADO! Preparate...", 1, 0.4, 0.1)

    elseif comando == "detenido" then
        HoldoorClient.estado.activo = false
        HoldoorClient.chat("[HOLDOOR] Sistema de oleadas detenido.", 0.7, 0.7, 0.7)

    elseif comando == "completado" then
        HoldoorClient.estado.activo = false
        HoldoorClient.chat("[HOLDOOR] ¡Todas las oleadas completadas! Sobreviviste " .. (args.oleadas or 0) .. " oleadas.", 0.2, 1, 0.4)

    elseif comando == "baseActualizada" then
        HoldoorClient.estado.baseX        = args.x
        HoldoorClient.estado.baseY        = args.y
        HoldoorClient.estado.baseZ        = args.z
        HoldoorClient.estado.baseDefinida = true
        HoldoorClient.chat("[HOLDOOR] Base establecida en " .. args.x .. ", " .. args.y, 0.4, 0.8, 1)

    elseif comando == "aviso" then
        HoldoorClient.chat("[HOLDOOR] " .. (args.mensaje or ""), 1, 0.8, 0.2)

    elseif comando == "mensaje" then
        HoldoorClient.chat("[HOLDOOR] " .. (args.texto or ""), 1, 0.6, 0.2)

    elseif comando == "estado" then
        -- Sincronizar estado completo al reconectarse
        for k, v in pairs(args) do
            HoldoorClient.estado[k] = v
        end
        -- Actualizar UI si está abierto
        if HoldoorUI and HoldoorUI.instancia then
            HoldoorUI.instancia:actualizarEstado()
        end
    end
end

-- ─────────────────────────────────────────────
--  MOSTRAR OLEADA EN PANTALLA
-- ─────────────────────────────────────────────

function HoldoorClient.mostrarOleada(args)
    HoldoorClient.estado.oleadaActual = args.numero or 0

    -- Línea de separación visual en el chat
    HoldoorClient.chat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", 0.6, 0.3, 0.1)

    -- Número de oleada
    HoldoorClient.chat("⚔  OLEADA " .. args.numero .. "  —  " .. args.cantidad .. " zombis en camino", 1, 0.3, 0.1)

    -- Frase de GoT
    if args.frase then
        HoldoorClient.chat(args.frase, 0.9, 0.8, 0.5)
    end
    if args.autor then
        HoldoorClient.chat("    " .. args.autor, 0.5, 0.5, 0.4)
    end

    HoldoorClient.chat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", 0.6, 0.3, 0.1)

    -- Actualizar contador en la UI si está abierta
    if HoldoorUI and HoldoorUI.instancia then
        HoldoorUI.instancia:actualizarEstado()
    end
end

-- ─────────────────────────────────────────────
--  ENVIAR COMANDOS AL SERVIDOR
-- ─────────────────────────────────────────────

function HoldoorClient.iniciar(config)
    sendServerCommand(HoldoorConfig.MODULE, "iniciar", { config = config })
end

function HoldoorClient.detener()
    sendServerCommand(HoldoorConfig.MODULE, "detener", {})
end

function HoldoorClient.setBase()
    local player = getSpecificPlayer(0)
    if not player then return end
    sendServerCommand(HoldoorConfig.MODULE, "setBase", {
        x = math.floor(player:getX()),
        y = math.floor(player:getY()),
        z = math.floor(player:getZ()),
    })
end

function HoldoorClient.oleadaManual()
    sendServerCommand(HoldoorConfig.MODULE, "oleadaManual", {})
end

function HoldoorClient.pedirEstado()
    sendServerCommand(HoldoorConfig.MODULE, "pedirEstado", {})
end

-- ─────────────────────────────────────────────
--  UTILITARIOS
-- ─────────────────────────────────────────────

function HoldoorClient.chat(texto, r, g, b)
    local player = getSpecificPlayer(0)
    if player then
        player:Say(texto)
    end
    -- Fallback: escribir en el chat del servidor
    if getGameTime then
        -- Usar addLineInChat si está disponible
        local chat = getPlayerInlineChat and getPlayerInlineChat(0)
        if chat then
            chat:addLineInChat(nil, texto, ChatType.General, false)
        end
    end
end

-- ─────────────────────────────────────────────
--  COMANDO DE CHAT: /holdoor
-- ─────────────────────────────────────────────

function HoldoorClient.onChatCommand(command, args)
    if command == "/holdoor" or command == "/hd" then
        HoldoorUI.abrir()
        return true
    end
    return false
end

-- ─────────────────────────────────────────────
--  INICIALIZACIÓN
-- ─────────────────────────────────────────────

function HoldoorClient.init()
    -- Pedir el estado actual al servidor al conectarse
    HoldoorClient.pedirEstado()
    -- Copiar config por defecto
    HoldoorClient.estado.config = {}
    for k, v in pairs(HoldoorConfig.defaults) do
        HoldoorClient.estado.config[k] = v
    end
    print("[Holdoor] Cliente inicializado v" .. HoldoorConfig.VERSION)
end

-- ─────────────────────────────────────────────
--  REGISTRO DE EVENTOS
-- ─────────────────────────────────────────────

Events.OnServerCommand.Add(HoldoorClient.onComandoServidor)
Events.OnGameStart.Add(HoldoorClient.init)
Events.OnChatCommand.Add(HoldoorClient.onChatCommand)
