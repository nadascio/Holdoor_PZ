# Holdoor — Historial de sprints

> Append-only. Cada cierre de sesión / merge / feature completada se agrega abajo. No reescribir lo viejo.

---

## 2026-06-12 — Trono de Hierro funcional + limpieza arquitectónica

**Contexto:** Sesión larga continuada de implementación del Trono de Hierro. Veníamos del rename "Brasero" → "Trono", spawn 2x2 con `IsoThumpable`, HP compartido 1500. La sesión cerró con sistema funcional pero arrastró varios bugs encadenados.

### Lo que se hizo

**Sistema del Trono — completamente operativo:**
- Spawn 2×2 con offsets `{0,0}, {1,0}, {0,1}, {1,1}`.
- Pool de HP 1500 (4 piezas × 375 HP).
- Validación de sprite con `IsoSpriteManager:getSprite()` antes de spawnear (evita fantasmas).
- Lista de sprites candidatos con fallback garantizado (`carpentry_02_56`, `carpentry_02_64`).
- Damage boost server-side cada 2s que compensa el daño bajo de zombis vanilla a IsoThumpables. Escalado por modo (`facil=1, normal=2, dificil=4, pesadilla=8, test=5` HP por zombi adyacente por ciclo).
- Polling de HP cada 1s con broadcast a clientes.
- Warnings centrados al cruzar umbrales 60%/30%/10% (amarillo/rojo/crítico).
- Game over épico cuando HP llega a 0 y `modoDefensa = true`.
- Checkbox "Modo Defensa: defender el Trono de Hierro" en el panel F10.

**Bugs resueltos en orden:**

1. **`ñ` en identificador `_aplicarDañoBoost`** — kahlua no acepta caracteres no-ASCII en nombres de variables/funciones. Renombrado a `_aplicarDanoBoost`. Esto rompía **TODO el server Lua**, lo que explicaba por qué la oleada no arrancaba y por qué el Trono no spawneaba. Ver `gotchas.md` #1.

2. **3 copias del mod desincronizadas + overlay invisible de B42** — `Documents/Holdoor_PZ/`, `Zomboid/mods/Holdoor/`, `Zomboid/Workshop/.../Holdoor/media/`, y una subcarpeta `Workshop/.../Holdoor/42/`. PZ B42 hace **overlay con prioridad**: lee primero del `42/` y cae al `media/` raíz solo para los archivos que falten. Toda la sesión anterior alguien sincronizaba archivos sueltos a `42/` dejando `media/` raíz viejo. PZ usaba HoldoorServer.lua nuevo del `42/` + HoldoorClient/UI viejo del `media/` raíz. El mod funcionaba "a medias" sin que nadie se diera cuenta.

3. **Borrado prematuro de `42/` rompió el F10** — Borré la subcarpeta `42/` pensando que era redundante. PZ perdió el overlay nuevo y cayó al `media/` raíz que era del commit inicial del 11 (sin Trono, sin F10, sin handlers). El F10 dejó de abrir. Intenté "restaurar desde git" (`git checkout HEAD -- ...`) sin notar que el único commit era de hace varios sprints — y el laburo de meses estaba uncommitted en el source. Casi pierdo todo.

4. **Restore desde backup salvó la sesión** — Hice un backup del source completo ANTES de actuar (`Holdoor_PZ_BACKUP_20260612_pre_restore`). Restaurar desde ahí recuperó el estado funcional. Sin ese backup hoy habríamos perdido meses.

### Inventario de qué tenía la versión funcional (vs el commit inicial)

Diff entre commit inicial `604059d` (2026-06-11) y checkpoint `9e119fb` (2026-06-12):

**HoldoorClient.lua (+735 líneas)** — funciones nuevas:
- `getSaldo`, `getMateriales`, `jugadoresConectados`, `esAdmin`
- `guardarRecord`, `obtenerRecord` (records persistentes en ModData)
- `onTick`, `iniciar`, `pedirEstado`
- `comprar`, `transferir` (tienda + transferencia entre players)
- `onKeyPressed` (binding F10 — la clave que se perdió al hacer git checkout)
- `instalarComandoChat` (/holdoor)
- `onZombieMuertoLocal` (kills locales)

**HoldoorServer.lua (+1449 líneas)** — funciones nuevas:
- Trono: `_plantarTrono`, `_quitarTrono`, `_aplicarDanoBoost`, `_checkWarningsHP`, `_tronoCayo`
- Monedas: `_transferirMonedas`, `_comprar`, `_distribuirMonedas`
- Oleadas: `_iniciarPreparacion`, `_spawnTanda`, `_lanzarOleada`, `_reAggroZombies`, `_limpiarZona`, `_oleadaCompletada`
- Spawn: `spawnZombie`, `_spawnUno`, `calcularComposicion`
- Markers: `_plantarBandera`, `_quitarBandera`

**HoldoorUI.lua (+1480 líneas)** — clases nuevas:
- `HoldoorOverlay` — render world-space (worldToScreen + render)
- `HoldoorPanel` — panel F10 grande con tabs, modos, checkbox Modo Defensa
- `HoldoorHUD` — HUD lateral compacto con stats, botones Enviar/Tienda, expandir

**Archivos nuevos:**
- `HoldoorShop.lua` (+279 líneas) — UI de tienda
- `HoldoorShopCatalog.lua` (+161 líneas) — definición del catálogo

**Convención lockeada DEFINITIVA:** al editar cualquier archivo del mod, ejecutar el script de sync de `infra.md` sección 1 que copia `media/` ENTERO a las 3 ubicaciones de destino (incluyendo la `42/`). No archivos sueltos. No "limpieza" de la `42/` sin entender que es un overlay con prioridad. Ver `gotchas.md` #2 + #2b y `infra.md` sección 1.

**Acción inmediata post-sesión:** Commit `9e119fb` ya hecho como red de seguridad. El backup `Holdoor_PZ_BACKUP_20260612_pre_restore/` queda intacto hasta que el checkpoint se valide en uso real.

3. **Cadáveres contados como zombis vivos** — `getMovingObjects()` retorna cadáveres y son `IsoZombie`. El damage boost los contaba, generando `-10 HP` pasivo al Trono sin que nadie lo atacara. Fix: filtro `obj:isDead()`. Ver `gotchas.md` #4.

**Confirmaciones del user:**
- "funciona, lo rompen y se terminan, sale los carteles y el daño se incrementa" ✅
- Warning del 30% visible y bien (screenshot)
- Game over disparado correctamente al llegar HP a 0

### Pendientes que arrastra este sprint

- Visual del Trono — todavía no se ve. Plan A (sprite vanilla) o Plan B (custom PNG). Ver `next_steps.md` #1.
- Reseñas adicionales que el user mencionó tener listas pero no pasó aún.
- Sync visual MP del IsoThumpable. Ver `next_steps.md` #2.

### Decisiones de diseño lockeadas en esta sesión

- **Una sola fuente de la verdad** = `Documents/Holdoor_PZ/`. Workshop solo al publicar a Steam.
- **NO recrear `42/`** dentro del workshop folder — mod es B42-only.
- **Monedas y materiales son ModData**, no items reales (decisión venía pero se reafirmó tras fallar `InventoryItemFactory.CreateItem`).
- **Damage boost server-side** para compensar el daño bajo vanilla a IsoThumpables — preferible a hackear el sistema de daño nativo.

### Documentación creada en esta sesión

