-- =========================================================
-- 038 · Series de energía para la gráfica del panel y día comparable incompleto
-- Decisión D47 (03/11/2026).
--
--   · valores_usos: el motor guarda, cada 15 minutos, lo medido por uso y
--     cuadro y los "otros usos" de cada cuadro por diferencia. Los
--     resúmenes diarios por uso (Sankey) son la suma de esta serie, así la
--     gráfica y el Sankey coinciden.
--   · serie_energia(edificio, serie, desde, hasta, agrupación, filtro): la
--     serie de cualquier dato de energía del panel. "serie" es el
--     identificador del KPI o del nodo del Sankey:
--        ENERGIA_CONSUMIDA, ELECTRICIDAD (consumida), RED, FOTOVOLTAICA,
--        EOLICA, EXPORTADA, GAS, RENOVABLE (consumida), CALOR_RENOVABLE,
--        SOLAR_TERMICA, GEOTERMIA, BIOMASA, EMISIONES (kgCO₂e),
--        HVAC / ILUMINACION / OTROS (grupos), un uso final
--        (HVAC_REFRIGERACION…), uso y cuadro (ILUMINACION:<id del cuadro>)
--        y OTROS_NO_MEDIDO.
--     Misma regla que el Sankey: lo no medido se reparte con los porcentajes
--     del edificio y el resto es "otros usos · no medido".
--   · series_energia_edificio(edificio): las series disponibles, con su
--     nombre y su grupo, para el selector de la gráfica.
--   · hoy_edificio y fuentes_hoy_edificio: si el día comparable tiene menos
--     del 90 % de los cuartos de hora que tiene hoy (por ejemplo, mientras se
--     cargan históricos), no se calcula la variación y se avisa
--     (comparable_incompleto).
-- =========================================================
begin;

-- ---------------------------------------------------------
-- 1. Serie de 15 minutos por uso y cuadro
-- ---------------------------------------------------------
create table if not exists public.valores_usos (
  id_edificio uuid not null references public.edificios(id) on delete restrict,
  fecha_hora timestamptz not null,
  id_uso_energia smallint not null references public.usos_energia(id) on delete restrict,
  tipo_energia varchar(20) not null,
  id_cuadro uuid references public.cuadros_electricos(id) on delete restrict,
  valor double precision not null,
  constraint valores_usos_uq unique nulls not distinct (id_edificio, fecha_hora, id_uso_energia, tipo_energia, id_cuadro),
  constraint valores_usos_tipo_ck check (tipo_energia in ('ELECTRICIDAD', 'GAS', 'CALOR_RENOVABLE'))
);

comment on table public.valores_usos is
  'Energía de cada cuarto de hora por uso y cuadro (kWh), calculada por el motor: submedidores y "otros usos" de cada cuadro por diferencia.';

alter table public.valores_usos enable row level security;

drop policy if exists valores_usos_select on public.valores_usos;
create policy valores_usos_select on public.valores_usos
for select to authenticated
using (id_edificio in (select private.edificios_accesibles()));

create index if not exists valores_usos_edificio_fecha_idx on public.valores_usos (id_edificio, fecha_hora);

-- Recalcular los edificios que ya tienen usos, para rellenar la serie
insert into public.motor_pendiente as mp (id_edificio, desde, motivo)
select ru.id_edificio, min(ru.fecha)::timestamp at time zone 'UTC' - interval '1 day', 'CONFIGURACION'
from public.resumenes_diarios_usos ru
group by ru.id_edificio
on conflict (id_edificio) do update set desde = least(mp.desde, excluded.desde), actualizado = now();

