-- =========================================================
-- 043 · Temperatura por eficiencia y volúmenes de los recintos
-- Decisión D55 (12/11/2026, revisada 16/11/2026).
--
--   · Solo se muestra la EFICIENCIA: se quita la temperatura de confort
--     (la plataforma no actúa sobre la consigna) y no hay avisos de
--     demasiado frío o calor.
--   · Por edificio, temperatura de eficiencia (Te) de invierno entre 19 y
--     21 °C (por defecto 19) y de verano entre 25 y 27 °C (por defecto 26).
--   · Cinco tramos (colores en la web):
--       invierno  T ≤ Te EFICIENTE · ≤ Te+1 LEVE · ≤ Te+2,5 MODERADO · ≤ Te+4 ALTO · > Te+4 MUY_ALTO
--       verano    T ≥ Te EFICIENTE · ≥ Te−1 LEVE · ≥ Te−2,5 MODERADO · ≥ Te−4 ALTO · < Te−4 MUY_ALTO
--     Entretiempo: sin tramo (solo el valor).
--   · volumenes_sensor: volúmenes de habitaciones del GLB (los que conserva
--     herramientas/modelo3d) asignados a un sensor de temperatura; uno o
--     varios por sensor, y cada volumen a un solo sensor. El visor los
--     ilumina en la pestaña Ambiente con el color del tramo.
--   · ambiente_edificio() devuelve la Te de la temporada, el tramo de cada
--     recinto y los volúmenes con su tramo.
-- =========================================================
begin;

-- 1. Temperaturas de eficiencia: rangos nuevos y fuera la de confort
alter table public.edificios drop constraint if exists edificios_temperaturas_ck;
alter table public.edificios drop constraint if exists edificios_temp_eficiencia_ck;
update public.edificios
   set temp_eficiencia_invierno = least(greatest(temp_eficiencia_invierno, 19), 21),
       temp_eficiencia_verano = least(greatest(temp_eficiencia_verano, 25), 27)
 where temp_eficiencia_invierno not between 19 and 21 or temp_eficiencia_verano not between 25 and 27;
alter table public.edificios alter column temp_eficiencia_verano set default 26;
alter table public.edificios add constraint edificios_temp_eficiencia_ck check (
  temp_eficiencia_invierno between 19 and 21 and temp_eficiencia_verano between 25 and 27);
alter table public.edificios drop column if exists temp_confort_invierno;
alter table public.edificios drop column if exists temp_confort_verano;
comment on column public.edificios.temp_eficiencia_invierno is
  'Temperatura de eficiencia en invierno (Te, °C, de 19 a 21): por encima, la escala de colores sube en tramos de +1, +1,5, +1,5 y más de +4 °C.';
comment on column public.edificios.temp_eficiencia_verano is
  'Temperatura de eficiencia en verano (Te, °C, de 25 a 27): por debajo, la escala baja en tramos de −1, −1,5, −1,5 y más de −4 °C.';

-- 2. Tramo de una temperatura
drop function if exists public.estado_temperatura(numeric, text, numeric, numeric);
drop function if exists public.estado_temperatura(numeric, text, numeric);
create function public.estado_temperatura(p_valor numeric, p_temporada text, p_eficiencia numeric)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_valor is null or p_eficiencia is null or coalesce(p_temporada, '') not in ('INVIERNO', 'VERANO') then null
    when p_temporada = 'INVIERNO' then
      case when p_valor <= p_eficiencia then 'EFICIENTE'
           when p_valor <= p_eficiencia + 1 then 'LEVE'
           when p_valor <= p_eficiencia + 2.5 then 'MODERADO'
           when p_valor <= p_eficiencia + 4 then 'ALTO'
           else 'MUY_ALTO' end
    else
      case when p_valor >= p_eficiencia then 'EFICIENTE'
           when p_valor >= p_eficiencia - 1 then 'LEVE'
           when p_valor >= p_eficiencia - 2.5 then 'MODERADO'
           when p_valor >= p_eficiencia - 4 then 'ALTO'
           else 'MUY_ALTO' end
  end;
