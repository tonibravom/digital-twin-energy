-- =========================================================
-- 042 · Etiquetas 3D sin solape
-- Decisión D53 (12/11/2026; implementada 16/11/2026).
--
--   · Una etiqueta por DISPOSITIVO (una fila por sensor). Un sensor que
--     pertenece a un dispositivo no se coloca suelto: se coloca el
--     dispositivo y sus sensores heredan el punto.
--   · Altura fija: 1,5 m sobre el suelo de la planta (cota del nivel más
--     bajo de la planta en el modelo). La base de datos la calcula.
--   · Distancia mínima fija entre etiquetas visibles de la misma planta,
--     calculada para cada modelo con sus medidas, el tamaño de las
--     etiquetas y un visor de referencia de portátil con el zoom mínimo
--     (= encuadre) y el ángulo mínimo de cámara (35°) que impone el visor.
--     Una posición más cercana NO se guarda ("valor no permitido").
--   · Las coordenadas copiadas al sustituir el modelo (por_revisar) no se
--     comprueban hasta que se confirman. Las sustituciones de sensores y
--     dispositivos (que solo cambian el dueño de la etiqueta) no se comprueban.
--   · modelos_3d guarda sus medidas y niveles (los da el informe de
--     herramientas/modelo3d o la escena del propio GLB).
--   · sensores_estado_edificio devuelve el dispositivo de cada sensor.
-- =========================================================
begin;

-- 1. Medidas y niveles del modelo
alter table public.modelos_3d
  add column if not exists ancho_m numeric(8,2),
  add column if not exists fondo_m numeric(8,2),
  add column if not exists alto_m numeric(8,2),
  add column if not exists niveles jsonb not null default '[]';

alter table public.modelos_3d drop constraint if exists modelos_3d_medidas_ck;
alter table public.modelos_3d add constraint modelos_3d_medidas_ck check (
  (ancho_m is null or ancho_m > 0) and (fondo_m is null or fondo_m > 0) and (alto_m is null or alto_m > 0)
  and pg_catalog.jsonb_typeof(niveles) = 'array');

comment on column public.modelos_3d.ancho_m is 'Ancho del modelo (eje X, m). Con fondo_m fija la distancia mínima entre etiquetas.';
comment on column public.modelos_3d.fondo_m is 'Fondo del modelo (eje Z, m).';
comment on column public.modelos_3d.alto_m is 'Alto del modelo (eje Y, m).';
comment on column public.modelos_3d.niveles is
  'Niveles del modelo con su cota: [{"nombre": "L3", "cota": 12.73}, …]. Fijan la altura de las etiquetas de cada planta.';

-- 2. Parámetros de las etiquetas (los mismos que usa el visor)
create or replace function public.parametros_etiquetas_3d()
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'altura_m', 1.5,            -- altura de la etiqueta sobre el suelo de la planta
    'visor_alto_px', 630,       -- visor de referencia: portátil de 1366 × 768
    'fov_grados', 40,           -- campo de visión vertical de la cámara
    'encuadre', 0.95,           -- factor de distancia del encuadre del visor
    'ancho_px', 76,             -- ancho de una etiqueta («1.234,5 kWh»)
    'fila_px', 17,              -- alto de cada fila (un sensor)
    'margen_px', 8,             -- borde y separación de la etiqueta
    'angulo_min_grados', 35);   -- ángulo mínimo de la cámara sobre la horizontal
$$;