-- ---------------------------------------------------------
-- 2. Motor (versión de la 037): serie de 15 minutos por uso y cuadro
-- ---------------------------------------------------------
create or replace function public.motor_calcular(p_id_edificio uuid, p_desde timestamptz, p_hasta timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_origen constant timestamptz := timestamptz '2000-01-01 00:00:00+00';
  v_zona text;
  v_desde timestamptz;
  v_hasta timestamptz := least(p_hasta, pg_catalog.now() + interval '1 day');
  v_previa timestamptz;
  v_dia_desde date;
  v_dia_hasta date;
  v_ini_dias timestamptz;
  v_fin_dias timestamptz;
  v_avisos text[] := '{}';
  v_nivel integer := 0;
  v_hechas integer;
  v_valores integer;
  v_resumenes integer;
  v_usos integer;
  v_otros integer;
  v_uso_otros smallint;
  r record;
begin
  select e.zona_horaria into v_zona from public.edificios e where e.id = p_id_edificio;
  if v_zona is null then
    raise exception 'Edificio inexistente';
  end if;
  if p_desde is null or p_desde >= v_hasta then
    return pg_catalog.jsonb_build_object('id_edificio', p_id_edificio, 'valores', 0, 'resumenes', 0);
  end if;

  select min(x.f) into v_previa
  from private.motor_sensores_edificio(p_id_edificio) s(id)
  cross join lateral (select l.fecha_hora as f from public.lecturas l
                      where l.id_sensor = s.id and l.fecha_hora < p_desde
                        and l.fecha_hora >= p_desde - interval '7 days'
                      order by l.fecha_hora desc limit 1) x;
  v_desde := pg_catalog.date_bin('15 minutes', least(p_desde, coalesce(v_previa, p_desde)), v_origen);

  perform public.asegurar_particiones_valores_magnitud(
    extract(year from v_desde at time zone 'UTC')::integer,
    extract(year from v_hasta at time zone 'UTC')::integer);

  if pg_catalog.to_regclass('pg_temp._motor_mag') is null then
    create temporary table _motor_mag (id uuid primary key, unidad text, nivel integer) on commit drop;
    create temporary table _motor_val (id_me uuid, instante timestamptz, valor double precision, calidad smallint) on commit drop;
  else
    truncate _motor_mag;
    truncate _motor_val;
  end if;
  if pg_catalog.to_regclass('pg_temp._motor_q') is null then
    create temporary table _motor_q (funcion text, id_uso smallint, id_cuadro uuid, tipo text, instante timestamptz,
                                     kwh double precision) on commit drop;
  else
    truncate _motor_q;
  end if;

  insert into _motor_mag (id, unidad, nivel)
  select me.id, m.unidad, null
  from public.magnitudes_edificio me
  join public.magnitudes m on m.id = me.id_magnitud
  where me.id_edificio = p_id_edificio and me.activa
    and exists (select 1 from public.magnitudes_fuentes mf where mf.id_magnitud_edificio = me.id);

  loop
    update _motor_mag mm set nivel = v_nivel
    where mm.nivel is null
      and not exists (select 1 from public.magnitudes_fuentes mf
                      left join _motor_mag o on o.id = mf.id_magnitud_origen
                      where mf.id_magnitud_edificio = mm.id and mf.id_magnitud_origen is not null
                        and (o.id is null or o.nivel is null));
    get diagnostics v_hechas = row_count;
    exit when v_hechas = 0;

    for r in
      select mf.id_magnitud_edificio as id_me, mf.id_sensor, mf.papel, mm.unidad as unidad_mag,
             s.unidad as unidad_sensor, s.codigo, te.codigo as tipo_energia
      from public.magnitudes_fuentes mf
      join _motor_mag mm on mm.id = mf.id_magnitud_edificio and mm.nivel = v_nivel
      join public.sensores s on s.id = mf.id_sensor
      left join public.tipos_energia te on te.id = s.id_tipo_energia
    loop
      if private.motor_factor_unidad(r.unidad_sensor, r.unidad_mag, r.tipo_energia, v_desde::date) is null then
        v_avisos := v_avisos || pg_catalog.format('Sensor %s: no se puede pasar de %s a %s', r.codigo, r.unidad_sensor, r.unidad_mag);
        continue;
      end if;
      insert into _motor_val (id_me, instante, valor, calidad)
      select r.id_me, x.instante,
             x.valor * private.motor_factor_unidad(r.unidad_sensor, r.unidad_mag, r.tipo_energia,
                                                   (x.instante at time zone v_zona)::date)
                     * case when r.papel = 'RESTA' then -1 else 1 end,
             x.calidad
      from private.motor_serie_fuente(r.id_sensor, v_desde, v_hasta) x;
    end loop;

    insert into _motor_val (id_me, instante, valor, calidad)
    select mf.id_magnitud_edificio, v.instante,
           v.valor * case when mf.papel = 'RESTA' then -1 else 1 end, v.calidad
    from public.magnitudes_fuentes mf
    join _motor_mag mm on mm.id = mf.id_magnitud_edificio and mm.nivel = v_nivel
    join (select id_me, instante, sum(valor) as valor, max(calidad) as calidad
          from _motor_val group by 1, 2) v on v.id_me = mf.id_magnitud_origen;

    v_nivel := v_nivel + 1;
    exit when v_nivel > 20;
  end loop;

  if exists (select 1 from _motor_mag where nivel is null) then
    v_avisos := v_avisos || 'Algunas magnitudes dependen de otras que no tienen fuentes: no se calculan';
  end if;

  delete from public.valores_magnitud v
  where v.id_magnitud_edificio in (select me.id from public.magnitudes_edificio me where me.id_edificio = p_id_edificio)
    and v.fecha_hora >= v_desde and v.fecha_hora < v_hasta;

  insert into public.valores_magnitud (id_magnitud_edificio, fecha_hora, valor, calidad, version_motor)
  select id_me, instante, sum(valor), max(calidad), '1.2'
  from _motor_val
  group by id_me, instante;
  get diagnostics v_valores = row_count;

  -- -------- Resúmenes diarios de los días locales afectados --------
  v_dia_desde := (v_desde at time zone v_zona)::date;
  v_dia_hasta := ((v_hasta - interval '1 microsecond') at time zone v_zona)::date;
  v_ini_dias := v_dia_desde::timestamp at time zone v_zona;
  v_fin_dias := (v_dia_hasta + 1)::timestamp at time zone v_zona;

  delete from public.resumenes_diarios rd
  where rd.id_edificio = p_id_edificio and rd.origen = 'MOTOR'
    and rd.fecha between v_dia_desde and v_dia_hasta;

  insert into public.resumenes_diarios (id_edificio, fecha, indicador, valor, completo, origen)
  select p_id_edificio, d.fecha, d.indicador, d.valor,
         d.intervalos >= extract(epoch from ((d.fecha + 1)::timestamp at time zone v_zona)
                                          - (d.fecha::timestamp at time zone v_zona)) / 900
           and d.calidad = 0,
         'MOTOR'
  from (
    select (v.fecha_hora at time zone v_zona)::date as fecha,
           case m.codigo when 'ENERGIA_EXPORTADA' then 'ELECTRICIDAD_EXPORTADA' else m.codigo end as indicador,
           sum(v.valor) as valor, count(distinct v.fecha_hora) as intervalos, max(v.calidad) as calidad
    from public.valores_magnitud v
    join public.magnitudes_edificio me on me.id = v.id_magnitud_edificio
    join public.magnitudes m on m.id = me.id_magnitud
    where me.id_edificio = p_id_edificio and me.activa and me.ambito = 'EDIFICIO'
      and m.codigo in ('CONSUMO_ELECTRICIDAD', 'CONSUMO_GAS', 'CONSUMO_AGUA', 'ENERGIA_EXPORTADA',
                       'GENERACION_FOTOVOLTAICA', 'GENERACION_EOLICA', 'GENERACION_SOLAR_TERMICA',
                       'GENERACION_GEOTERMIA', 'GENERACION_BIOMASA')
      and v.fecha_hora >= v_ini_dias and v.fecha_hora < v_fin_dias
    group by 1, 2
  ) d
  on conflict (id_edificio, fecha, indicador) do nothing;
  get diagnostics v_resumenes = row_count;

  -- -------- Consumo por usos y cuadros: serie de 15 min (gráfica) y días (Sankey) --------
  -- 1) kWh de cada cuarto de hora de cada medidor de cuadro o de uso
  insert into _motor_q (funcion, id_uso, id_cuadro, tipo, instante, kwh)
  select s.funcion_medidor, s.id_uso_energia, s.id_cuadro,
         case te.codigo when 'GAS' then 'GAS' when 'TERMICA' then 'CALOR_RENOVABLE' else 'ELECTRICIDAD' end,
         x.instante,
         sum(x.valor * private.motor_factor_unidad(s.unidad, 'kWh', te.codigo, (x.instante at time zone v_zona)::date))
  from public.sensores s
  join public.tipos_energia te on te.id = s.id_tipo_energia and te.codigo in ('ELECTRICIDAD', 'GAS', 'TERMICA')
  cross join lateral private.motor_serie_fuente(s.id, v_ini_dias, v_fin_dias) x
  where s.activo and s.funcion_medidor in ('CUADRO', 'USO')
    and public.obtener_edificio_recinto(s.id_recinto) = p_id_edificio
    and private.motor_factor_unidad(s.unidad, 'kWh', te.codigo, v_dia_desde) is not null
  group by 1, 2, 3, 4, 5
  having sum(x.valor) is not null;

  delete from public.valores_usos vu
  where vu.id_edificio = p_id_edificio and vu.fecha_hora >= v_ini_dias and vu.fecha_hora < v_fin_dias;

  -- 2) Lo que miden los submedidores, con su cuadro
  insert into public.valores_usos (id_edificio, fecha_hora, id_uso_energia, tipo_energia, id_cuadro, valor)
  select p_id_edificio, instante, id_uso, tipo, id_cuadro, sum(kwh)
  from _motor_q where funcion = 'USO'
  group by instante, id_uso, tipo, id_cuadro;
  get diagnostics v_usos = row_count;

  -- 3) "Otros usos" de cada cuadro con medidor, por diferencia en cada cuarto de hora
  v_uso_otros := (select id from public.usos_energia where codigo = 'OTROS_SIN_DESGLOSE');
  with recursive
  cuadros as (
    select c.id, c.id_cuadro_padre,
           exists (select 1 from public.sensores s where s.id_cuadro = c.id and s.funcion_medidor = 'CUADRO' and s.activo) as con_medidor
    from public.cuadros_electricos c
    where c.id_edificio = p_id_edificio and c.activo
  ),
  -- Para cada cuadro con medidor: él mismo y, bajando, sus hijos; se baja por los
  -- cuadros sin medidor y se para en los que tienen medidor (se resta su total).
  arbol(raiz, id, con_medidor) as (
    select c.id, c.id, c.con_medidor from cuadros c where c.con_medidor
    union all
    select a.raiz, h.id, h.con_medidor
    from arbol a join cuadros h on h.id_cuadro_padre = a.id
    where a.id = a.raiz or not a.con_medidor
  ),
  restar as (
    select a.raiz, d.instante, sum(d.kwh) as kwh
    from arbol a
    join _motor_q d on d.id_cuadro = a.id and d.tipo = 'ELECTRICIDAD'
     and ((d.funcion = 'USO' and (a.id = a.raiz or not a.con_medidor))
          or (d.funcion = 'CUADRO' and a.id <> a.raiz and a.con_medidor))
    group by a.raiz, d.instante
  ),
  totales as (
    select d.id_cuadro, d.instante, sum(d.kwh) as kwh from _motor_q d
    where d.funcion = 'CUADRO' group by d.id_cuadro, d.instante
  )
  insert into public.valores_usos (id_edificio, fecha_hora, id_uso_energia, tipo_energia, id_cuadro, valor)
  select p_id_edificio, t.instante, v_uso_otros, 'ELECTRICIDAD', t.id_cuadro,
         greatest(t.kwh - coalesce(rs.kwh, 0), 0)
  from totales t
  left join restar rs on rs.raiz = t.id_cuadro and rs.instante = t.instante
  on conflict (id_edificio, fecha_hora, id_uso_energia, tipo_energia, id_cuadro)
    do update set valor = public.valores_usos.valor + excluded.valor;
  get diagnostics v_otros = row_count;

  -- 4) Resúmenes diarios por uso y cuadro (Sankey): suma de la serie, así gráfica y Sankey coinciden
  delete from public.resumenes_diarios_usos ru
  where ru.id_edificio = p_id_edificio and ru.fecha between v_dia_desde and v_dia_hasta;
  insert into public.resumenes_diarios_usos (id_edificio, fecha, id_uso_energia, tipo_energia, id_cuadro, valor)
  select p_id_edificio, (vu.fecha_hora at time zone v_zona)::date, vu.id_uso_energia, vu.tipo_energia, vu.id_cuadro, sum(vu.valor)
  from public.valores_usos vu
  where vu.id_edificio = p_id_edificio and vu.fecha_hora >= v_ini_dias and vu.fecha_hora < v_fin_dias
  group by 2, 3, 4, 5;

  if exists (
    with dia as (
      select d.id_cuadro, (d.instante at time zone v_zona)::date as fecha,
             sum(d.kwh) filter (where d.funcion = 'CUADRO') as total, sum(d.kwh) filter (where d.funcion = 'USO') as usos
      from _motor_q d where d.id_cuadro is not null
      group by 1, 2)
    select 1 from dia where dia.total is not null and dia.total + 0.5 < coalesce(dia.usos, 0)) then
    v_avisos := v_avisos || 'En algún cuadro los submedidores suman más que el total del cuadro: revise su configuración';
  end if;

  return pg_catalog.jsonb_build_object(
    'id_edificio', p_id_edificio, 'desde', v_desde, 'hasta', v_hasta,
    'magnitudes', (select count(*) from _motor_mag where nivel is not null),
    'valores', v_valores, 'resumenes', v_resumenes, 'usos', v_usos, 'otros_cuadros', v_otros,
    'avisos', pg_catalog.to_jsonb(v_avisos));
