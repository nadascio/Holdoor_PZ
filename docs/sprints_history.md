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
