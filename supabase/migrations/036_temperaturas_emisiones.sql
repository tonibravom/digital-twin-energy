-- =========================================================
-- 036 · Temperaturas de eficiencia y confort por temporada;
--       aporte y emisiones por fuente
-- Decisión D45 (03/11/2026):
--   · Por edificio y temporada se configuran la temperatura de
--     EFICIENCIA (en España, la del RITE: 19 °C en invierno y 27 °C en
--     verano) y la de CONFORT. Así la plataforma sirve para países con
--     otros límites. Sustituye a temperatura_confort (034).
--       invierno: T ≤ eficiencia verde · ≤ confort naranja · > confort rojo
--                 (eficiencia < confort)
--       verano:   T ≥ eficiencia verde · ≥ confort naranja · < confort rojo
--                 (confort < eficiencia)
--   · fuentes_hoy_edificio(): añade lo que aporta cada fuente a la
--     energía total (%) y sus emisiones (solo electricidad de la red y
--     gas; las renovables no emiten).
-- =========================================================
begin;

-- ---------------------------------------------------------
-- 1. Temperaturas por temporada
-- ---------------------------------------------------------
alter table public.edificios
  add column if not exists temp_eficiencia_invierno numeric(4,1) not null default 19,
  add column if not exists temp_confort_invierno numeric(4,1) not null default 25,
  add column if not exists temp_eficiencia_verano numeric(4,1) not null default 27,
  add column if not exists temp_confort_verano numeric(4,1) not null default 25;

-- Se conserva el confort que ya tuviera cada edificio (034)
do $$
begin
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'edificios' and column_name = 'temperatura_confort') then
    update public.edificios set temp_confort_invierno = temperatura_confort, temp_confort_verano = temperatura_confort;
  end if;
end;
$$;

alter table public.edificios drop constraint if exists edificios_confort_ck;
alter table public.edificios drop column if exists temperatura_confort;

alter table public.edificios drop constraint if exists edificios_temperaturas_ck;
alter table public.edificios add constraint edificios_temperaturas_ck check (
  temp_eficiencia_invierno < temp_confort_invierno
  and temp_confort_verano < temp_eficiencia_verano
  and temp_eficiencia_invierno between 10 and 30 and temp_confort_invierno between 10 and 30
  and temp_eficiencia_verano between 15 and 35 and temp_confort_verano between 15 and 35);

comment on column public.edificios.temp_eficiencia_invierno is
  'Temperatura máxima eficiente con calefacción (°C). En España, 19 °C (RITE). Debe ser menor que la de confort de invierno.';
comment on column public.edificios.temp_confort_invierno is 'Temperatura de confort en invierno (°C).';
comment on column public.edificios.temp_eficiencia_verano is
  'Temperatura mínima eficiente con refrigeración (°C). En España, 27 °C (RITE). Debe ser mayor que la de confort de verano.';
comment on column public.edificios.temp_confort_verano is 'Temperatura de confort en verano (°C).';

-- Color de la temperatura: ahora con la eficiencia y el confort de la temporada
drop function if exists public.estado_temperatura(numeric, text, numeric);
create or replace function public.estado_temperatura(p_valor numeric, p_temporada text, p_eficiencia numeric, p_confort numeric)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_valor is null or p_temporada is null then null
    when p_temporada = 'INVIERNO' then
      case when p_valor <= p_eficiencia then 'VERDE' when p_valor <= p_confort then 'NARANJA' else 'ROJO' end
    when p_temporada = 'VERANO' then
      case when p_valor >= p_eficiencia then 'VERDE' when p_valor >= p_confort then 'NARANJA' else 'ROJO' end
  end;
$$;

create or replace function public.ambiente_edificio(p_id_edificio uuid)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_edif record;
  v_temporada text;
  v_eficiencia numeric;
  v_confort numeric;
  v_res jsonb;
begin
  select e.id, e.zona_horaria, e.temp_eficiencia_invierno, e.temp_confort_invierno, e.temp_eficiencia_verano, e.temp_confort_verano
    into v_edif from public.edificios e where e.id = p_id_edificio;
  if v_edif.id is null then
    raise exception 'Edificio inexistente o sin acceso';
  end if;
  v_temporada := public.temporada_edificio(p_id_edificio, (pg_catalog.now() at time zone v_edif.zona_horaria)::date);
  v_eficiencia := case v_temporada when 'INVIERNO' then v_edif.temp_eficiencia_invierno when 'VERANO' then v_edif.temp_eficiencia_verano end;
  v_confort := case v_temporada when 'INVIERNO' then v_edif.temp_confort_invierno when 'VERANO' then v_edif.temp_confort_verano end;

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
    'temperatura_eficiencia', v_eficiencia,
    'temperatura_confort', v_confort,
    'recintos', coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id_recinto', id_recinto, 'recinto', recinto, 'planta', planta, 'nivel', nivel,
        'temperatura', case when hay_t then pg_catalog.jsonb_build_object(
            'valor', round(t::numeric, 1), 'ultima_lectura', t_fecha,
            'estado', public.estado_temperatura(round(t::numeric, 1), v_temporada, v_eficiencia, v_confort)) end,
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
-- 2. Fuentes de hoy: aporte (%) y emisiones de cada una
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
  fuentes(codigo, nombre, orden, factor) as (
    values ('ELECTRICIDAD', 'Electricidad de la red', 1, v_f_elec), ('GAS', 'Gas', 2, v_f_gas), ('RENOVABLE', 'Renovables', 3, 0::numeric)
  ),
  tabla as (
    select f.codigo, f.nombre, f.orden, f.factor,
      (exists (select 1 from mags m where (f.codigo = 'ELECTRICIDAD' and m.codigo = 'CONSUMO_ELECTRICIDAD')
                                       or (f.codigo = 'GAS' and m.codigo = 'CONSUMO_GAS')
                                       or (f.codigo = 'RENOVABLE' and m.codigo like 'GENERACION_%'))) as configurada,
      coalesce((select case f.codigo when 'ELECTRICIDAD' then electricidad when 'GAS' then gas else renovable end
                from sumas where dia = 'hoy'), 0) as hoy,
      (select case f.codigo when 'ELECTRICIDAD' then electricidad when 'GAS' then gas else renovable end
       from sumas where dia = 'comp') as comparable
    from fuentes f
  ),
  total as (select sum(hoy) as kwh, sum(hoy * factor) as kg from tabla where configurada)
  select pg_catalog.jsonb_build_object(
    'dia_comparable', v_comp,
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

revoke all on function public.estado_temperatura(numeric, text, numeric, numeric) from public, anon;
grant execute on function public.estado_temperatura(numeric, text, numeric, numeric) to authenticated, service_role;

commit;
