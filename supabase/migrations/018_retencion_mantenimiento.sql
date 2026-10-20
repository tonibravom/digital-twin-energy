begin;

-- =========================================================
-- RETENCIÓN Y MANTENIMIENTO DE DATOS
-- Regla (maestro §8): conservar lecturas brutas desde el 1 de
-- enero UTC del año actual menos cuatro años. En 2026 el límite
-- es 01/01/2022. Los valores calculados (valores_magnitud) se
-- conservan indefinidamente.
--
-- Como lecturas está particionada por mes, la retención elimina
-- particiones completas: es instantáneo y no genera bloat.
-- =========================================================

create or replace function public.limite_retencion_lecturas()
returns timestamptz
language sql
stable
set search_path = ''
as $$
  select (
    pg_catalog.date_trunc('year', pg_catalog.now() at time zone 'UTC')
    - interval '4 years'
  ) at time zone 'UTC';
$$;

create or replace function public.aplicar_retencion_lecturas()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_limite date := (public.limite_retencion_lecturas() at time zone 'UTC')::date;
  r record;
  v_eliminadas integer := 0;
begin
  if not pg_catalog.pg_try_advisory_xact_lock(1800182026) then
    raise notice 'La retención ya se está ejecutando';
    return 0;
  end if;

  for r in
    select c.relname
    from pg_catalog.pg_inherits i
    join pg_catalog.pg_class c on c.oid = i.inhrelid
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where i.inhparent = 'public.lecturas'::regclass
      and n.nspname = 'particiones'
      and c.relname ~ '^lecturas_[0-9]{4}_[0-9]{2}$'
      and pg_catalog.to_date(pg_catalog.substr(c.relname, 10), 'YYYY_MM') < v_limite
  loop
    execute pg_catalog.format('drop table particiones.%I', r.relname);
    v_eliminadas := v_eliminadas + 1;
  end loop;

  return v_eliminadas;
end;
$$;

comment on function public.aplicar_retencion_lecturas() is
  'Elimina las particiones de lecturas anteriores al 1 de enero UTC del año actual menos cuatro años. No toca valores_magnitud. Devuelve el número de particiones eliminadas.';

-- Tarea única de mantenimiento: crea particiones futuras y aplica retención.
create or replace function public.mantenimiento_datos()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ahora timestamp := pg_catalog.now() at time zone 'UTC';
  v_lect integer;
  v_val integer;
  v_ret integer;
begin
  v_lect := public.asegurar_particiones_lecturas(
    v_ahora::date, (v_ahora + interval '3 months')::date);
  v_val := public.asegurar_particiones_valores_magnitud(
    extract(year from v_ahora)::integer, extract(year from v_ahora)::integer + 1);
  v_ret := public.aplicar_retencion_lecturas();

  return pg_catalog.jsonb_build_object(
    'particiones_lecturas_creadas', v_lect,
    'particiones_valores_creadas', v_val,
    'particiones_lecturas_eliminadas', v_ret,
    'ejecutado', pg_catalog.now()
  );
end;
$$;

revoke all on function public.limite_retencion_lecturas() from public, anon;
revoke all on function public.aplicar_retencion_lecturas() from public, anon, authenticated;
revoke all on function public.mantenimiento_datos() from public, anon, authenticated;
grant execute on function public.aplicar_retencion_lecturas() to service_role;
grant execute on function public.mantenimiento_datos() to service_role;

commit;

-- =========================================================
-- PROGRAMACIÓN (fuera de la transacción)
-- En Supabase se usa pg_cron. Si la extensión no está
-- disponible, el backend debe llamar a mantenimiento_datos()
-- una vez al día con la service_role key.
-- =========================================================
do $$
begin
  begin
    create extension if not exists pg_cron;
  exception when others then
    raise notice 'pg_cron no disponible: programe mantenimiento_datos() desde el backend';
    return;
  end;

  perform cron.unschedule(jobid)
  from cron.job where jobname = 'mantenimiento_datos';

  perform cron.schedule(
    'mantenimiento_datos',
    '15 3 * * *',
    'select public.mantenimiento_datos()'
  );
end;
$$;
