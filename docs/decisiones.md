# Registro de decisiones y cambios respecto al documento maestro v2.0

Este archivo complementa el *Documento maestro v2.0 (15/10/2026)*. Cuando ambos difieren, **prevalece este registro**. Al regenerar el maestro hay que incorporar estos puntos.

## Decisiones del 20/10/2026

| # | Decisión | Afecta a |
|---|---|---|
| D1 | **Modelo de negocio:** venta única de la plataforma con cesión total del código. El comprador contrata y opera su propia infraestructura (Supabase, API, frontend). Cada comprador es una instalación independiente. | §2, §14 |
| D2 | **Supabase es requisito obligatorio** (en la nube o autoalojado). | §14 |
| D3 | **Frecuencia de referencia:** una lectura cada 15 minutos por sensor. | §8, dimensionamiento |
| D4 | **Modelos 3D de EDIFICIO o de RECINTO**, no de planta. Sirve tanto para edificios altos (muchas plantas, pocos recintos por planta) como para edificios extensos (pocas plantas, muchos recintos). Una planta con un único recinto usa el tipo de recinto `PLANTA_COMPLETA`. Como máximo, un modelo activo por edificio y otro por recinto. | §12 (sustituye "edificio o planta") |
| D5 | Dentro de cada instalación se mantiene la jerarquía Administrador → Partner → Cliente → Edificio. El rol `ADMIN_SAAS` corresponde al administrador del comprador. | §6 |

## Decisiones del 21/10/2026