$$;

-- 3. Volúmenes de los recintos asignados a sensores de temperatura
create table if not exists public.volumenes_sensor (
  id uuid primary key default gen_random_uuid(),
  id_modelo_3d uuid not null references public.modelos_3d(id) on delete restrict,
  id_sensor uuid not null references public.sensores(id) on delete restrict,
  clave_volumen text not null,
  nombre_volumen text not null,
  nivel_modelo text,
  centro_x numeric(10,2),
  centro_z numeric(10,2),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint volumenes_sensor_volumen_uq unique (id_modelo_3d, clave_volumen)
);
alter table public.volumenes_sensor enable row level security;
create index if not exists ix_volumenes_sensor_sensor on public.volumenes_sensor(id_sensor);
comment on table public.volumenes_sensor is
  'Volúmenes de habitaciones del modelo 3D asignados a un sensor de temperatura (D55). Un sensor puede tener varios; cada volumen, un solo sensor. nombre, nivel y centro sirven para reencontrarlos al sustituir el GLB.';

create or replace function public.validar_volumen_sensor()
returns trigger
language plpgsql
security definer   -- comprueba sensor y modelo aunque RLS los oculte; el permiso lo decide RLS
set search_path = ''
as $$
declare
  v_modelo public.modelos_3d%rowtype;
  v_recinto uuid;
  v_familia text;
begin
  select * into v_modelo from public.modelos_3d where id = new.id_modelo_3d;
  select s.id_recinto, f.codigo into v_recinto, v_familia
  from public.sensores s join public.familias_sensor f on f.id = s.id_familia
  where s.id = new.id_sensor and s.activo;
  if v_modelo.id is null or v_recinto is null then
    raise exception 'El modelo o el sensor no existen' using errcode = 'check_violation';
  end if;
  if v_familia <> 'TEMPERATURA' then
    raise exception 'Solo los sensores de temperatura tienen volúmenes' using errcode = 'check_violation';
  end if;
  if public.obtener_edificio_recinto(v_recinto) is distinct from v_modelo.id_edificio
     or (v_modelo.tipo_modelo = 'RECINTO' and v_recinto is distinct from v_modelo.id_recinto) then
    raise exception 'El sensor debe ser del edificio (o del recinto) del modelo 3D' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_volumenes_sensor_validar on public.volumenes_sensor;
create trigger trg_volumenes_sensor_validar
before insert or update of id_modelo_3d, id_sensor on public.volumenes_sensor
for each row execute function public.validar_volumen_sensor();

drop trigger if exists trg_volumenes_sensor_updated_at on public.volumenes_sensor;
create trigger trg_volumenes_sensor_updated_at
before update on public.volumenes_sensor
for each row execute function public.set_updated_at();

drop trigger if exists trg_auditoria on public.volumenes_sensor;
create trigger trg_auditoria after insert or update or delete on public.volumenes_sensor
for each row execute function public.auditar_cambio();

-- Mismos permisos que las etiquetas (ubicaciones_3d)
drop policy if exists volumenes_sensor_select on public.volumenes_sensor;
create policy volumenes_sensor_select on public.volumenes_sensor
for select to authenticated
using (private.usuario_tiene_acceso_edificio(private.edificio_de_modelo_3d(id_modelo_3d))
       and private.usuario_tiene_permiso('VER_3D'));

drop policy if exists volumenes_sensor_insert on public.volumenes_sensor;
create policy volumenes_sensor_insert on public.volumenes_sensor
for insert to authenticated
with check (private.usuario_puede_edificio(private.edificio_de_modelo_3d(id_modelo_3d), 'MODIFICAR_UBICACION_3D'));

