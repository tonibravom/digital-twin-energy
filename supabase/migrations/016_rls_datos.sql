begin;

-- Funciones auxiliares para resolver el edificio de una magnitud o modelo.
create or replace function private.edificio_de_magnitud(p_id_magnitud_edificio uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select me.id_edificio
  from public.magnitudes_edificio me
  where me.id = p_id_magnitud_edificio;
$$;

create or replace function private.edificio_de_modelo_3d(p_id_modelo uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select m.id_edificio from public.modelos_3d m where m.id = p_id_modelo;
$$;

create or replace function private.magnitudes_accesibles()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select me.id
  from public.magnitudes_edificio me
  where me.id_edificio in (select private.edificios_accesibles());
$$;

revoke all on function private.magnitudes_accesibles() from public, anon;
grant execute on function private.magnitudes_accesibles() to authenticated;

revoke all on function private.edificio_de_magnitud(uuid) from public, anon;
revoke all on function private.edificio_de_modelo_3d(uuid) from public, anon;
grant execute on function private.edificio_de_magnitud(uuid) to authenticated;
grant execute on function private.edificio_de_modelo_3d(uuid) to authenticated;

-- Activación de RLS.
alter table public.lecturas enable row level security;
alter table public.magnitudes enable row level security;
alter table public.magnitudes_edificio enable row level security;
alter table public.magnitudes_fuentes enable row level security;
alter table public.valores_magnitud enable row level security;

alter table public.suministros enable row level security;
alter table public.suministros_electricidad enable row level security;
alter table public.suministros_gas enable row level security;
alter table public.suministros_agua enable row level security;
alter table public.suministros_agua_incendios enable row level security;
alter table public.suministros_generacion enable row level security;
alter table public.suministros_dispositivos enable row level security;

alter table public.modelos_3d enable row level security;
alter table public.ubicaciones_3d enable row level security;

alter table public.calendario_edificio enable row level security;
alter table public.modalidades_edificio enable row level security;
alter table public.complementos_edificio enable row level security;
alter table public.parametros_saas enable row level security;

alter table public.estado_comunicacion enable row level security;
alter table public.incidencias_comunicacion enable row level security;

alter table public.niveles_alarma enable row level security;
alter table public.reglas_alarma enable row level security;
alter table public.reglas_alarma_recintos enable row level security;
alter table public.reglas_alarma_usuarios enable row level security;
alter table public.eventos_alarma enable row level security;
alter table public.notificaciones enable row level security;

alter table public.auditoria enable row level security;

-- LECTURAS: consulta solamente. La ingesta se ejecutará mediante backend seguro.
drop policy if exists lecturas_select on public.lecturas;
create policy lecturas_select on public.lecturas
for select to authenticated
using (
  (select private.usuario_tiene_permiso('VER_LECTURAS'))
  and id_sensor in (select private.sensores_accesibles())
);

-- Catálogo SaaS de magnitudes: lectura para usuarios autenticados.
drop policy if exists magnitudes_select on public.magnitudes;
create policy magnitudes_select on public.magnitudes
for select to authenticated
using (activa and private.usuario_tiene_permiso('VER_MAGNITUDES'));

drop policy if exists magnitudes_edificio_select on public.magnitudes_edificio;
create policy magnitudes_edificio_select on public.magnitudes_edificio
for select to authenticated
using (
  private.usuario_tiene_acceso_edificio(id_edificio)
  and private.usuario_tiene_permiso('VER_MAGNITUDES')
);

drop policy if exists magnitudes_edificio_insert on public.magnitudes_edificio;
create policy magnitudes_edificio_insert on public.magnitudes_edificio
for insert to authenticated
with check (
  private.usuario_puede_edificio(id_edificio, 'MODIFICAR_MAGNITUDES')
);

drop policy if exists magnitudes_edificio_update on public.magnitudes_edificio;
create policy magnitudes_edificio_update on public.magnitudes_edificio
for update to authenticated
using (
  private.usuario_puede_edificio(id_edificio, 'MODIFICAR_MAGNITUDES')
)
with check (
  private.usuario_puede_edificio(id_edificio, 'MODIFICAR_MAGNITUDES')
);

drop policy if exists magnitudes_fuentes_select on public.magnitudes_fuentes;
create policy magnitudes_fuentes_select on public.magnitudes_fuentes
for select to authenticated
using (
  private.usuario_tiene_acceso_edificio(
    private.edificio_de_magnitud(id_magnitud_edificio)
  )
  and private.usuario_tiene_permiso('VER_MAGNITUDES')
);

drop policy if exists magnitudes_fuentes_insert on public.magnitudes_fuentes;
create policy magnitudes_fuentes_insert on public.magnitudes_fuentes
for insert to authenticated
with check (
  private.usuario_puede_edificio(
    private.edificio_de_magnitud(id_magnitud_edificio),
    'MODIFICAR_MAGNITUDES'
  )
  and (
    id_sensor is null
    or private.usuario_tiene_acceso_edificio(
      private.edificio_de_sensor(id_sensor)
    )
  )
  and (
    id_magnitud_origen is null
    or private.usuario_tiene_acceso_edificio(
      private.edificio_de_magnitud(id_magnitud_origen)
    )
  )
);

drop policy if exists magnitudes_fuentes_update on public.magnitudes_fuentes;
create policy magnitudes_fuentes_update on public.magnitudes_fuentes
for update to authenticated
using (
  private.usuario_puede_edificio(
    private.edificio_de_magnitud(id_magnitud_edificio),
    'MODIFICAR_MAGNITUDES'
  )
)
with check (
  private.usuario_puede_edificio(
    private.edificio_de_magnitud(id_magnitud_edificio),
    'MODIFICAR_MAGNITUDES'
  )
  and (
    id_sensor is null
    or private.usuario_tiene_acceso_edificio(
      private.edificio_de_sensor(id_sensor)
    )
  )
  and (
    id_magnitud_origen is null
    or private.usuario_tiene_acceso_edificio(
      private.edificio_de_magnitud(id_magnitud_origen)
    )
  )
);

drop policy if exists valores_magnitud_select on public.valores_magnitud;
create policy valores_magnitud_select on public.valores_magnitud
for select to authenticated
using (
  (select private.usuario_tiene_permiso('VER_MAGNITUDES'))
  and id_magnitud_edificio in (select private.magnitudes_accesibles())
);

-- SUMINISTROS
drop policy if exists suministros_select on public.suministros;
create policy suministros_select on public.suministros
for select to authenticated
using (
  private.usuario_tiene_acceso_edificio(id_edificio)
  and private.usuario_tiene_permiso('VER_SUMINISTRO')
);

drop policy if exists suministros_insert on public.suministros;
create policy suministros_insert on public.suministros
for insert to authenticated
with check (
  private.usuario_puede_edificio(id_edificio, 'CREAR_SUMINISTRO')
);

drop policy if exists suministros_update on public.suministros;
create policy suministros_update on public.suministros
for update to authenticated
using (
  private.usuario_puede_edificio(id_edificio, 'MODIFICAR_SUMINISTRO')
)
with check (
  private.usuario_puede_edificio(id_edificio, 'MODIFICAR_SUMINISTRO')
);

-- Políticas comunes para tablas específicas de suministros.
drop policy if exists suministro_electricidad_select on public.suministros_electricidad;
create policy suministro_electricidad_select on public.suministros_electricidad
for select to authenticated
using (
  exists (
    select 1 from public.suministros s
    where s.id = id_suministro
      and private.usuario_tiene_acceso_edificio(s.id_edificio)
      and private.usuario_tiene_permiso('VER_SUMINISTRO')
  )
);

drop policy if exists suministro_electricidad_insert on public.suministros_electricidad;
create policy suministro_electricidad_insert on public.suministros_electricidad
for insert to authenticated
with check (
  exists (
    select 1 from public.suministros s
    where s.id = id_suministro
      and private.usuario_puede_edificio(s.id_edificio, 'CREAR_SUMINISTRO')
      and s.tipo = 'ELECTRICIDAD'
  )
);

drop policy if exists suministro_electricidad_update on public.suministros_electricidad;
create policy suministro_electricidad_update on public.suministros_electricidad
for update to authenticated
using (
  exists (
    select 1 from public.suministros s
    where s.id = id_suministro
      and private.usuario_puede_edificio(s.id_edificio, 'MODIFICAR_SUMINISTRO')
      and s.tipo = 'ELECTRICIDAD'
  )
)
with check (
  exists (
    select 1 from public.suministros s
    where s.id = id_suministro
      and private.usuario_puede_edificio(s.id_edificio, 'MODIFICAR_SUMINISTRO')
      and s.tipo = 'ELECTRICIDAD'
  )
);

drop policy if exists suministro_gas_select on public.suministros_gas;
create policy suministro_gas_select on public.suministros_gas
for select to authenticated
using (
  exists (select 1 from public.suministros s
    where s.id = id_suministro
      and private.usuario_tiene_acceso_edificio(s.id_edificio)
      and private.usuario_tiene_permiso('VER_SUMINISTRO'))
);

drop policy if exists suministro_gas_insert on public.suministros_gas;
create policy suministro_gas_insert on public.suministros_gas
for insert to authenticated
with check (
  exists (select 1 from public.suministros s
    where s.id = id_suministro
      and s.tipo = 'GAS'
      and private.usuario_puede_edificio(s.id_edificio, 'CREAR_SUMINISTRO'))
);

drop policy if exists suministro_gas_update on public.suministros_gas;
create policy suministro_gas_update on public.suministros_gas
for update to authenticated
using (
  exists (select 1 from public.suministros s
    where s.id = id_suministro
      and s.tipo = 'GAS'
      and private.usuario_puede_edificio(s.id_edificio, 'MODIFICAR_SUMINISTRO'))
)
with check (
  exists (select 1 from public.suministros s
    where s.id = id_suministro
      and s.tipo = 'GAS'
      and private.usuario_puede_edificio(s.id_edificio, 'MODIFICAR_SUMINISTRO'))
);

drop policy if exists suministro_agua_select on public.suministros_agua;
create policy suministro_agua_select on public.suministros_agua
for select to authenticated
using (
  exists (select 1 from public.suministros s
    where s.id = id_suministro
      and private.usuario_tiene_acceso_edificio(s.id_edificio)
      and private.usuario_tiene_permiso('VER_SUMINISTRO'))
);

drop policy if exists suministro_agua_insert on public.suministros_agua;
create policy suministro_agua_insert on public.suministros_agua
for insert to authenticated
with check (
  exists (select 1 from public.suministros s
    where s.id = id_suministro
      and s.tipo = 'AGUA'
      and private.usuario_puede_edificio(s.id_edificio, 'CREAR_SUMINISTRO'))
);

drop policy if exists suministro_agua_update on public.suministros_agua;
create policy suministro_agua_update on public.suministros_agua
for update to authenticated
using (
  exists (select 1 from public.suministros s
    where s.id = id_suministro
      and s.tipo = 'AGUA'
      and private.usuario_puede_edificio(s.id_edificio, 'MODIFICAR_SUMINISTRO'))
)
with check (
  exists (select 1 from public.suministros s
    where s.id = id_suministro
      and s.tipo = 'AGUA'
      and private.usuario_puede_edificio(s.id_edificio, 'MODIFICAR_SUMINISTRO'))
);

drop policy if exists suministro_agua_incendios_select on public.suministros_agua_incendios;
create policy suministro_agua_incendios_select on public.suministros_agua_incendios
for select to authenticated
using (
  exists (select 1 from public.suministros s
    where s.id = id_suministro
      and private.usuario_tiene_acceso_edificio(s.id_edificio)
      and private.usuario_tiene_permiso('VER_SUMINISTRO'))
);

drop policy if exists suministro_agua_incendios_insert on public.suministros_agua_incendios;
create policy suministro_agua_incendios_insert on public.suministros_agua_incendios
for insert to authenticated
with check (
  exists (select 1 from public.suministros s
    where s.id = id_suministro
      and s.tipo = 'AGUA_INCENDIOS'
      and private.usuario_puede_edificio(s.id_edificio, 'CREAR_SUMINISTRO'))
);

drop policy if exists suministro_agua_incendios_update on public.suministros_agua_incendios;
create policy suministro_agua_incendios_update on public.suministros_agua_incendios
for update to authenticated
using (
  exists (select 1 from public.suministros s
    where s.id = id_suministro
      and s.tipo = 'AGUA_INCENDIOS'
      and private.usuario_puede_edificio(s.id_edificio, 'MODIFICAR_SUMINISTRO'))
)
with check (
  exists (select 1 from public.suministros s
    where s.id = id_suministro
      and s.tipo = 'AGUA_INCENDIOS'
      and private.usuario_puede_edificio(s.id_edificio, 'MODIFICAR_SUMINISTRO'))
);

drop policy if exists suministro_generacion_select on public.suministros_generacion;
create policy suministro_generacion_select on public.suministros_generacion
for select to authenticated
using (
  exists (select 1 from public.suministros s
    where s.id = id_suministro
      and private.usuario_tiene_acceso_edificio(s.id_edificio)
      and private.usuario_tiene_permiso('VER_SUMINISTRO'))
);

drop policy if exists suministro_generacion_insert on public.suministros_generacion;
create policy suministro_generacion_insert on public.suministros_generacion
for insert to authenticated
with check (
  exists (select 1 from public.suministros s
    where s.id = id_suministro
      and s.tipo = 'GENERACION'
      and private.usuario_puede_edificio(s.id_edificio, 'CREAR_SUMINISTRO'))
);

drop policy if exists suministro_generacion_update on public.suministros_generacion;
create policy suministro_generacion_update on public.suministros_generacion
for update to authenticated
using (
  exists (select 1 from public.suministros s
    where s.id = id_suministro
      and s.tipo = 'GENERACION'
      and private.usuario_puede_edificio(s.id_edificio, 'MODIFICAR_SUMINISTRO'))
)
with check (
  exists (select 1 from public.suministros s
    where s.id = id_suministro
      and s.tipo = 'GENERACION'
      and private.usuario_puede_edificio(s.id_edificio, 'MODIFICAR_SUMINISTRO'))
);

-- ASOCIACIÓN SUMINISTRO-DISPOSITIVO
drop policy if exists suministro_dispositivos_select on public.suministros_dispositivos;
create policy suministro_dispositivos_select on public.suministros_dispositivos
for select to authenticated
using (
  exists (select 1 from public.suministros s
    where s.id = id_suministro
      and private.usuario_tiene_acceso_edificio(s.id_edificio)
      and private.usuario_tiene_permiso('VER_SUMINISTRO'))
);

drop policy if exists suministro_dispositivos_insert on public.suministros_dispositivos;
create policy suministro_dispositivos_insert on public.suministros_dispositivos
for insert to authenticated
with check (
  exists (
    select 1
    from public.suministros s
    where s.id = id_suministro
      and private.usuario_puede_edificio(s.id_edificio, 'ASIGNAR_DISPOSITIVO_SUMINISTRO')
  )
  and private.usuario_puede_edificio(
    private.edificio_de_dispositivo(id_dispositivo),
    'ASIGNAR_DISPOSITIVO_SUMINISTRO'
  )
);

drop policy if exists suministro_dispositivos_update on public.suministros_dispositivos;
create policy suministro_dispositivos_update on public.suministros_dispositivos
for update to authenticated
using (
  exists (select 1 from public.suministros s
    where s.id = id_suministro
      and private.usuario_puede_edificio(s.id_edificio, 'ASIGNAR_DISPOSITIVO_SUMINISTRO'))
)
with check (
  exists (select 1 from public.suministros s
    where s.id = id_suministro
      and private.usuario_puede_edificio(s.id_edificio, 'ASIGNAR_DISPOSITIVO_SUMINISTRO'))
  and private.usuario_puede_edificio(
    private.edificio_de_dispositivo(id_dispositivo),
    'ASIGNAR_DISPOSITIVO_SUMINISTRO'
  )
);

-- MODELOS 3D
drop policy if exists modelos_3d_select on public.modelos_3d;
create policy modelos_3d_select on public.modelos_3d
for select to authenticated
using (
  private.usuario_tiene_acceso_edificio(
    id_edificio
  )
  and private.usuario_tiene_permiso('VER_MODELOS_3D')
);

drop policy if exists modelos_3d_insert on public.modelos_3d;
create policy modelos_3d_insert on public.modelos_3d
for insert to authenticated
with check (
  private.usuario_puede_edificio(
    id_edificio,
    'CARGAR_MODELO_3D'
  )
);

drop policy if exists modelos_3d_update on public.modelos_3d;
create policy modelos_3d_update on public.modelos_3d
for update to authenticated
using (
  private.usuario_puede_edificio(
    id_edificio,
    'SUSTITUIR_MODELO_3D'
  )
)
with check (
  private.usuario_puede_edificio(
    id_edificio,
    'SUSTITUIR_MODELO_3D'
  )
);

drop policy if exists ubicaciones_3d_select on public.ubicaciones_3d;
create policy ubicaciones_3d_select on public.ubicaciones_3d
for select to authenticated
using (
  private.usuario_tiene_acceso_edificio(
    private.edificio_de_modelo_3d(id_modelo_3d)
  )
  and private.usuario_tiene_permiso('VER_3D')
);

drop policy if exists ubicaciones_3d_insert on public.ubicaciones_3d;
create policy ubicaciones_3d_insert on public.ubicaciones_3d
for insert to authenticated
with check (
  private.usuario_puede_edificio(
    private.edificio_de_modelo_3d(id_modelo_3d),
    'MODIFICAR_UBICACION_3D'
  )
);

drop policy if exists ubicaciones_3d_update on public.ubicaciones_3d;
create policy ubicaciones_3d_update on public.ubicaciones_3d
for update to authenticated
using (
  private.usuario_puede_edificio(
    private.edificio_de_modelo_3d(id_modelo_3d),
    'MODIFICAR_UBICACION_3D'
  )
)
with check (
  private.usuario_puede_edificio(
    private.edificio_de_modelo_3d(id_modelo_3d),
    'MODIFICAR_UBICACION_3D'
  )
);

drop policy if exists ubicaciones_3d_delete on public.ubicaciones_3d;
create policy ubicaciones_3d_delete on public.ubicaciones_3d
for delete to authenticated
using (
  private.usuario_puede_edificio(
    private.edificio_de_modelo_3d(id_modelo_3d),
    'ELIMINAR_UBICACION_3D'
  )
);

-- CALENDARIO, MODALIDAD Y COMPLEMENTOS
drop policy if exists calendario_edificio_select on public.calendario_edificio;
create policy calendario_edificio_select on public.calendario_edificio
for select to authenticated
using (private.usuario_tiene_acceso_edificio(id_edificio));

drop policy if exists calendario_edificio_insert on public.calendario_edificio;
create policy calendario_edificio_insert on public.calendario_edificio
for insert to authenticated
with check (private.usuario_puede_edificio(id_edificio, 'MODIFICAR_CALENDARIO'));

drop policy if exists calendario_edificio_update on public.calendario_edificio;
create policy calendario_edificio_update on public.calendario_edificio
for update to authenticated
using (private.usuario_puede_edificio(id_edificio, 'MODIFICAR_CALENDARIO'))
with check (private.usuario_puede_edificio(id_edificio, 'MODIFICAR_CALENDARIO'));

drop policy if exists modalidades_edificio_select on public.modalidades_edificio;
create policy modalidades_edificio_select on public.modalidades_edificio
for select to authenticated
using (
  private.usuario_tiene_acceso_edificio(id_edificio)
  and private.usuario_tiene_permiso('VER_MODALIDAD_EDIFICIO')
);

drop policy if exists modalidades_edificio_insert on public.modalidades_edificio;
create policy modalidades_edificio_insert on public.modalidades_edificio
for insert to authenticated
with check (
  private.usuario_puede_edificio(id_edificio, 'MODIFICAR_MODALIDAD_EDIFICIO')
);

drop policy if exists modalidades_edificio_update on public.modalidades_edificio;
create policy modalidades_edificio_update on public.modalidades_edificio
for update to authenticated
using (
  private.usuario_puede_edificio(id_edificio, 'MODIFICAR_MODALIDAD_EDIFICIO')
)
with check (
  private.usuario_puede_edificio(id_edificio, 'MODIFICAR_MODALIDAD_EDIFICIO')
);

drop policy if exists complementos_edificio_select on public.complementos_edificio;
create policy complementos_edificio_select on public.complementos_edificio
for select to authenticated
using (private.usuario_tiene_acceso_edificio(id_edificio));

drop policy if exists complementos_edificio_insert on public.complementos_edificio;
create policy complementos_edificio_insert on public.complementos_edificio
for insert to authenticated
with check (
  private.usuario_puede_edificio(id_edificio, 'ACTIVAR_COMPLEMENTO_EDIFICIO')
);

drop policy if exists complementos_edificio_update on public.complementos_edificio;
create policy complementos_edificio_update on public.complementos_edificio
for update to authenticated
using (
  private.usuario_puede_edificio(id_edificio, 'ACTIVAR_COMPLEMENTO_EDIFICIO')
)
with check (
  private.usuario_puede_edificio(id_edificio, 'ACTIVAR_COMPLEMENTO_EDIFICIO')
);

-- PARÁMETROS SAAS: visibles, pero no modificables por usuarios de cliente/partner.
drop policy if exists parametros_saas_select on public.parametros_saas;
create policy parametros_saas_select on public.parametros_saas
for select to authenticated
using (activo);

-- COMUNICACIÓN
drop policy if exists estado_comunicacion_select on public.estado_comunicacion;
create policy estado_comunicacion_select on public.estado_comunicacion
for select to authenticated
using (
  (select private.usuario_tiene_permiso('VER_COMUNICACION'))
  and id_sensor in (select private.sensores_accesibles())
);

drop policy if exists incidencias_comunicacion_select on public.incidencias_comunicacion;
create policy incidencias_comunicacion_select on public.incidencias_comunicacion
for select to authenticated
using (
  (select private.usuario_tiene_permiso('VER_COMUNICACION'))
  and id_sensor in (select private.sensores_accesibles())
);

-- ALARMAS
drop policy if exists niveles_alarma_select on public.niveles_alarma;
create policy niveles_alarma_select on public.niveles_alarma
for select to authenticated
using (activo and private.usuario_tiene_permiso('VER_ALARMAS'));

drop policy if exists reglas_alarma_select on public.reglas_alarma;
create policy reglas_alarma_select on public.reglas_alarma
for select to authenticated
using (
  private.usuario_tiene_acceso_edificio(id_edificio)
  and private.usuario_tiene_permiso('VER_ALARMAS')
);

drop policy if exists reglas_alarma_insert on public.reglas_alarma;
create policy reglas_alarma_insert on public.reglas_alarma
for insert to authenticated
with check (private.usuario_puede_edificio(id_edificio, 'MODIFICAR_ALARMAS'));

drop policy if exists reglas_alarma_update on public.reglas_alarma;
create policy reglas_alarma_update on public.reglas_alarma
for update to authenticated
using (private.usuario_puede_edificio(id_edificio, 'MODIFICAR_ALARMAS'))
with check (private.usuario_puede_edificio(id_edificio, 'MODIFICAR_ALARMAS'));

drop policy if exists reglas_alarma_recintos_select on public.reglas_alarma_recintos;
create policy reglas_alarma_recintos_select on public.reglas_alarma_recintos
for select to authenticated
using (
  exists (
    select 1 from public.reglas_alarma ra
    where ra.id = id_regla_alarma
      and private.usuario_tiene_acceso_edificio(ra.id_edificio)
      and private.usuario_tiene_permiso('VER_ALARMAS')
  )
);

drop policy if exists reglas_alarma_recintos_insert on public.reglas_alarma_recintos;
create policy reglas_alarma_recintos_insert on public.reglas_alarma_recintos
for insert to authenticated
with check (
  exists (
    select 1 from public.reglas_alarma ra
    where ra.id = id_regla_alarma
      and private.usuario_puede_edificio(ra.id_edificio, 'MODIFICAR_ALARMAS')
  )
  and private.usuario_tiene_acceso_edificio(
    private.edificio_de_recinto(id_recinto)
  )
  and private.edificio_de_recinto(id_recinto) = (
    select ra.id_edificio
    from public.reglas_alarma ra
    where ra.id = id_regla_alarma
  )
);

drop policy if exists reglas_alarma_recintos_delete on public.reglas_alarma_recintos;
create policy reglas_alarma_recintos_delete on public.reglas_alarma_recintos
for delete to authenticated
using (
  exists (
    select 1 from public.reglas_alarma ra
    where ra.id = id_regla_alarma
      and private.usuario_puede_edificio(ra.id_edificio, 'MODIFICAR_ALARMAS')
  )
);

drop policy if exists reglas_alarma_usuarios_select on public.reglas_alarma_usuarios;
create policy reglas_alarma_usuarios_select on public.reglas_alarma_usuarios
for select to authenticated
using (
  exists (
    select 1 from public.reglas_alarma ra
    where ra.id = id_regla_alarma
      and private.usuario_tiene_acceso_edificio(ra.id_edificio)
      and private.usuario_tiene_permiso('VER_ALARMAS')
  )
);

drop policy if exists reglas_alarma_usuarios_insert on public.reglas_alarma_usuarios;
create policy reglas_alarma_usuarios_insert on public.reglas_alarma_usuarios
for insert to authenticated
with check (
  exists (
    select 1 from public.reglas_alarma ra
    where ra.id = id_regla_alarma
      and private.usuario_puede_edificio(ra.id_edificio, 'MODIFICAR_ALARMAS')
  )
);

drop policy if exists reglas_alarma_usuarios_delete on public.reglas_alarma_usuarios;
create policy reglas_alarma_usuarios_delete on public.reglas_alarma_usuarios
for delete to authenticated
using (
  exists (
    select 1 from public.reglas_alarma ra
    where ra.id = id_regla_alarma
      and private.usuario_puede_edificio(ra.id_edificio, 'MODIFICAR_ALARMAS')
  )
);

drop policy if exists eventos_alarma_select on public.eventos_alarma;
create policy eventos_alarma_select on public.eventos_alarma
for select to authenticated
using (
  private.usuario_tiene_acceso_edificio(
    (select ra.id_edificio
     from public.reglas_alarma ra
     where ra.id = id_regla_alarma)
  )
  and private.usuario_tiene_permiso('VER_ALARMAS')
);

-- Sin UPDATE directo: el motor (service_role) crea y actualiza eventos;
-- los usuarios solo reconocen o cierran mediante estas funciones.
drop policy if exists eventos_alarma_update on public.eventos_alarma;

create or replace function public.reconocer_alarma(
  p_id_evento uuid,
  p_comentario text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_edificio uuid;
  v_estado text;
begin
  select ra.id_edificio, ea.estado into v_edificio, v_estado
  from public.eventos_alarma ea
  join public.reglas_alarma ra on ra.id = ea.id_regla_alarma
  where ea.id = p_id_evento
  for update of ea;

  if v_edificio is null
     or not private.usuario_puede_edificio(v_edificio, 'RECONOCER_ALARMAS') then
    raise exception 'Alarma inexistente o sin permiso para reconocerla' using errcode = '42501';
  end if;

  if v_estado <> 'ACTIVA' then
    raise exception 'Solo se pueden reconocer alarmas activas' using errcode = '22023';
  end if;

  update public.eventos_alarma
     set estado = 'RECONOCIDA',
         fecha_reconocimiento = pg_catalog.now(),
         id_usuario_reconoce = private.usuario_actual(),
         comentario = coalesce(p_comentario, comentario)
   where id = p_id_evento;
end;
$$;

create or replace function public.cerrar_alarma(
  p_id_evento uuid,
  p_comentario text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_edificio uuid;
  v_estado text;
  v_usuario uuid := private.usuario_actual();
begin
  select ra.id_edificio, ea.estado into v_edificio, v_estado
  from public.eventos_alarma ea
  join public.reglas_alarma ra on ra.id = ea.id_regla_alarma
  where ea.id = p_id_evento
  for update of ea;

  if v_edificio is null
     or not private.usuario_puede_edificio(v_edificio, 'CERRAR_ALARMAS') then
    raise exception 'Alarma inexistente o sin permiso para cerrarla' using errcode = '42501';
  end if;

  if v_estado = 'CERRADA' then
    raise exception 'La alarma ya está cerrada' using errcode = '22023';
  end if;

  update public.eventos_alarma
     set estado = 'CERRADA',
         fecha_cierre = pg_catalog.now(),
         id_usuario_cierra = v_usuario,
         fecha_reconocimiento = coalesce(fecha_reconocimiento, pg_catalog.now()),
         id_usuario_reconoce = coalesce(id_usuario_reconoce, v_usuario),
         comentario = coalesce(p_comentario, comentario)
   where id = p_id_evento;
end;
$$;

revoke all on function public.reconocer_alarma(uuid, text) from public, anon;
revoke all on function public.cerrar_alarma(uuid, text) from public, anon;
grant execute on function public.reconocer_alarma(uuid, text) to authenticated;
grant execute on function public.cerrar_alarma(uuid, text) to authenticated;

drop policy if exists notificaciones_select on public.notificaciones;
create policy notificaciones_select on public.notificaciones
for select to authenticated
using (
  (
    id_evento_alarma is not null
    and exists (
      select 1
      from public.eventos_alarma ea
      join public.reglas_alarma ra on ra.id = ea.id_regla_alarma
      where ea.id = id_evento_alarma
        and private.usuario_tiene_acceso_edificio(ra.id_edificio)
        and private.usuario_tiene_permiso('VER_ALARMAS')
    )
  )
  or (
    id_sensor is not null
    and private.usuario_tiene_acceso_edificio(
      private.edificio_de_sensor(id_sensor)
    )
    and (
      private.usuario_tiene_permiso('VER_COMUNICACION')
      or private.usuario_tiene_permiso('VER_ALARMAS')
    )
  )
  or id_usuario = (select private.usuario_actual())
);

-- AUDITORÍA: consulta con permiso específico.
drop policy if exists auditoria_select on public.auditoria;
create policy auditoria_select on public.auditoria
for select to authenticated
using (
  private.usuario_tiene_rol('ADMIN_SAAS')
  or (
    private.usuario_tiene_permiso('VER_AUDITORIA')
    and id_edificio is not null
    and private.usuario_tiene_acceso_edificio(id_edificio)
  )
);

commit;