| # | Decisión | Afecta a |
|---|---|---|
| D6 | **Pantallas:** una única plantilla de "ámbito" con tres niveles (Plataforma → Partner → Cliente) y después la página de edificio. Ver `docs/pantallas.md` | §4 |
| D7 | **KPIs:** energía = electricidad + gas (kWh) *(sustituido por D15)*; emisiones = electricidad × **0,183** + gas × **0,182** kgCO₂e/kWh (sustituye el factor común 0,20); agua en m³ aparte; generación renovable = fotovoltaica + solar térmica + geotermia (+ eólica, biomasa) | §9 |
| D8 | Comparación con el **mismo periodo del año anterior**, solo con edificios que tienen datos en ambos periodos | §4 |
| D9 | Los usuarios de cliente con **un solo edificio** entran directamente a la página del edificio (confirmado) | §4 |
| D11 | **HOY** se compara con el **último día equivalente** según el calendario (último laborable si hoy es laborable; último no laborable si no lo es), en el mismo tramo horario | §4, §11 |
| D12 | En el **3D**, el modelo de recinto se elige **en una lista**; no hay etiquetas de recinto en el modelo | §12 |
| D13 | **Ficha** y **Configuración** son pestañas dentro de la página del edificio. Ver `docs/pagina-edificio.md` | §4 |
| D14 | **Diagrama Sankey**: fuentes (red eléctrica, gas, fotovoltaica) → usos (HVAC: climatización y renovación de aire; iluminación; otros). Lo no medido se reparte según configuración o va a "Otros", marcado como estimado | §9 |
| D15 | **Energía consumida** = electricidad importada + gas + renovable consumida (fotovoltaica y eólica autoconsumidas + solar térmica, geotermia y biomasa). Se usa en KPIs, HOY y Sankey. Las emisiones solo cuentan la electricidad importada y el gas. Se añade el % de cobertura renovable | §9 |
| D16 | **Configuración** del edificio en una única pestaña: modo guiado para el alta y navegación libre para editar. Ver `docs/configuracion-edificio.md` | §4 |
| D17 | **Importación desde Excel** de estructura, sensores, coordenadas 3D y calendario, con validación previa | §4 |
| D18 | Al sustituir un GLB, las coordenadas se **copian marcadas "por revisar"** | §12 |
| D19 | **Calendario** en la pestaña Ficha, editable por el Partner y el **cliente avanzado** (este, solo de hoy en adelante). Horario tipo semanal, festivos por país, provincia o municipio, y generación automática del año siguiente desde el 1 de diciembre | §11 |
| D20 | La plataforma admite **edificios con equipos existentes** y **carga de históricos**. Lo anterior al límite de retención se guarda **como resúmenes** diarios o mensuales | §8, §15 |
| D21 | **Alcance actual: solo modalidad BASIC.** PRO y PREMIUM (análisis energético, predicción, **conector Datadis** y **validación de facturas**) quedan para fases posteriores | §3 |
| D22 | **OPC UA** se añade al catálogo de conexiones | §7 |
| D23 | Importación de lecturas en **dos formatos de archivo**: **ancho** (una columna por sensor) y **largo** (fecha, sensor, valor). El formato y el emparejamiento de columnas se guardan como **perfil** reutilizable por edificio | §15 |
| D24 | Al crear una conexión cuyo origen guarda histórico (Sentilo, API REST, OPC UA), el Partner puede pedir la **recuperación automática** del pasado desde una fecha | §7, §15 |
| D25 | **Solo el Partner** (y el administrador) importa históricos: permiso `IMPORTAR_HISTORICOS`. El cliente, ni siquiera el avanzado, no importa | §5 |
| D26 | Toda importación pasa antes por una **simulación** que muestra qué se guardaría, qué se rechazaría y mínimos, máximos y medias por sensor | §15 |
| D27 | **Altas de usuarios sin invitación:** el administrador de la plataforma y el Partner (administrador **y técnico**) crean usuarios con email y **contraseña inicial**. El técnico no puede crear administradores del Partner | §5 |
| D28 | ~~La contraseña inicial se cambia obligatoriamente~~ (sustituida por D39; se mantiene el mínimo de 10 caracteres, letras y números) | §5 |
| D29 | **Doble factor por email:** código de 6 cifras, válido 10 minutos, 5 intentos y máximo 5 códigos cada 15 minutos. Se pide en cada sesión nueva | §5 |
| D30 | Doble factor **obligatorio** para el administrador de la plataforma y los administradores de Partner (`roles.requiere_doble_factor`, configurable) y **voluntario** para el resto | §5 |
| D31 | Conector **Sentilo** (consulta cada 15 min y recuperación de históricos) y **LoRaWAN** por webhook del servidor de red (The Things Stack y ChirpStack), con la carga decodificada en origen | §7 |
| D32 | Los conectores se desarrollan y prueban con **simuladores** integrados en la API (solo desarrollo y demos), sin usar datos de edificios reales hasta tener un edificio propio | §7 |
| D33 | La **tarea periódica** la dispara Supabase (pg_cron + pg_net) llamando a la API cada 15 minutos | §7 |
| D34 | **Conector API REST genérico** configurable (JSON por GET o POST, autenticación, rutas, filtros y periodo). El simulador de demostración es una API REST neutra | §7 |
| D35 | El doble factor se mantiene **solo por email** (27/10/2026). Se valoró la app de códigos TOTP (gratuita en Supabase): queda como mejora futura; la base de datos ya acepta `aal2` | §5 |
| D36 | **Recuperación de contraseña con código por email** (27/10/2026): "¿Has olvidado la contraseña?" envía un código de 6 cifras y con él el usuario elige una contraseña nueva. La respuesta es la misma exista o no el email | §5 |
| D37 | **Frontend en Vue 3 + Vite** (repositorio `digital-twin-energy-web`), sitio estático en Render. Lee los datos con la clave pública de Supabase y la sesión del usuario (RLS); las acciones que lo requieren pasan por la API | §8 |
| D38 | **Edición de usuarios** (27/10/2026): nombre, apellidos, teléfono, rol dentro del mismo tipo (plataforma, Partner o cliente) y asignaciones. El email y el Partner no cambian; para otro tipo de usuario, baja y alta nueva. Sobre uno mismo, solo los datos personales | §5 |
| D39 | **Alta sin contraseña** (27/10/2026): quien da de alta solo indica email, nombre, rol y ámbito. La cuenta se crea con una contraseña aleatoria que nadie ve, el usuario recibe un **email de bienvenida** y elige su contraseña con «¿Primera vez o ha olvidado la contraseña?». El antiguo «restablecer contraseña» pasa a ser **«Anular contraseña»** (para contraseñas comprometidas). Sustituye a la contraseña inicial de D28 | §5 |
| D40 | **Motor de cálculo en la base de datos** (27/10/2026): funciones SQL ejecutadas por pg_cron cada 15 minutos (no por la API). Solo calcula por edificio; Cliente, Partner y Plataforma suman los resúmenes de sus edificios al consultar. Intervalos de 15 min; contadores repartidos en el tiempo; gas en m³ → kWh con FACTOR_CONVERSION_GAS (11,70 kWh/m³) | §8 |
| D41 | **Pestaña Hoy** (27/10/2026): dos columnas (KPIs a la izquierda; 3D o, sin 3D, lista de sensores a la derecha) y debajo la curva de 15 min con el horario sombreado y el Sankey. KPI «Energía total consumida» con desglose por fuente y emisiones totales; KPI «Potencia» con factor de potencia, ambos comparados con el día comparable. Sin tarjetas de emisiones, renovable ni fuera de horario (este va a alarmas y avisos) | §9 |
| D42 | **Página de edificio en tres zonas** (02/11/2026), sustituye a la disposición de D41: en horizontal 1/3 · 1/2 · 1/6. Izquierda: pestañas **Hoy**, **Suministros de red** y **Producción renovable** (lo único que cambia). Centro: 3D (si está contratado) o lista de sensores de la planta más baja a la más alta (2/3 de la altura) y la gráfica (1/3) con selector de magnitud, periodo y agrupación (15 min, hora, día, semana, mes); al pulsar un sensor se ve su gráfica. Derecha: alarmas. Sin pestañas de 3D ni de alarmas; Históricos va en la gráfica; Ficha y Configuración, botones de la cabecera. Hoy: KPI de energía (con % por fuente), Sankey y ambiente por recinto. Potencia, factor de potencia y agua pasan a Suministros de red | §9 |
| D43 | **Ambiente por recinto** (02/11/2026): temperatura de confort por edificio (19 < confort < 27, por defecto 25 °C) y temporadas por fechas (por defecto invierno 01/11–31/03, verano 01/06–30/09). Invierno: ≤19 verde, hasta el confort naranja, más rojo. Verano: ≥27 verde, desde el confort naranja, menos rojo. Fuera de temporada, sin color. Humedad todo el año: 30–70 % verde, fuera rojo. CO₂ sin color de momento. Valor: el último de cada recinto | §9 |
| D44 | **Cabecera sin menú lateral** (02/11/2026): logotipo a la izquierda; campana de alarmas (todas las de los edificios del usuario) y usuario (Mi cuenta, Usuarios, Cerrar sesión) a la derecha, en todas las páginas. En el edificio, nueva pestaña **Condiciones ambientales** con el ambiente por recinto; **Hoy** queda en dos mitades: energía y Sankey | §9 |
| D45 | **Hoy en tres bloques y temperaturas configurables** (03/11/2026), sustituye en parte a D43 y D44. La pestaña Hoy es un desplazamiento vertical con tres bloques del mismo alto: **energía** (cada fuente con su energía, su **aporte al total** y su % frente al día comparable; **emisiones** totales y separadas en electricidad de la red y gas, las renovables no emiten), **Sankey** y **ambiente por recinto**. Se quita la pestaña Condiciones ambientales. Banda de alarmas más estrecha y gráfica más alta. Por edificio y temporada se configuran la **temperatura de eficiencia** (en España la del RITE: 19 °C en invierno, 27 °C en verano) y la **de confort** (25 °C por defecto), para poder usar la plataforma en países con otros límites. Invierno: ≤ eficiencia verde, ≤ confort naranja, más rojo (eficiencia < confort). Verano: ≥ eficiencia verde, ≥ confort naranja, menos rojo (confort < eficiencia) | §9 |
| D46 | **Cuadros eléctricos y función de cada medidor** (03/11/2026). Cada medidor de energía se configura en este orden: qué mide (contador general, total de un cuadro o submedidor de un uso), su uso (solo submedidores) y el cuadro del que depende o ninguno (medidor independiente, como el gas de una caldera). Los cuadros están en una planta o en un recinto y pueden colgar de otro (el local, del de planta baja). Otros usos de un cuadro = total − submedidores − cuadros que cuelgan de él; lo que el contador general no reparte es "Otros usos · no medido" (estimado). Usos: HVAC (climatización, refrigeración, calefacción, ACS, calefacción y ACS, renovación de aire), Alumbrado y Otros usos (informática, servicios comunes y resto). Sankey: fuentes → vector → grupo → detalle por uso (HVAC) o por uso y cuadro (Alumbrado, Otros usos); compacto en Hoy y con el detalle al pulsar **Ampliar**. Demo: torre de oficinas (sótano, planta baja con local, plantas 1–5 y cubierta con el cuadro de HVAC; gas 55 %, refrigeración 30 %, renovación 15 % del HVAC; fotovoltaica) que sustituye a DEMO-OFICINAS | §8, §9 |
| D47 | **La gráfica del panel muestra cualquier dato** (03/11/2026). El desplegable, con buscador, ofrece las series de energía del edificio (energía total consumida, electricidad de la red, gas, renovables, fotovoltaica, exportada, emisiones), los usos y cuadros del Sankey (totales de HVAC, alumbrado y otros usos, cada uso final y cada uso por cuadro), las demás magnitudes (potencia, factor de potencia, agua) y todos los sensores. Pulsar un dato lo muestra en la gráfica: KPI de energía y emisiones, usos finales de la última columna del Sankey **solo en la vista ampliada** (con el periodo del Sankey), valores de ambiente, lista de sensores, alarmas y datos de las pestañas Suministros y Producción. Energía: líneas cada 15 min o por horas, barras por días, semanas o meses; con «Hoy», comparada con el día comparable. El motor guarda la serie de 15 min de cada uso y cuadro (opción a), de la que sale también el Sankey. Si el día comparable tiene menos del 90 % de los cuartos de hora que tiene hoy, no se da la variación ("Día comparable incompleto") | §9 |
| D48 | **Usos determinados y otros usos** (09/11/2026), modifica D46. Un submedidor con uso asignado mide ese uso: la informática es informática, no "otros usos". **Otros usos** es solo lo que no tiene uso determinado: la diferencia de cada cuadro (total − submedidores) y lo que el contador general no reparte. Usos principales: HVAC (con sus usos finales), Alumbrado, Informática, Servicios comunes y Otros usos. El Sankey compacto muestra los totales de esos usos; se amplía **pulsando el diagrama** (se quita el botón «Ampliar»). En el panel, el 3D o la lista de sensores ocupa 5/8 del alto y la gráfica 3/8 (mínimo 250 px) | §9 |
| D49 | **Interfaz compacta y temas** (10/11/2026). Letra compacta en toda la plataforma, como los EMS: base 13 px y nada por debajo de 11 px; cabecera de 48 px. Tema **claro, oscuro o automático** (sigue al sistema), elegido en el menú del usuario y guardado en el navegador. Colores en variables CSS (`estilos/base.css`) y paleta de gráficas por tema. El Sankey muestra la energía de cada nodo; en el ampliado, también el % de la energía consumida (kWh; desde 10.000 kWh, MWh) | §9 |
| D50 | **Distribución compacta del panel del edificio** (10/11/2026), modifica D45. Columna izquierda (pestaña Hoy): KPI de energía y Sankey, que ocupa el resto del alto. Centro: 3D o lista de sensores (2/3 del alto) y gráfica (1/3, mínimo 200 px, letra de 11 px). Columna derecha, algo más ancha: alarmas (mitad superior) y ambiente por recinto (mitad inferior), cada una con su desplazamiento vertical. Menos espacio entre cabecera, título y pestañas, e interlineado más ajustado en los KPI | §9 |
| D51 | **Visor 3D y modelos desde Revit o Blender** (11/11/2026), modifica D10. Proceso en tres etapas, igual para todos los Partners (`docs/modelos-3d.md`): exportar (Revit con Leia, vista 3D sin barandillas, mobiliario ni equipos; o Blender), **preparar** con `herramientas/modelo3d` (metros y Y arriba, solo id, categoría, nivel y tipo de cada elemento, geometría agrupada por nivel y material, Draco, informe con límites) y publicar. Cada planta indica qué **niveles del modelo** la forman (`plantas.niveles_modelo`, varios por planta; los no asignados van por cota). En el panel, el centro muestra el modelo (botón 3D \| Lista): «Todo el edificio» o una planta (oculta las superiores y muestra las etiquetas de sus sensores con valor y estado); pulsar una etiqueta la lleva a la gráfica; pulsar el modelo identifica el elemento y, a Partner y administrador, da el punto X, Y, Z. Demo: el modelo de ejemplo de Revit; la planta 1 de la torre pasa a ser la **entreplanta** | §9, §12 |
| D56 | **Pestaña Hoy en transparencia y corte esquemático sin 3D** (16/11/2026). En Hoy, con «Todo el edificio» el edificio se ve semitransparente (40 %; en Ambiente, 12 %) solo con las **etiquetas de suministro**: los contadores que alimentan el KPI de energía y el agua (Electricidad de la red, Gas, Renovables, Agua), con su título y color del KPI, el consumo de **hoy** (en la unidad del contador y, si no es kWh y es energía, también en kWh: el gas en m³ y kWh; el agua solo en m³) y la variación frente al día comparable; con varios contadores de un suministro, una etiqueta en cada uno (migraciones 045 y 046). Con una planta elegida, esa planta opaca (100 %), las de debajo como referencia (15 %) y todo lo que queda por encima de su techo recortado (también escaleras, núcleos o muros cortina que suben desde abajo), con todas sus etiquetas. **Los contadores (energía, gas, agua) muestran siempre el consumo de hoy**, no la lectura acumulada. En el esquema se ve siempre todo. Si se tapan entre plantas, la de menos prioridad queda como punto (la distancia mínima de D53 sigue siendo solo por planta). En las demás pestañas, el edificio opaco. **Edificios sin modelo 3D**: en lugar de la lista de sensores, un **corte esquemático** generado con la configuración (una franja por planta de la cubierta al sótano, recintos como cajas con ancho según su superficie y las etiquetas por dispositivo con la misma estética del 3D; en Ambiente, cajas con el color de la temperatura y leyenda), con la gráfica fija debajo. En los edificios **con** 3D, el botón **3D | Esquema** permite ver también el corte (con la gráfica flotante); la elección se recuerda en el navegador | §9 |
| D57 | **Pestaña Suministros y medidor general obligatorio** (16/11/2026). Con 3D, el edificio entero (sin selector de planta, al 40 %) con **una etiqueta por suministro** en el punto de su medidor general: compacta (consumo de hoy, potencia y cos φ en electricidad; consumo en gas —m³ y kWh— y en agua) y, al pulsar su cabecera, **desplegada** con todos los parámetros que mide; cada fila abre su gráfica. En la columna izquierda, **fichas desplegables una debajo de otra** (electricidad, gas, agua): parámetros del medidor en vivo (pulsables), **gráfico mensual de barras** de este año frente al anterior (electricidad y gas en kWh; agua en m³) y datos del contrato (comercializadora, distribuidora, CUPS, nº de contrato o póliza, alta, tarifa, potencias contratadas, contador…). La ficha abierta se despliega también en el 3D. En el **esquema** (edificios sin 3D o botón Esquema) se ven igualmente solo las etiquetas de los suministros, en el recinto de su medidor general, como en Ambiente solo las ambientales. La generación (FV…) va en la pestaña Producción. **Medidor general**: cada suministro tiene un dispositivo marcado como medidor general y sus sensores dicen qué miden (catálogo `parametros_medidor`). **Obligatorios** (bloquean el cierre de la parametrización): en electricidad, consumo (energía activa importada), potencia activa y factor de potencia; en gas, el consumo. Además, sin suministro eléctrico no se cierra. **Opcionales**: energía exportada y reactiva, potencias reactiva y aparente, tensión e intensidad por fase, intensidad de neutro y frecuencia; presión del gas; caudal instantáneo, presión (bar) y temperatura del agua (051). En el agua, el medidor es un aviso. Los opcionales no ocupan fila en las etiquetas del resto de pestañas ni cuentan para la distancia mínima entre etiquetas (D53) | §5, §9, configuración |
| D58 | **Pestaña Producción** (17/11/2026), con el mismo criterio que Suministros: 3D de todo el edificio sin selector de planta, con las **placas iluminadas** según lo que producen (de azul oscuro a amarillo intenso: % de la potencia pico en FV, de la nominal en solar térmica) y una etiqueta por instalación que se despliega; en el esquema, solo las instalaciones (caja «Placas» en su planta). A la izquierda, una ficha desplegable por instalación: KPIs de hoy, medidor en vivo, producción mensual de este año frente al anterior y datos de la instalación. Se empieza por **fotovoltaica y solar térmica**. **Medidor de producción obligatorio** (bloquea la parametrización): energía producida y potencia. KPIs FV: producción, variación, potencia y % del pico, autoconsumo, excedente, cobertura, kWh/kWp, PR (con irradiancia) y emisiones evitadas. Solar térmica: **no** se calcula «gas ahorrado» (depende de cómo se produzca el calor); en su lugar, el **aporte solar** a los usos servidos y, en el **Sankey**, el calor solar llega a esos usos (reparto del calor renovable) junto al gas o la electricidad, con el desglose por energía al pasar el ratón. **Placas en el 3D**: del modelo, marcadas «FV: campo» / «ST: campo» en *Comentarios* o *Marca* (Revit) o en la propiedad *Produccion* (Blender), o dibujadas como polígono sobre una planta | §5, §9, configuración, modelos 3D |
| D59 | **Motor de alarmas** (23/11/2026). Dos tipos de regla: **libres** (umbral sobre un sensor o una magnitud, las de siempre) y **de la plataforma** (catálogo `tipos_regla_alarma`, 21 reglas con umbrales recomendados). **El Partner las activa y elige el nivel de cada una de acuerdo con el cliente.** Tres niveles: **MUY CRÍTICA** (email inmediato, solo lo que no puede esperar), **CRÍTICA** (resumen diario por email) y **AVISO** (informes semanales y mensuales); todas se ven en la plataforma (campana, pestaña Alarmas, 3D). Muy críticas recomendadas: electricidad sin suministro (las tres tensiones < 20 V), fallo de fase (una fase < 80 % de 230 V con las otras bien), cos φ < 0,80 durante 15 min, maxímetro > 100 % de la potencia contratada del periodo P1–P6 en curso (media de 15 min; preaviso al 90 % como crítica); agua sin suministro (< 0,5 bar) y presión excesiva (> 5 bar); gas sin suministro (< 60 % de la presión de operación) y presión excesiva (> 130 %); posible corte (el medidor general y los demás equipos dejan de comunicar a la vez). Críticas: consumo fuera de horario, cos φ < 0,95 durante 1 h, fuga de agua (fuera de horario el caudal no baja del umbral en horas), consumo anómalo del día, FV con bajo rendimiento o inversor parado, solar térmica sin circulación, temperatura muy alejada de la eficiente y CO₂ > 1500 ppm (> 1000, aviso). Los fallos de comunicación, aviso. **Sin impacto en €** en BASIC: precios, facturas y la comparación de la curva de la compañía con la de los sensores van al pack PRO. **Estados**: ACTIVA (causa presente, sin atender) → RECONOCIDA (alguien se ocupa; la causa sigue) → RESUELTA (la causa ha desaparecido, falta cerrarla) → CERRADA. **Nadie puede cerrar mientras la causa siga**; con **rearme automático** se cierra sola al resolverse. Si la causa vuelve antes de 60 min, se reabre el mismo evento (sin nuevo email). Se puede **silenciar** hasta 30 días con fecha y motivo (obra, mantenimiento); si al acabar sigue, vuelve a avisar. **Escalado**: una muy crítica sin reconocer en N minutos (15 por defecto) se envía también a los destinatarios de escalado. **Emails**: dominio propio con SPF, DKIM y DMARC; enlace «Reconocer en la plataforma» a la alarma. SMS, Telegram y notificaciones push quedan preparados para más adelante (canal en `notificaciones`) | §5, §9, configuración |
| D60 | **Renovables, almacenamiento y piloto** (23/11/2026, a desarrollar después de las alarmas). Las **redes urbanas de calor y frío** son un suministro (energía consumida, como el gas: kWh por el agua a temperatura). La **eólica** sigue el principio de la FV (autoconsumo como entrada de electricidad y excedentes, normalmente todo a venta). **Geotermia y cogeneración**, como la solar térmica (calor que reduce lo que aporta la caldera o la electricidad). Las **baterías** tienen su propia pestaña, **Almacenamiento**. En Producción se muestran también las tecnologías **no instaladas**, como tarjetas en gris con un «Ejemplo», visibles para todos los usuarios (enseñan lo que puede hacer la plataforma), con una opción por edificio para ocultarlas. **Orden**: 1) alarmas e informe mensual; 2) eólica y baterías; 3) bombas de calor, cogeneración, biomasa y redes urbanas. **Piloto**: un edificio `DEMO-` en el Supabase de pruebas con acuerdo firmado (piloto y encargo de tratamiento, RGPD art. 28), buscado a través de un Partner instalador o mantenedor; antes, actualizar `demo_limpiar.sql` con las tablas nuevas | §5, §9 |
| D61 | **Informes semanal y mensual del edificio** (24/11/2026). Se generan solos: el **semanal** cada lunes (semana anterior, más resumido: energía, consumo diario, dentro y fuera de horario, alarmas, avisos y calidad de datos) y el **mensual** el día 1 (además, comparación con el mismo mes del año anterior, producción renovable y ambiente por recinto). Cada informe es una foto guardada que se consulta en el edificio (botón **Informes**) y se descarga en **PDF**. Se envía por **email** (cifras clave y enlace) a los destinatarios que **elige el Partner** por edificio. **Marca doble**: logo del Partner y nombre de la plataforma. Los informes de **cliente** (todos sus edificios) y de **Partner** (todos sus clientes y edificios) se definirán con esas pantallas | §9, informes |
| D55 | **Escala de temperatura por eficiencia** (12/11/2026; implementada el 16/11/2026, migración 043), modifica D45 y la migración 036. Solo se muestra la **eficiencia**: se elimina la temperatura de confort (la plataforma no actúa sobre la consigna) y no hay avisos de demasiado frío o calor. Por edificio, junto a los meses de invierno y verano (`temporada_edificio`): **Te de invierno entre 19 y 21 °C** (por defecto 19) y **Te de verano entre 25 y 27 °C** (por defecto 26). Cinco tramos: invierno T ≤ Te verde esmeralda `#10B981`; Te < T ≤ Te+1 verde lima `#84CC16`; Te+1 < T ≤ Te+2,5 ámbar `#F59E0B`; Te+2,5 < T ≤ Te+4 rojo `#EF4444`; T > Te+4 rojo oscuro `#991B1B`. Verano, simétrico: T ≥ Te esmeralda; Te−1 ≤ T < Te lima; Te−2,5 ≤ T < Te−1 ámbar; Te−4 ≤ T < Te−2,5 rojo; T < Te−4 rojo oscuro. **Entretiempo: sin colores** (solo el valor). Se aplica en la pestaña Ambiente y en el 3D: en Ambiente el edificio se ve semitransparente y cada recinto con sensor de temperatura se ilumina con su color (sin datos, gris). Volúmenes de los recintos (revisado 16/11/2026): **el GLB debe traer los volúmenes de las habitaciones con su nombre**, hechos con la herramienta que sea (en Revit las habitaciones no se exportan: se convierten en DirectShape de Modelos genéricos con Dynamo, con el nombre de la habitación; en Blender, objetos con la propiedad `Volumen` = nombre). La herramienta de preparación los conserva aparte, les asigna el nivel por la cota de su base (y de ahí la planta por `niveles_modelo`), una clave interna única (los nombres se repiten) y su superficie. Al configurar un **sensor de temperatura**, la plataforma lista los volúmenes de su planta («Live/Work Unit · 72 m²», resaltados en el 3D al pasar por ellos; propone el que contiene la etiqueta) y el Partner asigna **uno o varios volúmenes** al sensor. Al sustituir el GLB se reencuentran por planta, nombre y posición; los demás quedan «por revisar». Descartados: detección automática de espacios por muros y volúmenes dibujados en la plataforma | §9, §12 |
| D54 | **Clima exterior** (12/11/2026; implementada el 16/11/2026, migración 044). Previsión y tiempo actual de **MET Norway** (api.met.no, Locationforecast 2.0; datos CC BY 4.0 con cita de la fuente, User-Agent identificado, respuestas guardadas según `Expires`, nunca llamado desde el navegador). La API consulta **cada 60 minutos** por edificio (latitud y longitud de `edificios`) y lo guarda en la base de datos; la web lo lee de ahí. Se guardan la **observación de cada hora** y la **previsión de los próximos días** (base para la predicción de versiones PRO/PREMIUM; el histórico antiguo, más adelante con NASA POWER). Open-Meteo descartado: su servicio gratuito no admite uso comercial. En pantalla: recuadro sobre el 3D con **icono** (sol, sol con nubes, nublado, lluvia, niebla, nieve, tormenta; día y noche; juego de iconos propio en SVG), **temperatura, humedad, viento y UV** (de cielo despejado), y al pulsarlo las próximas horas o días; fila «Exterior» en la pestaña Ambiente. **Sensores exteriores propios**: si el edificio tiene sensor de temperatura y/o humedad exterior y comunica, se muestra su valor; si no comunica o no tiene, se muestra el de MET Norway, que se guarda siempre como respaldo (y para la predicción) | §9 |
| D53 | **Etiquetas 3D sin solape** (12/11/2026; implementada el 16/11/2026, migración 042). 1) Una etiqueta por **dispositivo**, del mismo ancho, con una fila por sensor y un solo punto; en Configuración se coloca el dispositivo y sus sensores heredan el punto. 2) **Altura fija: 1,5 m** sobre el suelo de la planta para todas las etiquetas; el Partner solo pulsa el punto en planta. 3) Límites de la vista: **zoom mínimo = encuadre** (del edificio o de la planta) y **ángulo mínimo de cámara 35°** sobre la horizontal. 4) **Distancia mínima fija** entre etiquetas de la misma planta, calculada por la plataforma para cada modelo (tamaño del modelo, ancho y alto de la etiqueta según sus filas, pantalla de referencia de portátil), sin opción de cambiarla; si sale exagerada, el edificio necesita modelos por recinto. 5) **Bloqueo**: una posición más cercana no se guarda («valor no permitido»), comprobado en la base de datos (trigger) para que valga también por Excel. Plan: migración 042 (ubicaciones por dispositivo, medidas del modelo en `modelos_3d`, función de distancia mínima y trigger, con pruebas), visor (etiquetas multifila, límites) y demo (unas 2 etiquetas por recinto) | §12 |
| D52 | **El 3D es la base del panel del edificio** (11/11/2026), modifica D48, D50 y D51. Con modelo 3D: columna izquierda (30 %) con las pestañas **Hoy · Suministros · Ambiente · Producción · Alarmas** (contador en rojo) y el visor 3D en el resto, sin lista de sensores (un sensor se busca en el 3D o en el desplegable de la gráfica). La **gráfica flota** sobre la parte baja del 3D, semitransparente, con Ampliar y Cerrar; no se abre sola, sino al pulsar un KPI, el Sankey ampliado, un sensor, una alarma o un valor de ambiente. Pulsar una alarma o un recinto lleva el 3D a su planta. **Etiquetas**: punto en la posición X, Y, Z exacta y el valor con su unidad pegado a él; el nombre, al pasar el ratón. No se apilan: si el valor de una tapa al de otra con más prioridad (seleccionada, en alarma, más cercana), solo se ve su punto. En «Todo el edificio» se ven la seleccionada y las de alarma; en una planta, las suyas. Sin modelo 3D: mismas pestañas y, en el centro, lista de sensores y gráfica fija | §9, §12 |
| D10 | Las **coordenadas 3D** (X, Y, Z) se obtienen sobre el archivo preparado: **pulsando en el visor de la plataforma** (muestra el elemento y el punto; en Configuración se asignará al sensor), o a mano / por Excel con cualquier visor de GLB. Más adelante, desde sensores modelados como familias de Revit. Actualizada por D51 | §12 |

