-- =========================================================
-- MODELO 3D DE LA TORRE DE DEMOSTRACIÓN (solo desarrollo y demos)
-- Requiere la migración 041 y el edificio DEMO-TORRE (docs/demo_torre.sql).
-- Pegar entero en el SQL Editor de Supabase y pulsar Run.
--
-- 1. Adapta las plantas de la torre al modelo de Revit de ejemplo (D51):
--      Sótano = Parking · Planta baja = L1 (bloques 35, 37 y 43) · Entreplanta = M1
--      Plantas 2 a 5 = L2 a L5 · Cubierta = R1–R3, cubierta verde y antepechos
--    (la antigua "Planta 1" pasa a llamarse "Entreplanta", con sus recintos, cuadro y sensores).
-- 2. Registra el modelo del edificio (primero el registro y después el archivo).
-- 3. Coloca la etiqueta de cada sensor sobre una pared de su recinto (coordenadas en
--    metros, Y hacia arriba, sobre el archivo preparado con herramientas/modelo3d).
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

  -- 2. Registro del modelo del edificio (si ya hay uno activo, se usa ese)
  select id, archivo into v_modelo, v_archivo from public.modelos_3d
  where id_edificio = v_edif and tipo_modelo = 'EDIFICIO' and activo;
  if v_modelo is null then
    v_archivo := 'edificios/' || v_edif || '/modelos/torre-v1.glb';
    insert into public.modelos_3d (id_edificio, tipo_modelo, nombre, archivo, formato, compresion, descripcion)
    values (v_edif, 'EDIFICIO', 'Torre de oficinas (Revit)', v_archivo, 'GLB', 'DRACO',
            'Modelo de ejemplo de Revit exportado con Leia y preparado con herramientas/modelo3d')
    returning id into v_modelo;
  end if;

  -- 3. Etiquetas sobre paredes reales del modelo (calculadas con herramientas/modelo3d/puntos_demo.mjs):
  --    hasta 8 puntos por recinto, cada 1,6 m alternando 1,3 y 1,9 m de altura (en la cubierta
  --    y el aparcamiento, sobre el suelo); los sensores del recinto ocupan los puntos por orden de código
  with puntos(recinto, i, x, y, z) as (values
      ('APARCAMIENTO', 0, -2.4, 1.89, -0.8), ('APARCAMIENTO', 1, -0.8, 1.89, -0.8), ('APARCAMIENTO', 2, 0.8, 1.89, -0.8), ('APARCAMIENTO', 3, 2.4, 1.89, -0.8),
      ('APARCAMIENTO', 4, -2.4, 1.89, 0.8), ('APARCAMIENTO', 5, -0.8, 1.89, 0.8), ('APARCAMIENTO', 6, 0.8, 1.89, 0.8), ('APARCAMIENTO', 7, 2.4, 1.89, 0.8),
      ('CUARTO-CONT', 0, -5.87, 7.83, -9.2), ('CUARTO-CONT', 1, -5.87, 7.23, -10.8), ('CUARTO-CONT', 2, -5.87, 7.23, -7.6), ('CUARTO-CONT', 3, -5.95, 7.83, -12.4),
      ('CUARTO-CONT', 4, -5.82, 7.23, -14), ('VESTIBULO', 0, 6.93, 7.86, -5.8), ('VESTIBULO', 1, 6.93, 7.26, -4.2), ('VESTIBULO', 2, 6.93, 7.86, -2.6),
      ('VESTIBULO', 3, 6.93, 7.86, -9), ('VESTIBULO', 4, 6.93, 7.26, -1), ('VESTIBULO', 5, 6.93, 7.86, 0.6), ('LOCAL', 0, -9.43, 7.14, -4.8),
      ('LOCAL', 1, -9.33, 6.54, -3.2), ('LOCAL', 2, -9.43, 6.54, -6.4), ('LOCAL', 3, -9.33, 7.14, -1.6), ('LOCAL', 4, -9.33, 6.54, 0),
      ('LOCAL', 5, -9.33, 7.14, 1.6), ('OFICINAS-P1', 0, -17.2, 10.56, -4.24), ('OFICINAS-P1', 1, -18.8, 9.96, -4.24), ('OFICINAS-P1', 2, -15.6, 9.96, -4.24),
      ('OFICINAS-P1', 3, -20.4, 10.56, -4.24), ('OFICINAS-P1', 4, -14, 10.56, -4.24), ('OFICINAS-P1', 5, -12.4, 9.96, -4.24), ('OFICINAS-P2', 0, -2.4, 10.75, -4.13),
      ('OFICINAS-P2', 1, 2.4, 11.35, -4.13), ('OFICINAS-P2', 2, -4, 11.35, -4.13), ('OFICINAS-P2', 3, 4, 10.75, -4.13), ('OFICINAS-P2', 4, -5.6, 10.75, -4.13),
      ('OFICINAS-P3', 0, -0.8, 14.63, -4.13), ('OFICINAS-P3', 1, 0.8, 14.03, -4.13), ('OFICINAS-P3', 2, -2.4, 14.03, -4.13), ('OFICINAS-P3', 3, 2.4, 14.63, -4.13),
      ('OFICINAS-P3', 4, -4, 14.63, -4.13), ('OFICINAS-P3', 5, 4, 14.03, -4.13), ('OFICINAS-P3', 6, -5.6, 14.03, -4.13), ('OFICINAS-P4', 0, 0.8, 18.69, -2.37),
      ('OFICINAS-P4', 1, -0.8, 18.09, -2.37), ('OFICINAS-P4', 2, 2.4, 18.09, -2.37), ('OFICINAS-P4', 3, 4, 18.69, -2.37), ('OFICINAS-P4', 4, -4, 18.09, -2.37),
      ('OFICINAS-P4', 5, 5.6, 18.09, -2.37), ('OFICINAS-P4', 6, -5.6, 18.69, -2.37), ('OFICINAS-P5', 0, 0.8, 22.15, -4.13), ('OFICINAS-P5', 1, -2.4, 22.15, -4.13),
      ('OFICINAS-P5', 2, 2.4, 22.75, -4.13), ('OFICINAS-P5', 3, -4, 22.75, -4.13), ('OFICINAS-P5', 4, 4, 22.15, -4.13), ('OFICINAS-P5', 5, -5.6, 22.15, -4.13),
      ('ZONA-TEC', 0, 1.1, 23.66, 3.2), ('ZONA-TEC', 1, 2.7, 23.66, 3.2), ('ZONA-TEC', 2, 4.3, 23.66, 3.2), ('ZONA-TEC', 3, 5.9, 23.66, 3.2),
      ('ZONA-TEC', 4, 1.1, 23.66, 4.8), ('ZONA-TEC', 5, 2.7, 23.66, 4.8), ('ZONA-TEC', 6, 4.3, 23.66, 4.8), ('ZONA-TEC', 7, 5.9, 23.66, 4.8),
      ('SALA-CALDERAS', 0, -12.4, 25.3, -6.8), ('SALA-CALDERAS', 1, -10.8, 25.3, -6.8), ('SALA-CALDERAS', 2, -9.2, 25.3, -6.8), ('SALA-CALDERAS', 3, -7.6, 25.3, -6.8),
      ('SALA-CALDERAS', 4, -12.4, 25.3, -5.2), ('SALA-CALDERAS', 5, -10.8, 25.3, -5.2), ('SALA-CALDERAS', 6, -9.2, 25.3, -5.2), ('SALA-CALDERAS', 7, -7.6, 25.3, -5.2)),
  sensores as (
    select s.id, r.codigo as recinto, (row_number() over (partition by r.id order by s.codigo) - 1) % 8 as i
    from public.sensores s
    join public.recintos r on r.id = s.id_recinto
    join public.plantas pl on pl.id = r.id_planta and pl.id_edificio = v_edif
    where s.activo
  )
  insert into public.ubicaciones_3d (id_modelo_3d, id_sensor, x, y, z, visible)
  select v_modelo, s.id, p.x, p.y, p.z, true
  from sensores s join puntos p on p.recinto = s.recinto and p.i = s.i
  on conflict (id_modelo_3d, id_sensor) where id_sensor is not null
  do update set x = excluded.x, y = excluded.y, z = excluded.z, por_revisar = false;
  get diagnostics v_ubicadas = row_count;

  insert into demo_resultado3d values
    (1, 'Bucket de Storage', 'modelos-3d'),
    (2, 'Carpeta donde subir el GLB preparado', pg_catalog.regexp_replace(v_archivo, '/[^/]+$', '')),
    (3, 'Nombre exacto del archivo', pg_catalog.regexp_replace(v_archivo, '^.*/', '')),
    (4, 'Sensores con etiqueta', v_ubicadas::text);
end;
$$;

select dato as "Dato", valor as "Valor" from demo_resultado3d order by paso;
