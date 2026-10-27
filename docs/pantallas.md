# Pantallas y funcionamiento general

Especificación de la navegación y de las pantallas de la plataforma (salvo la página de edificio, que se define aparte). Es el guion de la Fase 3 y está acordada el 21/10/2026.

## 1. Mapa de pantallas

```
Login
 └─► Enrutado según rol y alcance
      ├─► Ámbito PLATAFORMA (admin SaaS) ── lista de Partners
      │      └─► Ámbito PARTNER ─────────── lista de Clientes
      │             └─► Ámbito CLIENTE ──── lista de Edificios
      │                    └─► Página de EDIFICIO (se define aparte)
      └─► (cada usuario entra en el nivel que le corresponde)
```

Las tres pantallas de ámbito son **una sola plantilla** que cambia según el nivel (maestro §19: una única aplicación y un esquema de dashboard coherente).

## 2. Login y enrutado

Login con email y contraseña (Supabase Auth). Incluye "¿Has olvidado la contraseña?". No hay registro público: los usuarios se crean por invitación.

Tras iniciar sesión, la plataforma lee el **rol** y el **alcance** del usuario y decide a qué pantalla va:

| Usuario | Pantalla de entrada |
|---|---|
| Administrador de la plataforma (ADMIN_SAAS) | Ámbito **Plataforma** |
| Admin o técnico de un Partner | Ámbito **Partner** de su Partner. Si pertenece a varios, primero elige cuál |
| Usuario de cliente con varios edificios | Ámbito **Cliente**. Si tiene acceso a varios clientes, primero elige cuál |
| Usuario de cliente con **un solo edificio** | Directo a la **página del edificio** |
| Usuario sin ninguna asignación activa | Mensaje "Su cuenta no tiene edificios asignados. Contacte con su administrador" |

## 3. Plantilla de ámbito (los tres niveles)

```
┌──────────────────────────────────────────────────────────────────┐
│ Logo │ Plataforma › Partner Norte › Cliente Hotel Sol   [usuario▾]│  ← cabecera y ruta
├──────┬───────────────────────────────────────────────────────────┤
│ Menú │  KPIs del año: Energía · Emisiones · Agua · Renovables      │  ← franja de KPIs
│      │  (valor y % frente al mismo periodo del año anterior)       │
│ Inicio├─────────────────────────────┬─────────────────────────────┤
│ Análisis│        MAPA               │  PENDIENTES (solo Partner)  │
│ Alarmas │   edificios del ámbito    │  edificios en parametriz.   │
│ Usuarios├─────────────────────────────┴─────────────────────────────┤
│ Config. │  LISTA (Partners / Clientes / Edificios)  [Buscar] [Filtros] [+ Nuevo] │
└──────┴───────────────────────────────────────────────────────────┘
```

| Nivel | Título | La lista muestra | Al pulsar un elemento |
|---|---|---|---|
| Plataforma | "Plataforma" | Partners | Ámbito de ese Partner |
| Partner | Nombre del Partner | Clientes | Ámbito de ese Cliente |
| Cliente | Nombre del Cliente | Edificios | Página del edificio |

- **Ruta de navegación:** cada tramo es un enlace para volver al nivel superior. Un usuario solo ve los tramos a los que tiene acceso: un usuario de cliente no ve "Plataforma" ni el Partner.
- **El mapa** muestra los edificios de todo el ámbito, agrupados en racimos cuando están cerca:
  - el color indica el estado del edificio (ver apartado 5);
  - al pulsar un edificio se abre una ficha breve con su nombre, cliente, consumo del año y alarmas, y el botón "Ir al edificio".

## 4. KPIs

Año en curso hasta hoy, comparado con **el mismo periodo del año anterior**.

| KPI | Cálculo | Unidad |
|---|---|---|
| **Consumo de energía** | Toda la energía que consume el edificio: electricidad importada de la red + gas + renovable consumida (fotovoltaica y eólica autoconsumidas + solar térmica, geotermia y biomasa) | kWh (MWh si es grande) |
| **Emisiones** | (electricidad importada × 0,183 + gas × 0,182) / 1000. Las renovables no emiten | tCO₂e |
| **Agua** | Suma de consumos de agua | m³ |
| **Generación renovable** | Fotovoltaica + eólica + solar térmica + geotermia + biomasa, con el **% de cobertura renovable** (renovable consumida / consumo de energía) | kWh y % |

- Debajo de cada KPI: **variación %** frente al año anterior. Verde si baja el consumo o las emisiones, o si sube la generación renovable; rojo en el caso contrario.
- La variación se calcula **solo con edificios que tienen datos en ambos periodos**, para que un edificio nuevo no la distorsione. Se indica, por ejemplo, "Comparación sobre 2 de 3 edificios".
- Junto a Emisiones se muestran los **factores usados**, como pide el maestro: "Electricidad 0,183 · Gas 0,182 kgCO₂e/kWh". Los factores se cambian en *Parámetros* (solo el administrador) y se aplican según su fecha de vigencia.
- Al pulsar un KPI se despliega su desglose: electricidad y gas por separado, y cada tecnología renovable.

*Soporte en la base de datos (022):*
- `kpis_ambito(nivel, id)` da los KPIs de la franja;
- `kpis_lista(nivel, id)` da las columnas de consumo de la lista;
- ambas leen `resumenes_diarios`, que rellena el motor (Fase 5).

## 5. Estados de los edificios (mapa y lista)

