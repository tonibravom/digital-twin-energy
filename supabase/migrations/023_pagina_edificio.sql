begin;

-- =========================================================
-- PÁGINA DE EDIFICIO (decisiones 21/10/2026)
--
-- · HOY se compara con el ÚLTIMO DÍA EQUIVALENTE según el
--   calendario del edificio: el último laborable si hoy es
--   laborable, el último no laborable si hoy no lo es. Siempre
--   el mismo tramo horario (de 00:00 a la hora actual).
-- · Consumo fuera de horario: lo consumido fuera del horario de
--   funcionamiento del día (en un día no laborable, todo).
-- · Series agrupadas (15 min, hora, día, mes, año) con filtro de
--   calendario, para Históricos y para las gráficas.
--
-- Convenciones:
-- · Un valor de valores_magnitud con fecha_hora = 10:15 corresponde
--   al intervalo que EMPIEZA a las 10:15.
-- · Días y horas en la zona horaria del edificio.
-- · Sin fila de calendario para un día: lunes a viernes laborable
--   y fin de semana no laborable, sin horario definido.
-- =========================================================

-- ---------------------------------------------------------
-- 1. Calendario
-- ---------------------------------------------------------
create or replace function public.dia_calendario(p_id_edificio uuid, p_fecha date)
returns table (laborable boolean, hora_inicio time, hora_fin time, definido boolean)
language sql
stable
set search_path = ''
as $$
  select coalesce(c.laborable, extract(isodow from p_fecha) < 6),
         c.hora_inicio, c.hora_fin, c.id is not null
  from (select 1) x
  left join public.calendario_edificio c
    on c.id_edificio = p_id_edificio and c.fecha = p_fecha;
$$;

-- Último día anterior con el mismo carácter (laborable / no laborable).
create or replace function public.dia_comparable(p_id_edificio uuid, p_fecha date)
returns date
language plpgsql
stable
set search_path = ''
as $$
declare
  v_laborable boolean;
  v_dia date;
begin
  select laborable into v_laborable from public.dia_calendario(p_id_edificio, p_fecha);

  for i in 1..60 loop
    v_dia := p_fecha - i;
    if (select laborable from public.dia_calendario(p_id_edificio, v_dia)) = v_laborable then
      return v_dia;
    end if;
  end loop;

  return null;
end;
$$;

-- ---------------------------------------------------------
-- 2. Series agrupadas
-- p_granularidad: '15min' | 'hora' | 'dia' | 'mes' | 'anio'
-- p_filtro: 'TODOS' | 'LABORABLES' | 'NO_LABORABLES' | 'EN_HORARIO' | 'FUERA_HORARIO'
-- Límites para no saturar la base de datos: 15 min ≤ 62 días,
-- hora ≤ 400 días.
-- ---------------------------------------------------------
create or replace function private.validar_serie(p_desde timestamptz, p_hasta timestamptz, p_granularidad text, p_filtro text)
returns void
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_hasta <= p_desde then
    raise exception 'El periodo no es válido';
  end if;
  if p_granularidad not in ('15min', 'hora', 'dia', 'mes', 'anio') then
    raise exception 'Granularidad no válida: %', p_granularidad;
  end if;
  if p_filtro not in ('TODOS', 'LABORABLES', 'NO_LABORABLES', 'EN_HORARIO', 'FUERA_HORARIO') then
    raise exception 'Filtro no válido: %', p_filtro;
  end if;
  if (p_granularidad = '15min' and p_hasta - p_desde > interval '62 days')
     or (p_granularidad = 'hora' and p_hasta - p_desde > interval '400 days') then
    raise exception 'Periodo demasiado largo para la granularidad %: elija una agrupación mayor', p_granularidad;
  end if;
end;
$$;

create or replace function private.inicio_intervalo(p_instante timestamptz, p_granularidad text, p_zona text)
returns timestamptz
language sql
immutable
set search_path = ''
as $$
  select case p_granularidad
    when '15min' then pg_catalog.date_bin('15 minutes', p_instante, timestamptz '2000-01-01 00:00:00+00')
    when 'hora'  then pg_catalog.date_trunc('hour',  p_instante at time zone p_zona) at time zone p_zona
    when 'dia'   then pg_catalog.date_trunc('day',   p_instante at time zone p_zona) at time zone p_zona
    when 'mes'   then pg_catalog.date_trunc('month', p_instante at time zone p_zona) at time zone p_zona
    when 'anio'  then pg_catalog.date_trunc('year',  p_instante at time zone p_zona) at time zone p_zona
  end;
