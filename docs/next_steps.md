# Holdoor — Next Steps

> Lista viva. Ordenado por prioridad. Cuando se cierra, mover a `sprints_history.md`.

---

## 🔥 PRÓXIMO INMEDIATO

### 1. Ajuste de drops + balance de tienda
**Estado:** sin tocar desde la última pasada. Necesita revisión completa.

**Qué revisar:**
- **Drops de monedas por oleada**: ¿están proporcionales al esfuerzo? ¿el modo NORMAL da demasiado/poco?
- **Drops de materiales** (Cuero/Hierro/Acero/Valyrio/Obsidiana): tabla actual en `HoldoorConfig.rewardTable`. ¿Probabilidades correctas?
- **Precios de la tienda**: catálogo en `HoldoorShopCatalog.lua`. ¿Hay items demasiado caros/baratos? ¿Falta variedad?
- **Multiplicadores por modo**: facil ×0.5 / normal ×1 / dificil ×2 / pesadilla ×4 / test ×0. ¿Son las brechas correctas?

**Criterio de éxito:** progresión sentida — al terminar 3-4 oleadas en NORMAL deberías poder comprar al menos 1 ítem decente.

### 2. Sync visual MP del Trono
**Estado:** Probablemente roto en MP — el IsoThumpable existe server-side pero no se transmite visualmente a clientes. El overlay UI sí se ve en MP (es cliente-side) pero la forja real abajo capaz no.

**Pendiente probar:**
- `syncIsoObject(obj, true, nil)` post-spawn
- `transmitCompleteItemToServer` / `transmitUpdatedSprite` / `transmitAddObjectToSquare`

Solo cuando se vuelva al testing MP. SP funciona OK.

---

## ⭐ NICE TO HAVE (sin urgencia)

### Sprite custom isométrico real del Trono de Hierro (camino C2)
**Estado actual:** PNG overlay funciona bien — el Trono se ve, no requiere arte custom.

**Para mejorar a "sprite del mundo real" (que oclusione bien, tenga sombras propias, no requiera transparencia hack):**
- Dibujar sprite custom iso del Trono (~5-8h de pixel art skill medio-alto, $30-50 USD en Fiverr).
- Empaquetarlo con **TileZed** (tool oficial de PZ) en un `.pack` file.
- Registrarlo en un `.tx` con nombre custom (ej. `Holdoor_TronoHierro_01_0`).
- Cambiar el sprite del layout en `HoldoorServer._tronoLayoutForja` al custom.

**Por qué no es urgente:** lo actual funciona, los zombis atacan, el HP responde, el visual queda decente con la transparencia por proximidad. El upgrade es solo cosmético.

**Alternativa intermedia (~30 min):** editar la PNG actual en GIMP — agregarle sombra elíptica en la base + recortar excedente + bajar brillo de bordes. Mejora la "integración" visual sin reemplazar el sistema.

---

## 🛠 SPRINTS CHICOS (1-2h cada uno)

### 3. Balance de daño Trono
Por ahora `_damagePerZombi = {facil=1, normal=2, dificil=4, pesadilla=8, test=5}`. En el último test el Trono cayó relativamente rápido en normal. Necesita afinar:
- Mirar cuánto tarda en caer cada modo con N jugadores.
- Considerar si el HP base (1500) o el dmg/zombi/ciclo necesitan ajuste.
- ¿Escalado con cantidad de jugadores?

### 4. HUD visual del Trono (barra de HP)
Actualmente solo label numérico (`Trono: 413 / 1500 HP`). Sumar:
- Barra de HP visual en el HUD lateral (verde→amarillo→rojo según %).
- Animación de tembleque/flash cuando recibe daño grande.
- Sonido de campana al cruzar umbrales (60/30/10).

### 5. Indicador visual del Trono en el mapa
Marcador en el world map y/o pin en el minimap apuntando al Trono mientras está vivo.

### 6. Reseñas pendientes del user (2026-06-12)
*Nahuel dijo "tengo reseñas luego para pasarte" tras confirmar que el sistema funciona. Anotar acá cuando las pase.*

- (pendiente)

---

## 🎮 FEATURES MEDIANOS

### 7. Integración Medieval Z mod en la tienda
El mod externo Medieval Z (Steam Workshop) tiene armas y armaduras medievales que calzan estéticamente con GoT.

**Plan:**
- Detectar si el mod está activo (`getActivatedMods()`).
- Si lo está → habilitar sección "Equipo Medieval" en la TIENDA con sus ítems comprables con monedas/materiales.
- Si no → ocultar la sección y mostrar mensaje "Instala Medieval Z para desbloquear equipo medieval".

