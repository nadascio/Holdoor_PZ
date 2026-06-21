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

**Importante:** En **comentarios y strings de código la `ñ` es segura PARA EL PARSER** — Lua acepta UTF-8 ahí. Solo rompe en identificadores.

**PERO: el FONT de PZ B42 no renderiza UTF-8 multi-byte en labels/drawText** — los acentos y ñ se muestran como `?` en la pantalla del juego. **Cualquier string que vaya a UI (catálogo de tienda, nombres de items, labels) debe ser ASCII puro.** Detectado de nuevo 2026-06-15 con "Café del Norte" → "Caf?" y "Vino del Otoño" → "Vino del Oto?o" al agregar Boosters/Lujos.

Regla práctica: al agregar items al catálogo o cualquier label nuevo, correr:
```bash
grep -nE 'nombre="[^"]*[áéíóúñÁÉÍÓÚÑ]|desc="[^"]*[áéíóúñÁÉÍÓÚÑ]' "media/lua/shared/HoldoorShopCatalog.lua"
```
Tiene que devolver vacío.

**Cómo detectarlo:**
```bash
grep -n '[ñáéíóúÑÁÉÍÓÚ]' archivo.lua
```
Después chequear si están dentro de strings/comments (`--`, `"..."`, `'...'`, `[[...]]`) o son identificadores. Si es identificador → rename obligado.

**Cuando rompió:** 2026-06-12. La función `_aplicarDañoBoost` rompía todo el server lua, lo que hacía que **el mod entero no funcionara** (oleada no arrancaba, Trono no spawneaba, prints no aparecían).

---

## 🔥 2. La subcarpeta `42/` del Workshop es la ÚNICA que PZ carga (confirmado empíricamente 2026-06-13)

**Verificación empírica:** Agregamos un botón "TEST UBICACION" al panel del mod con 4 valores distintos en las 4 copias del filesystem. Resultado al apretarlo: `[HOLDOOR] Mod cargado desde: WORKSHOP 42 (overlay B42)`.

**Esto significa:** de las 4 ubicaciones, PZ usa una sola: `Zomboid/Workshop/Holdoor/Contents/mods/Holdoor/42/`. Las otras 3 son irrelevantes a nivel runtime.

**Por qué pasa esto:**

- El mod está **publicado en Steam Workshop** y suscripto en esta máquina.
- Steam descarga la versión publicada al folder del Workshop.
- PZ B42 dentro del Workshop prioriza la subcarpeta versionada `42/` sobre `media/` raíz (mecanismo de soporte dual B41/B42).
- PZ **no usa** `Zomboid/mods/Holdoor/` cuando hay una versión del Workshop activa para el mismo mod ID.

**El bug del 2026-06-12** (perdimos toda la sesión a esto):

Asumí que tener 4 copias era duplicación a limpiar y borré la `42/`. PZ perdió la única ubicación que cargaba y cayó al `Workshop/media/` que tenía archivos del commit inicial (sin Trono, sin F10). Todo el laburo "desapareció".

**Implicancia: la `42/` es la fuente de la verdad RUNTIME**, aunque el source of truth EDITORIAL siga siendo `Documents/Holdoor_PZ/` (git).

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

---

## 🔥 10. APIs de B42 con firmas que NO matchean la documentación pre-B42

**Síntoma:** `java.lang.RuntimeException: No implementation found for function: <X>(args...)` o `expected 4 arguments, got 5`.

**Causa:** Entre B41 y B42 cambiaron varias firmas de funciones. Tutoriales y docs viejas del Internet citan la firma B41 que ya no existe.

**Firmas confirmadas que SÍ funcionan en B42 (2026-06-13):**

| API | Firma B42 confirmada | Firma B41 que NO anda |
|---|---|---|
| `IsoUtils.XToScreenExact(x, y, z, ofs)` | **4 args** | NO usa 5 args con `(x, y, z, 0, 0)` |
| `IsoUtils.YToScreenExact(x, y, z, ofs)` | **4 args** | Igual |
| `IsoThumpable.new(cell, sq, sprite, n, cfg)` | **5 args con `cell` PRIMERO** | NO usa `(sq, sprite, n, cfg)` (4 args) |
| `self:drawTextureScaled(tex, x, y, w, h, a)` | **6 args** (last = alpha) | Funciona en ISUIElement |
| `getRenderer():render(tex, x, y, w, h, r, g, b, a)` | NO está implementado en B42 (9 args falla) | — |
| `self:drawTextureScaledColor(tex, x, y, w, h, r, g, b, a)` | NO está implementado con 9 args | — |

**Estrategia defensiva al usar APIs de PZ:**
1. **Wrappear en `pcall`** todas las llamadas Java desde Lua. Si una API falla, `pcall` evita que el mod entero crashee.
2. **Fallbacks múltiples**: si una firma no funciona, probar otra variante. Ej: primero `drawTextureScaled`, después `drawTexture`.
3. **Flag de "deshabilitado"** después de N fallos consecutivos para evitar spammear el error log cada frame.
4. **Diagnóstico antes de codear "para producción"**: probar la API en aislado con `print()` de los args antes de meterla en código crítico.

**Cuando rompió:** 2026-06-13 al implementar el overlay PNG del Trono. Tuve que iterar 3 veces hasta encontrar la firma correcta.

---

## 🔥 11. Sprites INDOOR de B42 no renderizan al aire libre

**Síntoma:** Plantás un `IsoThumpable` con un sprite indoor (couches, chairs, beds, etc.) en un tile abierto del campo y queda **invisible** (pero ocupa el tile, los zombis lo perciben como bloqueo).

**Causa:** Los sprites con namespace `furniture_seating_indoor_*`, `furniture_storage_indoor_*`, etc. están diseñados para renderizar **dentro de un `IsoRoom`** (habitación con paredes construidas). Al ponerlos al aire libre, PZ los esconde o no los dibuja.

**Sprites que SÍ funcionan al aire libre:**
- `furniture_seating_outdoor_*` (sillas/bancos outdoor)
- `furniture_outdoor_*`
- `crafted_*` (items crafteados a mano)
- `constructedobjects_*` (sandbags, barricadas)
- `carpentry_*` (paredes/objetos de carpintería)
- `industry_*`, `industry_railroad_*`
- `fencing_*` (cercas)
- `lighting_outdoor_*`

**Cuando rompió:** 2026-06-12 al armar la galería de sprites para elegir el Trono. La lista inicial incluía indoor, ninguno se veía. Filtramos a solo outdoor y funcionó todo.

---

## 🔥 12. Para visuales custom: overlay UI > sprite custom (en costo)

**Si el sprite vanilla no alcanza:**
- **Camino fácil (~1h)**: PNG overlay con `ISUIElement` + `drawTextureScaled`. Limitación: no se integra al z-order del mundo, hay que hackear con transparencia por proximidad.
- **Camino medio (~3-5h)**: editar/modificar la PNG existente para que se integre mejor (sombras, recorte). Requiere skill básico de GIMP/Photoshop.
- **Camino caro (~5-8h + Fiverr $30-50)**: sprite custom iso real con TileZed + pipeline `.pack` + registro como sprite nuevo.

**Lección de la sesión:** el camino fácil funciona muy bien para la mayoría de casos. Solo escalar a iso custom si el mod va a publicarse en serio y se vende como producto pulido. Para uso personal/co-op casual, el overlay PNG alcanza.

---

## 🔥 13. Items de Base que existen en B41 pero NO en B42 (sweep 2026-06-13)

**Síntoma:** Compras un item de la tienda, mensaje en consola `Item: can't find Base.XYZ`, el item no aparece en el inventario pero la moneda se descuenta.

**Items conocidos que NO existen en B42:**
- `Base.FirstAidKit` → reemplazar por package `{Base.Bandage, Base.Antibiotics, Base.Pills}`
- `Base.WaterBottleFull` → usar `Base.WineBottle` o sin agua
- `Base.Alcohol` → usar `Base.AlcoholedCottonBalls` o `Base.AlcoholBandage`
- `Base.Hat_ArmyHelmet` → usar `Base.Hat_Hardhat`
- `Base.Vest_BulletKevlar` → usar `Base.Vest_HighVis_Blue` u otro
- `Base.Pop` → usar otra bebida (`Base.WineBottle`)

**Items NUEVOS y útiles de B42 médico:**
- `Base.AlcoholBandage` — Venda Esterilizada (mejor que Bandage)
- `Base.AlcoholedCottonBalls` — Algodón con Alcohol
- `Base.AlcoholRippedSheets` — Tela Esterilizada
- `Base.AlcoholWipes` — Toallitas con Alcohol

**Diagnóstico:**
Usar el **"Buscador de objetos"** del debug menu de PZ (Items List) para verificar si un item ID existe en este build. Filtrar por nombre o categoría (Medical, Weapon, Food, etc.).

**Cuando rompió:** 2026-06-13 al expandir el catálogo de la tienda. Items que asumimos que existían no estaban en B42.

---

## 🔥 14. APIs de player/traits/stats que cambiaron de B41 a B42

**Síntoma:** Acción de tienda (`trait`, `cura_trait`, `restore`, `cure_bite`) falla silenciosamente o tira error de Lua. La moneda se descuenta pero el efecto no se aplica.

**APIs que cambiaron en B42:**

| Función B41 | Estado en B42 | Workaround |
|---|---|---|
| `player:getTraits():add(name)` | Puede fallar | Cascada: probar `getDescriptor():getTraits():add()` primero |
| `player:getTraits():contains(name)` | NO existe en B42 | Usar `player:HasTrait(name)` |
| `Perks.FromString("Strength")` | Devuelve nil para algunos perks | Fallback: `Perks[name]` |
| `stats:setHunger(0)` | Puede requerir `setHunger(0.0)` o `getNutrition():setCalories()` | Cascada de pcall |
| `bd:isInfected()` | Case sensitive cambió | Probar `IsInfected()`, `bd:bitten()`, `bd:IsBitten()` |
| `part:bitten()` | Idem | Probar variantes con case distinto |

**Estrategia defensiva al usar APIs de PZ:**
1. **Cascada con pcall**: probar la API más común primero, fallback a variantes.
2. **Flag "valido_check"**: si NINGUNA variante de la validación funciona, dejar pasar el efecto. Mejor que bloquear todo por error de check.
3. **Log de debug**: agregar `print()` paso a paso para diagnosticar en qué step falla la API.

**Cuando rompió:** 2026-06-13 al implementar Rasgos Heroicos + Milagros del Maestre + Festín de Invernalia.

---

## 🔥 15. ISUIElement debe sobreescribir TODOS los handlers de mouse (incluido onRightMouseDown)

**Síntoma:** Cuando tu mod tiene un UIElement fullscreen invisible activo (overlay del Trono, overlay del marker de base, etc.), el **click derecho del mundo deja de funcionar**. Las acciones contextuales del juego (Destruir / Sentarse / Ir a / etc.) no responden.

**Causa:** `ISUIElement` por default tiene TODOS los handlers de mouse devolviendo **true** (consume el evento). Si tu overlay solo overridea `onMouseDown` y `onMouseUp` pero NO `onRightMouseDown`/`onRightMouseUp`, el click derecho llega a tu UI, se consume, y el juego nunca lo recibe.

**Solución obligatoria** en CUALQUIER UIElement invisible fullscreen del mod:
```lua
function MiOverlay:onMouseDown(x, y)        return false end
function MiOverlay:onMouseUp(x, y)          return false end
function MiOverlay:onMouseMove(dx, dy)      return false end
function MiOverlay:onMouseMoveOutside(dx,dy) return false end
function MiOverlay:onMouseDownOutside(x,y)  return false end
function MiOverlay:onMouseUpOutside(x,y)    return false end
function MiOverlay:onRightMouseDown(x, y)   return false end
function MiOverlay:onRightMouseUp(x, y)     return false end
function MiOverlay:onMouseWheel(del)        return false end
function MiOverlay:isMouseOver()            return false end
```

**Cuando rompió:** 2026-06-13. El `HoldoorOverlayUI` (el del Trono PNG) tenía solo 3 handlers overrideados. Le faltaban los del right click → bug del click derecho que persiguió al user durante varias sesiones.

---

## 🔥 16. API de Traits B42 — completamente distinta a B41 + namespace cliente-only

**Síntoma:** todas las APIs viejas (`TraitFactory.getTrait`, `player:addStringTrait`, `player:addTrait`, `player:getTraits():add`) son `nil` y crashean. Errores típicos:
```
attempted index: getTrait of non-table: null   ← TraitFactory es nil
Object tried to call nil in pcall              ← addStringTrait/addTrait/etc
expected argument of type CharacterTrait, got String  ← :add() con string
```

**Causa:** B42 deprecó toda la API B41. La nueva:
- Vive en namespace **`CharacterTrait`** (no `TraitFactory`), accesible **solo cliente-side**.
- Métodos del player: `getCharacterTraits()` → `:add(enum)` / `:remove(enum)` / `:getKnownTraits()`.
- Argumentos esperan **objeto `CharacterTrait`**, no string.

**Fix confirmado (`HoldoorClient.lua:aplicarTraitLocal`):**
```lua
local enum = CharacterTrait[traitIdUpperSnake]   -- "STRONG", "OUT_OF_SHAPE"
if enum then
    player:getCharacterTraits():add(enum)
    player:modifyTraitXPBoost(enum, false)
    SyncXp(player)
end
```

**Quitar:** `:remove(enum)` + `modifyTraitXPBoost(enum, true)`. **Verificar:** `getKnownTraits():contains(enum)` (fallback a `HasTrait`/`hasTrait`).

**Server → cliente:** namespace `CharacterTrait` NO existe server-side → toda la lógica de traits se delega al cliente vía `sendServerCommand(jugador, MODULE, "aplicarTrait", { trait = id })`.

**IDs reales B42** (`media/scripts/generated/characters/character_traits.txt`): formato `base:nombre` minúscula. Mapeo enum:
- `base:strong` → `CharacterTrait.STRONG`
- `base:out of shape` → `CharacterTrait.OUT_OF_SHAPE`
- `base:irongut` → `CharacterTrait.IRON_GUT`
- `base:eagleeyed` → `CharacterTrait.EAGLE_EYED`
- `base:thinskinned` → `CharacterTrait.THIN_SKINNED`
- `base:nightvision` → `CharacterTrait.NIGHT_VISION`