## Cambios técnicos aplicados en las migraciones (20/10/2026)

**Seguridad**
- RLS activado en todas las tablas (67 tras la migración 026) desde la migración que las crea. Las particiones también tienen RLS y están en un esquema no expuesto.
- Las tablas de usuarios, roles y asignaciones tienen políticas de lectura por alcance y **no** admiten escritura directa. Las altas se hacen desde el backend con `service_role`.
- El rol anónimo no tiene acceso a ninguna tabla.
- Alta de edificio por Partner mediante `crear_edificio_partner()`.
- Protección de columnas sensibles:
  - cambiar el cliente de un edificio queda reservado al administrador;
  - dar de baja exige `DAR_BAJA_*`.
- Alarmas: no se editan directamente; se reconocen o cierran con `reconocer_alarma()` y `cerrar_alarma()`.
- Auditoría **automática por triggers** en las tablas de configuración (37 tras la 021). Ya no se puede escribir a mano. En las modificaciones solo guarda los campos cambiados.
- Las filas de auditoría sin edificio asociado solo las ve el administrador de plataforma.
- Storage 3D: un archivo solo se puede subir o leer si existe su registro en `modelos_3d` y el usuario tiene permiso sobre ese edificio.

**Integridad**
- Validación de "mismo edificio":
  - reglas de alarma ↔ sensor/magnitud, recintos y usuarios destinatarios;
  - eventos ↔ regla;
  - suministro ↔ dispositivo;
  - Partner ↔ cliente del edificio.