-- 3. Distancia mínima (m) entre dos etiquetas de un modelo según sus filas.
--    Con la escala del zoom mínimo (px por metro) y el ángulo mínimo de
--    cámara, dos etiquetas no se tapan en ninguna orientación si su
--    distancia en planta es al menos √(ancho² + (alto / sen ángulo)²).
create or replace function public.distancia_minima_etiquetas(p_id_modelo uuid, p_filas_a integer default 1, p_filas_b integer default 1)
returns numeric
language sql
stable
security definer   -- la usa el trigger de validación; solo lee medidas del modelo
set search_path = ''
as $$
  with p as (select public.parametros_etiquetas_3d() j),
  m as (select greatest(ancho_m, fondo_m) / 2 as radio from public.modelos_3d where id = p_id_modelo),
  c as (
    select (p.j->>'visor_alto_px')::numeric * pg_catalog.cos(pg_catalog.radians((p.j->>'fov_grados')::numeric / 2))
             / (2 * (p.j->>'encuadre')::numeric * m.radio) as px_m,
           (p.j->>'ancho_px')::numeric as ancho,
           greatest(coalesce(p_filas_a, 1), coalesce(p_filas_b, 1), 1) * (p.j->>'fila_px')::numeric
             + (p.j->>'margen_px')::numeric as alto,
           pg_catalog.sin(pg_catalog.radians((p.j->>'angulo_min_grados')::numeric)) as seno
    from p, m
    where m.radio > 0
  )
  select pg_catalog.ceil(pg_catalog.sqrt(ancho ^ 2 + (alto / seno) ^ 2) / px_m * 10) / 10 from c;
$$;

-- 4. Validación de cada etiqueta
create or replace function public.validar_etiqueta_3d()
returns trigger
language plpgsql
security definer   -- compara con todas las etiquetas del modelo; el permiso lo decide RLS
set search_path = ''
as $$
declare
  v_modelo public.modelos_3d%rowtype;
  v_recinto uuid;
  v_planta uuid;
  v_dispositivo uuid;
  v_filas integer;
  v_cota numeric;
  v_otra record;
  v_comprobar boolean;
begin
  -- Solo se comprueba al colocar o mover una etiqueta, al hacerla visible o al confirmar una copiada;
  -- no en las sustituciones de sensores o dispositivos (que solo cambian a quién pertenece)
  v_comprobar := tg_op = 'INSERT'
    or (new.x, new.z) is distinct from (old.x, old.z)
    or (new.visible and not old.visible)
    or (old.por_revisar and not new.por_revisar);

  select * into v_modelo from public.modelos_3d where id = new.id_modelo_3d;
  if not found then
    return new;   -- validar_ubicacion_3d ya lo rechaza
  end if;

  if new.id_sensor is not null then
    select s.id_recinto, s.id_dispositivo into v_recinto, v_dispositivo from public.sensores s where s.id = new.id_sensor;
    if v_dispositivo is not null and not new.por_revisar and v_comprobar then
      raise exception 'El sensor pertenece a un dispositivo: coloque el dispositivo y sus sensores heredan el punto'
        using errcode = 'check_violation';
    end if;
    v_filas := 1;
  else
    select d.id_recinto into v_recinto from public.dispositivos d where d.id = new.id_dispositivo;
    select pg_catalog.count(*) into v_filas from public.sensores s where s.id_dispositivo = new.id_dispositivo and s.activo;
  end if;
  select r.id_planta into v_planta from public.recintos r where r.id = v_recinto;

  -- Altura fija: 1,5 m sobre el nivel más bajo de la planta en el modelo del edificio
  if v_modelo.tipo_modelo = 'EDIFICIO' then
    select pg_catalog.min((n->>'cota')::numeric) into v_cota
    from public.plantas p, pg_catalog.jsonb_array_elements(v_modelo.niveles) n
    where p.id = v_planta and n->>'nombre' = any (p.niveles_modelo);
    if v_cota is not null then
      new.y := v_cota + (public.parametros_etiquetas_3d()->>'altura_m')::numeric;
    end if;
  end if;

  -- Distancia mínima con las demás etiquetas visibles de la misma planta
  if v_comprobar and new.visible and not new.por_revisar and v_modelo.ancho_m is not null and v_modelo.fondo_m is not null then
    for v_otra in
      select u.x, u.z, coalesce(d.nombre, s.nombre) as nombre,
             case when u.id_dispositivo is not null
                  then (select pg_catalog.count(*) from public.sensores x where x.id_dispositivo = u.id_dispositivo and x.activo)
                  else 1 end as filas
      from public.ubicaciones_3d u
      left join public.sensores s on s.id = u.id_sensor
      left join public.dispositivos d on d.id = u.id_dispositivo
      join public.recintos r on r.id = coalesce(s.id_recinto, d.id_recinto)
      where u.id_modelo_3d = new.id_modelo_3d and u.id <> new.id and u.visible and not u.por_revisar
        and r.id_planta = v_planta
    loop
      if pg_catalog.sqrt((v_otra.x - new.x) ^ 2 + (v_otra.z - new.z) ^ 2)
         < public.distancia_minima_etiquetas(new.id_modelo_3d, v_filas, v_otra.filas::integer) then
        raise exception 'Valor no permitido: la etiqueta quedaría a % m de «%» y en este modelo la distancia mínima es % m. Sepárela o use un modelo por recinto',
          pg_catalog.round(pg_catalog.sqrt((v_otra.x - new.x) ^ 2 + (v_otra.z - new.z) ^ 2), 1), v_otra.nombre,
          public.distancia_minima_etiquetas(new.id_modelo_3d, v_filas, v_otra.filas::integer)
          using errcode = 'check_violation';
      end if;
    end loop;
  end if;

  return new;
