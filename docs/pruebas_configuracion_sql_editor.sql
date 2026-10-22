-- VERSIÓN PARA EL SQL EDITOR DE SUPABASE: pegar entero y pulsar Run.
-- Al final sale un mensaje en ROJO a propósito con el resumen;
-- al ser un error, deshace todos los datos de prueba.
-- =========================================================
-- PRUEBAS DE CONFIGURACIÓN Y EDICIÓN DE EDIFICIOS (migración 025)
-- Ejecutar con:  npx supabase test db
-- =========================================================
begin;
set search_path = public, extensions;

create temp table resultados (n serial, t text);
grant all on resultados to public;
grant all on sequence resultados_n_seq to public;
select plan(28);

-- ---------------------------------------------------------
-- Datos de prueba: Partner P con un edificio en Barcelona
-- ---------------------------------------------------------
insert into auth.users (id, email) values
  ('e5000000-0000-0000-0000-000000000001', 'partner@conf.test'),
  ('e5000000-0000-0000-0000-000000000002', 'avanzado@conf.test'),
  ('e5000000-0000-0000-0000-000000000003', 'basico@conf.test'),
  ('e5000000-0000-0000-0000-000000000004', 'otro@conf.test');
insert into proveedores (id, codigo, nombre) values
  ('bb000000-0000-0000-0000-00000000000a', 'CP', 'Partner'),
  ('bb000000-0000-0000-0000-00000000000b', 'CQ', 'Otro partner');
insert into clientes (id, codigo, nombre) values ('bb100000-0000-0000-0000-000000000001', 'CC', 'Cliente');
insert into proveedores_clientes (id_proveedor, id_cliente) values
  ('bb000000-0000-0000-0000-00000000000a', 'bb100000-0000-0000-0000-000000000001');
insert into edificios (id, id_cliente, codigo, nombre, provincia, municipio) values
  ('bb200000-0000-0000-0000-000000000001', 'bb100000-0000-0000-0000-000000000001', 'BCN', 'Oficinas', 'Barcelona', 'Barcelona'),
  ('bb200000-0000-0000-0000-000000000002', 'bb100000-0000-0000-0000-000000000001', 'MAD', 'Almacén', 'Madrid', 'Madrid');
insert into proveedores_edificios (id_proveedor, id_edificio) values
  ('bb000000-0000-0000-0000-00000000000a', 'bb200000-0000-0000-0000-000000000001'),
  ('bb000000-0000-0000-0000-00000000000a', 'bb200000-0000-0000-0000-000000000002');
insert into plantas (id, id_edificio, codigo, nombre) values
  ('bb300000-0000-0000-0000-000000000001', 'bb200000-0000-0000-0000-000000000001', 'P0', 'PB');
insert into recintos (id, id_planta, codigo, nombre) values
  ('bb400000-0000-0000-0000-000000000001', 'bb300000-0000-0000-0000-000000000001', 'R1', 'Sala técnica'),
  ('bb400000-0000-0000-0000-000000000002', 'bb300000-0000-0000-0000-000000000001', 'R2', 'Vacío');
insert into conexiones (id, id_edificio, id_tipo_conexion, codigo, nombre)
select 'bb500000-0000-0000-0000-000000000001', 'bb200000-0000-0000-0000-000000000001', id, 'HTTP', 'Gateway'
from tipos_conexion where codigo = 'ENVIO_HTTP';
insert into dispositivos (id, id_recinto, id_conexion, id_tipo_dispositivo, codigo, nombre, numero_serie)
select 'bb600000-0000-0000-0000-000000000001', 'bb400000-0000-0000-0000-000000000001', 'bb500000-0000-0000-0000-000000000001',
       id, 'AN-1', 'Analizador', 'SN-OLD'
from tipos_dispositivo where codigo = 'CONTADOR_ENERGIA';
insert into sensores (id, id_dispositivo, id_recinto, id_familia, id_naturaleza, id_tratamiento, codigo, nombre, unidad, direccion, id_uso_energia)
select x.id::uuid, 'bb600000-0000-0000-0000-000000000001', 'bb400000-0000-0000-0000-000000000001', f.id, n.id, t.id,
       x.cod, x.cod, 'kWh', jsonb_build_object('clave', x.cod), u.id
