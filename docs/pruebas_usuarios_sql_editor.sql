-- VERSIÓN PARA EL SQL EDITOR DE SUPABASE: pegar entero y pulsar Run.
-- Al final sale un mensaje en ROJO a propósito con el resumen;
-- al ser un error, deshace todos los datos de prueba.
-- =========================================================
-- PRUEBAS DE ALTA DE USUARIOS, CONTRASEÑA INICIAL Y DOBLE FACTOR (migración 027)
-- Ejecutar con:  npx supabase test db
-- =========================================================
begin;
set search_path = public, extensions;

create temp table resultados (n serial, t text);
grant all on resultados to public;
grant all on sequence resultados_n_seq to public;
select plan(37);

insert into auth.users (id, email) values
  ('e8000000-0000-0000-0000-000000000001', 'saas@u.test'),
  ('e8000000-0000-0000-0000-000000000002', 'adminA@u.test'),
  ('e8000000-0000-0000-0000-000000000003', 'tecA@u.test'),
  ('e8000000-0000-0000-0000-000000000004', 'adminB@u.test'),
  ('e8000000-0000-0000-0000-000000000005', 'clienteA@u.test'),
  ('e8000000-0000-0000-0000-000000000006', 'nuevo1@u.test'),
  ('e8000000-0000-0000-0000-000000000007', 'nuevo2@u.test');

insert into proveedores (id, codigo, nombre) values
  ('ee000000-0000-0000-0000-00000000000a', 'UA', 'Partner A'),
  ('ee000000-0000-0000-0000-00000000000b', 'UB', 'Partner B');
insert into clientes (id, codigo, nombre) values
  ('ee100000-0000-0000-0000-00000000000a', 'CUA', 'Cliente A'),
  ('ee100000-0000-0000-0000-00000000000b', 'CUB', 'Cliente B');
insert into proveedores_clientes (id_proveedor, id_cliente) values
  ('ee000000-0000-0000-0000-00000000000a', 'ee100000-0000-0000-0000-00000000000a'),
  ('ee000000-0000-0000-0000-00000000000b', 'ee100000-0000-0000-0000-00000000000b');
insert into edificios (id, id_cliente, codigo, nombre) values
  ('ee200000-0000-0000-0000-00000000000a', 'ee100000-0000-0000-0000-00000000000a', 'EUA', 'Edificio A'),
  ('ee200000-0000-0000-0000-00000000000b', 'ee100000-0000-0000-0000-00000000000b', 'EUB', 'Edificio B');
insert into proveedores_edificios (id_proveedor, id_edificio) values
  ('ee000000-0000-0000-0000-00000000000a', 'ee200000-0000-0000-0000-00000000000a'),
  ('ee000000-0000-0000-0000-00000000000b', 'ee200000-0000-0000-0000-00000000000b');

insert into usuarios (id, auth_user_id, nombre, email, id_rol)
select x.id::uuid, x.auth::uuid, 'U', x.mail, r.id
from (values
  ('ee700000-0000-0000-0000-000000000001', 'e8000000-0000-0000-0000-000000000001', 'saas@u.test', 'ADMIN_SAAS'),
  ('ee700000-0000-0000-0000-000000000002', 'e8000000-0000-0000-0000-000000000002', 'admina@u.test', 'ADMIN_PARTNER'),
  ('ee700000-0000-0000-0000-000000000003', 'e8000000-0000-0000-0000-000000000003', 'teca@u.test', 'TECNICO_PARTNER'),
  ('ee700000-0000-0000-0000-000000000004', 'e8000000-0000-0000-0000-000000000004', 'adminb@u.test', 'ADMIN_PARTNER'),
  ('ee700000-0000-0000-0000-000000000005', 'e8000000-0000-0000-0000-000000000005', 'clientea@u.test', 'USUARIO_CLIENTE')) x(id, auth, mail, rol)
join roles r on r.codigo = x.rol;
insert into usuarios_partners (id_usuario, id_proveedor) values
  ('ee700000-0000-0000-0000-000000000002', 'ee000000-0000-0000-0000-00000000000a'),
  ('ee700000-0000-0000-0000-000000000003', 'ee000000-0000-0000-0000-00000000000a'),
  ('ee700000-0000-0000-0000-000000000004', 'ee000000-0000-0000-0000-00000000000b');
insert into usuarios_clientes (id_usuario, id_cliente) values
  ('ee700000-0000-0000-0000-000000000005', 'ee100000-0000-0000-0000-00000000000a');

