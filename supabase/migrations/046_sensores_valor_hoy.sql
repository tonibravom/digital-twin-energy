-- =========================================================
-- 046 · Estado de sensores: suministro y valor de hoy
-- Decisión D56 (16/11/2026).
--
--   · suministro: si el sensor alimenta un suministro del edificio (las
--     mismas fuentes que el KPI de energía): ELECTRICIDAD (red), GAS,
--     RENOVABLE (cualquier generación) o AGUA. Con un suministro de varios
--     contadores, cada uno lleva su etiqueta.
--   · valor_hoy: en los contadores (sensores acumulativos: energía, gas,
--     agua…), lo de hoy = última lectura de hoy − última lectura antes de
--     las 0:00 (hora del edificio); valor_comparable, lo mismo en el día
--     comparable hasta la misma hora. Lo calcula la base de datos: la web
--     nunca suma ni resta lecturas.
-- =========================================================
begin;

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
  dispositivo varchar,
  funcion_medidor varchar,
  tipo_energia varchar,
  flujo_energia varchar,
  suministro varchar,
  valor_hoy double precision,
  valor_comparable double precision
)
language sql
stable
set search_path = ''
as $$
  with par as (
    select e.zona_horaria as z, (pg_catalog.now() at time zone e.zona_horaria)::date as hoy
    from public.edificios e where e.id = p_id_edificio
  ),
  rango as (
    -- hoy: de las 0:00 a ahora; día comparable: de sus 0:00 a la misma hora (en la hora del edificio)
    select (hoy::timestamp at time zone z) as ini_hoy,
           (public.dia_comparable(p_id_edificio, hoy)::timestamp at time zone z) as ini_comp,
           (public.dia_comparable(p_id_edificio, hoy)::timestamp + ((pg_catalog.now() at time zone z) - hoy::timestamp)) at time zone z as fin_comp
    from par
  ),
  suministros as (
    -- Sensor que alimenta cada suministro del edificio (las mismas fuentes que el KPI de energía)
    select mf.id_sensor,
           pg_catalog.min(case when m.codigo = 'CONSUMO_ELECTRICIDAD' then 'ELECTRICIDAD'
                               when m.codigo = 'CONSUMO_GAS' then 'GAS'
                               when m.codigo = 'CONSUMO_AGUA' then 'AGUA'
                               when m.codigo like 'GENERACION\_%' then 'RENOVABLE' end) as suministro
    from public.magnitudes_fuentes mf
    join public.magnitudes_edificio me on me.id = mf.id_magnitud_edificio and me.id_edificio = p_id_edificio and me.ambito = 'EDIFICIO'
    join public.magnitudes m on m.id = me.id_magnitud
    group by mf.id_sensor
  )
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
         s.id_dispositivo, d.nombre, s.funcion_medidor, te.codigo, fe.codigo,
         su.suministro,
         -- Contadores (acumulativos): lo de hoy = última lectura de hoy − última lectura antes de las 0:00.
         -- Si el contador se reinicia (resta negativa), se deja vacío.
         case when n.codigo = 'ACUMULATIVA' then nullif(greatest(
           (select l.valor from public.lecturas l where l.id_sensor = s.id and l.fecha_hora >= r.ini_hoy
             order by l.fecha_hora desc limit 1)
           - (select l.valor from public.lecturas l where l.id_sensor = s.id and l.fecha_hora <= r.ini_hoy
               and l.fecha_hora > r.ini_hoy - interval '7 days' order by l.fecha_hora desc limit 1), -1), -1) end,
         case when n.codigo = 'ACUMULATIVA' then nullif(greatest(
           (select l.valor from public.lecturas l where l.id_sensor = s.id and l.fecha_hora > r.ini_comp and l.fecha_hora <= r.fin_comp
             order by l.fecha_hora desc limit 1)
           - (select l.valor from public.lecturas l where l.id_sensor = s.id and l.fecha_hora <= r.ini_comp
               and l.fecha_hora > r.ini_comp - interval '7 days' order by l.fecha_hora desc limit 1), -1), -1) end
  from public.sensores s
  cross join rango r
  join public.familias_sensor f on f.id = s.id_familia
  join public.naturalezas_sensor n on n.id = s.id_naturaleza
  left join public.dispositivos d on d.id = s.id_dispositivo
  left join public.tipos_energia te on te.id = s.id_tipo_energia
  left join public.flujos_energia fe on fe.id = s.id_flujo_energia
  left join suministros su on su.id_sensor = s.id
  left join public.estado_comunicacion ec on ec.id_sensor = s.id
  where s.activo
    and public.obtener_edificio_recinto(s.id_recinto) = p_id_edificio;
$$;

revoke all on function public.sensores_estado_edificio(uuid) from public, anon;
grant execute on function public.sensores_estado_edificio(uuid) to authenticated, service_role;

commit;