Estrategia: usar UPPERCASE_SNAKE en el catálogo (`accion={tipo="trait", trait="STRONG"}`) y resolver con `CharacterTrait[id]` en cliente.

**Cuando rompió:** 2026-06-14/15 (sesión completa). Cinco intentos con APIs B41 antes de leer vanilla y descubrir el patrón nuevo.

**Refs vanilla:** `client/ISUI/PlayerStats/ISPlayerStatsUI.lua:594` (add), `:669` (remove), `server/XpSystem/XpUpdate.lua:209+` (uso real).

---

## 🔥 17. kahlua: `type(obj.method)` devuelve `"nil"` aunque el método exista

**Síntoma:** `if type(obj.method) == "function" then obj:method() end` SIEMPRE entra al else, aunque la llamada directa funcione.

**Causa:** los métodos Java de PZ se exponen via **metatable** del userdata, NO como fields directos. `obj.method` devuelve nil en lookup directa; `obj:method()` resuelve via metatable y funciona.

**Regla:** NUNCA usar `type(obj.method) == "function"` para gatear llamadas a métodos Java. Verificar el **namespace** (no el método):
```lua
-- ❌ MAL — type() da "nil" siempre para métodos Java
if type(p.addStringTrait) == "function" then p:addStringTrait("Strong") end

-- ✅ BIEN — verificar namespace
if CharacterTrait then
    local enum = CharacterTrait["STRONG"]
    if enum then p:getCharacterTraits():add(enum) end
end
```

**Cuando rompió:** 2026-06-15. Cinco APIs de traits chequeadas con `type()` daban todas nil, lo que escondió que el problema real era el namespace `CharacterTrait` faltante.

---

## 🔥 18. kahlua: `pcall` NO atrapa "Object tried to call nil" ni "attempted index nil"

**Síntoma:** envolver llamada peligrosa en `pcall` y ver igual stack trace completo en consola.

**Causa:** kahlua tiene implementación parcial de `pcall`. Escapan:
- `Object tried to call nil in pcall` (invocar field nil como función)
- `attempted index: X of non-table: null` (indexar nil)

**Implicancia:** verificar previamente que namespace/método existe ANTES del pcall:
```lua
-- ❌ MAL — pcall NO atrapa
pcall(function() TraitFactory.getTrait("Strong") end)   -- crashea igual si TraitFactory es nil

-- ✅ BIEN — guard explícito
if TraitFactory and TraitFactory.getTrait then
    pcall(function() TraitFactory.getTrait("Strong") end)
end
```

**Cuando rompió:** 2026-06-15. Motor de traits tenía 5 APIs en cascada cada una en `pcall`. Todas fallaban con errores no-atrapados, llenaban el log y el usuario veía errores en pantalla.

---

## 🔥 19. Stats del player en B42 — usar `getStats():set(CharacterStat.X, val)`, NO setters individuales

**Síntoma:** llamar `stats:setFatigue(0.0)` (o `setHunger`, `setEndurance`, `setStress`, etc.) tira `Object tried to call nil in pcall` y kahlua NO lo atrapa (escapa al log).

**Causa:** B42 deprecó TODOS los setters individuales de stats. La nueva API unificada usa un enum `CharacterStat`:

```lua
-- ❌ B41 / antiguo — NO EXISTE en B42
stats:setFatigue(0.0)
stats:setHunger(0.0)
stats:setEndurance(1.0)

-- ✅ B42 — confirmado en media/lua/shared/Foraging/forageSystem.lua
stats:set(CharacterStat.FATIGUE, 0.0)
stats:set(CharacterStat.HUNGER, 0.0)
stats:set(CharacterStat.ENDURANCE, 1.0)
```

**Enums disponibles** (extraídos de vanilla con grep):
- Vitales: `HUNGER`, `THIRST`, `FATIGUE`, `ENDURANCE`, `SICKNESS`, `WETNESS`, `TEMPERATURE`
- Mentales: `STRESS`, `PANIC`, `BOREDOM`, `UNHAPPINESS`, `ANGER`, `SANITY`, `MORALE`, `IDLENESS`, `DISCOMFORT`
- Físicos: `PAIN`, `POISON`, `INTOXICATION`, `FOOD_SICKNESS`, `NICOTINE_WITHDRAWAL`
- Zombi: `ZOMBIE_FEVER`, `ZOMBIE_INFECTION`
- Otro: `FITNESS`

**Trampa de naming**: la API B42 usa `UNHAPPINESS` (con I), NO `UNHAPPYNESS` (con Y) — los métodos viejos de B41 tenían el typo histórico de PZ.

**Aliases que pasamos al motor `restore` del mod** (mapeo nombre amigable → enum):
- `hunger` → `HUNGER` (val 0.0)
- `endurance` → `ENDURANCE` (val 1.0 = max)
- `drunk` → `INTOXICATION` (val 0.0)
- `unhappy` → `UNHAPPINESS` (val 0.0)
- `pain` → `PAIN` (val 0.0, NO `setPainReduction` que era B41)
- resto → enum del mismo nombre, val 0.0

**Cuando rompió:** 2026-06-15. Boosters NO funcionaban (ninguno) porque todos pasaban por `setFatigue` que era nil. El Festín de Invernalia probablemente tampoco funcionó nunca del todo (no crasheaba pero solo afectaba algún stat aislado).

**Refs vanilla:**
- `media/lua/shared/Foraging/forageSystem.lua` — uso real con `CharacterStat.ENDURANCE` y `.FATIGUE`.
- Lista completa de enums: `grep -rhE "CharacterStat\.[A-Z_]+" media/lua/ | sort -u`.

---

## 🔥 20. ISChat hook B42: `onCommandEntered`, NO `sendCurrentInputText`

**Síntoma:** el comando `/holdoor` en chat MP llega al server crudo y PZ responde "Unknown command holdoor". El override del chat nunca se instala.

**Causa:** B42 renombró el método principal de ISChat:
- B41: `ISChat:sendCurrentInputText()`
- B42: `ISChat:onCommandEntered()` (confirmado en `media/lua/client/Chat/ISChat.lua:465`)

El hook viejo tenía `if not ISChat.sendCurrentInputText then return end` → salía temprano sin instalar nada.

**Fix:**
```lua
local _orig = ISChat.onCommandEntered
function ISChat:onCommandEntered()
    local text = ISChat.instance and ISChat.instance.textEntry and
                 ISChat.instance.textEntry:getText()
    if text and string.lower(text):match("^/holdoor") then
        ISChat.instance.textEntry:setText("")
        ISChat.instance:unfocus()
        if HoldoorClient.esAdmin() then HoldoorUI.abrir() end
        return  -- corta el flujo original
    end
    _orig(self)
end
```

**Trampa adicional — timing en MP:** en MP `ISChat` puede NO estar cargado al momento de `OnGameStart`. Si la primera ejecución de `instalarComandoChat()` falla, hay que **reintentarlo con `Events.OnTick`** hasta que esté disponible (cada ~1s). Una vez instalado, el listener se auto-remueve.

**Cuando rompió:** 2026-06-15. En MP el comando `/holdoor` no abría el panel. El bug existía silenciosamente desde la migración a B42 — en SP no se notaba porque ahí se abre con F10, no con `/holdoor`.

---

## 🔥 21. Paneles fullscreen rompen hover del inventario — `setWantMouseEvents(false)` es la API real, no los overrides Lua

**Síntoma:** crear un ISPanel fullscreen (`ISPanel.new(self, 0, 0, sw, sh)`) bloquea el hover del inventario vanilla — el inventario superior no se expande cuando pasás el cursor. Otras UIs vanilla también tienen comportamiento raro.

**Trampa #1:** parece que los overrides de mouse handlers en Lua deberían resolverlo:
```lua
function MyPanel:isMouseOver()       return false end
function MyPanel:onMouseDown(x, y)   return false end
function MyPanel:onMouseUp(x, y)     return false end
-- ... etc
```
**Esto NO funciona.** Los handlers Lua son cosméticos. El motor Java decide capturar eventos según el flag `consumeMouseEvents` del javaObject, NO según lo que devuelvan los handlers Lua.

**Causa raíz:** en `ISUIElement.lua:1998` el constructor pone `o.wantMouseEvents = true` por DEFAULT. Después en `instantiate` se llama `javaObject:setConsumeMouseEvents(self.wantMouseEvents)`. Eso le dice al motor Java "este panel consume mouse events" — y empieza a interceptar todo en su bounding box, sin importar los overrides Lua.

**Fix real:**
```lua
function MyPanel:initialise()
    ISPanel.initialise(self)
    pcall(function() self:setWantMouseEvents(false) end)
end
```

Esto setea el flag Java correctamente. Después el motor permite que los eventos pasen al panel debajo (inventario, toolbar, etc.).

**Aplica a:** TODO panel fullscreen que sea decorativo / informativo (overlays, anuncios, toasts, radar markers). NO aplica a paneles con botones interactivos (como el HoldoorHUD que tiene TIENDA/Enviar monedas) — esos SÍ necesitan capturar eventos.

