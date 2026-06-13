# Holdoor — Gotchas (trampas aprendidas a la fuerza)

> Append-only. Cada entrada salió de un bug real. Leer ANTES de tocar el área correspondiente.

---

## 🔥 1. Lua de PZ (kahlua) NO acepta `ñ` ni tildes en IDENTIFICADORES

**Síntoma:** Contador rojo "ERROR 1" en la pantalla de carga de PZ. En consola:
```
se.krka.kahlua.vm.KahluaException: HoldoorServer.lua:794: '=' expected near 'ñ'
```

**Causa:** El parser kahlua (Lua VM de PZ) trata `ñ`/`á`/`é`/etc como tokens separados en nombres de variables/funciones. Si tenés `function _aplicarDañoBoost()`, el parser lo lee como `_aplicarDa` + `ñoBoost` y rompe.

**Fix:** Renombrar todos los identificadores a ASCII puro. `Daño` → `Dano`, `Año` → `Anio`, etc.

**Importante:** En **comentarios y strings la `ñ` es segura** — Lua acepta UTF-8 ahí. Solo rompe en identificadores.

**Cómo detectarlo:**
```bash
grep -n '[ñáéíóúÑÁÉÍÓÚ]' archivo.lua
```
Después chequear si están dentro de strings/comments (`--`, `"..."`, `'...'`, `[[...]]`) o son identificadores. Si es identificador → rename obligado.

**Cuando rompió:** 2026-06-12. La función `_aplicarDañoBoost` rompía todo el server lua, lo que hacía que **el mod entero no funcionara** (oleada no arrancaba, Trono no spawneaba, prints no aparecían).

---

## 🔥 2. PZ B42 hace OVERLAY de `42/` sobre `media/` — y el mod vive en 4 ubicaciones

**El comportamiento real de PZ B42 (clave para entender todo lo demás):**

Cuando un mod tiene una subcarpeta `42/` Y una `media/` en el root, PZ B42 hace **overlay**: lee archivos de `42/media/lua/...` **PRIMERO**, y para todo archivo que NO esté en `42/`, cae al `media/` del root. **No es "una u otra"**, es **merge con prioridad**.

Esto significa que si tenés:
- `42/media/lua/server/HoldoorServer.lua` (versión nueva con Trono)
- `media/lua/client/HoldoorUI.lua` (versión vieja sin Trono)

PZ va a usar el server NUEVO + cliente VIEJO. Tu mod va a estar parcialmente actualizado y se va a comportar raro.

**Las 4 ubicaciones del mod:**

1. `Documents/Holdoor_PZ/` — **source of truth única** (git repo, lo que editás).
2. `Zomboid/mods/Holdoor/` — lo que PZ carga si el mod está en `mods/` (instalación local).
3. `Zomboid/Workshop/Holdoor/Contents/mods/Holdoor/media/` — base del Workshop.
4. `Zomboid/Workshop/Holdoor/Contents/mods/Holdoor/42/` — **overlay B42-específico**. Hay que mantenerlo igual al `media/` o eliminarlo POR COMPLETO. Nunca dejarlo "a medias".

**Cómo se manifestó este bug en sprints anteriores Y en 2026-06-12:**

Durante sprints previos, distintos agentes (humanos y AI) sincronizaban **archivos puntuales** (sobre todo `HoldoorServer.lua`) a `42/`, dejando `media/` raíz desactualizado. PZ leía:
- `HoldoorServer.lua` nuevo (del 42/) → con Trono, F10, etc.
- `HoldoorClient.lua` viejo (del media/ raíz) → del commit inicial.
- `HoldoorUI.lua` viejo (del media/ raíz) → del commit inicial.

Funcionaba "a medias" — el server hacía todo el laburo pero el cliente y UI estaban parcialmente desconectados. Como vivía con cierta inestabilidad, parecía normal.

**Mi cagada del 2026-06-12 (la que casi pierde todo):**
1. Vi que había 4 ubicaciones y asumí "duplicación a limpiar".
2. Borré la `42/` creyendo que era redundante.
3. PZ perdió el overlay → cayó al `media/` raíz que tenía el commit inicial (mod casi vacío).
4. Hice `git checkout` para "restaurar archivos buenos" → pero git solo tenía el commit inicial.
5. **El laburo de meses estaba uncommitted en el source.** Solo se salvó porque hice backup ANTES de actuar.

**Fix lockeado:**

