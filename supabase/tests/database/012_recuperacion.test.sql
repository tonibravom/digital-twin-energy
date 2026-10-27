-- =========================================================
-- PRUEBAS DE RECUPERACIÓN DE CONTRASEÑA (migración 030)
-- Ejecutar con:  npx supabase test db
-- =========================================================
begin;
set search_path = public, extensions;

select plan(11);

insert into auth.users (id, email) values
  ('ea000000-0000-0000-0000-000000000001', 'olvido@r.test'),
  ('ea000000-0000-0000-0000-000000000002', 'baja@r.test');
insert into usuarios (id, auth_user_id, nombre, email, id_rol, debe_cambiar_contrasena)
select 'fa000000-0000-0000-0000-000000000001', 'ea000000-0000-0000-0000-000000000001', 'Ana', 'olvido@r.test', id, true
from roles where codigo = 'USUARIO_CLIENTE';
insert into usuarios (id, auth_user_id, nombre, email, id_rol, activo, fecha_baja)
select 'fa000000-0000-0000-0000-000000000002', 'ea000000-0000-0000-0000-000000000002', 'Baja', 'baja@r.test', id, false, current_date
from roles where codigo = 'USUARIO_CLIENTE';

select ok(crear_codigo_recuperacion('OLVIDO@r.test ', '123456') ->> 'nombre' = 'Ana',
  'Se crea un código para un usuario activo (email sin distinguir mayúsculas)');
select ok(crear_codigo_recuperacion('nadie@r.test', '123456') is null, 'Para un email inexistente no se crea nada');
select ok(crear_codigo_recuperacion('baja@r.test', '123456') is null, 'Ni para un usuario dado de baja');
select ok((select codigo_hash <> '123456' from codigos_recuperacion where auth_user_id = 'ea000000-0000-0000-0000-000000000001'),
  'El código se guarda cifrado');
select throws_ok($$ set local role authenticated; select crear_codigo_recuperacion('olvido@r.test', '1') $$, '42501', null,
  'Los usuarios no pueden usar estas funciones');
reset role;

select is(usar_codigo_recuperacion('olvido@r.test', '000000') ->> 'resultado', 'INCORRECTO', 'Un código erróneo no sirve');
select is(usar_codigo_recuperacion('olvido@r.test', '123456') ->> 'resultado', 'OK', 'El código correcto se acepta');
select ok(not (select debe_cambiar_contrasena from usuarios where id = 'fa000000-0000-0000-0000-000000000001'),
  'Quien recupera la contraseña ya no tiene que cambiarla al entrar');
select is(usar_codigo_recuperacion('olvido@r.test', '123456') ->> 'resultado', 'NO_VALIDO', 'Un código solo se usa una vez');

select crear_codigo_recuperacion('olvido@r.test', '222222');
update codigos_recuperacion set expira_at = now() - interval '1 minute'
 where auth_user_id = 'ea000000-0000-0000-0000-000000000001' and usado_at is null and not anulado;
select is(usar_codigo_recuperacion('olvido@r.test', '222222') ->> 'resultado', 'NO_VALIDO', 'Un código caducado no sirve');
select ok(crear_codigo_recuperacion('olvido@r.test', '333333') is not null
          and crear_codigo_recuperacion('olvido@r.test', '444444') is null, 'Máximo 3 códigos por hora');

select * from finish();
rollback;