end;
$$;

-- ---------------------------------------------------------
-- 3. Serie de cualquier dato de energía del panel
-- ---------------------------------------------------------
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
  dias as (
    select d::date as fecha, c.laborable, c.hora_inicio, c.hora_fin
    from pg_catalog.generate_series((p_desde at time zone v_zona)::date, (p_hasta at time zone v_zona)::date, interval '1 day') d
    cross join lateral public.dia_calendario(p_id_edificio, d::date) c
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

-- ---------------------------------------------------------
-- 4. Series de energía disponibles en un edificio (selector de la gráfica)
-- ---------------------------------------------------------
create or replace function public.series_energia_edificio(p_id_edificio uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  with
  mags as (
    select m.codigo from public.magnitudes_edificio me join public.magnitudes m on m.id = me.id_magnitud
    where me.id_edificio = p_id_edificio and me.ambito = 'EDIFICIO' and me.activa
  ),
  hay as (
    select bool_or(codigo = 'CONSUMO_ELECTRICIDAD') as red, bool_or(codigo = 'CONSUMO_GAS') as gas,
           bool_or(codigo = 'ENERGIA_EXPORTADA') as exp, bool_or(codigo like 'GENERACION_%') as gen,
           bool_or(codigo in ('GENERACION_FOTOVOLTAICA', 'GENERACION_EOLICA')) as gen_elec,
           bool_or(codigo = 'GENERACION_FOTOVOLTAICA') as fv, bool_or(codigo = 'GENERACION_EOLICA') as eol,
           bool_or(codigo = 'GENERACION_SOLAR_TERMICA') as st, bool_or(codigo = 'GENERACION_GEOTERMIA') as geo,
           bool_or(codigo = 'GENERACION_BIOMASA') as bio
    from mags
  ),
  fuentes(id, nombre, orden, unidad) as (
    select 'ENERGIA_CONSUMIDA', 'Energía total consumida', 1, 'kWh' from hay where red or gas or gen
    union all select 'RED', 'Electricidad de la red', 2, 'kWh' from hay where red
    union all select 'ELECTRICIDAD', 'Electricidad consumida (red + renovable)', 3, 'kWh' from hay where red and gen_elec
    union all select 'GAS', 'Gas', 4, 'kWh' from hay where gas
    union all select 'RENOVABLE', 'Renovables consumidas', 5, 'kWh' from hay where gen
    union all select 'FOTOVOLTAICA', 'Fotovoltaica generada', 6, 'kWh' from hay where fv
    union all select 'EOLICA', 'Eólica generada', 7, 'kWh' from hay where eol
    union all select 'SOLAR_TERMICA', 'Solar térmica', 8, 'kWh' from hay where st
    union all select 'GEOTERMIA', 'Geotermia', 9, 'kWh' from hay where geo
    union all select 'BIOMASA', 'Biomasa', 10, 'kWh' from hay where bio
    union all select 'EXPORTADA', 'Exportada a la red', 11, 'kWh' from hay where exp
    union all select 'EMISIONES', 'Emisiones', 12, 'kgCO₂e' from hay where red or gas
  ),
  -- Nodos de uso según la configuración (submedidores, cuadros con medidor y repartos)
  base_usos as (
    select s.id_uso_energia as uso, s.id_cuadro as cuadro
    from public.sensores s
    where s.activo and s.funcion_medidor = 'USO' and public.obtener_edificio_recinto(s.id_recinto) = p_id_edificio
    union
    select (select id from public.usos_energia where codigo = 'OTROS_SIN_DESGLOSE'), s.id_cuadro
    from public.sensores s
    where s.activo and s.funcion_medidor = 'CUADRO' and public.obtener_edificio_recinto(s.id_recinto) = p_id_edificio
    union
    select ru.id_uso_energia, null::uuid from public.repartos_uso_edificio ru
    where ru.id_edificio = p_id_edificio
      and ru.id_uso_energia <> (select id from public.usos_energia where codigo = 'OTROS_SIN_DESGLOSE')
  ),
  nodos as (
    select distinct
           case when coalesce(p.codigo, u.codigo) = 'HVAC' or bu.cuadro is null then u.codigo
                else u.codigo || ':' || bu.cuadro::text end as id,
           case when coalesce(p.codigo, u.codigo) = 'HVAC' or bu.cuadro is null then u.nombre
                else u.nombre || ' · ' || coalesce(public.ubicacion_cuadro(bu.cuadro), '?') end as nombre,
           coalesce(p.codigo, u.codigo) as grupo, coalesce(p.nombre, u.nombre) as nombre_grupo,
           coalesce(p.orden, u.orden) as orden_grupo, u.orden,
           case when coalesce(p.codigo, u.codigo) = 'HVAC' or bu.cuadro is null then 0
                else coalesce((select pl.nivel from public.cuadros_electricos c
                               left join public.recintos rc on rc.id = c.id_recinto
                               join public.plantas pl on pl.id = coalesce(c.id_planta, rc.id_planta)
                               where c.id = bu.cuadro), 0) * 10
                     + (select case when c.id_recinto is null then 0 else 1 end from public.cuadros_electricos c where c.id = bu.cuadro)
           end as orden_cuadro
    from base_usos bu
    join public.usos_energia u on u.id = bu.uso
    left join public.usos_energia p on p.id = u.id_padre
  ),
  grupos as (
    select distinct grupo, nombre_grupo, orden_grupo from nodos
  ),
  lista as (
    select 0 as bloque, f.orden as o1, 0 as o2, 0 as o3, f.id, f.nombre, 'Edificio'::text as grupo, f.unidad from fuentes f
    union all
    select 1, g.orden_grupo, -1, 0, g.grupo,
           case g.grupo when 'HVAC' then 'Total HVAC' when 'ILUMINACION' then 'Total alumbrado' else 'Total ' || pg_catalog.lower(g.nombre_grupo) end,
           g.nombre_grupo, 'kWh'
    from grupos g
    union all
    select 1, n.orden_grupo, n.orden, n.orden_cuadro, n.id, n.nombre, n.nombre_grupo, 'kWh' from nodos n where n.id <> n.grupo
    union all
    select 1, (select orden from public.usos_energia where codigo = 'OTROS'), 9999, 0, 'OTROS_NO_MEDIDO', 'Otros usos · no medido',
           (select nombre from public.usos_energia where codigo = 'OTROS'), 'kWh'
    from hay where red and exists (select 1 from nodos)
  )
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('id', id, 'nombre', nombre, 'grupo', grupo, 'unidad', unidad)
                                       order by bloque, o1, o2, o3, nombre), '[]'::jsonb)
  from lista;
