-- =========================================================
-- MODELO 3D DE LA TORRE DE DEMOSTRACIÓN (solo desarrollo y demos)
-- Requiere las migraciones 041, 042 y 043 y el edificio DEMO-TORRE (docs/demo_torre.sql).
-- Pegar entero en el SQL Editor de Supabase y pulsar Run.
--
-- 1. Adapta las plantas de la torre al modelo de Revit de ejemplo (D51):
--      Sótano = Parking · Planta baja = L1 (bloques 35, 37 y 43) · Entreplanta = M1
--      Plantas 2 a 5 = L2 a L5 · Cubierta = R1–R3, cubierta verde y antepechos
--    (la antigua "Planta 1" pasa a llamarse "Entreplanta", con sus recintos, cuadro y sensores).
-- 2. Registra el modelo del edificio (primero el registro y después el archivo).
-- 3. Agrupa los sensores en dispositivos (ambiental, medidor del cuadro, contador general…)
--    y coloca una etiqueta por dispositivo (D53): altura fija de 1,5 m sobre el suelo de la
--    planta y separadas al menos la distancia mínima del modelo. Requiere la migración 042.
--
-- 4. Asigna los volúmenes de las habitaciones a los sensores de temperatura (D55). El modelo
--    pasa a la versión 2 (torre-v2.glb, con los volúmenes): si existía la versión 1, se sustituye.
--
-- Al final muestra la RUTA donde hay que subir el GLB preparado en Storage
-- (bucket modelos-3d). Se puede ejecutar varias veces.
-- =========================================================

drop table if exists pg_temp.demo_resultado3d;
create temp table demo_resultado3d (paso int, dato text, valor text);

do $$
declare
  v_edif uuid;
  v_modelo uuid;
  v_archivo text;
  v_ubicadas integer;
  v_volumenes integer;
