# Holdoor — Testing Workflow (debug con logs de PZ)

> Cómo diagnosticar bugs sin pedir capturas al usuario. Lockeado 2026-06-15 tras ahorrarnos 4-6h de debugging en la sesión de Rasgos Heroicos / Milagros.

---

## 🎯 La regla central

**Antes de pedir capturas o re-leer código a ciegas, LEER los logs de PZ directamente.** El usuario corrió el juego y todo lo que pasó (prints, errores Java, stack traces de kahlua) quedó escrito en archivos accesibles desde el filesystem.

Es la diferencia entre debuggear "a tientas" y debuggear con datos reales.

---

## 📁 Ubicaciones clave de logs

### 1. Consola viva (lo más importante)

```
C:/Users/nahue/Zomboid/console.txt
```

- **Append-only**: cada partida de PZ acumula sus prints + errores al final del archivo.
- Incluye TODO lo que viste en la consola in-game (F11): `print()` del mod, errores Java, stack traces.
- Lo más reciente está al **final** del archivo.

### 2. Logs estructurados por sesión

```
C:/Users/nahue/Zomboid/Logs/<fecha>_DebugLog.txt
C:/Users/nahue/Zomboid/Logs/<fecha>_console.txt
```

- Una carpeta nueva por cada partida.
- `DebugLog-*.txt` separa logs por subsistema (server, client, network).
- Útil cuando `console.txt` está muy mezclado.

---

## 🔬 Workflow de debug

### Paso 1: pedirle al user que reproduzca el bug

"Reproducí el bug una vez en una partida limpia y avisame cuando termines."

No necesitamos screenshot. Solo confirmación de que corrió el flow.

### Paso 2: leer `console.txt` con `tail` (últimas líneas)

```bash
tail -n 100 "/c/Users/nahue/Zomboid/console.txt"
```

Esto te muestra lo último que pasó. Si el bug es reciente, está acá.

### Paso 3: buscar el patrón con `grep`

Para errores estructurados específicos:

```bash
# Errores de kahlua
grep -n "attempted index\|tried to call nil\|Lua fail" "/c/Users/nahue/Zomboid/console.txt" | tail -n 20

# Prints de diagnóstico que pusiste vos
grep -n "\[Holdoor\]" "/c/Users/nahue/Zomboid/console.txt" | tail -n 30

# Buscar referencias a una función específica
grep -n "aplicarTraitLocal\|TraitFactory" "/c/Users/nahue/Zomboid/console.txt" | tail -n 20
```

### Paso 4: leer el contexto completo con `sed`

Si grep te muestra el evento pero querés ver el stack trace completo:

```bash
sed -n '680,770p' "/c/Users/nahue/Zomboid/console.txt"
```

(rango de líneas alrededor del error)

---

## 🧠 Estrategia de prints como tracers

Si no estás seguro qué API funciona en B42, **agregá prints diagnósticos** ANTES de intentar cascadas de fallback:

```lua
print(string.format("[Holdoor] aplicarTraitLocal: '%s' | TraitFactory=%s | p.addStringTrait=%s | p.getCharacterTraits=%s",
    tostring(traitId),
    type(TraitFactory),
    type(p.addStringTrait),
    type(p.getCharacterTraits)
))
```

Después de que el user reproduce el bug, grepeás esa línea exacta:

```bash
grep "aplicarTraitLocal:" "/c/Users/nahue/Zomboid/console.txt" | tail -n 1
```

Y obtenés en una sola línea **qué APIs existen y cuáles son nil** en el contexto donde se ejecutó. Esto guía la solución sin adivinar.

---

## 💡 Cuándo aplicar este workflow (vs pedir capturas)

**SÍ usar logs.txt:**

- "No pasa nada cuando hago X" (síntoma genérico — el log te dice qué pasó internamente).
- Error que aparece en consola in-game pero el usuario no lo copió.
- Stack trace de kahlua o Java que necesitás analizar.
- Validar que tu print de diagnóstico se ejecutó (y qué imprimió).
- Buscar la última vez que se ejecutó una función específica.

**SÍ pedir captura:**

- Bug visual / layout de UI (texto pisado, botón fuera de lugar, color raro).
- Comportamiento que no genera logs (animación, posición de cámara, hitboxes).
- Modal o estado intermedio que querés ver renderizado.

**Híbrido óptimo:** captura para el síntoma visual + `console.txt` para el contexto runtime.

---

## 🔥 Caso real — sesión 2026-06-15

**Bug:** "comprar un Rasgo Heroico no aplicaba el trait".

**Iteración sin logs:** habríamos probado 5 APIs distintas a ciegas (`TraitFactory.getTrait`, `addStringTrait`, `addTrait` con obj y con string, `getTraits():add`), cada una requiriendo un build + test + capture round-trip. Estimado: 4-6h de back-and-forth.

**Iteración con logs:**

1. Agregué un print con `type()` de cada API candidata.
2. Le pedí al user que reproduzca.
3. Leí `console.txt`:
   ```
   [Holdoor] aplicarTraitLocal: 'Strong' | TraitFactory=nil | p.addStringTrait=nil
   p.addTrait=nil | p.getTraits=nil
   ```
4. **Eureka instantáneo**: todas las APIs son nil en server context → la lógica de traits hay que llevarla al cliente.
5. Confirmé leyendo código vanilla de PZ (`media/lua/client/ISUI/PlayerStats/ISPlayerStatsUI.lua:594`).
6. Implementé la solución correcta en un solo paso.

**Ahorro estimado:** 4-6h de iteración compactadas en ~30 minutos.

Ver `gotchas.md` #16, #17, #18 para las trampas técnicas que aprendimos.

---

## ⚠️ Limitaciones

- `console.txt` **no se vacía automáticamente** — crece partida tras partida. Si el bug es de hace varias sesiones, mirar las fechas en `Zomboid/Logs/<fecha>/`.
- Algunos errores Java muy bajo-nivel (NPE en el motor del juego) NO aparecen en `console.txt`, sino en `hs_err_pid*.log` en la raíz de la instalación de PZ (raro pero existe).
- Si el user juega con el log silenciado o el archivo locked por un proceso anterior, puede no actualizarse — pedirle reiniciar PZ resuelve.

---

**Última actualización:** 2026-06-15