- Detección de ciclos entre magnitudes (A→B→A).
- Histórico de ubicaciones físicas automático. Al mover un dispositivo se mueven sus sensores.
- Como máximo un evento abierto por regla y recinto. Una alarma RECONOCIDA exige fecha.
- Plantas con nivel negativo (sótanos).

**Datos y escalabilidad**
- `lecturas` particionada por mes: 117 bytes por lectura frente a 354 del diseño anterior. El tipo de lectura lo define el sensor, no cada fila.
- `valores_magnitud` particionada por año.
- Retención corregida a **año actual − 4** (antes −5), eliminando particiones completas.
- Tarea diaria `mantenimiento_datos()` con pg_cron.
- Políticas de las tablas grandes evaluadas una vez por consulta.

**Alineación con el maestro**
- Catálogos:
  - conexiones: + BACnet, Modbus TCP;
  - dispositivos: + presencia/ocupación;
  - familias: INTENSIDAD (no CORRIENTE);
  - naturalezas: instantánea, acumulativa, estado, contaje;
  - tratamientos: directo, delta, promedio, máximo, mínimo, suma, estado, contaje.
- Partner y Cliente con estado OPERATIVO / SUSPENDIDO / BAJA.
- Roles:
  - `TECNICO_PARTNER` gestiona usuarios;
  - `USUARIO_CLIENTE` ya no reconoce alarmas (reservado al avanzado).
- Campos añadidos:
  - suministros: % de energía verde (electricidad) y fecha de puesta en marcha (generación);
  - eventos: fecha de fin y comentario;
  - notificaciones: destinatario, reintentos e incidencia de comunicación.
- El factor de CO₂ (`parametros_saas`) es legible por todos los usuarios para mostrarlo junto al KPI.
- La antigua 019 (pruebas) pasa a `supabase/tests/database/`. La nueva 019 contiene la instalación del primer administrador y la verificación de RLS.

## Migración 021 · Parametrización genérica de conectores (21/10/2026)

- Cuatro modos de conexión:
  - CONSULTA (Sentilo, API REST);
  - SUSCRIPCIÓN (MQTT);
  - ENVÍO (HTTP estándar);
  - PASARELA (Modbus TCP y BACnet mediante un equipo en el edificio).
- Cada tipo de conexión define con JSON Schema sus parámetros y cómo se direcciona cada punto. No hay tablas por protocolo (coherente con el maestro).
- Sensores con dirección en el origen, escala, desplazamiento, unidad de origen, rango válido y política de vacíos (DESCARTAR, CERO, MANTENER_ULTIMO). La política se define por sensor, como pide el maestro §8.
- Plantillas de dispositivo, globales o privadas de un Partner, que crean el dispositivo y todos sus sensores.
- Canal único de entrada `procesar_lecturas()`:
  - identifica el punto;
  - interpreta fechas con o sin zona y en epoch;
  - aplica la transformación y el rango;
  - descarta duplicados;
  - actualiza el estado de comunicación;
  - devuelve un resumen con los motivos de cada rechazo.
- Tokens de envío por conexión, guardados como huella SHA-256. Los secretos van en Supabase Vault.
- Nuevo tipo de conexión `ENVIO_HTTP` y nuevo permiso `GESTIONAR_PLANTILLAS`.
- Coherencia con la 002 y la 009:
  - el tipo `IOT` queda desactivado (lo sustituye `ENVIO_HTTP`);
  - `OTRA` se reserva para importaciones de archivos;
  - `sensores.magnitud_origen` pasa a ser solo descriptivo;
  - el umbral de comunicación se toma de `parametros_saas`;
  - la nueva función `revisar_comunicacion()` (pg_cron, cada 15 min) abre las incidencias, y al volver a llegar lecturas se cierran solas.
- Asistente del Partner:
  - estado de configuración por sensor (PENDIENTE/PROBADO/ERROR) e historial `pruebas_lectura`;
  - vista previa `transformar_valor`;
  - lista de comprobación `estado_parametrizacion_edificio` y `cerrar_parametrizacion`, que pasa el edificio a OPERATIVO solo si no falta nada bloqueante (maestro §4).
