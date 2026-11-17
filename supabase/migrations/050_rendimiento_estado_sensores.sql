-- =========================================================
-- 050 · Rendimiento del estado de los sensores (página de edificio)
-- 17/11/2026.
--
--   Con historial largo (la tabla lecturas tiene una partición por mes), el
--   cálculo de «lo de hoy» de los contadores en sensores_estado_edificio()
--   evaluaba la política RLS de lecturas en cada partición y en cada sensor:
--   con un usuario normal tardaba segundos y en Supabase superaba el límite
--   (el visor 3D se quedaba sin etiquetas y suministros_edificio(), que la usa,
--   también fallaba).
--
--   · private.valores_hoy_edificio(): lo de hoy y lo del día comparable de
--     todos los contadores del edificio, con UN control de acceso al principio
--     (acceso al edificio y permiso VER_LECTURAS, lo mismo que exige la
--     política de lecturas) y las lecturas leídas sin RLS (security definer).
--   · sensores_estado_edificio() la usa y pasa a security definer con un solo
--     control al principio que reproduce las políticas de cada tabla: acceso al
--     edificio (sensores, dispositivos), VER_COMUNICACION (estado), VER_3D y
--     VER_MODELOS_3D (posiciones), VER_ALARMAS (alarma activa) y VER_LECTURAS
--     (lo de hoy). Mismas columnas y mismos valores.
--   · consumo_mensual_suministro(): igual (control de acceso una vez, al
--     principio: acceso al edificio, VER_SUMINISTRO y VER_LECTURAS).
--   · La API como service_role y las conexiones directas (SQL Editor, pruebas)
--     siguen viéndolo todo, como con RLS (private.puede_leer_lecturas_edificio).
-- =========================================================
begin;

-- Llamada sin usuario de la plataforma: la API como service_role o una conexión directa a la
-- base de datos (SQL Editor, pruebas). RLS no se aplica a esos roles, así que estas funciones
-- tampoco les restringen nada. Los usuarios de la web siempre llegan con su sesión (rol authenticated).
create or replace function private.sin_usuario_plataforma()
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce(coalesce(nullif(pg_catalog.current_setting('request.jwt.claims', true), ''), '{}')::jsonb->>'role', 'service_role')
         = 'service_role';
$$;
revoke all on function private.sin_usuario_plataforma() from public, anon;
grant execute on function private.sin_usuario_plataforma() to authenticated, service_role;

-- Quién puede leer las lecturas de un edificio (lo mismo que la política RLS de lecturas):
-- usuario con acceso al edificio y permiso VER_LECTURAS.
create or replace function private.puede_leer_lecturas_edificio(p_id_edificio uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.sin_usuario_plataforma()
      or (private.usuario_tiene_acceso_edificio(p_id_edificio) and private.usuario_tiene_permiso('VER_LECTURAS'));
$$;
revoke all on function private.puede_leer_lecturas_edificio(uuid) from public, anon;
grant execute on function private.puede_leer_lecturas_edificio(uuid) to authenticated, service_role;

create or replace function private.valores_hoy_edificio(p_id_edificio uuid)
returns table (id_sensor uuid, valor_hoy double precision, valor_comparable double precision)
language plpgsql
stable
security definer   -- un solo control de acceso; las lecturas, sin evaluar RLS en cada partición
set search_path = ''
as $$
declare
  v_z text;
  v_hoy date;
  v_ini_hoy timestamptz;
  v_ini_comp timestamptz;
  v_fin_comp timestamptz;
begin
  if not private.puede_leer_lecturas_edificio(p_id_edificio) then
    return;
  end if;
  select e.zona_horaria, (pg_catalog.now() at time zone e.zona_horaria)::date into v_z, v_hoy
  from public.edificios e where e.id = p_id_edificio;
  -- hoy: de las 0:00 a ahora; día comparable: de sus 0:00 a la misma hora (en la hora del edificio)
  v_ini_hoy := v_hoy::timestamp at time zone v_z;
  v_ini_comp := public.dia_comparable(p_id_edificio, v_hoy)::timestamp at time zone v_z;
  v_fin_comp := (public.dia_comparable(p_id_edificio, v_hoy)::timestamp + ((pg_catalog.now() at time zone v_z) - v_hoy::timestamp)) at time zone v_z;

  -- Contadores (acumulativos): última lectura del periodo − última lectura antes de su inicio.
  -- Si el contador se reinicia (resta negativa), se deja vacío.
  return query
  select s.id,
         nullif(greatest(
           (select l.valor from public.lecturas l where l.id_sensor = s.id and l.fecha_hora >= v_ini_hoy
             order by l.fecha_hora desc limit 1)
           - (select l.valor from public.lecturas l where l.id_sensor = s.id and l.fecha_hora <= v_ini_hoy
               and l.fecha_hora > v_ini_hoy - interval '7 days' order by l.fecha_hora desc limit 1), -1), -1),
         nullif(greatest(
           (select l.valor from public.lecturas l where l.id_sensor = s.id and l.fecha_hora > v_ini_comp and l.fecha_hora <= v_fin_comp
             order by l.fecha_hora desc limit 1)
           - (select l.valor from public.lecturas l where l.id_sensor = s.id and l.fecha_hora <= v_ini_comp
               and l.fecha_hora > v_ini_comp - interval '7 days' order by l.fecha_hora desc limit 1), -1), -1)
  from public.sensores s
  join public.naturalezas_sensor n on n.id = s.id_naturaleza and n.codigo = 'ACUMULATIVA'
  where s.activo and public.obtener_edificio_recinto(s.id_recinto) = p_id_edificio;
end;
$$;

revoke all on function private.valores_hoy_edificio(uuid) from public, anon;
grant execute on function private.valores_hoy_edificio(uuid) to authenticated, service_role;

create or replace function public.sensores_estado_edificio(p_id_edificio uuid)
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
  valor_comparable double precision,
  valor_hoy_kwh double precision
)
language sql
stable
security definer   -- un control de acceso al principio (los mismos permisos que las políticas RLS
                   -- de cada tabla) en lugar de evaluar RLS en cada fila y en cada partición
