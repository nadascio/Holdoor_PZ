# Holdoor — Infraestructura técnica

> Vivo. Si algo no calza con la realidad → actualizar este doc primero, después tocar código.

## 1. Las 4 ubicaciones del mod — actualizado con evidencia empírica 2026-06-13

El mod vive en **4 ubicaciones** simultáneamente. **PZ carga de UNA sola** (verificado con el botón "TEST UBICACION"). Las otras 3 están "por consistencia" — para git, backups y eventual cambio del método de carga.

| # | Ubicación | Rol | PZ lee de acá? |
|---|---|---|---|
| 1 | `Documents/Holdoor_PZ/` | **Source of truth EDITORIAL** (git repo, lo que editás) | NO |
| 2 | `Zomboid/mods/Holdoor/` | Mod local | NO (con el mod publicado en Workshop) |
| 3 | `Zomboid/Workshop/Holdoor/Contents/mods/Holdoor/media/` | Base del Workshop | NO (en B42, ver abajo) |
| 4 | `Zomboid/Workshop/Holdoor/Contents/mods/Holdoor/42/` | **Source of truth RUNTIME** — PZ carga DE ACÁ | **SÍ** |

### Verificación empírica

Agregamos un botón "TEST UBICACION" al panel del mod (`HoldoorUI.lua`) con un identificador `HoldoorUI._UBICACION` distinto en cada copia. Al apretarlo en juego, PZ muestra cuál es la copia que está usando.

**Resultado 2026-06-13:** `WORKSHOP 42 (overlay B42)`. Confirmado.

### Por qué carga del 42/ y no de las otras

- El mod está **publicado en Steam Workshop** y suscripto en esta máquina.
- Steam descarga la versión publicada al folder `Zomboid/Workshop/<id>/Contents/mods/<modname>/`.
- PZ B42 dentro de ese folder prioriza la subcarpeta `42/` sobre `media/` raíz (mecanismo dual B41/B42).
- PZ **ignora** `Zomboid/mods/Holdoor/` cuando hay una versión del Workshop activa con el mismo mod ID.

### Implicancia operativa

- **Al editar y querer probar:** lo crítico es que `42/` esté sincronizado con el source. Las otras 2 destinos son nice-to-have.
- **NUNCA borrar la `42/`** sin antes haber confirmado que PZ va a leer de otro lado (botón TEST UBICACION).
- **Al publicar a Steam Workshop:** subís el folder del Workshop entero. Steam re-distribuye y los demás suscriptos también reciben la `42/`.

### Script de sync OBLIGATORIO

**No copies archivos sueltos. No.** Siempre `cp -r media/` enterito a TODAS las ubicaciones. Si no, te clavás con un overlay desincronizado.

```bash
SRC="C:/Users/nahue/Documents/Holdoor_PZ"
MODS="C:/Users/nahue/Zomboid/mods/Holdoor"
WS="C:/Users/nahue/Zomboid/Workshop/Holdoor/Contents/mods/Holdoor"

# 1. mods/Holdoor — donde PZ lee si esta como local
rm -rf "$MODS/media" && cp -r "$SRC/media" "$MODS/" && cp "$SRC/mod.info" "$MODS/"

# 2. Workshop media/ — base del Steam Workshop
rm -rf "$WS/media" && cp -r "$SRC/media" "$WS/" && cp "$SRC/mod.info" "$WS/"

# 3. Workshop 42/ — overlay B42 (mantener idéntico a media/)
rm -rf "$WS/42" && mkdir -p "$WS/42" && cp -r "$SRC/media" "$WS/42/" && cp "$SRC/mod.info" "$WS/42/"
```

### Verificar sync

```bash
for f in "media/lua/client/HoldoorClient.lua" "media/lua/client/HoldoorUI.lua" "media/lua/server/HoldoorServer.lua"; do
  md5sum "$SRC/$f" "$MODS/$f" "$WS/$f" "$WS/42/$f"
done
```