$$;

-- ---------------------------------------------------------
-- 5. Hoy y fuentes de hoy: sin variación si el día comparable está incompleto
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
      count(distinct fecha_hora) filter (where aporte <> 0) as cuartos,
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
    -- Día comparable incompleto (por ejemplo, mientras se cargan históricos): sin variación
    'comparable_incompleto', coalesce((select c.cuartos < 0.9 * coalesce(h.cuartos, 0)
                              from (select cuartos from sumas where dia = 'hoy') h
                              left join (select cuartos from sumas where dia = 'comp') c on true), false)
                             or not exists (select 1 from sumas where dia = 'comp'),
    'variacion_energia_pct', (select case when c.energia > 0 and c.cuartos >= 0.9 * coalesce(h.cuartos, 0)
                                then round(((coalesce(h.energia, 0) - c.energia) / c.energia * 100)::numeric, 1) end
                              from (select energia, cuartos from sumas where dia = 'comp') c
                              left join (select energia, cuartos from sumas where dia = 'hoy') h on true),
    'curva', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                'franja', franja, 'hoy', hoy, 'comparable', comparable) order by franja) from curva), '[]'::jsonb)
  ) into v_res;

  return v_res;
end;
$$;

create or replace function public.fuentes_hoy_edificio(p_id_edificio uuid, p_ahora timestamptz default now())
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_zona text;
  v_hoy date;
  v_comp date;
  v_transcurrido interval;
  v_f_elec numeric;
  v_f_gas numeric;
  v_res jsonb;
