-- =========================================================
-- 034 · Panel del edificio: ambiente por recinto, fuentes de hoy,
--       alarmas y agrupación semanal
-- Decisión D42 (02/11/2026): nueva página de edificio en tres zonas
-- (pestañas a la izquierda; 3D o sensores y gráfica en el centro;
-- alarmas a la derecha).
--
--   · Temporadas y temperatura de confort del edificio (para el KPI de
--     ambiente). Confort entre 19 y 27 °C (sin incluirlos). Temporadas
--     por fechas (MM-DD), iguales cada año; pueden cruzar el año.
--   · Colores (criterio de ahorro energético):
--       invierno:  T ≤ 19 verde · 19 < T ≤ confort naranja · T > confort rojo
--       verano:    T ≥ 27 verde · confort ≤ T < 27 naranja · T < confort rojo
--       resto del año: la temperatura no se colorea
--       humedad (todo el año): 30–70 % verde; fuera, rojo
--       CO₂: sin color por ahora
--   · ambiente_edificio(): último valor por recinto (media si hay varios
--     sensores iguales en el recinto).
--   · fuentes_hoy_edificio(): electricidad, gas y renovable consumida de
--     hoy frente al día comparable hasta la misma hora.
--   · alarmas_edificio(): alarmas activas y sensores sin comunicación.
--   · serie_magnitud / serie_sensor admiten agrupación por semana.
-- =========================================================
begin;

-- ---------------------------------------------------------
-- 1. Configuración del edificio: confort y temporadas
-- ---------------------------------------------------------
alter table public.edificios
  add column if not exists temperatura_confort numeric(4,1) not null default 25,
  add column if not exists invierno_desde varchar(5) not null default '11-01',
  add column if not exists invierno_hasta varchar(5) not null default '03-31',
  add column if not exists verano_desde varchar(5) not null default '06-01',
  add column if not exists verano_hasta varchar(5) not null default '09-30';

alter table public.edificios drop constraint if exists edificios_confort_ck;
alter table public.edificios add constraint edificios_confort_ck
  check (temperatura_confort > 19 and temperatura_confort < 27);
alter table public.edificios drop constraint if exists edificios_temporadas_ck;
alter table public.edificios add constraint edificios_temporadas_ck check (
  invierno_desde ~ '^(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$' and invierno_hasta ~ '^(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$'
  and verano_desde ~ '^(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$' and verano_hasta ~ '^(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$');

comment on column public.edificios.temperatura_confort is
  'Temperatura de confort (°C) para el KPI de ambiente. Mayor que 19 y menor que 27.';
comment on column public.edificios.invierno_desde is
  'Inicio de la temporada de calefacción (MM-DD). Las temporadas se repiten cada año y pueden cruzar el año (11-01 a 03-31).';

-- Temporada de una fecha para un edificio: INVIERNO, VERANO o null
create or replace function public.temporada_edificio(p_id_edificio uuid, p_fecha date default current_date)
returns text
language sql
stable
set search_path = ''
as $$
  with e as (
    select pg_catalog.to_char(p_fecha, 'MM-DD') as d, invierno_desde, invierno_hasta, verano_desde, verano_hasta
    from public.edificios where id = p_id_edificio
  )
  select case
    when (invierno_desde <= invierno_hasta and d between invierno_desde and invierno_hasta)
      or (invierno_desde > invierno_hasta and (d >= invierno_desde or d <= invierno_hasta)) then 'INVIERNO'
    when (verano_desde <= verano_hasta and d between verano_desde and verano_hasta)
      or (verano_desde > verano_hasta and (d >= verano_desde or d <= verano_hasta)) then 'VERANO'
  end
  from e;
$$;

-- Color de la temperatura según la temporada
create or replace function public.estado_temperatura(p_valor numeric, p_temporada text, p_confort numeric)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_valor is null or p_temporada is null then null
    when p_temporada = 'INVIERNO' then
      case when p_valor <= 19 then 'VERDE' when p_valor <= p_confort then 'NARANJA' else 'ROJO' end
    when p_temporada = 'VERANO' then
      case when p_valor >= 27 then 'VERDE' when p_valor >= p_confort then 'NARANJA' else 'ROJO' end
  end;
$$;

create or replace function public.estado_humedad(p_valor numeric)
returns text
language sql
immutable
set search_path = ''
as $$
  select case when p_valor is null then null when p_valor >= 30 and p_valor <= 70 then 'VERDE' else 'ROJO' end;
$$;

-- ---------------------------------------------------------
-- 2. Ambiente por recinto (temperatura, humedad, CO₂)
-- ---------------------------------------------------------
create or replace function public.ambiente_edificio(p_id_edificio uuid)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_edif record;
  v_temporada text;
  v_res jsonb;
