-- =========================================================
-- 028 · Conectores Sentilo (consulta) y LoRaWAN (envío), secretos en Vault
--       y tarea programada que despierta a la API cada 15 minutos
-- Decisiones D31–D33 (26/10/2026).
-- =========================================================
begin;

-- ---------------------------------------------------------
-- 1. LoRaWAN: el servidor de red (The Things Stack, ChirpStack…) envía
--    cada mensaje (uplink) a la API por webhook. Cada campo decodificado
--    del dispositivo es un sensor: dirección = DevEUI + campo.
-- ---------------------------------------------------------
insert into public.tipos_conexion (codigo, nombre, descripcion) values
  ('LORAWAN', 'LoRaWAN (webhook del servidor de red)',
   'Gateways y sensores LoRaWAN. El servidor de red (The Things Stack, ChirpStack o el integrado en el gateway) reenvía cada mensaje a la API por webhook, con el token de la conexión. Requiere que el servidor de red decodifique la carga útil.')
on conflict (codigo) do nothing;

update public.tipos_conexion set modo = 'ENVIO',
  esquema_configuracion = '{
    "type": "object",
    "properties": {
      "servidor_red": {"type": "string", "enum": ["THE_THINGS_STACK", "CHIRPSTACK", "OTRO"], "title": "Servidor de red LoRaWAN"}
    }
  }'::jsonb,
  esquema_punto = '{
    "type": "object",
    "required": ["dev_eui", "campo"],
    "properties": {
      "dev_eui": {"type": "string", "title": "DevEUI del dispositivo (16 caracteres hexadecimales)", "pattern": "^[0-9A-Fa-f]{16}$", "examples": ["24E124710B000001"]},
      "campo":   {"type": "string", "title": "Campo decodificado", "examples": ["temperature", "co2", "active_energy"]}
    }
  }'::jsonb
where codigo = 'LORAWAN';

-- La clave que usa procesar_lecturas se deriva sola: DEVEUI/campo
create or replace function public.clave_lorawan()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.direccion ? 'dev_eui'
     and exists (
       select 1 from public.conexiones c join public.tipos_conexion tc on tc.id = c.id_tipo_conexion
       where c.id = coalesce(new.id_conexion,
                             (select d.id_conexion from public.dispositivos d where d.id = new.id_dispositivo))
         and tc.codigo = 'LORAWAN') then
    if new.direccion->>'dev_eui' !~ '^[0-9A-Fa-f]{16}$' then
      raise exception 'DevEUI no válido: debe tener 16 caracteres hexadecimales';
    end if;
    new.direccion := new.direccion || pg_catalog.jsonb_build_object(
      'dev_eui', pg_catalog.upper(new.direccion->>'dev_eui'),
      'clave', pg_catalog.upper(new.direccion->>'dev_eui') || '/' || (new.direccion->>'campo'));
  end if;
  return new;
end;
$$;

-- Se llama "trg_sensores_clave…" para ejecutarse antes que "trg_sensores_validar_direccion"
drop trigger if exists trg_sensores_clave_lorawan on public.sensores;
create trigger trg_sensores_clave_lorawan
before insert or update of direccion, id_conexion, id_dispositivo
on public.sensores
for each row execute function public.clave_lorawan();

-- Puntos recibidos que aún no tienen sensor: ayudan al Partner a configurar
alter table public.conexiones
  add column if not exists puntos_detectados jsonb not null default '{}'::jsonb;

comment on column public.conexiones.puntos_detectados is
  'Claves recibidas sin sensor configurado (clave → última vez vista). Las muestra el asistente de alta.';

-- Claves configuradas de la conexión de un token (la API descarta el resto)
create or replace function public.claves_conexion_token(p_token text)
returns text[]
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_con uuid := private.conexion_de_token(p_token);
begin
  if v_con is null then
    raise exception 'Token no válido' using errcode = '28000';
  end if;
  return coalesce((
    select pg_catalog.array_agg(s.direccion->>'clave')
    from public.sensores s
    left join public.dispositivos d on d.id = s.id_dispositivo
    where coalesce(s.id_conexion, d.id_conexion) = v_con and s.activo and s.direccion ? 'clave'), '{}');
