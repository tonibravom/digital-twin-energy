-- VERSIÓN PARA EL SQL EDITOR DE SUPABASE: pegar entero y pulsar Run.
-- Al final sale un mensaje en ROJO a propósito con el resumen;
-- al ser un error, deshace todos los datos de prueba.
-- =========================================================
-- PRUEBAS DE EDIFICIOS EXISTENTES Y CARGA DE HISTÓRICOS (migración 026)
-- Ejecutar con:  npx supabase test db
-- =========================================================
begin;
set search_path = public, extensions;

create temp table resultados (n serial, t text);
grant all on resultados to public;
grant all on sequence resultados_n_seq to public;
select plan(22);

insert into auth.users (id, email) values
  ('e6000000-0000-0000-0000-000000000001', 'partner@hist.test'),
  ('e6000000-0000-0000-0000-000000000002', 'otro@hist.test'),
  ('e6000000-0000-0000-0000-000000000003', 'avanzado@hist.test');
insert into proveedores (id, codigo, nombre) values
  ('cc000000-0000-0000-0000-00000000000a', 'HP', 'Partner'),
  ('cc000000-0000-0000-0000-00000000000b', 'HQ', 'Otro');
insert into clientes (id, codigo, nombre) values ('cc100000-0000-0000-0000-000000000001', 'HC', 'Cliente');
insert into proveedores_clientes (id_proveedor, id_cliente) values
  ('cc000000-0000-0000-0000-00000000000a', 'cc100000-0000-0000-0000-000000000001');
insert into edificios (id, id_cliente, codigo, nombre) values
  ('cc200000-0000-0000-0000-000000000001', 'cc100000-0000-0000-0000-000000000001', 'HE', 'Edificio existente');
insert into proveedores_edificios (id_proveedor, id_edificio) values
  ('cc000000-0000-0000-0000-00000000000a', 'cc200000-0000-0000-0000-000000000001');
insert into plantas (id, id_edificio, codigo, nombre) values
  ('cc300000-0000-0000-0000-000000000001', 'cc200000-0000-0000-0000-000000000001', 'P0', 'PB');
insert into recintos (id, id_planta, codigo, nombre) values
  ('cc400000-0000-0000-0000-000000000001', 'cc300000-0000-0000-0000-000000000001', 'R', 'Sala');
insert into conexiones (id, id_edificio, id_tipo_conexion, codigo, nombre)
select 'cc500000-0000-0000-0000-000000000001', 'cc200000-0000-0000-0000-000000000001', id, 'IMP', 'Importación BMS'
from tipos_conexion where codigo = 'OTRA';
insert into sensores (id, id_conexion, id_recinto, id_familia, id_naturaleza, id_tratamiento, codigo, nombre, unidad, direccion)
select 'cc600000-0000-0000-0000-000000000001', 'cc500000-0000-0000-0000-000000000001', 'cc400000-0000-0000-0000-000000000001',
       f.id, n.id, t.id, 'TEMP', 'Temperatura', '°C', '{"clave": "TEMP"}'
from familias_sensor f, naturalezas_sensor n, tratamientos_sensor t
where f.codigo = 'TEMPERATURA' and n.codigo = 'INSTANTANEA' and t.codigo = 'PROMEDIO';

insert into usuarios (id, auth_user_id, nombre, email, id_rol)
select x.id::uuid, x.auth::uuid, 'U', x.mail, r.id
from (values
  ('cc700000-0000-0000-0000-000000000001', 'e6000000-0000-0000-0000-000000000001', 'partner@hist.test', 'ADMIN_PARTNER'),
  ('cc700000-0000-0000-0000-000000000002', 'e6000000-0000-0000-0000-000000000002', 'otro@hist.test', 'ADMIN_PARTNER'),
  ('cc700000-0000-0000-0000-000000000003', 'e6000000-0000-0000-0000-000000000003', 'avanzado@hist.test', 'USUARIO_CLIENTE_AVANZADO')) x(id, auth, mail, rol)
join roles r on r.codigo = x.rol;
insert into usuarios_partners (id_usuario, id_proveedor) values
  ('cc700000-0000-0000-0000-000000000001', 'cc000000-0000-0000-0000-00000000000a'),
  ('cc700000-0000-0000-0000-000000000002', 'cc000000-0000-0000-0000-00000000000b');
insert into usuarios_clientes (id_usuario, id_cliente) values
  ('cc700000-0000-0000-0000-000000000003', 'cc100000-0000-0000-0000-000000000001');