-- Sesión: aal (aal1 = solo contraseña) e id de sesión de Supabase Auth
create function pg_temp.login(p_auth uuid, p_aal text default 'aal2', p_sesion uuid default null) returns void language sql as $$
  select set_config('request.jwt.claim.sub', p_auth::text, true),
         set_config('request.jwt.claims', json_build_object('sub', p_auth, 'role', 'authenticated', 'aal', p_aal,
                    'session_id', coalesce(p_sesion, gen_random_uuid()))::text, true);
$$;
create function pg_temp.logout() returns void language sql as $$
  select set_config('request.jwt.claim.sub', '', true), set_config('request.jwt.claims', '', true);
$$;

-- =========================================================
-- 1. Doble factor por email
-- =========================================================
insert into resultados (t) select ok((select bool_and(requiere_doble_factor) from roles where codigo in ('ADMIN_SAAS', 'ADMIN_PARTNER'))
          and not (select bool_or(requiere_doble_factor) from roles where codigo in ('TECNICO_PARTNER', 'USUARIO_CLIENTE')),
  'El doble factor es obligatorio para administradores de plataforma y de Partner');

select pg_temp.login('e8000000-0000-0000-0000-000000000002', 'aal1', 'aaaa0000-0000-0000-0000-000000000001');
set local role authenticated;
insert into resultados (t) select is((select count(*) from edificios), 0::bigint, 'Un administrador de Partner sin código verificado no ve ningún dato');
insert into resultados (t) select ok((select (mi_cuenta()->>'requiere_doble_factor')::boolean and not (mi_cuenta()->>'acceso_completo')::boolean),
  'mi_cuenta indica que falta el código');
insert into resultados (t) select throws_ok($$ select count(*) from codigos_verificacion $$, '42501', null, 'Los códigos no son accesibles para los usuarios');
reset role;
select pg_temp.logout();

insert into resultados (t) select ok(crear_codigo_verificacion('e8000000-0000-0000-0000-000000000002', 'aaaa0000-0000-0000-0000-000000000001', '123456') > now(),
  'La API registra un código que caduca en el futuro');
insert into resultados (t) select is((select codigo_hash <> '123456' from codigos_verificacion
           where auth_user_id = 'e8000000-0000-0000-0000-000000000002'), true, 'El código se guarda cifrado');
insert into resultados (t) select is(verificar_codigo('e8000000-0000-0000-0000-000000000002', 'aaaa0000-0000-0000-0000-000000000001', '000000'),
  '{"resultado": "INCORRECTO", "intentos_restantes": 4}'::jsonb, 'Un código erróneo resta intentos');
insert into resultados (t) select is(verificar_codigo('e8000000-0000-0000-0000-000000000002', 'aaaa0000-0000-0000-0000-000000000001', '123456')->>'resultado',
  'OK', 'El código correcto verifica la sesión');

select pg_temp.login('e8000000-0000-0000-0000-000000000002', 'aal1', 'aaaa0000-0000-0000-0000-000000000001');
set local role authenticated;
insert into resultados (t) select is((select count(*) from edificios), 1::bigint, 'Con la sesión verificada ve sus edificios');
reset role;
select pg_temp.login('e8000000-0000-0000-0000-000000000002', 'aal1', 'aaaa0000-0000-0000-0000-000000000002');
set local role authenticated;
insert into resultados (t) select is((select count(*) from edificios), 0::bigint, 'Otra sesión (otro navegador) necesita su propio código');
reset role;
select pg_temp.logout();

select crear_codigo_verificacion('e8000000-0000-0000-0000-000000000004', 'bbbb0000-0000-0000-0000-000000000001', '111111');
update codigos_verificacion set expira_at = now() - interval '1 minute' where auth_user_id = 'e8000000-0000-0000-0000-000000000004';
insert into resultados (t) select is(verificar_codigo('e8000000-0000-0000-0000-000000000004', 'bbbb0000-0000-0000-0000-000000000001', '111111')->>'resultado',
  'CADUCADO', 'Un código caducado no sirve');
select crear_codigo_verificacion('e8000000-0000-0000-0000-000000000004', 'bbbb0000-0000-0000-0000-000000000001', '222222');
select verificar_codigo('e8000000-0000-0000-0000-000000000004', 'bbbb0000-0000-0000-0000-000000000001', '000000')
from generate_series(1, 5);
insert into resultados (t) select is(verificar_codigo('e8000000-0000-0000-0000-000000000004', 'bbbb0000-0000-0000-0000-000000000001', '222222')->>'resultado',
  'BLOQUEADO', 'Tras 5 intentos fallidos el código queda bloqueado aunque luego se acierte');
select crear_codigo_verificacion('e8000000-0000-0000-0000-000000000004', 'bbbb0000-0000-0000-0000-000000000001', '333333')
from generate_series(1, 3);
insert into resultados (t) select throws_like(
  $$ select crear_codigo_verificacion('e8000000-0000-0000-0000-000000000004', 'bbbb0000-0000-0000-0000-000000000001', '444444') $$,
  '%Demasiados códigos%', 'No se pueden pedir más de 5 códigos en 15 minutos');