Estructura `docs/` en el repo con:
- `infra.md` — arquitectura técnica viva
- `gotchas.md` — trampas aprendidas
- `next_steps.md` — pendientes priorizados
- `sprints_history.md` (este doc) — append-only
- `README.md` — índice

Decisión: documentación del mod vive en su repo (`Documents/Holdoor_PZ/docs/`), NO en memoria de Claude del proyecto ContentIA. Memoria de Claude mantiene solo el doc de diseño general (`holdoor_mod_design.md`) y el MVP2 (`holdoor_mvp2_white_walkers.md`) como brújula estratégica.

---

**Próxima sesión arranca por:** Visual del Trono (punto 1 de `next_steps.md`) + reseñas del user pendientes.

---

## 2026-06-13 — Sprint mayor: HP por modo + drops materiales + items + tienda expandida + traits

**Implementado en una sola sesión (sprint #1):**

### HP del Trono por dificultad
- Tabla `HoldoorConfig.tronoHPPorModo`: facil 1500 / normal 1250 / dificil 1100 / pesadilla 1000 / test 1500.
- `_plantarTrono` usa el HP del modo activo.
- Panel F10 muestra "Vida del Trono: X HP" al elegir el modo.
- Modo Defensa activado ON por default (más atractivo).

### Sistema de drops por oleada (función única `_distribuirRecompensaOleada`)
- Multiplicadores por modo: facil 0.7x / normal 1x / dificil 1.5x / pesadilla 2.2x.
- Monedas base 2x más bronce (`floor(zombis/2)` en vez de `/4`).
- Chances de plata/oro +50%.
- **Drop de materiales** nuevo: Cuero / Hierro / Acero / Valyrio / Obsidiana con probabilidades escaladas por modo.
- **Drop de items reales** nuevo: pool extensible con categorías (médico, comida, armas, tesorosGoT vacío esperando).
- Rarezas: común / poco_común / raro / épico.
- **Performance bonus**: +10% monedas si player mató >70% zombis.
- **Perfect run bonus**: +25% monedas + 15% materiales si Trono terminó oleada con HP completo.

### HUD lateral rediseñado
- 2 líneas: monedas (Bronce/Plata/Oro) + materiales (Cu/Hi/Ac/Va/Ob).
- Cada moneda y material con su color temático (marrón, gris, dorado, violeta, púrpura).
- Render custom con `drawText()` directo (ASCII porque kahlua no procesa escapes UTF-8 `\xHH`).

### Tienda expandida (5 categorías nuevas + rebalance médico/comida)
- **Consumibles**: 3 tiers (individuales baratos → packs medianos → kits grandes). 11 items médicos y de comida.
- **Libros de Guerra**: 15 libros XP de combate (5 lite a 80 bronce, 9 full a 1 silver, 1 legendario a 1 oro).
- **Rasgos Heroicos** (NUEVO): 6 traits positivos. Máximo 1 por vida del personaje.
- **Milagros del Maestre** (NUEVO): 5 cura traits negativos. Máximo 1 por vida del personaje.
- **Botón "[TEST] DARME"** en panel F10: da monedas/materiales/items para testing rápido.
- Scroll vertical con paginación (6 filas + botones ▲/▼).
- Header con colores por moneda/material.

### Bugs aprendidos a la fuerza (APIs de B42 distintas)
- `Base.FirstAidKit`, `Base.WaterBottleFull`, `Base.Alcohol`, `Base.Hat_ArmyHelmet`, `Base.Vest_BulletKevlar` NO existen en B42. Reemplazados por items reales: `Base.AlcoholBandage`, `Base.AlcoholedCottonBalls`, `Base.WineBottle`, `Base.Hat_Hardhat`, `Base.Vest_HighVis_Blue`.
- `Perks.FromString("Strength")` puede devolver nil → agregado fallback a `Perks[name]`.
- `getTraits():add()` cambió API → cascada de 4 APIs intentadas (descriptor:getTraits():add, getTraits():add, TraitFactory:applyToPlayer, HasTrait+add).
- `traits:contains()` no existe → reemplazado por `jugador:HasTrait()`.
- `stats:setHunger(0)` puede haber cambiado a `setHunger(0.0)`, agregado `getNutrition():setCalories()` como fallback.
- `bd:isInfected()` puede no existir → cascada de APIs + validación defensiva (si no podemos verificar, dejamos pasar).
- ñ/tildes en strings de UI: el font de PZ B42 NO renderiza UTF-8 multi-byte. Solo ASCII puro en labels y drawText. Identificadores Lua tampoco soportan ñ (kahlua).

### UI fixes pre-commit
- Header de tienda: panel ampliado a 820px, labels reposicionados a x=220 para no cortarse.
- Header con colores por moneda/material (Saldo y Materiales).
- Bug crítico Z-order: click derecho del mundo no funcionaba cuando estaba el overlay del Trono PNG abierto. Causa: faltaba `onRightMouseDown` y `onRightMouseUp` devolviendo false en HoldoorOverlayUI. ISUIElement por default devuelve true en handlers de mouse y consume eventos.

### Pendiente para próximos sprints (en `next_steps.md`)
- Tutorial de bienvenida + about-me + footer creador + botón reportar bugs (sprint #2).
- i18n ES + EN (sprint #3-#4).
- "Raise up John Snow" — seguro de vida (sprint #5).
- Sprite custom iso del Trono (nice to have).
- MVP2 White Walkers.

---

## 2026-06-13 — Confirmación empírica: PZ carga del Workshop/42/

**Idea de Nahuel:** agregar un botón al panel del mod que muestre desde qué ubicación del filesystem cargó el HoldoorUI.lua. Cada copia (source / mods / Workshop/media / Workshop/42) tiene un identificador distinto en `HoldoorUI._UBICACION`. Al apretar el botón, PZ revela la verdad.

**Resultado:** botón "TEST UBICACION" muestra `[HOLDOOR] Mod cargado desde: WORKSHOP 42 (overlay B42)`.

**Conclusión:** confirmado al 100% que PZ usa **solo** `Zomboid/Workshop/Holdoor/Contents/mods/Holdoor/42/`. Las otras 3 ubicaciones son irrelevantes a nivel runtime. Esto explica retroactivamente todo el caos del 12: cuando borré la `42/`, PZ cayó al fallback `Workshop/media/` que tenía el commit inicial — sin Trono, sin F10.

**Implicancia operativa:** el script de sync de `infra.md` debe priorizar mantener la `42/` actualizada. Las otras dos copias del filesystem (mods/ y Workshop/media/) se sincronizan "por consistencia" pero PZ no las usa.

**Otras mejoras de esta sesión:**
- Lista ampliada de sprites candidatos para el Trono (`couches_01_X`, `chairs_01_X`, `chairs_02_X` con varios índices).
- `HoldoorServer.testSprite(nombre)` — replanta el Trono en la base con un sprite específico desde la Lua Command Line.
- `HoldoorServer.testSpriteAqui(nombre)` — variante que planta donde está parado el player.
- Botón "TEST UBICACION" en el panel del F10 (queda como herramienta de diagnóstico permanente).

**Pendiente activo:** encontrar el sprite vanilla que mejor queda visualmente para el Trono. Si ninguno convence, plan B = sprite custom PNG del Trono de las Cien Espadas.

---

## 2026-06-13 — Visual del Trono de Hierro + balance de combate

**Logros de la sesión:**

### Visual del Trono (camino C0 — overlay PNG flotante)
- Implementado overlay UI fullscreen (`HoldoorOverlayUI` derivado de `ISUIElement`) que dibuja la PNG real del Trono de Hierro encima del tile de la forja vanilla (`crafted_01_16`).
- La PNG (~1.5 MB, 1024x1024) vive en `media/textures/Holdoor_TronoHierro.png` y se replica a las 4 ubicaciones del mod al sincronizar.
- API de render que funciona en B42: `self:drawTextureScaled(texture, x, y, w, h, alpha)` (6 args). NO funciona `getRenderer():render(...)` con 9 args ni `drawTextureScaledColor` con 9 args — la firma esperada es distinta.
- API de coords mundo→pantalla que funciona en B42: `IsoUtils.XToScreenExact(x, y, z, ofs)` con **4 args**, NO 5. Mi código original con `(x, y, z, 0, 0)` rompía.
- Posición/tamaño del overlay: W=180, H=270 a zoom 1, offset Y = `H * 0.72` (proporción del alto que sale arriba del tile).
- **Transparencia por proximidad**: cuando player o cualquier zombi están a ≤4 tiles del Trono, el alpha baja proporcional (min 0.3, max 1.0). Cache de 100ms para no iterar zombis cada frame (eficiente).

### Estructura del Trono lógica
- Layout final: **1 sola pieza** = la forja `crafted_01_16` con 1500 HP.
- Decisión: el sistema de "respaldo + forja" o "cruz de 5 piezas" se descartó porque las rejas vanilla son saltables por zombis y se veían apiladas/feas.
- La forja `crafted_01_16` es alta, maciza y los zombis la atacan sí o sí (no la saltan).
- Game over cuando HP de la forja llega a 0.

### Re-aggro reverteado
- Se intentó cambiar `_reAggroZombies` para hacer path DIRECTO a la forja y subir frecuencia a 4s. Resultado: peor que antes — zombis se amontonaban torpemente.
- Revertido al comportamiento original: path aleatorio en radio del 30% del spawn, cada 12s. **El bug NO era la frecuencia, era el target específico.**

### Mejoras de balance de oleada
- **Colchón de zombis** (`_asegurarColchon`): cada 3s durante oleada activa, si vivos cerca de la base < 5 Y hay encolados pendientes, forzar `_spawnTanda` inmediato con tamaño reducido. Evita que el user tenga que ir a buscar zombis lejanos.
- **Limpieza al terminar oleada**: en `_oleadaCompletada`, llamar `_limpiarZona()` antes de fase pausa. No quedan zombis residuales vagando.
- **Limpieza al game over (Trono caído)**: en `_tronoCayo`, llamar `_limpiarZona()`. No tiene sentido que sigan zombis después de perder.

### Comandos de diagnóstico agregados (vivos en HoldoorServer)
- `testSprite(name)`, `testSpriteAqui(name)`, `testTronoCompuesto(sprites, ancho)`, `testGaleria(N)`, `dejarTile(name)`, `apilarTile(name)`, `deshacerTile()`, `borrarTileAqui()`, `moverUltimoAqui()`, `dumpTrono()`, `matarZombiesCerca(radio)`.
- Solo accesibles vía Lua Command Line del debugger. No molestan al jugador.
- Útiles para investigar nuevos sprites, debug, o futuras adiciones al mod.

### Bugs / aprendizajes técnicos
- En B42, no se puede crear un IsoThumpable con cualquier sprite name: si el sprite no existe, el thumpable se crea invisible pero igual ocupa el tile. **Hay que validar con `IsoSpriteManager.instance:getSprite(name)` antes de plantar.**
- Los sprites **indoor** (couches, chairs) en B42 NO renderizan correctamente al aire libre (requieren estar dentro de un IsoRoom). Por eso terminamos usando solo **outdoor / carpentry / industry / constructed / fencing**.
- Los **cadáveres siguen siendo `IsoZombie`** después de morir → el damage boost los contaba como zombis vivos. Fix: filtrar `not obj:isDead()`.
- La firma de `IsoUtils.XToScreenExact` en B42 es **4 args** (`x, y, z, offsetXorY`), no 5.
- La firma de render de textura útil en B42 es `self:drawTextureScaled(texture, x, y, w, h, alpha)`. Los otros métodos (`drawTextureScaledColor` con 9 args, `getRenderer():render` con 9 args) NO están implementados o tienen otra firma.
- Para el render del overlay UI: hay que usar un `ISUIElement` fullscreen + sobreescribir `render()`. Calcular coords mundo→pantalla con `IsoUtils.XToScreenExact` y ajustar por zoom (`getCore():getZoom(0)`).

**Pendiente activo (ver `next_steps.md`):**
- Próximo sprint: **ajuste de drops + balance de tienda**.
- Nice to have lejano: sprite custom isométrico real del Trono (camino C2). Requeriría TileZed + arte de pixel art skill medio-alto.

---

## Sprint v0.5 final — Tienda estabilizada + sistema de Traits B42 + Boosters (2026-06-15)

**Contexto:** después de cerrar la base v0.5 (HP variable / drops generosos / HUD lateral / etc.), faltaba estabilizar el catálogo de la tienda: Rasgos Heroicos y Milagros del Maestre no aplicaban en B42, los precios estaban totalmente desproporcionados respecto a la economía real, faltaba feedback al usuario y faltaba una categoría completa (boosters/energizantes).

### 1. Rasgos Heroicos + Milagros — API B42 descubierta a mano

**Problema:** TODAS las APIs de traits viejas de B41 (`TraitFactory`, `addStringTrait`, `addTrait`, `getTraits():add`) son **nil en B42** tanto en server como en cliente. El intento de aplicar un trait crasheaba con "Object tried to call nil" que **kahlua NO atrapa con pcall**.

**Diagnóstico:** leyendo el código vanilla de PZ B42 (`media/lua/client/ISUI/PlayerStats/ISPlayerStatsUI.lua:594` + `server/XpSystem/XpUpdate.lua:209+`) descubrimos la API real:

```lua
-- Agregar trait
local enum = CharacterTrait[idMayusculasSnake]   -- ej "STRONG", "OUT_OF_SHAPE"
player:getCharacterTraits():add(enum)
player:modifyTraitXPBoost(enum, false)
SyncXp(player)

-- Quitar trait
player:getCharacterTraits():remove(enum)
player:modifyTraitXPBoost(enum, true)
SyncXp(player)
```

**Detalles clave:**
- `:add()` / `:remove()` requieren el **objeto `CharacterTrait` enum**, no string. Pasar string da `expected argument of type CharacterTrait, got String`.
- El enum se accede con `CharacterTrait["STRONG"]` (UPPERCASE_SNAKE).
- IDs alternativos como string ("strong" en minúscula) NO los acepta `getCharacterTraitDefinition()` con string puro.
- **Server context NO tiene acceso al namespace `CharacterTrait`** — toda la lógica de traits vive del lado cliente.

**Solución arquitectónica:** el server cobra y guarda flag en ModData del player; manda `sendServerCommand` al cliente con `aplicarTrait`/`curarTrait`; el cliente resuelve el enum y aplica. Para SP también hay fallback directo `HoldoorClient.aplicarTraitLocal()` (server y cliente comparten VM).

**Catálogo definitivo (15 items):**
- 6 Rasgos Heroicos: STRONG / ATHLETIC / BRAVE / EAGLE_EYED / NIGHT_VISION / IRON_GUT.
- 9 Milagros: WEAK / THIN_SKINNED / OUT_OF_SHAPE / ASTHMATIC / HEMOPHOBIC / SMOKER / SLOW_HEALER / COWARDLY / OBESE.
- Todos validados in-game (compré los 6 Heroicos secuenciales con restricción desactivada para testing).

### 2. Validación pre-compra + modal de confirmación

**Problema:** podías comprar STRONG aunque ya tuvieras STRONG (se cobraba sin efecto), o comprar Bendición del Cuervo (cura ASTHMATIC) sin ser asmático.

**Fix:** función expuesta `HoldoorClient.tieneTrait(id)` que usa `getCharacterTraits():getKnownTraits():contains(enum)` con fallback a `HasTrait`/`hasTrait`. La validación se ejecuta en `HoldoorShopPanel:onComprar` ANTES de mostrar el modal:
- Heroico + ya lo tenés → toast "Ya tenes ese rasgo" y se acaba (sin modal).
- Milagro + no lo tenés → toast "No tenes ese rasgo, no hay nada que curar".
- Pasa la validación → modal `ISModalDialog` "ATENCION: solo podes invocar UN X por vida. Confirmás?".

**Indicador en UI** ("YA USADO"): cuando el player ya compró su trait/milagro de vida, los OTROS items de la misma categoría muestran `"Limite 1 por vida alcanzado"` y SOLO el item efectivamente comprado muestra `"Ya invocado por este personaje"`. Antes mostraba el nombre del trait comprado en TODOS los items y confundía.

### 3. Toast UI arriba de pantalla — `HoldoorToast`

**Problema:** `player:Say()` (sobre la cabeza del personaje) queda tapado por el panel de tienda. Los mensajes [HOLDOOR] no se leían.

**Fix:** nuevo `HoldoorToast` similar a `HoldoorAnnounce` pero compacto, posicionado a y=90 desde el top, una sola línea, fade in/out, duración 3s. `HoldoorClient.chat()` ahora dispara ambos: el `Say()` clásico + el toast nuevo.

Visible POR ENCIMA de la tienda.

### 4. Rebalanceo total del catálogo

**Conversión usada** (basada en precios de Materiales como referencia): `1 Valyrio = 1 Obsidiana = 1 Oro = 250 Bronce`; `1 Acero = 1 Plata = 50 Bronce`.

**Economía estimada por partida NORMAL:** ~120 Bronce + ~1-2 Plata + ~1 Oro = ~500 br equivalente.

Antes del rebalanceo: Strong costaba **2250 br equivalente** (15 partidas Normal). Después: **750 br** (3 partidas). Reducción general ~60%.

**Heroicos (objetivo `~Cost vanilla × 75`):**
- STRONG/ATHLETIC (cost 10): 3 Oro
- BRAVE/EAGLE_EYED (cost 4): 1 Oro + 1 Hierro
- NIGHT_VISION (cost 3): 4 Plata + 2 Hierro
- IRON_GUT (cost 2): 3 Plata + 1 Hierro

**Milagros (mismo principio sobre |cost|):**
- WEAK (10): 3 Oro
- THIN_SKINNED (8): 2 Oro + 1 Acero
- OUT_OF_SHAPE (6): 2 Oro
- ASTHMATIC / HEMOPHOBIC (5): 1 Oro + 2 Acero
- SMOKER / SLOW_HEALER (3): 4 Plata + 2 Acero
- COWARDLY / OBESE (2-0): 2 Plata + 1 Hierro

**Libros de Guerra — XP multiplicado:**
- Lite: 250 → **2000 XP** (×8), 50 Br + 1 Hi
- Full: 500 → **5000 XP** (×10), 80 Br + 1 Hi
- Legendario: 1000 → **15000 XP** (×15), 3 Plata + 1 Hi (antes 1 Oro + 1 Valyrio).

### 5. Lujos ampliados (2 nuevos)

- **Vino del Otoño** (1 Plata) — `Base.WineBottle` al inventario.
- **Reliquia del Septón Supremo** (5 Plata + 1 Obsidiana) — pack mega-médico (5 vendas esterilizadas + 5 antibióticos + 5 pastillas + 3 algodones con alcohol).

Festín de Invernalia rebajado de 3 → 2 Plata.

### 6. NUEVA categoría: **Boosters** (7 items)

**Motor extendido** — agregué `panic` / `unhappy` / `drunk` / `pain` al tipo `restore` en `HoldoorServer.lua:282+`. Pcall-cascade defensivo porque las APIs B42 pueden tener nombres distintos según versión (`setUnhappynessLevel` / `setUnhappyness`).

**Items:**
- Café del Norte (25 Br + 1 Hi) — fatigue + endurance + boredom.
- Hidromiel del Valle (30 Br + 1 Hi) — stress + panic + unhappy.
- Tónico del Maestre (1 Plata) — endurance + fatigue + pain.
- Hojaroja de Asshai (40 Br) — panic + stress.
- Antídoto del Bardo (15 Br) — drunk + unhappy.
- Sangre del Dragón (2 Plata + 1 Valyrio) — fatigue + endurance + panic + pain + stress.
- Polvo del Susurro (3 Plata + 1 Obsidiana) — stim completo (7 stats).

Pensados para usarse pre-oleada o emergencia. Efecto instantáneo, no van al inventario.

### Bugs / aprendizajes técnicos clave

- **`type(obj.method)` en kahlua devuelve `"nil"` para métodos Java aunque el método EXISTA** — los métodos Java de PZ se exponen via metatable, no como fields del userdata. NUNCA chequear con `type()` antes de llamar.
- **`pcall` en kahlua NO atrapa `"Object tried to call nil in pcall"` ni `"attempted index nil"`** consistentemente — esos errores escapan al log igual aunque el flujo continúe. Hay que verificar previamente si los namespaces/métodos no son nil con check explícito `if X == nil then`.
- **`CharacterTrait` y `TraitFactory` viven en namespace CLIENT-side** en B42 — server no tiene acceso. Todo lo de traits hay que delegarlo al cliente vía `sendServerCommand`.
- **`getCharacterTraits()` devuelve un objeto Java `CharacterTraits`** que tiene `:add(CharacterTrait)`, `:remove(CharacterTrait)`, `:getKnownTraits()` (lista con `:contains`/`:get`/`:size`). NO confundir con `getTraits()` (B41, no existe en B42).
- **IDs de traits B42** definidos en `media/scripts/generated/characters/character_traits.txt` con prefijo `base:nombre`. El mapeo enum es `base:strong` → `CharacterTrait.STRONG`, `base:out of shape` → `CharacterTrait.OUT_OF_SHAPE`, `base:irongut` → `CharacterTrait.IRON_GUT`.

**Pendiente activo (ver `next_steps.md`):**
- Sistema de Jefes de Oleada (sprint diseñado, no implementado — Opción C/D de la discusión).
- Tutorial wizard + about-me + footer (sprint #1).
- i18n ES/EN (sprint #2-#4).
- Raise up John Snow (sprint #5).

---

## Sesión 2026-06-15 — Bugfixes intensos + diseño Sprint v0.6 (modelo C híbrido)

**Resumen ejecutivo:** sesión MUY larga (~10h) de bugfixes post-merge v0.5 + diseño del refactor mayor que se ejecuta mañana. Encontramos y arreglamos 7 bugs estructurales en cascada, descubrimos la causa raíz del bug histórico del hover del inventario, y diseñamos completamente el modelo C híbrido (timer + target de kills) que reemplazará el sistema de oleadas en v0.6.

### Bugfixes aplicados (8 fixes, todos sincronizados a Workshop/42)

**1. Catálogo tienda — APIs B42 + UTF-8 + nombres**
- Acentos/ñ en `nombre`/`desc` aparecen como `?` en UI → cambiados a ASCII puro ("Café" → "Cafe", "Otoño" → "Otono").
- Eliminado "Reliquia del Septón" de Lujos (redundante con Botiquín de Consumibles).

**2. Boosters category (motor `restore` con API B42 real)**
- `stats:setFatigue(0)` y similares **NO existen** en B42 → reemplazados por `stats:set(CharacterStat.<ENUM>, val)`.
- Confirmado en `media/lua/shared/Foraging/forageSystem.lua` vanilla.
- Mapping completo: hunger / thirst / fatigue / endurance / stress / boredom / panic / unhappy (UNHAPPINESS, no Unhappyness) / drunk (INTOXICATION) / pain.
- Gotcha #19 reescrito con la API correcta.

**3. Magia de Asshai (cure_bite) — API B42**
- `bd:setInfected(false)` global NO existe en B42 → iterar body parts con `SetBitten(false)` / `SetInfected(false)` / `SetFakeInfected(false)` (capital S).
- Confirmado en `server/ClientCommands.lua:495+` (cheat de body parts).

**4. Comando `/holdoor` en MP no abría panel**
- Método ISChat renombrado en B42: `sendCurrentInputText` (B41) → `onCommandEntered` (B42).
- Además ISChat copia la referencia del método al `textEntry` al crearse (`textEntry.onCommandEntered = ISChat.onCommandEntered`) → hookear la clase NO funciona, hay que hookear `ISChat.instance.textEntry` directamente.
- Reintento via `OnTick` cada ~1s hasta que ISChat esté disponible (en MP carga después de OnGameStart).
- Gotcha #20 creado.
- **Pendiente:** host del server no se detecta como admin nativamente → tarea para mañana.

**5. Hover del inventario roto (bug HISTÓRICO resuelto)**
- Paneles fullscreen del mod consumían eventos del mouse aunque los handlers Lua devolvieran false.
- Causa raíz: `ISUIElement` tiene `wantMouseEvents=true` por DEFAULT (línea 1998 vanilla). Los handlers Lua son **cosméticos**; el motor Java decide capturar según el flag `consumeMouseEvents` del javaObject.
- Fix: `self:setWantMouseEvents(false)` en `:initialise()` de cada panel fullscreen decorativo.
- Aplica a: `HoldoorOverlay`, `HoldoorAnnounce`, `HoldoorToast`, `HoldoorOverlayUI`.
- NO aplica a `HoldoorHUD` (tiene botones interactivos).
- Gotcha #21 creado — **este resuelve también el bug histórico del click derecho del Trono** (gotcha #15) que veníamos arrastrando hace 2 sesiones.

**6. Limpieza de zombies en MP — `removeFromWorld` → `setHealth(0)`**
- `z:removeFromWorld()` deja zombies "fantasma" en clientes MP que reaparecen al re-sync del chunk.
- Fix: `z:setHealth(0)` en `_limpiarZona()` — flujo normal de muerte, sincronizado en todos los clientes.
- **Side effect descubierto:** dispara eventos `OnZombieDead` que decrementan `zombiesRestantes` de la oleada nueva (porque la limpieza pasa antes de setear el counter). Resuelto con contador `_zombiesIgnorarN` que descarta los próximos N eventos.
- Gotcha #22 creado.

**7. Botón "DETENER OLEADAS" no mataba zombies**
- En SP, `HoldoorClient.detener()` mutaba estado del server directo, salteándose `HoldoorServer.detener()` que tiene la limpieza.
- Fix: SP también llama `pcall(HoldoorServer.detener, player)` igual que iniciar/oleadaManual/setBase.

**8. Colchón "refuerzo final" en bucle**
- Mi fix anterior usaba `vivos` (cerca del radio) para gatillar refuerzo de cierre → si quedaban zombies lejos, vivos<3 disparaba cada 3s en bucle (total subía y bajaba).
- Fix: usar `zombiesRestantes` (total real del mod) + flag `_colchonFinalDisparado` single-shot por oleada (se resetea en `_lanzarOleada`).

**9. `next()` reemplazado por iteración con `pairs`**
- En 3 ubicaciones de `_distribuirRecompensaOleada` y `_distribuirMateriales`, `next(t)` tiraba "Object tried to call nil" → probable override de otro mod global.
- Fix defensivo: `for _k, _ in pairs(t) do _hay = true; break end`.

**10. Base no persiste entre sesiones (feature)**
- Antes la base + Trono físico sobrevivían al cargar partida → confuso.
- `HoldoorServer.resetearBaseAlInicio` en `OnGameStart` busca el Trono físico en (baseX, baseY) y destruye sus piezas (filtradas por sprite name del layout — no afecta otros muebles).
- Cliente también limpia ModData global del mod al iniciar.

### Features agregadas

**a) Botón "Quitar base / Trono"** en panel F10
- Destruye IsoThumpable del Trono + resetea estado + limpia ModData.
- Modal de confirmación porque no es reversible.
- Bloqueado durante oleada activa.

**b) Toast superior `HoldoorToast`** (creado al inicio de sesión)
- Cartel compacto en franja superior (y=90) con fade in/out.
- Una línea, configurable por color.
- Renderiza POR ENCIMA de la tienda y otras UIs.
- `HoldoorClient.chat()` ahora dispara `player:Say()` + toast (excepto separadores decorativos `===`/`---` que filtra para no spam).

**c) Frases épicas movidas al toast superior**
- "Valar Morghulis -- Hodor" antes salía sobre la cabeza del personaje y se tapaba con cartel grande centrado.
- Ahora aparecen como toast dorado arriba — claras y legibles.
- TODO el resto del flujo de anuncios queda IGUAL (cartel grande centrado, chat con `===`, etc).

**d) Reorganización del panel F10**
- Fila 1: Marcar mi base | Quitar base / Trono (acciones de base)
- Fila 2: INICIAR OLEADAS | DETENER OLEADAS (control de oleadas)
- Fila 3: Forzar oleada (full ancho, manual override)
- Fila 4-5: TEST DARME + Cerrar
- Eliminado el botón huérfano que quedaba solo en una fila.

### Diseño cerrado para Sprint v0.6 (próxima sesión)

**Modelo C híbrido — timer + target de kills:**
- Cada oleada dura T segundos fijos.
- Spawnea zombies continuamente con curva creciente (intervalo decrece con el tiempo).
- Cierra por **lo que pase primero**: matás target → CIERRE LIMPIO (+25%), vence timer → SOBREVIVISTE (recompensa base), o Trono cae → game over.

**Decisiones lockeadas:**
- Duración Normal: ~25 min total partida (Opción A confirmada).
- Pausa entre oleadas: **30s** (relajado, da tiempo a tienda).
- Multiplicadores por modo: Fácil 0.8× / Normal 1.0× / Difícil 1.1× / Pesadilla 1.2× (duración).
- HUD nuevo: "⏱ Tiempo: 2:34 | 🎯 Kills: 23/60" (reemplaza "Zombis X/Y").
- Anuncios menores → toast / mayores (ÚLTIMA OLEADA, VICTORIA, TRONO CAÍDO) → centrados épicos.

**Estimación:** ~5h de refactor concentrado. Plan completo en `next_steps.md` sección 0.

### Aprendizajes técnicos consolidados (gotchas nuevos)

- **#20** — ISChat `onCommandEntered` reemplaza `sendCurrentInputText` en B42 + hay que hookear `textEntry`, no la clase.
- **#21** — `setWantMouseEvents(false)` es la API real para paneles fullscreen transparentes al mouse (los overrides Lua son cosméticos).
- **#22** — En MP, NUNCA `removeFromWorld()` zombies — usar `setHealth(0)` (sincronización natural).

Gotcha #19 (motor `restore` con stats B42) reescrito completo con la API real `CharacterStat` enum.

### Cosas que NO se hicieron / quedan pendientes para mañana

1. **Validar los 8 bugfixes con cierre completo de PZ** — varios cambios aplicados durante la sesión pero sin un test limpio post-reload.
2. **MP: host no detectado como admin nativo** — investigar API alternativa (probablemente `isServer()`).
3. **Sprint v0.6 — refactor modelo C** — sesión dedicada mañana.
4. Sistema de Jefes de Oleada (post-v0.6).

### Notas del equipo (proceso)

- Sesión emocionalmente intensa — varios ciclos de "fix → bug nuevo → revert → fix correcto". Aprendizajes:
  - **NO mover funcionalidades visuales sin que el user confirme exactamente lo que quiere** — el user me cazó moviendo el cartel grande centrado al toast sin haber acordado eso explícitamente.
  - **Lua del mod NO se recarga al volver al menú principal** — solo al cerrar PZ entero. El user lo sabía y yo no le creí al principio (me equivoqué — el user tenía razón sobre crear nuevo personaje).
  - **Cuando el user dice "tengo razón" sobre comportamiento del juego, tomar como dato** — no como hipótesis.

**Cierre del día:** mod en estado funcional pero con bugs pendientes de validar. Mañana arrancamos Sprint v0.6 limpio con cabeza fresh.

### Fix bonus de cierre — MP host detection con `isCoopHost()` (validado in-game)

Antes de cerrar, Nahuel montó un MP server hosted para validar. El comando `/holdoor` y F10 fallaban con "Solo el host puede" porque el host se reporta como `AccessLevel="user"` en B42 hosted mode.

**Primer intento (fallido):** agregué `if isServer() then return true end` en `esAdmin()`. NO funcionó — `isServer()` devuelve false en hosted (solo es true en dedicated server process).

**Fix real:** **`isCoopHost()`** es la API correcta para detectar al host de MP hosted. Confirmado en código vanilla B42 (`InviteFriends.lua:338`, `ISJoyPadListBox.lua:12`).

Nueva cascada en `esAdmin()`:
1. `not isClient()` → SP puro → admin
2. `isCoopHost()` → host hosted → admin ⭐ (caso típico)
3. `isServer()` → dedicated server process → admin
4. `getAccessLevel()` matches admin/moderator/gm/overseer → admin
5. Cualquier otro → no admin

**F10 habilitado en MP también:** antes había return temprano si `isClient()` o `isServer()` eran true. Ahora pasa por `esAdmin()` — el host hosted puede usar F10 directo, igual que SP.

**Gotcha #23 creado** con la API correcta + refs vanilla.

**Validado in-game por Nahuel:** F10 y `/holdoor` funcionan correctamente en MP hosted. El log muestra `[Holdoor] esAdmin: detectado como CoopHost → admin OK`.

**Estado v0.5.1 al cierre real:** completamente listo para subir a Steam Workshop. Mañana arrancamos Sprint v0.6.

---

## Sprint v0.6 — Modelo C híbrido (timer + target kills) + Cúmulos + Drops live (2026-06-15)

**Contexto:** sprint de refactor mayor del motor de oleadas. Pasamos del modelo "total fijo de zombies por oleada" (v0.5) al modelo C híbrido (v0.6): cada oleada dura T segundos con stream continuo de zombies. Cierre por target kills (cierre limpio +25%) o por timer (sobreviviste, recompensa base) o trono cae (game over). Elimina el "zombie hunting" final.

**Resumen de cierre:** modelo C funcional + drops live por kill + cúmulos de zombies. Sin testing exhaustivo en los 4 modos (solo TEST y Normal probados a fondo). 5 pendientes anotados para próxima sesión.

### Cambios clave (orden temporal)

**1) Refactor del motor de oleadas**
- `_lanzarOleada` reescrito: lee `modosV6` (mults duración/spawn/kills/recompensa) + `oleadasV6` (curva base por # oleada).
- `_spawnTick` reemplaza `_spawnTanda`: spawn continuo con curva lerp(spawnInicio→spawnFin) según progreso temporal.
- `_chequearCierreOleada`: cierre por kills >= target (CIERRE LIMPIO, flag `cierreLimpio=true`) o por timer (`elapsed >= duracionSeg`).
- `onZombieMuerto` simplificado: incrementa `oleadaKills`, dispara `_rollDropsPorKill`. Sin `zombiesRestantes` (no existe en modelo C).
- Eliminado del flow: `_asegurarColchon`, `encoladosTiers`, `_spawnTanda`, counter "Zombis X/Y".

**2) Config v0.6 en HoldoorConfig.lua**
- `modosV6` con mults por modo (fácil 0.8× / normal 1.0× / difícil 1.1× / pesadilla 1.2× duración).
- `oleadasV6` con 12 entradas de curva base (8 normales + 4 extras para difícil/pesadilla).
- `pausaOleadasSegV6 = 30s` (TEST: 5s override).
- `cierreLimpioBonus = 0.25` (+25% recompensa).
- `aggroIntervalSec/Radio/Volumen` para aggro sostenido.
- `dropPorKillBase` (chances bronce/plata/oro/item por kill).
- `dropMultPorModoV6` (multiplicadores por dificultad).
- `dropMaterialesPorKillBase` (Cuero 5% / Hierro 2% / Acero 1% / Valyrio 0.1% / Obsidiana 0.1%).
- `recompensaFinOleadaMultV6 = 0.60` (rebalance — kills dan monedas live, fin oleada baja al 60%).

**3) Cúmulos (sistema clave por feedback de Nahuel)**
- Spawn perdigonado (1 zombi por tick) era anti-climático y los zombies venían lentos en hilera.
- Refactor: `_spawnTick` ahora spawnea **grupos de 2-5 zombies juntos** en tiles adyacentes alrededor del ángulo elegido. Comparten destino. Se sienten como horda real.
- Cluster apretado: offset random -2 a +2 alrededor del centro del cúmulo.
- Cada cúmulo arranca con sonido localizado (`addSound`) para reforzar agresividad.

**4) Aggro real (combinación 2 mecanismos)**
- `_aggroSostenido` cada 4s: hace `addSound(nil, baseX, baseY, baseZ, radio=120, vol=200)` (atrae lejos) + llama `_reAggroZombies` (path explícito de cercanos).
- `_reAggroZombies` (recuperado del modelo viejo): itera IsoZombies cercanos al cell y fuerza `pathToLocation(destX, destY, destZ)` hacia tile cerca del Trono.
- `addSound` solo no alcanza en B42 (zombies pasivos). El `pathToLocation` explícito garantiza agresividad.
- Print diagnóstico en aggro: `[Holdoor] AGGRO sound radio=X vol=Y ok=true/false`.