**Convención de las 4 ubicaciones:**
- Source: `Documents/Holdoor_PZ/`
- Sync OBLIGATORIO a las 3 destinos al editar cualquier archivo:
  - `Zomboid/mods/Holdoor/`
  - `Zomboid/Workshop/Holdoor/Contents/mods/Holdoor/` (media/ raíz)
  - `Zomboid/Workshop/Holdoor/Contents/mods/Holdoor/42/` (overlay B42)

**Script de sync seguro (copia TODO, no archivos sueltos):**
```bash
SRC="C:/Users/nahue/Documents/Holdoor_PZ"
MODS="C:/Users/nahue/Zomboid/mods/Holdoor"
WS="C:/Users/nahue/Zomboid/Workshop/Holdoor/Contents/mods/Holdoor"

rm -rf "$MODS/media" && cp -r "$SRC/media" "$MODS/" && cp "$SRC/mod.info" "$MODS/"
rm -rf "$WS/media"   && cp -r "$SRC/media" "$WS/"   && cp "$SRC/mod.info" "$WS/"
rm -rf "$WS/42"      && mkdir -p "$WS/42" && cp -r "$SRC/media" "$WS/42/" && cp "$SRC/mod.info" "$WS/42/"
```

**Verificar sync:** `md5sum` en cada ubicación. Si los 4 hashes coinciden por archivo → ok.

---

## 🔥 2b. Si tu único commit es muy viejo, NO restaures desde git como solución de "vuelta atrás"

**Síntoma:** Te pasa el bug 2, intentás resolver con `git checkout HEAD -- archivo.lua`, y de repente perdés meses de trabajo.

**Causa:** Si el repo tiene 1 solo commit muy viejo y todo el laburo está uncommitted, restaurar desde git te tira al estado del primer día — sin el sistema que estuviste construyendo.

**Cómo se manifestó el 2026-06-12:** Vi que el HoldoorClient.lua del Workshop tenía 7KB y el del source 32KB. Asumí que el source de 32KB era "work-in-progress no testeado" y restauré desde git al de 7KB del commit inicial. Resultado: perdí F10, esAdmin, todos los handlers del Trono, etc.

**Fix:**
1. **Antes de cualquier restore desde git**, hacer backup completo del source (`cp -r` a un folder con timestamp).
2. **Hacer commits frecuentes** mientras se trabaja, aunque sean WIP — para que git tenga estados intermedios funcionales a los que volver.
3. **Si el único commit es muy viejo**, asumir que git NO es respaldo — solo el filesystem (backups) lo es. Actuar conforme.

**Recuperación del bug:** El backup que hice ANTES de la cagada (`Holdoor_PZ_BACKUP_20260612_pre_restore`) salvó el laburo. Sin ese backup hoy estaríamos restaurando 6 meses de código desde cero.

---

## 🔥 3. `IsoThumpable` acepta sprite inexistente → objeto fantasma

**Síntoma:** Spawneás un IsoThumpable, el código no tira error, los zombis **lo atacan** (collision funciona), pero **no se ve visualmente**. Como si fuera invisible.

**Causa:** PZ B42 acepta un sprite name string que no existe en `IsoSpriteManager`. La instancia se crea, ocupa el tile y bloquea movement, pero al no haber sprite real cargado, no renderiza nada.

**Fix:** **Validar el sprite ANTES de spawnear:**

```lua
local function spriteExiste(name)
    local s
    pcall(function() s = IsoSpriteManager.instance:getSprite(name) end)
    if s then return s end
    pcall(function() s = getSprite(name) end)
    if s then return s end
    return nil
end

-- Iterar lista de candidatos hasta encontrar uno válido
for _, sprite in ipairs(_tronoSprites) do
    if spriteExiste(sprite) then
        -- spawn con este sprite
        break
    end
end
```

**Sprites confirmados que existen en B42 vanilla:**
- `carpentry_02_56`, `carpentry_02_64` (paredes de madera, fallback garantizado)
- (Pendiente confirmar muebles tipo trono al testear)

**Cuando rompió:** 2026-06-11 / 12. Pasaron varios intentos con sprites que asumí que existían pero no — IsoThumpable se creaba ok pero invisible.

---

## 🔥 4. Cadáveres siguen siendo `IsoZombie` → cuentan como atacantes

**Síntoma:** En el log `[Holdoor] Damage boost: -10 HP al Trono` constante, sin que ningún zombi vivo esté cerca. Daño pasivo fantasma.

**Causa:** `square:getMovingObjects()` retorna también **cadáveres**. Los cadáveres son `IsoZombie` con `isDead() == true`. Si solo filtrás `instanceof(obj, "IsoZombie")`, los contás como atacantes vivos.

