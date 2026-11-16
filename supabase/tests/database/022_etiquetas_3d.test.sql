-- =========================================================
-- PRUEBAS DE ETIQUETAS 3D SIN SOLAPE (migraciones 042 y 045, D53 y D56)
-- Ejecutar con:  npx supabase test db
-- =========================================================
begin;
set search_path = public, extensions;

select plan(14);

insert into proveedores (id, codigo, nombre) values
  ('fb000000-0000-0000-0000-00000000000a', 'EA', 'Partner etiquetas A'),
  ('fb000000-0000-0000-0000-00000000000b', 'EB', 'Partner etiquetas B');
insert into clientes (id, codigo, nombre) values ('fb100000-0000-0000-0000-000000000001', 'EC', 'Cliente etiquetas');
insert into proveedores_clientes (id_proveedor, id_cliente) values
  ('fb000000-0000-0000-0000-00000000000a', 'fb100000-0000-0000-0000-000000000001');
insert into edificios (id, id_cliente, codigo, nombre, zona_horaria) values
  ('fb200000-0000-0000-0000-000000000001', 'fb100000-0000-0000-0000-000000000001', 'EE', 'Edificio etiquetas', 'Europe/Madrid');
insert into proveedores_edificios (id_proveedor, id_edificio) values
  ('fb000000-0000-0000-0000-00000000000a', 'fb200000-0000-0000-0000-000000000001');
insert into plantas (id, id_edificio, codigo, nombre, nivel, niveles_modelo) values
  ('fb300000-0000-0000-0000-000000000002', 'fb200000-0000-0000-0000-000000000001', 'P2', 'Planta 2', 2, '{L2}'),
  ('fb300000-0000-0000-0000-000000000003', 'fb200000-0000-0000-0000-000000000001', 'P3', 'Planta 3', 3, '{L3}');
insert into recintos (id, id_planta, codigo, nombre) values
  ('fb400000-0000-0000-0000-000000000002', 'fb300000-0000-0000-0000-000000000002', 'OF2', 'Oficinas 2'),
  ('fb400000-0000-0000-0000-000000000003', 'fb300000-0000-0000-0000-000000000003', 'OF3', 'Oficinas 3');
insert into conexiones (id, id_edificio, id_tipo_conexion, codigo, nombre)
select 'fb500000-0000-0000-0000-000000000001', 'fb200000-0000-0000-0000-000000000001', id, 'HTTP', 'Pasarela'
from tipos_conexion where codigo = 'ENVIO_HTTP';
-- Dispositivo ambiental con 3 sensores en la planta 3
insert into dispositivos (id, id_recinto, id_conexion, id_tipo_dispositivo, codigo, nombre)
select 'fb600000-0000-0000-0000-000000000001', 'fb400000-0000-0000-0000-000000000003', 'fb500000-0000-0000-0000-000000000001', id, 'AMB3', 'Ambiental 3'
from tipos_dispositivo where codigo = 'SENSOR_AMBIENTAL';

create function pg_temp.sensor(p_id text, p_cod text, p_rec text, p_disp text) returns void language sql as $$
  insert into sensores (id, id_conexion, id_dispositivo, id_recinto, id_familia, id_naturaleza, id_tratamiento, codigo, nombre, unidad, direccion)
  select p_id::uuid, case when p_disp is null then 'fb500000-0000-0000-0000-000000000001'::uuid end, p_disp::uuid, p_rec::uuid,
         f.id, n.id, t.id, p_cod, p_cod, '°C', jsonb_build_object('clave', p_cod)
  from familias_sensor f, naturalezas_sensor n, tratamientos_sensor t
  where f.codigo = 'TEMPERATURA' and n.codigo = 'INSTANTANEA' and t.codigo = 'PROMEDIO';
$$;
select pg_temp.sensor('fb700000-0000-0000-0000-000000000001', 'T2A', 'fb400000-0000-0000-0000-000000000002', null);
select pg_temp.sensor('fb700000-0000-0000-0000-000000000002', 'T2B', 'fb400000-0000-0000-0000-000000000002', null);
select pg_temp.sensor('fb700000-0000-0000-0000-000000000003', 'T3', 'fb400000-0000-0000-0000-000000000003', 'fb600000-0000-0000-0000-000000000001');
select pg_temp.sensor('fb700000-0000-0000-0000-000000000004', 'HR3', 'fb400000-0000-0000-0000-000000000003', 'fb600000-0000-0000-0000-000000000001');
select pg_temp.sensor('fb700000-0000-0000-0000-000000000005', 'CO23', 'fb400000-0000-0000-0000-000000000003', 'fb600000-0000-0000-0000-000000000001');
select pg_temp.sensor('fb700000-0000-0000-0000-000000000006', 'T3B', 'fb400000-0000-0000-0000-000000000003', null);

-- Modelo de 56 × 32 m con los niveles L2 (9,45 m) y L3 (12,73 m)
insert into modelos_3d (id, id_edificio, tipo_modelo, nombre, archivo, ancho_m, fondo_m, alto_m, niveles) values
  ('fb800000-0000-0000-0000-000000000001', 'fb200000-0000-0000-0000-000000000001', 'EDIFICIO', 'Torre',
   'edificios/fb200000-0000-0000-0000-000000000001/modelos/torre.glb', 56, 32, 30,
   '[{"nombre": "L2", "cota": 9.45}, {"nombre": "L3", "cota": 12.73}]');