set search_path = ''
as $$
  with per as (
    select x.libre or private.usuario_tiene_acceso_edificio(p_id_edificio) as acceso,
           x.libre or private.usuario_tiene_permiso('VER_COMUNICACION') as comunicacion,
           x.libre or (private.usuario_tiene_permiso('VER_3D') and private.usuario_tiene_permiso('VER_MODELOS_3D')) as tres_d,
           x.libre or private.usuario_tiene_permiso('VER_ALARMAS') as alarmas
    from (select private.sin_usuario_plataforma() as libre) x
  ),
  par as (
    select e.zona_horaria as z, (pg_catalog.now() at time zone e.zona_horaria)::date as hoy
    from public.edificios e where e.id = p_id_edificio
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
  select b.id, b.codigo, b.nombre, b.familia, b.unidad, b.id_recinto, b.ultimo_valor, b.ultima_lectura, b.estado,
         b.alarma, b.ubicaciones, b.id_dispositivo, b.dispositivo, b.funcion_medidor, b.tipo_energia, b.flujo_energia,
         b.suministro, b.valor_hoy, b.valor_comparable,
         -- Contadores que miden en otra unidad (gas en m³…): lo de hoy también en kWh, con la misma conversión
         -- que el motor (FACTOR_CONVERSION_GAS…). El agua no es energía: sin kWh.
         case when b.valor_hoy is not null and coalesce(b.tipo_e, '') <> 'AGUA'
                   and pg_catalog.lower(pg_catalog.btrim(b.unidad_sensor)) <> 'kwh'
              then b.valor_hoy * private.factor_kwh_sensor(b.unidad_sensor, b.tipo_e, b.hoy) end
  from (
  select s.id, s.codigo, s.nombre, f.codigo as familia, s.unidad, s.id_recinto,
         ec.ultimo_valor, ec.ultima_lectura, coalesce(ec.estado, 'SIN_DATOS') as estado,
         per.alarmas and exists (select 1 from public.eventos_alarma ea
                 join public.reglas_alarma ra on ra.id = ea.id_regla_alarma
                 where ea.estado <> 'CERRADA'
                   and (ea.id_sensor = s.id or ra.id_sensor = s.id)) as alarma,
         case when not per.tres_d then '[]'::jsonb else coalesce((
           select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                    'id_modelo_3d', u.id_modelo_3d, 'tipo_modelo', m.tipo_modelo,
                    'x', u.x, 'y', u.y, 'z', u.z, 'visible', u.visible))
           from public.ubicaciones_3d u
           join public.modelos_3d m on m.id = u.id_modelo_3d and m.activo
           where u.id_sensor = s.id
              or (u.id_dispositivo is not null and u.id_dispositivo = s.id_dispositivo)
         ), '[]'::jsonb) end as ubicaciones,
         s.id_dispositivo, d.nombre as dispositivo, s.funcion_medidor, te.codigo as tipo_energia, fe.codigo as flujo_energia,
         su.suministro, s.unidad as unidad_sensor, te.codigo as tipo_e, (select hoy from par) as hoy,
         -- Contadores: lo de hoy y lo del día comparable (050: en una sola función con un control de acceso)
         vh.valor_hoy, vh.valor_comparable
  from public.sensores s
  cross join per
  join public.familias_sensor f on f.id = s.id_familia
  join public.naturalezas_sensor n on n.id = s.id_naturaleza
  left join public.dispositivos d on d.id = s.id_dispositivo
  left join public.tipos_energia te on te.id = s.id_tipo_energia
  left join public.flujos_energia fe on fe.id = s.id_flujo_energia
  left join suministros su on su.id_sensor = s.id
  left join public.estado_comunicacion ec on ec.id_sensor = s.id and per.comunicacion
  left join private.valores_hoy_edificio(p_id_edificio) vh on vh.id_sensor = s.id
  where s.activo and per.acceso
    and public.obtener_edificio_recinto(s.id_recinto) = p_id_edificio
  ) b;