$$;

-- ¿Cumple el instante el filtro de calendario?
create or replace function private.cumple_filtro(
  p_filtro text, p_laborable boolean, p_inicio time, p_fin time, p_hora time)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case p_filtro
    when 'TODOS' then true
    when 'LABORABLES' then p_laborable
    when 'NO_LABORABLES' then not p_laborable
    when 'EN_HORARIO' then p_laborable and p_inicio is not null
                           and p_hora >= p_inicio and p_hora < p_fin
    when 'FUERA_HORARIO' then not (p_laborable and p_inicio is not null
                                   and p_hora >= p_inicio and p_hora < p_fin)
  end;
$$;

-- Serie de una magnitud del edificio. Energía, agua y emisiones se
-- SUMAN; el resto (potencia, temperatura...) se PROMEDIA.
create or replace function public.serie_magnitud(
  p_id_magnitud_edificio uuid,
  p_desde timestamptz,
  p_hasta timestamptz,
  p_granularidad text default 'hora',
  p_filtro text default 'TODOS'
)
returns table (instante timestamptz, valor double precision, minimo double precision, maximo double precision, muestras integer)
language plpgsql
stable
set search_path = ''
as $$
declare
  v_edificio uuid;
  v_zona text;
  v_suma boolean;
begin
  perform private.validar_serie(p_desde, p_hasta, p_granularidad, p_filtro);

  select me.id_edificio, e.zona_horaria, m.unidad in ('kWh', 'MWh', 'Wh', 'm3', 'kgCO2e', 'tCO2e')
    into v_edificio, v_zona, v_suma
  from public.magnitudes_edificio me
  join public.magnitudes m on m.id = me.id_magnitud
  join public.edificios e on e.id = me.id_edificio
  where me.id = p_id_magnitud_edificio;

  if v_edificio is null then
    raise exception 'Magnitud inexistente o sin acceso';
  end if;

  return query
  with dias as (
    select d::date as fecha, c.laborable, c.hora_inicio, c.hora_fin
    from pg_catalog.generate_series((p_desde at time zone v_zona)::date, (p_hasta at time zone v_zona)::date, interval '1 day') d
    cross join lateral public.dia_calendario(v_edificio, d::date) c
  )
  select private.inicio_intervalo(v.fecha_hora, p_granularidad, v_zona) as instante,
         case when v_suma then sum(v.valor) else avg(v.valor) end,
         min(v.valor), max(v.valor), count(*)::integer
  from public.valores_magnitud v
  join dias on dias.fecha = (v.fecha_hora at time zone v_zona)::date
  where v.id_magnitud_edificio = p_id_magnitud_edificio
    and v.fecha_hora >= p_desde and v.fecha_hora < p_hasta
    and private.cumple_filtro(p_filtro, dias.laborable, dias.hora_inicio, dias.hora_fin,
                              (v.fecha_hora at time zone v_zona)::time)
  group by 1
  order by 1;
end;
$$;

-- Serie de un sensor (lecturas brutas). En sensores acumulativos o
-- de contaje devuelve el CONSUMO de cada intervalo (diferencia del
-- contador); en el resto, el promedio.
create or replace function public.serie_sensor(
  p_id_sensor uuid,
  p_desde timestamptz,
  p_hasta timestamptz,
  p_granularidad text default 'hora',
  p_filtro text default 'TODOS'
)
returns table (instante timestamptz, valor double precision, minimo double precision, maximo double precision, muestras integer)
language plpgsql
stable
set search_path = ''
as $$
declare
  v_edificio uuid;
  v_zona text;
  v_acumulativo boolean;
