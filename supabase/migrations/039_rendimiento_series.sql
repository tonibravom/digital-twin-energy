-- =========================================================
-- 039 · Rendimiento de las series de la gráfica
-- (09/11/2026) Con la sesión de un usuario (RLS), serie_magnitud,
-- serie_sensor y serie_energia tardaban de 3 a 14 s en periodos de 7 días
-- o más: PostgreSQL integraba el calendario en la consulta y llamaba a
-- dia_calendario() en cada cuarto de hora (unos 3 ms por llamada con RLS).
-- Supabase corta las consultas de los usuarios a los 8 s y el navegador
-- mostraba "Failed to fetch". Ahora el calendario del periodo se lee una
-- sola vez. Mismo resultado, sin cambios de interfaz.
-- =========================================================
begin;

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
  -- Calendario del periodo leído una sola vez (materialized): antes se evaluaba
  -- dia_calendario() en cada fila y, con RLS, tardaba segundos (039)
  with dias as materialized (
    select d::date as fecha, coalesce(c.laborable, extract(isodow from d) < 6) as laborable, c.hora_inicio, c.hora_fin
    from pg_catalog.generate_series((p_desde at time zone v_zona)::date, (p_hasta at time zone v_zona)::date, interval '1 day') d
    left join public.calendario_edificio c on c.id_edificio = v_edificio and c.fecha = d::date
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
  -- Calendario del periodo leído una sola vez (materialized): antes se evaluaba
  -- dia_calendario() en cada fila y, con RLS, tardaba segundos (039)
  with dias as materialized (
    select d::date as fecha, coalesce(c.laborable, extract(isodow from d) < 6) as laborable, c.hora_inicio, c.hora_fin
    from pg_catalog.generate_series((p_desde at time zone v_zona)::date - 1, (p_hasta at time zone v_zona)::date, interval '1 day') d
    left join public.calendario_edificio c on c.id_edificio = v_edificio and c.fecha = d::date
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

create or replace function public.serie_energia(
  p_id_edificio uuid,
  p_serie text,
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
  v_zona text;
  v_fuente boolean := false;
  v_codigo text;
  v_cuadro uuid;
  v_grupo text;
  v_es_grupo boolean := false;
  v_resto boolean := false;
begin
  perform private.validar_serie(p_desde, p_hasta, p_granularidad, p_filtro);
  select e.zona_horaria into v_zona from public.edificios e where e.id = p_id_edificio;
  if v_zona is null then
    raise exception 'Edificio inexistente o sin acceso';
  end if;

  if p_serie in ('ENERGIA_CONSUMIDA', 'ELECTRICIDAD', 'RED', 'FOTOVOLTAICA', 'EOLICA', 'EXPORTADA', 'GAS', 'RENOVABLE',
                 'CALOR_RENOVABLE', 'SOLAR_TERMICA', 'GEOTERMIA', 'BIOMASA', 'EMISIONES') then
    v_fuente := true;
  elsif p_serie = 'OTROS_NO_MEDIDO' then
    v_codigo := p_serie;
    v_resto := true;
  else
    v_codigo := pg_catalog.split_part(p_serie, ':', 1);
    if pg_catalog.strpos(p_serie, ':') > 0 then
      begin
        v_cuadro := pg_catalog.split_part(p_serie, ':', 2)::uuid;
      exception when others then
        raise exception 'Serie desconocida: %', p_serie;
      end;
    end if;
    select coalesce(p.codigo, u.codigo) into v_grupo
    from public.usos_energia u left join public.usos_energia p on p.id = u.id_padre
    where u.codigo = v_codigo;
    if v_grupo is null then
      raise exception 'Serie desconocida: %', p_serie;
    end if;
    v_es_grupo := v_cuadro is null and v_codigo = v_grupo;
    v_resto := v_es_grupo and v_grupo = 'OTROS';
  end if;

  return query
  with
  -- Calendario del periodo leído una sola vez (materialized): antes se evaluaba
  -- dia_calendario() en cada fila y, con RLS, tardaba segundos (039)
  dias as materialized (
    select d::date as fecha, coalesce(c.laborable, extract(isodow from d) < 6) as laborable, c.hora_inicio, c.hora_fin
    from pg_catalog.generate_series((p_desde at time zone v_zona)::date, (p_hasta at time zone v_zona)::date, interval '1 day') d
    left join public.calendario_edificio c on c.id_edificio = p_id_edificio and c.fecha = d::date
  ),
  mags as (
    select me.id, m.codigo
    from public.magnitudes_edificio me join public.magnitudes m on m.id = me.id_magnitud
    where me.id_edificio = p_id_edificio and me.ambito = 'EDIFICIO' and me.activa
      and (m.codigo in ('CONSUMO_ELECTRICIDAD', 'CONSUMO_GAS', 'ENERGIA_EXPORTADA') or m.codigo like 'GENERACION_%')
  ),
  base as (
    select v.fecha_hora as t,
      coalesce(sum(v.valor) filter (where m.codigo = 'CONSUMO_ELECTRICIDAD'), 0) as red,
      coalesce(sum(v.valor) filter (where m.codigo = 'GENERACION_FOTOVOLTAICA'), 0) as fv,
      coalesce(sum(v.valor) filter (where m.codigo = 'GENERACION_EOLICA'), 0) as eol,
      coalesce(sum(v.valor) filter (where m.codigo = 'ENERGIA_EXPORTADA'), 0) as exp,
      coalesce(sum(v.valor) filter (where m.codigo = 'CONSUMO_GAS'), 0) as gas,
      coalesce(sum(v.valor) filter (where m.codigo = 'GENERACION_SOLAR_TERMICA'), 0) as st,
      coalesce(sum(v.valor) filter (where m.codigo = 'GENERACION_GEOTERMIA'), 0) as geo,
      coalesce(sum(v.valor) filter (where m.codigo = 'GENERACION_BIOMASA'), 0) as bio
    from public.valores_magnitud v join mags m on m.id = v.id_magnitud_edificio
    where v.fecha_hora >= p_desde and v.fecha_hora < p_hasta
    group by v.fecha_hora
  ),
  b as (select x.*, least(x.exp, x.fv + x.eol) as exp_ef from base x),
  usos as (
    select vu.fecha_hora as t, vu.tipo_energia as tipo, vu.id_cuadro as cuadro, vu.valor as kwh,
           u.codigo, coalesce(p.codigo, u.codigo) as grupo
    from public.valores_usos vu
    join public.usos_energia u on u.id = vu.id_uso_energia
    left join public.usos_energia p on p.id = u.id_padre
    where not v_fuente and vu.id_edificio = p_id_edificio and vu.fecha_hora >= p_desde and vu.fecha_hora < p_hasta
  ),
  usos_t as (
    select x.t, x.tipo, sum(x.kwh) as medido,
           coalesce(sum(x.kwh) filter (where
             (v_es_grupo and x.grupo = v_grupo)
             or (not v_es_grupo and v_cuadro is not null and x.codigo = v_codigo and x.cuadro = v_cuadro)
             or (not v_es_grupo and v_cuadro is null and x.codigo = v_codigo and (x.grupo = 'HVAC' or x.cuadro is null))), 0) as sel
    from usos x group by x.t, x.tipo
  ),
  pct as (
    select ru.tipo_energia as tipo, sum(ru.porcentaje) as total,
           coalesce(sum(ru.porcentaje) filter (where
             (v_es_grupo and coalesce(p.codigo, u.codigo) = v_grupo)
             or (not v_es_grupo and v_cuadro is null and u.codigo = v_codigo and u.codigo <> 'OTROS_SIN_DESGLOSE')
             or (p_serie = 'OTROS_NO_MEDIDO' and u.codigo = 'OTROS_SIN_DESGLOSE')), 0) as sel
    from public.repartos_uso_edificio ru
    join public.usos_energia u on u.id = ru.id_uso_energia
    left join public.usos_energia p on p.id = u.id_padre
    where ru.id_edificio = p_id_edificio
    group by ru.tipo_energia
  ),
  tipos(tipo) as (values ('ELECTRICIDAD'::text), ('GAS'), ('CALOR_RENOVABLE')),
  cuartos as (select x.t from b x where not v_fuente union select y.t from usos y),
  por_tipo as (
    select c.t, ti.tipo,
           coalesce(case ti.tipo when 'ELECTRICIDAD' then bb.red + bb.fv + bb.eol - bb.exp_ef
                                 when 'GAS' then bb.gas else bb.st + bb.geo + bb.bio end, 0) as total,
           coalesce(ut.medido, 0) as medido, coalesce(ut.sel, 0) as sel,
           coalesce(pc.sel, 0) + case when v_resto then 100 - coalesce(pc.total, 0) else 0 end as porcentaje
    from cuartos c
    cross join tipos ti
    left join b bb on bb.t = c.t
    left join usos_t ut on ut.t = c.t and ut.tipo = ti.tipo
    left join pct pc on pc.tipo = ti.tipo
  ),
  valores as (
    select x.t,
           case p_serie
             when 'ENERGIA_CONSUMIDA' then x.red + x.fv + x.eol - x.exp_ef + x.gas + x.st + x.geo + x.bio
             when 'ELECTRICIDAD' then x.red + x.fv + x.eol - x.exp_ef
             when 'RED' then x.red
             when 'FOTOVOLTAICA' then x.fv
             when 'EOLICA' then x.eol
             when 'EXPORTADA' then x.exp
             when 'GAS' then x.gas
             when 'RENOVABLE' then x.fv + x.eol - x.exp_ef + x.st + x.geo + x.bio
             when 'CALOR_RENOVABLE' then x.st + x.geo + x.bio
             when 'SOLAR_TERMICA' then x.st
             when 'GEOTERMIA' then x.geo
             when 'BIOMASA' then x.bio
             when 'EMISIONES' then
               x.red * coalesce(public.factor_co2('FACTOR_CO2_ELECTRICIDAD', (x.t at time zone v_zona)::date), 0)
               + x.gas * coalesce(public.factor_co2('FACTOR_CO2_GAS', (x.t at time zone v_zona)::date), 0)
           end as kwh
    from b x where v_fuente
    union all
    select pt.t, sum(pt.sel + greatest(pt.total - pt.medido, 0) * pt.porcentaje / 100.0)
    from por_tipo pt where not v_fuente
    group by pt.t
  )
  select private.inicio_intervalo(vv.t, p_granularidad, v_zona),
         sum(vv.kwh), min(vv.kwh), max(vv.kwh), count(*)::integer
  from valores vv
  join dias on dias.fecha = (vv.t at time zone v_zona)::date
  where private.cumple_filtro(p_filtro, dias.laborable, dias.hora_inicio, dias.hora_fin, (vv.t at time zone v_zona)::time)
  group by 1
  order by 1;
end;
$$;

commit;