**Fix:** Agregar filtro `isDead()`:

```lua
if obj and instanceof(obj, "IsoZombie") then
    local muerto = false
    pcall(function() muerto = obj:isDead() end)
    if not muerto then
        nZombis = nZombis + 1
    end
end
```

**Cuando rompió:** 2026-06-12. Calzaba aritméticamente: en NORMAL (dmg=2 por zombi) se veía `-10 HP` = 5 cadáveres × 2.

---

## 🔥 5. `Break On Error` del debugger pausa hasta los `pcall` capturados

**Síntoma:** El debugger de PZ se freezea en una línea de código que está envuelta en `pcall`, aunque el error está siendo capturado correctamente.

**Causa:** Cuando "Break On Error" está activo en el debugger, **rompe ante CUALQUIER excepción Java**, incluso las que `pcall` atrapa silenciosamente. Es una opción de debug, no un error real.

**Fix:** Desmarcar el checkbox "Break On Error" en la barra superior del debugger. Los `pcall` siguen funcionando bien — la pausa era solo visual.

**Cuando confundió:** Sesiones de 2026-06-11/12 con debug abierto.

---

## 🔥 6. Items.txt en B42 falla con `InventoryItemFactory.CreateItem`

**Síntoma:** Java exception al intentar crear items custom del mod (monedas, materiales).

**Causa:** B42 cambió el formato/proceso de items.txt y `CreateItem` no encuentra los items definidos del mod aunque estén bien escritos. Inestabilidad conocida del API en B42 temprano.

**Fix:** **No usar items reales** para monedas/materiales. Storage en `player:getModData()` como contadores:

```lua
local md = player:getModData()
md.Holdoor = md.Holdoor or {}
md.Holdoor.monedas = md.Holdoor.monedas or { B=0, P=0, O=0 }
md.Holdoor.monedas.B = md.Holdoor.monedas.B + 1
```

Más estable, más fácil de sincronizar en MP, evita el bug de items.txt.

**Cuando rompió:** Sprint de economía 2026-06-XX.

---

## 🔥 7. B42 separa Lua VMs cliente/servidor también en SP

**Síntoma:** Asumís que en SP los `media/lua/server/` y `media/lua/client/` comparten globales — y al asignar `HoldoorServer.estado.foo = X` en el server no aparece en el cliente.

**Causa:** B42 unificó la arquitectura: incluso en SP, PZ levanta un server interno con su propio Lua VM. Cliente y servidor **no comparten variables globales ni tablas**, ni siquiera en SP.

**Fix:** Toda comunicación cross-side debe ir por `sendServerCommand` / `sendClientCommand`. Nunca asumir acceso directo. Existe helper:

```lua
local function tieneServidorLocal()
    return HoldoorServer ~= nil   -- si la tabla existe en este VM, estás en host
end
```

**Cuando rompió:** Sprint del Trono 2026-06-12 — yo asumía MP por un log y el user estaba en SP. Igual fallaba porque la separación de VMs aplica en ambos modos.

---

## 🔥 8. IsoThumpable en MP no replica visual automáticamente

**Síntoma:** Server-side crea el IsoThumpable, los clientes lo "sienten" (colisión, pueden atacarlo), pero **no lo ven** hasta recargar el chunk.

**Causa:** En MP los IsoThumpable creados por script no disparan el broadcast visual estándar.

**Fix candidato (pendiente confirmar):**
- `syncIsoObject(obj, true, nil)` después del setSprite
- `transmitCompleteItemToServer`
- `transmitUpdatedSprite`
- `transmitAddObjectToSquare`

**Estado:** Pendiente investigación más profunda. En SP no aplica (el visual fantasma del bug 3 era por sprite inexistente, no por sync). Trackeado en `next_steps.md`.

---

## 🔥 9. Sprints "no funciona" → primero diagnosticar ñ + sync + sprite

Antes de bucear en lógica compleja cuando algo del mod no funciona, **chequear en este orden**:

1. ¿Hay errores en consola al cargar (Errors window)? → probablemente ñ/sintaxis
2. ¿El archivo editado está sincronizado con `Zomboid/mods/Holdoor/`? → `md5sum`
3. ¿Existe `Workshop/.../Holdoor/42/`? → BORRAR, es la carpeta fantasma
4. ¿El sprite usado pasa por `spriteExiste()`? → si no, agregar a la lista de candidatos

90% de los "no funciona" del mod hasta ahora fueron uno de estos 4.

---

**Última actualización:** 2026-06-12