**5) Drops por kill (live)**
- `_rollDropsPorKill` en cada `onZombieMuerto`:
  - **Bronce** (silencioso, `player:Say` sobre cabeza): 20-35% chance escalado por modo.
  - **Plata** (toast amarillo + Say): 2-12% chance.
  - **Oro** (toast dorado épico + sonido `LevelPerk`): 0.1-3% chance.
  - **Item raro** (toast violeta + sonido): 0.3-2% chance, validado con `InventoryItemFactory.CreateItem` antes de notificar (evita toasts fantasma de items que no existen en B42).
  - **Materiales** (Cuero/Hierro/Acero/Valyrio/Obsidiana): 5/2/1/0.1/0.1% chance escalado por modo. Solo 1 material por kill (si cae Cuero, no rolea más raros).
- Drops sobre la cabeza del personaje vía `player:Say()` además del toast superior.

**6) HUD nuevo modelo C**
- Reemplaza "Zombis X/Y" por:
  - `⏱ Tiempo: 2:34` (countdown del timer)
  - `Kills: 23 / 50` (vs target)
- Header en oleada activa: `OL.3 NOR 23/50` (kills vs target en vez de zombies vivos).
- `lblFzaHUD` durante pausa/preparación: muestra `Siguiente: ~X kills` (target de oleada N+1).
- Refresh cada 1s durante fase activa (antes era cada 2s — segundero saltaba de a 2).
- Radar deshabilitado (`mostrarRadar = false` hardcoded — código comentado, no eliminado).