end;
$$;

create or replace function public.registrar_puntos_detectados(p_token text, p_claves text[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_con uuid := private.conexion_de_token(p_token);
begin
  if v_con is null then
    raise exception 'Token no válido' using errcode = '28000';
  end if;
  update public.conexiones c
     set puntos_detectados = (
       select pg_catalog.jsonb_object_agg(k, v) from (
         select k, v from pg_catalog.jsonb_each(c.puntos_detectados) e(k, v)
         where not (k = any (p_claves))
         union all
         select k, pg_catalog.to_jsonb(pg_catalog.now()) from pg_catalog.unnest(p_claves) k
         order by 2 desc limit 200) x)
   where c.id = v_con and pg_catalog.cardinality(p_claves) > 0;
end;
$$;

-- ---------------------------------------------------------
-- 2. Secretos de las conexiones en Supabase Vault
--    (token de Sentilo, credenciales de APIs). Nunca en configuracion.
-- ---------------------------------------------------------
alter table public.conexiones
  add column if not exists id_secreto uuid;

comment on column public.conexiones.id_secreto is
  'Id del secreto en Supabase Vault (token o credencial del origen). Solo lo lee la API.';

create or replace function public.guardar_secreto_conexion(p_id_conexion uuid, p_secreto text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_con public.conexiones%rowtype;
begin
  select * into v_con from public.conexiones where id = p_id_conexion;
  if not found then
    raise exception 'La conexión no existe';
  end if;
  if auth.uid() is not null
     and not private.usuario_puede_edificio(v_con.id_edificio, 'MODIFICAR_CONEXION') then
    raise exception 'Sin permiso para gestionar esta conexión' using errcode = '42501';
  end if;
  if coalesce(pg_catalog.btrim(p_secreto), '') = '' then
    raise exception 'El secreto está vacío';
  end if;

  if v_con.id_secreto is not null and exists (select 1 from vault.secrets where id = v_con.id_secreto) then
    perform vault.update_secret(v_con.id_secreto, p_secreto);
  else
    update public.conexiones
       set id_secreto = vault.create_secret(p_secreto, 'conexion_' || p_id_conexion::text,
                                            'Secreto de la conexión ' || v_con.codigo)
     where id = p_id_conexion;
  end if;
end;
$$;

create or replace function public.secreto_conexion(p_id_conexion uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select ds.decrypted_secret
  from public.conexiones c
  join vault.decrypted_secrets ds on ds.id = c.id_secreto
  where c.id = p_id_conexion;
$$;

-- ---------------------------------------------------------
-- 3. Lo que la tarea de la API necesita en cada ciclo
-- ---------------------------------------------------------
-- Conexiones de consulta activas con sus sensores y su última lectura
create or replace function public.conexiones_para_consultar()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'id', c.id, 'codigo', c.codigo, 'tipo', tc.codigo, 'configuracion', c.configuracion,
    'tiene_secreto', c.id_secreto is not null,
    'sensores', (
      select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
               'id', s.id, 'direccion', s.direccion, 'ultima_lectura', ec.ultima_lectura)), '[]'::jsonb)
      from public.sensores s
      left join public.dispositivos d on d.id = s.id_dispositivo
      left join public.estado_comunicacion ec on ec.id_sensor = s.id
      where coalesce(s.id_conexion, d.id_conexion) = c.id and s.activo and s.direccion <> '{}'::jsonb)
  ) order by c.codigo), '[]'::jsonb)
  from public.conexiones c
  join public.tipos_conexion tc on tc.id = c.id_tipo_conexion
  where c.activo and tc.modo = 'CONSULTA';
$$;

