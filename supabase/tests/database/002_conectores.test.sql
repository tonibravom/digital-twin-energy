-- =========================================================
-- PRUEBAS DE CONECTORES Y PARAMETRIZACIÓN (migración 021)
-- Ejecutar con:  npx supabase test db
-- =========================================================
begin;
set search_path = public, extensions;

select plan(51);

-- ---------------------------------------------------------
-- Datos de prueba
-- ---------------------------------------------------------
insert into auth.users (id, email) values
  ('e1000000-0000-0000-0000-000000000001', 'a@conectores.test'),
  ('e1000000-0000-0000-0000-000000000002', 'b@conectores.test');
insert into proveedores (id, codigo, nombre) values
  ('c0000000-0000-0000-0000-00000000000a', 'IOT_A', 'IoT A'),
  ('c0000000-0000-0000-0000-00000000000b', 'IOT_B', 'IoT B');
insert into clientes (id, codigo, nombre) values
  ('c1000000-0000-0000-0000-00000000000a', 'CLA', 'Cliente A'),
  ('c1000000-0000-0000-0000-00000000000b', 'CLB', 'Cliente B');
insert into proveedores_clientes (id_proveedor, id_cliente) values
  ('c0000000-0000-0000-0000-00000000000a', 'c1000000-0000-0000-0000-00000000000a'),
  ('c0000000-0000-0000-0000-00000000000b', 'c1000000-0000-0000-0000-00000000000b');
insert into edificios (id, id_cliente, codigo, nombre) values
  ('c2000000-0000-0000-0000-00000000000a', 'c1000000-0000-0000-0000-00000000000a', 'E', 'Edificio A'),
  ('c2000000-0000-0000-0000-00000000000b', 'c1000000-0000-0000-0000-00000000000b', 'E', 'Edificio B');
insert into proveedores_edificios (id_proveedor, id_edificio) values
  ('c0000000-0000-0000-0000-00000000000a', 'c2000000-0000-0000-0000-00000000000a'),
  ('c0000000-0000-0000-0000-00000000000b', 'c2000000-0000-0000-0000-00000000000b');
insert into plantas (id, id_edificio, codigo, nombre) values
  ('c3000000-0000-0000-0000-00000000000a', 'c2000000-0000-0000-0000-00000000000a', 'P0', 'PB'),
  ('c3000000-0000-0000-0000-00000000000b', 'c2000000-0000-0000-0000-00000000000b', 'P0', 'PB');
insert into recintos (id, id_planta, codigo, nombre) values
  ('c4000000-0000-0000-0000-00000000000a', 'c3000000-0000-0000-0000-00000000000a', 'R', 'Sala'),
  ('c4000000-0000-0000-0000-00000000000b', 'c3000000-0000-0000-0000-00000000000b', 'R', 'Sala');
insert into usuarios (id, auth_user_id, nombre, email, id_rol)
select x.id::uuid, x.auth::uuid, 'U', x.mail, r.id
from (values
  ('c5000000-0000-0000-0000-00000000000a', 'e1000000-0000-0000-0000-000000000001', 'a@conectores.test'),
  ('c5000000-0000-0000-0000-00000000000b', 'e1000000-0000-0000-0000-000000000002', 'b@conectores.test')) x(id, auth, mail)
join roles r on r.codigo = 'ADMIN_PARTNER';
insert into usuarios_partners (id_usuario, id_proveedor) values
  ('c5000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-00000000000a'),
  ('c5000000-0000-0000-0000-00000000000b', 'c0000000-0000-0000-0000-00000000000b');

