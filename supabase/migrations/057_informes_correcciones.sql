-- =========================================================
-- 057 · Informes: correcciones (D61)
--  - Emisiones: el factor de CO₂ se leía con un código equivocado (salían 0 tCO₂e).
--  - Consumo por día: la fecha se guardaba con hora y la gráfica no se dibujaba.
--  - Calidad de los datos: cuentan también los sensores dados de alta después del periodo
--    si tienen lecturas importadas de ese periodo.
-- Los informes ya generados se corrigen volviéndolos a generar (botón Informes).
-- =========================================================
begin;

create or replace function private.energia_periodo(p_id_edificio uuid, p_desde date, p_hasta date)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with d as (
    select r.indicador, r.fecha, r.valor,
           case r.indicador
             when 'CONSUMO_ELECTRICIDAD' then r.valor * coalesce(public.factor_co2('FACTOR_CO2_ELECTRICIDAD', r.fecha), 0)
             when 'CONSUMO_GAS' then r.valor * coalesce(public.factor_co2('FACTOR_CO2_GAS', r.fecha), 0)
           end as kg
    from public.resumenes_diarios r
    where r.id_edificio = p_id_edificio and r.fecha between p_desde and p_hasta
  ),
  s as (
    select count(distinct fecha) as dias,
      coalesce(sum(valor) filter (where indicador = 'CONSUMO_ELECTRICIDAD'), 0) as electricidad,
      coalesce(sum(valor) filter (where indicador = 'CONSUMO_GAS'), 0) as gas,
      coalesce(sum(valor) filter (where indicador = 'CONSUMO_AGUA'), 0) as agua,
      coalesce(sum(valor) filter (where indicador = 'ELECTRICIDAD_EXPORTADA'), 0) as exportada,
      coalesce(sum(valor) filter (where indicador in ('GENERACION_FOTOVOLTAICA', 'GENERACION_EOLICA')), 0) as ren_electrica,
      coalesce(sum(valor) filter (where indicador in ('GENERACION_SOLAR_TERMICA', 'GENERACION_GEOTERMIA', 'GENERACION_BIOMASA')), 0) as ren_termica,
      coalesce(sum(valor) filter (where indicador = 'GENERACION_FOTOVOLTAICA'), 0) as fotovoltaica,
      coalesce(sum(valor) filter (where indicador = 'GENERACION_SOLAR_TERMICA'), 0) as solar_termica,
      coalesce(sum(kg), 0) / 1000.0 as tco2
    from d
  )
  select case when s.dias = 0 then null else pg_catalog.jsonb_build_object(
    'dias', s.dias,
    'energia', pg_catalog.round((s.electricidad + s.gas + greatest(s.ren_electrica - s.exportada, 0) + s.ren_termica)::numeric, 1),
    'electricidad', pg_catalog.round(s.electricidad::numeric, 1), 'gas', pg_catalog.round(s.gas::numeric, 1),
    'agua', pg_catalog.round(s.agua::numeric, 2), 'exportada', pg_catalog.round(s.exportada::numeric, 1),
    'renovable_generada', pg_catalog.round((s.ren_electrica + s.ren_termica)::numeric, 1),
    'renovable_consumida', pg_catalog.round((greatest(s.ren_electrica - s.exportada, 0) + s.ren_termica)::numeric, 1),
    'fotovoltaica', pg_catalog.round(s.fotovoltaica::numeric, 1), 'solar_termica', pg_catalog.round(s.solar_termica::numeric, 1),
    'tco2', pg_catalog.round(s.tco2::numeric, 3),
    'cobertura_renovable_pct', case when s.electricidad + s.gas + greatest(s.ren_electrica - s.exportada, 0) + s.ren_termica > 0
      then pg_catalog.round(((greatest(s.ren_electrica - s.exportada, 0) + s.ren_termica)
             / (s.electricidad + s.gas + greatest(s.ren_electrica - s.exportada, 0) + s.ren_termica) * 100)::numeric, 1) end) end
  from s;
$$;
revoke all on function private.energia_periodo(uuid, date, date) from public, anon, authenticated;

