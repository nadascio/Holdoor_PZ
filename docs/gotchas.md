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

**Última actualización:** 2026-06-13