Los 4 hashes deben coincidir **por archivo**. Si alguno difiere → sync no completo, riesgo de comportamiento inestable.

### Flow de edición

1. Editar en `Documents/Holdoor_PZ/...`
2. Copiar archivos modificados a `Zomboid/mods/Holdoor/...` (mismo path relativo).
3. Recargar el save / reiniciar PZ.
4. Workshop solo se toca cuando se va a publicar.

### Cómo verificar que están sincronizados

```bash
md5sum "C:/Users/nahue/Documents/Holdoor_PZ/media/lua/server/HoldoorServer.lua" \
       "C:/Users/nahue/Zomboid/mods/Holdoor/media/lua/server/HoldoorServer.lua"
```

Si los hashes coinciden, están sincronizados.

## 2. Estructura del mod

```
Holdoor_PZ/
├── mod.info                  ← name, id, pzversion=42, modversion
├── poster.png                ← thumbnail Steam Workshop
├── docs/                     ← documentación técnica (este doc)
└── media/
    └── lua/
        ├── client/
        │   ├── HoldoorClient.lua    ← lógica cliente: render, input, recv server commands
        │   └── HoldoorUI.lua        ← panel F10, HUD, labels HP del Trono, checkbox
        └── server/
            └── HoldoorServer.lua    ← lógica server: spawn zombis, HP, damage boost, warnings
```

### Convención de nombres

- Todo el código en español **excepto identificadores** (Lua no acepta `ñ`/tildes en nombres de variables/funciones — ver `gotchas.md`).
- Funciones internas del mod prefijadas con `_` (ej: `_plantarTrono`, `_aplicarDanoBoost`).
- Comandos cliente↔server: snake_case sin prefijo (ej: `"tronoHP"`, `"warningTrono"`, `"tronoCayo"`).

## 3. Arquitectura cliente/servidor

### Build 42 — separación de Lua VMs

PZ B42 **separa los Lua VMs** de cliente y servidor incluso en singleplayer:

- `media/lua/server/` corre en el VM del servidor (incluso en SP, donde PZ levanta un server interno).
- `media/lua/client/` corre en el VM del cliente.
- **No comparten variables globales** ni tablas, ni siquiera en SP.

Por eso toda comunicación va por:

```lua
-- Cliente → servidor
sendClientCommand(player, "Holdoor", "comando", { args })

-- Servidor → cliente(s)
sendServerCommand(player, "Holdoor", "comando", { args })   -- a 1 player
sendServerCommand("Holdoor", "comando", { args })            -- broadcast
```

### Helper: ¿corre el servidor localmente?

```lua
local function tieneServidorLocal()
    return HoldoorServer ~= nil
end
```

Si `true` → estás en host SP/MP y podés invocar funciones de `HoldoorServer.*` directamente.
Si `false` → solo cliente conectado a server remoto, usar `sendClientCommand`.

## 4. El Trono de Hierro — modelo de datos

### Estructura

- **4 piezas** de `IsoThumpable` formando un 2×2.
- Cada pieza: 375 HP → total pool 1500 HP.
- Offsets: `{ {0,0}, {1,0}, {0,1}, {1,1} }`.
- Sprite: se busca el primero válido de la lista `HoldoorServer._tronoSprites` (validado contra `IsoSpriteManager.instance:getSprite`).

### Tabla de estado

```lua
HoldoorServer.estado.trono = {
    piezas = { obj, x, y, z },   -- 4 IsoThumpable
    sprite = "<nombre del sprite usado>",
    x, y, z,                      -- esquina de spawn
    maxHP = 375 * 4,              -- 1500
}
```

### Damage boost — compensa daño bajo vanilla

Cada 2 segundos en fase activa, por cada pieza del Trono:
1. Cuenta zombis **vivos** en los 8 tiles adyacentes.
2. Aplica `nZombis × damagePerZombi[modo]` HP de daño.

Escalado por modo:

| Modo | dmg/zombi/ciclo |
|---|---|
| facil | 1 |
| normal | 2 |
| dificil | 4 |
| pesadilla | 8 |
| test | 5 |

