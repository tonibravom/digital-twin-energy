-- =========================================================
-- 044 · Clima exterior (MET Norway)
-- Decisión D54 (12/11/2026; implementada 16/11/2026).
--
--   · La API consulta cada hora, por edificio con latitud y longitud, la
--     previsión de MET Norway (api.met.no, Locationforecast 2.0; datos con
--     licencia CC BY 4.0: hay que citar la fuente). La API identifica la
--     plataforma (User-Agent) y respeta la caducidad de cada respuesta.
--   · clima_observaciones: el tiempo de cada hora (el primer paso de la
--     previsión más reciente). Se guarda siempre: respaldo de los sensores
--     exteriores y base para la predicción de versiones futuras.
--   · clima_previsiones: la última previsión de los próximos días.
--   · clima_consultas: control de la consulta de cada edificio (solo la API).
--   · clima_edificio(): lo que muestra la web. Si el edificio tiene sensor
--     propio de temperatura o humedad exterior (recinto ZONA_EXTERIOR) y
--     comunica, se muestra su valor; si no, el de MET Norway.
-- =========================================================
begin;

-- 1. Tablas
create table if not exists public.clima_observaciones (
  id_edificio uuid not null references public.edificios(id) on delete restrict,
  fecha_hora timestamptz not null,
  temperatura numeric(5,1),
  humedad numeric(5,1),
  viento_ms numeric(5,1),
  viento_direccion numeric(5,1),
  nubosidad numeric(5,1),
  precipitacion_mm numeric(6,1),
  uv_cielo_despejado numeric(4,1),
  simbolo varchar(40),
  created_at timestamptz not null default now(),
  primary key (id_edificio, fecha_hora)
);
alter table public.clima_observaciones enable row level security;

create table if not exists public.clima_previsiones (
  id_edificio uuid not null references public.edificios(id) on delete restrict,
  fecha_hora timestamptz not null,
  horas smallint not null default 1,            -- 1 o 6: periodo del símbolo y la precipitación
  temperatura numeric(5,1),
  temperatura_min numeric(5,1),
  temperatura_max numeric(5,1),
  humedad numeric(5,1),
  viento_ms numeric(5,1),
  nubosidad numeric(5,1),
  precipitacion_mm numeric(6,1),
  uv_cielo_despejado numeric(4,1),
  simbolo varchar(40),
  emitida_en timestamptz not null,
  primary key (id_edificio, fecha_hora),
  constraint clima_previsiones_horas_ck check (horas in (1, 6, 12))
);
alter table public.clima_previsiones enable row level security;

create table if not exists public.clima_consultas (
  id_edificio uuid primary key references public.edificios(id) on delete restrict,
  expira_en timestamptz,
  ultima_modificacion text,
  actualizado_en timestamptz,
  ultimo_error text,
  updated_at timestamptz not null default now()
);
alter table public.clima_consultas enable row level security;   -- sin políticas: solo la API (service_role)

comment on table public.clima_observaciones is 'Tiempo de cada hora en el edificio según MET Norway (CC BY 4.0). Respaldo de los sensores exteriores y base para la predicción.';
comment on table public.clima_previsiones is 'Última previsión de MET Norway para el edificio (CC BY 4.0).';
comment on table public.clima_consultas is 'Control de la consulta horaria a MET Norway por edificio (caducidad y Last-Modified). Solo la API.';

-- Lectura: quien tiene acceso al edificio. Escritura: solo la API (service_role)
drop policy if exists clima_observaciones_select on public.clima_observaciones;
create policy clima_observaciones_select on public.clima_observaciones
for select to authenticated using (private.usuario_tiene_acceso_edificio(id_edificio));
drop policy if exists clima_previsiones_select on public.clima_previsiones;
create policy clima_previsiones_select on public.clima_previsiones
for select to authenticated using (private.usuario_tiene_acceso_edificio(id_edificio));
grant select on public.clima_observaciones, public.clima_previsiones to authenticated;
grant all on public.clima_observaciones, public.clima_previsiones, public.clima_consultas to service_role;

-- 2. Edificios cuya previsión ha caducado (o nunca se ha pedido)
create or replace function public.edificios_clima_pendientes()
returns table (id_edificio uuid, latitud numeric, longitud numeric, ultima_modificacion text)
language sql
stable
set search_path = ''
as $$
  select e.id, pg_catalog.round(e.latitud, 4), pg_catalog.round(e.longitud, 4), c.ultima_modificacion
  from public.edificios e
  left join public.clima_consultas c on c.id_edificio = e.id
  where e.activo and e.latitud is not null and e.longitud is not null
    and (c.expira_en is null or c.expira_en <= pg_catalog.now())
  order by c.actualizado_en nulls first;
$$;

-- 3. Guardar una respuesta. p_pasos: [{fecha_hora, horas, temperatura, temperatura_min, temperatura_max,
--    humedad, viento_ms, viento_direccion, nubosidad, precipitacion_mm, uv_cielo_despejado, simbolo}, …]
--    Sin p_pasos (respuesta 304 o error) solo actualiza la caducidad y el error.
create or replace function public.guardar_clima(
  p_id_edificio uuid,
  p_pasos jsonb,
  p_expira_en timestamptz,
  p_ultima_modificacion text default null,
  p_error text default null
)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_n integer := 0;
  v_emitida timestamptz := pg_catalog.now();