**7) Anuncios**
- Frases épicas (Valar Morghulis) movidas al toast superior (antes player:Say sobre cabeza se tapaba).
- Toast `HoldoorToast.mostrar` con duración 3s + fade in/out.
- Toast de CIERRE LIMPIO en pausa: `"CIERRE LIMPIO! +25% recompensa (X/Y kills)"` + sonido.
- Cartel grande centrado `HoldoorAnnounce` se mantiene para OLEADA inicio/completada y eventos épicos (ÚLTIMA OLEADA, VICTORIA, TRONO CAÍDO).

**8) Botón "Quitar base/Trono" mantenido**
- Layout panel F10 reorganizado en 2 columnas:
  - Marcar mi base | Quitar base / Trono (acciones de base)
  - INICIAR OLEADAS | DETENER OLEADAS (control oleadas)
  - Forzar oleada (full ancho, secundario)
- Modal de confirmación al Quitar (destruye IsoThumpable + resetea ModData).

**9) HP Trono reset al iniciar nueva instancia**
- Cuando `HoldoorServer.iniciar()` corre, antes de empezar oleadas: itera piezas del Trono y `setHealth(maxHP)`. Cada nueva sesión arranca con Trono full.

**10) HP Trono rebalanceado** (feedback de Nahuel: 1000-1500 era demasiado, los zombies no podían romperlo nunca)
- Fácil: 1500 → 600
- Normal: 1250 → 500
- Difícil: 1100 → 400
- Pesadilla: 1000 → 300

