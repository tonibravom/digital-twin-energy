begin;

create or replace function private.edificio_de_recinto(p_id_recinto uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select p.id_edificio
  from public.recintos r
  join public.plantas p on p.id = r.id_planta
  where r.id = p_id_recinto;
$$;

create or replace function private.edificio_de_dispositivo(p_id_dispositivo uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select p.id_edificio
  from public.dispositivos d
  join public.recintos r on r.id = d.id_recinto
  join public.plantas p on p.id = r.id_planta
  where d.id = p_id_dispositivo;
$$;

create or replace function private.edificio_de_sensor(p_id_sensor uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select p.id_edificio
  from public.sensores s
  join public.recintos r on r.id = s.id_recinto
  join public.plantas p on p.id = r.id_planta
  where s.id = p_id_sensor;
$$;

create or replace function private.edificio_de_conexion(p_id_conexion uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select c.id_edificio
  from public.conexiones c
  where c.id = p_id_conexion;
$$;

revoke all on function private.edificio_de_recinto(uuid) from public, anon;
revoke all on function private.edificio_de_dispositivo(uuid) from public, anon;
revoke all on function private.edificio_de_sensor(uuid) from public, anon;
revoke all on function private.edificio_de_conexion(uuid) from public, anon;

grant execute on function private.edificio_de_recinto(uuid) to authenticated;
grant execute on function private.edificio_de_dispositivo(uuid) to authenticated;
grant execute on function private.edificio_de_sensor(uuid) to authenticated;
grant execute on function private.edificio_de_conexion(uuid) to authenticated;

alter table public.plantas enable row level security;
alter table public.recintos enable row level security;
alter table public.conexiones enable row level security;
alter table public.dispositivos enable row level security;
alter table public.sensores enable row level security;
alter table public.dispositivos_recintos_ambito enable row level security;
alter table public.sensores_recintos_ambito enable row level security;
alter table public.dispositivos_ubicaciones enable row level security;
alter table public.sensores_ubicaciones enable row level security;

-- PLANTAS
drop policy if exists plantas_select on public.plantas;
create policy plantas_select on public.plantas
for select to authenticated
using (private.usuario_tiene_acceso_edificio(id_edificio));

drop policy if exists plantas_insert on public.plantas;
create policy plantas_insert on public.plantas
for insert to authenticated
with check (private.usuario_puede_edificio(id_edificio, 'CREAR_PLANTA'));

drop policy if exists plantas_update on public.plantas;
create policy plantas_update on public.plantas
for update to authenticated
using (private.usuario_puede_edificio(id_edificio, 'MODIFICAR_PLANTA'))
with check (private.usuario_puede_edificio(id_edificio, 'MODIFICAR_PLANTA'));

-- RECINTOS
drop policy if exists recintos_select on public.recintos;
create policy recintos_select on public.recintos
for select to authenticated
using (
  private.usuario_tiene_acceso_edificio(
    private.edificio_de_recinto(id)
  )
);

drop policy if exists recintos_insert on public.recintos;
create policy recintos_insert on public.recintos
for insert to authenticated
with check (
  private.usuario_puede_edificio(
    (select p.id_edificio
     from public.plantas p
     where p.id = id_planta),
    'CREAR_RECINTO'
  )
);

drop policy if exists recintos_update on public.recintos;
create policy recintos_update on public.recintos
for update to authenticated
using (
  private.usuario_puede_edificio(
    private.edificio_de_recinto(id),
    'MODIFICAR_RECINTO'
  )
)
with check (
  private.usuario_puede_edificio(
    (select p.id_edificio
     from public.plantas p
     where p.id = id_planta),
    'MODIFICAR_RECINTO'
  )
);

-- CONEXIONES
drop policy if exists conexiones_select on public.conexiones;
create policy conexiones_select on public.conexiones
for select to authenticated
using (private.usuario_tiene_acceso_edificio(id_edificio));

drop policy if exists conexiones_insert on public.conexiones;
create policy conexiones_insert on public.conexiones
for insert to authenticated
with check (private.usuario_puede_edificio(id_edificio, 'CREAR_CONEXION'));

drop policy if exists conexiones_update on public.conexiones;
create policy conexiones_update on public.conexiones
for update to authenticated
using (private.usuario_puede_edificio(id_edificio, 'MODIFICAR_CONEXION'))
with check (private.usuario_puede_edificio(id_edificio, 'MODIFICAR_CONEXION'));

-- DISPOSITIVOS
drop policy if exists dispositivos_select on public.dispositivos;
create policy dispositivos_select on public.dispositivos
for select to authenticated
using (
  private.usuario_tiene_acceso_edificio(
    private.edificio_de_recinto(id_recinto)
  )
);

drop policy if exists dispositivos_insert on public.dispositivos;
create policy dispositivos_insert on public.dispositivos
for insert to authenticated
with check (
  private.usuario_puede_edificio(
    private.edificio_de_recinto(id_recinto),
    'CREAR_DISPOSITIVO'
  )
  and private.usuario_puede_edificio(
    private.edificio_de_conexion(id_conexion),
    'CREAR_DISPOSITIVO'
  )
);

drop policy if exists dispositivos_update on public.dispositivos;
create policy dispositivos_update on public.dispositivos
for update to authenticated
using (
  private.usuario_puede_edificio(
    private.edificio_de_recinto(id_recinto),
    'MODIFICAR_DISPOSITIVO'
  )
)
with check (
  private.usuario_puede_edificio(
    private.edificio_de_recinto(id_recinto),
    'MODIFICAR_DISPOSITIVO'
  )
  and private.usuario_puede_edificio(
    private.edificio_de_conexion(id_conexion),
    'MODIFICAR_DISPOSITIVO'
  )
);

-- SENSORES
drop policy if exists sensores_select on public.sensores;
create policy sensores_select on public.sensores
for select to authenticated
using (
  private.usuario_tiene_acceso_edificio(
    private.edificio_de_recinto(id_recinto)
  )
);

drop policy if exists sensores_insert on public.sensores;
create policy sensores_insert on public.sensores
for insert to authenticated
with check (
  private.usuario_puede_edificio(
    private.edificio_de_recinto(id_recinto),
    'CREAR_SENSOR'
  )
  and (
    (
      id_dispositivo is not null
      and private.usuario_puede_edificio(
        private.edificio_de_dispositivo(id_dispositivo),
        'CREAR_SENSOR'
      )
    )
    or
    (
      id_conexion is not null
      and private.usuario_puede_edificio(
        private.edificio_de_conexion(id_conexion),
        'CREAR_SENSOR'
      )
    )
  )
);

drop policy if exists sensores_update on public.sensores;
create policy sensores_update on public.sensores
for update to authenticated
using (
  private.usuario_puede_edificio(
    private.edificio_de_recinto(id_recinto),
    'MODIFICAR_SENSOR'
  )
)
with check (
  private.usuario_puede_edificio(
    private.edificio_de_recinto(id_recinto),
    'MODIFICAR_SENSOR'
  )
  and (
    (
      id_dispositivo is not null
      and private.usuario_puede_edificio(
        private.edificio_de_dispositivo(id_dispositivo),
        'MODIFICAR_SENSOR'
      )
    )
    or
    (
      id_conexion is not null
      and private.usuario_puede_edificio(
        private.edificio_de_conexion(id_conexion),
        'MODIFICAR_SENSOR'
      )
    )
  )
);

-- ÁMBITOS FUNCIONALES DE DISPOSITIVOS
drop policy if exists dispositivos_ambito_select
  on public.dispositivos_recintos_ambito;
create policy dispositivos_ambito_select
on public.dispositivos_recintos_ambito
for select to authenticated
using (
  private.usuario_tiene_acceso_edificio(
    private.edificio_de_dispositivo(id_dispositivo)
  )
);

drop policy if exists dispositivos_ambito_insert
  on public.dispositivos_recintos_ambito;
create policy dispositivos_ambito_insert
on public.dispositivos_recintos_ambito
for insert to authenticated
with check (
  private.usuario_puede_edificio(
    private.edificio_de_dispositivo(id_dispositivo),
    'MODIFICAR_DISPOSITIVO'
  )
  and private.usuario_puede_edificio(
    private.edificio_de_recinto(id_recinto),
    'MODIFICAR_DISPOSITIVO'
  )
);

drop policy if exists dispositivos_ambito_update
  on public.dispositivos_recintos_ambito;
create policy dispositivos_ambito_update
on public.dispositivos_recintos_ambito
for update to authenticated
using (
  private.usuario_puede_edificio(
    private.edificio_de_dispositivo(id_dispositivo),
    'MODIFICAR_DISPOSITIVO'
  )
)
with check (
  private.usuario_puede_edificio(
    private.edificio_de_dispositivo(id_dispositivo),
    'MODIFICAR_DISPOSITIVO'
  )
  and private.usuario_puede_edificio(
    private.edificio_de_recinto(id_recinto),
    'MODIFICAR_DISPOSITIVO'
  )
);

-- ÁMBITOS FUNCIONALES DE SENSORES
drop policy if exists sensores_ambito_select
  on public.sensores_recintos_ambito;
create policy sensores_ambito_select
on public.sensores_recintos_ambito
for select to authenticated
using (
  private.usuario_tiene_acceso_edificio(
    private.edificio_de_sensor(id_sensor)
  )
);

drop policy if exists sensores_ambito_insert
  on public.sensores_recintos_ambito;
create policy sensores_ambito_insert
on public.sensores_recintos_ambito
for insert to authenticated
with check (
  private.usuario_puede_edificio(
    private.edificio_de_sensor(id_sensor),
    'MODIFICAR_SENSOR'
  )
  and private.usuario_puede_edificio(
    private.edificio_de_recinto(id_recinto),
    'MODIFICAR_SENSOR'
  )
);

drop policy if exists sensores_ambito_update
  on public.sensores_recintos_ambito;
create policy sensores_ambito_update
on public.sensores_recintos_ambito
for update to authenticated
using (
  private.usuario_puede_edificio(
    private.edificio_de_sensor(id_sensor),
    'MODIFICAR_SENSOR'
  )
)
with check (
  private.usuario_puede_edificio(
    private.edificio_de_sensor(id_sensor),
    'MODIFICAR_SENSOR'
  )
  and private.usuario_puede_edificio(
    private.edificio_de_recinto(id_recinto),
    'MODIFICAR_SENSOR'
  )
);

-- HISTÓRICO DE UBICACIONES FÍSICAS: solo lectura directa.
drop policy if exists dispositivos_ubicaciones_select
  on public.dispositivos_ubicaciones;
create policy dispositivos_ubicaciones_select
on public.dispositivos_ubicaciones
for select to authenticated
using (
  private.usuario_tiene_acceso_edificio(
    private.edificio_de_dispositivo(id_dispositivo)
  )
);

drop policy if exists sensores_ubicaciones_select
  on public.sensores_ubicaciones;
create policy sensores_ubicaciones_select
on public.sensores_ubicaciones
for select to authenticated
using (
  private.usuario_tiene_acceso_edificio(
    private.edificio_de_sensor(id_sensor)
  )
);

-- CATÁLOGOS SaaS: lectura para cualquier usuario autenticado.
-- Su modificación queda reservada al backend (service_role).
do $$
declare
  t text;
begin
  foreach t in array array[
    'tipos_conexion', 'tipos_dispositivo', 'familias_sensor',
    'naturalezas_sensor', 'tratamientos_sensor', 'tipos_energia', 'flujos_energia'
  ] loop
    execute pg_catalog.format('drop policy if exists %I on public.%I', t || '_select', t);
    execute pg_catalog.format(
      'create policy %I on public.%I for select to authenticated using (true)',
      t || '_select', t);
  end loop;
end;
$$;

commit;