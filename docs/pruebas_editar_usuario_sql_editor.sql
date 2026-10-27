-- VERSIÓN PARA EL SQL EDITOR DE SUPABASE: pegar entero y pulsar Run.
-- Al final sale un mensaje en ROJO a propósito con el resumen;
-- al ser un error, deshace todos los datos de prueba.
-- =========================================================
-- PRUEBAS DE EDICIÓN DE USUARIOS (migración 031)
-- Ejecutar con:  npx supabase test db
-- =========================================================
begin;
set search_path = public, extensions;

create temp table resultados (n serial, t text);
grant all on resultados to public;
grant all on sequence resultados_n_seq to public;
select plan(21);

insert into auth.users (id, email) values
  ('e9000000-0000-0000-0000-000000000001', 'saas@e.test'),
  ('e9000000-0000-0000-0000-000000000002', 'adminA@e.test'),
  ('e9000000-0000-0000-0000-000000000003', 'tecA@e.test'),
  ('e9000000-0000-0000-0000-000000000004', 'adminB@e.test'),
  ('e9000000-0000-0000-0000-000000000005', 'clienteA@e.test'),
  ('e9000000-0000-0000-0000-000000000006', 'tecA2@e.test'),
  ('e9000000-0000-0000-0000-000000000007', 'bajaA@e.test');

insert into proveedores (id, codigo, nombre) values
  ('ef000000-0000-0000-0000-00000000000a', 'EA', 'Partner A'),
  ('ef000000-0000-0000-0000-00000000000b', 'EB', 'Partner B');
insert into clientes (id, codigo, nombre) values
  ('ef100000-0000-0000-0000-00000000000a', 'CEA', 'Cliente A'),
  ('ef100000-0000-0000-0000-00000000000b', 'CEB', 'Cliente B');
insert into proveedores_clientes (id_proveedor, id_cliente) values
  ('ef000000-0000-0000-0000-00000000000a', 'ef100000-0000-0000-0000-00000000000a'),
  ('ef000000-0000-0000-0000-00000000000b', 'ef100000-0000-0000-0000-00000000000b');
insert into edificios (id, id_cliente, codigo, nombre) values
  ('ef200000-0000-0000-0000-00000000000a', 'ef100000-0000-0000-0000-00000000000a', 'EEA1', 'Edificio A1'),
  ('ef200000-0000-0000-0000-0000000000a2', 'ef100000-0000-0000-0000-00000000000a', 'EEA2', 'Edificio A2'),
  ('ef200000-0000-0000-0000-00000000000b', 'ef100000-0000-0000-0000-00000000000b', 'EEB', 'Edificio B');
insert into proveedores_edificios (id_proveedor, id_edificio) values
  ('ef000000-0000-0000-0000-00000000000a', 'ef200000-0000-0000-0000-00000000000a'),
  ('ef000000-0000-0000-0000-00000000000a', 'ef200000-0000-0000-0000-0000000000a2'),
  ('ef000000-0000-0000-0000-00000000000b', 'ef200000-0000-0000-0000-00000000000b');

insert into usuarios (id, auth_user_id, nombre, email, id_rol)
select x.id::uuid, x.auth::uuid, 'U', x.mail, r.id
from (values
  ('ef700000-0000-0000-0000-000000000001', 'e9000000-0000-0000-0000-000000000001', 'saas@e.test', 'ADMIN_SAAS'),
  ('ef700000-0000-0000-0000-000000000002', 'e9000000-0000-0000-0000-000000000002', 'admina@e.test', 'ADMIN_PARTNER'),
  ('ef700000-0000-0000-0000-000000000003', 'e9000000-0000-0000-0000-000000000003', 'teca@e.test', 'TECNICO_PARTNER'),
  ('ef700000-0000-0000-0000-000000000004', 'e9000000-0000-0000-0000-000000000004', 'adminb@e.test', 'ADMIN_PARTNER'),
  ('ef700000-0000-0000-0000-000000000005', 'e9000000-0000-0000-0000-000000000005', 'clientea@e.test', 'USUARIO_CLIENTE'),
  ('ef700000-0000-0000-0000-000000000006', 'e9000000-0000-0000-0000-000000000006', 'teca2@e.test', 'TECNICO_PARTNER'),
  ('ef700000-0000-0000-0000-000000000007', 'e9000000-0000-0000-0000-000000000007', 'bajaa@e.test', 'USUARIO_CLIENTE')) x(id, auth, mail, rol)
join roles r on r.codigo = x.rol;
insert into usuarios_partners (id_usuario, id_proveedor) values
  ('ef700000-0000-0000-0000-000000000002', 'ef000000-0000-0000-0000-00000000000a'),
  ('ef700000-0000-0000-0000-000000000003', 'ef000000-0000-0000-0000-00000000000a'),
  ('ef700000-0000-0000-0000-000000000004', 'ef000000-0000-0000-0000-00000000000b'),
  ('ef700000-0000-0000-0000-000000000006', 'ef000000-0000-0000-0000-00000000000a');