-- Conexión de envío HTTP en el edificio A, con fechas locales de Madrid
insert into conexiones (id, id_edificio, id_tipo_conexion, codigo, nombre, zona_horaria_origen)
select 'c6000000-0000-0000-0000-00000000000a', 'c2000000-0000-0000-0000-00000000000a', id, 'HTTP', 'Gateway A', 'Europe/Madrid'
from tipos_conexion where codigo = 'ENVIO_HTTP';
-- Conexión Modbus en el edificio B
insert into conexiones (id, id_edificio, id_tipo_conexion, codigo, nombre, configuracion)
select 'c6000000-0000-0000-0000-00000000000b', 'c2000000-0000-0000-0000-00000000000b', id, 'MB', 'Modbus B',
       '{"host": "192.168.1.50", "puerto": 502, "id_unidad": 1}'::jsonb
from tipos_conexion where codigo = 'MODBUS_TCP';

create function pg_temp.login(p_auth uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', p_auth::text, true),
         set_config('request.jwt.claims', json_build_object('sub', p_auth, 'role', 'authenticated')::text, true);
$$;

-- =========================================================
-- 1. VALIDACIÓN DE LA CONFIGURACIÓN
-- =========================================================
select throws_like(
  $$ insert into conexiones (id_edificio, id_tipo_conexion, codigo, nombre, configuracion)
     select 'c2000000-0000-0000-0000-00000000000a', id, 'X1', 'X', '{"host": "1.2.3.4"}'
     from tipos_conexion where codigo = 'MODBUS_TCP' $$,
  '%Faltan parámetros obligatorios%', 'Una conexión Modbus exige puerto e id_unidad');
select throws_like(
  $$ insert into conexiones (id_edificio, id_tipo_conexion, codigo, nombre, configuracion)
     select 'c2000000-0000-0000-0000-00000000000a', id, 'X2', 'X',
            '{"url": "https://x", "autenticacion": "BASIC", "ruta_lista": "$", "campo_fecha": "t", "password": "1234"}'
     from tipos_conexion where codigo = 'API_REST' $$,
  '%no puede contener secretos%', 'No se admiten contraseñas en la configuración');
select throws_like(
  $$ update conexiones set zona_horaria_origen = 'Marte/Olympus' where id = 'c6000000-0000-0000-0000-00000000000a' $$,
  '%Zona horaria no válida%', 'La zona horaria del origen se valida');

-- =========================================================
-- 2. PLANTILLAS
-- =========================================================
select ok(exists (select 1 from plantillas_dispositivo where codigo = 'EJEMPLO_ENVIO_CONTADOR' and id_proveedor is null),
  'Existe la plantilla global de ejemplo');

select lives_ok(
  $$ select crear_dispositivo_desde_plantilla(
       (select id from plantillas_dispositivo where codigo = 'EJEMPLO_ENVIO_CONTADOR'),
       'c4000000-0000-0000-0000-00000000000a', 'c6000000-0000-0000-0000-00000000000a',
       'CONT-01', 'Contador general') $$,
  'Se crea un dispositivo desde la plantilla');
select is((select count(*) from sensores s join dispositivos d on d.id = s.id_dispositivo where d.codigo = 'CONT-01'),
  2::bigint, 'La plantilla crea sus 2 sensores');
select is((select direccion->>'clave' from sensores where codigo = 'CONT-01.energia_importada'),
  'CONT-01/energia_importada', 'La clave de envío se prefija con el código del dispositivo');
select is((select escala from sensores where codigo = 'CONT-01.energia_importada'),
  0.001::float8, 'La escala Wh→kWh se copia de la plantilla');
select throws_like(
  $$ select crear_dispositivo_desde_plantilla(
       (select id from plantillas_dispositivo where codigo = 'EJEMPLO_ENVIO_CONTADOR'),
       'c4000000-0000-0000-0000-00000000000b', 'c6000000-0000-0000-0000-00000000000b', 'X', 'X') $$,
  '%no es del tipo que requiere la plantilla%', 'Una plantilla de envío HTTP no se aplica a una conexión Modbus');

-- =========================================================
-- 3. DIRECCIONES DE LOS SENSORES
-- =========================================================
insert into dispositivos (id, id_recinto, id_conexion, id_tipo_dispositivo, codigo, nombre)
select 'c7000000-0000-0000-0000-00000000000b', 'c4000000-0000-0000-0000-00000000000b',
       'c6000000-0000-0000-0000-00000000000b', id, 'AN-1', 'Analizador'
from tipos_dispositivo where codigo = 'CONTADOR_ENERGIA';

select throws_like(
  $$ insert into sensores (id_dispositivo, id_recinto, id_familia, id_naturaleza, id_tratamiento, codigo, nombre, unidad, direccion)
     select 'c7000000-0000-0000-0000-00000000000b', 'c4000000-0000-0000-0000-00000000000b', f.id, n.id, t.id, 'S1', 'S', 'V',
            '{"registro": 3000}'
     from familias_sensor f, naturalezas_sensor n, tratamientos_sensor t
     where f.codigo = 'TENSION' and n.codigo = 'INSTANTANEA' and t.codigo = 'PROMEDIO' $$,
  '%Faltan datos de la dirección%', 'Un punto Modbus exige tipo de registro y tipo de dato');
select lives_ok(
  $$ insert into sensores (id_dispositivo, id_recinto, id_familia, id_naturaleza, id_tratamiento, codigo, nombre, unidad, direccion)
     select 'c7000000-0000-0000-0000-00000000000b', 'c4000000-0000-0000-0000-00000000000b', f.id, n.id, t.id, 'S1', 'S', 'V',
            '{"registro": 3000, "tipo_registro": "HOLDING", "tipo_dato": "FLOAT32"}'
     from familias_sensor f, naturalezas_sensor n, tratamientos_sensor t
     where f.codigo = 'TENSION' and n.codigo = 'INSTANTANEA' and t.codigo = 'PROMEDIO' $$,
  'Un punto Modbus completo se acepta');
select throws_like(
  $$ insert into sensores (id_dispositivo, id_recinto, id_familia, id_naturaleza, id_tratamiento, codigo, nombre, unidad, direccion)
     select 'c7000000-0000-0000-0000-00000000000b', 'c4000000-0000-0000-0000-00000000000b', f.id, n.id, t.id, 'S2', 'S', 'V',
            '{"registro": 3000, "tipo_registro": "HOLDING", "tipo_dato": "FLOAT32"}'
     from familias_sensor f, naturalezas_sensor n, tratamientos_sensor t
     where f.codigo = 'TENSION' and n.codigo = 'INSTANTANEA' and t.codigo = 'PROMEDIO' $$,
  '%misma dirección%', 'Dos sensores no pueden leer el mismo punto de la misma conexión');

-- Sensor de temperatura con rango válido y política "mantener último"
insert into sensores (id, id_conexion, id_recinto, id_familia, id_naturaleza, id_tratamiento, codigo, nombre, unidad,
                      direccion, valor_minimo, valor_maximo, politica_vacios)
select 'c8000000-0000-0000-0000-00000000000a', 'c6000000-0000-0000-0000-00000000000a', 'c4000000-0000-0000-0000-00000000000a',
       f.id, n.id, t.id, 'TEMP-01', 'Temperatura sala', '°C', '{"clave": "TEMP-01"}', -20, 60, 'MANTENER_ULTIMO'
from familias_sensor f, naturalezas_sensor n, tratamientos_sensor t
where f.codigo = 'TEMPERATURA' and n.codigo = 'INSTANTANEA' and t.codigo = 'PROMEDIO';

-- =========================================================
-- 4. PROCESAMIENTO DE LECTURAS (canal único)
-- =========================================================
create temp table r as
select procesar_lecturas('c6000000-0000-0000-0000-00000000000a', jsonb_build_array(
  jsonb_build_object('clave', 'CONT-01/energia_importada', 'fecha_hora', to_char((date_trunc('hour', now()) - interval '1 hour') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'), 'valor', 1500000),
  jsonb_build_object('clave', 'CONT-01/energia_importada', 'fecha_hora', to_char((date_trunc('hour', now()) - interval '1 hour') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'), 'valor', 1500000),
  jsonb_build_object('clave', 'CONT-01/potencia_activa', 'fecha_hora', to_char(date_trunc('hour', now() at time zone 'Europe/Madrid') - interval '1 hour', 'YYYY-MM-DD HH24:MI'), 'valor', '2500,5'),
  jsonb_build_object('clave', 'TEMP-01', 'fecha_hora', to_char((date_trunc('hour', now()) - interval '2 hour') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'), 'valor', 21.5),
  jsonb_build_object('clave', 'TEMP-01', 'fecha_hora', to_char((date_trunc('hour', now()) - interval '1 hour') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'), 'valor', null),
  jsonb_build_object('clave', 'TEMP-01', 'fecha_hora', to_char((date_trunc('hour', now()) - interval '30 minutes') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'), 'valor', 999),
  jsonb_build_object('clave', 'NO-EXISTE', 'fecha_hora', now()::text, 'valor', 1),
  jsonb_build_object('clave', 'TEMP-01', 'fecha_hora', 'ayer por la tarde', 'valor', 20),
  jsonb_build_object('clave', 'TEMP-01', 'fecha_hora', '2001-01-01T00:00:00Z', 'valor', 20)
)) as resumen;

select is((select (resumen->>'recibidas')::int from r), 9, 'Se reciben 9 lecturas');
select is((select (resumen->>'guardadas')::int from r), 4, 'Se guardan 4 válidas (incluida la vacía rellenada con la anterior)');
select is((select (resumen->>'duplicadas')::int from r), 1, 'La lectura repetida se detecta como duplicada');
select is((select (resumen->>'rechazadas')::int from r), 4, 'Se rechazan 4 (punto desconocido, fecha inválida, fecha antigua, fuera de rango)');
select ok((select resumen->'detalle_rechazos' @> '[{"motivo": "punto desconocido en esta conexión"}]' from r),
  'El rechazo explica el motivo');
select is((select valor from lecturas l join sensores s on s.id = l.id_sensor where s.codigo = 'CONT-01.energia_importada'),
  1500::float8, 'Escala aplicada: 1.500.000 Wh se guardan como 1.500 kWh');
select is((select fecha_hora from lecturas l join sensores s on s.id = l.id_sensor where s.codigo = 'CONT-01.potencia_activa'),
  date_trunc('hour', now()) - interval '1 hour', 'Una fecha sin zona se interpreta en la zona horaria del origen (Madrid)');
select is((select valor from lecturas l join sensores s on s.id = l.id_sensor where s.codigo = 'CONT-01.potencia_activa'),
  2.5005::float8, 'Se aceptan números con coma decimal y se aplica la escala W→kW');
select is((select valor from lecturas where id_sensor = 'c8000000-0000-0000-0000-00000000000a'
           and fecha_hora = date_trunc('hour', now()) - interval '1 hour'),
  21.5::float8, 'Un valor vacío con política MANTENER_ULTIMO toma la lectura anterior');
select is((select estado from estado_comunicacion where id_sensor = 'c8000000-0000-0000-0000-00000000000a'),
  'COMUNICANDO', 'El estado de comunicación del sensor se actualiza');
select ok((select ultimo_ok is not null and ultimo_error is not null from conexiones where id = 'c6000000-0000-0000-0000-00000000000a'),
  'La conexión registra su última ejecución y los rechazos');

select is((select ultimo_valor from estado_comunicacion e join sensores s on s.id = e.id_sensor where s.codigo = 'CONT-01.energia_importada'),
  1500::float8, 'Se guarda el valor actual del sensor (para etiquetas 3D y paneles)');
select is((select umbral_minutos from estado_comunicacion where id_sensor = 'c8000000-0000-0000-0000-00000000000a'),
  30, 'El umbral de comunicación se toma de parametros_saas');

-- Pérdida y recuperación de comunicación
update estado_comunicacion set ultima_lectura = now() - interval '2 hours'
where id_sensor = 'c8000000-0000-0000-0000-00000000000a';
select ok(revisar_comunicacion() >= 1, 'La revisión detecta sensores sin comunicación');
select is((select estado from estado_comunicacion where id_sensor = 'c8000000-0000-0000-0000-00000000000a'),
  'SIN_COMUNICACION', 'El sensor pasa a SIN_COMUNICACION');
select is((select count(*) from incidencias_comunicacion where id_sensor = 'c8000000-0000-0000-0000-00000000000a' and estado = 'ABIERTA'),
  1::bigint, 'Se abre una incidencia de comunicación');
select is((select (procesar_lecturas('c6000000-0000-0000-0000-00000000000a', jsonb_build_array(
            jsonb_build_object('clave', 'TEMP-01', 'fecha_hora', to_char(date_trunc('minute', now()) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'), 'valor', 22.1)
          ))->>'guardadas')::int), 1, 'Llega una lectura nueva');
select ok((select estado = 'CERRADA' and duracion_segundos is not null from incidencias_comunicacion
           where id_sensor = 'c8000000-0000-0000-0000-00000000000a' order by fecha_inicio desc limit 1),
  'Al volver a comunicar, la incidencia se cierra con su duración');
select ok(not (select activo from tipos_conexion where codigo = 'IOT'),
  'El tipo IOT antiguo queda sustituido por ENVIO_HTTP');

-- =========================================================
-- 4 bis. ASISTENTE: PRUEBA DE LECTURA Y CIERRE
-- =========================================================
select is((select estado_configuracion from sensores where codigo = 'S1' and id_dispositivo = 'c7000000-0000-0000-0000-00000000000b'),
  'PENDIENTE', 'Un sensor nuevo queda PENDIENTE de prueba');
select is((select transformar_valor(id, 2305) ->> 'valor_transformado' from sensores where codigo = 'CONT-01.energia_importada'),
  '2.305', 'La vista previa muestra el valor transformado (2305 Wh = 2,305 kWh)');
select is((select registrar_prueba_lectura('c6000000-0000-0000-0000-00000000000b', s.id, true, 230.4, now(), 'Lectura correcta') ->> 'correcto'
           from sensores s where s.codigo = 'S1' and s.id_dispositivo = 'c7000000-0000-0000-0000-00000000000b'),
  'true', 'Una prueba de lectura correcta se registra');
select is((select estado_configuracion from sensores where codigo = 'S1' and id_dispositivo = 'c7000000-0000-0000-0000-00000000000b'),
  'PROBADO', 'Tras la prueba, el sensor queda PROBADO');
update sensores set escala = 0.1 where codigo = 'S1' and id_dispositivo = 'c7000000-0000-0000-0000-00000000000b';
select is((select estado_configuracion from sensores where codigo = 'S1' and id_dispositivo = 'c7000000-0000-0000-0000-00000000000b'),
  'PENDIENTE', 'Si se cambia la escala, hay que volver a probar');
select is((select estado_configuracion from sensores where codigo = 'CONT-01.energia_importada'),
  'PROBADO', 'La primera lectura real también confirma el sensor');
select ok(not (estado_parametrizacion_edificio('c2000000-0000-0000-0000-00000000000b') ->> 'completo')::boolean,
  'El edificio B aún no está completo (sin modalidad, magnitudes, sensor pendiente)');
select throws_like($$ select cerrar_parametrizacion('c2000000-0000-0000-0000-00000000000b') $$,
  '%No se puede cerrar la parametrización%SENSORES_SIN_PROBAR%', 'No se cierra la parametrización con requisitos pendientes');

-- Edificio A completo: modalidad + magnitud con su sensor → se puede cerrar
insert into modalidades_edificio (id_edificio, modalidad) values ('c2000000-0000-0000-0000-00000000000a', 'BASIC');
insert into magnitudes_edificio (id, id_edificio, id_magnitud, ambito)
select 'c9000000-0000-0000-0000-00000000000a', 'c2000000-0000-0000-0000-00000000000a', id, 'EDIFICIO'
from magnitudes where codigo = 'ENERGIA_CONSUMIDA';
insert into magnitudes_fuentes (id_magnitud_edificio, id_sensor)
select 'c9000000-0000-0000-0000-00000000000a', id from sensores where codigo = 'CONT-01.energia_importada';
select ok((estado_parametrizacion_edificio('c2000000-0000-0000-0000-00000000000a') ->> 'completo')::boolean,
  'El edificio A cumple todos los requisitos bloqueantes');
select lives_ok($$ select cerrar_parametrizacion('c2000000-0000-0000-0000-00000000000a') $$,
  'Se cierra la parametrización del edificio A');
select is((select estado from edificios where id = 'c2000000-0000-0000-0000-00000000000a'),
  'OPERATIVO', 'El edificio A pasa a OPERATIVO');

-- =========================================================
-- 5. TOKENS DE ENVÍO Y PERMISOS
-- =========================================================
select pg_temp.login('e1000000-0000-0000-0000-000000000002');
set local role authenticated;
select throws_ok($$ select generar_token_conexion('c6000000-0000-0000-0000-00000000000a') $$, '42501', null,
  'El Partner B no puede generar tokens de una conexión del Partner A');
select is((select count(*) from plantillas_dispositivo where codigo = 'EJEMPLO_ENVIO_CONTADOR'), 1::bigint,
  'Las plantillas globales son visibles para cualquier Partner');
select lives_ok(
  $$ insert into plantillas_dispositivo (id_proveedor, codigo, nombre, id_tipo_dispositivo, id_tipo_conexion)
     select 'c0000000-0000-0000-0000-00000000000b', 'SENSOR_PROPIO_B', 'Sensor propio de B', td.id, tc.id
     from tipos_dispositivo td, tipos_conexion tc where td.codigo = 'SENSOR_AMBIENTAL' and tc.codigo = 'ENVIO_HTTP' $$,
  'Un Partner crea plantillas propias');
reset role;

select pg_temp.login('e1000000-0000-0000-0000-000000000001');
set local role authenticated;
select is((select count(*) from plantillas_dispositivo where codigo = 'SENSOR_PROPIO_B'), 0::bigint,
  'Las plantillas privadas de B no son visibles para A');
select throws_ok(
  $$ insert into plantillas_dispositivo (id_proveedor, codigo, nombre, id_tipo_dispositivo, id_tipo_conexion)
     select null, 'GLOBAL_FALSA', 'X', td.id, tc.id
     from tipos_dispositivo td, tipos_conexion tc where td.codigo = 'OTRO' and tc.codigo = 'ENVIO_HTTP' $$,
  '42501', null, 'Un Partner no puede crear plantillas globales');
create temp table tk as select generar_token_conexion('c6000000-0000-0000-0000-00000000000a') as token;
reset role;

select ok((select token like 'dte\_%' and length(token) > 60 from tk), 'El Partner A genera el token de su conexión');
select is((select (procesar_lecturas_token((select token from tk), jsonb_build_array(
            jsonb_build_object('clave', 'TEMP-01', 'fecha_hora', to_char((date_trunc('hour', now())) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'), 'valor', 22)
          ))->>'guardadas')::int), 1, 'Con el token se envían lecturas');
select throws_ok($$ select procesar_lecturas_token('dte_token_falso', '[]') $$, '28000', null,
  'Un token falso se rechaza');

select pg_temp.login('e1000000-0000-0000-0000-000000000001');
set local role authenticated;
select is((select count(*) from pruebas_lectura), 0::bigint, 'El Partner A no ve las pruebas de lectura del edificio de B');
reset role;

select * from finish();
rollback;