from (values ('bb700000-0000-0000-0000-000000000001', 'AN-1.energia'),
             ('bb700000-0000-0000-0000-000000000002', 'AN-1.potencia')) x(id, cod),
     familias_sensor f, naturalezas_sensor n, tratamientos_sensor t, usos_energia u
where f.codigo = 'ENERGIA' and n.codigo = 'ACUMULATIVA' and t.codigo = 'DELTA' and u.codigo = 'HVAC_CLIMATIZACION';
insert into lecturas (id_sensor, fecha_hora, valor) values
  ('bb700000-0000-0000-0000-000000000001', date_trunc('hour', now()) - interval '1 hour', 100);
insert into magnitudes_edificio (id, id_edificio, id_magnitud, ambito)
select 'bb800000-0000-0000-0000-000000000001', 'bb200000-0000-0000-0000-000000000001', id, 'EDIFICIO'
from magnitudes where codigo = 'CONSUMO_ELECTRICIDAD';
insert into magnitudes_fuentes (id_magnitud_edificio, id_sensor) values
  ('bb800000-0000-0000-0000-000000000001', 'bb700000-0000-0000-0000-000000000001');
insert into modelos_3d (id, id_edificio, tipo_modelo, nombre, archivo) values
  ('bb900000-0000-0000-0000-000000000001', 'bb200000-0000-0000-0000-000000000001', 'EDIFICIO', 'General',
   'edificios/bb200000-0000-0000-0000-000000000001/modelos/general_v1.glb');
insert into ubicaciones_3d (id_modelo_3d, id_sensor, x, y, z) values
  ('bb900000-0000-0000-0000-000000000001', 'bb700000-0000-0000-0000-000000000001', 1.5, 2.0, -3.0);
insert into complementos_edificio (id_edificio, codigo) values ('bb200000-0000-0000-0000-000000000001', '3D');

insert into usuarios (id, auth_user_id, nombre, email, id_rol)
select x.id::uuid, x.auth::uuid, 'U', x.mail, r.id
from (values
  ('bba00000-0000-0000-0000-000000000001', 'e5000000-0000-0000-0000-000000000001', 'partner@conf.test', 'ADMIN_PARTNER'),
  ('bba00000-0000-0000-0000-000000000002', 'e5000000-0000-0000-0000-000000000002', 'avanzado@conf.test', 'USUARIO_CLIENTE_AVANZADO'),
  ('bba00000-0000-0000-0000-000000000003', 'e5000000-0000-0000-0000-000000000003', 'basico@conf.test', 'USUARIO_CLIENTE'),
  ('bba00000-0000-0000-0000-000000000004', 'e5000000-0000-0000-0000-000000000004', 'otro@conf.test', 'ADMIN_PARTNER')) x(id, auth, mail, rol)
join roles r on r.codigo = x.rol;
insert into usuarios_partners (id_usuario, id_proveedor) values
  ('bba00000-0000-0000-0000-000000000001', 'bb000000-0000-0000-0000-00000000000a'),
  ('bba00000-0000-0000-0000-000000000004', 'bb000000-0000-0000-0000-00000000000b');
insert into usuarios_clientes (id_usuario, id_cliente) values
  ('bba00000-0000-0000-0000-000000000002', 'bb100000-0000-0000-0000-000000000001'),
  ('bba00000-0000-0000-0000-000000000003', 'bb100000-0000-0000-0000-000000000001');

