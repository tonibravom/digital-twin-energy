-- =========================================================
-- PRUEBAS DE CONECTORES SENTILO Y LORAWAN, SECRETOS Y TAREA PROGRAMADA (migración 028)
-- Ejecutar con:  npx supabase test db
-- =========================================================
begin;
set search_path = public, extensions;

select plan(22);

insert into auth.users (id, email) values
  ('e9000000-0000-0000-0000-000000000001', 'pa@c.test'),
  ('e9000000-0000-0000-0000-000000000002', 'pb@c.test');
insert into proveedores (id, codigo, nombre) values
  ('f0000000-0000-0000-0000-00000000000a', 'CA', 'Partner A'),
  ('f0000000-0000-0000-0000-00000000000b', 'CB', 'Partner B');
insert into clientes (id, codigo, nombre) values ('f0100000-0000-0000-0000-000000000001', 'CC', 'Cliente');
insert into proveedores_clientes (id_proveedor, id_cliente) values
  ('f0000000-0000-0000-0000-00000000000a', 'f0100000-0000-0000-0000-000000000001');
insert into edificios (id, id_cliente, codigo, nombre) values
  ('f0200000-0000-0000-0000-000000000001', 'f0100000-0000-0000-0000-000000000001', 'CE', 'Edificio');
insert into proveedores_edificios (id_proveedor, id_edificio) values
  ('f0000000-0000-0000-0000-00000000000a', 'f0200000-0000-0000-0000-000000000001');
insert into plantas (id, id_edificio, codigo, nombre) values
  ('f0300000-0000-0000-0000-000000000001', 'f0200000-0000-0000-0000-000000000001', 'P0', 'PB');
insert into recintos (id, id_planta, codigo, nombre) values
  ('f0400000-0000-0000-0000-000000000001', 'f0300000-0000-0000-0000-000000000001', 'R', 'Oficina');

insert into conexiones (id, id_edificio, id_tipo_conexion, codigo, nombre, configuracion)
select 'f0500000-0000-0000-0000-000000000001', 'f0200000-0000-0000-0000-000000000001', id, 'LORA', 'Gateway LoRaWAN',
       '{"servidor_red": "THE_THINGS_STACK"}'
from tipos_conexion where codigo = 'LORAWAN';
insert into conexiones (id, id_edificio, id_tipo_conexion, codigo, nombre, configuracion)
select 'f0500000-0000-0000-0000-000000000002', 'f0200000-0000-0000-0000-000000000001', id, 'SENT', 'Sentilo',
       '{"url_base": "https://sentilo.ejemplo.com", "proveedor": "SIMULADOR"}'
from tipos_conexion where codigo = 'SENTILO';

create function pg_temp.sensor(p_id uuid, p_con uuid, p_cod text, p_dir jsonb) returns void language sql as $$
  insert into sensores (id, id_conexion, id_recinto, id_familia, id_naturaleza, id_tratamiento, codigo, nombre, unidad, direccion)
  select p_id, p_con, 'f0400000-0000-0000-0000-000000000001', f.id, n.id, t.id, p_cod, p_cod, '°C', p_dir
  from familias_sensor f, naturalezas_sensor n, tratamientos_sensor t
  where f.codigo = 'TEMPERATURA' and n.codigo = 'INSTANTANEA' and t.codigo = 'PROMEDIO';
$$;

insert into usuarios (id, auth_user_id, nombre, email, id_rol)
select x.id::uuid, x.auth::uuid, 'U', x.mail, r.id
from (values
  ('f0700000-0000-0000-0000-000000000001', 'e9000000-0000-0000-0000-000000000001', 'pa@c.test', 'ADMIN_PARTNER'),
  ('f0700000-0000-0000-0000-000000000002', 'e9000000-0000-0000-0000-000000000002', 'pb@c.test', 'ADMIN_PARTNER')) x(id, auth, mail, rol)
join roles r on r.codigo = x.rol;
insert into usuarios_partners (id_usuario, id_proveedor) values
  ('f0700000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-00000000000a'),
  ('f0700000-0000-0000-0000-000000000002', 'f0000000-0000-0000-0000-00000000000b');