insert into usuarios_clientes (id_usuario, id_cliente) values
  ('ef700000-0000-0000-0000-000000000005', 'ef100000-0000-0000-0000-00000000000a'),
  ('ef700000-0000-0000-0000-000000000007', 'ef100000-0000-0000-0000-00000000000a');
update usuarios set activo = false, fecha_baja = current_date where id = 'ef700000-0000-0000-0000-000000000007';

create function pg_temp.login(p_auth uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', p_auth::text, true),
         set_config('request.jwt.claims', json_build_object('sub', p_auth, 'role', 'authenticated', 'aal', 'aal2',
                    'session_id', gen_random_uuid())::text, true);
$$;

-- =========================================================
-- 1. Datos personales y rol dentro del mismo tipo
-- =========================================================
insert into resultados (t) select is(modificar_usuario('ef700000-0000-0000-0000-000000000002', 'ef700000-0000-0000-0000-000000000005',
            ' Laura ', 'Puig', '600 000 000'),
  'ef700000-0000-0000-0000-000000000005'::uuid, 'El administrador del Partner edita los datos de un usuario de su cliente');
insert into resultados (t) select is((select nombre || '|' || apellidos || '|' || telefono from usuarios where id = 'ef700000-0000-0000-0000-000000000005'),
  'Laura|Puig|600 000 000', 'Los datos quedan guardados (sin espacios sobrantes)');

select modificar_usuario('ef700000-0000-0000-0000-000000000002', 'ef700000-0000-0000-0000-000000000005',
  'Laura', 'Puig', '', 'SOLO_LECTURA');
insert into resultados (t) select is((select r.codigo::text from usuarios u join roles r on r.id = u.id_rol where u.id = 'ef700000-0000-0000-0000-000000000005'),
  'SOLO_LECTURA', 'El rol cambia dentro de los roles de cliente');
insert into resultados (t) select is((select telefono from usuarios where id = 'ef700000-0000-0000-0000-000000000005'), null,
  'Un teléfono vacío se guarda como vacío');

insert into resultados (t) select throws_like(
  $$ select modificar_usuario('ef700000-0000-0000-0000-000000000002', 'ef700000-0000-0000-0000-000000000005',
       'Laura', null, null, 'TECNICO_PARTNER') $$,
  '%mismo tipo%', 'Un usuario de cliente no pasa a ser de Partner');

insert into resultados (t) select throws_like(
  $$ select modificar_usuario('ef700000-0000-0000-0000-000000000002', 'ef700000-0000-0000-0000-000000000005',
       '  ', null, null) $$,
  '%nombre es obligatorio%', 'El nombre es obligatorio');

-- =========================================================
-- 2. Quién puede editar a quién
-- =========================================================
insert into resultados (t) select throws_ok(
  $$ select modificar_usuario('ef700000-0000-0000-0000-000000000004', 'ef700000-0000-0000-0000-000000000005',
       'X', null, null) $$,
  '42501', null, 'El administrador de otro Partner NO edita a usuarios de clientes ajenos');

insert into resultados (t) select throws_ok(
  $$ select modificar_usuario('ef700000-0000-0000-0000-000000000003', 'ef700000-0000-0000-0000-000000000002',
       'X', null, null) $$,
  '42501', null, 'Un técnico NO edita a su administrador');

insert into resultados (t) select throws_ok(
  $$ select modificar_usuario('ef700000-0000-0000-0000-000000000003', 'ef700000-0000-0000-0000-000000000006',
       'U', null, null, 'ADMIN_PARTNER') $$,
  '42501', null, 'Un técnico NO asciende a otro técnico a administrador');

select modificar_usuario('ef700000-0000-0000-0000-000000000002', 'ef700000-0000-0000-0000-000000000006',
  'U', null, null, 'ADMIN_PARTNER');
insert into resultados (t) select is((select r.codigo::text from usuarios u join roles r on r.id = u.id_rol where u.id = 'ef700000-0000-0000-0000-000000000006'),
  'ADMIN_PARTNER', 'El administrador del Partner sí asciende a un técnico de su Partner');

insert into resultados (t) select throws_like(
  $$ select modificar_usuario('ef700000-0000-0000-0000-000000000002', 'ef700000-0000-0000-0000-000000000007',
       'U', null, null) $$,
  '%dado de baja%', 'Un usuario dado de baja no se edita sin reactivarlo');

insert into resultados (t) select throws_ok(
  $$ select modificar_usuario('ef700000-0000-0000-0000-000000000005', 'ef700000-0000-0000-0000-000000000005',
       'Yo', null, null) $$,
  '42501', null, 'Un usuario de cliente no puede modificar usuarios, ni el suyo');

-- =========================================================
-- 3. Uno mismo: solo datos personales
-- =========================================================
select modificar_usuario('ef700000-0000-0000-0000-000000000002', 'ef700000-0000-0000-0000-000000000002',
  'Ana', 'Admin', null);
insert into resultados (t) select is((select nombre from usuarios where id = 'ef700000-0000-0000-0000-000000000002'), 'Ana',
  'Un administrador cambia sus propios datos personales');
insert into resultados (t) select throws_ok(
  $$ select modificar_usuario('ef700000-0000-0000-0000-000000000002', 'ef700000-0000-0000-0000-000000000002',
       'Ana', null, null, 'TECNICO_PARTNER') $$,
  '42501', null, 'Nadie cambia su propio rol');

-- =========================================================
-- 4. Asignaciones
-- =========================================================
select modificar_usuario('ef700000-0000-0000-0000-000000000002', 'ef700000-0000-0000-0000-000000000005',
  'Laura', 'Puig', null, null, 'RESTRINGIDO',
  array['ef100000-0000-0000-0000-00000000000a']::uuid[], array['ef200000-0000-0000-0000-00000000000a']::uuid[]);
insert into resultados (t) select is((select tipo_alcance::text || ':' || (select count(*) from usuarios_edificios
                                                where id_usuario = 'ef700000-0000-0000-0000-000000000005' and activo)
           from usuarios_clientes where id_usuario = 'ef700000-0000-0000-0000-000000000005' and activo),
  'RESTRINGIDO:1', 'El usuario de cliente pasa a restringido con un edificio');

select pg_temp.login('e9000000-0000-0000-0000-000000000005');
set local role authenticated;
insert into resultados (t) select is((select count(*) from edificios where id_cliente = 'ef100000-0000-0000-0000-00000000000a'), 1::bigint,
  'Restringido: solo ve el edificio indicado de su cliente (RLS)');
reset role;

insert into resultados (t) select throws_like(
  $$ select modificar_usuario('ef700000-0000-0000-0000-000000000002', 'ef700000-0000-0000-0000-000000000005',
       'Laura', null, null, null, 'RESTRINGIDO',
       array['ef100000-0000-0000-0000-00000000000a']::uuid[], array['ef200000-0000-0000-0000-00000000000b']::uuid[]) $$,
  '%no pertenece%', 'No se asigna un edificio de otro cliente');

insert into resultados (t) select throws_ok(
  $$ select modificar_usuario('ef700000-0000-0000-0000-000000000002', 'ef700000-0000-0000-0000-000000000005',
       'Laura', null, null, null, 'MASTER',
       array['ef100000-0000-0000-0000-00000000000a', 'ef100000-0000-0000-0000-00000000000b']::uuid[], null) $$,
  '42501', null, 'El Partner NO asigna un cliente de otro Partner');

select modificar_usuario('ef700000-0000-0000-0000-000000000002', 'ef700000-0000-0000-0000-000000000005',
  'Laura', 'Puig', null, null, 'MASTER', array['ef100000-0000-0000-0000-00000000000a']::uuid[], null);
insert into resultados (t) select is((select count(*) from usuarios_edificios where id_usuario = 'ef700000-0000-0000-0000-000000000005' and activo),
  0::bigint, 'Al volver a MASTER se desactivan los edificios (queda el histórico)');

select modificar_usuario('ef700000-0000-0000-0000-000000000001', 'ef700000-0000-0000-0000-000000000003',
  'U', null, null, null, 'RESTRINGIDO', null, array['ef200000-0000-0000-0000-0000000000a2']::uuid[]);
insert into resultados (t) select is((select tipo_alcance::text from usuarios_partners where id_usuario = 'ef700000-0000-0000-0000-000000000003' and activo),
  'RESTRINGIDO', 'El administrador de la plataforma restringe a un técnico a un edificio de su Partner');

-- =========================================================
-- 5. Solo la API
-- =========================================================
select pg_temp.login('e9000000-0000-0000-0000-000000000002');
set local role authenticated;
insert into resultados (t) select throws_ok(
  $$ select modificar_usuario('ef700000-0000-0000-0000-000000000002', 'ef700000-0000-0000-0000-000000000005',
       'X', null, null) $$,
  '42501', null, 'Desde el navegador no se puede llamar a modificar_usuario');
reset role;

do $$
declare v_total int; v_fallos int; v_detalle text;
begin
  select count(*), count(*) filter (where t like 'not ok%'),
         string_agg(split_part(t, E'\n', 1), E'\n' order by n) filter (where t like 'not ok%')
    into v_total, v_fallos, v_detalle from resultados;
  if v_fallos = 0 and v_total = 21 then
    raise exception 'RESULTADO: % de 21 pruebas OK. Todo correcto (los datos de prueba se han deshecho).', v_total;
  else
    raise exception E'RESULTADO: % pruebas ejecutadas, % FALLAN:\n%', v_total, v_fallos, coalesce(v_detalle, '(faltan pruebas)');
  end if;
end;
$$;
