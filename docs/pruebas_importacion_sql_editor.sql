-- VERSIÓN PARA EL SQL EDITOR DE SUPABASE: pegar entero y pulsar Run.
-- Al final sale un mensaje en ROJO a propósito con el resumen;
-- al ser un error, deshace todos los datos de prueba.
-- =========================================================
-- PRUEBAS DE IMPORTACIÓN AVANZADA DE HISTÓRICOS (migración 026)
-- Permiso solo Partner, simulación, perfiles, recuperación
-- automática y vía API con token.
-- Ejecutar con:  npx supabase test db
-- =========================================================
begin;
set search_path = public, extensions;

create temp table resultados (n serial, t text);
grant all on resultados to public;
grant all on sequence resultados_n_seq to public;
select plan(28);

insert into auth.users (id, email) values
  ('e7000000-0000-0000-0000-000000000001', 'partner@imp.test'),
  ('e7000000-0000-0000-0000-000000000002', 'otro@imp.test'),
  ('e7000000-0000-0000-0000-000000000003', 'avanzado@imp.test');
insert into proveedores (id, codigo, nombre) values
  ('dd000000-0000-0000-0000-00000000000a', 'IP', 'Partner'),
  ('dd000000-0000-0000-0000-00000000000b', 'IQ', 'Otro');
insert into clientes (id, codigo, nombre) values ('dd100000-0000-0000-0000-000000000001', 'IC', 'Cliente');
insert into proveedores_clientes (id_proveedor, id_cliente) values
  ('dd000000-0000-0000-0000-00000000000a', 'dd100000-0000-0000-0000-000000000001');
insert into edificios (id, id_cliente, codigo, nombre) values
  ('dd200000-0000-0000-0000-000000000001', 'dd100000-0000-0000-0000-000000000001', 'IE', 'Edificio');
insert into proveedores_edificios (id_proveedor, id_edificio) values
  ('dd000000-0000-0000-0000-00000000000a', 'dd200000-0000-0000-0000-000000000001');
insert into plantas (id, id_edificio, codigo, nombre) values
  ('dd300000-0000-0000-0000-000000000001', 'dd200000-0000-0000-0000-000000000001', 'P0', 'PB');
insert into recintos (id, id_planta, codigo, nombre) values
  ('dd400000-0000-0000-0000-000000000001', 'dd300000-0000-0000-0000-000000000001', 'R', 'Sala');

-- Conexión de envío (empresa IoT) y conexión API REST (recuperable)
insert into conexiones (id, id_edificio, id_tipo_conexion, codigo, nombre)
select 'dd500000-0000-0000-0000-000000000001', 'dd200000-0000-0000-0000-000000000001', id, 'ENV', 'Gateway IoT'
from tipos_conexion where codigo = 'ENVIO_HTTP';
insert into conexiones (id, id_edificio, id_tipo_conexion, codigo, nombre, configuracion)
select 'dd500000-0000-0000-0000-000000000002', 'dd200000-0000-0000-0000-000000000001', id, 'API', 'Plataforma fabricante',
       '{"url": "https://api.ejemplo.test/datos", "autenticacion": "NINGUNA", "ruta_lista": "$.items", "campo_fecha": "t"}'
from tipos_conexion where codigo = 'API_REST';

insert into sensores (id, id_conexion, id_recinto, id_familia, id_naturaleza, id_tratamiento, codigo, nombre, unidad, direccion)
select 'dd600000-0000-0000-0000-000000000001', 'dd500000-0000-0000-0000-000000000001', 'dd400000-0000-0000-0000-000000000001',
       f.id, n.id, t.id, 'TEMP', 'Temperatura', '°C', '{"clave": "TEMP"}'
from familias_sensor f, naturalezas_sensor n, tratamientos_sensor t
where f.codigo = 'TEMPERATURA' and n.codigo = 'INSTANTANEA' and t.codigo = 'PROMEDIO';

insert into usuarios (id, auth_user_id, nombre, email, id_rol)
select x.id::uuid, x.auth::uuid, 'U', x.mail, r.id
from (values
  ('dd700000-0000-0000-0000-000000000001', 'e7000000-0000-0000-0000-000000000001', 'partner@imp.test', 'TECNICO_PARTNER'),
  ('dd700000-0000-0000-0000-000000000002', 'e7000000-0000-0000-0000-000000000002', 'otro@imp.test', 'ADMIN_PARTNER'),
  ('dd700000-0000-0000-0000-000000000003', 'e7000000-0000-0000-0000-000000000003', 'avanzado@imp.test', 'USUARIO_CLIENTE_AVANZADO')) x(id, auth, mail, rol)
join roles r on r.codigo = x.rol;
insert into usuarios_partners (id_usuario, id_proveedor) values
  ('dd700000-0000-0000-0000-000000000001', 'dd000000-0000-0000-0000-00000000000a'),
  ('dd700000-0000-0000-0000-000000000002', 'dd000000-0000-0000-0000-00000000000b');