$$;

create or replace function public.consumo_mensual_suministro(p_id_suministro uuid)
returns table (anio integer, mes integer, consumo double precision, unidad varchar, consumo_kwh double precision)
language plpgsql
stable
security definer   -- control de acceso una vez al principio; las lecturas, sin RLS por partición
set search_path = ''
as $$
declare
  v_tipo text;
  v_z text;
  v_hoy date;
  v_sensor uuid;
  v_unidad varchar;
  v_energia text;
  v_mes date;
  v_ini timestamptz;
  v_fin timestamptz;
  v_a double precision;
  v_b double precision;
begin
  select su.tipo, e.zona_horaria, (pg_catalog.now() at time zone e.zona_horaria)::date
    into v_tipo, v_z, v_hoy
  from public.suministros su join public.edificios e on e.id = su.id_edificio
  where su.id = p_id_suministro
    and private.puede_leer_lecturas_edificio(su.id_edificio)
    -- la ficha del suministro: la misma condición que su política RLS
    and (private.usuario_actual() is null or private.usuario_tiene_permiso('VER_SUMINISTRO'));
  if v_tipo is null then
    return;   -- inexistente o sin acceso
  end if;

  -- El contador de consumo del medidor general
  select s.id, s.unidad, te.codigo into v_sensor, v_unidad, v_energia
  from public.suministros_dispositivos sd
  join public.sensores s on s.id_dispositivo = sd.id_dispositivo and s.activo
  join public.parametros_medidor pm on pm.id = s.id_parametro_medidor and pm.consumo
  left join public.tipos_energia te on te.id = s.id_tipo_energia
  where sd.id_suministro = p_id_suministro and sd.activo and sd.medidor_general
  limit 1;
  if v_sensor is null then
    return;
  end if;
  v_energia := coalesce(v_energia, case v_tipo when 'AGUA_INCENDIOS' then 'AGUA' else v_tipo end);

  v_mes := (pg_catalog.date_trunc('year', v_hoy) - interval '1 year')::date;
  while v_mes <= v_hoy loop
    -- Última lectura antes del cambio de mes y última del mes (el mes en curso, hasta ahora), en la hora del edificio
    v_ini := v_mes::timestamp at time zone v_z;
    v_fin := least((v_mes + interval '1 month')::timestamp at time zone v_z, pg_catalog.now());
    select l.valor into v_a from public.lecturas l
    where l.id_sensor = v_sensor and l.fecha_hora <= v_ini and l.fecha_hora > v_ini - interval '31 days'
    order by l.fecha_hora desc limit 1;
    -- Sin lectura antes del mes (el contador empezó a medir ese mes): desde su primera lectura del mes
    if v_a is null then
      select l.valor into v_a from public.lecturas l
      where l.id_sensor = v_sensor and l.fecha_hora > v_ini and l.fecha_hora <= v_fin
      order by l.fecha_hora limit 1;
    end if;
    select l.valor into v_b from public.lecturas l
    where l.id_sensor = v_sensor and l.fecha_hora <= v_fin and l.fecha_hora > v_ini
    order by l.fecha_hora desc limit 1;

    anio := pg_catalog.date_part('year', v_mes)::integer;
    mes := pg_catalog.date_part('month', v_mes)::integer;
    unidad := v_unidad;
    -- Si el contador se reinicia o se sustituye (resta negativa), el mes queda vacío
    consumo := case when v_b - v_a >= 0 then v_b - v_a end;
    consumo_kwh := case
      when consumo is null or v_energia = 'AGUA' then null
      when pg_catalog.lower(pg_catalog.btrim(v_unidad)) = 'kwh' then consumo
      else consumo * private.factor_kwh_sensor(v_unidad, v_energia, v_mes) end;
    return next;
    v_mes := (v_mes + interval '1 month')::date;
  end loop;
end;
$$;

revoke all on function public.sensores_estado_edificio(uuid) from public, anon;
revoke all on function public.consumo_mensual_suministro(uuid) from public, anon;
grant execute on function public.sensores_estado_edificio(uuid) to authenticated, service_role;
grant execute on function public.consumo_mensual_suministro(uuid) to authenticated, service_role;

commit;
