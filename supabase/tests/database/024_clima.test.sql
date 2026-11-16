-- =========================================================
-- PRUEBAS DEL CLIMA EXTERIOR (migración 044, D54)
-- Ejecutar con:  npx supabase test db
-- =========================================================
begin;
set search_path = public, extensions;

select plan(10);

insert into proveedores (id, codigo, nombre) values
  ('fc600000-0000-0000-0000-00000000000a', 'KA', 'Partner clima A'),
  ('fc600000-0000-0000-0000-00000000000b', 'KB', 'Partner clima B');
insert into clientes (id, codigo, nombre) values ('fc610000-0000-0000-0000-000000000001', 'KC', 'Cliente clima');
insert into proveedores_clientes (id_proveedor, id_cliente) values
  ('fc600000-0000-0000-0000-00000000000a', 'fc610000-0000-0000-0000-000000000001');
insert into edificios (id, id_cliente, codigo, nombre, zona_horaria, latitud, longitud) values
  ('fc620000-0000-0000-0000-000000000001', 'fc610000-0000-0000-0000-000000000001', 'KE', 'Edificio clima', 'Europe/Madrid', 40.41678912, -3.70379);
insert into proveedores_edificios (id_proveedor, id_edificio) values
  ('fc600000-0000-0000-0000-00000000000a', 'fc620000-0000-0000-0000-000000000001');

select is((select array[latitud, longitud] from edificios_clima_pendientes() where id_edificio = 'fc620000-0000-0000-0000-000000000001'),
  array[40.4168, -3.7038]::numeric[], 'Un edificio con coordenadas está pendiente, con 4 decimales (condición de MET Norway)');

-- Respuesta de MET Norway: la hora en curso, dos horas más y un paso de 6 horas pasado mañana
select is(guardar_clima('fc620000-0000-0000-0000-000000000001', jsonb_build_array(
    jsonb_build_object('fecha_hora', date_trunc('hour', now()), 'horas', 1, 'temperatura', 14.2, 'humedad', 71, 'viento_ms', 3.4,
                       'uv_cielo_despejado', 1.8, 'simbolo', 'partlycloudy_day', 'precipitacion_mm', 0),
    jsonb_build_object('fecha_hora', date_trunc('hour', now()) + interval '1 hour', 'horas', 1, 'temperatura', 15.0, 'simbolo', 'cloudy'),
    jsonb_build_object('fecha_hora', date_trunc('hour', now()) + interval '2 hours', 'horas', 1, 'temperatura', 15.5, 'simbolo', 'rain'),
    jsonb_build_object('fecha_hora', (date_trunc('day', now() at time zone 'Europe/Madrid') + interval '2 days 12 hours') at time zone 'Europe/Madrid',
                       'horas', 6, 'temperatura', 9.5, 'temperatura_min', 7.5, 'temperatura_max', 10, 'simbolo', 'snow', 'precipitacion_mm', 2.1)),
  now() + interval '1 hour', 'Mon, 16 Nov 2026 09:30:00 GMT'), 4, 'Se guarda la previsión');
select is((select count(*)::integer from clima_observaciones where id_edificio = 'fc620000-0000-0000-0000-000000000001'
           and fecha_hora = date_trunc('hour', now()) and temperatura = 14.2), 1, 'Y la observación de la hora en curso');
select is((select count(*)::integer from edificios_clima_pendientes() where id_edificio = 'fc620000-0000-0000-0000-000000000001'), 0,
  'Hasta que caduca, el edificio no se vuelve a consultar');

select is(clima_edificio('fc620000-0000-0000-0000-000000000001')->'ahora'->>'fuente_temperatura', 'MET_NORWAY',
  'Sin sensor exterior, la temperatura es la de MET Norway');
select is((select jsonb_agg(h->>'simbolo') from jsonb_array_elements(clima_edificio('fc620000-0000-0000-0000-000000000001')->'horas') h),
  '["cloudy", "rain"]'::jsonb, 'Próximas horas');
select is(clima_edificio('fc620000-0000-0000-0000-000000000001')->'dias'->0->>'simbolo', 'snow', 'Próximos días con su símbolo');

-- Con sensor exterior propio que comunica, se muestra su valor
insert into plantas (id, id_edificio, codigo, nombre, nivel) values
  ('fc630000-0000-0000-0000-000000000001', 'fc620000-0000-0000-0000-000000000001', 'CUB', 'Cubierta', 5);
insert into recintos (id, id_planta, codigo, nombre, tipo) values
  ('fc640000-0000-0000-0000-000000000001', 'fc630000-0000-0000-0000-000000000001', 'EXT', 'Exterior', 'ZONA_EXTERIOR');
insert into conexiones (id, id_edificio, id_tipo_conexion, codigo, nombre)
select 'fc650000-0000-0000-0000-000000000001', 'fc620000-0000-0000-0000-000000000001', id, 'HTTP', 'Pasarela'
from tipos_conexion where codigo = 'ENVIO_HTTP';
insert into sensores (id, id_conexion, id_recinto, id_familia, id_naturaleza, id_tratamiento, codigo, nombre, unidad, direccion)
select 'fc660000-0000-0000-0000-000000000001', 'fc650000-0000-0000-0000-000000000001', 'fc640000-0000-0000-0000-000000000001',
       f.id, n.id, t.id, 'TEXT', 'Temperatura exterior', '°C', '{"clave": "TEXT"}'
from familias_sensor f, naturalezas_sensor n, tratamientos_sensor t
where f.codigo = 'TEMPERATURA' and n.codigo = 'INSTANTANEA' and t.codigo = 'PROMEDIO';
insert into estado_comunicacion (id_sensor, estado, ultima_lectura, ultimo_valor)
values ('fc660000-0000-0000-0000-000000000001', 'COMUNICANDO', now(), 12.94);
select is(clima_edificio('fc620000-0000-0000-0000-000000000001')->'ahora' ->> 'temperatura', '12.9',
  'Con sensor exterior que comunica, se muestra su temperatura (la de MET Norway queda de respaldo)');

-- Acceso
insert into auth.users (id, email) values ('e9a00000-0000-0000-0000-000000000002', 'b@clima.test');
insert into usuarios (id, auth_user_id, nombre, email, id_rol)
select 'fc690000-0000-0000-0000-000000000002', 'e9a00000-0000-0000-0000-000000000002', 'B', 'b@clima.test', r.id
from roles r where r.codigo = 'ADMIN_PARTNER';
insert into usuarios_partners (id_usuario, id_proveedor) values ('fc690000-0000-0000-0000-000000000002', 'fc600000-0000-0000-0000-00000000000b');
select set_config('request.jwt.claims', json_build_object('sub', 'e9a00000-0000-0000-0000-000000000002', 'role', 'authenticated',
                  'aal', 'aal2', 'session_id', gen_random_uuid())::text, true);
set local role authenticated;
select is((select count(*)::integer from clima_observaciones), 0, 'Otro Partner no ve el clima del edificio');
select throws_ok($$ select guardar_clima('fc620000-0000-0000-0000-000000000001', '[]', now()) $$,
  '42501', null, 'Solo la API (service_role) guarda el clima');
reset role;

select * from finish();
rollback;