begin
  select id into v_edif from public.edificios where codigo = 'DEMO-TORRE';
  if v_edif is null then
    raise exception 'No existe el edificio DEMO-TORRE: créelo antes con docs/demo_torre.sql';
  end if;

  -- 1. Plantas con sus niveles del modelo; la planta 1 pasa a ser la entreplanta
  update public.plantas p set nombre = x.nombre, niveles_modelo = x.niveles
  from (values ('SOT', 'Sótano', '{Parking}'::text[]),
               ('P0', 'Planta baja', '{"L1 - Block 35","L1 - Block 37","L1 - Block 43"}'),
               ('P1', 'Entreplanta', '{M1}'), ('P2', 'Planta 2', '{L2}'), ('P3', 'Planta 3', '{L3}'),
               ('P4', 'Planta 4', '{L4}'), ('P5', 'Planta 5', '{L5}'),
               ('CUB', 'Cubierta', '{R1,R2,R3,"Green Roof Hardscape",Parapet,"Parapet 2","Block 39 - Parapet"}')) x(codigo, nombre, niveles)
  where p.id_edificio = v_edif and p.codigo = x.codigo;
  update public.recintos r set nombre = 'Oficinas entreplanta'
  from public.plantas p where p.id = r.id_planta and p.id_edificio = v_edif and r.codigo = 'OFICINAS-P1';
  update public.cuadros_electricos set nombre = 'Cuadro de entreplanta' where id_edificio = v_edif and codigo = 'C-P1';
  update public.sensores s set nombre = replace(s.nombre, 'Cuadro de planta 1', 'Cuadro de entreplanta')
  where s.activo and s.nombre like 'Cuadro de planta 1%' and public.obtener_edificio_recinto(s.id_recinto) = v_edif;
  update public.sensores s set nombre = replace(s.nombre, 'Oficinas planta 1', 'Oficinas entreplanta')
  where s.activo and s.nombre like '%Oficinas planta 1' and public.obtener_edificio_recinto(s.id_recinto) = v_edif;

  -- 2. Registro del modelo del edificio: versión 2 (con los volúmenes de las habitaciones, D55).
  --    Si existe la versión 1, se sustituye (sustituir_modelo_3d) sin copiar coordenadas: se colocan abajo.
  select id, archivo into v_modelo, v_archivo from public.modelos_3d
  where id_edificio = v_edif and tipo_modelo = 'EDIFICIO' and activo;
  if v_modelo is null then
    v_archivo := 'edificios/' || v_edif || '/modelos/torre-v2.glb';
    insert into public.modelos_3d (id_edificio, tipo_modelo, nombre, archivo, formato, compresion, descripcion)
    values (v_edif, 'EDIFICIO', 'Torre de oficinas (Revit)', v_archivo, 'GLB', 'DRACO',
            'Modelo de ejemplo de Revit exportado con Leia y preparado con herramientas/modelo3d')
    returning id into v_modelo;
  elsif v_archivo like '%/torre-v1.glb' then
    v_archivo := 'edificios/' || v_edif || '/modelos/torre-v2.glb';
    v_modelo := public.sustituir_modelo_3d(v_modelo, v_archivo, null, 'DRACO', false);
  end if;

  -- Medidas y niveles del modelo preparado (informe de herramientas/modelo3d): fijan la altura
  -- de las etiquetas y la distancia mínima entre ellas (D53)
  update public.modelos_3d set ancho_m = 55.9, fondo_m = 32.4, alto_m = 29.6,
    niveles = '[{"nombre": "Parking", "cota": 1.83}, {"nombre": "L1 - Block 35", "cota": 5.18},
                {"nombre": "L1 - Block 37", "cota": 5.93}, {"nombre": "L1 - Block 43", "cota": 6.98},
                {"nombre": "M1", "cota": 8.66}, {"nombre": "L2", "cota": 9.45}, {"nombre": "L3", "cota": 12.73},
                {"nombre": "L4", "cota": 16.79}, {"nombre": "L5", "cota": 20.85}, {"nombre": "R1", "cota": 23.41},
                {"nombre": "Block 39 - Parapet", "cota": 24.26}, {"nombre": "R2", "cota": 24.92},
                {"nombre": "Green Roof Hardscape", "cota": 25.22}, {"nombre": "Parapet", "cota": 25.4},
                {"nombre": "R3", "cota": 27.97}, {"nombre": "Parapet 2", "cota": 28.57}]'
  where id = v_modelo;

  -- 3. Dispositivos (D53: una etiqueta por dispositivo, con una fila por sensor):
  --    en cada recinto, el sensor ambiental (temperatura, humedad y CO2) y el medidor del cuadro;
  --    en el cuarto de contadores, el contador general; en la cubierta, el cuadro general.
  --    El agua, la fotovoltaica y el gas quedan como sensores sueltos.
  delete from public.ubicaciones_3d where id_modelo_3d = v_modelo;
  with grupos(recinto, prefijo, codigo, nombre, tipo) as (values
      ('APARCAMIENTO', 'AMB-SOT-', 'AMB-SOT', 'Ambiente · Aparcamiento', 'SENSOR_AMBIENTAL'),
      ('APARCAMIENTO', 'E-SOT-', 'MED-SOT', 'Cuadro de sótano', 'CONTADOR_ENERGIA'),
      ('VESTIBULO', 'AMB-PB-', 'AMB-PB', 'Ambiente · Vestíbulo', 'SENSOR_AMBIENTAL'),
      ('VESTIBULO', 'E-PB-', 'MED-PB', 'Cuadro de planta baja', 'CONTADOR_ENERGIA'),
      ('LOCAL', 'AMB-LOC-', 'AMB-LOC', 'Ambiente · Local comercial', 'SENSOR_AMBIENTAL'),
      ('LOCAL', 'E-LOC-', 'MED-LOC', 'Cuadro del local', 'CONTADOR_ENERGIA'),
      ('CUARTO-CONT', '%-GENERAL', 'CONT-GEN', 'Contador general', 'SMART_METER'),
      ('OFICINAS-P1', 'AMB-P1-', 'AMB-P1', 'Ambiente · Oficinas entreplanta', 'SENSOR_AMBIENTAL'),
      ('OFICINAS-P1', 'E-P1-', 'MED-P1', 'Cuadro de entreplanta', 'CONTADOR_ENERGIA'),
      ('OFICINAS-P2', 'AMB-P2-', 'AMB-P2', 'Ambiente · Oficinas planta 2', 'SENSOR_AMBIENTAL'),
      ('OFICINAS-P2', 'E-P2-', 'MED-P2', 'Cuadro de planta 2', 'CONTADOR_ENERGIA'),
      ('OFICINAS-P3', 'AMB-P3-', 'AMB-P3', 'Ambiente · Oficinas planta 3', 'SENSOR_AMBIENTAL'),
      ('OFICINAS-P3', 'E-P3-', 'MED-P3', 'Cuadro de planta 3', 'CONTADOR_ENERGIA'),
      ('OFICINAS-P4', 'AMB-P4-', 'AMB-P4', 'Ambiente · Oficinas planta 4', 'SENSOR_AMBIENTAL'),
      ('OFICINAS-P4', 'E-P4-', 'MED-P4', 'Cuadro de planta 4', 'CONTADOR_ENERGIA'),
      ('OFICINAS-P5', 'AMB-P5-', 'AMB-P5', 'Ambiente · Oficinas planta 5', 'SENSOR_AMBIENTAL'),
      ('OFICINAS-P5', 'E-P5-', 'MED-P5', 'Cuadro de planta 5', 'CONTADOR_ENERGIA'),
      ('ZONA-TEC', 'E-CUB-', 'MED-CUB', 'Cuadro general de cubierta', 'CONTADOR_ENERGIA')),
  datos as (
    select g.*, r.id as id_recinto,
           (select pg_catalog.min(coalesce(s.id_conexion, d.id_conexion)::text)::uuid
            from public.sensores s left join public.dispositivos d on d.id = s.id_dispositivo
            where s.id_recinto = r.id and s.activo and s.codigo like g.prefijo || case when g.prefijo like '\%%' then '' else '%' end) as id_conexion
    from grupos g
    join public.recintos r on r.codigo = g.recinto
    join public.plantas p on p.id = r.id_planta and p.id_edificio = v_edif
  )
  insert into public.dispositivos (id_recinto, id_conexion, id_tipo_dispositivo, codigo, nombre)
  select d.id_recinto, d.id_conexion, t.id, d.codigo, d.nombre
  from datos d join public.tipos_dispositivo t on t.codigo = d.tipo
  where d.id_conexion is not null
    and not exists (select 1 from public.dispositivos x where x.id_recinto = d.id_recinto and x.codigo = d.codigo);

  update public.sensores s set id_dispositivo = d.id, id_conexion = null
  from public.dispositivos d
  join public.recintos r on r.id = d.id_recinto
  join public.plantas p on p.id = r.id_planta and p.id_edificio = v_edif
  where s.id_recinto = d.id_recinto and s.activo and s.id_dispositivo is null
    and s.id_conexion = d.id_conexion
    and (   (d.codigo = 'CONT-GEN' and s.codigo like '%-GENERAL')
         or (d.codigo like 'AMB-%' and s.codigo like d.codigo || '-%')
         or (d.codigo like 'MED-%' and s.codigo like 'E-' || substr(d.codigo, 5) || '-%'));

  -- 4. Etiquetas: un punto (x, z) por dispositivo o sensor suelto; la altura (1,5 m sobre el
  --    suelo de la planta) la pone la plataforma. Separadas al menos la distancia mínima del
  --    modelo (de 7,9 m para una fila a 16,1 m para cinco), que la plataforma comprueba.
  with puntos(codigo, x, z) as (values
      ('AMB-SOT', -10.0, -5.0), ('MED-SOT', 5.0, -5.0),
      ('AMB-LOC', -16.0, -8.0), ('MED-LOC', -24.0, 4.0), ('CONT-GEN', -2.0, -12.0), ('AGUA-CONT', -10.0, 4.0),
      ('AMB-PB', 4.0, 4.0), ('MED-PB', 14.0, -10.0),
      ('AMB-P1', -23.8, -10.5), ('MED-P1', -11.9, -10.5),
      ('AMB-P2', -4.6, 2.4), ('MED-P2', -4.0, -10.0), ('AMB-P3', -18.0, -6.0), ('MED-P3', -4.0, -10.0),
      ('AMB-P4', -18.0, -6.0), ('MED-P4', -4.0, -10.0), ('AMB-P5', -18.0, -6.0), ('MED-P5', -4.0, -10.0),
      ('MED-CUB', 3.5, 4.0), ('FV-PROD', 20.0, 4.0), ('GAS-CALDERA', -10.0, -6.0)),
  elementos as (
    select d.id as id_dispositivo, null::uuid as id_sensor, d.codigo
    from public.dispositivos d join public.recintos r on r.id = d.id_recinto
    join public.plantas p on p.id = r.id_planta and p.id_edificio = v_edif
    where d.activo
    union all
    select null, s.id, s.codigo
    from public.sensores s join public.recintos r on r.id = s.id_recinto
    join public.plantas p on p.id = r.id_planta and p.id_edificio = v_edif
    where s.activo and s.id_dispositivo is null
  )
  insert into public.ubicaciones_3d (id_modelo_3d, id_dispositivo, id_sensor, x, y, z, visible)
  select v_modelo, e.id_dispositivo, e.id_sensor, p.x, 0, p.z, true
  from elementos e join puntos p on p.codigo = e.codigo;
  get diagnostics v_ubicadas = row_count;

  -- 5. Volúmenes de las habitaciones (GLB versión 2) asignados a los sensores de temperatura (D55);
  --    el de la planta 2 tiene dos volúmenes
  delete from public.volumenes_sensor where id_modelo_3d = v_modelo;
  with asignacion(sensor, clave, nombre, nivel, cx, cz) as (values
      ('AMB-SOT-T', '2483026', 'Parking Garage', 'Parking', -0.61, -3.21),
      ('AMB-PB-T', '2482993', 'Residential Lobby', 'L1 - Block 37', 3.48, -0.01),
      ('AMB-LOC-T', '2482988', 'Café', 'L1 - Block 35', -15.42, -8.38),
      ('AMB-LOC-T', '2482989', 'Café Kitchen', 'L1 - Block 35', -19.07, -11.73),
      ('AMB-P1-T', '2483032', 'Mezzanine Dining', 'M1', -17.91, -10.71),
      ('AMB-P2-T', '2482998', 'Live/Work Unit', 'L2', -4.61, 2.37),
      ('AMB-P2-T', '2483001', 'Live/Work Unit', 'L2', 12.85, -9.26),
      ('AMB-P3-T', '2483002', 'Office Unit', 'L3', -18.43, -6.26),
      ('AMB-P4-T', '2483010', 'Office Unit', 'L4', -18.43, -6.59),
      ('AMB-P5-T', '2483019', 'Office Unit', 'L5', -17.86, -7.02))
  insert into public.volumenes_sensor (id_modelo_3d, id_sensor, clave_volumen, nombre_volumen, nivel_modelo, centro_x, centro_z)
  select v_modelo, s.id, a.clave, a.nombre, a.nivel, a.cx, a.cz
  from asignacion a
  join public.sensores s on s.codigo = a.sensor and s.activo
  join public.recintos r on r.id = s.id_recinto
  join public.plantas p on p.id = r.id_planta and p.id_edificio = v_edif;
  get diagnostics v_volumenes = row_count;

  insert into demo_resultado3d values
    (1, 'Bucket de Storage', 'modelos-3d'),
    (2, 'Carpeta donde subir el GLB preparado', pg_catalog.regexp_replace(v_archivo, '/[^/]+$', '')),
    (3, 'Nombre exacto del archivo', pg_catalog.regexp_replace(v_archivo, '^.*/', '')),
    (4, 'Etiquetas colocadas (dispositivos y sensores sueltos)', v_ubicadas::text),
    (5, 'Volúmenes asignados a sensores de temperatura', v_volumenes::text);
end;
$$;

select dato as "Dato", valor as "Valor" from demo_resultado3d order by paso;
