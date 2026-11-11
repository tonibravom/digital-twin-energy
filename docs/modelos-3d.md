# Modelos 3D: de Revit o Blender al visor de la plataforma

Guía para Partners (decisión D51, 11/11/2026). Explica cómo convertir el modelo de un edificio en un archivo GLB que el visor de la plataforma muestre bien y rápido, planta a planta, con las etiquetas de los sensores encima.

El proceso tiene **tres etapas**, siempre iguales:

| Etapa | Dónde | Resultado |
|---|---|---|
| 1. Exportar | Revit (con Leia) o Blender | `edificio.glb` |
| 2. Preparar | Herramienta de la plataforma (`herramientas/modelo3d`) | `edificio-preparado.glb` + informe |
| 3. Publicar | Plataforma (hoy, panel de Supabase) | Modelo visible en la página del edificio |

> Los archivos GLB **no se guardan en los repositorios de código**: se guardan en una carpeta de proyecto (p. ej. `D:\digital-twin-3d`) y en el almacenamiento de Supabase.

---

## 1. Exportar

### 1.1 Desde Revit con Leia (e-verse)

**Antes de exportar, prepare una vista 3D solo para la plataforma** (p. ej. "3D plataforma"):

1. Duplique la vista 3D por defecto y quite la plantilla de vista (o compruebe que no sobrescribe la visibilidad).
2. En *Visibilidad/Gráficos* (VV) **oculte lo que pesa y no aporta**:
   - **barandillas** (en el edificio de ejemplo eran el 59 % de los triángulos);
   - mobiliario y sistemas de mobiliario, aparatos sanitarios, equipos especializados, entorno, plantación y vegetación, personas y vehículos;
   - anotaciones, rejillas, niveles, cotas, líneas de referencia, cámaras y habitaciones.
3. Conserve muros, suelos, cubiertas, techos, pilares, estructura, escaleras, puertas, ventanas y muros cortina. Las instalaciones (conductos, tuberías, equipos mecánicos) solo si se quieren ver en el gemelo.
4. Si el edificio tiene varios bloques o niveles parciales, déjelos todos: la plataforma permite asignar varios niveles de Revit a una misma planta.

**Opciones de Leia:**

| Grupo | Opción | Valor |
|---|---|---|
| Materials | Colors | ✔ (no *Textures*: pesan mucho y el visor no las necesita) |
| Transform | Flip YZ-Axis | ✔ |
| Transform | Export Normals | ✔ |
| Transform | Relocate to 0 | ✔ |
| Data | Export BatchId | ✔ |
| Data | Export Levels | ✔ |
| Data | Export Properties | ✔ (la herramienta solo conserva id, categoría, nivel y tipo) |
| Data | Export Grids | ✘ |
| Compresión | Draco | ✔ (el archivo pesa ~20 veces menos) |

Exporte desde la vista "3D plataforma". **Revit Rooms no hacen falta**: los recintos se dan de alta en la plataforma.

### 1.2 Desde Blender

1. Escala en metros (*Scene Properties → Units*, *Unit Scale* = 1) y el edificio cerca del origen.
2. Un objeto por elemento (o por grupo de elementos) con estas **propiedades personalizadas** (*Object Properties → Custom Properties*):
   - `Nivel`: nombre del nivel o planta (p. ej. `P2`); si falta, la herramienta lo asigna por altura;
   - `Categoría`: muros, suelos, ventanas… (si falta, se usa la primera palabra del nombre del objeto).
3. *File → Export → glTF 2.0*: formato **glTF Binary (.glb)**, *+Y Up* ✔, *Custom Properties* ✔, *Compression* (Draco) ✔. Sin texturas si no son imprescindibles.

---

## 2. Preparar con la herramienta de la plataforma

La herramienta está en el repositorio de la plataforma, `herramientas/modelo3d`. Requiere Node.js 18 o superior.

```powershell
cd herramientas\modelo3d
npm install                      # solo la primera vez
node preparar.mjs "D:\digital-twin-3d\edificio_draco.glb" "D:\digital-twin-3d\edificio-preparado.glb"
```

Opcional: `--excluir "Barandillas,Mobiliario"` quita categorías que no se ocultaron en Revit.

**Qué hace (siempre igual, para que todos los modelos se comporten igual):**