**11) radioSpawn default = 15 tiles** (eran 20-30, los zombies tardaban mucho en llegar)
- Cambio en los 5 modos del config.
- Slider del panel F10 sigue ajustable por user (10-100).
- Spawn real = `radioSpawn + 5` (al borde del círculo del user).

**12) Speed = 2 (Fast Shamblers, NO Sprinters)**
- Speed 1 = Sprinters BUGGY en B42 (no pathean bien).
- Speed 2 = Fast Shamblers (caminan rápido, lo correcto).
- Sprinter sigue siendo speed=3 cuando es corredor.

**13) Fix bug clave: kills/monedas no contaban durante limpieza pre-oleada**
- Antes: `_zombiesIgnorarN` contaba "próximas N muertes a ignorar". Pero `OnZombieDead` es async → si user mataba zombies mientras la limpieza estaba procesándose, sus kills se "absorbían" por el contador.
- Fix: cambiado a sistema por TIEMPO (`_zombiesIgnorarHasta = os.time() + 2`). Ventana de 2s post-limpieza, después todo cuenta.
- Mismo fix en cliente: `_killsIgnorarHasta`.

**14) Bug del `estado.modoId` que nunca se asignaba**
- `_lanzarOleada` leía `estado.modoId` que era nil → fallback a "normal" siempre.
- Modo TEST se trataba como Normal → target 30 en lugar de 9.
- Fix: leer de `estado.config.modoId` que SÍ se asigna en `iniciar()`.