begin
  select e.zona_horaria into v_zona from public.edificios e where e.id = p_id_edificio;
  if v_zona is null then
    raise exception 'Edificio inexistente o sin acceso';
  end if;
  v_hoy := (p_ahora at time zone v_zona)::date;
  v_transcurrido := (p_ahora at time zone v_zona) - v_hoy::timestamp;
  v_comp := public.dia_comparable(p_id_edificio, v_hoy);
  v_f_elec := coalesce(public.factor_co2('FACTOR_CO2_ELECTRICIDAD', v_hoy), 0);
  v_f_gas := coalesce(public.factor_co2('FACTOR_CO2_GAS', v_hoy), 0);

  with mags as (
    select me.id, m.codigo from public.magnitudes_edificio me join public.magnitudes m on m.id = me.id_magnitud
    where me.id_edificio = p_id_edificio and me.ambito = 'EDIFICIO' and me.activa
      and (m.codigo in ('CONSUMO_ELECTRICIDAD', 'CONSUMO_GAS', 'ENERGIA_EXPORTADA') or m.codigo like 'GENERACION_%')
  ),
  tramo as (
    select m.codigo, v.valor, v.fecha_hora,
           case when v.fecha_hora >= (v_hoy::timestamp at time zone v_zona) then 'hoy' else 'comp' end as dia
    from public.valores_magnitud v join mags m on m.id = v.id_magnitud_edificio
    where (v.fecha_hora >= (v_hoy::timestamp at time zone v_zona) and v.fecha_hora < p_ahora)
       or (v_comp is not null and v.fecha_hora >= (v_comp::timestamp at time zone v_zona)
           and v.fecha_hora < ((v_comp::timestamp + v_transcurrido) at time zone v_zona))
  ),
  sumas as (
    select dia,
      coalesce(sum(valor) filter (where codigo = 'CONSUMO_ELECTRICIDAD'), 0) as electricidad,
      coalesce(sum(valor) filter (where codigo = 'CONSUMO_GAS'), 0) as gas,
      greatest(coalesce(sum(valor) filter (where codigo like 'GENERACION_%'), 0)
               - coalesce(sum(valor) filter (where codigo = 'ENERGIA_EXPORTADA'), 0), 0) as renovable,
      count(distinct fecha_hora) filter (where codigo = 'CONSUMO_ELECTRICIDAD') as c_electricidad,
      count(distinct fecha_hora) filter (where codigo = 'CONSUMO_GAS') as c_gas,
      count(distinct fecha_hora) filter (where codigo like 'GENERACION_%') as c_renovable
    from tramo group by dia
  ),
  fuentes(codigo, nombre, orden, factor) as (
    values ('ELECTRICIDAD', 'Electricidad de la red', 1, v_f_elec), ('GAS', 'Gas', 2, v_f_gas), ('RENOVABLE', 'Renovables', 3, 0::numeric)
  ),
  tabla0 as (
    select f.codigo, f.nombre, f.orden, f.factor,
      (exists (select 1 from mags m where (f.codigo = 'ELECTRICIDAD' and m.codigo = 'CONSUMO_ELECTRICIDAD')
                                       or (f.codigo = 'GAS' and m.codigo = 'CONSUMO_GAS')
                                       or (f.codigo = 'RENOVABLE' and m.codigo like 'GENERACION_%'))) as configurada,
      coalesce((select case f.codigo when 'ELECTRICIDAD' then electricidad when 'GAS' then gas else renovable end
                from sumas where dia = 'hoy'), 0) as hoy,
      (select case f.codigo when 'ELECTRICIDAD' then electricidad when 'GAS' then gas else renovable end
       from sumas where dia = 'comp') as comparable_bruto,
      -- El día comparable cuenta solo si tiene al menos el 90 % de los cuartos de hora que tiene hoy
      coalesce((select case f.codigo when 'ELECTRICIDAD' then c_electricidad when 'GAS' then c_gas else c_renovable end
                from sumas where dia = 'comp'), 0)
        >= 0.9 * coalesce((select case f.codigo when 'ELECTRICIDAD' then c_electricidad when 'GAS' then c_gas else c_renovable end
                           from sumas where dia = 'hoy'), 0) as comparable_completo
    from fuentes f
  ),
  tabla as (
    select t0.*, case when t0.comparable_completo then t0.comparable_bruto end as comparable
    from tabla0 t0
  ),
  total as (select sum(hoy) as kwh, sum(hoy * factor) as kg from tabla where configurada)
  select pg_catalog.jsonb_build_object(
    'dia_comparable', v_comp,
    'comparable_incompleto', coalesce(bool_or(not comparable_completo) filter (where configurada), false),
    'total_kwh', (select kwh from total),
    'emisiones_kg', (select round(kg::numeric, 1) from total),
    'fuentes', coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'codigo', codigo, 'nombre', nombre, 'kwh', hoy, 'comparable_kwh', comparable,
      'variacion_pct', case when comparable > 0 then round(((hoy - comparable) / comparable * 100)::numeric, 1) end,
      'aporte_pct', case when (select kwh from total) > 0 then round((hoy / (select kwh from total) * 100)::numeric, 1) end,
      'emisiones_kg', case when codigo <> 'RENOVABLE' then round((hoy * factor)::numeric, 1) end)
      order by orden) filter (where configurada), '[]'::jsonb))
  into v_res
  from tabla;

  return v_res;
end;
$$;

-- ---------------------------------------------------------
-- 6. Permisos
-- ---------------------------------------------------------
revoke all on function public.motor_calcular(uuid, timestamptz, timestamptz) from public, anon, authenticated;
grant execute on function public.motor_calcular(uuid, timestamptz, timestamptz) to service_role;
revoke all on function public.serie_energia(uuid, text, timestamptz, timestamptz, text, text) from public, anon;
grant execute on function public.serie_energia(uuid, text, timestamptz, timestamptz, text, text) to authenticated, service_role;
revoke all on function public.series_energia_edificio(uuid) from public, anon;
grant execute on function public.series_energia_edificio(uuid) to authenticated, service_role;
revoke all on function public.hoy_edificio(uuid, timestamptz) from public, anon;
grant execute on function public.hoy_edificio(uuid, timestamptz) to authenticated, service_role;
revoke all on function public.fuentes_hoy_edificio(uuid, timestamptz) from public, anon;
grant execute on function public.fuentes_hoy_edificio(uuid, timestamptz) to authenticated, service_role;

commit;