1. Lleva todo a **metros con la Y hacia arriba** (aplica la escala y el giro que añade el exportador). No recentra: las coordenadas del archivo preparado son las del visor de la plataforma.
2. De cada elemento conserva solo **identificador de Revit, categoría, nivel y tipo**; quita el resto de propiedades.
3. Calcula la **cota de cada nivel** (mediana de la base de sus elementos) y asigna nivel por altura a lo que no lo trae.
4. **Agrupa la geometría por nivel y material** (cientos de objetos en vez de miles: el visor va fluido) y guarda en cada vértice el número de elemento (`_ID`) para saber qué se ha pulsado.
5. Unifica materiales repetidos, elimina lo que sobra y **comprime con Draco**.
6. Escribe `edificio-preparado.informe.json` y lo resume en pantalla.

**Límites y avisos:**

| Comprobación | Aviso | Error (no se debe subir) |
|---|---|---|
| Tamaño del archivo | — | más de 40 MB |
| Triángulos | más de 1,5 millones | más de 3 millones |
| Altura del edificio | — | menos de 2 m o más de 500 m (unidades equivocadas) |
| Elementos | — | más de 65.535 |

Si hay un error, la herramienta termina con código 1 y el informe dice qué categorías pesan más: ocúltelas en la vista de exportación y repita.

**Ejemplo (edificio de muestra de Revit):** 10,4 MB y 501.000 triángulos a la entrada → **1,8 MB**, 403 objetos y 72 materiales; 16 niveles (de *Parking* a *Parapet 2*).

Revise en el informe la lista de **niveles con su cota**: son los nombres que se asignan a las plantas en el paso 3.

---

## 3. Publicar en la plataforma

### 3.1 Plantas del modelo

Cada planta de la plataforma indica qué niveles del modelo la forman (`plantas.niveles_modelo`). Un nivel del modelo pertenece a una sola planta. Los niveles que no se asignan van a la planta más cercana por debajo, según su cota.

Ejemplo (torre de demostración):

| Planta | Niveles del modelo |
|---|---|
| Sótano | Parking |
| Planta baja | L1 - Block 35, L1 - Block 37, L1 - Block 43 |
| Entreplanta | M1 |
| Planta 2 … Planta 5 | L2 … L5 |
| Cubierta | R1, R2, R3, Green Roof Hardscape, Parapet, Parapet 2, Block 39 - Parapet |

### 3.2 Registro y subida del archivo

Primero se crea el registro del modelo y después se sube el archivo a la ruta registrada. Mientras no exista la pantalla de Configuración:

1. Cree el registro en `modelos_3d` (tipo `EDIFICIO`, archivo `edificios/<id del edificio>/modelos/<nombre>.glb`, compresión `DRACO`). Para la demo, `docs/demo_torre_modelo3d.sql` lo hace y muestra la ruta.
2. En el panel de Supabase: **Storage → `modelos-3d`**, entre en la carpeta `edificios/<id>/modelos/` (créela si no existe con *Create folder*, carpeta a carpeta) y suba el GLB preparado **con el nombre exacto registrado**.
3. Abra la página del edificio: el centro del panel muestra el modelo (botón **3D | Lista** para volver a la lista de sensores).

Para una nueva versión del modelo se usa `sustituir_modelo_3d`: la anterior queda inactiva y las coordenadas se copian marcadas "por revisar".

### 3.3 Etiquetas de los sensores (D10)

Cada sensor tiene un punto X, Y, Z (metros, Y hacia arriba) sobre el archivo preparado. Tres formas de obtenerlo:

1. **Pulsando en el visor de la plataforma** (Partner y administrador): al pulsar el modelo se ve el elemento (categoría, tipo, planta, id de Revit) y el punto X / Y / Z, con un botón para copiarlo. En la futura pantalla de Configuración, ese punto se asignará al sensor directamente.
2. **A mano o por Excel**: coordenadas tomadas de cualquier visor de GLB sobre el **mismo archivo preparado**.
3. **Más adelante**: sensores modelados como familias de Revit, con su posición extraída automáticamente.

Recomendación: la etiqueta, a 1,2–1,6 m sobre el suelo del recinto. Si varios sensores comparten punto, el visor apila sus etiquetas.

---

## 4. Lo que ve el usuario

- **Todo el edificio**: el modelo completo; solo se muestra la etiqueta del sensor seleccionado.
- **Una planta**: se ocultan las plantas superiores, la vista se acerca a esa planta y aparecen las etiquetas de sus sensores, con el último valor y el estado (verde comunicando, gris sin datos, rojo alarma).
- Pulsar una etiqueta muestra el sensor en la gráfica del panel.
- Pulsar el modelo identifica el elemento; arrastrar gira, rueda acerca, botón derecho desplaza; **Encuadrar** vuelve a la vista inicial.