### Warnings de HP

Cuando el HP cruza un umbral hacia abajo, broadcast a clientes para mostrar mensaje centrado:

| % HP | Mensaje | Color |
|---|---|---|
| 60% | EL TRONO ESTA SIENDO ATACADO | amarillo |
| 30% | PELIGRO! EL TRONO ESTA POR CAER | rojo |
| 10% | ULTIMA LINEA DE DEFENSA! EL TRONO RESISTE | crítico |

### Game over

Si `modoDefensa = true` y HP llega a 0 → `_tronoCayo()` → broadcast `tronoCayo` → cliente muestra game over épico.

## 5. Economía virtual (ModData-based)

Items.txt en B42 dio problemas con `InventoryItemFactory.CreateItem`. Decisión: **no usamos items reales** para monedas/materiales, **todo es contador en ModData** del player.

### Monedas

- Bronce (B), Plata (P), Oro (O).
- Guardadas en `player:getModData().Holdoor.monedas`.
- Drop al fin de cada oleada según multiplicador del modo.

### Materiales

- Cuero, Hierro, Acero, Valyrio, Obsidiana.
- Mismo storage: `player:getModData().Holdoor.materiales`.
- Drop con probabilidades crecientes por modo.

## 6. Modos de juego

| Modo | Zombis base | +%/oleada | SR | Tick | Oleadas | dmg/zombi/ciclo |
|---|---|---|---|---|---|---|
| Facil | 15 | +10% | 5% | 90s | 6 | 1 |
| Normal | 25 | +12% | 10% | 60s | 8 | 2 |
| Dificil | 40 | +18% | 15% | 45s | 10 | 4 |
| Pesadilla | 60 | +25% | 20% | 30s | 12 | 8 |
| Test | 3 | 0% | 0% | 20s | 2 | 5 |

Multiplicador de monedas: facil ×0.5 / normal ×1 / dificil ×2 / pesadilla ×4 / test ×0.

## 7. Tabla global `HoldoorServer.estado`

```lua
estado = {
    activo = false,           -- ¿oleadas corriendo?
    fase = "espera",          -- "espera" | "activa" | "tregua" | "fin"
    oleadaActual = 0,
    config = { modoId, base, radio, mp_jugadores, ... },
    sesionDueno = "<username>",  -- solo este player puede detener
    trono = nil,              -- ver sección 4
    modoDefensa = false,      -- ¿pierdes si cae el Trono?
    ultimoHPTick = 0,         -- timestamp último broadcast HP
    ultimoDmgBoost = 0,       -- timestamp último damage boost
    ultimoHPNotificado = nil, -- para detectar umbrales en _checkWarningsHP
    -- ... más campos según funcionalidad
}
```

## 8. Comandos cliente↔servidor relevantes

| Comando | Dir | Args | Para qué |
|---|---|---|---|
| `iniciar` | C→S | { config } | Arranca sesión de oleadas |
| `detener` | C→S | — | Stop sesión |
| `marcarBase` | C→S | { x, y, z } | Set centro de spawn |
| `forzarOleada` | C→S | — | Skip tregua |
| `estado` | S→C | { fase, oleada, zombisRestantes, ... } | Update HUD |
| `tronoHP` | S→C | { hp, maxHp } | Update barra HP del Trono |
| `warningTrono` | S→C | { msg, pct, color, hp, maxHp } | Mensaje centrado al cruzar umbral |
| `tronoCayo` | S→C | — | Game over épico |
| `monedasUpdate` | S→C | { B, P, O } | Refresh display monedas |

## 9. Mods externos relacionados (no integrados aún)

- **Medieval Z** (Steam Workshop) — armas/armaduras medievales. Pendiente: integrar como ítems comprables en tienda.
- (Pendiente catalogar otros que aparezcan.)

---

**Última actualización:** 2026-06-12 (post fix de ñ + limpieza 3 copias + fix cadáveres contados como zombis vivos)