insert into usuarios_clientes (id_usuario, id_cliente) values
  ('dd700000-0000-0000-0000-000000000003', 'dd100000-0000-0000-0000-000000000001');

create function pg_temp.login(p_auth uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', p_auth::text, true),
         set_config('request.jwt.claims', json_build_object('sub', p_auth, 'role', 'authenticated')::text, true);
$$;
create function pg_temp.logout() returns void language sql as $$
  select set_config('request.jwt.claim.sub', '', true), set_config('request.jwt.claims', '', true);
$$;

create temp table f as select (date_trunc('year', now()) - interval '6 months') as t0;
grant select on f to authenticated;

-- =========================================================
-- 1. Permiso: solo Partner y administrador
-- =========================================================
insert into resultados (t) select ok(exists (select 1 from roles_permisos rp join roles r on r.id = rp.id_rol join permisos p on p.id = rp.id_permiso
                  where r.codigo = 'TECNICO_PARTNER' and p.codigo = 'IMPORTAR_HISTORICOS'),
  'El técnico del Partner tiene el permiso de importar');
insert into resultados (t) select ok(not exists (select 1 from roles_permisos rp join roles r on r.id = rp.id_rol join permisos p on p.id = rp.id_permiso
                      where r.codigo like 'USUARIO_CLIENTE%' and p.codigo = 'IMPORTAR_HISTORICOS'),
  'Ningún rol de cliente tiene el permiso de importar');

select pg_temp.login('e7000000-0000-0000-0000-000000000003');
set local role authenticated;
insert into resultados (t) select throws_ok(
  $$ select crear_importacion('dd200000-0000-0000-0000-000000000001', 'LECTURAS', 'EXCEL',
                              'dd500000-0000-0000-0000-000000000001', 'x.xlsx', 1) $$,
  '42501', null, 'El cliente avanzado no puede crear importaciones');
insert into resultados (t) select throws_ok(
  $$ select importar_resumenes('dd200000-0000-0000-0000-000000000001',
       '[{"indicador": "CONSUMO_GAS", "fecha": "2015-05-01", "valor": 1}]'::jsonb) $$,
  '42501', null, '… ni importar resúmenes');
reset role;
select pg_temp.login('e7000000-0000-0000-0000-000000000003');
set local role authenticated;
insert into resultados (t) select ok(not puede_importar('dd200000-0000-0000-0000-000000000001'), 'puede_importar: el cliente avanzado no');
reset role;
select pg_temp.login('e7000000-0000-0000-0000-000000000001');
set local role authenticated;
insert into resultados (t) select ok(puede_importar('dd200000-0000-0000-0000-000000000001'), 'puede_importar: el Partner del edificio sí');
reset role;
select pg_temp.login('e7000000-0000-0000-0000-000000000002');
set local role authenticated;
insert into resultados (t) select ok(not puede_importar('dd200000-0000-0000-0000-000000000001'), 'puede_importar: otro Partner no');
insert into resultados (t) select throws_ok(
  $$ select simular_lecturas('dd500000-0000-0000-0000-000000000001', '[]'::jsonb) $$,
  '42501', null, 'Otro Partner no puede simular en conexiones ajenas');
reset role;

-- =========================================================
-- 2. Simulación (vista previa sin guardar)
-- =========================================================
select pg_temp.login('e7000000-0000-0000-0000-000000000001');
set local role authenticated;
create temp table sim as
select simular_lecturas('dd500000-0000-0000-0000-000000000001', jsonb_build_array(
  jsonb_build_object('clave', 'TEMP', 'fecha_hora', (select t0 from f)::text, 'valor', 20),
  jsonb_build_object('clave', 'TEMP', 'fecha_hora', ((select t0 from f) + interval '15 min')::text, 'valor', 24),
  jsonb_build_object('clave', 'NO_EXISTE', 'fecha_hora', (select t0 from f)::text, 'valor', 1)
)) as j;
reset role;
select pg_temp.logout();

insert into resultados (t) select ok((select (j->>'simulacion')::boolean from sim), 'La simulación se identifica como tal');
insert into resultados (t) select is((select (j->>'nuevas')::int from sim), 2, 'La simulación cuenta las lecturas que se guardarían');
insert into resultados (t) select is((select (j->>'rechazadas')::int from sim), 1, '… y las que se rechazarían');
insert into resultados (t) select is((select (j->'por_sensor'->0->>'maximo')::numeric from sim), 24::numeric,
  'Muestra estadísticas por sensor (mínimo, máximo, media) para revisar escalas');
insert into resultados (t) select is((select count(*) from lecturas where id_sensor = 'dd600000-0000-0000-0000-000000000001'), 0::bigint,
  'La simulación no guarda ninguna lectura');

select pg_temp.login('e7000000-0000-0000-0000-000000000001');
set local role authenticated;
create temp table simr as
select importar_resumenes('dd200000-0000-0000-0000-000000000001',
  '[{"indicador": "CONSUMO_ELECTRICIDAD", "mes": "2016-02", "valor": 2900}]'::jsonb, false, null, true) as j;
reset role;
insert into resultados (t) select is((select (j->>'dias_guardados')::int from simr), 29, 'La simulación de resúmenes calcula los días (febrero bisiesto)');
insert into resultados (t) select is((select count(*) from resumenes_diarios where id_edificio = 'dd200000-0000-0000-0000-000000000001'), 0::bigint,
  '… sin guardarlos');

-- =========================================================
-- 3. Perfiles de importación (formatos ANCHO y LARGO)
-- =========================================================
select pg_temp.login('e7000000-0000-0000-0000-000000000001');
set local role authenticated;
insert into resultados (t) select lives_ok(
  $$ insert into perfiles_importacion (id_edificio, nombre, tipo, formato, configuracion) values
     ('dd200000-0000-0000-0000-000000000001', 'Exportación BMS', 'LECTURAS', 'ANCHO',
      '{"fila_cabecera": 1, "fila_inicio": 2, "columna_fecha": "A", "formato_fecha": "DD/MM/YYYY HH:mm",
        "zona_horaria": "Europe/Madrid", "separador_decimal": ",", "vacios": "DESCARTAR",
        "columnas": [{"columna": "B", "clave": "TEMP"}]}'),
     ('dd200000-0000-0000-0000-000000000001', 'Volcado SCADA', 'LECTURAS', 'LARGO',
      '{"fila_inicio": 2, "columna_fecha": "A", "columna_sensor": "B", "columna_valor": "C"}') $$,
  'El Partner guarda perfiles de formato ancho y largo');
insert into resultados (t) select throws_like(
  $$ insert into perfiles_importacion (id_edificio, nombre, tipo, formato, configuracion) values
     ('dd200000-0000-0000-0000-000000000001', 'Sin fecha', 'LECTURAS', 'LARGO', '{"columna_valor": "C"}') $$,
  '%perfiles_importacion_config_ck%', 'Un perfil de lecturas debe indicar la columna de fecha');
reset role;

select pg_temp.login('e7000000-0000-0000-0000-000000000002');
set local role authenticated;
insert into resultados (t) select is((select count(*) from perfiles_importacion), 0::bigint, 'Otro Partner no ve los perfiles');
reset role;
select pg_temp.login('e7000000-0000-0000-0000-000000000003');
set local role authenticated;
insert into resultados (t) select is((select count(*) from perfiles_importacion), 0::bigint, 'El cliente tampoco');
reset role;

-- =========================================================
-- 4. Recuperación automática al conectar
-- =========================================================
select pg_temp.login('e7000000-0000-0000-0000-000000000001');
set local role authenticated;
insert into resultados (t) select throws_like(
  $$ select solicitar_recuperacion('dd500000-0000-0000-0000-000000000001', date '2024-01-01') $$,
  '%no permite recuperar%', 'Una conexión de envío no admite recuperación automática');
create temp table rec as
select solicitar_recuperacion('dd500000-0000-0000-0000-000000000002', date '2010-01-01') as j;
insert into resultados (t) select throws_like(
  $$ select solicitar_recuperacion('dd500000-0000-0000-0000-000000000002', date '2024-01-01') $$,
  '%en marcha%', 'No se lanzan dos recuperaciones a la vez');
reset role;
select pg_temp.logout();

insert into resultados (t) select is((select (j->>'desde')::date from rec), (limite_retencion_lecturas() at time zone 'UTC')::date,
  'Una fecha anterior a la retención se ajusta al límite');
insert into resultados (t) select ok((select j->>'aviso' like '%resúmenes%' from rec), '… con un aviso para importar ese periodo como resúmenes');
insert into resultados (t) select is((select recuperacion_estado from conexiones where id = 'dd500000-0000-0000-0000-000000000002'), 'PENDIENTE',
  'La conexión queda con la recuperación pendiente para la API');
insert into resultados (t) select is((select origen from importaciones where id = (select (j->>'id_importacion')::uuid from rec)), 'CONECTOR',
  'La recuperación queda registrada como importación del conector');

select avanzar_recuperacion('dd500000-0000-0000-0000-000000000002', now(), 'COMPLETADA');
insert into resultados (t) select is((select estado from importaciones where id = (select (j->>'id_importacion')::uuid from rec)), 'COMPLETADA',
  'Al terminar la recuperación, la importación se cierra');

-- =========================================================
-- 5. Vía API con token (empresas IoT)
-- =========================================================
create temp table tk as select generar_token_conexion('dd500000-0000-0000-0000-000000000001') as t;
create temp table ti as select crear_importacion_token((select t from tk), 1) as id;
create temp table tr as
select procesar_lote_token((select t from tk), (select id from ti), 1, jsonb_build_array(
  jsonb_build_object('clave', 'TEMP', 'fecha_hora', (select t0 from f)::text, 'valor', 19)
)) as j;
insert into resultados (t) select is((select (j->>'guardadas')::int from tr), 1, 'Una empresa IoT carga su histórico por lotes con el token');
insert into resultados (t) select throws_ok(
  $$ select crear_importacion_token('dte_inventado', 1) $$, '28000', null, 'Un token falso se rechaza');

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