-- Recuperaciones de histórico pendientes o en curso
create or replace function public.recuperaciones_pendientes()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'id_conexion', c.id, 'tipo', tc.codigo, 'configuracion', c.configuracion,
    'desde', coalesce(c.recuperado_hasta, c.recuperar_desde::timestamptz),
    'id_importacion', c.id_importacion_recuperacion,
    'lotes_procesados', coalesce(i.lotes_procesados, 0),
    'sensores', (
      select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('id', s.id, 'direccion', s.direccion)), '[]'::jsonb)
      from public.sensores s
      left join public.dispositivos d on d.id = s.id_dispositivo
      where coalesce(s.id_conexion, d.id_conexion) = c.id and s.activo and s.direccion <> '{}'::jsonb)
  )), '[]'::jsonb)
  from public.conexiones c
  join public.tipos_conexion tc on tc.id = c.id_tipo_conexion
  left join public.importaciones i on i.id = c.id_importacion_recuperacion
  where c.activo and c.recuperacion_estado in ('PENDIENTE', 'EN_CURSO');
$$;

-- Error de una consulta (la conexión no responde, token incorrecto…)
create or replace function public.registrar_error_conexion(p_id_conexion uuid, p_error text)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.conexiones
     set ultima_ejecucion = pg_catalog.now(), ultimo_error = pg_catalog.left(p_error, 500)
   where id = p_id_conexion;
$$;

-- ---------------------------------------------------------
-- 4. Tarea programada: cada 15 minutos Supabase llama a la API
--    (POST <api>/v1/tareas/ciclo). Así funciona aunque la API esté en un
--    plan que se duerme. URL y secreto se guardan en Vault:
--      select vault.create_secret('https://<api>.onrender.com', 'api_url');
--      select vault.create_secret('<mismo valor que TAREAS_SECRETO>', 'api_tareas_secreto');
--    Requiere las extensiones pg_cron y pg_net.
-- ---------------------------------------------------------
create or replace function private.llamar_api_tareas()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_secreto text;
begin
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'api_url';
  select decrypted_secret into v_secreto from vault.decrypted_secrets where name = 'api_tareas_secreto';
  if v_url is null or v_secreto is null then
    raise notice 'Faltan los secretos api_url o api_tareas_secreto en Vault: no se llama a la API';
    return null;
  end if;
  return net.http_post(
    url := pg_catalog.rtrim(v_url, '/') || '/v1/tareas/ciclo',
    headers := pg_catalog.jsonb_build_object('Authorization', 'Bearer ' || v_secreto, 'Content-Type', 'application/json'),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000);
end;
$$;

do $$
begin
  if exists (select 1 from pg_catalog.pg_extension where extname = 'pg_cron')
     and exists (select 1 from pg_catalog.pg_extension where extname = 'pg_net') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'api_ciclo_15min';
    perform cron.schedule('api_ciclo_15min', '*/15 * * * *', 'select private.llamar_api_tareas()');
  else
    raise notice 'pg_cron o pg_net no están activos: active ambas extensiones y vuelva a ejecutar este bloque';
  end if;
end;
$$;

-- ---------------------------------------------------------
-- 5. Permisos
-- ---------------------------------------------------------
revoke all on function public.clave_lorawan() from public, anon, authenticated;
revoke all on function public.claves_conexion_token(text) from public, anon, authenticated;
revoke all on function public.registrar_puntos_detectados(text, text[]) from public, anon, authenticated;
revoke all on function public.guardar_secreto_conexion(uuid, text) from public, anon;
revoke all on function public.secreto_conexion(uuid) from public, anon, authenticated;
revoke all on function public.conexiones_para_consultar() from public, anon, authenticated;
revoke all on function public.recuperaciones_pendientes() from public, anon, authenticated;
revoke all on function public.registrar_error_conexion(uuid, text) from public, anon, authenticated;
revoke all on function private.llamar_api_tareas() from public, anon, authenticated;

grant execute on function public.claves_conexion_token(text) to service_role;
grant execute on function public.registrar_puntos_detectados(text, text[]) to service_role;
grant execute on function public.guardar_secreto_conexion(uuid, text) to authenticated, service_role;
grant execute on function public.secreto_conexion(uuid) to service_role;
grant execute on function public.conexiones_para_consultar() to service_role;
grant execute on function public.recuperaciones_pendientes() to service_role;
grant execute on function public.registrar_error_conexion(uuid, text) to service_role;

commit;