begin
  select e.id, e.zona_horaria, e.temperatura_confort into v_edif from public.edificios e where e.id = p_id_edificio;
  if v_edif.id is null then
    raise exception 'Edificio inexistente o sin acceso';
  end if;
  v_temporada := public.temporada_edificio(p_id_edificio, (pg_catalog.now() at time zone v_edif.zona_horaria)::date);

  with valores as (
    select r.id as id_recinto, r.nombre as recinto, p.nombre as planta, p.nivel, f.codigo as familia,
           avg(ec.ultimo_valor) as valor, max(ec.ultima_lectura) as ultima_lectura
    from public.sensores s
    join public.familias_sensor f on f.id = s.id_familia and f.codigo in ('TEMPERATURA', 'HUMEDAD', 'CO2')
    join public.recintos r on r.id = s.id_recinto
    join public.plantas p on p.id = r.id_planta and p.id_edificio = p_id_edificio
    left join public.estado_comunicacion ec on ec.id_sensor = s.id
    where s.activo
    group by r.id, r.nombre, p.nombre, p.nivel, f.codigo
  ),
  por_recinto as (
    select id_recinto, recinto, planta, nivel,
      max(valor) filter (where familia = 'TEMPERATURA') as t,
      max(ultima_lectura) filter (where familia = 'TEMPERATURA') as t_fecha,
      bool_or(familia = 'TEMPERATURA') as hay_t,
      max(valor) filter (where familia = 'HUMEDAD') as h,
      max(ultima_lectura) filter (where familia = 'HUMEDAD') as h_fecha,
      bool_or(familia = 'HUMEDAD') as hay_h,
      max(valor) filter (where familia = 'CO2') as c,
      max(ultima_lectura) filter (where familia = 'CO2') as c_fecha,
      bool_or(familia = 'CO2') as hay_c
    from valores
    group by id_recinto, recinto, planta, nivel
  )
  select pg_catalog.jsonb_build_object(
    'temporada', v_temporada,
    'temperatura_confort', v_edif.temperatura_confort,
    'recintos', coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id_recinto', id_recinto, 'recinto', recinto, 'planta', planta, 'nivel', nivel,
        'temperatura', case when hay_t then pg_catalog.jsonb_build_object(
            'valor', round(t::numeric, 1), 'ultima_lectura', t_fecha,
            'estado', public.estado_temperatura(round(t::numeric, 1), v_temporada, v_edif.temperatura_confort)) end,
        'humedad', case when hay_h then pg_catalog.jsonb_build_object(
            'valor', round(h::numeric, 0), 'ultima_lectura', h_fecha,
            'estado', public.estado_humedad(round(h::numeric, 0))) end,
        'co2', case when hay_c then pg_catalog.jsonb_build_object(
            'valor', round(c::numeric, 0), 'ultima_lectura', c_fecha) end)
      order by nivel, recinto), '[]'::jsonb))
  into v_res
  from por_recinto;

  return v_res;
end;
$$;

-- ---------------------------------------------------------
-- 3. Fuentes de energía de hoy frente al día comparable
--    (mismo tramo horario que hoy_edificio)
-- ---------------------------------------------------------
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
  v_res jsonb;
begin
  select e.zona_horaria into v_zona from public.edificios e where e.id = p_id_edificio;
  if v_zona is null then
    raise exception 'Edificio inexistente o sin acceso';
  end if;
  v_hoy := (p_ahora at time zone v_zona)::date;
  v_transcurrido := (p_ahora at time zone v_zona) - v_hoy::timestamp;
  v_comp := public.dia_comparable(p_id_edificio, v_hoy);

  with mags as (
    select me.id, m.codigo from public.magnitudes_edificio me join public.magnitudes m on m.id = me.id_magnitud
    where me.id_edificio = p_id_edificio and me.ambito = 'EDIFICIO' and me.activa
      and (m.codigo in ('CONSUMO_ELECTRICIDAD', 'CONSUMO_GAS', 'ENERGIA_EXPORTADA') or m.codigo like 'GENERACION_%')
  ),
  tramo as (
    select m.codigo, v.valor,
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
               - coalesce(sum(valor) filter (where codigo = 'ENERGIA_EXPORTADA'), 0), 0) as renovable
    from tramo group by dia
  ),
  fuentes(codigo, nombre, orden) as (
    values ('ELECTRICIDAD', 'Electricidad de la red', 1), ('GAS', 'Gas', 2), ('RENOVABLE', 'Renovables', 3)
  ),
  tabla as (
    select f.codigo, f.nombre, f.orden,
      (exists (select 1 from mags m where (f.codigo = 'ELECTRICIDAD' and m.codigo = 'CONSUMO_ELECTRICIDAD')
                                       or (f.codigo = 'GAS' and m.codigo = 'CONSUMO_GAS')
                                       or (f.codigo = 'RENOVABLE' and m.codigo like 'GENERACION_%'))) as configurada,
      (select case f.codigo when 'ELECTRICIDAD' then electricidad when 'GAS' then gas else renovable end
       from sumas where dia = 'hoy') as hoy,
      (select case f.codigo when 'ELECTRICIDAD' then electricidad when 'GAS' then gas else renovable end
       from sumas where dia = 'comp') as comparable
    from fuentes f
  )
  select pg_catalog.jsonb_build_object(
    'dia_comparable', v_comp,
    'fuentes', coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'codigo', codigo, 'nombre', nombre, 'kwh', coalesce(hoy, 0), 'comparable_kwh', comparable,
      'variacion_pct', case when comparable > 0 then round(((coalesce(hoy, 0) - comparable) / comparable * 100)::numeric, 1) end)
      order by orden) filter (where configurada), '[]'::jsonb))
  into v_res
  from tabla;

  return v_res;