- Guías: `docs/conectores.md` y `docs/configuracion-partner.md`.

## Migración 022 · KPIs y resúmenes (21/10/2026)

- Factores de CO₂: 0,183 (electricidad) y 0,182 (gas), con fecha de vigencia. La función `factor_co2(codigo, fecha)` devuelve el aplicable a cada día.
- Tecnologías de generación: se añaden SOLAR_TERMICA, GEOTERMIA y BIOMASA. La columna calculada `renovable` excluye la cogeneración.
- Magnitudes por suministro: CONSUMO_ELECTRICIDAD, CONSUMO_GAS, CONSUMO_AGUA, GENERACION_FOTOVOLTAICA, GENERACION_SOLAR_TERMICA, GENERACION_GEOTERMIA y GENERACION_OTRAS_RENOVABLES.
- `resumenes_diarios`: totales por edificio, día e indicador. Los rellena el motor (Fase 5) y alimentan todos los dashboards sin recorrer lecturas.
- `kpis_ambito(nivel, id, fecha)` y `kpis_lista(nivel, id, fecha)` calculan los KPIs y la variación respetando los permisos de cada usuario.

## Migración 023 · Página de edificio (21/10/2026)

- `dia_calendario` y `dia_comparable`: carácter del día según el calendario. Sin calendario: lunes a viernes laborable.
- `hoy_edificio`: la pestaña HOY en una llamada. Incluye energía, emisiones, agua, renovables y autoconsumo; día comparable y variación; potencia actual; consumo fuera de horario; y curva de 15 min de hoy y del día comparable.
- `serie_magnitud` y `serie_sensor`: históricos agrupados (15 min a año) con filtro de calendario. Los contadores acumulativos devuelven el consumo por intervalo.
- `sensores_estado_edificio`: sensores con valor actual, estado, alarma y posiciones 3D (etiquetas y paneles).
- `estado_comunicacion.ultimo_valor` (añadido en la 021): valor de la última lectura de cada sensor.

## Migración 024 · Usos finales y Sankey (21/10/2026)

- Catálogo jerárquico `usos_energia`: HVAC → climatización y renovación de aire; iluminación; otros usos. Ampliable.
- `sensores.id_uso_energia`: uso final que mide cada submedidor. Solo usos finales, no grupos.
- `repartos_uso_edificio`: % de la energía no medida por tipo (electricidad, gas) y uso, con un máximo de 100 %.
- `resumenes_diarios_usos` (lo rellena el motor) y nuevo indicador `ELECTRICIDAD_EXPORTADA`.
- **Aclaración:** `CONSUMO_ELECTRICIDAD` es la electricidad **importada de la red**. La energía consumida por el edificio se calcula según D15.
- Renovables separadas en eléctricas (fotovoltaica, eólica: pueden exportarse) y térmicas (solar térmica, geotermia, biomasa: "calor renovable" en el Sankey).
- `sankey_energia(nivel, id, desde, hasta)`: nodos y enlaces con la parte estimada separada y avisos de incoherencia.

## Migración 025 · Configuración y edición de edificios (21/10/2026)

- No se desactivan plantas o recintos con elementos activos.
- `sustituir_sensor` y `sustituir_dispositivo`: el elemento nuevo mantiene el código y hereda magnitud, uso, posición 3D, reglas, ámbitos y suministros. El antiguo queda inactivo con su histórico (maestro §5).
- `sustituir_modelo_3d`: nueva versión del GLB con coordenadas copiadas "por revisar" (`ubicaciones_3d.por_revisar`, añadida en la 021). Se revisan con `confirmar_coordenadas`, o se confirman solas al corregirlas.
- Calendario:
  - `horarios_tipo_edificio` y `festivos`;
  - `es_festivo` y `generar_calendario`;
  - generación anual dentro de `mantenimiento_datos`;
  - permiso MODIFICAR_CALENDARIO para el cliente avanzado, con bloqueo de días pasados para los usuarios de cliente.

## Migración 026 · Históricos y edificios existentes (21/10/2026)

- `procesar_lecturas(..., p_historico)`: modo histórico, que no altera el estado de comunicación, las incidencias ni el estado de prueba. Admite calidad por lectura. Los rechazos por antigüedad indican importar como resumen. (Cambio aplicado en la 021.)
- `importaciones`, `importaciones_lotes`, `crear_importacion` y `procesar_lote_lecturas`: cargas por lotes, idempotentes y reanudables.
- `recalculos_pendientes`: periodos que el motor debe rehacer.
- `importar_resumenes`: resúmenes diarios o mensuales, para periodos antiguos o datos de factura. `resumenes_diarios.origen` distingue motor e importación.
- `generar_calendario(..., p_incluir_pasado)`: calendario de años pasados para el Partner. (Cambio aplicado en la 025.)
- Tipo de conexión `OPC_UA`.
- Permiso `IMPORTAR_HISTORICOS` (ADMIN_SAAS, ADMIN_PARTNER, TECNICO_PARTNER), exigido por `crear_importacion`, `importar_resumenes` y `solicitar_recuperacion` (D25).
- Simulación: `simular_lecturas` (= `procesar_lecturas(..., p_historico => true, p_simular => true)`, con comprobación de permiso) e `importar_resumenes(..., p_simular => true)`. No guardan nada (D26).
- `puede_importar(edificio)`: la API comprueba el permiso antes de leer un archivo.
- `importar_resumenes` con importación: cuenta lotes y cierra la importación al recibir el último.
- `perfiles_importacion`: formatos ANCHO y LARGO guardados por edificio (D23).
- Recuperación automática: `tipos_conexion.admite_recuperacion`; en `conexiones`, `recuperar_desde`, `recuperacion_estado`, `recuperado_hasta` e `id_importacion_recuperacion`; funciones `solicitar_recuperacion` (ajusta la fecha al límite de retención y avisa) y `avanzar_recuperacion` (la usa la API) (D24).
- Vía API para empresas IoT con el token de la conexión: `crear_importacion_token` y `procesar_lote_token`.
- Guía: `docs/edificios-existentes-historicos.md`.

## Migración 027 · Usuarios, contraseña inicial y doble factor (26/10/2026)

- `roles.requiere_doble_factor` (ADMIN_SAAS y ADMIN_PARTNER), `usuarios.debe_cambiar_contrasena` y `usuarios.doble_factor` (voluntario).
- `private.usuario_actual()` ya no reconoce al usuario mientras deba cambiar la contraseña o le falte el código en esa sesión: **RLS le niega todos los datos** aunque se salte la interfaz. Acepta también `aal2` por si en el futuro se usa el MFA nativo de Supabase.
- `codigos_verificacion`: códigos cifrados (hash) ligados al `session_id` de Supabase Auth. Solo los usa la API (`crear_codigo_verificacion`, `verificar_codigo`).
- `mi_cuenta()`: estado de la entrada para guiar al frontend (código pendiente, contraseña pendiente, acceso completo).
- Altas: `validar_alta_usuario` (con la sesión de quien da de alta) → la API crea la cuenta en Supabase Auth → `registrar_usuario` (solo API, vuelve a comprobar permisos). Si el registro falla, la API borra la cuenta recién creada.
- Gestión: `gestionar_usuario` (baja, reactivar, restablecer contraseña, activar o desactivar el doble factor propio). Nadie se da de baja a sí mismo; un técnico no gestiona a su administrador.
- Guía: `docs/usuarios-acceso.md`.

## Migración 028 · Sentilo, LoRaWAN, secretos y tarea periódica (26/10/2026)

- Tipo de conexión `LORAWAN` (ENVÍO). Dirección del sensor: `dev_eui` + `campo`; el trigger `trg_sensores_clave_lorawan` calcula `clave = DEVEUI/campo`, así `procesar_lecturas` no cambia.
- `conexiones.puntos_detectados`: campos recibidos sin sensor (`registrar_puntos_detectados`). `claves_conexion_token`: la API descarta lo no configurado.
- Secretos en Vault: `conexiones.id_secreto`, `guardar_secreto_conexion` (Partner con MODIFICAR_CONEXION) y `secreto_conexion` (solo API).
- Para la tarea: `conexiones_para_consultar`, `recuperaciones_pendientes`, `registrar_error_conexion`.
- `private.llamar_api_tareas()` y el trabajo de pg_cron `api_ciclo_15min` (URL y secreto en Vault: `api_url`, `api_tareas_secreto`).
- Guía: `docs/conectores.md`, apartados 10 a 13.

## Migración 029 · Conector API REST genérico (26/10/2026)

- `API_REST` pasa a llamarse "API REST (JSON)", admite recuperación de históricos y añade `parametro_desde`/`parametro_hasta`, `formato_parametros` y `ventana_horas`. `cabecera_api_key` se renombra a `cabecera_clave` (el control de secretos rechazaba cualquier clave con "api_key").
- `trg_conexiones_validar_api_rest`: URL http(s), cabecera obligatoria con API_KEY y parámetros de periodo en pareja.
- Guía: `docs/conectores.md`, apartado 10.

## Migración 030 · Recuperación de contraseña (27/10/2026)