end;
$$;

-- Se ejecuta después de trg_ubicaciones_3d_revisar y trg_ubicaciones_3d_validar (orden alfabético)
drop trigger if exists trg_ubicaciones_3d_validar_etiquetas on public.ubicaciones_3d;
create trigger trg_ubicaciones_3d_validar_etiquetas
before insert or update on public.ubicaciones_3d
for each row execute function public.validar_etiqueta_3d();

-- 5. Estado de sensores con su dispositivo (el visor agrupa las filas por dispositivo)
drop function if exists public.sensores_estado_edificio(uuid);
create function public.sensores_estado_edificio(p_id_edificio uuid)
returns table (
  id_sensor uuid,
  codigo varchar,
  nombre varchar,
  familia varchar,
  unidad varchar,
  id_recinto uuid,
  ultimo_valor double precision,
  ultima_lectura timestamptz,
  estado_comunicacion varchar,
  alarma_activa boolean,
  ubicaciones jsonb,
  id_dispositivo uuid,
  dispositivo varchar
)
language sql
stable
set search_path = ''
as $$
  select s.id, s.codigo, s.nombre, f.codigo, s.unidad, s.id_recinto,
         ec.ultimo_valor, ec.ultima_lectura, coalesce(ec.estado, 'SIN_DATOS'),
         exists (select 1 from public.eventos_alarma ea
                 join public.reglas_alarma ra on ra.id = ea.id_regla_alarma
                 where ea.estado <> 'CERRADA'
                   and (ea.id_sensor = s.id or ra.id_sensor = s.id)),
         coalesce((
           select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                    'id_modelo_3d', u.id_modelo_3d, 'tipo_modelo', m.tipo_modelo,
                    'x', u.x, 'y', u.y, 'z', u.z, 'visible', u.visible))
           from public.ubicaciones_3d u
           join public.modelos_3d m on m.id = u.id_modelo_3d and m.activo
           where u.id_sensor = s.id
              or (u.id_dispositivo is not null and u.id_dispositivo = s.id_dispositivo)
         ), '[]'::jsonb),
         s.id_dispositivo, d.nombre
  from public.sensores s
  join public.familias_sensor f on f.id = s.id_familia
  left join public.dispositivos d on d.id = s.id_dispositivo
  left join public.estado_comunicacion ec on ec.id_sensor = s.id
  where s.activo
    and public.obtener_edificio_recinto(s.id_recinto) = p_id_edificio;
$$;

revoke all on function public.parametros_etiquetas_3d() from public, anon;
revoke all on function public.distancia_minima_etiquetas(uuid, integer, integer) from public, anon;
revoke all on function public.validar_etiqueta_3d() from public, anon;
revoke all on function public.sensores_estado_edificio(uuid) from public, anon;
grant execute on function public.parametros_etiquetas_3d() to authenticated, service_role;
grant execute on function public.distancia_minima_etiquetas(uuid, integer, integer) to authenticated, service_role;
grant execute on function public.sensores_estado_edificio(uuid) to authenticated, service_role;

commit;
