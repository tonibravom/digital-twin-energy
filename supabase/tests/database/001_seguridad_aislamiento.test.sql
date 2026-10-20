-- =========================================================
-- PRUEBAS DE SEGURIDAD, AISLAMIENTO E INTEGRIDAD
-- Ejecutar con:  npx supabase test db
-- Todo ocurre dentro de una transacción que se deshace al final.
--
-- Escenario: Partner A (cliente A, edificio A) y Partner B
-- (cliente B, edificio B), un usuario cliente de A, un
-- administrador de plataforma, un intruso registrado sin ficha
-- interna y el rol anónimo.
-- =========================================================
begin;
set search_path = public, extensions;

select plan(47);

-- ---------------------------------------------------------
-- Datos de prueba (como postgres)
-- ---------------------------------------------------------
insert into auth.users (id, email) values
  ('e0000000-0000-0000-0000-000000000001', 'admin.a@test.local'),
  ('e0000000-0000-0000-0000-000000000002', 'admin.b@test.local'),
  ('e0000000-0000-0000-0000-000000000003', 'cliente.a@test.local'),
  ('e0000000-0000-0000-0000-000000000004', 'saas@test.local'),
  ('e0000000-0000-0000-0000-000000000005', 'intruso@test.local');

insert into proveedores (id, codigo, nombre) values
  ('a0000000-0000-0000-0000-000000000001', 'PA', 'Partner A'),
  ('b0000000-0000-0000-0000-000000000001', 'PB', 'Partner B');
insert into clientes (id, codigo, nombre) values
  ('a1000000-0000-0000-0000-000000000001', 'CA', 'Cliente A'),
  ('b1000000-0000-0000-0000-000000000001', 'CB', 'Cliente B');
insert into proveedores_clientes (id_proveedor, id_cliente) values
  ('a0000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001'),
  ('b0000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001');
