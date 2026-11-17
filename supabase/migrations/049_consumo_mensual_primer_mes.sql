-- =========================================================
-- 049 · Consumo mensual: mes en que el contador empieza a medir
-- Decisión D57 (17/11/2026).
--
--   consumo_mensual_suministro() dejaba vacío el mes en que el contador
--   empieza a enviar datos (no hay lectura antes del cambio de mes). Ahora
--   ese mes se calcula desde su primera lectura (consumo parcial del mes).
-- =========================================================
begin;

create or replace function public.consumo_mensual_suministro(p_id_suministro uuid)
returns table (anio integer, mes integer, consumo double precision, unidad varchar, consumo_kwh double precision)
language plpgsql
stable
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
  where su.id = p_id_suministro;
  if v_tipo is null then
    return;   -- inexistente o sin acceso (RLS)
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

revoke all on function public.consumo_mensual_suministro(uuid) from public, anon;
grant execute on function public.consumo_mensual_suministro(uuid) to authenticated, service_role;

commit;