begin
  perform private.validar_serie(p_desde, p_hasta, p_granularidad, p_filtro);

  select public.obtener_edificio_recinto(s.id_recinto), n.codigo in ('ACUMULATIVA', 'CONTAJE')
    into v_edificio, v_acumulativo
  from public.sensores s
  join public.naturalezas_sensor n on n.id = s.id_naturaleza
  where s.id = p_id_sensor;

  select e.zona_horaria into v_zona from public.edificios e where e.id = v_edificio;

  if v_edificio is null or v_zona is null then
    raise exception 'Sensor inexistente o sin acceso';
  end if;

  return query
  with dias as (
    select d::date as fecha, c.laborable, c.hora_inicio, c.hora_fin
    from pg_catalog.generate_series((p_desde at time zone v_zona)::date - 1, (p_hasta at time zone v_zona)::date, interval '1 day') d
    cross join lateral public.dia_calendario(v_edificio, d::date) c
  ),
  -- En acumulativos se incluye la última lectura anterior al periodo
  -- para poder calcular el consumo del primer intervalo.
  base as (
    select l.fecha_hora, l.valor
    from public.lecturas l
    where l.id_sensor = p_id_sensor
      and l.fecha_hora >= p_desde and l.fecha_hora < p_hasta
    union all
    (select l.fecha_hora, l.valor from public.lecturas l
     where v_acumulativo and l.id_sensor = p_id_sensor and l.fecha_hora < p_desde
     order by l.fecha_hora desc limit 1)
  ),
  grupos as (
    select private.inicio_intervalo(b.fecha_hora, p_granularidad, v_zona) as inst,
           avg(b.valor) as media, min(b.valor) as mn, max(b.valor) as mx, count(*)::integer as n,
           bool_or(b.fecha_hora >= p_desde) as en_periodo,
           bool_and(private.cumple_filtro(p_filtro, dias.laborable, dias.hora_inicio, dias.hora_fin,
                                          (b.fecha_hora at time zone v_zona)::time)) as cumple
    from base b
    join dias on dias.fecha = (b.fecha_hora at time zone v_zona)::date
    group by 1
  ),
  calculado as (
    select g.inst, g.mn, g.mx, g.n, g.en_periodo, g.cumple,
           case when v_acumulativo
                then g.mx - lag(g.mx) over (order by g.inst)
                else g.media end as v
    from grupos g
  )
  select c.inst, c.v, c.mn, c.mx, c.n
  from calculado c
  where c.en_periodo and c.cumple and c.v is not null
  order by c.inst;
end;
$$;

-- ---------------------------------------------------------
-- 3. Pestaña HOY
-- ---------------------------------------------------------
create or replace function public.hoy_edificio(
  p_id_edificio uuid,
  p_ahora timestamptz default now()
)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_zona text;
  v_hoy date;
  v_transcurrido interval;
  v_comp date;
  v_cal record;
  v_cal_comp record;
  v_res jsonb;
