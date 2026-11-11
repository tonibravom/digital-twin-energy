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
-- 3. Coloca la etiqueta de cada sensor en su recinto (coordenadas en metros,
--    Y hacia arriba, sobre el archivo preparado con herramientas/modelo3d).
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

  -- 3. Etiquetas: cada recinto tiene un punto (x, z) y una altura; sus sensores se reparten
  --    en fila cada 1,6 m para que las etiquetas no se tapen
  with puntos(recinto, x, y, z) as (values
      ('APARCAMIENTO', 0.0, 3.6, 0.0),
      ('CUARTO-CONT', -4.0, 8.0, -10.0),
      ('VESTIBULO', 6.0, 8.0, -5.0),
      ('LOCAL', -20.0, 7.4, -4.0),
      ('OFICINAS-P1', -18.0, 10.2, -10.5),
      ('OFICINAS-P2', 0.0, 11.0, -4.0),
      ('OFICINAS-P3', 0.0, 14.3, -4.0),
      ('OFICINAS-P4', 0.0, 18.4, -4.0),
      ('OFICINAS-P5', 0.0, 22.4, -4.0),
      ('ZONA-TEC', 3.5, 25.4, 4.0),
      ('SALA-CALDERAS', -10.0, 26.8, -6.0)),
  sensores as (
    select s.id, p.x, p.y, p.z,
           row_number() over (partition by r.id order by s.codigo) - 1 as i,
           count(*) over (partition by r.id) as n
    from public.sensores s
    join public.recintos r on r.id = s.id_recinto
    join public.plantas pl on pl.id = r.id_planta and pl.id_edificio = v_edif
    join puntos p on p.recinto = r.codigo
    where s.activo
  )
  insert into public.ubicaciones_3d (id_modelo_3d, id_sensor, x, y, z, visible)
  select v_modelo, id, x + (i - (n - 1) / 2.0) * 1.6, y, z, true from sensores
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