- `codigos_recuperacion`: códigos cifrados (hash), 15 minutos, 5 intentos y como máximo 3 por hora y usuario. Pedir uno nuevo anula el anterior. Con RLS y sin políticas: solo la API.
- `crear_codigo_recuperacion(email, código)`: devuelve null si el email no es de un usuario activo o ha pedido demasiados; la API responde lo mismo en todos los casos.
- `usar_codigo_recuperacion(email, código)`: `OK` (marca el código como usado y quita la obligación de cambiar la contraseña, porque la elige el propio usuario), `INCORRECTO` con los intentos restantes, `BLOQUEADO` o `NO_VALIDO`.
- La API añade un límite por IP (10 peticiones cada 15 minutos) y cambia la contraseña en Supabase Auth.
- Guía: `docs/usuarios-acceso.md`, apartado 3 bis.

## Migración 031 · Edición de usuarios (27/10/2026)

- `modificar_usuario(creador, usuario, nombre, apellidos, teléfono, rol, alcance, clientes, edificios)`, solo API. `rol` o `alcance` a null = sin cambios.
- Mismas reglas que el alta (`comprobar_alta_usuario`) y la gestión (`puede_gestionar_usuario`), con el permiso MODIFICAR_USUARIO. Un usuario de baja no se edita sin reactivarlo.
- Las asignaciones que se quitan se desactivan con fecha de fin (queda el histórico); las nuevas se añaden.
- `private.tipo_rol()`: PLATAFORMA, PARTNER o CLIENTE.
- La API (0.7) añade además el alta sin contraseña con email de bienvenida (variable `WEB_URL`) y `anular-contrasena` (D39). La base de datos no cambia para eso: el usuario nuevo queda con `debe_cambiar_contrasena` hasta que elige su contraseña con el código.

## Migración 032 · Motor de cálculo (27/10/2026)

- **Cola incremental:** un trigger de sentencia en `lecturas` anota en `motor_pendiente`, por edificio, el instante más antiguo recibido (también datos atrasados e importaciones). Cambiar las fuentes de una magnitud o el uso de un submedidor anota el recálculo de todo su histórico. Los `recalculos_pendientes` pasan a esta cola.
- **`motor_calcular(edificio, desde, hasta)`:** serie de 15 min por sensor según su tratamiento (DELTA/CONTAJE: diferencia entre lecturas repartida en el tiempo; PROMEDIO, MAXIMO, MINIMO, SUMA), conversión de unidades, magnitudes = suma de fuentes (papel FUENTE o RESTA, también de otras magnitudes), `valores_magnitud`, `resumenes_diarios` del día local y `resumenes_diarios_usos` de los submedidores.
- **Calidad:** huecos de más de 1 hora → ESTIMADA; de más de 7 días, no se reparten; si el contador baja, ese tramo se descarta. `completo` = todos los intervalos del día (96, 92 o 100) y ninguno estimado.
- **No pisa** resúmenes importados (`origen` IMPORTACION_*).
- **Sustitución de sensores:** `sensores.id_sensor_anterior` (lo rellena `sustituir_sensor`); el motor suma el histórico del sensor antiguo sin mezclar contadores.
- **Ejecución:** `call motor_ejecutar()` (pg_cron `motor_15min`, minutos 5, 20, 35 y 50): tramos de 7 días, confirma cada tramo, máximo 240 s, sin solaparse. `estado_motor(edificio)` para la interfaz.
- Parámetro `FACTOR_CONVERSION_GAS` en `parametros_saas`. Si se cambia, hay que pedir un recálculo del periodo (insertar en `recalculos_pendientes`).
- Demo: `docs/demo_motor.sql` configura las magnitudes del edificio DEMO-OFICINAS.

## Migración 033 · Potencia en la pestaña Hoy (27/10/2026)

- Magnitud `FACTOR_POTENCIA` (sin unidad; un único sensor).
- `potencia_edificio(edificio)`: potencia y factor de potencia de la última hora, y la potencia del día comparable a la misma hora.
- Simulador: punto `FP-GENERAL` (factor de potencia, peor con poca carga). `docs/demo_motor.sql` crea el sensor en la demo y pide su histórico.

## Migración 034 · Panel del edificio (02/11/2026)

- `edificios`: `temperatura_confort`, `invierno_desde/hasta`, `verano_desde/hasta` (MM-DD), con comprobaciones.
- `temporada_edificio`, `estado_temperatura`, `estado_humedad`, `ambiente_edificio` (último valor por recinto, media si hay varias sondas iguales, ordenado por planta).
- `fuentes_hoy_edificio`: electricidad, gas y renovable consumida de hoy con su % frente al día comparable.
- `alarmas_edificio`: alarmas activas o reconocidas y sensores sin comunicación, por importancia.
- `serie_magnitud` y `serie_sensor` admiten `semana`.

## Migración 035 · Campana de alarmas (02/11/2026)

- `resumen_alarmas_usuario()`: total de alarmas activas o reconocidas y sensores sin comunicación de los edificios que ve el usuario (RLS), con el nivel más grave y la lista por edificio.

## Migración 036 · Temperaturas por temporada y emisiones por fuente (03/11/2026)

- `edificios`: `temp_eficiencia_invierno` (19), `temp_confort_invierno` (25), `temp_eficiencia_verano` (27) y `temp_confort_verano` (25), con comprobación de orden y rangos. Sustituyen a `temperatura_confort`, cuyo valor se copia a los dos confort.
- `estado_temperatura(valor, temporada, eficiencia, confort)` sustituye a la versión de tres parámetros.
- `ambiente_edificio` devuelve también `temperatura_eficiencia` y `temperatura_confort` de la temporada en curso.
- `fuentes_hoy_edificio` añade `total_kwh`, `emisiones_kg` y, por fuente, `aporte_pct` y `emisiones_kg` (nulo en renovables).

## Migración 037 · Cuadros eléctricos y Sankey por cuadro (03/11/2026)

- `cuadros_electricos` (RLS; alta y cambios con `MODIFICAR_MAGNITUDES`; validación de planta, recinto y cuadro padre del mismo edificio y sin ciclos; auditoría).
- `sensores.funcion_medidor` (`GENERAL`, `CUADRO`, `USO`) y `sensores.id_cuadro`, con comprobación de coherencia; un medidor total activo por cuadro; `sustituir_sensor` los conserva.
- Usos: `ILUMINACION` se llama "Alumbrado"; nuevos `HVAC_REFRIGERACION`, `HVAC_CALEFACCION`, `HVAC_ACS`, `HVAC_CALEFACCION_ACS`; "Otros usos" pasa a grupo con `OTROS_INFORMATICA`, `OTROS_SERVICIOS_COMUNES` y `OTROS_SIN_DESGLOSE` (lo asignado antes a `OTROS` pasa a este último).
- `resumenes_diarios_usos.id_cuadro` (clave única con `nulls not distinct`). El motor guarda lo medido por uso y cuadro y "otros usos" de cada cuadro con medidor, por diferencia.
- `sankey_energia`: columna de detalle (nivel 3) con nombres "uso · ubicación del cuadro" (`ubicacion_cuadro`); el resto no medido es el nodo `OTROS_NO_MEDIDO`. Fuera del nivel EDIFICIO no se desglosa por cuadro.
- `auditar_cambio`: si el edificio de la fila ya no existe (borrado de un edificio de demostración con `docs/demo_limpiar.sql`), la auditoría se guarda sin edificio.
- Demostración: `docs/demo_limpiar.sql` (borra un edificio `DEMO-*`) y `docs/demo_torre.sql` (crea la torre de oficinas); sustituyen a `demo_simuladores.sql` y `demo_motor.sql`.

## Migración 038 · Series de energía del panel (03/11/2026)

- `valores_usos` (RLS por edificios accesibles): energía de cada cuarto de hora por uso y cuadro, calculada por el motor (submedidores y "otros usos" de cada cuadro por diferencia, recortado a 0 en cada cuarto de hora). `resumenes_diarios_usos` pasa a ser la suma diaria de esta serie. La migración pide el recálculo de los edificios que ya tenían usos.
- `serie_energia(edificio, serie, desde, hasta, agrupación, filtro)`: serie de un KPI o de un nodo del Sankey (`ENERGIA_CONSUMIDA`, `RED`, `GAS`, `RENOVABLE`, `EMISIONES`, `HVAC`, `ILUMINACION:<cuadro>`, `OTROS_NO_MEDIDO`…), con la misma regla de reparto que el Sankey.
- `series_energia_edificio(edificio)`: series disponibles con nombre y grupo, para el desplegable.
- `hoy_edificio` y `fuentes_hoy_edificio`: `comparable_incompleto` y sin variación si el día comparable tiene menos del 90 % de los cuartos de hora de hoy.

## Migración 039 · Rendimiento de las series (09/11/2026)

- `serie_magnitud`, `serie_sensor` y `serie_energia` leen el calendario del periodo una sola vez (`with dias as materialized`, unión directa con `calendario_edificio`). Antes PostgreSQL llamaba a `dia_calendario()` en cada cuarto de hora y, con RLS, una serie de 7 a 365 días tardaba de 3 a 14 s; Supabase corta a los 8 s y el navegador mostraba "Failed to fetch". Ahora, unos 0,4 s (1 s para 30 días cada 15 min).
- Regla para funciones nuevas: no llamar a funciones con acceso a tablas dentro de una consulta que recorre series; leer los datos auxiliares una vez (CTE `materialized`) y unirlos.

## Migración 040 · Usos determinados (09/11/2026)

- `OTROS_INFORMATICA` → `INFORMATICA` y `OTROS_SERVICIOS_COMUNES` → `SERVICIOS_COMUNES`, sin padre (usos principales). "Otros usos" (`OTROS`) queda con `OTROS_SIN_DESGLOSE` (diferencias de los cuadros) y lo no medido. Las asignaciones, repartos y datos se conservan (van por identificador).