-- =========================================================
-- 2. Contraseña inicial
-- =========================================================
update usuarios set debe_cambiar_contrasena = true where id = 'ee700000-0000-0000-0000-000000000005';
select pg_temp.login('e8000000-0000-0000-0000-000000000005', 'aal1');
set local role authenticated;
insert into resultados (t) select is((select count(*) from edificios), 0::bigint, 'Con la contraseña inicial sin cambiar no ve ningún dato');
insert into resultados (t) select ok((mi_cuenta()->>'debe_cambiar_contrasena')::boolean, 'mi_cuenta indica que debe cambiar la contraseña');
reset role;
select gestionar_usuario('ee700000-0000-0000-0000-000000000005', 'ee700000-0000-0000-0000-000000000005', 'CONTRASENA_CAMBIADA');
set local role authenticated;
insert into resultados (t) select is((select count(*) from edificios), 1::bigint, 'Tras cambiarla accede a su edificio (sin código: su rol no lo exige)');
reset role;
select pg_temp.logout();

-- =========================================================
-- 3. Quién puede dar de alta a quién (validación con la sesión de quien da de alta)
-- =========================================================
select pg_temp.login('e8000000-0000-0000-0000-000000000002');   -- admin Partner A (aal2)
set local role authenticated;
insert into resultados (t) select is(validar_alta_usuario('nuevo1@u.test', 'USUARIO_CLIENTE', null, 'MASTER', array['ee100000-0000-0000-0000-00000000000a'::uuid]),
  'ee700000-0000-0000-0000-000000000002'::uuid, 'El admin del Partner A puede dar de alta usuarios de su cliente');
insert into resultados (t) select throws_ok(
  $$ select validar_alta_usuario('x@u.test', 'USUARIO_CLIENTE', null, 'MASTER', array['ee100000-0000-0000-0000-00000000000b'::uuid]) $$,
  '42501', null, '… pero no de un cliente de otro Partner');
insert into resultados (t) select throws_ok($$ select validar_alta_usuario('x@u.test', 'ADMIN_SAAS') $$, '42501', null,
  'Un Partner no puede crear administradores de la plataforma');
insert into resultados (t) select throws_ok($$ select validar_alta_usuario('CLIENTEA@u.test', 'USUARIO_CLIENTE', null, 'MASTER',
                     array['ee100000-0000-0000-0000-00000000000a'::uuid]) $$, '23505', null,
  'No se repiten emails (sin distinguir mayúsculas)');
insert into resultados (t) select throws_like(
  $$ select validar_alta_usuario('x@u.test', 'USUARIO_CLIENTE', null, 'RESTRINGIDO',
       array['ee100000-0000-0000-0000-00000000000a'::uuid], array['ee200000-0000-0000-0000-00000000000b'::uuid]) $$,
  '%edificio%', 'Un usuario restringido solo puede asignarse a edificios de sus clientes');
reset role;

select pg_temp.login('e8000000-0000-0000-0000-000000000003');   -- técnico Partner A
set local role authenticated;
insert into resultados (t) select lives_ok($$ select validar_alta_usuario('x@u.test', 'TECNICO_PARTNER', 'ee000000-0000-0000-0000-00000000000a') $$,
  'El técnico puede dar de alta técnicos de su Partner');
insert into resultados (t) select throws_ok($$ select validar_alta_usuario('x@u.test', 'ADMIN_PARTNER', 'ee000000-0000-0000-0000-00000000000a') $$,
  '42501', null, '… pero no administradores del Partner');
insert into resultados (t) select throws_ok($$ select validar_alta_usuario('x@u.test', 'TECNICO_PARTNER', 'ee000000-0000-0000-0000-00000000000b') $$,
  '42501', null, '… ni usuarios de otro Partner');
reset role;

select pg_temp.login('e8000000-0000-0000-0000-000000000005');   -- cliente
set local role authenticated;
insert into resultados (t) select throws_ok($$ select validar_alta_usuario('x@u.test', 'USUARIO_CLIENTE', null, 'MASTER',
                     array['ee100000-0000-0000-0000-00000000000a'::uuid]) $$, '42501', null,
  'Un usuario de cliente no da de alta usuarios');
insert into resultados (t) select throws_ok($$ select registrar_usuario('ee700000-0000-0000-0000-000000000005', 'e8000000-0000-0000-0000-000000000006',
                     'nuevo1@u.test', 'N', null, null, 'USUARIO_CLIENTE') $$, '42501', null,
  'Desde el navegador no se puede registrar usuarios directamente');