create function pg_temp.login(p_auth uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', p_auth::text, true),
         set_config('request.jwt.claims', json_build_object('sub', p_auth, 'role', 'authenticated', 'aal', 'aal2')::text, true);
$$;
create function pg_temp.logout() returns void language sql as $$
  select set_config('request.jwt.claim.sub', '', true), set_config('request.jwt.claims', '', true);
$$;

-- =========================================================
-- 1. LoRaWAN
-- =========================================================
select is((select modo from tipos_conexion where codigo = 'LORAWAN'), 'ENVIO', 'Existe el tipo LoRaWAN, por envío (webhook)');

select pg_temp.sensor('f0600000-0000-0000-0000-000000000001', 'f0500000-0000-0000-0000-000000000001', 'AM307-T',
                      '{"dev_eui": "24e124710b000001", "campo": "temperature"}');
select is((select direccion->>'clave' from sensores where id = 'f0600000-0000-0000-0000-000000000001'),
  '24E124710B000001/temperature', 'La clave del sensor se deriva del DevEUI y el campo');
select is((select direccion->>'dev_eui' from sensores where id = 'f0600000-0000-0000-0000-000000000001'),
  '24E124710B000001', 'El DevEUI se guarda en mayúsculas');
select throws_like(
  $$ select pg_temp.sensor(gen_random_uuid(), 'f0500000-0000-0000-0000-000000000001', 'MAL', '{"dev_eui": "1234", "campo": "co2"}') $$,
  '%DevEUI no válido%', 'Un DevEUI mal escrito se rechaza');
select throws_like(
  $$ select pg_temp.sensor(gen_random_uuid(), 'f0500000-0000-0000-0000-000000000001', 'DUP', '{"dev_eui": "24E124710B000001", "campo": "temperature"}') $$,
  '%misma dirección%', 'No puede haber dos sensores con el mismo DevEUI y campo');
select throws_like(
  $$ select pg_temp.sensor(gen_random_uuid(), 'f0500000-0000-0000-0000-000000000001', 'SINC', '{"dev_eui": "24E124710B000002"}') $$,
  '%campo%', 'El campo es obligatorio');

create temp table tk as select generar_token_conexion('f0500000-0000-0000-0000-000000000001') as t;
select is(claves_conexion_token((select t from tk)), array['24E124710B000001/temperature'],
  'La API obtiene las claves configuradas de la conexión del token');
select throws_ok($$ select claves_conexion_token('dte_falso') $$, '28000', null, '… y un token falso se rechaza');
select is((procesar_lecturas_token((select t from tk), jsonb_build_array(jsonb_build_object(
            'clave', '24E124710B000001/temperature', 'fecha_hora', now() - interval '5 minutes', 'valor', 21.4)))->>'guardadas')::int,
  1, 'Un mensaje LoRaWAN se guarda por el canal único de lecturas');
select registrar_puntos_detectados((select t from tk), array['24E124710B000001/co2', '24E124710B000001/humidity']);
select ok((select puntos_detectados ?& array['24E124710B000001/co2', '24E124710B000001/humidity']
           from conexiones where id = 'f0500000-0000-0000-0000-000000000001'),
  'Los campos recibidos sin sensor quedan como puntos detectados para el asistente');

-- =========================================================
-- 2. Secretos en Vault
-- =========================================================
select pg_temp.login('e9000000-0000-0000-0000-000000000001');
set local role authenticated;
select lives_ok($$ select guardar_secreto_conexion('f0500000-0000-0000-0000-000000000002', 'token-sentilo-1') $$,
  'El Partner guarda el token de Sentilo en Vault');
select throws_like($$ select guardar_secreto_conexion('f0500000-0000-0000-0000-000000000002', '  ') $$,
  '%vacío%', 'No se guarda un secreto vacío');
select throws_ok($$ select secreto_conexion('f0500000-0000-0000-0000-000000000002') $$, '42501', null,
  'Un usuario no puede leer el secreto');
reset role;
select pg_temp.login('e9000000-0000-0000-0000-000000000002');
set local role authenticated;
select throws_ok($$ select guardar_secreto_conexion('f0500000-0000-0000-0000-000000000002', 'robado') $$, '42501', null,
  'Otro Partner no puede cambiar el secreto');
reset role;
select pg_temp.logout();

select is(secreto_conexion('f0500000-0000-0000-0000-000000000002'), 'token-sentilo-1', 'La API lee el secreto');
create temp table s1 as select id_secreto from conexiones where id = 'f0500000-0000-0000-0000-000000000002';
select guardar_secreto_conexion('f0500000-0000-0000-0000-000000000002', 'token-sentilo-2');
select ok((select c.id_secreto = s1.id_secreto from conexiones c, s1 where c.id = 'f0500000-0000-0000-0000-000000000002')
          and secreto_conexion('f0500000-0000-0000-0000-000000000002') = 'token-sentilo-2',
  'Cambiar el secreto lo actualiza en Vault sin crear otro');
select ok(not (select configuracion::text like '%token-sentilo%' from conexiones where id = 'f0500000-0000-0000-0000-000000000002'),
  'El secreto no aparece en la configuración de la conexión');

-- =========================================================
-- 3. Lo que necesita la tarea de la API
-- =========================================================
select pg_temp.sensor('f0600000-0000-0000-0000-000000000002', 'f0500000-0000-0000-0000-000000000002', 'CONT-GENERAL',
                      '{"sensor": "CONT-GENERAL"}');
select is((select jsonb_array_length(c->'sensores') from jsonb_array_elements(conexiones_para_consultar()) c
           where c->>'codigo' = 'SENT'), 1, 'La tarea obtiene las conexiones de consulta con sus sensores');
select ok(not exists (select 1 from jsonb_array_elements(conexiones_para_consultar()) c where c->>'codigo' = 'LORA'),
  'Las conexiones por envío (LoRaWAN) no se consultan');

select solicitar_recuperacion('f0500000-0000-0000-0000-000000000002', current_date - 30);
select is((select (r->>'desde')::date from jsonb_array_elements(recuperaciones_pendientes()) r
           where r->>'id_conexion' = 'f0500000-0000-0000-0000-000000000002'), current_date - 30,
  'La tarea ve la recuperación de histórico pendiente y desde cuándo');

select registrar_error_conexion('f0500000-0000-0000-0000-000000000002', 'Sentilo responde 401');
select is((select ultimo_error from conexiones where id = 'f0500000-0000-0000-0000-000000000002'), 'Sentilo responde 401',
  'Los errores de consulta quedan en la conexión para el Partner');

select ok(case when exists (select 1 from vault.decrypted_secrets where name in ('api_url', 'api_tareas_secreto'))
               then true  -- instalación ya configurada: no se llama a la API desde una prueba
               else private.llamar_api_tareas() is null end,
  'Sin URL ni secreto de la API en Vault, la tarea programada no llama a nada');

select * from finish();
rollback;