## Migración 041 · Plantas del modelo 3D (11/11/2026)

- `plantas.niveles_modelo text[]`: niveles del modelo 3D que forman cada planta. Trigger `validar_niveles_modelo_planta` (security definer; el permiso lo decide RLS): un nivel no se repite en la planta ni se asigna a dos plantas activas del mismo edificio.
- `ubicaciones_3d.id_elemento_modelo`: elemento del modelo (id de Revit) sobre el que se colocó la etiqueta pulsando en el visor.
- Herramienta `herramientas/modelo3d/preparar.mjs` (Node, gltf-transform) y guía `docs/modelos-3d.md`. El visor (web) usa three.js con el decodificador Draco servido desde la propia web (`public/draco/`) y abre el GLB con una URL firmada de Storage (1 h).

## Migración 042 · Etiquetas 3D sin solape (16/11/2026, D53)

- `modelos_3d`: `ancho_m`, `fondo_m`, `alto_m` y `niveles` (nombre y cota), del informe de `herramientas/modelo3d`.
- `parametros_etiquetas_3d()`: constantes compartidas con el visor (altura 1,5 m, visor de referencia de 630 px de alto, campo de visión 40°, encuadre 0,95, etiqueta de 76 px de ancho y 17 px por fila, ángulo mínimo de cámara 35°).
- `distancia_minima_etiquetas(modelo, filas_a, filas_b)`: √(ancho² + (alto / sen 35°)²) / (px por metro con el zoom mínimo), redondeada al decímetro superior.
- Trigger `trg_ubicaciones_3d_validar_etiquetas` (security definer): fija la altura; impide colocar suelto un sensor de un dispositivo; rechaza una etiqueta visible a menos de la distancia mínima de otra de la misma planta («Valor no permitido…»). Solo comprueba al colocar, mover, hacer visible o confirmar una coordenada copiada; no en las sustituciones de sensores o dispositivos.
- `sensores_estado_edificio()` devuelve también `id_dispositivo` y `dispositivo`.
- Demo: la torre agrupa sus sensores en 18 dispositivos (ambiental, medidor del cuadro, contador general, cuadro de cubierta) y coloca 21 etiquetas.

## Migración 043 · Temperatura por eficiencia y volúmenes (16/11/2026, D55)

- `edificios`: Te de invierno 19–21 °C (por defecto 19) y de verano 25–27 °C (por defecto 26); se eliminan `temp_confort_invierno` y `temp_confort_verano` (los valores fuera de rango se ajustan al límite).
- `estado_temperatura(valor, temporada, te)`: EFICIENTE · LEVE · MODERADO · ALTO · MUY_ALTO (invierno: Te, +1, +2,5, +4; verano: Te, −1, −2,5, −4); en entretiempo, nulo.
- `volumenes_sensor` (RLS como `ubicaciones_3d`, auditoría): volúmenes del GLB asignados a sensores de temperatura (uno o varios por sensor; cada volumen, uno solo).
- `ambiente_edificio()`: sin confort; devuelve `volumenes` con el tramo de su sensor (nulo si no comunica).
- Herramienta de preparación: conserva los volúmenes (DirectShape de Revit/Dynamo u objetos de Blender con la propiedad `Volumen`) con su nivel, superficie y posición.

## Migración 044 · Clima exterior (16/11/2026, D54)

- `clima_observaciones` (cada hora), `clima_previsiones` (la última) y `clima_consultas` (caducidad y Last-Modified; solo la API). Lectura: quien tiene acceso al edificio; escritura: solo `service_role`.
- `edificios_clima_pendientes()` y `guardar_clima()` (solo la API): la tarea periódica de la API (`/v1/tareas/ciclo`, cada 15 minutos) consulta los edificios cuya previsión ha caducado (≈ cada hora) en api.met.no con `CLIMA_CONTACTO` en el User-Agent, coordenadas con 4 decimales e If-Modified-Since.
- `clima_edificio()`: hora en curso con prioridad a los sensores exteriores propios que comunican (recintos `ZONA_EXTERIOR`), próximas 12 horas y 3 días, y la atribución a MET Norway.

## Migración 045 · Estado de sensores con su función y su energía (16/11/2026, D56)

- `sensores_estado_edificio()` devuelve también `funcion_medidor` (GENERAL, CUADRO o USO), `tipo_energia` y `flujo_energia`, para que el visor filtre la vista general de la pestaña Hoy.

## Migración 046 · Suministro y valor de hoy de cada sensor (16/11/2026, D56)

- `sensores_estado_edificio()` añade `suministro` (ELECTRICIDAD, GAS, RENOVABLE o AGUA, según la magnitud de edificio que alimenta el sensor), `valor_hoy` (contadores: última lectura de hoy − última antes de las 0:00 en la hora del edificio; vacío si el contador se reinicia) y `valor_comparable` (lo mismo en el día comparable hasta la misma hora).

## Migración 047 · Valor de hoy en kWh (16/11/2026, D56)

- `sensores_estado_edificio()` añade `valor_hoy_kwh`: contadores de energía que miden en otra unidad (gas en m³, MJ…) convertidos con la conversión del motor (`FACTOR_CONVERSION_GAS`…), mediante `private.factor_kwh_sensor()` (security definer). El agua, sin kWh.

## Migración 048 · Suministros y medidor general (16/11/2026, D57)

- `suministros`: `comercializadora`, `distribuidora`, `numero_contrato` y `fecha_alta_contrato`.
- Catálogo `parametros_medidor` (de la plataforma, solo lectura) y `sensores.id_parametro_medidor` (un parámetro por dispositivo; la familia del sensor tiene que corresponder y el consumo tiene que ser un contador). Al sustituir un sensor, el nuevo conserva el parámetro.
- `suministros_dispositivos.medidor_general` (uno por suministro).
- `estado_parametrizacion_edificio()`: comprobaciones `SUMINISTRO_ELECTRICO` y `MEDIDOR_GENERAL` (una por suministro; bloqueante en electricidad y gas).
- `suministros_edificio()` (fichas con el medidor y sus parámetros en vivo), `consumo_mensual_suministro()` (meses de este año y del anterior, por diferencia del contador en los cambios de mes; gas también en kWh) y `parametros_faltan_suministro()`.
- `filas_etiqueta_dispositivo()`: las filas de una etiqueta 3D sin los parámetros opcionales del medidor; `validar_etiqueta_3d()` la usa para la distancia mínima.
- Demo: `docs/demo_torre_suministros.sql` (suministros de electricidad, gas y agua con su medidor general; el simulador añade reactiva, aparente, tensiones, intensidades, frecuencia, presión del gas y caudal del agua).

## Migración 049 · Consumo mensual del primer mes (17/11/2026, D57)

- `consumo_mensual_suministro()`: el mes en que el contador empieza a medir (sin lectura antes del cambio de mes) se calcula desde su primera lectura, en lugar de quedar vacío.
- Demo: `docs/demo_torre_historico_suministros.sql` rellena los contadores de los medidores generales con una lectura diaria desde el 1 de enero del año pasado (hacia atrás desde la primera lectura real, con estacionalidad), por `procesar_lecturas` como histórico.

## Migración 050 · Rendimiento del estado de los sensores (17/11/2026)

- Con historial largo (una partición de `lecturas` por mes), «lo de hoy» de los contadores evaluaba la política RLS de `lecturas` en cada partición y en cada sensor: con un usuario de la web, `sensores_estado_edificio()` tardaba segundos y en Supabase superaba el límite («La consulta ha tardado demasiado»): el 3D se quedaba sin etiquetas y la pestaña Suministros sin datos.
- `sensores_estado_edificio()` y `consumo_mensual_suministro()` pasan a **security definer con un solo control de acceso al principio** que reproduce las políticas de cada tabla (acceso al edificio; VER_COMUNICACION, VER_3D + VER_MODELOS_3D, VER_ALARMAS, VER_LECTURAS y VER_SUMINISTRO). Nuevas `private.valores_hoy_edificio()`, `private.puede_leer_lecturas_edificio()` y `private.sin_usuario_plataforma()` (la API como service_role y las conexiones directas siguen viéndolo todo, como con RLS). Mismos resultados; en local, de 3,3 s a 0,1 s con un usuario Partner.
- **Regla para funciones nuevas que lean `lecturas` de muchos sensores:** control de acceso una vez y lectura sin RLS (security definer), nunca RLS por fila sobre la tabla particionada.

## Migración 051 · Parámetros del agua (17/11/2026, D57)

- Medidor general del agua con 4 parámetros: consumo acumulado (m³, obligatorio; como la energía, lo de cada día o mes es la diferencia de lecturas), caudal instantáneo, **presión** (bar) y **temperatura del agua** (opcionales).
- Demo: el contador de agua simulado envía también la presión (entre 2 y 3 bar, baja algo con el consumo); `docs/demo_torre_suministros.sql` crea el sensor `PRES-AGUA`. La temperatura no se simula.

## Migración 052 · Producción: fotovoltaica y solar térmica (17/11/2026, D58)