begin
  insert into public.clima_consultas as c (id_edificio, expira_en, ultima_modificacion, actualizado_en, ultimo_error, updated_at)
  values (p_id_edificio, coalesce(p_expira_en, pg_catalog.now() + interval '1 hour'), p_ultima_modificacion,
          case when p_pasos is not null then v_emitida end, p_error, pg_catalog.now())
  on conflict (id_edificio) do update
    set expira_en = excluded.expira_en,
        ultima_modificacion = coalesce(excluded.ultima_modificacion, c.ultima_modificacion),
        actualizado_en = coalesce(excluded.actualizado_en, c.actualizado_en),
        ultimo_error = excluded.ultimo_error,
        updated_at = pg_catalog.now();

  if p_pasos is null or pg_catalog.jsonb_array_length(p_pasos) = 0 then
    return 0;
  end if;

  -- Previsión: se sustituye entera
  delete from public.clima_previsiones where id_edificio = p_id_edificio;
  insert into public.clima_previsiones (id_edificio, fecha_hora, horas, temperatura, temperatura_min, temperatura_max, humedad,
                                        viento_ms, nubosidad, precipitacion_mm, uv_cielo_despejado, simbolo, emitida_en)
  select p_id_edificio, (x->>'fecha_hora')::timestamptz, coalesce((x->>'horas')::smallint, 1),
         (x->>'temperatura')::numeric, (x->>'temperatura_min')::numeric, (x->>'temperatura_max')::numeric,
         (x->>'humedad')::numeric, (x->>'viento_ms')::numeric, (x->>'nubosidad')::numeric,
         (x->>'precipitacion_mm')::numeric, (x->>'uv_cielo_despejado')::numeric, x->>'simbolo', v_emitida
  from pg_catalog.jsonb_array_elements(p_pasos) x
  on conflict (id_edificio, fecha_hora) do nothing;
  get diagnostics v_n = row_count;

  -- Observación: el paso de la hora en curso (o el primero si la previsión empieza después)
  insert into public.clima_observaciones as o (id_edificio, fecha_hora, temperatura, humedad, viento_ms, viento_direccion,
                                               nubosidad, precipitacion_mm, uv_cielo_despejado, simbolo)
  select p_id_edificio, pg_catalog.date_trunc('hour', (x->>'fecha_hora')::timestamptz),
         (x->>'temperatura')::numeric, (x->>'humedad')::numeric, (x->>'viento_ms')::numeric,
         (x->>'viento_direccion')::numeric, (x->>'nubosidad')::numeric, (x->>'precipitacion_mm')::numeric,
         (x->>'uv_cielo_despejado')::numeric, x->>'simbolo'
  from pg_catalog.jsonb_array_elements(p_pasos) x
  order by pg_catalog.abs(extract(epoch from (x->>'fecha_hora')::timestamptz - pg_catalog.date_trunc('hour', pg_catalog.now())))
  limit 1
  on conflict (id_edificio, fecha_hora) do update
    set temperatura = excluded.temperatura, humedad = excluded.humedad, viento_ms = excluded.viento_ms,
        viento_direccion = excluded.viento_direccion, nubosidad = excluded.nubosidad,
        precipitacion_mm = excluded.precipitacion_mm, uv_cielo_despejado = excluded.uv_cielo_despejado,
        simbolo = excluded.simbolo;

  return v_n;
end;
$$;

-- 4. Clima para la web: ahora (con prioridad a los sensores exteriores propios), próximas horas y días
create or replace function public.clima_edificio(p_id_edificio uuid)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_zona text;
  v_ahora jsonb;
  v_sensor_t record;
  v_sensor_h record;
  v_horas jsonb;
  v_dias jsonb;
  v_actualizado timestamptz;