end;
$$;

-- ---------------------------------------------------------
-- 4. Alarmas del edificio: alarmas activas o reconocidas y
--    sensores sin comunicación (el motor de alarmas llegará después)
-- ---------------------------------------------------------
create or replace function public.alarmas_edificio(p_id_edificio uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(pg_catalog.jsonb_agg(x.fila order by x.prioridad desc, x.desde desc), '[]'::jsonb)
  from (
    select n.prioridad, ea.fecha_inicio as desde,
           pg_catalog.jsonb_build_object(
             'tipo', 'ALARMA', 'id', ea.id, 'nivel', n.codigo, 'nivel_nombre', n.nombre, 'prioridad', n.prioridad,
             'titulo', ra.nombre, 'detalle', ea.mensaje, 'estado', ea.estado, 'desde', ea.fecha_inicio,
             'valor', ea.valor_detectado, 'id_sensor', coalesce(ea.id_sensor, ra.id_sensor),
             'sensor', s.nombre, 'recinto', r.nombre) as fila
    from public.eventos_alarma ea
    join public.reglas_alarma ra on ra.id = ea.id_regla_alarma and ra.id_edificio = p_id_edificio
    join public.niveles_alarma n on n.id = ra.id_nivel_alarma
    left join public.sensores s on s.id = coalesce(ea.id_sensor, ra.id_sensor)
    left join public.recintos r on r.id = coalesce(ea.id_recinto, s.id_recinto)
    where ea.estado in ('ACTIVA', 'RECONOCIDA')
    union all
    select 2, ic.fecha_inicio,
           pg_catalog.jsonb_build_object(
             'tipo', 'COMUNICACION', 'id', ic.id, 'nivel', 'AVISO', 'nivel_nombre', 'Aviso', 'prioridad', 2,
             'titulo', 'Sin comunicación', 'detalle', 'No llegan lecturas de este sensor', 'estado', 'ACTIVA',
             'desde', ic.fecha_inicio, 'id_sensor', s.id, 'sensor', s.nombre, 'recinto', r.nombre)
    from public.incidencias_comunicacion ic
    join public.sensores s on s.id = ic.id_sensor and s.activo
    join public.recintos r on r.id = s.id_recinto
    join public.plantas p on p.id = r.id_planta and p.id_edificio = p_id_edificio
    where ic.estado = 'ABIERTA'
  ) x;
$$;

-- ---------------------------------------------------------
-- 5. Agrupación por semana (lunes a domingo) en las series
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
  if p_granularidad not in ('15min', 'hora', 'dia', 'semana', 'mes', 'anio') then
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
    when '15min'  then pg_catalog.date_bin('15 minutes', p_instante, timestamptz '2000-01-01 00:00:00+00')
    when 'hora'   then pg_catalog.date_trunc('hour',  p_instante at time zone p_zona) at time zone p_zona
    when 'dia'    then pg_catalog.date_trunc('day',   p_instante at time zone p_zona) at time zone p_zona
    when 'semana' then pg_catalog.date_trunc('week',  p_instante at time zone p_zona) at time zone p_zona
    when 'mes'    then pg_catalog.date_trunc('month', p_instante at time zone p_zona) at time zone p_zona
    when 'anio'   then pg_catalog.date_trunc('year',  p_instante at time zone p_zona) at time zone p_zona
  end;
$$;

-- ---------------------------------------------------------
-- 6. Permisos
-- ---------------------------------------------------------
revoke all on function public.temporada_edificio(uuid, date) from public, anon;
revoke all on function public.estado_temperatura(numeric, text, numeric) from public, anon;
revoke all on function public.estado_humedad(numeric) from public, anon;
revoke all on function public.ambiente_edificio(uuid) from public, anon;
revoke all on function public.fuentes_hoy_edificio(uuid, timestamptz) from public, anon;
revoke all on function public.alarmas_edificio(uuid) from public, anon;
grant execute on function public.temporada_edificio(uuid, date) to authenticated, service_role;
grant execute on function public.estado_temperatura(numeric, text, numeric) to authenticated, service_role;
grant execute on function public.estado_humedad(numeric) to authenticated, service_role;
grant execute on function public.ambiente_edificio(uuid) to authenticated, service_role;
grant execute on function public.fuentes_hoy_edificio(uuid, timestamptz) to authenticated, service_role;
grant execute on function public.alarmas_edificio(uuid) to authenticated, service_role;

commit;
