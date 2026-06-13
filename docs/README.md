# Holdoor — Documentación técnica

> Índice de los docs de este folder. Cada uno tiene un propósito claro. Leer el que aplique antes de tocar código.

## 🚨 LEER PRIMERO en sesión nueva

- **[infra.md](infra.md)** — Arquitectura técnica viva. **Estructura de carpetas (3 ubicaciones del mod), qué carga PZ de dónde, flow de sync edición→juego**, separación de Lua VMs cliente/servidor en B42, modelo de datos del Trono, economía virtual, modos de juego, comandos cliente↔server. **Si dudás de algo técnico → revisar acá primero.**

- **[gotchas.md](gotchas.md)** — Trampas aprendidas a la fuerza. **Lua no acepta `ñ` en identificadores**, 3 copias del mod desincronizadas, sprites IsoThumpable necesitan validación, cadáveres son `IsoZombie`, Break On Error confunde con `pcall`, items.txt en B42 falla, B42 separa VMs incluso en SP. **Leer ANTES de debuggear algo que "no funciona".**

## 📋 Estado del proyecto

- **[next_steps.md](next_steps.md)** — Pendientes priorizados. Próximo inmediato (visual del Trono, sync MP), sprints chicos, features medianos, ideas grandes (MVP2 White Walkers, MP coop, persistencia), bugs conocidos.

- **[sprints_history.md](sprints_history.md)** — Append-only de qué se cerró cada sesión. Para retomar después de un compactor: leer el último sprint.

## 📁 Estructura del proyecto

Ver `infra.md` sección 2. Resumen:

```
Holdoor_PZ/
├── mod.info
├── poster.png
├── docs/                     ← estás acá
└── media/
    └── lua/
        ├── client/HoldoorClient.lua + HoldoorUI.lua
        └── server/HoldoorServer.lua
```

## 🔄 Flow de edición (lockeado 2026-06-12)

```
Documents/Holdoor_PZ/         ← edito acá (git)
        │
        ▼ copy
Zomboid/mods/Holdoor/         ← PZ lee al jugar
        │
        ▼ (solo al publicar a Steam)
Zomboid/Workshop/Holdoor/Contents/mods/Holdoor/
```

❌ **NUNCA** recrear `Workshop/.../Holdoor/42/`. Ver `gotchas.md` #2.

## 🔗 Memoria de Claude relacionada

Docs estratégicos que viven en memoria personal de Claude (`C:\Users\nahue\.claude\projects\C--ContentIA\memory\`), no en este folder:

- `holdoor_mod_design.md` — diseño general del MVP1 (este mod), API B42, features pendientes.
- `holdoor_mvp2_white_walkers.md` — MVP2 (futuro): fort Night's Watch, skins WW, Rey de la Noche, ítems GoT.

---

**Convención de actualización:**
- `infra.md` → al cambiar arquitectura, estructura, paths, modelo de datos.
- `gotchas.md` → cada bug que arde una segunda vez → append-only.
- `next_steps.md` → al planear o cerrar features.
- `sprints_history.md` → al cerrar sesión grande / merge → append-only.
- `README.md` → cuando se suma un doc nuevo o cambia un flow general.
