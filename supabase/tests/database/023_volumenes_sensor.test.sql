-- =========================================================
-- PRUEBAS DE VOLÚMENES DE LOS RECINTOS (migración 043, D55)
-- Ejecutar con:  npx supabase test db
-- Edificio en invierno todo el año, Te 19 °C.
-- =========================================================
begin;
set search_path = public, extensions;

select plan(10);

insert into proveedores (id, codigo, nombre) values
  ('fc500000-0000-0000-0000-00000000000a', 'VA', 'Partner volúmenes A'),
  ('fc500000-0000-0000-0000-00000000000b', 'VB', 'Partner volúmenes B');
insert into clientes (id, codigo, nombre) values ('fc510000-0000-0000-0000-000000000001', 'VC', 'Cliente volúmenes');
insert into proveedores_clientes (id_proveedor, id_cliente) values
  ('fc500000-0000-0000-0000-00000000000a', 'fc510000-0000-0000-0000-000000000001');
insert into edificios (id, id_cliente, codigo, nombre, zona_horaria, invierno_desde, invierno_hasta) values
  ('fc520000-0000-0000-0000-000000000001', 'fc510000-0000-0000-0000-000000000001', 'VE', 'Edificio volúmenes', 'Europe/Madrid', '01-01', '12-31'),
  ('fc520000-0000-0000-0000-000000000002', 'fc510000-0000-0000-0000-000000000001', 'VO', 'Otro edificio', 'Europe/Madrid', '01-01', '12-31');
insert into proveedores_edificios (id_proveedor, id_edificio) values
  ('fc500000-0000-0000-0000-00000000000a', 'fc520000-0000-0000-0000-000000000001');
insert into plantas (id, id_edificio, codigo, nombre, nivel) values
  ('fc530000-0000-0000-0000-000000000001', 'fc520000-0000-0000-0000-000000000001', 'P3', 'Planta 3', 3),
  ('fc530000-0000-0000-0000-000000000002', 'fc520000-0000-0000-0000-000000000002', 'P0', 'Planta baja', 0);
insert into recintos (id, id_planta, codigo, nombre) values
  ('fc540000-0000-0000-0000-000000000001', 'fc530000-0000-0000-0000-000000000001', 'OF3', 'Oficinas 3'),
  ('fc540000-0000-0000-0000-000000000002', 'fc530000-0000-0000-0000-000000000002', 'OTRO', 'Otro recinto');
insert into conexiones (id, id_edificio, id_tipo_conexion, codigo, nombre)
select x.id::uuid, x.edif::uuid, t.id, 'HTTP', 'Pasarela'
from (values ('fc550000-0000-0000-0000-000000000001', 'fc520000-0000-0000-0000-000000000001'),
             ('fc550000-0000-0000-0000-000000000002', 'fc520000-0000-0000-0000-000000000002')) x(id, edif),
     tipos_conexion t where t.codigo = 'ENVIO_HTTP';

create function pg_temp.sensor(p_id text, p_cod text, p_rec text, p_con text, p_fam text) returns void language sql as $$
  insert into sensores (id, id_conexion, id_recinto, id_familia, id_naturaleza, id_tratamiento, codigo, nombre, unidad, direccion)
  select p_id::uuid, p_con::uuid, p_rec::uuid, f.id, n.id, t.id, p_cod, p_cod, '°C', jsonb_build_object('clave', p_cod)
  from familias_sensor f, naturalezas_sensor n, tratamientos_sensor t
  where f.codigo = p_fam and n.codigo = 'INSTANTANEA' and t.codigo = 'PROMEDIO';
$$;
select pg_temp.sensor('fc560000-0000-0000-0000-000000000001', 'T3', 'fc540000-0000-0000-0000-000000000001', 'fc550000-0000-0000-0000-000000000001', 'TEMPERATURA');
select pg_temp.sensor('fc560000-0000-0000-0000-000000000002', 'HR3', 'fc540000-0000-0000-0000-000000000001', 'fc550000-0000-0000-0000-000000000001', 'HUMEDAD');
select pg_temp.sensor('fc560000-0000-0000-0000-000000000003', 'TO', 'fc540000-0000-0000-0000-000000000002', 'fc550000-0000-0000-0000-000000000002', 'TEMPERATURA');
insert into estado_comunicacion (id_sensor, estado, ultima_lectura, ultimo_valor)
values ('fc560000-0000-0000-0000-000000000001', 'COMUNICANDO', now(), 21.2);

insert into modelos_3d (id, id_edificio, tipo_modelo, nombre, archivo) values
  ('fc570000-0000-0000-0000-000000000001', 'fc520000-0000-0000-0000-000000000001', 'EDIFICIO', 'Edificio',
   'edificios/fc520000-0000-0000-0000-000000000001/modelos/e.glb');