select is(distancia_minima_etiquetas('fb800000-0000-0000-0000-000000000001', 1, 1), 7.9::numeric,
  'Distancia mínima entre etiquetas de una fila en un modelo de 56 m: 7,9 m');
select ok(distancia_minima_etiquetas('fb800000-0000-0000-0000-000000000001', 3, 1) > 7.9,
  'Una etiqueta de varias filas (dispositivo) necesita más distancia');

insert into ubicaciones_3d (id, id_modelo_3d, id_sensor, x, y, z) values
  ('fb900000-0000-0000-0000-000000000001', 'fb800000-0000-0000-0000-000000000001', 'fb700000-0000-0000-0000-000000000001', 0, 99, 0);
select is((select y from ubicaciones_3d where id = 'fb900000-0000-0000-0000-000000000001'), 10.95::numeric,
  'La altura de la etiqueta la fija la plataforma: 1,5 m sobre el nivel de la planta');

select throws_like($$ insert into ubicaciones_3d (id_modelo_3d, id_sensor, x, y, z) values
  ('fb800000-0000-0000-0000-000000000001', 'fb700000-0000-0000-0000-000000000002', 4, 0, 0) $$,
  'Valor no permitido%', 'Una etiqueta más cerca que la distancia mínima en la misma planta no se guarda');
select lives_ok($$ insert into ubicaciones_3d (id_modelo_3d, id_sensor, x, y, z) values
  ('fb800000-0000-0000-0000-000000000001', 'fb700000-0000-0000-0000-000000000002', 9, 0, 0) $$,
  'A la distancia mínima o más, sí');
select lives_ok($$ insert into ubicaciones_3d (id_modelo_3d, id_sensor, x, y, z, visible) values
  ('fb800000-0000-0000-0000-000000000001', 'fb700000-0000-0000-0000-000000000006', 3, 0, 0, false) $$,
  'Una etiqueta oculta no cuenta');
select throws_like($$ insert into ubicaciones_3d (id_modelo_3d, id_sensor, x, y, z) values
  ('fb800000-0000-0000-0000-000000000001', 'fb700000-0000-0000-0000-000000000003', 20, 0, 0) $$,
  '%coloque el dispositivo%', 'Un sensor de un dispositivo no se coloca suelto');
select lives_ok($$ insert into ubicaciones_3d (id, id_modelo_3d, id_dispositivo, x, y, z) values
  ('fb900000-0000-0000-0000-000000000003', 'fb800000-0000-0000-0000-000000000001', 'fb600000-0000-0000-0000-000000000001', 1, 0, 1) $$,
  'Otra planta: la distancia solo cuenta dentro de la misma planta');
select is((select y from ubicaciones_3d where id = 'fb900000-0000-0000-0000-000000000003'), 14.23::numeric,
  'El dispositivo toma la altura de su planta');
select is((select count(*)::integer from sensores_estado_edificio('fb200000-0000-0000-0000-000000000001')
           where id_dispositivo = 'fb600000-0000-0000-0000-000000000001' and jsonb_array_length(ubicaciones) = 1), 3,
  'Los sensores del dispositivo heredan su punto y llevan el dispositivo');

select is((select count(*)::integer from sensores_estado_edificio('fb200000-0000-0000-0000-000000000001')
           where funcion_medidor is null and tipo_energia is null and flujo_energia is null), 6,
  'El estado de los sensores incluye su función y su energía (045; aquí, sondas sin energía)');

-- Coordenadas copiadas al sustituir el modelo: no se comprueban hasta confirmarlas
update modelos_3d set ancho_m = null where id = 'fb800000-0000-0000-0000-000000000001';
update ubicaciones_3d set x = 5 where id = 'fb900000-0000-0000-0000-000000000001';
update ubicaciones_3d set por_revisar = true where id = 'fb900000-0000-0000-0000-000000000001';
select ok(true, 'Sin medidas del modelo no hay comprobación de distancia');
update modelos_3d set ancho_m = 56 where id = 'fb800000-0000-0000-0000-000000000001';
select throws_like($$ select confirmar_coordenadas('fb800000-0000-0000-0000-000000000001') $$,
  'Valor no permitido%', 'Al confirmar una coordenada copiada se comprueba la distancia');

-- Acceso: otro Partner no coloca etiquetas en el edificio
insert into auth.users (id, email) values ('e9800000-0000-0000-0000-000000000002', 'b@etiquetas.test');
insert into usuarios (id, auth_user_id, nombre, email, id_rol)
select 'fb990000-0000-0000-0000-000000000002', 'e9800000-0000-0000-0000-000000000002', 'B', 'b@etiquetas.test', r.id
from roles r where r.codigo = 'ADMIN_PARTNER';
insert into usuarios_partners (id_usuario, id_proveedor) values ('fb990000-0000-0000-0000-000000000002', 'fb000000-0000-0000-0000-00000000000b');
select set_config('request.jwt.claims', json_build_object('sub', 'e9800000-0000-0000-0000-000000000002', 'role', 'authenticated',
                  'aal', 'aal2', 'session_id', gen_random_uuid())::text, true);
set local role authenticated;
select throws_like($$ insert into ubicaciones_3d (id_modelo_3d, id_sensor, x, y, z) values
  ('fb800000-0000-0000-0000-000000000001', 'fb700000-0000-0000-0000-000000000006', 30, 0, 0) $$,
  '%', 'Otro Partner no puede colocar etiquetas en el edificio (ni siquiera ve el modelo)');
reset role;

select * from finish();
rollback;
