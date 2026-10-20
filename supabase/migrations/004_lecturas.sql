begin;

-- =========================================================
-- LECTURAS BRUTAS
-- Tabla particionada por mes (UTC). Diseño medido: ~117 bytes
-- por lectura incluyendo índice, frente a ~354 del diseño
-- anterior. La naturaleza de la lectura (instantánea,
-- acumulativa, estado, contaje) la define el sensor, no se
-- repite en cada fila.
--
-- Las particiones se crean en el esquema "particiones", que no
-- se expone en la API de Supabase. El acceso se hace siempre a
-- través de public.lecturas, que aplica RLS.
-- =========================================================

create schema if not exists particiones;
revoke all on schema particiones from public, anon, authenticated;

create table if not exists public.lecturas (
  id_sensor uuid not null references public.sensores(id) on delete restrict,
  fecha_hora timestamptz not null,
  valor double precision not null,
  calidad smallint not null default 0,
  created_at timestamptz not null default now(),
  constraint lecturas_pk primary key (id_sensor, fecha_hora),
  constraint lecturas_calidad_ck check (calidad in (0, 1, 2))
) partition by range (fecha_hora);

alter table public.lecturas enable row level security;

comment on table public.lecturas is
  'Lecturas brutas de sensores, particionadas por mes UTC. Clave de deduplicación: sensor + instante. Retención: migración 018.';
comment on column public.lecturas.fecha_hora is
  'Instante de la lectura (timestamptz, almacenado en UTC). La interfaz muestra la zona horaria del edificio.';
comment on column public.lecturas.calidad is
  '0 = VALIDA, 1 = ESTIMADA, 2 = CORREGIDA.';
comment on column public.lecturas.created_at is
  'Momento de la ingesta. Permite procesamiento incremental del motor.';

-- ---------------------------------------------------------
-- Crea las particiones mensuales que falten entre dos fechas.
-- Idempotente. La invoca la tarea programada (018) y el backend
-- antes de importar históricos.
-- ---------------------------------------------------------
create or replace function public.asegurar_particiones_lecturas(
  p_desde date,
  p_hasta date
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_mes date;
  v_nombre text;
  v_creadas integer := 0;
begin
  if p_desde is null or p_hasta is null or p_hasta < p_desde then
    raise exception 'Rango de fechas no válido';
  end if;

  if p_hasta > p_desde + interval '15 years' then
    raise exception 'Rango demasiado amplio (máximo 15 años)';
  end if;

  v_mes := pg_catalog.date_trunc('month', p_desde)::date;

  while v_mes <= p_hasta loop
    v_nombre := 'lecturas_' || pg_catalog.to_char(v_mes, 'YYYY_MM');

    if not exists (
      select 1
      from pg_catalog.pg_class c
      join pg_catalog.pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'particiones' and c.relname = v_nombre
    ) then
      execute pg_catalog.format(
        'create table particiones.%I partition of public.lecturas
           for values from (%L) to (%L)',
        v_nombre,
        v_mes::text || ' 00:00:00+00',
        (v_mes + interval '1 month')::date::text || ' 00:00:00+00'
      );
      execute pg_catalog.format(
        'alter table particiones.%I enable row level security', v_nombre
      );
      v_creadas := v_creadas + 1;
    end if;

    v_mes := (v_mes + interval '1 month')::date;
  end loop;

  return v_creadas;
end;
$$;

revoke all on function public.asegurar_particiones_lecturas(date, date)
  from public, anon, authenticated;
grant execute on function public.asegurar_particiones_lecturas(date, date)
  to service_role;

-- Particiones iniciales: desde el límite de retención hasta 3 meses vista.
select public.asegurar_particiones_lecturas(
  (pg_catalog.date_trunc('year', pg_catalog.now() at time zone 'UTC')
     - interval '4 years')::date,
  ((pg_catalog.now() at time zone 'UTC') + interval '3 months')::date
);

commit;