select lives_ok($$ insert into volumenes_sensor (id_modelo_3d, id_sensor, clave_volumen, nombre_volumen, nivel_modelo, centro_x, centro_z) values
  ('fc570000-0000-0000-0000-000000000001', 'fc560000-0000-0000-0000-000000000001', '2483002', 'Office Unit', 'L3', -18.4, -6.3) $$,
  'Un volumen del modelo se asigna a un sensor de temperatura');
select lives_ok($$ insert into volumenes_sensor (id_modelo_3d, id_sensor, clave_volumen, nombre_volumen) values
  ('fc570000-0000-0000-0000-000000000001', 'fc560000-0000-0000-0000-000000000001', '2483003', 'Corridor') $$,
  'Un sensor puede tener varios volúmenes');
select throws_like($$ insert into volumenes_sensor (id_modelo_3d, id_sensor, clave_volumen, nombre_volumen) values
  ('fc570000-0000-0000-0000-000000000001', 'fc560000-0000-0000-0000-000000000001', '2483002', 'Office Unit') $$,
  '%volumenes_sensor_volumen_uq%', 'Cada volumen pertenece a un solo sensor');
select throws_like($$ insert into volumenes_sensor (id_modelo_3d, id_sensor, clave_volumen, nombre_volumen) values
  ('fc570000-0000-0000-0000-000000000001', 'fc560000-0000-0000-0000-000000000002', '2483004', 'Studio Unit') $$,
  'Solo los sensores de temperatura%', 'Un sensor que no es de temperatura no tiene volúmenes');
select throws_like($$ insert into volumenes_sensor (id_modelo_3d, id_sensor, clave_volumen, nombre_volumen) values
  ('fc570000-0000-0000-0000-000000000001', 'fc560000-0000-0000-0000-000000000003', '2483005', 'Live/Work Unit') $$,
  'El sensor debe ser del edificio%', 'Un sensor de otro edificio no se asigna al modelo');

select is((select jsonb_agg(v->>'clave' || ':' || (v->>'estado') order by v->>'clave')
           from jsonb_array_elements(ambiente_edificio('fc520000-0000-0000-0000-000000000001')->'volumenes') v),
  '["2483002:MODERADO", "2483003:MODERADO"]'::jsonb,
  'El ambiente devuelve los volúmenes con el tramo de su sensor (21,2 °C con Te 19: moderado)');
select is(ambiente_edificio('fc520000-0000-0000-0000-000000000001')->'recintos'->0->'temperatura'->>'estado', 'MODERADO',
  'Y el recinto, el mismo tramo');
update estado_comunicacion set estado = 'SIN_COMUNICACION' where id_sensor = 'fc560000-0000-0000-0000-000000000001';
select is((ambiente_edificio('fc520000-0000-0000-0000-000000000001')->'volumenes'->0->>'estado'), null,
  'Si el sensor no comunica, el volumen va sin color');

-- Acceso: el Partner del edificio ve los volúmenes; otro Partner, no
insert into auth.users (id, email) values
  ('e9900000-0000-0000-0000-000000000001', 'a@volumenes.test'), ('e9900000-0000-0000-0000-000000000002', 'b@volumenes.test');
insert into usuarios (id, auth_user_id, nombre, email, id_rol)
select x.id::uuid, x.auth::uuid, 'U', x.mail, r.id
from (values ('fc590000-0000-0000-0000-000000000001', 'e9900000-0000-0000-0000-000000000001', 'a@volumenes.test'),
             ('fc590000-0000-0000-0000-000000000002', 'e9900000-0000-0000-0000-000000000002', 'b@volumenes.test')) x(id, auth, mail)
join roles r on r.codigo = 'ADMIN_PARTNER';
insert into usuarios_partners (id_usuario, id_proveedor) values
  ('fc590000-0000-0000-0000-000000000001', 'fc500000-0000-0000-0000-00000000000a'),
  ('fc590000-0000-0000-0000-000000000002', 'fc500000-0000-0000-0000-00000000000b');
create function pg_temp.login(p_auth uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_auth, 'role', 'authenticated', 'aal', 'aal2',
                    'session_id', gen_random_uuid())::text, true);
$$;
select pg_temp.login('e9900000-0000-0000-0000-000000000001');
set local role authenticated;
select is((select count(*)::integer from volumenes_sensor), 2, 'El Partner del edificio ve sus volúmenes');
reset role;
select pg_temp.login('e9900000-0000-0000-0000-000000000002');
set local role authenticated;
select is((select count(*)::integer from volumenes_sensor), 0, 'Otro Partner no ve los volúmenes del edificio');
reset role;

select * from finish();
rollback;