begin
  select e.zona_horaria into v_zona from public.edificios e where e.id = p_id_edificio;
  if v_zona is null then
    raise exception 'Edificio inexistente o sin acceso';
  end if;

  -- Hora en curso: la previsión de esta hora o, si no hay, la última observación
  select pg_catalog.to_jsonb(x) into v_ahora from (
    select fecha_hora, temperatura, humedad, viento_ms, nubosidad, precipitacion_mm, uv_cielo_despejado, simbolo
    from public.clima_previsiones
    where id_edificio = p_id_edificio and horas = 1
      and fecha_hora >= pg_catalog.date_trunc('hour', pg_catalog.now()) - interval '1 hour'
    order by pg_catalog.abs(extract(epoch from fecha_hora - pg_catalog.date_trunc('hour', pg_catalog.now()))) limit 1) x;
  if v_ahora is null then
    select pg_catalog.to_jsonb(x) into v_ahora from (
      select fecha_hora, temperatura, humedad, viento_ms, nubosidad, precipitacion_mm, uv_cielo_despejado, simbolo
      from public.clima_observaciones where id_edificio = p_id_edificio
        and fecha_hora >= pg_catalog.now() - interval '6 hours'
      order by fecha_hora desc limit 1) x;
  end if;

  -- Sensores exteriores propios que comunican (recintos de tipo ZONA_EXTERIOR)
  select ec.ultimo_valor as valor, ec.ultima_lectura, s.id as id_sensor into v_sensor_t
  from public.sensores s
  join public.familias_sensor f on f.id = s.id_familia and f.codigo = 'TEMPERATURA'
  join public.recintos r on r.id = s.id_recinto and r.tipo = 'ZONA_EXTERIOR'
  join public.plantas p on p.id = r.id_planta and p.id_edificio = p_id_edificio
  join public.estado_comunicacion ec on ec.id_sensor = s.id and ec.estado = 'COMUNICANDO'
  where s.activo order by ec.ultima_lectura desc limit 1;
  select ec.ultimo_valor as valor, ec.ultima_lectura, s.id as id_sensor into v_sensor_h
  from public.sensores s
  join public.familias_sensor f on f.id = s.id_familia and f.codigo = 'HUMEDAD'
  join public.recintos r on r.id = s.id_recinto and r.tipo = 'ZONA_EXTERIOR'
  join public.plantas p on p.id = r.id_planta and p.id_edificio = p_id_edificio
  join public.estado_comunicacion ec on ec.id_sensor = s.id and ec.estado = 'COMUNICANDO'
  where s.activo order by ec.ultima_lectura desc limit 1;

  v_ahora := coalesce(v_ahora, '{}'::jsonb)
    || pg_catalog.jsonb_build_object(
         'fuente_temperatura', case when v_sensor_t.id_sensor is not null then 'SENSOR' when v_ahora ? 'temperatura' then 'MET_NORWAY' end,
         'fuente_humedad', case when v_sensor_h.id_sensor is not null then 'SENSOR' when v_ahora ? 'humedad' then 'MET_NORWAY' end,
         'id_sensor_temperatura', v_sensor_t.id_sensor, 'id_sensor_humedad', v_sensor_h.id_sensor);
  if v_sensor_t.id_sensor is not null then
    v_ahora := v_ahora || pg_catalog.jsonb_build_object('temperatura', round(v_sensor_t.valor::numeric, 1));
  end if;
  if v_sensor_h.id_sensor is not null then
    v_ahora := v_ahora || pg_catalog.jsonb_build_object('humedad', round(v_sensor_h.valor::numeric, 0));
  end if;

  -- Próximas 12 horas
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(x) order by x.fecha_hora), '[]'::jsonb) into v_horas from (
    select fecha_hora, temperatura, precipitacion_mm, simbolo
    from public.clima_previsiones
    where id_edificio = p_id_edificio and horas = 1 and fecha_hora > pg_catalog.now()
    order by fecha_hora limit 12) x;

  -- Próximos 3 días (en la hora local del edificio): mínima, máxima, lluvia y el símbolo de mediodía
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(d) order by d.fecha), '[]'::jsonb) into v_dias from (
    select (fecha_hora at time zone v_zona)::date as fecha,
           min(coalesce(temperatura_min, temperatura)) as temperatura_min,
           max(coalesce(temperatura_max, temperatura)) as temperatura_max,
           sum(precipitacion_mm) filter (where horas = 1 or horas = 6) as precipitacion_mm,
           (pg_catalog.array_agg(simbolo order by pg_catalog.abs(extract(hour from fecha_hora at time zone v_zona) - 12))
              filter (where simbolo is not null))[1] as simbolo
    from public.clima_previsiones
    where id_edificio = p_id_edificio
      and (fecha_hora at time zone v_zona)::date between (pg_catalog.now() at time zone v_zona)::date + 1
                                                    and (pg_catalog.now() at time zone v_zona)::date + 3
    group by 1) d;

  select c.actualizado_en into v_actualizado from public.clima_consultas c where c.id_edificio = p_id_edificio;
  if v_actualizado is null then
    select max(emitida_en) into v_actualizado from public.clima_previsiones where id_edificio = p_id_edificio;
  end if;

  return pg_catalog.jsonb_build_object(
    'ahora', case when v_ahora ? 'fecha_hora' or v_sensor_t.id_sensor is not null then v_ahora end,
    'horas', v_horas, 'dias', v_dias, 'actualizado', v_actualizado,
    'atribucion', 'Datos de MET Norway (api.met.no), licencia CC BY 4.0');
end;
$$;

revoke all on function public.edificios_clima_pendientes() from public, anon, authenticated;
revoke all on function public.guardar_clima(uuid, jsonb, timestamptz, text, text) from public, anon, authenticated;
revoke all on function public.clima_edificio(uuid) from public, anon;
grant execute on function public.edificios_clima_pendientes() to service_role;
grant execute on function public.guardar_clima(uuid, jsonb, timestamptz, text, text) to service_role;
grant execute on function public.clima_edificio(uuid) to authenticated, service_role;

commit;