**15) Bug crash al CIERRE LIMPIO**
- En cliente, `pcall(function() getSoundManager():PlayUISound("LevelPerk") end)` crasheaba con "Object tried to call nil in pcall" (gotcha #18: kahlua no atrapa este error).
- Fix: usar la helper `playUISound("LevelPerk")` ya definida (con check `soundsEnabled` + pcall propio).

**16) HUD label "Siguiente" actualizado para modelo C**
- Antes calculaba con `tamanoOleada * escala` (lógica vieja).
- Ahora lee `oleadasV6[N+1].targetKills × multKills` del modo.
- Texto: `"Siguiente: ~50 kills"` en vez de `"Siguiente: ~11 zombis"`.

### Pendientes que quedaron sin atacar (próxima sesión)

1. **Crawlers/Arrastradores funcionan mal** (oleada 2 TEST con `setCrawler(true)` hardcoded del modelo viejo).
2. **Modo TEST: composición especial por oleada** (oleada 1 lentos / 2 arrastradores / 3 rápidos). En modelo C todas siguen `pctCorredores` que es 0% en TEST.
3. **Bug "llega al target y no termina la oleada"** — Nahuel lo reportó pero capaz era confusión visual. Por confirmar.
4. **Drops de items: validar variedad real** — Nahuel pidió y armé pool ampliado pero falta test casual en partida larga.
5. **Drops de monedas: bajar cantidad** — Nahuel dijo "demasiado, pero por ahora dejalo así". Para rebalancear después.
6. **Textos sobre la cabeza tapándose** — estético, no urgente.
7. **MP host detection vía `isCoopHost`** — funcionó vos solo, falta testear cliente remoto (amigo).

