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