create function pg_temp.login(p_auth uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', p_auth::text, true),
         set_config('request.jwt.claims', json_build_object('sub', p_auth, 'role', 'authenticated', 'aal', 'aal2')::text, true);
$$;
create function pg_temp.logout() returns void language sql as $$
  select set_config('request.jwt.claim.sub', '', true), set_config('request.jwt.claims', '', true);
$$;

-- Fecha histórica dentro del periodo de retención (año anterior)
create temp table f as
select (date_trunc('year', now()) - interval '6 months') as t0;

-- =========================================================
-- 1. OPC UA
-- =========================================================
insert into resultados (t) select ok(exists (select 1 from tipos_conexion where codigo = 'OPC_UA' and modo = 'PASARELA'),
  'Existe el tipo de conexión OPC UA');
insert into resultados (t) select throws_like(
  $$ insert into conexiones (id_edificio, id_tipo_conexion, codigo, nombre, configuracion)
     select 'cc200000-0000-0000-0000-000000000001', id, 'OPC', 'SCADA', '{"endpoint": "opc.tcp://10.0.0.5:4840"}'
     from tipos_conexion where codigo = 'OPC_UA' $$,
  '%Faltan parámetros obligatorios%', 'OPC UA exige política y modo de seguridad');

-- =========================================================
-- 2. Importación de lecturas por lotes (como Partner)
-- =========================================================
select pg_temp.login('e6000000-0000-0000-0000-000000000001');
set local role authenticated;
create temp table imp as
select crear_importacion('cc200000-0000-0000-0000-000000000001', 'LECTURAS', 'EXCEL',
                         'cc500000-0000-0000-0000-000000000001', 'historico_bms.xlsx', 2) as id;
reset role;
select pg_temp.logout();

insert into resultados (t) select ok((select id is not null from imp), 'El Partner crea una importación');

-- Lote 1: 3 lecturas históricas (una con calidad ESTIMADA)
create temp table r1 as
select procesar_lote_lecturas((select id from imp), 1, jsonb_build_array(
  jsonb_build_object('clave', 'TEMP', 'fecha_hora', (select t0 from f)::text, 'valor', 20),
  jsonb_build_object('clave', 'TEMP', 'fecha_hora', ((select t0 from f) + interval '15 min')::text, 'valor', 21),
  jsonb_build_object('clave', 'TEMP', 'fecha_hora', ((select t0 from f) + interval '30 min')::text, 'valor', 22, 'calidad', 'ESTIMADA')
)) as j;

insert into resultados (t) select is((select (j->>'guardadas')::int from r1), 3, 'El lote 1 guarda 3 lecturas históricas');
insert into resultados (t) select is((select calidad from lecturas where id_sensor = 'cc600000-0000-0000-0000-000000000001'
           and fecha_hora = (select t0 from f) + interval '30 min'), 1::smallint,
  'La lectura marcada como ESTIMADA se guarda con calidad 1');
insert into resultados (t) select is((select count(*) from estado_comunicacion where id_sensor = 'cc600000-0000-0000-0000-000000000001'), 0::bigint,
  'Una carga histórica no altera el estado de comunicación del sensor');
insert into resultados (t) select is((select estado_configuracion from sensores where id = 'cc600000-0000-0000-0000-000000000001'), 'PENDIENTE',
  '… ni marca el sensor como probado');
insert into resultados (t) select ok((select ya_procesado from (select (procesar_lote_lecturas((select id from imp), 1, '[]'::jsonb)->>'ya_procesado')::boolean as ya_procesado) x),
  'Repetir un lote ya procesado no hace nada (importación reanudable)');
insert into resultados (t) select is((select count(*) from lecturas where id_sensor = 'cc600000-0000-0000-0000-000000000001'), 3::bigint,
  '… y no duplica datos');
insert into resultados (t) select is((select count(*) from recalculos_pendientes where id_importacion = (select id from imp)), 1::bigint,
  'El lote deja un recálculo pendiente para el motor');
insert into resultados (t) select is((select desde from recalculos_pendientes where id_importacion = (select id from imp)), (select t0 from f),
  'El recálculo cubre el periodo importado');

-- Lote 2: una lectura anterior a la retención → rechazada con indicación
create temp table r2 as
select procesar_lote_lecturas((select id from imp), 2, jsonb_build_array(
  jsonb_build_object('clave', 'TEMP', 'fecha_hora', '2015-01-01T00:00:00Z', 'valor', 18)
)) as j;
insert into resultados (t) select ok((select j->'detalle_rechazos'->0->>'motivo' like '%resumen%' from r2),
  'Lo anterior a la retención se rechaza indicando que se importe como resumen');
insert into resultados (t) select is((select estado from importaciones where id = (select id from imp)), 'CON_ERRORES',
  'Al terminar los 2 lotes, la importación queda completada con errores');
insert into resultados (t) select is((select guardadas::int from importaciones where id = (select id from imp)), 3,
  'La importación acumula los totales de sus lotes');

-- =========================================================
-- 3. Resúmenes históricos
-- =========================================================
select pg_temp.login('e6000000-0000-0000-0000-000000000001');
set local role authenticated;
create temp table rr as
select importar_resumenes('cc200000-0000-0000-0000-000000000001', jsonb_build_array(
  jsonb_build_object('indicador', 'CONSUMO_ELECTRICIDAD', 'mes', '2015-04', 'valor', 3000),
  jsonb_build_object('indicador', 'CONSUMO_GAS', 'fecha', '2015-04-10', 'valor', 50),
  jsonb_build_object('indicador', 'INVENTADO', 'fecha', '2015-04-10', 'valor', 1)
)) as j;
reset role;
select pg_temp.logout();

insert into resultados (t) select is((select (j->>'dias_guardados')::int from rr), 31, 'Un mes (30 días) + un día = 31 resúmenes diarios');
insert into resultados (t) select is((select round(sum(valor)::numeric, 3) from resumenes_diarios
           where id_edificio = 'cc200000-0000-0000-0000-000000000001' and indicador = 'CONSUMO_ELECTRICIDAD'),
  3000.000, 'El valor mensual se reparte entre los días sin perder total');
insert into resultados (t) select ok((select bool_and(not completo and origen = 'IMPORTACION_MENSUAL') from resumenes_diarios
           where id_edificio = 'cc200000-0000-0000-0000-000000000001' and indicador = 'CONSUMO_ELECTRICIDAD'),
  'Los días de un valor mensual se marcan como no completos');
insert into resultados (t) select is((select (j->>'rechazadas')::int from rr), 1, 'Un indicador desconocido se rechaza');
insert into resultados (t) select ok((select (kpis_ambito('EDIFICIO', 'cc200000-0000-0000-0000-000000000001', date '2015-12-31')->'indicadores'->0->>'valor')::numeric > 3000),
  'Los KPIs de 2015 ya pueden calcularse con los resúmenes importados');

select pg_temp.login('e6000000-0000-0000-0000-000000000002');
set local role authenticated;
insert into resultados (t) select throws_ok(
  $$ select importar_resumenes('cc200000-0000-0000-0000-000000000001',
       '[{"indicador": "CONSUMO_GAS", "fecha": "2015-05-01", "valor": 1}]'::jsonb) $$,
  '42501', null, 'Otro Partner no puede importar en este edificio');
reset role;

-- =========================================================
-- 4. Calendario de años pasados
-- =========================================================
select pg_temp.login('e6000000-0000-0000-0000-000000000001');
set local role authenticated;
insert into resultados (t) select ok(generar_calendario('cc200000-0000-0000-0000-000000000001', 2024, false, true) > 100,
  'El Partner genera el calendario de un año pasado para analizar históricos');
reset role;
select pg_temp.login('e6000000-0000-0000-0000-000000000003');
set local role authenticated;
insert into resultados (t) select throws_like(
  $$ select generar_calendario('cc200000-0000-0000-0000-000000000001', 2023, false, true) $$,
  '%días pasados%', 'El cliente no puede generar años pasados');
reset role;

do $$
declare v_total int; v_fallos int; v_detalle text;
begin
  select count(*), count(*) filter (where t like 'not ok%'),
         string_agg(split_part(t, E'\n', 1), E'\n' order by n) filter (where t like 'not ok%')
    into v_total, v_fallos, v_detalle from resultados;
  if v_fallos = 0 and v_total = 22 then
    raise exception 'RESULTADO: % de 22 pruebas OK. Todo correcto (los datos de prueba se han deshecho).', v_total;
  else
    raise exception E'RESULTADO: % pruebas ejecutadas, % FALLAN:\n%', v_total, v_fallos, coalesce(v_detalle, '(faltan pruebas)');
  end if;
end;
$$;
