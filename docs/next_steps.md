# Holdoor — Next Steps

> Lista viva. Ordenado por prioridad. Cuando se cierra, mover a `sprints_history.md`.

---

## 🔥 PRÓXIMO INMEDIATO — Pendientes Sprint v0.6 + v0.6.1 (post 2026-06-15)

Sprint v0.6 IMPLEMENTADO + v0.6.1 (fix crítico mouse passthrough) CERRADO. Ver `sprints_history.md` para detalle.

### 🆕 v0.6.1: HoldoorToast bloquea 3s cuando aparece
- Toast cuando aparece (drop por kill, anuncio fin oleada) hace `setVisible(true)` 3 segundos → bloquea scroll/hover del inventario en TODA la pantalla durante esos 3s (rect fullscreen).
- Fix posible (mismo approach que el Trono): cambiar a rect chico (~600×80 px) solo donde se dibuja el cuadrito del toast (centrado horizontal, ~y=90 desde top). Coords relativas (0,0) en drawRect/drawText.
- **Validar primero si en partida real es molesto**. Si pasa desapercibido (el user está mirando el toast, no el inventario en ese momento), lo dejamos así.

### 1. Crawlers/Arrastradores funcionan mal
- Reporte de Nahuel: en modo TEST oleada 2 (que del modelo viejo eran crawlers hardcoded), los arrastradores funcionan mal — tardan mucho, son poco reactivos.
- En modelo C eliminé toda la lógica de crawlers explícitos. Hoy solo hay `pctCorredores` (corredores) o normales.
- **Fix posible**: agregar `pctCrawlers` opcional al `oleadasV6` para mezclar crawlers en ciertas oleadas. O dejarlos solo en modo TEST oleada 2 como caso especial.

### 2. Modo TEST: composición especial por oleada
- Modelo viejo: TEST oleada 1 = lentos, oleada 2 = arrastradores, oleada 3 = rápidos. Servía para testear cada tipo de zombi.
- Modelo C: todas las oleadas TEST son iguales (siguen `pctCorredores=0%`).
- **Fix posible**: override por oleada en `oleadasV6` para tipos especiales (ej. `forzarCrawlers=true`, `forzarSprinters=true`).

### 3. Bug "llega al target y no termina la oleada"
- Nahuel lo reportó en una sesión temprana del v0.6, antes de los fixes posteriores. **No confirmé si sigue activo después de los fixes finales**.
- Test: jugar oleada hasta llegar al target → debería disparar CIERRE LIMPIO inmediato. Si no, hay bug en `_chequearCierreOleada`.

### 4. Drops de items raros — testear variedad real
- Pool ampliado en v0.6 con 6 categorías (médico, comida, herramientas, munición, libros, ropa) + validación anti-crash.
- **Falta testear casualmente en partida larga** para validar que los items aparecen y se distribuyen bien.

### 5. Bajar drop de monedas
- Nahuel reportó "demasiado drop de monedas" pero pidió "por ahora dejalo así".
- Cuando se rebalancee: ajustar `dropPorKillBase.bronceChance/min/max` y `dropMultPorModoV6`.

### 6. Textos sobre la cabeza tapándose
- Drops + frases épicas + chat se acumulan sobre la cabeza del personaje y se superponen.
- Estético, no urgente. Posibles fixes:
  - Limitar a 1 mensaje sobre la cabeza al mismo tiempo (queue).
  - Mover MÁS cosas al toast superior (pero ya se quejó cuando lo hice antes).
  - Filtrar solo prioridad alta sobre cabeza (oro/item raro), resto solo toast.

### 7. MP: cliente remoto admin (no host)
- v0.5.1 dejó arreglado `isCoopHost()` para detección de host. Falta probar con un AMIGO conectado al server como admin remoto (con `/setaccesslevel admin`).
- Si el admin remoto puede usar `/holdoor` correctamente → confirmado MP funcional.

---

## 🆕 PRÓXIMOS SPRINTS (después de cerrar v0.6)

### Sprint v0.7 — Sistema de Jefes de Oleada (diseñado, no implementado)

**Estado:** brainstorming cerrado, falta implementar. Discusión en sesión 2026-06-15.