### 8. Progresión de velocidad de zombis por oleada
Ya está la base (`_damagePerZombi` escala por modo). Falta:
- Velocidad de movimiento de zombis aumenta con cada oleada.
- En `pesadilla` arrancan ya en sprint, en `facil` se mantienen lentos.
- Definir curva exacta (lineal? exponencial? con techo?).

### 9. Tipos de zombis especiales por oleada
- Oleada 1-2: zombis normales.
- Oleada 3-4: empiezan a aparecer corredores.
- Oleada 5+: zombis "élite" (más HP / más daño / sprinters fijos).
- Oleada final: jefe (zombi gigante o boss equivalente).

### 10. Sistema de logros / records
- Mejor oleada alcanzada en cada modo.
- Tiempo total sobrevivido.
- Zombis matados acumulado.
- Display en panel F10 + leaderboard MP.

---

## 🌟 IDEAS GRANDES (no inmediato)

### 11. MVP2 — Modo White Walkers
Doc completo en memoria de Claude: `holdoor_mvp2_white_walkers.md`.

Resumen:
- Fort de madera Night's Watch auto-construido en spawn.
- Skins WW custom (zombis con piel azul/blanca + ojos azules brillantes).
- Boss "Rey de la Noche" cada N oleadas.
- Ítems GoT: Dragonglass, acero Valyrio (one-shot a WW).
- Overlay visual de frío.
- WW levantan a tus muertos como aliados suyos.
- Fuego como debilidad (Molotov hace más daño).

**Cuándo arrancarlo:** Después que MVP1 esté completamente pulido (Trono visual + balance + tienda básica).

### 12. Modo cooperativo MP completo
- HP del Trono compartido entre todos.
- Monedas/materiales transferibles entre jugadores (ya hay botón "Enviar monedas").
- Chat de squad cuando se inicia sesión.
- Revivir compañeros caídos con costo de materiales.

### 13. Persistencia de progreso
Guardar entre saves:
- Records personales.
- Materiales acumulados (¿reset por save o eternos?).
- Logros desbloqueados.
- Customización del trono (skins, mejoras de HP).

---

## 🐛 BUGS CONOCIDOS PENDIENTES

| Bug | Severidad | Estado |
|---|---|---|
| Trono no se ve visualmente | Alta | Plan A vs Plan B → ver punto 1 |
| Sync visual MP de IsoThumpable | Media | Pendiente test MP |
| (otros que aparezcan en próximas reseñas) | — | — |

---

## ✅ CERRADO RECIENTEMENTE (2026-06-13)

Movido a `sprints_history.md`:
- **Visual del Trono de Hierro (camino C0)**: overlay PNG flotante sobre la forja. Funciona, se transparenta al acercarse player/zombis (cache 100ms).
- **Layout del Trono**: 1 pieza (forja `crafted_01_16`, 1500 HP). Game over cuando llega a 0.
- **Colchón de zombis**: cada 3s, si vivos < 5 y hay encolados → spawn inmediato. Evita "ir a buscarlos".
- **Limpieza al terminar oleada y al perder (game over)**: `_limpiarZona()` en `_oleadaCompletada` y `_tronoCayo`.
- **Comandos de diagnóstico vivos**: `testSprite`, `testGaleria`, `dejarTile`, `apilarTile`, `dumpTrono`, `matarZombiesCerca`, etc.
- **APIs B42 documentadas en gotchas**: `IsoUtils.XToScreenExact` con 4 args, `drawTextureScaled` con 6 args.

## ✅ CERRADO 2026-06-12

Movido a `sprints_history.md`:
- Fix `ñ` en identificador `_aplicarDañoBoost` → renombrado a `_aplicarDanoBoost` (kahlua no acepta caracteres no-ASCII en identificadores).
- Filtro `isDead()` en damage boost para no contar cadáveres como atacantes (eliminó el daño pasivo de 10 HP fantasma).
- Convención de sync de las 4 ubicaciones del mod lockeada (overlay 42/ + media/ entendido correctamente).
- Recuperación completa del estado funcional desde backup tras casi perderlo por un git checkout mal hecho.
- Commit checkpoint `9e119fb` — primer commit del laburo del Trono que estaba uncommitted desde junio.
- Documentación técnica inicial (`docs/infra.md`, `docs/gotchas.md`, `docs/next_steps.md`, `docs/sprints_history.md`, `docs/README.md`) con la explicación correcta del overlay B42.

---

**Última actualización:** 2026-06-12