**Cuando rompió:** 2026-06-15. Tras horas de diagnóstico binary-search apagando paneles uno por uno. La causa parecía ser overrides faltantes (gotcha #15), pero esos solo mitigan parcialmente. La fix real es esta y resuelve también de raíz el bug del click derecho del Trono de gotcha #15.

**Refs vanilla:**
- `media/lua/client/ISUI/ISUIElement.lua:1837` — `setWantMouseEvents(want)` definición.
- `media/lua/client/ISUI/ISUIElement.lua:1004` — donde se aplica al instantiate.
- `media/lua/client/ISUI/ISUIElement.lua:1998` — el default `wantMouseEvents=true`.

---

## 🔥 22. En MP, NUNCA usar `zombie:removeFromWorld()` — usar `zombie:setHealth(0)`

**Síntoma:** zombies que "deberían eliminarse" (limpiar zona, end of wave, detener oleadas) **desaparecen del server** pero los clientes los siguen viendo, o "reaparecen" instantáneamente al re-sincronizar el chunk. Comportamiento desastroso visualmente en MP.

**Causa:** `removeFromWorld()` saca el `IsoZombie` del cell del server pero NO triggerea el flow de sincronización con clientes. En MP cada cliente tiene su propia copia del zombie y el motor no la limpia automáticamente solo porque el server lo borró.

**Fix:** usar la API real de muerte:
```lua
pcall(function() z:setHealth(0.0) end)
```

Esto pasa por el flow normal del motor: HP llega a 0 → motor marca el zombie como muerto → cadaver cae al suelo → todos los clientes ven la muerte natural sincronizada. Cero fantasmas.

**Aplica a:**
- `_limpiarZona()` después de oleada / detener
- Cualquier "kill all zombies near base"
- Cualquier "clear arena"

**NO aplica a:**
- Piezas del Trono (IsoThumpable) — esas SÍ se eliminan con `removeFromWorld()` porque no son zombies y sí queremos que desaparezcan instantáneamente.

**Cuando rompió:** 2026-06-15. Bug visible en MP test del amigo del user. En SP no se notaba porque server y cliente comparten estado, no hay desincronización posible.

---

## 🔥 23. Detectar host de MP hosted en B42: `isCoopHost()`, NO `isServer()`

**Síntoma:** en MP **hosted** (partida iniciada con "Host" del menú principal), el HOST NO se detecta como admin. `getAccessLevel()` devuelve `"user"` para él. Tiene que correr `/setaccesslevel <user> admin` a mano.

**Confusión común — `isServer()` NO es la respuesta:**
- `isServer()` SOLO devuelve true en **dedicated server** (proceso aparte).
- En **hosted** (cliente + server integrado), `isServer()` devuelve **false** incluso en el host.

**API correcta — `isCoopHost()`:**

```lua
local ok, esHost = pcall(isCoopHost)
if ok and esHost then
    -- Es el host del MP hosted → admin de facto, sin importar AccessLevel
end
```

Refs vanilla B42:
- `media/lua/client/JoyPad/ISJoyPadListBox.lua:12`
- `media/lua/client/OptionScreens/InviteFriends.lua:338` (`self.isCoopHost = CoopServer:isRunning()`)
- `media/lua/client/OptionScreens/ConnectToServer.lua:271`

**Cascada robusta para detectar admin en cualquier contexto PZ B42:**

```lua
function esAdmin()
    if not isClient() then return true end       -- SP puro
    if isCoopHost() then return true end         -- host hosted ⭐
    if isServer() then return true end           -- dedicated server process
    local lvl = string.lower(tostring(player:getAccessLevel() or ""))
    if lvl == "admin" or lvl == "moderator" or lvl == "gm" or lvl == "overseer" then
        return true
    end
    return false
end
```

**Para que F10 funcione en MP:** el handler de tecla debe llamar a `esAdmin()` en vez de bloquear todo MP. Hosted host ahora puede usar F10 directamente, igual que en SP.

**Cuando rompió:** 2026-06-15. Nahuel hosting server local para test → log mostraba `AccessLevel detectado: 'user'` para el host. El primer intento de fix con `isServer()` tampoco funcionó. `isCoopHost()` resolvió.

---

## 🔥 24. `SandboxVars.ZombieConfig.Speed = 1` son SPRINTERS BUGGY — usar speed=2

**Síntoma:** zombies spawneados con `speed=1` pretendiendo "fast shamblers" (caminan rápido pero no corren) → en realidad spawnean como SPRINTERS que no pathean bien, se quedan o caminan errático.

**Causa:** los valores de `SandboxVars.ZombieConfig.Speed` en PZ B42:
- **1 = Sprinters** (corren — BUGGY en B42, pathfinding falla)
- **2 = Fast Shamblers** (caminan rápido, comportamiento estable)
- **3 = Slow Shamblers** (caminan lento)
- **4 = Random** (mix)

**Trampa común**: pensar que el orden es "1 = más rápido" es correcto, pero asumir que "1 = caminar rápido". NO — 1 son sprinters bug-prone.

**Para wave defense que necesita zombies AGRESIVOS pero ESTABLES:** usar **speed=2 (Fast Shamblers)**. Si querés sprinter como tier especial (corredores), ahí sí usar speed=3 puntualmente (con cuidado, pueden ser inconsistentes).

**Cuando rompió:** 2026-06-15. Sprint v0.6 — cambié de `speed=2` a `speed=1` pensando "más rápido" → zombies pasivos, no llegaban a la base. Nahuel reportó "tardan minutos en llegar". Revertido a `speed=2` resolvió.

**Refs vanilla:**
- `media/lua/server/HoldoorServer.lua` comentario viejo: `srSpeed = 3 -- capped: sin speed 4 (sprinters buggy)`. Speed 4 también es buggy. El valor "seguro" para fast shamblers es 2.

---

## 🔥 25. Eventos `OnZombieDead` son ASYNC — usar ventanas de tiempo, no contadores

**Síntoma:** querés ignorar las muertes de una "limpieza" (matar zombies cerca de la base) para que no cuenten como kills del player. Usás un contador `_zombiesIgnorarN = N`. Al matar zombies posteriores, sus kills se "absorben" por el contador → no suman.

**Causa:** `setHealth(0)` en zombies dispara `OnZombieDead` **asincrónicamente** — el motor procesa las muertes en los próximos ticks (no instantáneo). Si entre la limpieza y los siguientes kills del player pasa más tiempo del esperado, los eventos rezagados se confunden con kills nuevos.

**Approach que NO funciona** (contador):
```lua
estado._zombiesIgnorarN = estado._zombiesIgnorarN + N
-- En onZombieMuerto:
if estado._zombiesIgnorarN > 0 then
    estado._zombiesIgnorarN = estado._zombiesIgnorarN - 1
    return
end
```

**Approach que SÍ funciona** (ventana de tiempo):
```lua
estado._zombiesIgnorarHasta = os.time() + 2   -- ventana de 2s
-- En onZombieMuerto:
if os.time() < (estado._zombiesIgnorarHasta or 0) then return end
```

Los `setHealth(0)` async se procesan en <2s. Después, todo lo que muera cuenta como kill real.

**Aplica a:** `_limpiarZona`, cualquier "kill all near base", procesos masivos de muerte.

**Cuando rompió:** 2026-06-15. Sprint v0.6 — Nahuel mataba zombies durante oleada activa y NO sumaban bajas ni monedas. Cambiar de contador a ventana de tiempo resolvió.

---

## 🔥 26. `estado.modoId` vive en `estado.config.modoId` — NO en el root del estado

**Síntoma:** lees `estado.modoId` y siempre es `nil` → caés en fallback `"normal"` aunque el modo activo sea otro (Test, Difícil, etc).

**Causa:** en este mod, el modo se asigna a `estado.config.modoId` en `HoldoorServer.iniciar()`:
```lua
estado.config = {
    modoId = "test",  -- o el modo elegido
    ...
}
```
Pero NO se asigna a `estado.modoId` directamente. Cualquier código que lea `estado.modoId` cae al `nil`.

**Fix**: leer siempre con fallback explícito:
```lua
local modoId = (estado.config and estado.config.modoId) or "normal"
```

**Cuando rompió:** 2026-06-15. Sprint v0.6 — `_lanzarOleada` y `_rollDropsPorKill` leían `estado.modoId` → todos los modos se trataban como Normal (target=30 cuando debería ser 9 en Test). Bug crítico que afectaba balance.

---

## 🔥 27. Spawn perdigonado vs cúmulos — UX wave defense

**Aprendizaje no técnico pero crítico:** spawnear 1 zombi cada N segundos genera "hilera de zombies aislados" → wave defense pasivo y débil. El usuario reporta "no es amenazante, vienen como tontos".

**Patrón correcto:** spawnear **grupos (cúmulos) de 2-5 zombies juntos** en tiles adyacentes (cluster apretado, offset ±2). Comparten destino. Se sienten como horda real.

**Implementación clave:**
```lua
local tamCumulo = 2 + ZombRand(4)  -- 2-5 zombies
local spawnX, spawnY = encontrarTileExteriorValida(...)
local destX, destY = tileCercaTrono(...)
for i = 1, tamCumulo do
    local offX, offY = ZombRand(5) - 2, ZombRand(5) - 2
    HoldoorServer._spawnUno(spawnX + offX, spawnY + offY, ..., destX, destY, ...)
end
```

**Lección de diseño:** cuando hagas wave defense, NUNCA spawnees 1 zombi por tick. Siempre grupos. Visualmente y mecánicamente se siente 10x mejor.

**Cuando rompió:** 2026-06-15. Sprint v0.6 — primera versión usaba spawn 1-zombi-por-tick. Nahuel: "estás creándolos como perdigonados, tenés que crear bullicio de zombis". Cambio resolvió la sensación al instante.

---

## 🔥 28. `addSound()` solo no alcanza para aggro sostenido — combinar con `pathToLocation` explícito

**Síntoma:** ponés `addSound(nil, baseX, baseY, baseZ, radio=120, vol=200)` cada N segundos esperando que los zombies vengan a la base. **No funciona** — los zombies siguen pasivos, los del aggro pre-spawn van pero los lejanos no.

**Causa probable:** `addSound` en B42 atrae zombies que YA están en estado idle/exploration, pero no fuerza re-pathing en los que ya tienen un path. Y para los muy lejos del radio del sonido, simplemente no entra.

**Fix combinado (recuperado del modelo viejo):**

1. `addSound` cada 4s (atrae lejanos a la base).
2. `_reAggroZombies` cada 4s (itera IsoZombies cercanos y fuerza `pathToLocation(destX, destY, destZ)` hacia tile cerca del Trono).

Código:
```lua
function _reAggroZombies()
    local cell = getCell()
    for dx = -radio, radio do
        for dy = -radio, radio do
            local sq = cell:getGridSquare(bx + dx, by + dy, bz)
            for obj in sq:getMovingObjects() do
                if instanceof(obj, "IsoZombie") then
                    obj:pathToLocation(destX, destY, destZ)
                end
            end
        end
    end
end
```

**Cuando rompió:** 2026-06-15. Sprint v0.6 inicial usaba solo addSound → zombies pasivos. Combinar con pathToLocation explícito resolvió.

---

## 🚨🔥 29. **GOTCHA CRÍTICO B42** — `setWantMouseEvents(false)` NO basta: necesita ADEMÁS `setVisible(false)` o rect chico

**Síntoma:** un panel overlay con `setWantMouseEvents(false)` + handlers `onMouseX:return false` SIGUE bloqueando scroll/hover/tooltips del inventario vanilla detrás. El usuario no puede usar la rueda del mouse, ni ver el detalle de items al pasar el cursor encima.

**Causa raíz:** En B42 el dispatcher de mouse de Java usa el RECT del panel para hit-test, **ignorando el flag de `setWantMouseEvents` cuando `setVisible(true)`**. Los handlers Lua solo se llaman DESPUÉS de que Java decide rutar el evento al panel — si Java se lo queda, los handlers nunca ven el evento. La doc gotcha #21 (anterior) era incompleta.

**Reglas finales en B42:**

| Estado del panel | Hit-test del mouse | Bloquea UI detrás |
|---|---|---|
| `setVisible(false)` | Java lo ignora completamente | ❌ No bloquea |
| `setVisible(true)` + rect fullscreen | Java rutea el evento (aunque setWantMouseEvents=false) | ✅ **Bloquea** |
| `setVisible(true)` + rect chico (≤ ~200×200 alejado del cursor) | Hit-test solo en ese rect | ✅ Solo bloquea en su rect |

**Fix definitivo (3 patterns):**

1. **Overlays invisibles permanentes** (HoldoorOverlay, HoldoorAnnounce, HoldoorToast): arrancar con `inst:setVisible(false)` en su `crear()`. Solo `setVisible(true)` cuando vayan a renderizar algo concreto. Cuando termina el render, volver a `setVisible(false)`.

2. **Overlays que renderizan sobre objetos del mundo** (HoldoorOverlayTrono — dibuja sprite del trono): cada frame en `render()`, reposicionar el RECT del panel para que coincida EXACTAMENTE con el área del sprite (`self:setX/Y/Width/Height` a las coords calculadas). Cambiar drawTextureScaled/drawTexture a coordenadas RELATIVAS al panel (0,0). El rect chico solo bloquea su propia zona.

3. **Overlays con drag/botones** (HoldoorHUD lateral): el rect del HUD root NO es fullscreen → no rompe nada. Pero los sub-componentes (header draggable, botones) viven en sub-paneles `setWantMouseEvents=true` que sí capturan. El HUD root va `setWantMouseEvents=false`.

**Caso especial:** si el objeto al que se hace render OUT-OF-VIEWPORT (ej. el trono cuando te alejás), `IsoUtils.XToScreen` devuelve coordenadas fuera de pantalla, PZ las clampea al borde, y el sprite queda "pegado" al margen. Detectar fuera-de-viewport y achicar el panel a 1×1 en (0,0) sin dibujar:

```lua
local sw_view = getCore():getScreenWidth()
local sh_view = getCore():getScreenHeight()
if (rx + rw < 0) or (ry + rh < 0) or (rx > sw_view) or (ry > sh_view) then
    self:setX(0); self:setY(0); self:setWidth(1); self:setHeight(1)
    return  -- no dibujar
end
```

**Cuando rompió:** 2026-06-15. Sprint v0.6.1 (post v0.6) — bug crítico encontrado durante prueba del fix de items raros. Diagnóstico tomó múltiples iteraciones con teclas F11/F12/F9/F8/F7/F6 que ocultaban cada overlay individualmente para identificar al culpable. Plan A (handlers con guard `isMouseOver`) falló. Plan B (`setWantMouseEvents(false)` total en root) no alcanzó. Plan C (este — `setVisible(false)` + rect chico) resolvió. Esta gotcha **SUPERSEDE la #21**.

**Test rápido futuro:** si el inventario deja de scrollear/mostrar tooltips con el mod activo, hay un overlay nuestro con `setVisible(true)` y rect grande. Buscar overlays sin `setVisible(false)` por default en `crear()`.

---

## 🔥 30. `pcall` NO atrapa excepciones Java en B42 — usar `getScriptManager():FindItem()` para validar items

**Síntoma:** `pcall(function() InventoryItemFactory.CreateItem("Base.X") end)` con un item inválido tira excepción Java al log + "Break On Error" lo intercepta como crítico **aunque esté dentro del pcall**. El flow del Lua que estaba corriendo se rompe en seco.

**Causa:** `pcall` solo atrapa errores de Lua. Excepciones de Java desde APIs nativas (`InventoryItemFactory.CreateItem` con item inexistente lanza `RuntimeException`) escapan al pcall en B42. Esto rompió todo el flow de `onZombieMuerto` cuando un item raro inválido fue rolado: kills no se incrementaba, items no dropeaban, todo silencioso después del crash.

**Fix:** usar la API "safe" que devuelve `nil` en lugar de lanzar excepción:

```lua
-- ❌ NO HACER:
local itemValido = false
pcall(function()
    local test = InventoryItemFactory.CreateItem(def.item)  -- excepción Java escapa pcall
    itemValido = (test ~= nil)
end)

-- ✅ HACER:
local itemValido = false
local sm = getScriptManager and getScriptManager() or nil
if sm then
    local scr = sm:FindItem(def.item)  -- devuelve nil limpio si no existe
    itemValido = (scr ~= nil)
end
```

**Cuando rompió:** 2026-06-15. Sprint v0.6 — items inválidos como `Base.WaterBottleFull`, `Base.WineBottle`, `Base.Shotgun_Shells`, `Base.223Bullets`, `Base.Hat_Hardhat`, `Base.Vest_HighVis_Blue` no existen en B42 vanilla pero estaban en `itemDropPool`. Cuando un kill rolaba alguno → crash → flow muere → no más drops.

**Validación batch del pool:** botón TEST en panel admin que intenta darle al jugador 1 de cada item del pool con `inv:AddItem(itemName)` bajo pcall (este sí atrapa porque AddItem es más tolerante) y loguea OK/falla por item. Pool curado validado contra `media/scripts/generated/items/*.txt` del juego.

---

## 🔥 31. `HoldoorClient.chat()` dispara Toast internamente — usar `player:Say()` para diagnósticos

**Síntoma:** durante diagnóstico del bug del scroll del inventario, los propios mensajes de TEST (`HoldoorClient.chat("[TEST F11] OCULTO")`) disparaban Toast → Toast visible → Toast bloqueaba el inventario que intentábamos diagnosticar. Era un loop confuso: el reporte rompía el test.

**Causa:** `HoldoorClient.chat()` (línea 922 HoldoorClient.lua) además de `player:Say()` llama internamente a `HoldoorToast.mostrar()` si Toast existe.

**Fix:** para diagnósticos / TEST que NO deben disparar Toast, usar directamente:

```lua
local function diagSay(txt)
    local p
    pcall(function() p = getSpecificPlayer(0) end)
    if p then pcall(function() p:Say(txt) end) end
    print("[Holdoor][DIAG] " .. txt)  -- al console.txt
end
```

**Cuando rompió:** 2026-06-15. Sprint v0.6.1 diagnóstico del mouse passthrough.

---

## 🔥 32. Items "fantasma" en inventario sin notificación — auditar TODAS las vías de `_distribuirItems`

**Síntoma:** el jugador encuentra el inventario lleno de items "raros" sin haber recibido notificación de drop. Cree que es bug pero los items entran realmente al inventario.

**Causa:** `_distribuirItems(items)` se llama desde MÚLTIPLES funciones del server. Una de ellas (`_distribuirRecompensaOleada` línea 1262-1281 del HoldoorServer.lua) iteraba TODO el pool de items, roleaba chance por cada uno, y los entregaba — **sin llamar a `notificarTodos("dropKill", ...)`**. Por eso eran silenciosos.

Con un pool de 52 items y chances de rareza (40%/18%/6%/1.5%), entregaba ~14 items POR OLEADA en Normal. Todos silenciosos.

**Fix doble:**

1. **Notificación al cliente** del botín entregado en `oleadaCompletada` con la lista de items. Cliente agrupa por nombre y muestra "Botín: 2x Bandage, 1x Sword..." en chat + toast.
2. **Bajar las chances**: 40/18/6/1.5 → 10/5/2/0.5. Target: ~3-5 items/oleada en Normal.

**Regla:** cada vía de spawn de items al inventario del player debe tener su correspondiente `notificarTodos("dropKill", {...})` o equivalente en el `oleadaCompletada`. Auditar con `grep "AddItem\|_distribuirItems"` en el server.

**Cuando rompió:** 2026-06-15. Sprint v0.6 — bug detectado por el user reportando "tengo el inventario lleno y nunca me avisaste".

---

## 🔥 33. `IsoUtils.XToScreen` para objeto fuera del viewport → sprite queda "pegado" al borde

**Síntoma:** un overlay que dibuja un sprite siguiendo a un objeto del mundo (ej. `drawTextureScaled` en posición `IsoUtils.XToScreenExact(objX, objY, objZ)`) muestra el sprite **flotando en el borde de pantalla** cuando el objeto está fuera del viewport del jugador.

**Causa:** `IsoUtils.XToScreen` devuelve coordenadas en pixels de pantalla — no `nil` cuando el objeto está fuera del viewport, devuelve valores negativos o > screenWidth. Cuando esas coordenadas se usan en `self:setX/setY` del panel, PZ las clampea al viewport. El sprite se ve "pegado" al borde más cercano.

**Fix:** detectar fuera-de-viewport antes de setX/setY y achicar el panel a 1×1 en (0,0):

```lua
local sw_view = getCore():getScreenWidth()
local sh_view = getCore():getScreenHeight()
local rx = math.floor(drawX)
local ry = math.floor(drawY)
local rw = math.max(1, math.floor(W))
local rh = math.max(1, math.floor(H))
if (rx + rw < 0) or (ry + rh < 0) or (rx > sw_view) or (ry > sh_view) then
    self:setX(0); self:setY(0); self:setWidth(1); self:setHeight(1)
    return  -- no dibujar
end
self:setX(rx); self:setY(ry); self:setWidth(rw); self:setHeight(rh)
-- ahora drawTextureScaled con coords (0,0,rw,rh) relativas al panel
```

**Cuando rompió:** 2026-06-15. Sprint v0.6.1 — el sprite del Trono quedaba flotando en la esquina sup derecha cuando el player se alejaba del trono real.

---

## 🔥 34. Diagnóstico de UIs que bloquean mouse — patrón de F-keys de toggle individual

**Cuando estás cazando qué overlay nuestro está bloqueando input del juego vanilla**, el patrón eficiente es:

1. Una tecla (F11) toggle TODOS los UIs del mod (`removeFromUIManager` de cada instancia). Si ocultando todos funciona → es uno de los nuestros.
2. Una tecla por overlay individual (F12, F9, F8, F7, F6...) toggle solo ese.
3. Probar de a uno. El culpable es el que al ocultarlo SOLO arregla el problema, o la combinación necesaria.

**Trampa que cazamos en sprint v0.6.1:** un overlay (HoldoorToast) parecía culpable cuando NO lo era — los mensajes de chat del propio diagnóstico (`[TEST F11] OCULTO`) disparaban el Toast (ver gotcha #31). Cambiar diagnósticos a `player:Say()` evita falsos positivos.

**Implementación de las funciones toggle:** usar `removeFromUIManager` (no `setVisible(false)`) para sacar el rect del hit-test definitivamente durante el test. Aunque la gotcha #29 muestra que `setVisible(false)` también funciona, en diagnóstico es más limpio quitarlo del UIManager por completo.

---

## 🔥 63. Steam Workshop `result=8 (k_EResultInvalidParam)` — causas confirmadas (em-dashes, descripción larga, archivos basura)

**Síntoma:** PZ "Update Mod" tira:
```
start update of existing item ID=3743052644
success requesting Steam to update the item
there is no way to stop the update once it has started
failed to update workshop item, result=8
finished
```

**`result=8`** corresponde a `k_EResultInvalidParam` de Steam Workshop API. Steam rechaza el upload por algún parámetro inválido. Las **3 causas confirmadas empíricamente** en este mod:

### Causa 1: caracteres no-ASCII en `workshop.txt`

Steam rechaza la mayoría de tipográficos Unicode. **Confirmado problemático:**
- `—` (em-dash, U+2014)
- `–` (en-dash, U+2013)
- Emojis (⚔️ 🆕 ⚡ 📍 💾 ━) — ya documentado en gotcha #35.
- Otros que pueden romper: `'` `'` `"` `"` `…`

**Verificación**: `LC_ALL=C grep '[^ -~	]' workshop.txt` debe devolver vacío. Si encuentra match → ese byte es el problema.

**Fix**: reemplazar con ASCII equivalente (`—` → `-`, `…` → `...`, etc).

### Causa 2: descripción del workshop.txt demasiado larga

**Confirmado 2026-06-21**: Steam rechaza si el largo total de las líneas `description=...` supera ~8000 caracteres.

**Cómo medir:**
```bash
grep "^description" workshop.txt | wc -c
```

**Fix**: acortar la descripción. Eliminar bloques de novedades de versiones antiguas (ej: cuando saques v0.9, podés borrar el bloque "NUEVO EN v0.7" porque ya no aporta a usuarios nuevos). Bloques de "NUEVO EN vX" deben ser breves: 1 párrafo o lista corta, no narrativas extensas.

**Histórico**: bloque que metí en v0.8.7 con 7 párrafos técnicos rompió el límite. Lo recorté a 1 párrafo + eliminé bloque "NOVEDADES v0.7" → bajó de 9662 → 7847 chars → Steam aceptó.

### Causa 3: archivos basura en el folder Workshop

**Confirmado 2026-06-16**: Steam parsea **todo** lo que vea en `C:/Users/nahue/Zomboid/Workshop/Holdoor/`. Si hay archivos que no espera, falla.

**Confirmados problemáticos:**
- `HoldoorServer.lua.tmp` (gotcha #35)
- `docs/` subfolder (gotcha #35)
- `workshop.txt.bak` (confirmado 2026-06-21)
- Cualquier otro `.bak`, `.swp`, `.swo` de editores

**Verificación pre-publish:**
```bash
ls "C:/Users/nahue/Zomboid/Workshop/Holdoor/"
```

Debe contener SOLO:
- `workshop.txt`
- `preview.png`
- `Contents/` (folder con mods/Holdoor/...)

**Fix**: borrar lo que no esté en esa lista.

### Protocolo pre-publish (checklist anti-result=8)

1. `LC_ALL=C grep '[^ -~	]' "C:/Users/nahue/Zomboid/Workshop/Holdoor/workshop.txt"` → debe devolver vacío.
2. `grep "^description" workshop.txt | wc -c` → debe ser **< 8000 caracteres**.
3. `ls C:/Users/nahue/Zomboid/Workshop/Holdoor/` → solo 3 entradas (workshop.txt, preview.png, Contents/).
4. `ls C:/Users/nahue/Zomboid/Workshop/Holdoor/Contents/mods/Holdoor/` → media/, mod.info, poster.png, 42/.
5. Si todos pasan → Update Mod en PZ debería aceptar (result=1).

Si después de los 5 checks sigue fallando → causa nueva, investigar más profundo (puede ser tags inválidos, preview.png corrupto, mod.info malformado, etc).

---

## 🔥 35. **PROTOCOLO RELEASE — Subir un update al Steam Workshop (paso a paso)**

**Síntoma (la cagada que casi paso 2026-06-16):** preparé todo (mod.info bumpeado, descripción nueva, código sincronizado) pero el Workshop seguía mostrando v0.5.1 después de "Update Mod" en PZ. Razón: actualicé el `workshop.txt` equivocado.

**LA REGLA DE ORO:** PZ Workshop uploader **lee de `C:/Users/nahue/Zomboid/Workshop/Holdoor/workshop.txt`** (NO del repo `Documents/Holdoor_PZ/workshop.txt`). El del repo es solo source para versionar; el del Zomboid es el que se usa cuando hacés Update Mod.

### Formato OBLIGATORIO del `workshop.txt` (PZ uploader)

NO acepta BBCode (`[h1]`, `[hr]`, etc). Usa formato propio plano:

```
version=1
id=<workshop_item_id>     ← NO CAMBIAR JAMÁS. Es el ID del item en Steam.
title=<titulo del item>    ← Sin versión hardcoded (ej. "Holdoor — Wave Defense GoT (Beta)").
description=<linea 1>
description=                ← líneas vacías = saltos de línea
description=<linea 2>
...
tags=Build 42;Multiplayer
visibility=public
```

Para separadores visuales usar caracteres unicode: `━━━━━━━━━━ SECCIÓN ━━━━━━━━━━`.

### Protocolo COMPLETO para subir un update — checklist

#### Fase A — Preparación (lo hace el dev / Claude)

1. **Verificar que el código del mod este sincronizado** en las 4 ubicaciones (Documents source + Zomboid/mods + Workshop/media + Workshop/42). Usar el script de sync del gotcha #2.
2. **Bumpear `modversion`** en `mod.info` (todas las 4 copias):
   - Documents/Holdoor_PZ/mod.info
   - Zomboid/mods/Holdoor/mod.info
   - Zomboid/Workshop/Holdoor/Contents/mods/Holdoor/mod.info
   - Zomboid/Workshop/Holdoor/Contents/mods/Holdoor/42/mod.info
3. **Actualizar `workshop.txt` en DOS lugares idénticos** (md5 debe coincidir):
   - **Crítico:** `C:/Users/nahue/Zomboid/Workshop/Holdoor/workshop.txt` — este es el que importa.
   - **Repo (para git):** `C:/Users/nahue/Documents/Holdoor_PZ/workshop.txt`.
4. **Actualizar la sección "NOVEDADES vX.Y.Z"** dentro del workshop.txt con los highlights del release.
5. **Crear `workshop_update_vX.Y.Z.txt`** en el repo con el changelog corto (para pegar en Change Notes durante el upload).
6. **Verificar md5** del workshop.txt en ambos lugares — debe ser idéntico.
7. **Verificar título** en workshop.txt: `Holdoor — Wave Defense GoT (Beta)` sin versión hardcoded.

#### Fase B — Upload (lo hace Nahuel desde PZ, NO se puede automatizar)

1. **Cerrar PZ si está abierto.** Volver a abrirlo limpio.
2. **Menú principal de PZ → Workshop → Mod Tools → Update Mod** (o Update Item, varía la versión de B42).
3. **Seleccionar Holdoor** en la lista.
4. **Click Update.** PZ va a leer el workshop.txt y los archivos del mod, empaquetarlos, y subirlos a Steam.
5. **Cuando aparezca el campo "Change Notes" / "What's New":** pegar el contenido de `workshop_update_vX.Y.Z.txt`.
6. **Confirmar el upload.**
7. **Esperar 1-2 minutos** y refrescar la página del Workshop en el navegador. Verificar:
   - Título actualizado (sin "v0.5.1" hardcoded)
   - Descripción nueva visible
   - "Actualizado [fecha de hoy]" en el panel derecho
   - "Tamaño" del mod cambió (si hubo cambios de código)

#### Fase C — Post-upload (cierre del release)

1. **Probar el mod desde Steam** — desuscribirse, suscribirse de nuevo, abrir PZ, verificar que carga la versión nueva.
2. **Commit + push al repo** (regla `feedback_no_push_auto`: solo cuando Nahuel da OK explícito):
   - Incluir: archivos modificados del mod + mod.info + workshop.txt + workshop_update_vX.Y.Z.txt + docs actualizados.
   - Tag git: `vX.Y.Z`.
   - Push.
3. **Actualizar `sprints_history.md`** con el sprint cerrado.

### Trampas conocidas (ya cazadas)

| Trampa | Consecuencia | Cómo evitar |
|---|---|---|
| Actualizar solo el workshop.txt del repo | Steam no muestra los cambios | Actualizar AMBOS (md5 idéntico) |
| Usar BBCode `[h1]`, `[hr]`, `[b]` | PZ uploader no los renderiza | Texto plano con barras unicode `━━━━` |
| Cambiar el campo `id=` | Crea un Workshop item NUEVO (perdés suscriptores) | NUNCA tocar el `id=` |
| Hardcodear versión en el `title=` | Hay que editarlo en cada release | Dejar solo `(Beta)`, sin número |
| Olvidar el `visibility=public` | Steam lo sube como private | Verificar al final del workshop.txt |
| Bumpear mod.info en una sola copia | Mismatch entre source y runtime | Sincronizar las 4 con el script del gotcha #2 |
| Saltar la verificación md5 | El upload sube info vieja | Siempre `md5sum` final antes de avisar "listo para subir" |

### Comandos de verificación (copiar y pegar al cerrar un release)

```bash
# 1) workshop.txt sincronizado entre repo y Zomboid:
md5sum "C:/Users/nahue/Documents/Holdoor_PZ/workshop.txt" \
       "C:/Users/nahue/Zomboid/Workshop/Holdoor/workshop.txt"

# 2) mod.info en las 4 ubicaciones:
md5sum "C:/Users/nahue/Documents/Holdoor_PZ/mod.info" \
       "C:/Users/nahue/Zomboid/mods/Holdoor/mod.info" \
       "C:/Users/nahue/Zomboid/Workshop/Holdoor/Contents/mods/Holdoor/mod.info" \
       "C:/Users/nahue/Zomboid/Workshop/Holdoor/Contents/mods/Holdoor/42/mod.info"

# 3) Confirmar versión:
grep modversion "C:/Users/nahue/Documents/Holdoor_PZ/mod.info"

# 4) Confirmar formato del workshop.txt:
head -5 "C:/Users/nahue/Zomboid/Workshop/Holdoor/workshop.txt"
tail -3 "C:/Users/nahue/Zomboid/Workshop/Holdoor/workshop.txt"
```

### Cuándo aplica este protocolo

Cada vez que se sube **cualquier cosa al Workshop**: release mayor (v0.X.0), patch (v0.X.Y), hotfix urgente. Siempre los mismos 3 fases A-B-C.

**Cuando rompió:** 2026-06-16. Sprint v0.6.0 release — actualicé solo el workshop.txt del repo creyendo que era el único. PZ uploader subía la descripción vieja porque leía del archivo en Zomboid. Nahuel detectó: en Steam seguía figurando "Beta v0.5.1" después del Update Mod. Fix inmediato: encontrar el archivo real en Zomboid/Workshop, reescribir con formato PZ uploader, sincronizar repo. Lockear protocolo para que no pase otra vez.

---

**Última actualización:** 2026-06-16 — Sprint v0.6.0 release flow lockeado (gotcha #35)

---

## 🚨🔥 36. **LOCKEADO PERMANENTE — `notificarTodos` SIEMPRE llama `HoldoorClient.onComandoServidor` directo PRIMERO**

**Lockeado el 2026-06-16 después de cagarla 3 VECES con el mismo bug.** No tocar este patrón. No "optimizar". No "limpiar". No quitar el call directo.

### La regla de oro

```lua
function HoldoorServer.notificarTodos(tipo, datos)
    -- PASO 1 OBLIGATORIO: call directo al cliente local. SIEMPRE primero.
    -- NO BORRAR. NO MOVER. NO "OPTIMIZAR".
    if type(HoldoorClient) == "table" and HoldoorClient.onComandoServidor then
        pcall(HoldoorClient.onComandoServidor, HoldoorConfig.MODULE, tipo, datos)
    end

    -- PASO 2: broadcast a clientes remotos via sendServerCommand (excluyendo host local)
    ...
end
```

### Por qué pasa el bug si lo sacás

En **MP hosted** (host + server en mismo proceso PZ):
- `sendServerCommand(host_local, ...)` **NO entrega al cliente local** (PZ no rutea loopback al mismo socket)
- `sendClientCommand(...)` es cliente→server, NO server→cliente (nomenclatura confusa de PZ B42)
- Resultado sin el call directo: el HUD del cliente del host queda **desincronizado** del estado real del server. Dice "[Inactivo]" mientras la oleada está corriendo a full

### Por qué pensé que podía sacar el call directo

3 veces tuve la "epifanía" de que el call directo era el problema, porque:
- Ejecuta en server-context Lua donde `InventoryItemFactory` es null
- Ejecuta en server-context donde `getSpecificPlayer(0)` puede ser raro
- Tira errors raros si los handlers del cliente intentan usar APIs cliente-only

3 veces lo saqué. 3 veces se rompió el HUD. 3 veces tuve que restaurar.

### Por qué AHORA está bien dejarlo

Los items y XP (que NECESITAN cliente-context para usar APIs cliente-only) ya **NO usan notificarTodos**:
- Items de tienda: `HoldoorClient.comprar` → `SendCommandToServer("/additem")` cliente-side directo
- Items drop por kill: `HoldoorServer._entregarItemsViaAdmin` → `sendServerCommand("ejecutarAddItem")` al host admin → cliente-side
- XP: `SendCommandToServer("/addxp")` cliente-side

`notificarTodos` ya solo lleva updates de HUD (estado oleada, kills, HP del Trono, monedas/materiales updates). Esos handlers **NO usan APIs cliente-only**, solo modifican labels de UI. Por eso ejecutar en server-context vía call directo es seguro.

### Tabla de "qué API usar"

| Caso | Server → Cliente | Funciona en MP hosted host local? |
|---|---|---|
| Notificar HUD update (label, fase, kills) | Call directo `HoldoorClient.onComandoServidor` | ✅ Único método que funciona |
| Entregar items en MP | `/additem` admin via `SendCommandToServer` (cliente) | ✅ Vanilla flow legítimo |
| Entregar XP en MP | `/addxp` admin via `SendCommandToServer` (cliente) | ✅ Vanilla flow legítimo |
| Aplicar Traits | `sendServerCommand("aplicarTrait")` + call directo fallback | ✅ Ya funcionaba en v0.5.1 |
| Broadcast genérico a remotos | `sendServerCommand(player, ...)` | ✅ Solo para clientes remotos, no host local |

### Test de regresión

Si en el futuro sospechás que el call directo está rompiendo algo (y querés sacarlo): **NO lo saques**. En su lugar:
1. Identificá QUÉ handler está rompiendo
2. Fixeá ese handler para que NO use APIs cliente-only cuando se ejecuta en server-context
3. O delegá la lógica problemática fuera de notificarTodos (como hicimos con items/XP)

**El call directo es la única vía de sync HUD a host local hosted en B42.** No hay alternativa.

**Cuándo rompió:** 2026-06-16. Sprint v0.6.1 — 3 veces en el mismo sprint. Cada vez que aparecía un nuevo bug (item fantasma, XP que se sobreescribe, comando que falla), pensaba que el call directo era el culpable. Era OTRO bug. El call directo es necesario. **Lockear para siempre.**

---

## 🚨🔥 37. **Entrega de items en MP — NUNCA usar `inv:AddItem()` desde server o cliente no-admin. SIEMPRE `/additem` admin via `SendCommandToServer`**

**Síntoma:** Le das un item al player (tienda, drop por kill, recompensa de oleada). El item APARECE en el inventario, pero:
- No se puede equipar (intentás equiparlo, la TimedAction cancela a 1/5 de progreso).
- No se puede usar (click derecho → "Usar" no hace nada).
- Si lo droppeás al piso, se queda ahí como item fantasma y al recogerlo de vuelta sigue inservible.
- En el log: nada particularmente raro. El item "existe" como objeto en memoria pero el server no lo reconoce.

**Causa raíz:** En MP, `InventoryItemFactory.CreateItem()` ejecutado en server-context (o en cliente que NO es el dueño del item) crea instancias **que no están sincronizadas con el flow vanilla de items**. El motor las trata como "fantasmas": existen en el `getInventory()` pero el server no las tiene en su tracking → cualquier acción que requiera confirmación server-side falla.

**Adicionalmente:** desde server-context Lua (`HoldoorServer.lua`), `InventoryItemFactory` puede ser directamente **null**. Aun con call directo a `HoldoorClient`, si la función fue invocada por server (cross-VM), el contexto Lua sigue siendo server.

**Fix DEFINITIVO** — usar comandos admin vanilla via `SendCommandToServer` ejecutado desde **cliente-context** del player que recibe el item:

```lua
-- HoldoorClient.lua - cliente-context (correcto)
function HoldoorClient.entregarItem(itemName)
    local me = getSpecificPlayer(0)
    if not me then return end
    local user = me:getUsername()
    local cmd = string.format('/additem "%s" "%s" 1', user, itemName)
    pcall(function() SendCommandToServer(cmd) end)
end
```

**Patrón completo (server cobra, cliente entrega):**

1. **Server**: cobra recursos (monedas/materiales). NO entrega item.
2. **Server**: en payload del `notificarTodos("oleadaCompletada"/"dropKill"/etc)`, incluir `items = {...}` + `target = username`.
3. **Cliente** (handler del comando): si `args.target == miUsuario`, ejecutar `/additem` via `SendCommandToServer`.

```lua
-- Server side (HoldoorServer.lua)
function HoldoorServer.ejecutarAccion(jugador, accion)
    -- ... cobrar costo ...
    -- NO HACER inv:AddItem o InventoryItemFactory.CreateItem aca
    return true  -- el cliente se encarga via comando admin
end

-- Cliente side (HoldoorClient.lua)
function HoldoorClient.comprar(accion)
    -- ... pedir al server cobrar ...
    if accion.tipo == "item" or accion.tipo == "package" then
        local items = obtenerItemsDe(accion)
        for _, itemName in ipairs(items) do
            local cmd = string.format('/additem "%s" "%s" 1', meUser, itemName)
            pcall(function() SendCommandToServer(cmd) end)
        end
    end
end
```

**Lo mismo aplica a XP** — usar `/addxp "user" Perk=N` via `SendCommandToServer`. `Perks` setter desde server crea XP que se "revierte" inmediatamente (mismo root cause).

```lua
local cmd = string.format('/addxp "%s" %s=%d', meUser, perk, amount)
pcall(function() SendCommandToServer(cmd) end)
```

**SP vs MP:** en SP `SendCommandToServer` funciona igual (PZ B42 usa el mismo flow vanilla con server local interno). El patrón es portable.

**Restricción:** `/additem` y `/addxp` **requieren accessLevel admin** del player que envía el comando. Esto resuelve para:
- SP (todos son admin)
- MP hosted host (es admin de facto — ver gotcha #38 para clientes remotos no-admin)

**Cuando rompió:** 2026-06-16. Sprint v0.6.1 — items de tienda/drops/recompensa todos se metían como "fantasmas" en MP. Detectado al equipar una katana comprada: la TimedAction cancela. Mismo bug aplicaba a XP de libros de skill. **Solución única y consistente: admin command via cliente-context.**

---

## 🚨🔥 38. **Clientes no-admin en MP: delegación cliente → server → host admin → `/additem`**

**Síntoma:** El patrón del gotcha #37 (`/additem` via cliente) NO funciona para clientes remotos que NO son admin. El comando se envía pero PZ lo rechaza con "permission denied" silenciosamente.

**Causa:** En MP hosted, solo el host (o admins explícitos) puede ejecutar comandos admin vanilla. Los clientes remotos comunes corren con `accessLevel="user"`.

**Fix con delegación al host:** el cliente no-admin pide al server que reenvíe el comando al host admin, que lo ejecuta a su nombre del player que recibe el item.

**Patrón completo en 3 hops:**

```lua
-- HOP 1: cliente NO-admin (HoldoorClient.lua)
function HoldoorClient.comprar(accion)
    if HoldoorClient.esAdmin() then
        -- soy admin, ejecuto directo (gotcha #37)
        SendCommandToServer(string.format('/additem "%s" "%s" 1', meUser, item))
    else
        -- no soy admin, delego al server
        sendClientCommand(HoldoorConfig.MODULE, "delegarAddItem", {
            target = meUser, items = { item },
        })
    end
end

-- HOP 2: server (HoldoorServer.lua) — recibe la delegación
function HoldoorServer.onClientCommand(module, command, jugador, args)
    if command == "delegarAddItem" then
        -- reenviar al host admin
        local host = HoldoorServer._buscarHostAdmin()
        if host then
            sendServerCommand(host, HoldoorConfig.MODULE, "ejecutarAddItem", args)
        end
    end
end

-- HOP 3: host admin (HoldoorClient.lua) — recibe y ejecuta
HoldoorClient.handlers.ejecutarAddItem = function(args)
    if not HoldoorClient.esAdmin() then return end  -- guard
    for _, item in ipairs(args.items or {}) do
        local cmd = string.format('/additem "%s" "%s" 1', args.target, item)
        pcall(function() SendCommandToServer(cmd) end)
    end
end
```

**Lo mismo para XP:** `delegarAddXp` → `ejecutarAddXp`.

**Trampa importante**: `sendServerCommand(host_local, ...)` **NO loopbackea al host hosted** (gotcha #36). Si el server quiere mandarle un comando al host de su propio proceso, hay que hacer call directo `pcall(HoldoorClient.onComandoServidor, ...)`. PERO si el host está delegando comandos a sí mismo, mejor cortocircuitar antes en HOP 1 (`esAdmin() → ejecutar directo`).

**Cuando rompió:** 2026-06-16. Sprint v0.6.1 — en testing con cliente remoto no-admin, items no llegaban aunque el server confirmara cobro. Implementación de delegación resolvió.

---

## 🚨🔥 39. **`_buscarHostAdmin()` necesita fallback — host hosted NO tiene `accessLevel="admin"` explícito**

**Síntoma:** El patrón del gotcha #38 falla en server **hosted** (no dedicated): `_buscarHostAdmin()` itera `getOnlinePlayers()` buscando `getAccessLevel() == "admin"` y NUNCA encuentra a nadie, aunque el host esté online.

**Causa:** El host de un MP hosted (partida iniciada con "Host" del menú principal) corre con `accessLevel="user"` o `""`. PZ lo trata como host vía `isCoopHost()` (gotcha #23) pero **NO le asigna AccessLevel admin formal**. Solo en dedicated server el primer admin tiene accessLevel="admin" explícito.

**Fix con 2-pass + fallback final:**

```lua
function HoldoorServer._buscarHostAdmin()
    local ok, players = pcall(getOnlinePlayers)
    if not ok or not players then return nil end
    local n
    pcall(function() n = players:size() end)
    if not n or n == 0 then return nil end

    -- PASS 1: buscar accessLevel admin/moderator/gm/overseer explícito
    for i = 0, n - 1 do
        local p = players:get(i)
        if p then
            local lvl = string.lower(tostring(p:getAccessLevel() or ""))
            if lvl == "admin" or lvl == "moderator" or lvl == "gm" or lvl == "overseer" then
                return p
            end
        end
    end

    -- PASS 2 (FALLBACK): host hosted NO tiene admin formal → asumir primer player online
    -- En hosted, el host SIEMPRE está en getOnlinePlayers (es su propio proceso).
    -- En dedicated, si nadie es admin, devolver el primero igual (peor escenario: nadie ejecuta el comando).
    return players:get(0)
end
```

**Por qué el fallback es seguro:**
- Hosted: el host **es** el primer online en la práctica (es su PC). El comando `/additem` ejecuta como cliente local del host, y `SendCommandToServer` desde host hosted pasa el check de admin de PZ (es admin de facto por `isCoopHost`).
- Dedicated: si el server no tiene admin online → el fallback intenta con un user normal → falla silenciosa (acceptable, el server admin debería estar online).

**Cuando rompió:** 2026-06-16. Sprint v0.6.1 — `_buscarHostAdmin` devolvía nil en hosted, items nunca se entregaban. Agregar el fallback PASS 2 resolvió. **Misma lógica que isCoopHost de gotcha #23, pero aplicada al lookup desde server-context.**

---

## 🚨🔥 40. **Derrota colectiva MP — trackear `estado.participantes` + hook `Events.OnPlayerDeath`**

**Síntoma:** En MP, si todos los jugadores mueren durante una oleada, la oleada sigue corriendo en el server (timer + spawn + el Trono se va destruyendo) hasta que termina por timer. Visualmente: nadie está vivo defendiendo pero el sistema no lo nota.

**Causa:** El motor de oleadas asume "el dueño de la sesión sigue vivo". En SP esto es cierto trivialmente. En MP hay que detectar activamente cuando todos los participantes están muertos/offline.

**Fix completo:**

**1. Tracking de participantes al iniciar la oleada (HoldoorServer.iniciar):**

```lua
function HoldoorServer.iniciar(...)
    -- ... resto de la lógica de inicio ...
    estado.participantes = {}
    local ok, players = pcall(getOnlinePlayers)
    if ok and players then
        local n = players:size()
        for i = 0, n - 1 do
            local p = players:get(i)
            if p then
                local user = p:getUsername()
                if user then estado.participantes[user] = true end
            end
        end
    end
end
```

**2. Hook `Events.OnPlayerDeath` server-side:**

```lua
Events.OnPlayerDeath.Add(HoldoorServer._onPlayerMuerto)

function HoldoorServer._onPlayerMuerto(jugador)
    local estado = HoldoorServer.estado
    if not estado.activo then return end
    if not estado.participantes then return end

    local username = jugador:getUsername()
    if not username then return end
    estado.participantes[username] = nil

    -- Contar participantes vivos Y online
    local vivos = 0
    local ok, players = pcall(getOnlinePlayers)
    if ok and players then
        local n = players:size()
        for i = 0, n - 1 do
            local p = players:get(i)
            if p then
                local u = p:getUsername()
                if u and estado.participantes[u] and not p:isDead() then
                    vivos = vivos + 1
                end
            end
        end
    end

    if vivos == 0 then
        HoldoorServer.notificarTodos("derrotaColectiva", {
            ultimoCaido = username,
            oleada = estado.oleadaActual,
        })
        HoldoorServer._tronoCayo()  -- forzar end-of-game como si el Trono fuera destruido
    end
end
```

**Cliente** maneja `derrotaColectiva` mostrando mensaje épico + reset de UI.

**Por qué este enfoque y no otros:**
- ❌ `Events.OnPlayerDeath` cliente-side: en MP solo se dispara para el player local. El host no sabe cuándo muere un remoto.
- ❌ Polling cada N ticks: gastas CPU, además el momento de la muerte tiene latencia variable.
- ✅ Event server-side: se dispara una vez por muerte real, sincronizado con el motor.

**Caso edge — disconnect:** si un participante se desconecta durante la oleada, su lookup en `getOnlinePlayers` devuelve nil → el contador `vivos` lo trata como "no vivo" → si era el último, dispara derrota colectiva. Comportamiento deseable.

**Cuando rompió:** 2026-06-16. Sprint v0.6.1 — request del user: "agreguemos también de que si muero yo y todos los players online (que están jugando la oleada) se de por perdida". Implementación con OnPlayerDeath + participants tracking resolvió.

---

## 🔥 41. Off-by-one en "Sobreviviste N oleadas" — `args.oleadas - 1`

**Síntoma:** Cliente muere durante la oleada 3. Mensaje muestra "Sobreviviste 3 oleadas". Realmente sobrevivió 2 (la 1 y la 2; en la 3 cayó).

**Causa:** El server envía en el payload de `tronoCayo` o `derrotaColectiva` el número de oleada **donde murió** (`oleadaActual`), no las sobrevividas. El cliente lo usaba directo.

**Fix en el handler del cliente:**

```lua
HoldoorClient.handlers.tronoCayo = function(args)
    local sobrevividas = math.max(0, (args.oleadas or 1) - 1)
    local subline
    if sobrevividas == 0 then
        subline = "Caiste en la primera oleada."
    elseif sobrevividas == 1 then
        subline = "Sobreviviste 1 oleada. Caiste en la 2da."
    else
        subline = "Sobreviviste " .. sobrevividas .. " oleadas. Caiste en la " .. (sobrevividas + 1) .. "."
    end
    -- ... mostrar subline ...
end
```

**Regla:** cualquier counter que muestre "sobrevivió X" donde X puede ser 0, hay que considerar el edge case "X=0 → frase distinta a 'sobreviviste 0 oleadas'".

**Cuando rompió:** 2026-06-16. Sprint v0.6.1 — Nahuel: "no sobreviví 3 oleadas sino 2, porque en la tercera me morí".

---

**Última actualización:** 2026-06-16 — Sprint v0.6.2 parcial cerrado (gotchas #42-#47 sumados: refactor tienda + sistema vender niveles)

---

## 🔥 42. `Perks[slug]` indexing en B42 es INCONSISTENTE — usar cascada de 4 caminos

**Síntoma:** acceso `Perks["LongBlade"]` resuelve OK pero `Perks["Sprinting"]`, `Perks["Sneak"]`, `Perks["Lightfoot"]`, `Perks["Doctor"]`, etc. devuelven nil — aunque los slugs son los correctos (confirmado via `/addxp "user" Sprinting=500` que SÍ entrega 500 XP).

**Causa:** `Perks` en B42 es un namespace Java cuyo lookup por indexación string no funciona uniformemente. Algunos enums son accesibles directamente, otros requieren resolver via `Perks.FromString()` o iterar.

**Fix lockeado** — cascada de 4 caminos:

```lua
local function _resolverPerk(perkId)
    if not Perks or not perkId then return nil end
    local p

    -- 1) Acceso directo por indexación string
    pcall(function() p = Perks[perkId] end)
    if p then return p end

    -- 2) Perks.FromString
    pcall(function() p = Perks.FromString(perkId) end)
    if p then return p end

    -- 3) Iterar pairs(Perks)
    pcall(function()
        for k, v in pairs(Perks) do
            if tostring(k) == perkId then p = v; return end
        end
    end)
    if p then return p end

    -- 4) Iterar PerkFactory.PerkList (lista Java) buscando por id
    pcall(function()
        if PerkFactory and PerkFactory.PerkList then
            local list = PerkFactory.PerkList
            for i = 0, list:size() - 1 do
                local pf = list:get(i)
                if pf then
                    local id
                    pcall(function() id = tostring(pf:getId()) end)
                    if id == perkId then pcall(function() p = pf:getType() end); return end
                end
            end
        end
    end)
    return p
end
```

**Cuando rompió:** 2026-06-16. Sprint v0.6.2 — sistema "vender niveles" devolvía "(info no disponible)" para 10 de 16 skills. Resolver original solo tenía 2 caminos (indexing + FromString).

---

## 🔥 43. `player:getXp():getXP(perk)` devuelve FLOAT — `math.ceil` obligatorio antes de pasar a `/addxp`

**Síntoma:** después de calcular `xpFaltante = xpObjetivo - xpActual`, el valor venía con decimales (ej. `74.75` o `71.05869913101196`). Al pasarlo a `string.format('/addxp "%s" %s=%d', ...)` el `%d` lo trunca o el comando vanilla lo ignora silenciosamente, entregando **1 XP en lugar del valor real**.

**Causa:** B42 mantiene XP como `float` internamente. PZ asigna XP en cantidades fraccionarias (ej. cuando ganás XP por matar zombie). El número faltante hereda esa fracción.

**Fix:**
```lua
local xpFaltante = math.max(1, math.ceil(xpObjetivoAcum - xpAct))
```

`math.ceil` redondea para arriba (cubre el nivel completo). NO usar `math.floor` o `math.round` — pueden dejar XP justo abajo del threshold del nivel.

**Cuando rompió:** 2026-06-16. Sprint v0.6.2 — compras de subir_nivel en skills con XP fraccional entregaban 1 XP en lugar de los ~70-100 necesarios. Detectado en consola: "Added 1.0 Nimble xp's to HouS".

---

## 🔥 44. `/addxp` y `/additem` pueden silenciosamente entregar 1 XP / 0 items con slug INCORRECTO

**Síntoma:** ejecutás `/addxp "HouS" SmallBlunt=500` esperando 500 XP. Log dice "Added **1.0** SmallBlunt xp's to HouS". Solo 1 XP, no 500.

**Causa:** comandos admin vanilla B42 son tolerantes a slugs inválidos. Si el perk no existe con ese nombre exacto, el comando NO falla — entrega 1 XP como default o nada.

**Implicación crítica**: la **wiki PZ NO es fuente de verdad** sobre slugs B42. Hay que validar empíricamente.

**Protocolo de validación de slug:**
1. Abrir consola admin del juego (`/`)
2. Ejecutar `/addxp "TuUser" SlugCandidato=500`
3. Mirar el chat: si dice "Added 500.0 Slug xp's" → slug OK. Si dice "Added 1.0" o no aparece → slug NO existe.
4. Para items: `/additem "TuUser" "Base.SlugCandidato" 1` y verificar si llega al inventario.

**Cuando rompió:** 2026-06-16. Sprint v0.6.2 — `Base.WineBottle` no existía en B42 reciente (renamed a `Base.Wine2`), `Base.Jeans` renamed a `Base.Trousers_Denim`, `Base.Jacket_ArmyCamoForeign` no existe (usar `Jacket_ArmyCamoGreen`). Detectados solo via testing empírico.

---

## 🔥 45. B42 reciente migró varios items a Fluid Containers con slugs RENOMBRADOS

**Síntoma:** items que existían en B41 y en B42 inicial ahora dicen "doesn't exist" en B42 reciente.

**Causa:** PZ B42 introdujo el sistema de Fluid Containers (líquidos en botellas) y renombró varios items que eran botellas. Esto sigue en proceso de migración — algunos slugs cambian entre patches.

**Slugs confirmados que cambiaron (2026-06-16):**
- `Base.WineBottle` → **`Base.Wine2`** (Red Wine)
- `Base.Jeans` → **`Base.Trousers_Denim`**
- `Base.Jacket_ArmyCamoForeign` → **`Base.Jacket_ArmyCamoGreen`** (Foreign no existe en B42)

**Slugs que probablemente cambien en próximos patches B42** (vigilar):
- Items de bebida que aún tengan formato viejo
- Items de comida (algunos tienen variantes Fluid Container)

**Protocolo defensivo al codear catálogo con muchos slugs:**
1. Validar cada uno via gotcha #44 (consola admin).
2. Documentar en commit las versiones B42 donde funcionó.
3. Si una actualización rompe slugs, mostrar al user el error visible (no fallar silenciosamente).

**Cuando rompió:** 2026-06-16. Sprint v0.6.2 — tras agregar Bebidas con `Base.WineBottle` (que era válido en v0.6.1), el item no se entregaba en B42 versión actual.

---

## 🔥 46. Catálogo con estructura OPCIONAL (`subcategorias`) — actualizar TODAS las funciones que iteran

**Síntoma:** al introducir `cat.subcategorias` como alternativa a `cat.items`, algunas categorías rompen con `Expected a table` en `ipairs(cat.items)` cuando entran al `comprar` o lookup.

**Causa:** cuando se agrega una estructura nueva opcional al catálogo, hay que actualizar **TODAS** las funciones que iteran. Es fácil olvidarse de una (sobre todo cuando hay funciones gemelas en `Catalog.buscar`, `_findItemDef` en UI, y `comprar` en cliente).

**Fix patrón:** usar fallback `or {}` y agregar iter en sub-categorías SIEMPRE que se itera el catálogo:

```lua
-- Patron backward-compatible
for _, cat in ipairs(HoldoorShopCatalog.categorias) do
    if cat.id == categoriaId then
        -- buscar en items directos (categoria clasica)
        for _, it in ipairs(cat.items or {}) do
            if it.id == itemId then return it end
        end
        -- buscar en sub-categorias (categoria nueva)
        for _, sub in ipairs(cat.subcategorias or {}) do
            for _, it in ipairs(sub.items or {}) do
                if it.id == itemId then return it end
            end
        end
    end
end
```

**Funciones a actualizar al agregar `subcategorias`:**
1. `HoldoorShopCatalog.buscar(catId, itemId)` — shared
2. `_findItemDef(catId, itemId)` — HoldoorShop.lua (UI)
3. `HoldoorClient.comprar(catId, itemId)` — lookup del item
4. Cualquier loop futuro que itere categorías para validaciones

**Cuando rompió:** 2026-06-16. Sprint v0.6.2 — agregar sub-cats a Consumibles rompió las compras: la UI funcionaba (porque `_findItemDef` se actualizó) pero `HoldoorClient.comprar` reventó silenciosamente con "Expected a table" porque me olvidé esa función.

---

## 🔥 47. Refresh UI post-compra — NO esperar callback del server, llamar `refrescar()` DIRECTO

**Síntoma:** después de comprar un item de `subir_nivel`, el botón sigue mostrando el precio viejo (debería decir "MAX" si llegamos a nivel 10). Solo se actualiza al cambiar de pestaña.

**Causa:** el callback `monedasActualizadas` del server vuelve después de que `HoldoorClient.comprar` ya retornó. El handler dispara `HoldoorShop.refrescar()` pero el render queda "atrasado" porque el cálculo dinámico de nivel se hace en el render — y si el render no se llama, ves los valores de antes de la compra.

**Fix:** llamar `refrescar()` SINCRÓNICO al final de `comprar`, además del callback:

```lua
function HoldoorClient.comprar(categoriaId, itemId)
    -- ... pre-validación, cobro, entrega de items/XP ...

    -- Refresh inmediato sin esperar callback del server
    if HoldoorShop and HoldoorShop.refrescar then
        pcall(HoldoorShop.refrescar)
    end
end
```

El callback del server hace otro refresh redundante después (no rompe, solo doble-trabajo trivial).

**Aplica a:** cualquier acción de tienda que cambie el estado lookable del player (nivel de skill, monedas, materiales).

**Cuando rompió:** 2026-06-16. Sprint v0.6.2 — Nahuel compró nivel 9→10 de Maintenance, el comando se ejecutó OK, pero el botón seguía mostrando "6 Plata" en lugar de "MAX" hasta que cambió de pestaña.

---

**Última actualización:** 2026-06-16 — Sprint v0.6.2 parcial (gotchas #42-#47 lockeados tras refactor masivo de la tienda)

---

## 🔥 48. **Curaciones del Player en MP — usar `onHealthCheatCurrentPlayer` con `action="healthFull"` POR cada body part (NO `healthFullBody`)**

**Síntoma:** llamás `bP:RestoreToFullHealth()` cliente-side sobre los body parts del player → visualmente se cura en el momento. Pero **4-6 segundos después, el daño vuelve** (mordedura, sangrado, etc.). El sync MP revierte el cambio porque el server tenía estado viejo.

**Causa:** en MP el `BodyDamage` es authoritative del server. Cambios client-side se sincronizan al server, pero si el server NO recibe el cambio explícitamente, en el siguiente sync periódico el server propaga su versión vieja al cliente → se "revierte" la cura.

**Fix definitivo** — usar el mismo endpoint que el panel admin vanilla:

```lua
-- Para curar UN body part:
sendClientCommand(player, "player", "onHealthCheatCurrentPlayer", {
    bodyPartIndex = i,
    action = "healthFull",          -- ← action correcta
    id = player:getOnlineID(),
})

-- Para curar TODO el cuerpo: iterar los 17 body parts y enviar un comando por cada uno
local bd = player:getBodyDamage()
local parts = bd:getBodyParts()
for i = 0, parts:size() - 1 do
    sendClientCommand(player, "player", "onHealthCheatCurrentPlayer", {
        bodyPartIndex = i, action = "healthFull", id = player:getOnlineID(),
    })
end
```

**Trampa cazada — NO usar `action="healthFullBody"`:** en `ClientCommands.lua:557` el handler server-side de `healthFullBody` usa `player` en vez de `otherPlayer` (bug vanilla B42). Sólo `healthFull` individual aplica sobre el `otherPlayer` correcto.

**Aplica a curas de cualquier condición**: mordedura (action=`bite`), sangrado (`bleeding`), fractura (`fracture`), corte (`cut`), etc. Pero **ojo**: estas acciones son TOGGLE — si el body part NO tiene la condición, la AGREGAN. Iterar pre-filtrando con `bP:bitten()`, `bP:bleeding()`, etc.

**Cuando rompió:** 2026-06-16 noche. Sprint v0.6.2 — Reliquia "Beso del Dios" curaba visualmente pero a los 5 seg volvía la mordedura. Resolver tomó varias iteraciones hasta encontrar el endpoint server-side correcto y la trampa del `healthFullBody`.

**Ref vanilla:** `media/lua/client/XpSystem/ISUI/ISHealthPanel.lua:191` (onCheatCurrentPlayer cliente) → `media/lua/server/ClientCommands.lua:457` (handler server-side).

---

## 🔥 49. **APIs `setX` del Player (godmode/invisible/zombiesDontAttack/etc.) NO se aplican en MP desde código mod aunque uses `sendPlayerExtraInfo`**

**Síntoma:** llamás desde tu mod cliente:
```lua
player:setZombiesDontAttack(true)
sendPlayerExtraInfo(player)
```
Logs confirman ejecución sin errores. **PERO el efecto no aplica en gameplay** — los zombies te siguen atacando. Lo mismo con `setUnlimitedEndurance`, `setUnlimitedCarry`, `setFastMoveCheat`, `setInvisible`, `setNoClip`, etc.

**Test crítico:** desde el panel admin vanilla (Editar privilegios de administrador → toggle "Zombies Don't Attack" + Guardar) los mismos cambios SÍ funcionan. Y el panel admin hace EXACTAMENTE lo mismo: `setX(true)` + `sendPlayerExtraInfo(player)` al apretar Guardar.

**Diferencia invisible:** el panel admin tiene algún flujo interno Java-side adicional (capaz a través de `Capability` checks, o algún broadcast no documentado en Lua) que no se puede replicar desde código mod.

**Estado actual:** **limitación arquitectónica de B42**. Sin acceso al código Java fuente, no podemos resolver esto. Las APIs `setX` funcionan SP pero NO en MP desde mod.

**Workaround:**
- Para curaciones → usar gotcha #48 (`onHealthCheatCurrentPlayer`)
- Para teleport → usar `/teleport` o API directa `player:setX/Y/Z()` + `transmitPlayer()` (no testeado al 100%)
- Para godmode/invisible/zombies-don't-attack/etc → **no hay solución conocida desde mod**. Marcar como pendiente.

**Cuando rompió:** 2026-06-16 noche. Sprint v0.6.2 — implementamos 4 "Hechizos" con setX APIs replicando el panel admin. Logs OK. Efectos NO aplicaban. Después de horas de debug + comparación con vanilla, conclusión: hay algo Java-side que no podemos tocar. Items removidos del mod.

---

## 🔥 50. **Items de cura deben VALIDAR previo a comprar que el player tiene la condición**

**Síntoma:** player compra item de cura (ej. "Vendaje del Septón" para sangrado). Le cobran las monedas. Pero NO tenía sangrado → la cura no hace nada. Pierde monedas.

**Causa:** sin validación previa, el flow es cobrar primero, ejecutar después. Si la condición a curar no existe → no hay nada que curar pero el cobro ya se hizo.

**Fix:** validación pre-compra en `HoldoorClient.comprar` ANTES de pedir al server cobrar.

```lua
-- Ejemplo para "cura_sangrado"
if itemDef.accion.tipo == "reliquia_cura_sangrado" then
    local player = getSpecificPlayer(0)
    local tiene = false
    pcall(function()
        local parts = player:getBodyDamage():getBodyParts()
        for i = 0, parts:size() - 1 do
            local bP = parts:get(i)
            if bP and bP:bleeding() then tiene = true; return end
        end
    end)
    if not tiene then
        HoldoorClient.chat("[HOLDOOR] No tenés sangrado. Nada que curar.", 1, 0.6, 0.2)
        return  -- aborta antes del cobro
    end
end
```

**Pattern aplica a TODAS las curas específicas:** rasguños (`scratched`), sangrado (`bleeding`), fracturas (`getFractureTime > 0`), cortes (`isDeepWounded` or `isCut`), mordeduras (`bitten`), y al Beso del Dios genérico (check ANY de las anteriores).

**Regla operativa:** cuando un item TIENE precondiciones de uso, validar PRE-cobro. NO confiar en validación post-cobro o "el server decide" — eso deja al user sin monedas.

**Cuando rompió:** 2026-06-16 — Nahuel testeó el Beso del Dios sano (sin lastimaduras), pagó las monedas, no pasó nada. UX rota. Fix con validación previa.

---

**Última actualización:** 2026-06-16 — Sprint v0.6.2 cerrado (gotchas #48-#50 sumados: curaciones MP authoritative, limitación setX APIs, validación pre-compra)

---

## 🔥 51. **`player:getModData()` modificado server-side requiere `player:transmitModData()` después — sino NO persiste al save MP**

**Síntoma:** durante la sesión MP las monedas/materiales/contadores del player se modifican OK y se ven en el HUD. **PERO al cerrar y reabrir el server, todo vuelve a 0** — el player parece "nuevo".

**Causa:** en B42 MP, `player:getModData()` server-side modifica la copia EN MEMORIA del server. Pero sin llamar `player:transmitModData()` explícito:
1. El server NO marca el ModData del player como "dirty" → al guardar el mundo, persiste el ModData ORIGINAL (sin los cambios).
2. El cliente no recibe el sync del cambio → su `getSpecificPlayer(0):getModData()` muestra valores viejos (parcialmente compensado por sync automático cada N ticks pero no garantizado al close).

**Fix:** después de CUALQUIER modificación de `getModData()` server-side, llamar inmediatamente:

```lua
md.Holdoor_Bronze = (md.Holdoor_Bronze or 0) + 100
md.Holdoor_Cuero  = (md.Holdoor_Cuero  or 0) + 1
pcall(function() jugador:transmitModData() end)   -- ← OBLIGATORIO
```

Patrón helper recomendado:

```lua
local function _persistirModData(p)
    pcall(function() p:transmitModData() end)
end

-- En cada función que modifica ModData server-side:
md.X = nuevoValor
_persistirModData(p)
```

**Aplica a TODAS las operaciones server-side que tocan `getModData()`:**
- Dar monedas/materiales (`darMonedasA`, `darMatsA`)
- Cobrar tienda (`_comprar`)
- Transferir monedas (`_transferirMonedas` — para ambos players)
- Marcar flags (Holdoor_BesoDios, Holdoor_TraitComprado, Holdoor_TraitCurado)

**Si el cliente modifica `getModData()` (caso poco común — preferir delegación al server):** también llamar `transmitModData()` después para sincronizar al server.

**Refs vanilla B42:**
- `media/lua/client/Entity/ISUI/Controls/ISWidgetTitleHeader.lua:519` — `self.player:transmitModData()`
- Numerosos `isoObject:transmitModData()` en `ClientCommands.lua`, `SCampfireGlobalObject.lua`, `SPlantGlobalObject.lua`, etc. — confirma el patrón vanilla "modificar + transmit".

**Cuando rompió:** 2026-06-16 madrugada. Sprint v0.6.2 — Nahuel reportó que las monedas se reseteaban a 0 al cerrar y abrir el server. Detectado tras invertir varias horas en hipótesis falsas. Resolución: agregar `transmitModData()` en 8+ lugares de `HoldoorServer.lua` y 1 en `HoldoorUI.lua` (botón TEST DARME).

---

**Última actualización:** 2026-06-16 — Sprint v0.6.2 cerrado (gotchas #48-#51 lockeados — el #51 es el fix CRÍTICO de persistencia MP)

---

## #52 — B42: `setAccessLevel(string)` NO existe en IsoPlayer

**Síntoma:** llamar `jugador:setAccessLevel("admin")` en B42 server-side tira NullPointerException Java que `pcall` agarra (silently fails).

**Descubrimiento:** búsqueda en source vanilla. La API correcta para SETEAR rol/nivel es:
```lua
jugador:setRole("admin")             -- en ISPlayerStatsUI.lua:611
sendPlayerStatsChange(jugador)       -- propagar al cliente
```

**PERO en práctica empírica**: `setRole(string)` tampoco se aplica correctamente desde server-side (DIAG mostró que el role del jugador seguía siendo "user" tras la llamada). El método REAL que funciona es:

```lua
SendCommandToServer('/setaccesslevel "' .. username .. '" admin')
```

Esto funciona desde CLIENTE → server (incluido CoopHost). El coop host puede correr comandos admin via slash aunque su `getAccessLevel()` reporte "user" — la autoridad implícita del host.

**Notar:** `getAccessLevel()` SÍ funciona para LEER. La asimetría es solo en el setter.

**Cuándo aplica:** elevar temporalmente a jugador para que stats:set + sendPlayerStat sean aceptados por el server. Usado en el Beso del Dios v0.7 #33.

---

## #53 — Admin elevation auto-activa GodMod + Invisible + NoClip

**Síntoma:** después de `/setaccesslevel X admin`, el jugador entra automáticamente en GodMod (invulnerable), Invisible (zombies no lo ven) y NoClip (atraviesa paredes).

**Mecánica vanilla B42:** PZ guarda "admin privileges" por usuario. Al elevarse a admin, reaplica los flags del perfil (por default tienen GodMod + Invisible + NoClip activados). Probado empíricamente que esto ocurre incluso con perfiles aparentemente vacíos.

**Implicancias:**

1. **Como bug**: si elevamos a admin para hacer una operación puntual, el jugador queda invulnerable + invisible + atraviesa paredes durante TODO el tiempo que dure el rol elevado.
2. **Como feature**: GodMod cura ABSOLUTAMENTE TODO en ~50-150ms (mordeduras, hambre, sed, infección zombi, fatiga, fracturas, sangrado). Si lo querés usar como item premium ("Beso del Dios"), es perfecto.
3. **Mitigación selectiva**: si querés admin pero NO los flags, watchdog cada frame que apaga `setGodMod(false) + setInvisible(false) + setNoClip(false)`. Cuidado con `setGhostMode` (NoClip y GhostMode son diferentes — Ghost permite walk-through-walls también pero por mecánica distinta).

**Cuándo aplica:** v0.7 #33 (Beso del Dios), cualquier feature futuro que elevación a admin para forzar autoridad.

---

## #54 — Lua `local function` scope: solo visible DESPUÉS de la línea de declaración

**Síntoma:** llamada a función helper devuelve `nil reference` exception. La función está declarada en el archivo pero NO está en scope donde se llama.

**Causa raíz:** en Lua, `local function _foo(p)` es visible solo a partir de su línea de declaración hacia abajo. Si una función `HoldoorServer.bar()` declarada en línea 100 intenta llamar a `local function _foo` declarada en línea 375, en runtime `_foo` es `nil` desde el closure de `bar`.

**Ejemplo concreto (v0.7 #38b):**
```lua
-- Línea 97
function HoldoorServer._aplicarRefundAJugador(jugador)
    ...
    _persistirModData(jugador)   -- ❌ _persistirModData NO está en scope aún
end

-- Línea 375
local function _persistirModData(p)
    pcall(function() p:transmitModData() end)
end
```

**Fixes:**
- **Inline** la función helper: `pcall(function() jugador:transmitModData() end)` directamente.
- **Forward declare**: `local _persistirModData` antes de todo, luego asignar más adelante.
- **Mover** las funciones que la usan después de su declaración.
- **Exponer como miembro**: `function HoldoorServer._persistirModData(p)` global del namespace (no `local`).

**Cuándo aplica:** cualquier refactor donde agregás funciones helpers nuevas. Verificar el ORDEN del archivo, no solo que la función exista.

---

## #55 — Race condition con `stats:set()` + `sendPlayerStat()` en MP

**Síntoma:** cliente setea `stats:set(HUNGER, 0)` + `sendPlayerStat()` durante una compra en oleada activa. El server "rebota" el valor a ~0.033 en 1 segundo (en vez de quedarse en 0).

**Causa:** ejecutar el `stats:set()` INLINE durante el flow de compra crea race condition con el procesamiento server-side. El server tiene su propia copia del jugador y la sincroniza al cliente, pisando el cambio local.

**Fix probado empíricamente (v0.7 #28c):**

```lua
-- Server-side (HoldoorServer.lua) ramo de _aplicarAccion:
local sendFrames = 5
local sendHandler
sendHandler = function()
    sendFrames = sendFrames - 1
    if sendFrames <= 0 then
        HoldoorServer.notificarTodos("ejecutar_stats_reset", { target=username, stats=..., valores=... })
        Events.OnTick.Remove(sendHandler)
    end
end
Events.OnTick.Add(sendHandler)
```

Cliente recibe la notificación ~5 frames después de la compra (~80ms), ya pasó la ventana de race. Hace `stats:set + sendPlayerStat` y persiste.

**Cuándo aplica:** cualquier operación que modifique stats del player desde un flow disparado por sendClientCommand → onComandoCliente. Siempre demorar la ejecución del lado cliente.

---

## #56 — `Events.OnCreatePlayer` dispara en 3 escenarios

**Confirmado empíricamente:** el evento dispara cuando:
1. **Spawn inicial** — el jugador crea un personaje por primera vez en este server
2. **Respawn post-muerte** — el jugador muere y crea nuevo personaje
3. **Reconexión** — el jugador se desconecta y vuelve a entrar al server con su personaje existente

**Punto de hookeo perfecto** para aplicar estado per-username que tiene que persistir entre personajes (no en ModData del IsoPlayer, que muere con el char).

**Patrón usado en v0.7 #38 + #40:**

```lua
Events.OnCreatePlayer.Add(function(_, jugador)
    if not jugador then return end
    -- Aplicar seguro de muerte (refund pendiente)
    HoldoorServer._aplicarRefundAJugador(jugador)
    -- Aplicar pagos offline acumulados (recompensas de oleadas ganadas mientras estaba offline)
    HoldoorServer._aplicarPagosPendientesAJugador(jugador)
end)
```

Ambos handlers leen de tablas indexadas por username, aplican al IsoPlayer fresh, y limpian el entry.

**Persistencia:** estado per-username debe estar en GlobalModData (`ModData.getOrCreate("Holdoor_X")`) para sobrevivir restart del server.

---

---

## #57 — `/removezombies` borra cadáveres también, no solo zombies vivos

**Confirmado empíricamente + en código propio del mod** (HoldoorServer.lua línea 2759):
> "setHealth(0) deja cadaveres lootables durante los 30s pausa + 30s prep. El bridge /removezombies se dispara al inicio de la PROXIMA oleada y los limpia"

El comando `/removezombies -x X -y Y -z Z -radius R` elimina TANTO zombies vivos COMO `IsoDeadBody` (cadáveres) en el área. Útil para limpieza total de fin de oleada, pero **destructivo si necesitás preservar el cadáver del player muerto** (ej. Revival System v0.8 #21 donde el user vuelve a lootear su cuerpo).

**Solución para matar SOLO vivos preservando cadáveres:**

```lua
function HoldoorServer._matarZombiesEnArea(cx, cy, cz, radio)
    local ok_cell, cell = pcall(getCell)
    if not ok_cell or not cell then return 0 end
    local eliminados = 0
    for dx = -radio, radio do
        for dy = -radio, radio do
            if dx*dx + dy*dy <= radio*radio then
                local sq = cell:getGridSquare(cx + dx, cy + dy, cz)
                if sq then
                    local objs = sq:getMovingObjects()  -- IsoZombie vivos
                    -- Skip getStaticMovingObjects() (IsoDeadBody)
                    if objs then
                        for i = 0, objs:size() - 1 do
                            local obj = objs:get(i)
                            if obj and instanceof(obj, "IsoZombie") then
                                pcall(function() obj:setHealth(0.0); eliminados = eliminados + 1 end)
                            end
                        end
                    end
                end
            end
        end
    end
    return eliminados
end
```

**Cuándo aplica:** cualquier flow donde matás zombies por radio Y querés preservar cadáveres en el área (Revival System, eventos donde el lugar es importante mantener visualmente, etc).

---

## #58 — `LevelPerk` / `getXp:AddXP` server-side son flaky en MP, usar `/addxp` admin

Comentario del propio mod (HoldoorServer.lua línea 1066-1067):
> "el AddXP server-side se sobreescribe por el cliente cada vez que syncea (XP sube 1 nivel y vuelve a bajar). Solucion: NO hacer AddXP aca, dejar que HoldoorClient.comprar lo haga en cliente-context puro despues del cobro."

**Síntoma:** llamás `jugador:LevelPerk(enum)` o `jugador:getXp():AddXP(enum, delta)` server-side. En SP funciona. En MP el cliente puede pisar el cambio porque tiene su propia copia del XP y la sincroniza al server.

**Solución (mismo patrón tienda subir_nivel):** usar `/addxp` admin command via cliente.

```lua
-- Server calcula XP necesario para llegar a nivel objetivo
local xpTotal = 0
local perkDef = PerkFactory.getPerk(enum)
for lvl = 1, lvlObjetivo do
    local xp = perkDef:getXpForLevel(lvl)
    if xp then xpTotal = xpTotal + xp end
end
xpTotal = xpTotal + xpParcial   -- XP parcial dentro del nivel objetivo

-- Server dispatcha lista al cliente
sendServerCommand(jugador, MODULE, "ejecutarRestoreProgresoBatch", { xpDeltas = { ... } })

-- Cliente itera y emite /addxp por cada perk (con 2 frames de espacio anti-flood)
local cmd = string.format('/addxp "%s" %s=%d', username, perkName, amount)
SendCommandToServer(cmd)
```

**Por qué funciona:** `/addxp` es admin command server-authoritative que pasa por el flow validado de B42. El player debe ser admin en el momento (caso de uso del Revival: durante los 20s del admin trampoline post-spawn).

**Cuándo aplica:** restaurar progreso de skills tras muerte, otorgar XP por logros, cualquier delta de XP que debe persistir en MP.

---

## #59 — Nombres de materiales en md son LARGOS (Cuero/Hierro/Acero/Valyrio/Obsidiana), no abreviados

**Bug recurrente:** el HUD lateral muestra los materiales abreviados (`Cu`, `Hi`, `Ac`, `Va`, `Ob`). Es **fácil asumir** que los campos del md también son cortos. **NO**.

**Nombres REALES en md (confirmados en HoldoorServer.lua línea 790-794):**

```lua
md.Holdoor_Cuero       -- NO md.Holdoor_Cu
md.Holdoor_Hierro      -- NO md.Holdoor_Hi
md.Holdoor_Acero       -- NO md.Holdoor_Ac
md.Holdoor_Valyrio     -- NO md.Holdoor_Va
md.Holdoor_Obsidiana   -- NO md.Holdoor_Ob
```

**Síntoma del bug si inventás:** leer `md.Holdoor_Cu` devuelve `nil` → fallback a 0 → guardás 0 → restaurás 0. Eternamente. Sin error visible.

**Lección de regla #1:** NO INVENTAR. Antes de tocar materiales en md, **buscar en el código existente** (`grep "md.Holdoor_Cu"` da 0 hits, `grep "md.Holdoor_Cuero"` da los hits reales). Si no aparece, preguntar.

**Cuándo aplica:** snapshot/restore de materiales, modificación de cantidades, validaciones.

---

## #60 — Cell del lugar de muerte NO está cargado server-side en `OnCreatePlayer`

**Síntoma:** llamás `getCell():getGridSquare(deathX, deathY, deathZ):getMovingObjects()` desde el handler `OnCreatePlayer` y la lista viene vacía aunque visualmente hay zombies ahí cuando el player se teleporta segundos después.

**Causa:** cuando `OnCreatePlayer` dispara, el char nuevo está en su spawn point inicial (lejos del lugar de muerte). El server no tiene cargado el cell del lugar de muerte porque ningún player está cerca. `MovingObjects` no tiene los zombies instanciados todavía.

**Solución: diferir la operación con cola FIFO post-teleport.** En el Revival System v0.8 #21 usamos disparos espaciados a +2s/+5s/+10s. Al menos uno corre cuando el cell ya está cargado por el cliente teleportado:

```lua
HoldoorServer._matarZombiesQueue = {}

-- En OnCreatePlayer (encolar):
for _, delay in ipairs({2, 5, 10}) do
    table.insert(HoldoorServer._matarZombiesQueue, {
        x = coords.x, y = coords.y, z = coords.z, radio = 15,
        fireAt = os.time() + delay, label = "+"..delay.."s",
    })
end

-- onTick separado procesa la cola:
Events.OnTick.Add(function()
    if #HoldoorServer._matarZombiesQueue == 0 then return end
    local ahora = os.time()
    local i = 1
    while i <= #HoldoorServer._matarZombiesQueue do
        local task = HoldoorServer._matarZombiesQueue[i]
        if ahora >= task.fireAt then
            local n = HoldoorServer._matarZombiesEnArea(task.x, task.y, task.z, task.radio)
            print("[Diferido " .. task.label .. "] " .. n .. " zombies eliminados")
            table.remove(HoldoorServer._matarZombiesQueue, i)
        else
            i = i + 1
        end
    end
end)
```

**Cuándo aplica:** cualquier operación que toque tiles/objetos/zombies en coords lejanas del spawn inicial del player, ejecutada inmediatamente al OnCreatePlayer.

---

## #61 — Caracteres especiales rompen la fuente de PZ B42

**Síntoma:** chats / setHaloNote / labels con `¡`, `¿`, `á`, `é`, `í`, `ó`, `ú`, `ñ` renderizan algunos caracteres como `?` en pantalla aunque el código fuente los tenga bien escritos.

**Caracteres que SÍ rompen:**
- `¡` (apertura exclamación)
- `¿` (apertura interrogación)
- Vocales acentuadas (depende de la fuente y contexto)

**Caracteres que NO rompen:**
- `!` (cierre exclamación, sin la de apertura)
- `?` (cierre interrogación, sin la de apertura)
- Letras sin acento
- Símbolos ASCII normales
- Símbolos Unicode comunes (★, ✓, ⟲, →)

**Workaround:** mantener los textos del mod sin acentos ni signos de apertura. Si necesitás puntuación, usar solo cierre. Reformular oraciones para evitar acentos críticos.

**Ejemplos del mod:**
```
❌ "¡Volando al Trono!"  →  ✅ "Volando al Trono!"
❌ "Andá al panel"        →  ✅ "Abri el panel"
❌ "Marcá tu base"        →  ✅ "Marca tu base"
```

**Cuándo aplica:** todos los strings que se muestran al user (chat, halo notes, labels HUD, mensajes de tienda, descripciones de items).

---

**Última actualización:** 2026-06-21 — Sprint v0.8 cerrado (gotchas #57-#61 lockeados, ver sprints_history.md "2026-06-21 — Sprint v0.8")

---

## 🔥 62. CoopHost host — NUNCA forzar `sendClientCommand` desde el cliente del host (rompe APIs del mundo)

**Síntoma:** en MP CoopHost, server reporta que las APIs corren (logs muestran `_limpiarZona eliminó 57 zombies`, `addSound ok=true`), pero **empíricamente nada impacta el mundo que el host ve en pantalla**: zombies no caen, bocina no aggrea, Trono no recibe daño. Mensajes del HUD lateral SÍ funcionan (porque usan `notificarTodos` que SÍ broadcast bien).

**Cuándo rompió:** sprint v0.8.3 (2026-06-21). Mi teoría equivocada fue: "en CoopHost ejecutar `HoldoorServer.X()` directo desde el cliente del host hace que los broadcasts no lleguen al friend remoto. Forzar `sendClientCommand` garantiza que el server context se active". REALIDAD: rompí los 7 días siguientes intentando "fixes" basados en esa teoría.

**Causa real:**
- En MP CoopHost, server y client son **contextos lógicos separados** dentro del mismo proceso. Tienen sus propios `MovingObjects`, sus propios `IsoZombie`, su propio "world view".
- Cuando el cliente del host hace `HoldoorServer.X()` **DIRECTO**: la función corre en **CLIENT context del host** → `setHealth(0)`, `addSound`, iteración de `IsoZombie` impactan los objetos que el host VE.
- Cuando el cliente del host hace `sendClientCommand("X", ...)`: el comando entra al server PZ via networking interno y dispara el handler en **SERVER context puro**. Las APIs del mundo en server context tocan **otros** IsoZombies que NO son los del cliente del host. Por eso el log dice "57 eliminados" pero visualmente quedan vivos.

**Patrón correcto (host local directo, remoto via sendClientCommand):**
```lua
function HoldoorClient.iniciar(config)
    if tieneServidorLocal() then
        -- SP / CoopHost host: directo. El flow corre en client context
        -- donde setHealth(0), addSound, getMovingObjects impactan el mundo visible.
        local player = getSpecificPlayer(0)
        if player then
            pcall(HoldoorServer.iniciar, player, config)
        end
    else
        -- Cliente remoto: sendClientCommand es lo correcto (no hay otra opción).
        sendClientCommand(HoldoorConfig.MODULE, "iniciar", { config = config })
    end
end
```

**Cuándo aplica:** todas las acciones que el cliente del host invoca y que después llaman APIs del mundo PZ:
- `iniciar`, `detener`, `setBase`, `quitarBase`, `oleadaManual`, `comprar`, `transferir`, `pedirEstado`
- Cualquier flow que termine ejecutando `setHealth`, `addSound`, `getCell():getGridSquare():getMovingObjects()`, etc.

**Lo que SÍ se puede broadcastear sin tocar el mundo del host:**
- `notificarTodos("evento", datos)` para mensajes / HUD / chat / monedas / item drops via `/additem`. Eso NO toca el mundo, solo envía datos a clientes. Sigue funcionando bien tanto desde server context como desde client context (notificarTodos hace loopback al cliente del host).

**Lo que NO se puede broadcastear (server context no lo hace):**
- `setHealth(0)` sobre IsoZombie del cliente del host → solo funciona en client context del host
- `addSound(nil, ...)` cerca del cliente del host → solo aggrea desde client context del host

**Cómo verificar empíricamente:**
- Si el log del SERVIDOR (PZ console interno) dice que la función corre pero el USUARIO ve que no impacta el mundo → bug de context.
- Si el log del cliente (`console.txt` del usuario) muestra el print de la función Y empíricamente el mundo cambia → patrón correcto.

**Anti-pattern muerto (NO usar):** forzar `sendClientCommand` siempre "porque garantiza activar server context". Eso es exactamente lo que rompe.

**Relacionado:** gotcha #36 (`sendServerCommand` 3-args broken en CoopHost — sí, eso es real, los clientes remotos sí necesitan `sendClientCommand`). Esta gotcha #62 es el complemento: el host NO debe usar `sendClientCommand` para sus propias acciones.

---

**Última actualización:** 2026-06-21 — Sprint v0.8.7 cerrado + Workshop publicado (gotchas #62 y #63 lockeados).