**Opción elegida — Opción C MVP** (1 jefe simple primero, después escalar a pool):
- 1 jefe que aparece en la **última oleada de cada modo** (5/8/10/12).
- HP × 10 zombi normal + daño × 3 + velocidad alta.
- Outfit custom (`addZombiesInOutfit`).
- Anuncio épico al spawn (`HoldoorAnnounce.mostrar` con título "⚠️ EL X SE APROXIMA").
- Drop **garantizado** al matarlo: 1 Oro + 1 Obsidiana + chance bonus.

**Jefe MVP recomendado: 🦴 Lord de los Huesos o ⚰️ Wight con Armadura** — los más logrables técnicamente porque solo requieren spawn-loop + listener `OnZombieDead` + 1 habilidad pasiva (resucita / invoca). Sin mecánicas complejas tipo stun o tracking de HP en tick.

**Sprint futuro — Opción D (Pool de Jefes Nombrados):**
Una vez validado el scaffold con 1 jefe, agregar 4 más. Pool diseñado:
- 🧊 **Caminante Blanco** — rápido + outfit azul + **aullido stunea** (`setEndurance(0)` + `setFatigue(0.95)` + `setPanic(80)`, NO freeze de movimiento que es bug-prone).
- ⚰️ **Wight con Armadura** — HP MUY alto, lento, resucita al morir.
- 👹 **Gigante de Mag** — outfit cuernos, golpe demoledor, frenesí al 30% HP.
- 🦴 **Lord de los Huesos** — outfit esquelético, invoca 5 zombis enragiados al spawn.
- 🔥 **Maestre Corrupto** — outfit rojo, explota al morir (daño en zona).

Cada uno con drop firmado (Lord = obsidiana, Gigante = valyrio, etc).

**Tiempo estimado:** MVP (1 jefe) ~2 días. Pool completo (5 jefes) ~5 días adicionales.

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

## 🎓 TUTORIAL DE BIENVENIDA (sprint #1, primero después del sprint actual)

**Estado:** sin tutorial. Cuando el user nuevo abre el mod, no sabe qué hacer.