reset role;
select pg_temp.logout();

-- =========================================================
-- 4. Registro (lo hace la API como servicio)
-- =========================================================
insert into resultados (t) select ok(registrar_usuario('ee700000-0000-0000-0000-000000000002', 'e8000000-0000-0000-0000-000000000006',
          ' Nuevo1@U.test ', 'Ana', 'Pérez', null, 'USUARIO_CLIENTE', null, 'RESTRINGIDO',
          array['ee100000-0000-0000-0000-00000000000a'::uuid], array['ee200000-0000-0000-0000-00000000000a'::uuid]) is not null,
  'La API registra el usuario creado por el admin del Partner A');
insert into resultados (t) select ok((select debe_cambiar_contrasena and email = 'nuevo1@u.test' from usuarios where auth_user_id = 'e8000000-0000-0000-0000-000000000006'),
  'El usuario nuevo debe cambiar la contraseña y su email se normaliza');
insert into resultados (t) select is((select count(*) from usuarios_edificios ue join usuarios u on u.id = ue.id_usuario
           where u.auth_user_id = 'e8000000-0000-0000-0000-000000000006'), 1::bigint, 'Se le asigna el edificio indicado');
insert into resultados (t) select throws_ok(
  $$ select registrar_usuario('ee700000-0000-0000-0000-000000000004', 'e8000000-0000-0000-0000-000000000007',
       'nuevo2@u.test', 'B', null, null, 'USUARIO_CLIENTE', null, 'MASTER', array['ee100000-0000-0000-0000-00000000000a'::uuid]) $$,
  '42501', null, 'El registro vuelve a comprobar permisos: el Partner B no puede asignar el cliente A');

-- =========================================================
-- 5. Gestión de usuarios existentes
-- =========================================================
insert into resultados (t) select throws_ok(
  $$ select gestionar_usuario('ee700000-0000-0000-0000-000000000004', 'ee700000-0000-0000-0000-000000000005', 'BAJA') $$,
  '42501', null, 'El Partner B no puede dar de baja a un usuario de un cliente del Partner A');
insert into resultados (t) select throws_ok(
  $$ select gestionar_usuario('ee700000-0000-0000-0000-000000000003', 'ee700000-0000-0000-0000-000000000002', 'RESTABLECER_CONTRASENA') $$,
  '42501', null, 'El técnico no puede restablecer la contraseña de su administrador');
insert into resultados (t) select throws_ok(
  $$ select gestionar_usuario('ee700000-0000-0000-0000-000000000002', 'ee700000-0000-0000-0000-000000000002', 'BAJA') $$,
  '42501', null, 'Nadie puede darse de baja a sí mismo');
insert into resultados (t) select is(gestionar_usuario('ee700000-0000-0000-0000-000000000002', 'ee700000-0000-0000-0000-000000000005', 'BAJA'),
  'e8000000-0000-0000-0000-000000000005'::uuid, 'El admin del Partner A da de baja al usuario de su cliente');
select pg_temp.login('e8000000-0000-0000-0000-000000000005');
set local role authenticated;
insert into resultados (t) select ok(mi_cuenta() is null, 'Un usuario dado de baja deja de tener acceso');
reset role;
select pg_temp.logout();
insert into resultados (t) select throws_like(
  $$ select gestionar_usuario('ee700000-0000-0000-0000-000000000002', 'ee700000-0000-0000-0000-000000000002', 'DESACTIVAR_DOBLE_FACTOR') $$,
  '%exige el doble factor%', 'Un administrador no puede quitarse el doble factor');
select gestionar_usuario('ee700000-0000-0000-0000-000000000003', 'ee700000-0000-0000-0000-000000000003', 'ACTIVAR_DOBLE_FACTOR');
select pg_temp.login('e8000000-0000-0000-0000-000000000003', 'aal1');
set local role authenticated;
insert into resultados (t) select is((select count(*) from edificios), 0::bigint, 'Un técnico que activa el doble factor también necesita el código');
reset role;

do $$
declare v_total int; v_fallos int; v_detalle text;
begin
  select count(*), count(*) filter (where t like 'not ok%'),
         string_agg(split_part(t, E'\n', 1), E'\n' order by n) filter (where t like 'not ok%')
    into v_total, v_fallos, v_detalle from resultados;
  if v_fallos = 0 and v_total = 37 then
    raise exception 'RESULTADO: % de 37 pruebas OK. Todo correcto (los datos de prueba se han deshecho).', v_total;
  else
    raise exception E'RESULTADO: % pruebas ejecutadas, % FALLAN:\n%', v_total, v_fallos, coalesce(v_detalle, '(faltan pruebas)');
  end if;
end;
$$;