insert into edificios (id, id_cliente, codigo, nombre) values
  ('a2000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'E1', 'Edificio A'),
  ('b2000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'E1', 'Edificio B');
insert into proveedores_edificios (id_proveedor, id_edificio) values
  ('a0000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000001'),
  ('b0000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001');
insert into plantas (id, id_edificio, codigo, nombre) values
  ('a3000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000001', 'P0', 'Baja A'),
  ('b3000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001', 'P0', 'Baja B');
insert into recintos (id, id_planta, codigo, nombre, tipo) values
  ('a4000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000001', 'R1', 'Nave A1', 'NAVE'),
  ('a4000000-0000-0000-0000-000000000002', 'a3000000-0000-0000-0000-000000000001', 'R2', 'Nave A2', 'NAVE'),
  ('b4000000-0000-0000-0000-000000000001', 'b3000000-0000-0000-0000-000000000001', 'R1', 'Oficina B', 'OFICINA');
insert into conexiones (id, id_edificio, id_tipo_conexion, codigo, nombre)
select x.id::uuid, x.ed::uuid, t.id, 'C1', 'Sentilo'
from (values
  ('a5000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000001'),
  ('b5000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001')) x(id, ed),
  tipos_conexion t where t.codigo = 'SENTILO';
insert into dispositivos (id, id_recinto, id_conexion, id_tipo_dispositivo, codigo, nombre)
select x.id::uuid, x.rec::uuid, x.con::uuid, t.id, 'D1', 'Contador'
from (values
  ('a6000000-0000-0000-0000-000000000001', 'a4000000-0000-0000-0000-000000000001', 'a5000000-0000-0000-0000-000000000001'),
  ('b6000000-0000-0000-0000-000000000001', 'b4000000-0000-0000-0000-000000000001', 'b5000000-0000-0000-0000-000000000001')) x(id, rec, con),
  tipos_dispositivo t where t.codigo = 'CONTADOR_ENERGIA';
insert into sensores (id, id_dispositivo, id_recinto, id_familia, id_naturaleza, id_tratamiento, codigo, nombre, unidad)
select x.id::uuid, x.dis::uuid, x.rec::uuid, f.id, n.id, t.id, 'S1', 'Energía', 'kWh'
from (values
  ('a7000000-0000-0000-0000-000000000001', 'a6000000-0000-0000-0000-000000000001', 'a4000000-0000-0000-0000-000000000001'),
  ('b7000000-0000-0000-0000-000000000001', 'b6000000-0000-0000-0000-000000000001', 'b4000000-0000-0000-0000-000000000001')) x(id, dis, rec),
  familias_sensor f, naturalezas_sensor n, tratamientos_sensor t
where f.codigo = 'ENERGIA' and n.codigo = 'ACUMULATIVA' and t.codigo = 'DELTA';
insert into lecturas (id_sensor, fecha_hora, valor)
select s, pg_catalog.date_trunc('hour', now()) - (i * interval '15 minutes'), i
from unnest(array['a7000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000001']::uuid[]) s,
     generate_series(1, 10) i;
insert into suministros (id, id_edificio, codigo, nombre, tipo) values
  ('a8000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000001', 'SUM1', 'Electricidad A', 'ELECTRICIDAD');
insert into reglas_alarma (id, id_edificio, id_sensor, codigo, nombre, condicion, umbral, id_nivel_alarma)
select x.id::uuid, x.ed::uuid, x.sen::uuid, 'R1', 'Consumo alto', 'MAYOR_QUE', 100, n.id
from (values
  ('a9000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000001', 'a7000000-0000-0000-0000-000000000001'),
  ('b9000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000001')) x(id, ed, sen),
  niveles_alarma n where n.codigo = 'AVISO';
insert into eventos_alarma (id, id_regla_alarma, id_sensor, valor_detectado) values
  ('aa000000-0000-0000-0000-000000000001', 'a9000000-0000-0000-0000-000000000001', 'a7000000-0000-0000-0000-000000000001', 150),
  ('ba000000-0000-0000-0000-000000000001', 'b9000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000001', 150);
insert into modelos_3d (id, id_edificio, tipo_modelo, nombre, archivo) values
  ('ac000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000001', 'EDIFICIO', 'General A',
   'edificios/a2000000-0000-0000-0000-000000000001/modelos/general_v1.glb');

insert into usuarios (id, auth_user_id, nombre, email, id_rol)
select x.id::uuid, x.auth::uuid, x.nom, x.mail, r.id
from (values
  ('d1000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000001', 'Admin A', 'admin.a@test.local', 'ADMIN_PARTNER'),
  ('d2000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002', 'Admin B', 'admin.b@test.local', 'ADMIN_PARTNER'),
  ('d3000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000003', 'Cliente A', 'cliente.a@test.local', 'USUARIO_CLIENTE'),
  ('d4000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000004', 'Admin SaaS', 'saas@test.local', 'ADMIN_SAAS')) x(id, auth, nom, mail, rol)
join roles r on r.codigo = x.rol;
insert into usuarios_partners (id_usuario, id_proveedor) values
  ('d1000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001'),
  ('d2000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001');
insert into usuarios_clientes (id_usuario, id_cliente) values
  ('d3000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001');

-- Simula la sesión de un usuario de Supabase Auth.
create function pg_temp.login(p_auth uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', p_auth::text, true),
         set_config('request.jwt.claims', json_build_object('sub', p_auth, 'role', 'authenticated')::text, true);
$$;

-- =========================================================
-- 1. ANÓNIMO (solo clave pública)
-- =========================================================
set local role anon;
select throws_ok($$ select * from usuarios $$, '42501', null, 'Anónimo no puede leer usuarios');
select throws_ok($$ select * from edificios $$, '42501', null, 'Anónimo no puede leer edificios');
select throws_ok($$ select * from lecturas $$, '42501', null, 'Anónimo no puede leer lecturas');
reset role;

-- =========================================================
-- 2. INTRUSO: registrado en Auth pero sin ficha interna
-- =========================================================
select pg_temp.login('e0000000-0000-0000-0000-000000000005');
set local role authenticated;
select is((select count(*) from edificios), 0::bigint, 'Intruso no ve edificios');
select throws_ok(
  $$ insert into usuarios (auth_user_id, nombre, email, id_rol)
     select 'e0000000-0000-0000-0000-000000000005', 'X', 'x@x.com', id from roles where codigo = 'ADMIN_SAAS' $$,
  '42501', null, 'Intruso no puede autoasignarse ADMIN_SAAS');
select throws_ok(
  $$ insert into usuarios_partners (id_usuario, id_proveedor)
     values ('d1000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001') $$,
  '42501', null, 'Intruso no puede crear asignaciones de partner');
select throws_ok($$ select crear_cliente_partner('X', 'X') $$, '42501', null,
  'Intruso no puede crear clientes');
reset role;

-- =========================================================
-- 3. ADMIN DEL PARTNER A
-- =========================================================
select pg_temp.login('e0000000-0000-0000-0000-000000000001');
set local role authenticated;
select results_eq($$ select nombre::text from edificios order by 1 $$, array['Edificio A'],
  'Partner A solo ve su edificio');
select results_eq($$ select nombre::text from clientes order by 1 $$, array['Cliente A'],
  'Partner A solo ve su cliente');
select is((select count(*) from sensores where id = 'b7000000-0000-0000-0000-000000000001'), 0::bigint,
  'Partner A no ve sensores de B');
select is((select count(*) from lecturas), 10::bigint, 'Partner A ve solo las 10 lecturas de su sensor');
select is((select count(*) from eventos_alarma), 1::bigint, 'Partner A ve solo sus alarmas');
select results_eq($$ select email::text from usuarios order by 1 $$, array['admin.a@test.local', 'cliente.a@test.local'],
  'Partner A ve sus usuarios y los de su cliente, no los de B');
select throws_ok(
  $$ insert into suministros (id_edificio, codigo, nombre, tipo)
     values ('b2000000-0000-0000-0000-000000000001', 'X', 'Intruso', 'GAS') $$,
  '42501', null, 'Partner A no puede crear suministros en el edificio de B');
select throws_ok(
  $$ insert into usuarios_partners (id_usuario, id_proveedor)
     values ('d1000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001') $$,
  '42501', null, 'Partner A no puede darse acceso al Partner B');
select is_empty(
  $$ update edificios set nombre = 'hackeado' where id = 'b2000000-0000-0000-0000-000000000001' returning id $$,
  'Partner A no puede modificar el edificio de B');
select throws_ok(
  $$ update edificios set id_cliente = 'b1000000-0000-0000-0000-000000000001'
     where id = 'a2000000-0000-0000-0000-000000000001' $$,
  '42501', null, 'Partner A no puede mover su edificio a otro cliente');
select isnt(crear_edificio_partner('a1000000-0000-0000-0000-000000000001', 'E2', 'Edificio A2'), null,
  'Partner A crea un edificio para su cliente con la función de alta');
select is((select count(*) from edificios where nombre = 'Edificio A2'), 1::bigint,
  'El edificio creado es visible para el Partner A');
select throws_ok(
  $$ select crear_edificio_partner('b1000000-0000-0000-0000-000000000001', 'E9', 'Ajeno') $$,
  '42501', null, 'Partner A no puede crear edificios para el cliente de B');
select throws_ok(
  $$ insert into auditoria (tabla, id_registro, accion) values ('edificios', 'x', 'BAJA') $$,
  '42501', null, 'Nadie escribe auditoría a mano');
select ok((select count(*) from auditoria where tabla = 'edificios' and accion = 'ALTA') >= 1,
  'El alta de edificio quedó auditada automáticamente');
select is((select count(*) from auditoria where id_edificio = 'b2000000-0000-0000-0000-000000000001'), 0::bigint,
  'Partner A no ve la auditoría del edificio de B');
select throws_ok($$ select reconocer_alarma('ba000000-0000-0000-0000-000000000001') $$, '42501', null,
  'Partner A no puede reconocer alarmas de B');
select lives_ok($$ select reconocer_alarma('aa000000-0000-0000-0000-000000000001', 'Revisado') $$,
  'Partner A reconoce su alarma');
select is_empty(
  $$ update eventos_alarma set valor_detectado = 0 where id = 'aa000000-0000-0000-0000-000000000001' returning id $$,
  'Los eventos no se editan directamente (solo con reconocer/cerrar)');
select ok((select count(*) from parametros_saas where codigo = 'FACTOR_CO2_ELECTRICIDAD') = 1,
  'El factor de CO2 es legible para mostrarlo junto al KPI');
select lives_ok(
  $$ insert into storage.objects (bucket_id, name)
     values ('modelos-3d', 'edificios/a2000000-0000-0000-0000-000000000001/modelos/general_v1.glb') $$,
  'Partner A sube el GLB de un modelo registrado de su edificio');
select throws_ok(
  $$ insert into storage.objects (bucket_id, name)
     values ('modelos-3d', 'edificios/b2000000-0000-0000-0000-000000000001/modelos/x.glb') $$,
  '42501', null, 'Partner A no puede subir modelos al edificio de B');
select throws_ok(
  $$ insert into storage.objects (bucket_id, name)
     values ('modelos-3d', 'edificios/a2000000-0000-0000-0000-000000000001/modelos/sin_registro.glb') $$,
  '42501', null, 'No se sube un archivo sin registro previo en modelos_3d');
reset role;

-- =========================================================
-- 4. USUARIO CLIENTE DE A, ADMIN B Y ADMIN PLATAFORMA
-- =========================================================
select pg_temp.login('e0000000-0000-0000-0000-000000000003');
set local role authenticated;
select results_eq($$ select nombre::text from edificios where id_cliente = 'a1000000-0000-0000-0000-000000000001' and codigo = 'E1' $$,
  array['Edificio A'], 'El usuario cliente ve el edificio de su cliente');
select is((select count(*) from edificios where id = 'b2000000-0000-0000-0000-000000000001'), 0::bigint,
  'El usuario cliente no ve edificios de otros clientes');
select throws_ok(
  $$ insert into plantas (id_edificio, codigo, nombre) values ('a2000000-0000-0000-0000-000000000001', 'P1', 'X') $$,
  '42501', null, 'El usuario cliente no configura plantas');
reset role;

select pg_temp.login('e0000000-0000-0000-0000-000000000002');
set local role authenticated;
select results_eq($$ select nombre::text from edificios order by 1 $$, array['Edificio B'],
  'Partner B solo ve su edificio');
reset role;

select pg_temp.login('e0000000-0000-0000-0000-000000000004');
set local role authenticated;
select ok((select count(*) from edificios) >= 2, 'El administrador de plataforma ve todos los edificios');
reset role;

-- =========================================================
-- 5. INTEGRIDAD (aunque se use la service_role)
-- =========================================================
select throws_ok(
  $$ insert into reglas_alarma (id_edificio, id_sensor, codigo, nombre, condicion, umbral, id_nivel_alarma)
     select 'a2000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000001', 'X', 'X', 'MAYOR_QUE', 1, id
     from niveles_alarma limit 1 $$,
  'P0001', null, 'Una regla no puede usar un sensor de otro edificio');
select throws_ok(
  $$ insert into suministros_dispositivos (id_suministro, id_dispositivo)
     values ('a8000000-0000-0000-0000-000000000001', 'b6000000-0000-0000-0000-000000000001') $$,
  'P0001', null, 'Un suministro no puede asociarse a un dispositivo de otro edificio');
select throws_ok(
  $$ insert into modelos_3d (id_edificio, id_recinto, tipo_modelo, nombre, archivo)
     values ('a2000000-0000-0000-0000-000000000001', 'b4000000-0000-0000-0000-000000000001', 'RECINTO', 'X',
             'recintos/b4000000-0000-0000-0000-000000000001/modelos/x.glb') $$,
  'P0001', null, 'Un modelo de recinto no puede usar un recinto de otro edificio');
select throws_ok(
  $$ insert into modelos_3d (id_edificio, tipo_modelo, nombre, archivo)
     values ('a2000000-0000-0000-0000-000000000001', 'EDIFICIO', 'X', 'otra/ruta/x.glb') $$,
  'P0001', null, 'La ruta del GLB debe seguir el formato de Storage');
select lives_ok(
  $$ insert into modelos_3d (id_edificio, id_recinto, tipo_modelo, nombre, archivo)
     values ('a2000000-0000-0000-0000-000000000001', 'a4000000-0000-0000-0000-000000000002', 'RECINTO', 'Nave A2',
             'recintos/a4000000-0000-0000-0000-000000000002/modelos/nave_a2.glb') $$,
  'Se registra un modelo 3D de recinto');
select throws_ok(
  $$ insert into ubicaciones_3d (id_modelo_3d, id_sensor, x, y, z)
     select id, 'a7000000-0000-0000-0000-000000000001', 0, 0, 0 from modelos_3d where tipo_modelo = 'RECINTO' $$,
  'P0001', null, 'Un sensor solo se ubica en el modelo del recinto donde está');
select lives_ok(
  $$ insert into plantas (id_edificio, codigo, nombre, nivel)
     values ('a2000000-0000-0000-0000-000000000001', 'S1', 'Sótano', -1) $$,
  'Se admiten sótanos (nivel negativo)');
select throws_ok(
  $$ insert into eventos_alarma (id_regla_alarma) values ('b9000000-0000-0000-0000-000000000001') $$,
  '23505', null, 'No puede haber dos eventos abiertos de la misma regla y recinto');
update dispositivos set id_recinto = 'a4000000-0000-0000-0000-000000000002'
where id = 'a6000000-0000-0000-0000-000000000001';
select is((select id_recinto from sensores where id = 'a7000000-0000-0000-0000-000000000001'),
  'a4000000-0000-0000-0000-000000000002'::uuid, 'Mover un dispositivo mueve sus sensores');
select throws_ok(
  $$ select instalar_administrador('e0000000-0000-0000-0000-000000000005', 'Otro', 'otro@x.com') $$,
  'P0001', null, 'No se puede instalar un segundo administrador por la puerta de instalación');
select throws_ok(
  $$ insert into lecturas (id_sensor, fecha_hora, valor)
     values ('a7000000-0000-0000-0000-000000000001', '2000-01-01 00:00+00', 1) $$,
  '23514', null, 'No se guardan lecturas fuera de las particiones (anteriores a la retención)');
select is((select count(*) from verificar_rls()), 0::bigint, 'Todas las tablas de public tienen RLS');

select * from finish();
rollback;