create function pg_temp.login(p_auth uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', p_auth::text, true),
         set_config('request.jwt.claims', json_build_object('sub', p_auth, 'role', 'authenticated')::text, true);
$$;

-- =========================================================
-- 1. Bajas de estructura
-- =========================================================
insert into resultados (t) select throws_like(
  $$ update recintos set activo = false, fecha_baja = current_date where id = 'bb400000-0000-0000-0000-000000000001' $$,
  '%tiene 3 sensores o dispositivos activos%', 'No se desactiva un recinto con sensores o dispositivos activos');
insert into resultados (t) select throws_like(
  $$ update plantas set activo = false, fecha_baja = current_date where id = 'bb300000-0000-0000-0000-000000000001' $$,
  '%recintos activos%', 'No se desactiva una planta con recintos activos');
insert into resultados (t) select lives_ok(
  $$ update recintos set activo = false, fecha_baja = current_date where id = 'bb400000-0000-0000-0000-000000000002' $$,
  'Un recinto vacío sí se desactiva');

-- =========================================================
-- 2. Sustitución de un sensor (como Partner)
-- =========================================================
select pg_temp.login('e5000000-0000-0000-0000-000000000001');
set local role authenticated;
create temp table nuevo_sensor as
select sustituir_sensor('bb700000-0000-0000-0000-000000000001') as id;
reset role;

insert into resultados (t) select ok((select not activo and codigo like 'AN-1.energia#%' from sensores where id = 'bb700000-0000-0000-0000-000000000001'),
  'El sensor antiguo queda inactivo y renombrado con la fecha');
insert into resultados (t) select is((select codigo from sensores where id = (select id from nuevo_sensor)), 'AN-1.energia',
  'El sensor nuevo conserva el código original');
insert into resultados (t) select is((select estado_configuracion from sensores where id = (select id from nuevo_sensor)), 'PENDIENTE',
  'El sensor nuevo empieza pendiente de prueba');
insert into resultados (t) select is((select count(*) from lecturas where id_sensor = 'bb700000-0000-0000-0000-000000000001'), 1::bigint,
  'Las lecturas siguen en el sensor antiguo (histórico conservado)');
insert into resultados (t) select is((select id_sensor from magnitudes_fuentes where id_magnitud_edificio = 'bb800000-0000-0000-0000-000000000001'),
  (select id from nuevo_sensor), 'La magnitud pasa a alimentarse del sensor nuevo');
insert into resultados (t) select is((select id_sensor from ubicaciones_3d where id_modelo_3d = 'bb900000-0000-0000-0000-000000000001'),
  (select id from nuevo_sensor), 'La posición 3D pasa al sensor nuevo');
insert into resultados (t) select is((select u.codigo from sensores s join usos_energia u on u.id = s.id_uso_energia where s.id = (select id from nuevo_sensor)),
  'HVAC_CLIMATIZACION', 'El uso final se conserva');

-- =========================================================
-- 3. Sustitución de un dispositivo
-- =========================================================
create temp table nuevo_disp as
select sustituir_dispositivo('bb600000-0000-0000-0000-000000000001', 'SN-NEW') as id;
insert into resultados (t) select ok((select not activo from dispositivos where id = 'bb600000-0000-0000-0000-000000000001'),
  'El dispositivo antiguo queda inactivo');
insert into resultados (t) select is((select count(*) from sensores where id_dispositivo = (select id from nuevo_disp) and activo), 2::bigint,
  'El dispositivo nuevo tiene sus 2 sensores nuevos');
insert into resultados (t) select is((select numero_serie from dispositivos where id = (select id from nuevo_disp)), 'SN-NEW',
  'El dispositivo nuevo registra su número de serie');
insert into resultados (t) select is((select count(*) from sensores where id_dispositivo = 'bb600000-0000-0000-0000-000000000001' and activo), 0::bigint,
  'Ningún sensor sigue activo en el dispositivo antiguo');
insert into resultados (t) select is((select count(*) from sensores where codigo like 'AN-1.energia#%'), 2::bigint,
  'Un sensor sustituido dos veces el mismo día deja dos históricos distintos');

-- =========================================================
-- 4. Nueva versión del GLB
-- =========================================================
create temp table nuevo_modelo as
select sustituir_modelo_3d('bb900000-0000-0000-0000-000000000001',
  'edificios/bb200000-0000-0000-0000-000000000001/modelos/general_v2.glb') as id;
insert into resultados (t) select ok((select not activo from modelos_3d where id = 'bb900000-0000-0000-0000-000000000001'),
  'La versión anterior del modelo queda inactiva');
insert into resultados (t) select is((select version from modelos_3d where id = (select id from nuevo_modelo)), 2, 'El modelo nuevo es la versión 2');
insert into resultados (t) select ok((select por_revisar and x = 1.5 from ubicaciones_3d where id_modelo_3d = (select id from nuevo_modelo)),
  'Las coordenadas se copian marcadas "por revisar"');
insert into resultados (t) select ok(exists (select 1 from jsonb_array_elements(estado_parametrizacion_edificio('bb200000-0000-0000-0000-000000000001')->'comprobaciones') c
                  where c->>'codigo' = 'COORDENADAS_POR_REVISAR' and not (c->>'ok')::boolean),
  'La lista de comprobación avisa de coordenadas por revisar');
update ubicaciones_3d set x = 1.6 where id_modelo_3d = (select id from nuevo_modelo);
insert into resultados (t) select ok((select not por_revisar from ubicaciones_3d where id_modelo_3d = (select id from nuevo_modelo)),
  'Al corregir la coordenada deja de estar por revisar');

-- =========================================================
-- 5. Calendario
-- =========================================================
insert into horarios_tipo_edificio (id_edificio, dia_semana, laborable, hora_inicio, hora_fin)
select 'bb200000-0000-0000-0000-000000000001', d, d < 6, case when d < 6 then time '08:00' end, case when d < 6 then time '18:00' end
from generate_series(1, 7) d;
insert into festivos (ambito, pais, provincia, municipio, fecha, nombre) values
  ('MUNICIPIO', 'España', 'Barcelona', 'Barcelona', '2027-09-24', 'La Mercè');

insert into resultados (t) select is(generar_calendarios_anio_siguiente('2026-11-15'), 0, 'Antes de diciembre no se genera el año siguiente');
insert into resultados (t) select ok(generar_calendarios_anio_siguiente('2026-12-01') > 300, 'Desde el 1 de diciembre se genera el calendario de 2027');
insert into resultados (t) select ok((select laborable and hora_inicio = '08:00' from calendario_edificio
           where id_edificio = 'bb200000-0000-0000-0000-000000000001' and fecha = '2027-01-04'),
  'Lunes 4/1/2027: laborable de 8:00 a 18:00 según el horario tipo');
insert into resultados (t) select ok((select not laborable from calendario_edificio
           where id_edificio = 'bb200000-0000-0000-0000-000000000001' and fecha = '2027-01-01'),
  'El festivo nacional (1 de enero) queda no laborable');
insert into resultados (t) select ok((select not laborable from calendario_edificio
           where id_edificio = 'bb200000-0000-0000-0000-000000000001' and fecha = '2027-09-24'),
  'El festivo local de Barcelona se aplica al edificio de Barcelona');
insert into resultados (t) select ok(not es_festivo('bb200000-0000-0000-0000-000000000002', '2027-09-24'),
  '… y no al de Madrid');

select pg_temp.login('e5000000-0000-0000-0000-000000000002');
set local role authenticated;
insert into resultados (t) select lives_ok(
  $$ update calendario_edificio set hora_fin = '20:00'
     where id_edificio = 'bb200000-0000-0000-0000-000000000001' and fecha = '2027-01-04' $$,
  'El usuario cliente avanzado ajusta el horario de un día futuro');
reset role;
select set_config('request.jwt.claim.sub', '', true), set_config('request.jwt.claims', '', true);
insert into calendario_edificio (id_edificio, fecha, laborable, hora_inicio, hora_fin)
values ('bb200000-0000-0000-0000-000000000001', current_date - 10, true, '08:00', '18:00')
on conflict (id_edificio, fecha) do nothing;
select pg_temp.login('e5000000-0000-0000-0000-000000000002');
set local role authenticated;
insert into resultados (t) select throws_like(
  $$ update calendario_edificio set laborable = false, hora_inicio = null, hora_fin = null
     where id_edificio = 'bb200000-0000-0000-0000-000000000001' and fecha = current_date - 10 $$,
  '%días pasados%', 'El cliente no puede modificar días pasados');
reset role;

do $$
declare v_total int; v_fallos int; v_detalle text;
begin
  select count(*), count(*) filter (where t like 'not ok%'),
         string_agg(split_part(t, E'\n', 1), E'\n' order by n) filter (where t like 'not ok%')
    into v_total, v_fallos, v_detalle from resultados;
  if v_fallos = 0 and v_total = 28 then
    raise exception 'RESULTADO: % de 28 pruebas OK. Todo correcto (los datos de prueba se han deshecho).', v_total;
  else
    raise exception E'RESULTADO: % pruebas ejecutadas, % FALLAN:\n%', v_total, v_fallos, coalesce(v_detalle, '(faltan pruebas)');
  end if;
end;
$$;