### Aprendizajes técnicos / gotchas nuevos

- **speed=1 en B42 son Sprinters (BUGGY)** — no usar para zombies "rápidos pero no sprinters". Usar speed=2 (Fast Shamblers) que es el equivalente al "caminar rápido". Documentado en gotcha #24.
- **`estado.modoId` no se asigna en este mod** — el modo vive en `estado.config.modoId` solo. Cualquier código que necesite el modo debe leerlo de ahí.
- **`pcall(function() getSoundManager():PlayUISound(...) end)` puede crashear igual** — kahlua no atrapa "Object tried to call nil". Usar siempre helper `playUISound()` que tiene guard + pcall propio.
- **Spawn perdigonado vs cúmulos** — feedback de UX importante: spawnear 1 zombi a la vez se siente débil. Cúmulos de 2-5 juntos con destino compartido cambia completamente la sensación de "horda".
- **`addSound` solo no alcanza para agresividad sostenida** — combinarlo con `pathToLocation` explícito vía `_reAggroZombies` cada 4-5s.
- **Eventos `OnZombieDead` son ASYNC** — al usar `setHealth(0)`, los eventos no son instantáneos. Usar ventanas de tiempo (no contadores) para sincronización.

### Estado al cierre

Mod funcional en SP modo TEST y Normal. HP Trono rebalanceado. Drops live funcionando. Cúmulos visiblemente mejorados. Pendientes documentados para próxima sesión.

**NO testeado:** Difícil, Pesadilla, MP cliente remoto, comportamiento de crawlers, drops de materiales raros (Valyrio/Obsidiana en sesión real).

**Versión:** 0.6-dev (mod.info sigue en 0.5.1, se actualiza al cerrar sprint).

---

## Sprint v0.6.1 — Whitelist items + fix CRÍTICO mouse passthrough + drag del HUD restaurado (2026-06-15)