| Color | Significado | Origen |
|---|---|---|
| Verde | Operativo y sin incidencias | `edificios.estado` = OPERATIVO |
| Rojo | Alarmas activas | `eventos_alarma` abiertos |
| Naranja | Sensores sin comunicación | `estado_comunicacion` |
| Gris | Pendiente de parametrización | `edificios.estado` = PENDIENTE_PARAMETRIZACION |
| Gris tachado | Suspendido | `edificios.estado` = SUSPENDIDO |

Las bajas no aparecen salvo que se active el filtro "Incluir bajas".

## 6. Lista con búsqueda avanzada

**Buscador:** texto libre sobre nombre, código, CIF y municipio.

**Columnas por nivel:**

| Plataforma (Partners) | Partner (Clientes) | Cliente (Edificios) |
|---|---|---|
| Nombre | Nombre | Nombre y código |
| Estado | Estado | Estado (color) |
| Nº clientes / edificios | Nº edificios | Municipio / provincia |
| Energía y tCO₂ del año, variación % | Energía y tCO₂ del año, variación % | Energía, tCO₂, agua, renovables, variación % |
| Alarmas activas | Alarmas activas | Alarmas activas |
| Edificios sin comunicación | Edificios sin comunicación | Sensores sin comunicación |
| | | Modalidad y 3D |

**Filtros avanzados** (todos salen de campos existentes):
- estado;
- provincia y municipio;
- uso del edificio;
- superficie (rango);
- modalidad (BASIC / PRO / PREMIUM);
- complemento 3D;
- "con alarmas activas";
- "con incidencias de comunicación";
- "pendiente de parametrización".

Ordenación por cualquier columna y exportación a Excel/CSV de la lista filtrada.

## 7. Botones según permisos

Los botones aparecen según los **permisos** del usuario, no según la pantalla. La seguridad real la sigue garantizando la base de datos.

| Botón | Dónde | Permiso necesario |
|---|---|---|
| Nuevo Partner / Editar Partner | Plataforma | Solo ADMIN_SAAS |
| Nuevo cliente / Editar cliente | Partner | CREAR_CLIENTE / MODIFICAR_CLIENTE |
| Dar de baja cliente | Ficha de cliente | DAR_BAJA_CLIENTE |
| Nuevo edificio / Editar edificio | Cliente | CREAR_EDIFICIO / MODIFICAR_EDIFICIO |
| Dar de baja edificio | Ficha de edificio | DAR_BAJA_EDIFICIO |

Por ejemplo, el administrador de la plataforma, al bajar a un cliente, también ve "Nuevo edificio". El técnico de un Partner, que no puede crear clientes, no ve ese botón.

"Nuevo edificio" crea el edificio en estado **pendiente de parametrización** y abre el asistente de configuración (`docs/configuracion-partner.md`).

## 8. Panel "Pendientes" (solo nivel Partner)

Lista de edificios en parametrización, con su avance: "7 de 9 requisitos" y una barra de progreso (`estado_parametrizacion_edificio`). Al pulsar uno se abre el asistente en el punto donde se dejó.

## 9. Menú lateral

| Opción | Plataforma | Partner | Cliente |
|---|---|---|---|
| Inicio (pantalla de ámbito) | ✔ | ✔ | ✔ |
| Análisis › Indicadores | ✔ | ✔ | ✔ |
| Análisis › Benchmarking | ✔ | ✔ | ✔ (según modalidad) |
| Alarmas e incidencias | ✔ | ✔ | ✔ |
| Usuarios | ✔ | ✔ (los de su Partner y clientes) | Solo consulta su perfil |
| Plantillas de dispositivo | ✔ (globales) | ✔ (propias) | — |
| Parámetros (factores CO₂, umbrales) | ✔ | — | — |
| Auditoría | ✔ | ✔ (sus edificios) | — |
| Mi cuenta / Cerrar sesión | ✔ | ✔ | ✔ |

## 10. Análisis

**Indicadores** (todas las modalidades), sobre el ámbito actual y filtrables por periodo:
- evolución mensual de energía, emisiones, agua y renovables, comparada con el año anterior;
- ratios por superficie: kWh/m² y kgCO₂e/m² (sobre la superficie útil del edificio);
- % de autoabastecimiento renovable: generación renovable / (consumo + generación renovable);
- reparto del consumo por tipo de suministro.

**Benchmarking** (comparación entre edificios):
- ranking de edificios por kWh/m², kgCO₂e/m² y variación anual;
- comparación entre edificios del **mismo uso** (oficinas con oficinas, hoteles con hoteles);
- según el maestro, el benchmarking **avanzado** es de la modalidad **PRO** o superior. En BASIC se muestra el ranking simple.

## 11. Otros criterios

- **Adaptable a móvil:** en pantallas pequeñas el menú se pliega y el mapa pasa debajo de los KPIs.
- **Idioma:** español. Todos los textos en un único archivo, para poder traducirlos más adelante.
- **Marca configurable** (venta): nombre, logo y colores desde la configuración de la instalación.
- **Fechas y horas** en la zona horaria del edificio; números con formato español (1.234,5).

## 12. Pendiente de definir

| Tema | Nota |
|---|---|
| Página de edificio (HOY, 3D, históricos y gráficas) | Siguiente documento |
| Fórmulas exactas del benchmarking avanzado (normalización por clima, ocupación, horario) | Maestro: P2 |
| Cálculo de `resumenes_diarios` por el motor | Hecho (032) |