create or replace function private.calcular_informe(p_id_edificio uuid, p_tipo text, p_desde date, p_hasta date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  e public.edificios%rowtype;
  v_ini timestamptz;
  v_fin timestamptz;
  v_dias integer := p_hasta - p_desde + 1;
  v_partner jsonb;
  v_energia jsonb;
  v_diario jsonb;
  v_horario jsonb;
  v_ambiente jsonb;
  v_alarmas jsonb;
  v_comunicacion jsonb;
  v_total double precision;
  v_fuera double precision;
begin
  select * into e from public.edificios where id = p_id_edificio;
  v_ini := p_desde::timestamp at time zone e.zona_horaria;
  v_fin := (p_hasta + 1)::timestamp at time zone e.zona_horaria;

  select pg_catalog.jsonb_build_object('nombre', p.nombre, 'logo', p.logo_ruta) into v_partner
  from public.proveedores_edificios pe join public.proveedores p on p.id = pe.id_proveedor
  where pe.id_edificio = p_id_edificio and pe.activo order by pe.fecha_inicio limit 1;
  if v_partner is null then   -- el Partner del cliente
    select pg_catalog.jsonb_build_object('nombre', p.nombre, 'logo', p.logo_ruta) into v_partner
    from public.proveedores_clientes pc join public.proveedores p on p.id = pc.id_proveedor
    where pc.id_cliente = e.id_cliente and pc.activo limit 1;
  end if;

  -- Energía: el periodo, el anterior y el mismo del año pasado
  v_energia := pg_catalog.jsonb_build_object(
    'actual', private.energia_periodo(p_id_edificio, p_desde, p_hasta),
    'anterior', private.energia_periodo(p_id_edificio, p_desde - v_dias, p_desde - 1),
    'anio_anterior', private.energia_periodo(p_id_edificio, (p_desde - interval '1 year')::date, (p_hasta - interval '1 year')::date));

  select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('fecha', g.f::date,
           'electricidad', x.electricidad, 'gas', x.gas, 'agua', x.agua, 'renovable', x.renovable) order by g.f)
    into v_diario
  from pg_catalog.generate_series(p_desde, p_hasta, interval '1 day') g(f)
  left join lateral (
    select pg_catalog.round(sum(r.valor) filter (where r.indicador = 'CONSUMO_ELECTRICIDAD')::numeric, 1) as electricidad,
           pg_catalog.round(sum(r.valor) filter (where r.indicador = 'CONSUMO_GAS')::numeric, 1) as gas,
           pg_catalog.round(sum(r.valor) filter (where r.indicador = 'CONSUMO_AGUA')::numeric, 2) as agua,
           pg_catalog.round(sum(r.valor) filter (where r.indicador like 'GENERACION_%')::numeric, 1) as renovable
    from public.resumenes_diarios r where r.id_edificio = p_id_edificio and r.fecha = g.f::date
  ) x on true;

  -- Dentro y fuera del horario de uso (calendario del edificio)
  begin
    select sum(valor) into v_total from public.serie_energia(p_id_edificio, 'ENERGIA_CONSUMIDA', v_ini, v_fin, 'dia', 'TODOS');
    select sum(valor) into v_fuera from public.serie_energia(p_id_edificio, 'ENERGIA_CONSUMIDA', v_ini, v_fin, 'dia', 'FUERA_HORARIO');
    if coalesce(v_total, 0) > 0 then
      v_horario := pg_catalog.jsonb_build_object('total_kwh', pg_catalog.round(v_total::numeric, 1),
        'fuera_kwh', pg_catalog.round(coalesce(v_fuera, 0)::numeric, 1),
        'fuera_pct', pg_catalog.round((coalesce(v_fuera, 0) / v_total * 100)::numeric, 1));
    end if;
  exception when others then
    v_horario := null;
  end;

  -- Ambiente (solo el mensual): horas de uso, temperatura respecto a la eficiente y CO₂, por recinto
  if p_tipo = 'MENSUAL' then
    with horas as (
      select h, (h at time zone e.zona_horaria)::date as dia
      from pg_catalog.generate_series(v_ini, v_fin - interval '1 hour', interval '1 hour') h
      where private.en_horario(p_id_edificio, h)
    ),
    temporada as (
      select dia, t, case t when 'INVIERNO' then e.temp_eficiencia_invierno when 'VERANO' then e.temp_eficiencia_verano end as te
      from (select distinct dia, public.temporada_edificio(p_id_edificio, dia) as t from horas) x
    ),
    sens as (
      select s.id, f.codigo as familia, rc.id as id_recinto, rc.nombre as recinto, pl.nombre as planta, pl.nivel
      from public.sensores s
      join public.familias_sensor f on f.id = s.id_familia and f.codigo in ('TEMPERATURA', 'CO2')
      join public.recintos rc on rc.id = s.id_recinto and coalesce(rc.tipo, '') <> 'ZONA_EXTERIOR'
      join public.plantas pl on pl.id = rc.id_planta and pl.id_edificio = p_id_edificio
      where s.activo and s.id_parametro_medidor is null
    ),
    horarias as (
      select se.id_recinto, se.familia, h.h, h.dia, avg(l.valor) as v
      from sens se
      join public.lecturas l on l.id_sensor = se.id and l.fecha_hora >= v_ini and l.fecha_hora < v_fin
      join horas h on h.h = pg_catalog.date_trunc('hour', l.fecha_hora)
      group by 1, 2, 3, 4
    ),
    por_recinto as (
      select r.id_recinto, r.recinto, r.planta, r.nivel,
        count(*) filter (where ho.familia = 'TEMPERATURA') as horas_temp,
        count(*) filter (where ho.familia = 'TEMPERATURA' and public.estado_temperatura(ho.v::numeric, t.t, t.te) in ('EFICIENTE', 'LEVE')) as horas_ok,
        count(*) filter (where ho.familia = 'TEMPERATURA' and public.estado_temperatura(ho.v::numeric, t.t, t.te) in ('ALTO', 'MUY_ALTO')) as horas_alto,
        avg(ho.v) filter (where ho.familia = 'TEMPERATURA') as temp_media,
        avg(ho.v) filter (where ho.familia = 'CO2') as co2_medio,
        max(ho.v) filter (where ho.familia = 'CO2') as co2_max,
        count(*) filter (where ho.familia = 'CO2' and ho.v > 1000) as horas_co2_alto
      from (select distinct id_recinto, recinto, planta, nivel from sens) r
      left join horarias ho on ho.id_recinto = r.id_recinto
      left join temporada t on t.dia = ho.dia
      group by 1, 2, 3, 4
    )
    select pg_catalog.jsonb_build_object(
      'horas_uso', (select count(*) from horas),
      'recintos', coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'recinto', recinto, 'planta', planta,
        'temp_media', pg_catalog.round(temp_media::numeric, 1),
        'pct_confort', case when horas_temp > 0 then pg_catalog.round((horas_ok::numeric / horas_temp * 100), 0) end,
        'horas_alto', horas_alto,
        'co2_medio', pg_catalog.round(co2_medio::numeric, 0), 'co2_max', pg_catalog.round(co2_max::numeric, 0),
        'horas_co2_alto', horas_co2_alto) order by nivel, recinto), '[]'::jsonb))
    into v_ambiente
    from por_recinto where horas_temp > 0 or co2_medio is not null;
  end if;

  -- Alarmas del periodo
  with ev as (
    select ea.*, n.codigo as nivel, ra.nombre as regla,
           extract(epoch from ea.fecha_reconocimiento - ea.fecha_inicio) / 60 as min_rec,
           extract(epoch from coalesce(ea.fecha_resuelta, ea.fecha_cierre) - ea.fecha_inicio) / 60 as min_res
    from public.eventos_alarma ea
    join public.reglas_alarma ra on ra.id = ea.id_regla_alarma and ra.id_edificio = p_id_edificio
    join public.niveles_alarma n on n.id = ra.id_nivel_alarma
    where ea.fecha_inicio >= v_ini and ea.fecha_inicio < v_fin
  ),
  ic as (
    select ic.*, s.nombre as sensor, r.nombre as recinto
    from public.incidencias_comunicacion ic
    join public.sensores s on s.id = ic.id_sensor
    join public.recintos r on r.id = s.id_recinto
    join public.plantas p on p.id = r.id_planta and p.id_edificio = p_id_edificio
    where ic.fecha_inicio >= v_ini and ic.fecha_inicio < v_fin
  )
  select pg_catalog.jsonb_build_object(
    'total', (select count(*) from ev),
    'muy_criticas', (select count(*) from ev where nivel = 'MUY_CRITICA'),
    'criticas', (select count(*) from ev where nivel = 'CRITICA'),
    'avisos', (select count(*) from ev where nivel = 'AVISO'),
    'sin_comunicacion', (select count(*) from ic),
    'min_reconocer_medio', (select pg_catalog.round(avg(min_rec)::numeric) from ev where min_rec is not null),
    'min_resolver_medio', (select pg_catalog.round(avg(min_res)::numeric) from ev where min_res is not null),
    'por_regla', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('regla', regla, 'nivel', nivel, 'veces', n) order by n desc, regla)
                           from (select regla, nivel, count(*) as n from ev group by 1, 2 order by 3 desc, 1 limit 8) x), '[]'::jsonb),
    'lista_muy_criticas', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'regla', ev.regla, 'detalle', ev.mensaje, 'desde', ev.fecha_inicio, 'minutos', pg_catalog.round(ev.min_res::numeric),
        'minutos_reconocer', pg_catalog.round(ev.min_rec::numeric), 'estado', ev.estado,
        'cierra', case when ev.cierre_automatico then 'Automático' else u.nombre end, 'comentario', ev.comentario) order by ev.fecha_inicio)
      from ev left join public.usuarios u on u.id = ev.id_usuario_cierra where ev.nivel = 'MUY_CRITICA'), '[]'::jsonb),
    'lista_avisos', coalesce((select pg_catalog.jsonb_agg(x.f order by x.d desc) from (
        select ev.fecha_inicio as d, pg_catalog.jsonb_build_object('regla', ev.regla, 'detalle', ev.mensaje, 'desde', ev.fecha_inicio,
                 'minutos', pg_catalog.round(ev.min_res::numeric)) as f from ev where ev.nivel = 'AVISO'
        union all
        select ic.fecha_inicio, pg_catalog.jsonb_build_object('regla', 'Sin comunicación', 'detalle', ic.sensor || ' · ' || ic.recinto,
                 'desde', ic.fecha_inicio, 'minutos', pg_catalog.round(extract(epoch from coalesce(ic.fecha_fin, v_fin) - ic.fecha_inicio) / 60))
        from ic order by 1 desc limit 30) x), '[]'::jsonb),
    'abiertas_al_final', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'regla', ra.nombre, 'nivel', n.codigo, 'desde', ea.fecha_inicio, 'detalle', ea.mensaje) order by n.prioridad desc, ea.fecha_inicio)
      from public.eventos_alarma ea
      join public.reglas_alarma ra on ra.id = ea.id_regla_alarma and ra.id_edificio = p_id_edificio
      join public.niveles_alarma n on n.id = ra.id_nivel_alarma
      where ea.fecha_inicio < v_fin and (ea.fecha_cierre is null or ea.fecha_cierre >= v_fin)), '[]'::jsonb))
  into v_alarmas;

  -- Comunicación: horas con datos de cada sensor activo
  with s as (
    select s.id, s.nombre, rc.nombre as recinto,
      x.horas,
      -- Horas esperadas desde el alta del sensor o, si hay datos anteriores importados, desde el inicio del periodo
      greatest(1, extract(epoch from v_fin - greatest(v_ini, least(s.fecha_alta::timestamp at time zone e.zona_horaria, x.primera))) / 3600) as esperadas
    from public.sensores s
    join public.recintos rc on rc.id = s.id_recinto
    join public.plantas pl on pl.id = rc.id_planta and pl.id_edificio = p_id_edificio
    cross join lateral (
      select count(distinct pg_catalog.date_trunc('hour', l.fecha_hora)) as horas, min(l.fecha_hora) as primera
      from public.lecturas l where l.id_sensor = s.id and l.fecha_hora >= v_ini and l.fecha_hora < v_fin
    ) x
    where s.activo and (s.fecha_alta <= p_hasta or x.horas > 0)
  )
  select pg_catalog.jsonb_build_object(
    'sensores', count(*),
    'pct_datos', case when count(*) > 0 then pg_catalog.round(avg(least(100, horas / esperadas * 100))::numeric, 1) end,
    'con_huecos', coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('sensor', nombre, 'recinto', recinto,
        'pct', pg_catalog.round(least(100, horas / esperadas * 100)::numeric, 0)) order by horas / esperadas)
      filter (where horas / esperadas < 0.95), '[]'::jsonb))
  into v_comunicacion
  from s;

  return pg_catalog.jsonb_build_object(
    'tipo', p_tipo, 'desde', p_desde, 'hasta', p_hasta,
    'edificio', pg_catalog.jsonb_build_object('id', e.id, 'nombre', e.nombre, 'codigo', e.codigo, 'municipio', e.municipio,
                                             'zona_horaria', e.zona_horaria, 'superficie_m2', e.superficie_util_m2),
    'marca', pg_catalog.jsonb_build_object('partner', v_partner,
      'plataforma', (select valor_texto from public.parametros_saas where codigo = 'NOMBRE_PLATAFORMA' and activo limit 1)),
    'energia', v_energia, 'diario', coalesce(v_diario, '[]'::jsonb), 'horario', v_horario,
    'ambiente', v_ambiente, 'alarmas', v_alarmas, 'comunicacion', v_comunicacion);
end;
$$;
revoke all on function private.calcular_informe(uuid, text, date, date) from public, anon, authenticated;

commit;