Sprint correctivo encadenado al v0.6 después del crash + bug crítico del inventario vanilla bloqueado por overlays del mod.

### Contexto

Después de mergear v0.6, al testear drops por kill apareció un **crash al matar zombies** (item inválido en pool de drops + `pcall` no atrapando excepción Java). Al resolver eso, el user reportó un **bug críticamente más severo**: el inventario vanilla de PZ no scrolleaba, no mostraba tooltips al hacer hover, ni respondía al click derecho en la scrollbar. Funcionalidad core del juego rota por culpa de nuestros overlays. **El user lo calificó de "atrocidad" y "obligatorio fixearlo".**

### Implementación — 5 ejes

#### 1. Pool de items 100% validado contra B42 vanilla

**Antes:** pool de 26 items, varios con nombres inventados/desactualizados (`Base.WaterBottleFull`, `Base.WineBottle`, `Base.Shotgun_Shells`, `Base.223Bullets`, `Base.Hat_Hardhat`, `Base.Vest_HighVis_Blue`).

**Ahora:** pool de 52 items, **uno por uno grepeado** contra `C:/Program Files (x86)/Steam/steamapps/common/ProjectZomboid/media/scripts/generated/items/{food,weapon,clothing,literature,normal,drainable,container}.txt`. Categorías: medico (10), comida (10), herramientas (7), municion (5), libros (6), ropa (6), tesorosGoT (8 — armas vanilla con estética GoT: Katana, CrudeSword, WoodAxe, etc).

#### 2. Botón TEST de validación batch en panel admin

`[TEST] DARME TODOS LOS ITEMS DEL POOL` en HoldoorUI.lua. Itera el pool entero, intenta cada item con `getScriptManager():FindItem()` + `inv:AddItem()` bajo pcall, loguea ✅/❌ por item, halo note final con resultado. **No corta si alguno falla**, sigue la tirada completa. Test confirmó 52/52 OK en build actual de B42.

#### 3. Safety net en runtime para items inválidos

Reemplazado `InventoryItemFactory.CreateItem()` (tira excepción Java que escapa pcall) por `getScriptManager():FindItem()` (devuelve `nil` limpio) en `_rollDropsPorKill`. Gotcha #30 lockeado.

#### 4. Items "fantasma" — chances bajadas + notificación de botín

**Bug encontrado:** `_distribuirRecompensaOleada` entregaba ~14 items por oleada en Normal **sin notificación**. El jugador veía el inventario lleno sin saber cuándo le llegaron.

**Fix:**
- `rarezaChances` bajadas: 40/18/6/1.5 → **10/5/2/0.5** (target ~3-5 items/oleada en Normal).
- Cliente muestra al cierre de oleada `Botín: 2x Bandage, 1x Sword, ...` en chat + toast.

#### 5. FIX CRÍTICO — mouse passthrough roto (la batalla larga)

**Descubrimiento clave:** en B42, `setWantMouseEvents(false)` por sí solo NO basta para que un panel sea ignorado del hit-test del mouse de Java. Necesita ADEMÁS uno de estos dos:
- `setVisible(false)` → ignorado completamente
- Rect chico (NO fullscreen) → solo bloquea su propia zona

La gotcha #21 vieja decía que `setWantMouseEvents(false)` era la API real. Esa info era **incompleta**. Se rescribe en gotcha #29 (supersede).

**Diagnóstico iterativo:** se agregaron teclas F11/F12/F9/F8/F7/F6 que toggleaban cada overlay individualmente con `removeFromUIManager`. Después de varias rondas el patrón apareció: los overlays con `setVisible(true)` permanente bloqueaban; el único que NO bloqueaba era `HoldoorAnnounce` porque arrancaba `setVisible(false)`.

**Trampa cazada:** los propios mensajes de TEST (`HoldoorClient.chat`) disparaban `HoldoorToast` que hacía `setVisible(true)` y se sumaba al problema. Cambiar diagnósticos a `player:Say()` evitó el falso positivo.

**Fix aplicado a cada overlay:**

| Overlay | Antes | Fix |
|---|---|---|
| `HoldoorOverlay` (fullscreen invisible, base+cruz) | siempre setVisible(true) | arranca setVisible(false), activado al abrir panel admin con base marcada |
| `HoldoorOverlayTrono` (fullscreen, dibuja sprite trono) | siempre setVisible(true) | rect chico reposicionado cada frame al área exacta del trono (180×270 px). Coords relativas (0,0) en drawTextureScaled. Tick de 0.5s activa/desactiva según haya trono en el mundo. |
| `HoldoorHUD` lateral | rect chico siempre, fue refactoreado en sub-zonas (paranoia previa) | mantenido refactor + drag custom en `headerZone` (clase `HoldoorHUDDragZone`) que mueve el HUD parent al arrastrar. |
| `HoldoorAnnounce`, `HoldoorToast` | ya tenían setVisible(false) por default | (sin cambios — el #31 documenta el comportamiento) |

**Caso edge — sprite del trono pegado al borde:** cuando el player se aleja, el trono sale del viewport e `IsoUtils.XToScreen` devuelve coords clampeadas al borde → sprite "flotando" en esquina. Fix: detectar fuera-de-viewport y achicar rect a 1×1 en (0,0) sin dibujar (gotcha #33).

### Gotchas nuevos documentados

- **#29 (CRÍTICO, SUPERSEDE #21):** `setWantMouseEvents(false)` + `setVisible(true)` + rect fullscreen → bloquea el inventario igual.
- **#30:** `pcall` no atrapa excepciones Java en B42. Usar `getScriptManager():FindItem()` para validar items.
- **#31:** `HoldoorClient.chat()` dispara Toast internamente. Para diagnósticos usar `player:Say()`.
- **#32:** Items "fantasma" — auditar todas las vías de `_distribuirItems` que NO notifiquen al cliente.
- **#33:** `IsoUtils.XToScreen` para objeto fuera del viewport → sprite pegado al borde. Achicar rect a 1×1.
- **#34:** Patrón de diagnóstico con F-keys toggle individual por overlay.

### Aprendizajes

1. **`setWantMouseEvents(false)` es necesario pero NO suficiente en B42.** Siempre verificar `setVisible(false)` por default o rect chico para overlays que no estén renderizando algo concreto en ese momento.
2. **Auditar SIEMPRE todas las vías que entregan items al inventario.** Una vía sin notificación crea bug "items fantasma".
3. **Validar items contra `media/scripts/generated/items/*.txt` del juego** antes de meterlos en el pool. Asumir naming es peligroso (Hat_Hardhat ≠ Hat_HardHat).
4. **Diagnósticos no deben usar el mismo canal que diagnostican.** Si estamos cazando Toast, los mensajes de TEST NO pueden disparar Toast.
5. **Diagnóstico iterativo con teclas individuales** > tirar fixes a ciegas. Cada F-key acotó el culpable en 1 minuto de test.

### Estado al cierre

✅ Inventario vanilla funcionando 100% (scroll, hover, tooltips, scrollbar drag)
✅ Drops por kill no crashean
✅ Items "fantasma" notificados al cierre de oleada
✅ HUD lateral movible (drag restaurado)
✅ Sprite del trono no queda pegado al borde

**Pendiente menor:** `HoldoorToast` cuando aparece (3s) bloquea inventario en esa zona. Si lo confirmamos como molesto en partida real, aplicar mismo approach que Trono (rect chico solo del cuadrito arriba, ~600×80 px en lugar de fullscreen).

**Versión:** 0.6.1-dev (cerrado, mod.info pendiente bump).