begin
  select e.zona_horaria into v_zona from public.edificios e where e.id = p_id_edificio;
  if v_zona is null then
    raise exception 'Edificio inexistente o sin acceso';
  end if;

  v_hoy := (p_ahora at time zone v_zona)::date;
  v_transcurrido := (p_ahora at time zone v_zona) - v_hoy::timestamp;
  v_comp := public.dia_comparable(p_id_edificio, v_hoy);
  select * into v_cal from public.dia_calendario(p_id_edificio, v_hoy);
  select * into v_cal_comp from public.dia_calendario(p_id_edificio, v_comp);

  with
  mags as (
    select me.id, m.codigo
    from public.magnitudes_edificio me
    join public.magnitudes m on m.id = me.id_magnitud
    where me.id_edificio = p_id_edificio and me.ambito = 'EDIFICIO' and me.activa
      and m.codigo in ('CONSUMO_ELECTRICIDAD', 'CONSUMO_GAS', 'CONSUMO_AGUA', 'ENERGIA_EXPORTADA',
                       'GENERACION_FOTOVOLTAICA', 'GENERACION_EOLICA', 'GENERACION_SOLAR_TERMICA',
                       'GENERACION_GEOTERMIA', 'GENERACION_BIOMASA', 'POTENCIA_TOTAL')
  ),
  -- Aporte de cada valor a la ENERGÍA CONSUMIDA (opción B):
  -- importada + gas + renovables − exportada.
  vals as (
    select m.codigo, v.valor, v.fecha_hora,
           case when m.codigo in ('CONSUMO_ELECTRICIDAD', 'CONSUMO_GAS') or m.codigo like 'GENERACION_%' then v.valor
                when m.codigo = 'ENERGIA_EXPORTADA' then -v.valor
                else 0 end as aporte,
           case when (v.fecha_hora at time zone v_zona)::date = v_hoy then 'hoy' else 'comp' end as dia,
           (v.fecha_hora at time zone v_zona)::time as hora
    from public.valores_magnitud v
    join mags m on m.id = v.id_magnitud_edificio
    where (v.fecha_hora >= (v_hoy::timestamp at time zone v_zona) and v.fecha_hora < p_ahora)
       or (v.fecha_hora >= (v_comp::timestamp at time zone v_zona)
           and v.fecha_hora < ((v_comp + 1)::timestamp at time zone v_zona))
  ),
  -- Hasta la misma hora en ambos días
  tramo as (
    select * from vals
    where dia = 'hoy' or (fecha_hora < ((v_comp::timestamp + v_transcurrido) at time zone v_zona))
  ),
  sumas as (
    select dia,
      greatest(sum(aporte), 0) as energia,
      sum(valor) filter (where codigo = 'CONSUMO_ELECTRICIDAD') as electricidad,
      sum(valor) filter (where codigo = 'CONSUMO_GAS') as gas,
      sum(valor) filter (where codigo = 'CONSUMO_AGUA') as agua,
      sum(valor) filter (where codigo like 'GENERACION_%') as renovable,
      greatest(coalesce(sum(valor) filter (where codigo like 'GENERACION_%'), 0)
               - coalesce(sum(valor) filter (where codigo = 'ENERGIA_EXPORTADA'), 0), 0) as renovable_consumida,
      sum(case codigo
            when 'CONSUMO_ELECTRICIDAD' then valor * coalesce(public.factor_co2('FACTOR_CO2_ELECTRICIDAD', v_hoy), 0)
            when 'CONSUMO_GAS' then valor * coalesce(public.factor_co2('FACTOR_CO2_GAS', v_hoy), 0)
          end) as kg_co2,
      sum(aporte) filter (where not private.cumple_filtro('EN_HORARIO',
              case when dia = 'hoy' then v_cal.laborable else v_cal_comp.laborable end,
              case when dia = 'hoy' then v_cal.hora_inicio else v_cal_comp.hora_inicio end,
              case when dia = 'hoy' then v_cal.hora_fin else v_cal_comp.hora_fin end,
              hora)) as fuera_horario
    from tramo group by dia
  ),
  curva as (
    select pg_catalog.to_char(pg_catalog.date_bin('15 minutes', hora::interval + timestamp '2000-01-01', timestamp '2000-01-01'), 'HH24:MI') as franja,
           sum(aporte) filter (where dia = 'hoy') as hoy,
           sum(aporte) filter (where dia = 'comp') as comparable
    from vals
    where aporte <> 0
    group by 1
  )
  select pg_catalog.jsonb_build_object(
    'fecha', v_hoy,
    'hora', pg_catalog.to_char(p_ahora at time zone v_zona, 'HH24:MI'),
    'zona_horaria', v_zona,
    'laborable', v_cal.laborable,
    'horario', case when v_cal.hora_inicio is not null
                 then pg_catalog.jsonb_build_object('inicio', v_cal.hora_inicio, 'fin', v_cal.hora_fin) end,
    'dia_comparable', pg_catalog.jsonb_build_object('fecha', v_comp, 'laborable', v_cal_comp.laborable),
    'potencia_actual_kw', (select v.valor from public.valores_magnitud v join mags m on m.id = v.id_magnitud_edificio
                           where m.codigo = 'POTENCIA_TOTAL' and v.fecha_hora <= p_ahora
                             and v.fecha_hora > p_ahora - interval '1 hour'
                           order by v.fecha_hora desc limit 1),
    'hoy', (select pg_catalog.jsonb_build_object(
              'energia_kwh', coalesce(energia, 0), 'electricidad_kwh', coalesce(electricidad, 0),
              'gas_kwh', coalesce(gas, 0), 'agua_m3', coalesce(agua, 0),
              'renovable_kwh', coalesce(renovable, 0), 'tco2', coalesce(kg_co2, 0) / 1000.0,
              'fuera_horario_kwh', coalesce(fuera_horario, 0),
              'fuera_horario_pct', case when coalesce(energia, 0) > 0
                                     then round((coalesce(fuera_horario, 0) / energia * 100)::numeric, 1) end,
              'renovable_consumida_kwh', coalesce(renovable_consumida, 0),
              'cobertura_renovable_pct', case when coalesce(energia, 0) > 0
                                   then round((coalesce(renovable_consumida, 0) / energia * 100)::numeric, 1) end)
            from sumas where dia = 'hoy'),
    'comparable_mismo_tramo', (select pg_catalog.jsonb_build_object(
              'energia_kwh', coalesce(energia, 0), 'agua_m3', coalesce(agua, 0),
              'renovable_kwh', coalesce(renovable, 0), 'tco2', coalesce(kg_co2, 0) / 1000.0,
              'fuera_horario_kwh', coalesce(fuera_horario, 0))
            from sumas where dia = 'comp'),
    'variacion_energia_pct', (select case when c.energia > 0
                                then round(((coalesce(h.energia, 0) - c.energia) / c.energia * 100)::numeric, 1) end
                              from (select energia from sumas where dia = 'comp') c
                              left join (select energia from sumas where dia = 'hoy') h on true),
    'curva', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                'franja', franja, 'hoy', hoy, 'comparable', comparable) order by franja) from curva), '[]'::jsonb)
  ) into v_res;

  return v_res;