- `suministros_generacion`: ficha ampliada (módulos, inversor, azimut, inclinación, modalidad de autoconsumo, CAU, instalador, mantenedor, captadores, tipo de captador, acumulador y caldera de apoyo).
- `parametros_medidor`: catálogos FOTOVOLTAICA y SOLAR_TERMICA; `private.tipo_parametros_suministro()` (la generación usa el de su tecnología). `estado_parametrizacion_edificio()`: el medidor de producción es bloqueante.
- Tabla `superficies_produccion` (RLS como los suministros; auditoría): placas del modelo o dibujadas.
- `produccion_edificio()`: fichas con parámetros, superficies, usos servidos y KPIs. `private.factor_co2()` expone el factor de emisiones a los usuarios.
- `sankey_energia()` añade `desglose`: qué energía llega a cada uso y grupo de usos.
- Demo: `docs/demo_torre_produccion.sql` (FV de 40,5 kWp en dos zonas de la terraza y solar térmica de 6 captadores, con sus superficies dibujadas); el simulador añade potencia, irradiancia y temperatura de módulo (FV) y energía, potencia, temperaturas y caudal (solar térmica); `demo_torre_historico_suministros.sql` rellena también su producción. Herramienta 3D: placas marcadas «FV:» / «ST:».

## Migración 053 · Motor de alarmas (23/11/2026, D59)

- `niveles_alarma`: MUY_CRITICA, CRITICA y AVISO con su forma de envío (`envio`: INMEDIATO, RESUMEN_DIARIO, INFORMES). IMPORTANTE pasa a CRITICA e INFORMATIVA a AVISO (desactivados).
- Catálogo `tipos_regla_alarma` (21 reglas, con nivel y rearme recomendados, parámetros por defecto y requisitos). `reglas_alarma` admite reglas de la plataforma (`tipo_regla`, `id_suministro`, `parametros`, `escalado_minutos`); `reglas_alarma_usuarios.escalado`.
- `eventos_alarma`: estado RESUELTA, fecha de resolución, cierre automático, silencio (hasta, motivo, quién), reaperturas y escalado. Un evento abierto por regla, recinto y sensor.
- `notificaciones`: `motivo` (INMEDIATO, ESCALADO, REAVISO, RESUMEN_DIARIO) y `datos`; un resumen diario por persona y día.
- `motor_alarmas()` (pg_cron cada 5 min, `motor_alarmas_5min`): evalúa cada regla activa (`private.evaluar_regla_alarma`), abre, actualiza, reabre (< 60 min), resuelve o cierra, escala y reavisa; pide a la API que envíe los emails (`/v1/tareas/avisos`, con los mismos secretos de Vault que el ciclo). `preparar_resumen_diario()` (pg_cron 6:40 UTC, `resumen_alarmas_diario`). La API lee `avisos_pendientes()` y marca `marcar_aviso()` (solo service_role).
- Usuarios: `cerrar_alarma` solo en RESUELTA; `silenciar_alarma` (máximo 30 días, con motivo; `null` quita el silencio); `activar_regla_alarma`, `desactivar_regla_alarma`, `reglas_alarma_edificio`, `requisitos_regla_alarma` y `usuarios_alarmas_edificio` para la configuración. `alarmas_edificio` y `resumen_alarmas_usuario` incluyen las resueltas y no repiten un sensor sin comunicación que ya tiene su alarma.
- Pruebas: `028_alarmas.test.sql` (38) y `docs/pruebas_alarmas_sql_editor.sql`.

## Migración 054 · Ir a la alarma y averías simuladas en la demo (23/11/2026, D59)

- `private.ventana_sensor`: el valor vigente al empezar la ventana también cuenta. Con datos cada 15 minutos, una regla de 5 minutos decide siempre y una alarma se resuelve en cuanto llega el dato normal.
- `alarmas_edificio`: devuelve `id_recinto` y `planta`. En la web, pulsar una alarma (o llegar desde el email) lleva el 3D a su planta, resalta la etiqueta del sensor con el nombre de la alarma (punto latiendo) y abre su gráfica; arriba del 3D, un cartel dice qué alarma es y dónde está.
- **Averías simuladas** (solo edificios `DEMO-*`): tabla `averias_simuladas` (RLS; sin escritura directa), `tipos_averia_simulada()`, `simular_averia(edificio, tipo, minutos)` (15–240 min, permiso MODIFICAR_ALARMAS), `terminar_averia(id)` y `averias_simuladas_activas()` (solo service_role, para el simulador). Tipos: corte eléctrico, fallo de fase, cos φ bajo, maxímetro, sin gas, presión de gas alta, sin agua, presión de agua alta y CO₂ alto. El simulador de la API envía los valores de la avería por el camino normal de las lecturas (`app/simulador/averias.py`). Se usan desde **Configurar alarmas → Probar en el edificio de demostración**. `demo_limpiar.sql` las borra.
- Pruebas: `029_averias_simuladas.test.sql` (10) y `docs/pruebas_averias_sql_editor.sql`.

## Migración 055 · Histórico de alarmas (24/11/2026, D59)

- `eventos_alarma_acciones`: cronología de cada alarma (se abre, email enviado o no, escalada, reconocida, silenciada, silencio quitado o terminado, vuelve la causa, resuelta, reabierta, cerrada o cerrada sola), con fecha, persona (vacía = la plataforma) y detalle. La escriben triggers sobre `eventos_alarma` y `notificaciones`; no tiene políticas de escritura y nunca se borra. Las alarmas anteriores se completan con lo que ya guardaban.
- `historico_alarmas(edificio, desde, hasta, nivel, estado, texto, límite)`: alarmas e incidencias de comunicación de la más reciente a la más antigua, con duración, minutos hasta reconocerla, quién la reconoció y cerró, comentario, reaperturas, silencios y emails. `cronologia_alarma(id)`: sus pasos.
- Web: pestaña Alarmas → **Abiertas | Histórico**, con filtros, la cronología de cada alarma, «Descargar a Excel» (CSV) y, al pulsar 📍, el 3D en su planta y la gráfica del sensor de esos días con la franja de la alarma en rojo. El 3D de la pestaña Alarmas es el mismo que el de Hoy (edificio completo, plantas y recintos).
- Informe mensual (siguiente): resumen de alarmas por nivel y regla, tiempo medio hasta reconocer y hasta resolver, muy críticas del mes y abiertas a fin de mes.
- Pruebas: `030_historico_alarmas.test.sql` (12) y `docs/pruebas_historico_alarmas_sql_editor.sql`.

## Migración 056 · Informes (24/11/2026, D61)

- `informes` (foto en `datos` jsonb; uno por edificio, tipo y periodo) e `informes_destinatarios` (semanal / mensual por persona). RLS de lectura por edificio; escritura solo con funciones.
- `private.calcular_informe`: energía con la definición de los KPI (`private.energia_periodo`) del periodo, el anterior y el mismo del año pasado; consumo diario; energía fuera del horario de uso (`serie_energia` con `FUERA_HORARIO`); ambiente por recinto en horario de uso (mensual); alarmas (por nivel y regla, tiempos medios hasta reconocer y resolver, muy críticas, abiertas al final, avisos y sin comunicación); calidad de datos (horas con datos por sensor).
- `preparar_informes()` (pg_cron `informes_diario`, 5:30 UTC): los lunes el semanal y el día 1 el mensual de cada edificio con datos, y su email (`notificaciones` tipo INFORME, motivo INFORME_SEMANAL / INFORME_MENSUAL; los envía la API). `generar_informe` y `enviar_informe` (Partner, MODIFICAR_EDIFICIO), `destinatarios_informes` y `guardar_destinatarios_informes`.
- Marca: `parametros_saas.NOMBRE_PLATAFORMA`, `proveedores.logo_ruta` y bucket público `logos` (`proveedores/<id>/logo.<ext>`; escriben el administrador de la plataforma y el del Partner; `fijar_logo_partner`).
- Web: botón **Informes** en el edificio (lista, generar el último periodo, enviar, destinatarios y logo) y página `/edificio/<id>/informe/<id>` con **Descargar PDF** (impresión A4 del navegador).
- Pruebas: `031_informes.test.sql` (20) y `docs/pruebas_informes_sql_editor.sql`.
- **057** (correcciones): factor de CO₂ de las emisiones, fecha sin hora en el consumo por día (la gráfica no se dibujaba) y calidad de datos de sensores con lecturas importadas anteriores a su alta. Los informes ya generados se corrigen volviéndolos a generar.
- **058** (revisión con los informes reales de la demo): en el mensual, el periodo anterior es el mes natural anterior; con datos diarios (históricos importados) no se calcula el consumo fuera de horario y se indica; los sensores con una lectura al día se miden por días con datos; si 3 o más sensores dejan de comunicar en el mismo cuarto de hora, sale una sola línea «Corte de comunicación general».

## Pendientes funcionales que debe cerrar el comprador

Son decisiones de negocio que el código deja abiertas a propósito:

| Tema | Estado actual en el código |
|---|---|
| Efecto de SUSPENDIDO en Partner/Cliente/Edificio | Se registra el estado, pero no bloquea el acceso. Solo BAJA (inactivo) lo retira |
| Un rol por usuario | Cada usuario tiene un único rol global. Una persona con funciones distintas en dos Partners necesita dos cuentas |
| Catálogo final de KPIs y pantalla HOY | Pendiente (maestro §4) |
| Precios y modalidades BASIC/PRO/PREMIUM | Las tablas existen; la validación de requisitos al cambiar de modalidad se hace en la API |
| Plantillas y destinatarios de notificaciones | Emails de alarmas implementados (D59, `app/avisos.py` en la API); plantillas en español, sin personalizar por Partner. SMS, Telegram y push, preparados pero sin implementar |
| Retención de la auditoría | Indefinida |
| Pasarela Modbus/BACnet | Agente propio o gateways comerciales que envíen por HTTP/MQTT (ver `docs/conectores.md`) |