**Plan:**
1. Detectar primer uso vía `player:getModData().Holdoor_TutorialVisto`.
2. Wizard modal con 7 pasos (Bienvenida / F10-chat / Base+modos / Oleadas+Defensa / Monedas-Materiales-Tienda / Tip balance / "Hold the door!").
3. Cada paso: título + texto + [Atrás] [Siguiente] [Saltar].
4. Botón "Ver tutorial" en panel F10 para revisarlo de nuevo.
5. **Solo en castellano por ahora** (después se traduce en sprint #2).

**Tiempo estimado:** ~2-3h.

---

## 🌍 INTERNACIONALIZACIÓN (sprint #2-#4, después del tutorial)

### Holdoor versión ENG + ESP (sistema nativo de PZ)

**Estado:** mod actualmente solo en español. Queremos versión inglés para alcanzar audiencia global del Workshop.

**Camino A elegido — sistema nativo de PZ con archivos `Translate/<lang>/`:**

1. **Sweep de strings hardcoded** en:
   - `HoldoorClient.lua` (notificaciones de chat, mensajes server→client)
   - `HoldoorUI.lua` (todos los labels, botones, tooltips del panel y HUD)
   - `HoldoorShop.lua` (UI de tienda)
   - `HoldoorConfig.lua` (nombres de modos, descripciones)
   - `HoldoorServer.lua` (notificaciones de oleada, prints visibles)

2. **Reemplazar cada string** por `getText("Holdoor_<KeyName>")`.

3. **Crear archivos de traducción:**
   ```
   media/lua/shared/Translate/ES/Holdoor_ES.txt
   media/lua/shared/Translate/EN/Holdoor_EN.txt
   ```
   Formato: `Holdoor_KeyName = "valor en idioma X",`

4. **Aclarar en el título del mod** (mod.info + workshop.txt):
   ```
   Holdoor — Wave Defense GoT [ENG/ESP] (Beta)
   ```
   Que quede claro que soporta ambos idiomas.

5. **Workshop description bilingüe**: opción A (texto largo dividido en 2 mitades ENG arriba / ESP abajo) o opción B (publicar como item único con bandera 🇬🇧🇪🇸 al principio).

**Por qué Camino A y no B (mod separado):** mantener 2 mods sincronizados es doloroso. El sistema nativo de PZ resuelve esto correctamente y permite agregar más idiomas (PT, FR, RU) fácil después.

**Cuándo:** después del tutorial (sprint #1). Es importante para crecimiento del mod en Workshop.

---

## 👤 ABOUT ME / CREADOR / FOOTER / REPORTE DE BUGS (sprint #1, junto con tutorial)

**Estado:** mod actualmente NO menciona al creador ni cómo reportar bugs.

**Plan de TODO lo "informacional del mod" que va junto al tutorial:**

### 1. Autoría in-game (que quede asentado el creador)
- **`mod.info`**: agregar `author=Nahuel Scioro`.
- **`workshop.txt`**: sección "Sobre el creador" al final con el about-me.
- **Footer pequeño en panel F10**: línea en gris sutil tipo `Holdoor v0.5 — by Nahuel Scioro` en la esquina inferior del panel.
- **Footer en HUD lateral**: opcional, una línea chiquita "by Nahuel" abajo del HUD.
- **Paso final del tutorial**: "Creado por Nahuel Scioro — desde Argentina".

### 2. Botón "Acerca del autor" en panel F10
Abre un modal con el about-me + foto/avatar opcional + link a perfil de Steam/github.

### 3. Botón "Reportar un bug" en panel F10
Abre un modal con:
- Link al github issues: `https://github.com/nadascio/Holdoor_PZ/issues`
- Instrucciones cortas: "Pegá el error que viste + qué estabas haciendo".
- Botón "Copiar link al portapapeles" (si la API de PZ lo permite, sino solo mostrar el link).

### 4. About-me text (versión pulida, confirmada por Nahuel 2026-06-13)
```
¡Hola! Soy Nahuel Scioro, desde Argentina.

Soy contador público de profesión, pero giré hacia el lado
tecnológico. Hoy me dedico a automatizar procesos de impuestos
con IA, RPA y otras herramientas.

Este mod nació como un proyecto personal — un homenaje a
Game of Thrones y a las largas tardes jugando Project Zomboid
con amigos.

Quería compartirles algo de lo que disfruto haciendo. Espero
que les guste y se diviertan tanto como yo armándolo.

Hold the door!
— Nahuel
```

**Cuándo:** TODO se implementa junto con el tutorial (sprint #1) en castellano. La traducción inglés va en sprint #3.

---

## ⚰️ "RAISE UP JOHN SNOW" — Seguro de Vida (sprint #5 o cuando convenga)

**Estado:** diseño completo cerrado 2026-06-13. Implementación ~3-5h.

### Concepto

Item endgame de la tienda que da al player una **resurrección automática** la próxima vez que muera por CUALQUIER causa (zombi, caída, hambre, etc.). No requiere oleada activa.

### Approach técnico: INTERCEPCIÓN (no respawn)

En lugar de "morir y crear personaje nuevo" (que perdería apariencia/build), interceptamos el daño letal ANTES de matar al player vía `OnPlayerGetDamage` / `OnPlayerDeath` y curamos al mismo IsoPlayer.

**Ventajas**: conserva cara/pelo/género/edad/ropa/construcciones/vehículos/skills/traits/saldo — todo intacto.

### Flow definitivo

1. Player compra "Raise up John Snow" en tienda → flag `md.Holdoor_RaiseUpActivo = true`.
2. Player muere por cualquier causa.
3. **Servidor intercepta**, cancela el daño, ejecuta:
   - HP → 100%
   - Heridas / sangrado / infección / mordeduras → limpios
   - Hunger / thirst / fatigue / stress → razonables
   - Body damage → limpio
4. **Pantalla negra 3 segundos** + sonido épico (campanas/coro) + texto centrado:
   > **"¡John Snow ha sido levantado por el R'hllor!"**
5. **Teletransporte al lugar seguro (approach C híbrido)**:
   - Buscar tile sin zombis adyacentes cerca del Trono (radio 3 → 15).
   - Si no encuentra, buscar a 20-30 tiles del lugar de muerte.
   - Fallback: posición original con invulnerabilidad larga.
6. **Invulnerabilidad temporal 2-3 segundos** (god mode) para que el player se reposicione si la zona se complica.
7. Flag consumido. Próxima compra es full price de nuevo.

### Decisiones lockeadas

| | |
|---|---|
| Approach | **C híbrido** (Trono primero, lugar de muerte secundario) |
| Invulnerabilidad post-respawn | **2-3 segundos god mode** |
| Animación | **Pantalla negra 3s + texto épico + sonido** |
| Precio | **5 oro + 3 valyrio + 5 obsidiana** |
| Cuándo se puede comprar | **Cualquier momento** (no hay bloqueo por oleadas) |
| Cuándo se activa | **Cualquier momento que muera** el player (oleada o no) |
| Cantidad de revives | **1 sola por compra** (re-comprable después) |

### Categoría en tienda

Va en categoría **"Milagros del Maestre"** o en una nueva **"R'hllor"** dedicada solo a esto. Decidimos al implementar.

### Item key sugerido

```lua
{ id="raise_up_jon",
  nombre="Levanten a John Snow",
  desc="Una segunda chance. El R'hllor te levantara una vez antes de morir definitivamente.",
  precio={gold=5, valyrio=3, obsidiana=5},
  accion={tipo="raise_up"} }
```

### Limitaciones honestas

- Si el daño es **instantáneo y masivo** (caída altura gigante, explosión), el evento puede no interceptarse a tiempo. Backup: check de HP cada tick.
- **Construcciones/vehículos del player en el mapa NO se afectan** (sobreviven a la muerte de su creador). En este approach tampoco se tocan, así que perfecto.

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

## ✅ CERRADO 2026-06-13 — SPRINT MAYOR

Movido a `sprints_history.md`:
- **HP del Trono variable por dificultad** (facil 1500 / normal 1250 / dificil 1100 / pesadilla 1000).
- **Modo Defensa ON por defecto** + bonus "perfect run" (Trono sin daño = +25% monedas + 15% materiales).
- **Sistema de drops completo en `_distribuirRecompensaOleada`**: monedas 2x más + materiales (Cuero/Hierro/Acero/Valyrio/Obsidiana) + items reales del juego con pool extensible.
- **Performance bonus**: +10% monedas si player mató >70% zombis de la oleada.
- **HUD lateral con colores**: monedas + materiales con tonos temáticos. ASCII puro (kahlua no soporta UTF-8).
- **Tienda expandida**: 3 tiers en consumibles (médico + comida) con balance progresivo. 15 libros XP de combate. 6 Rasgos Heroicos (1 por vida). 5 Milagros del Maestre (1 por vida).
- **Botón [TEST] DARME** en panel F10 para autodarse monedas/items y probar la tienda.
- **Scroll vertical en tienda** con paginación (6 filas + ▲/▼).
- **Header tienda con colores por moneda/material**.
- **Bug del click derecho del mundo** arreglado (faltaba `onRightMouseDown` en overlay del Trono).
- **Fixes de APIs B42**: items que no existen reemplazados (`Base.FirstAidKit` → packages reales, `Base.WaterBottleFull` → `Base.WineBottle`, etc.), traits con cascada de 4 APIs, cura_trait con `HasTrait()`, stats restore defensivo.

## ✅ CERRADO 2026-06-13 (previo)

- **Visual del Trono de Hierro (camino C0)**: overlay PNG flotante sobre la forja. Funciona, se transparenta al acercarse player/zombis (cache 100ms).
- **Layout del Trono**: 1 pieza (forja `crafted_01_16`, 1500 HP base).
- **Colchón de zombis**: cada 3s, si vivos < 5 y hay encolados → spawn inmediato.
- **Limpieza al terminar oleada y al perder**: `_limpiarZona()`.
- **Comandos de diagnóstico vivos**: `testSprite`, `testGaleria`, `dejarTile`, `apilarTile`, `dumpTrono`, `matarZombiesCerca`.
- **APIs B42 documentadas**: `IsoUtils.XToScreenExact` con 4 args, `drawTextureScaled` con 6 args.

## ⚠️ PENDIENTE de validar en juego antes del próximo sprint

- Rasgos Heroicos: ¿la cascada de 4 APIs funciona en este build? (probar Strong primero, ver log STEP A/B/C/D).
- Milagros del Maestre: cura_trait defensivo, debería permitir paso si no puede verificar.
- Festín de Invernalia: restore stats con cascada.
- Magia de Asshai: cure_bite defensivo.
- Balance general: precios/drops sentirse correctos en runs reales.

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
