# Holdoor — Next Steps

> Lista viva. Ordenado por prioridad. Cuando se cierra, mover a `sprints_history.md`.

---

## 🔥 PRÓXIMO INMEDIATO

### 1. Visual del Trono de Hierro
**Estado:** Trono funcional (HP, daño, game over) pero **no se ve**.

**Plan A — sprite vanilla válido:** Iterar la lista de candidatos en `_tronoSprites`. Ya validamos con `spriteExiste()`, falta confirmar cuál renderiza bien como un trono/objeto sólido grande.

Candidatos pendientes de testear:
- Sillas/sillones grandes
- Estatuas
- Muebles pesados grandes
- Paredes decorativas

**Plan B — sprite custom:** Si ningún vanilla queda bien → crear "Trono de las Cien Espadas" custom (PNG isométrico, 2x2 tiles). Modelo: el del show de GoT. Empaquetar en `media/textures/` del mod y registrarlo como sprite custom.

**Criterio de éxito:** Trono visible, ocupa los 4 tiles, parece imponente, los zombis lo atacan correctamente.

### 2. Sync visual MP del Trono
**Estado:** Probablemente roto en MP — el IsoThumpable existe server-side pero no se transmite visualmente a clientes.

**Pendiente probar:**
- `syncIsoObject(obj, true, nil)` post-spawn
- `transmitCompleteItemToServer` / `transmitUpdatedSprite` / `transmitAddObjectToSquare`

Solo cuando se vuelva al testing MP. SP funciona (cuando el sprite existe).

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

## ✅ CERRADO RECIENTEMENTE (2026-06-12)

Movido a `sprints_history.md`:
- Fix `ñ` en identificador `_aplicarDañoBoost` → renombrado a `_aplicarDanoBoost` (kahlua no acepta caracteres no-ASCII en identificadores).
- Filtro `isDead()` en damage boost para no contar cadáveres como atacantes (eliminó el daño pasivo de 10 HP fantasma).
- Convención de sync de las 4 ubicaciones del mod lockeada (overlay 42/ + media/ entendido correctamente).
- Recuperación completa del estado funcional desde backup tras casi perderlo por un git checkout mal hecho.
- Commit checkpoint `9e119fb` — primer commit del laburo del Trono que estaba uncommitted desde junio.
- Documentación técnica (`docs/infra.md`, `docs/gotchas.md`, `docs/next_steps.md`, `docs/sprints_history.md`, `docs/README.md`) con la explicación correcta del overlay B42.

---

**Última actualización:** 2026-06-12