end;
$$;

-- ---------------------------------------------------------
-- 4. Sensores con su estado y posiciones 3D (etiquetas y paneles)
-- ---------------------------------------------------------
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
  ubicaciones jsonb
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
         ), '[]'::jsonb)
  from public.sensores s
  join public.familias_sensor f on f.id = s.id_familia
  left join public.estado_comunicacion ec on ec.id_sensor = s.id
  where s.activo
    and public.obtener_edificio_recinto(s.id_recinto) = p_id_edificio;
$$;

revoke all on function public.dia_calendario(uuid, date) from public, anon;
revoke all on function public.dia_comparable(uuid, date) from public, anon;
revoke all on function private.validar_serie(timestamptz, timestamptz, text, text) from public, anon;
revoke all on function private.inicio_intervalo(timestamptz, text, text) from public, anon;
revoke all on function private.cumple_filtro(text, boolean, time, time, time) from public, anon;
revoke all on function public.serie_magnitud(uuid, timestamptz, timestamptz, text, text) from public, anon;
revoke all on function public.serie_sensor(uuid, timestamptz, timestamptz, text, text) from public, anon;
revoke all on function public.hoy_edificio(uuid, timestamptz) from public, anon;
revoke all on function public.sensores_estado_edificio(uuid) from public, anon;

grant execute on function private.validar_serie(timestamptz, timestamptz, text, text) to authenticated, service_role;
grant execute on function private.inicio_intervalo(timestamptz, text, text) to authenticated, service_role;
grant execute on function private.cumple_filtro(text, boolean, time, time, time) to authenticated, service_role;
grant execute on function public.dia_calendario(uuid, date) to authenticated, service_role;
grant execute on function public.dia_comparable(uuid, date) to authenticated, service_role;
grant execute on function public.serie_magnitud(uuid, timestamptz, timestamptz, text, text) to authenticated, service_role;
grant execute on function public.serie_sensor(uuid, timestamptz, timestamptz, text, text) to authenticated, service_role;
grant execute on function public.hoy_edificio(uuid, timestamptz) to authenticated, service_role;
grant execute on function public.sensores_estado_edificio(uuid) to authenticated, service_role;

-- Magnitud de potencia total del edificio (para "potencia actual" en HOY)
insert into public.magnitudes (codigo, nombre, unidad, descripcion)
values ('POTENCIA_TOTAL', 'Potencia total', 'kW', 'Potencia calculada según las fuentes configuradas.')
on conflict (codigo) do nothing;

commit;