drop policy if exists volumenes_sensor_update on public.volumenes_sensor;
create policy volumenes_sensor_update on public.volumenes_sensor
for update to authenticated
using (private.usuario_puede_edificio(private.edificio_de_modelo_3d(id_modelo_3d), 'MODIFICAR_UBICACION_3D'))
with check (private.usuario_puede_edificio(private.edificio_de_modelo_3d(id_modelo_3d), 'MODIFICAR_UBICACION_3D'));

drop policy if exists volumenes_sensor_delete on public.volumenes_sensor;
create policy volumenes_sensor_delete on public.volumenes_sensor
for delete to authenticated
using (private.usuario_puede_edificio(private.edificio_de_modelo_3d(id_modelo_3d), 'ELIMINAR_UBICACION_3D'));

grant select, insert, update, delete on public.volumenes_sensor to authenticated;
grant all on public.volumenes_sensor to service_role;

-- 4. Ambiente: Te de la temporada, tramo de cada recinto y volúmenes con su tramo
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
  v_res jsonb;
  v_volumenes jsonb;
begin
  select e.id, e.zona_horaria, e.temp_eficiencia_invierno, e.temp_eficiencia_verano
    into v_edif from public.edificios e where e.id = p_id_edificio;
  if v_edif.id is null then
    raise exception 'Edificio inexistente o sin acceso';
  end if;
  v_temporada := public.temporada_edificio(p_id_edificio, (pg_catalog.now() at time zone v_edif.zona_horaria)::date);
  v_eficiencia := case v_temporada when 'INVIERNO' then v_edif.temp_eficiencia_invierno
                                   when 'VERANO' then v_edif.temp_eficiencia_verano end;

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
    'recintos', coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id_recinto', id_recinto, 'recinto', recinto, 'planta', planta, 'nivel', nivel,
        'temperatura', case when hay_t then pg_catalog.jsonb_build_object(
            'valor', round(t::numeric, 1), 'ultima_lectura', t_fecha,
            'estado', public.estado_temperatura(round(t::numeric, 1), v_temporada, v_eficiencia)) end,
        'humedad', case when hay_h then pg_catalog.jsonb_build_object(
            'valor', round(h::numeric, 0), 'ultima_lectura', h_fecha,
            'estado', public.estado_humedad(round(h::numeric, 0))) end,
        'co2', case when hay_c then pg_catalog.jsonb_build_object(
            'valor', round(c::numeric, 0), 'ultima_lectura', c_fecha) end)
      order by nivel, recinto), '[]'::jsonb))
  into v_res
  from por_recinto;

  -- Volúmenes del modelo activo del edificio con el tramo de su sensor (sin datos: estado nulo)
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
           'clave', vs.clave_volumen, 'nombre', vs.nombre_volumen, 'id_sensor', vs.id_sensor,
           'id_recinto', s.id_recinto,
           'valor', round(ec.ultimo_valor::numeric, 1),
           'estado', case when ec.estado = 'COMUNICANDO'
                          then public.estado_temperatura(round(ec.ultimo_valor::numeric, 1), v_temporada, v_eficiencia) end)
         order by vs.clave_volumen), '[]'::jsonb)
    into v_volumenes
  from public.volumenes_sensor vs
  join public.modelos_3d m on m.id = vs.id_modelo_3d and m.activo and m.tipo_modelo = 'EDIFICIO' and m.id_edificio = p_id_edificio
  join public.sensores s on s.id = vs.id_sensor and s.activo
  left join public.estado_comunicacion ec on ec.id_sensor = s.id;

  return v_res || pg_catalog.jsonb_build_object('volumenes', v_volumenes);
end;
$$;

revoke all on function public.estado_temperatura(numeric, text, numeric) from public, anon;
revoke all on function public.validar_volumen_sensor() from public, anon;
revoke all on function public.ambiente_edificio(uuid) from public, anon;
grant execute on function public.estado_temperatura(numeric, text, numeric) to authenticated, service_role;
grant execute on function public.ambiente_edificio(uuid) to authenticated, service_role;

commit;
