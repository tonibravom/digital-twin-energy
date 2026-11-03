-- VERSIÓN PARA EL SQL EDITOR DE SUPABASE: pegar entero y pulsar Run.
-- Al final sale un mensaje en ROJO a propósito con el resumen;
-- al ser un error, deshace todos los datos de prueba.
-- =========================================================
-- PRUEBAS DE CUADROS ELÉCTRICOS, FUNCIÓN DE LOS MEDIDORES Y SANKEY POR CUADRO (migración 037)
-- Ejecutar con:  npx supabase test db
--
-- Edificio en Europe/Madrid; día de prueba martes 20/10/2026. Contadores en kWh cada 15 min:
--   GEN   contador general                         +20   → 1.920 kWh
--   TPB   total cuadro planta baja                  +6   →   576
--   APB   alumbrado (cuadro planta baja)            +1   →    96
--   TLOC  total cuadro del local (cuelga de PB)     +2   →   192
--   ALOC  alumbrado del local                       +0,5 →    48
--   TP1   total cuadro planta 1                     +8   →   768
--   AP1   alumbrado (cuadro planta 1)               +2   →   192
--   INF   informática en un cuadro SIN medidor que cuelga del de planta 1 +1 → 96
--   GASC  gas de caldera, calefacción y ACS, independiente +3 → 288
-- Otros usos: PB = 576 − 96 − 192 = 288 · local = 192 − 48 = 144 · P1 = 768 − 192 − 96 = 480
-- No medido = 1.920 − (576 + 768) = 576
-- =========================================================
begin;
set search_path = public, extensions;

create temp table resultados (n serial, t text);
grant all on resultados to public;
grant all on sequence resultados_n_seq to public;
select plan(29);

insert into proveedores (id, codigo, nombre) values
  ('fd000000-0000-0000-0000-00000000000a', 'QA', 'Partner cuadros A'),
  ('fd000000-0000-0000-0000-00000000000b', 'QB', 'Partner cuadros B');
insert into clientes (id, codigo, nombre) values ('fd100000-0000-0000-0000-000000000001', 'QC', 'Cliente cuadros');
insert into proveedores_clientes (id_proveedor, id_cliente) values
  ('fd000000-0000-0000-0000-00000000000a', 'fd100000-0000-0000-0000-000000000001');
insert into edificios (id, id_cliente, codigo, nombre, zona_horaria) values
  ('fd200000-0000-0000-0000-000000000001', 'fd100000-0000-0000-0000-000000000001', 'QE', 'Edificio cuadros', 'Europe/Madrid'),
  ('fd200000-0000-0000-0000-000000000002', 'fd100000-0000-0000-0000-000000000001', 'QO', 'Otro edificio', 'Europe/Madrid');
insert into proveedores_edificios (id_proveedor, id_edificio) values
  ('fd000000-0000-0000-0000-00000000000a', 'fd200000-0000-0000-0000-000000000001');
insert into plantas (id, id_edificio, codigo, nombre, nivel) values
  ('fd300000-0000-0000-0000-000000000000', 'fd200000-0000-0000-0000-000000000001', 'P0', 'Planta baja', 0),
  ('fd300000-0000-0000-0000-000000000001', 'fd200000-0000-0000-0000-000000000001', 'P1', 'Planta 1', 1),
  ('fd300000-0000-0000-0000-000000000009', 'fd200000-0000-0000-0000-000000000002', 'P0', 'Planta baja', 0);
insert into recintos (id, id_planta, codigo, nombre) values
  ('fd400000-0000-0000-0000-000000000000', 'fd300000-0000-0000-0000-000000000000', 'VE', 'Vestíbulo'),
  ('fd400000-0000-0000-0000-000000000001', 'fd300000-0000-0000-0000-000000000000', 'LO', 'Local comercial'),
  ('fd400000-0000-0000-0000-000000000002', 'fd300000-0000-0000-0000-000000000001', 'OF', 'Oficina'),
  ('fd400000-0000-0000-0000-000000000009', 'fd300000-0000-0000-0000-000000000009', 'X', 'Otro');
insert into cuadros_electricos (id, id_edificio, id_planta, id_recinto, id_cuadro_padre, codigo, nombre) values
  ('fd500000-0000-0000-0000-000000000000', 'fd200000-0000-0000-0000-000000000001', 'fd300000-0000-0000-0000-000000000000', null, null, 'CPB', 'Cuadro planta baja'),
  ('fd500000-0000-0000-0000-000000000001', 'fd200000-0000-0000-0000-000000000001', null, 'fd400000-0000-0000-0000-000000000001', 'fd500000-0000-0000-0000-000000000000', 'CLOC', 'Cuadro del local'),
  ('fd500000-0000-0000-0000-000000000002', 'fd200000-0000-0000-0000-000000000001', 'fd300000-0000-0000-0000-000000000001', null, null, 'CP1', 'Cuadro planta 1'),
  ('fd500000-0000-0000-0000-000000000003', 'fd200000-0000-0000-0000-000000000001', 'fd300000-0000-0000-0000-000000000001', null, 'fd500000-0000-0000-0000-000000000002', 'CNM', 'Cuadro de informática'),
  ('fd500000-0000-0000-0000-000000000009', 'fd200000-0000-0000-0000-000000000002', 'fd300000-0000-0000-0000-000000000009', null, null, 'CX', 'Cuadro de otro edificio');
insert into conexiones (id, id_edificio, id_tipo_conexion, codigo, nombre)
select 'fd700000-0000-0000-0000-000000000001', 'fd200000-0000-0000-0000-000000000001', id, 'HTTP', 'Gateway'
from tipos_conexion where codigo = 'ENVIO_HTTP';

create function pg_temp.sensor(p_id text, p_cod text, p_rec text, p_ene text, p_funcion text, p_uso text, p_cuadro text)
returns void language sql as $$
  insert into sensores (id, id_conexion, id_recinto, id_familia, id_naturaleza, id_tratamiento, id_tipo_energia,
                        codigo, nombre, unidad, direccion, funcion_medidor, id_uso_energia, id_cuadro)
  select p_id::uuid, 'fd700000-0000-0000-0000-000000000001', p_rec::uuid, f.id, n.id, t.id, te.id, p_cod, p_cod, 'kWh',
         jsonb_build_object('clave', p_cod), p_funcion, (select id from usos_energia where codigo = p_uso), p_cuadro::uuid
  from familias_sensor f, naturalezas_sensor n, tratamientos_sensor t, tipos_energia te
  where f.codigo = 'ENERGIA' and n.codigo = 'ACUMULATIVA' and t.codigo = 'DELTA' and te.codigo = p_ene;
$$;
select pg_temp.sensor('fd800000-0000-0000-0000-000000000001', 'GEN', 'fd400000-0000-0000-0000-000000000000', 'ELECTRICIDAD', 'GENERAL', null, null);
select pg_temp.sensor('fd800000-0000-0000-0000-000000000002', 'TPB', 'fd400000-0000-0000-0000-000000000000', 'ELECTRICIDAD', 'CUADRO', null, 'fd500000-0000-0000-0000-000000000000');
select pg_temp.sensor('fd800000-0000-0000-0000-000000000003', 'APB', 'fd400000-0000-0000-0000-000000000000', 'ELECTRICIDAD', 'USO', 'ILUMINACION', 'fd500000-0000-0000-0000-000000000000');
select pg_temp.sensor('fd800000-0000-0000-0000-000000000004', 'TLOC', 'fd400000-0000-0000-0000-000000000001', 'ELECTRICIDAD', 'CUADRO', null, 'fd500000-0000-0000-0000-000000000001');
select pg_temp.sensor('fd800000-0000-0000-0000-000000000005', 'ALOC', 'fd400000-0000-0000-0000-000000000001', 'ELECTRICIDAD', 'USO', 'ILUMINACION', 'fd500000-0000-0000-0000-000000000001');
select pg_temp.sensor('fd800000-0000-0000-0000-000000000006', 'TP1', 'fd400000-0000-0000-0000-000000000002', 'ELECTRICIDAD', 'CUADRO', null, 'fd500000-0000-0000-0000-000000000002');
select pg_temp.sensor('fd800000-0000-0000-0000-000000000007', 'AP1', 'fd400000-0000-0000-0000-000000000002', 'ELECTRICIDAD', 'USO', 'ILUMINACION', 'fd500000-0000-0000-0000-000000000002');
select pg_temp.sensor('fd800000-0000-0000-0000-000000000008', 'INF', 'fd400000-0000-0000-0000-000000000002', 'ELECTRICIDAD', 'USO', 'OTROS_INFORMATICA', 'fd500000-0000-0000-0000-000000000003');
select pg_temp.sensor('fd800000-0000-0000-0000-000000000009', 'GASC', 'fd400000-0000-0000-0000-000000000000', 'GAS', 'USO', 'HVAC_CALEFACCION_ACS', null);

insert into magnitudes_edificio (id, id_edificio, id_magnitud, ambito)
select x.id::uuid, 'fd200000-0000-0000-0000-000000000001', m.id, 'EDIFICIO'
from (values ('fd600000-0000-0000-0000-000000000001', 'CONSUMO_ELECTRICIDAD'),
             ('fd600000-0000-0000-0000-000000000002', 'CONSUMO_GAS')) x(id, cod)
join magnitudes m on m.codigo = x.cod;
insert into magnitudes_fuentes (id_magnitud_edificio, id_sensor) values
  ('fd600000-0000-0000-0000-000000000001', 'fd800000-0000-0000-0000-000000000001'),
  ('fd600000-0000-0000-0000-000000000002', 'fd800000-0000-0000-0000-000000000009');

insert into lecturas (id_sensor, fecha_hora, valor)
select x.id::uuid, t, 1000 + x.inc * (row_number() over (partition by x.id order by t) - 1)
from (values ('fd800000-0000-0000-0000-000000000001', 20.0), ('fd800000-0000-0000-0000-000000000002', 6.0),
             ('fd800000-0000-0000-0000-000000000003', 1.0), ('fd800000-0000-0000-0000-000000000004', 2.0),
             ('fd800000-0000-0000-0000-000000000005', 0.5), ('fd800000-0000-0000-0000-000000000006', 8.0),
             ('fd800000-0000-0000-0000-000000000007', 2.0), ('fd800000-0000-0000-0000-000000000008', 1.0),
             ('fd800000-0000-0000-0000-000000000009', 3.0)) x(id, inc)
cross join generate_series(timestamptz '2026-10-20 00:00 Europe/Madrid', timestamptz '2026-10-21 00:00 Europe/Madrid', interval '15 minutes') t;

-- =========================================================
-- 1. Catálogo de usos
-- =========================================================
insert into resultados (t) select is((select string_agg(h.codigo, ',' order by h.orden) from usos_energia h join usos_energia p on p.id = h.id_padre where p.codigo = 'HVAC'),
  'HVAC_CLIMATIZACION,HVAC_REFRIGERACION,HVAC_CALEFACCION,HVAC_ACS,HVAC_CALEFACCION_ACS,HVAC_RENOVACION',
  'HVAC: climatización, refrigeración, calefacción, ACS, calefacción y ACS, renovación de aire');
insert into resultados (t) select is((select string_agg(h.codigo, ',' order by h.orden) from usos_energia h join usos_energia p on p.id = h.id_padre where p.codigo = 'OTROS'),
  'OTROS_INFORMATICA,OTROS_SERVICIOS_COMUNES,OTROS_SIN_DESGLOSE', 'Otros usos: informática, servicios comunes y resto');
insert into resultados (t) select is((select nombre from usos_energia where codigo = 'ILUMINACION'), 'Alumbrado', 'El uso de iluminación se llama Alumbrado');

-- =========================================================
-- 2. Validaciones
-- =========================================================
insert into resultados (t) select throws_like($$ insert into cuadros_electricos (id_edificio, id_planta, codigo, nombre)
                      values ('fd200000-0000-0000-0000-000000000001', 'fd300000-0000-0000-0000-000000000009', 'MAL', 'Mal') $$,
  '%planta del cuadro no es de este edificio%', 'Un cuadro no puede estar en una planta de otro edificio');
insert into resultados (t) select throws_ok($$ insert into cuadros_electricos (id_edificio, id_planta, id_recinto, codigo, nombre)
                    values ('fd200000-0000-0000-0000-000000000001', 'fd300000-0000-0000-0000-000000000000',
                            'fd400000-0000-0000-0000-000000000001', 'DOS', 'Dos') $$,
  '23514', null, 'Un cuadro está en una planta o en un recinto, no en los dos');
insert into resultados (t) select throws_like($$ update cuadros_electricos set id_cuadro_padre = 'fd500000-0000-0000-0000-000000000001'
                      where id = 'fd500000-0000-0000-0000-000000000000' $$,
  '%no puede depender de sí mismo%', 'No se permiten ciclos entre cuadros');
insert into resultados (t) select throws_like($$ select pg_temp.sensor('fd800000-0000-0000-0000-0000000000a1', 'X1', 'fd400000-0000-0000-0000-000000000000', 'ELECTRICIDAD', 'CUADRO', null, null) $$,
  '%Indique el cuadro%', 'Un medidor de cuadro necesita su cuadro');
insert into resultados (t) select throws_ok($$ select pg_temp.sensor('fd800000-0000-0000-0000-0000000000a2', 'X2', 'fd400000-0000-0000-0000-000000000000', 'ELECTRICIDAD', 'CUADRO', null, 'fd500000-0000-0000-0000-000000000000') $$,
  '23505', null, 'Un cuadro tiene un solo medidor total activo');
insert into resultados (t) select throws_like($$ select pg_temp.sensor('fd800000-0000-0000-0000-0000000000a3', 'X3', 'fd400000-0000-0000-0000-000000000000', 'ELECTRICIDAD', 'USO', 'ILUMINACION', 'fd500000-0000-0000-0000-000000000009') $$,
  '%no es de este edificio%', 'El cuadro de un submedidor debe ser de su edificio');
insert into resultados (t) select throws_like($$ select pg_temp.sensor('fd800000-0000-0000-0000-0000000000a4', 'X4', 'fd400000-0000-0000-0000-000000000000', 'GAS', 'USO', 'HVAC_CALEFACCION', 'fd500000-0000-0000-0000-000000000000') $$,
  '%Solo los medidores eléctricos%', 'Un contador de gas no depende de un cuadro eléctrico');
insert into resultados (t) select throws_ok($$ update sensores set id_uso_energia = (select id from usos_energia where codigo = 'ILUMINACION')
                    where id = 'fd800000-0000-0000-0000-000000000002' $$,
  '23514', null, 'Un medidor de cuadro no lleva uso');

-- =========================================================
-- 3. Motor: otros usos de cada cuadro por diferencia
-- =========================================================
insert into resultados (t) select lives_ok($$ select motor_calcular('fd200000-0000-0000-0000-000000000001',
                    timestamptz '2026-10-20 00:00 Europe/Madrid', timestamptz '2026-10-21 00:00 Europe/Madrid') $$,
  'El motor calcula el día');

create function pg_temp.uso(p_uso text, p_cuadro text) returns numeric language sql as $$
  select round(sum(valor)::numeric, 1) from resumenes_diarios_usos
  where id_edificio = 'fd200000-0000-0000-0000-000000000001' and fecha = '2026-10-20'
    and id_uso_energia = (select id from usos_energia where codigo = p_uso)
    and id_cuadro is not distinct from p_cuadro::uuid;
$$;
insert into resultados (t) select is(pg_temp.uso('ILUMINACION', 'fd500000-0000-0000-0000-000000000002'), 192.0, 'Alumbrado de la planta 1, con su cuadro');
insert into resultados (t) select is(pg_temp.uso('OTROS_SIN_DESGLOSE', 'fd500000-0000-0000-0000-000000000000'), 288.0,
  'Otros usos de planta baja = total − alumbrado − total del local que cuelga de él');
insert into resultados (t) select is(pg_temp.uso('OTROS_SIN_DESGLOSE', 'fd500000-0000-0000-0000-000000000001'), 144.0, 'Otros usos del local = total − alumbrado');
insert into resultados (t) select is(pg_temp.uso('OTROS_SIN_DESGLOSE', 'fd500000-0000-0000-0000-000000000002'), 480.0,
  'Otros usos de planta 1 = total − alumbrado − submedidores del cuadro hijo sin medidor');
insert into resultados (t) select is(pg_temp.uso('HVAC_CALEFACCION_ACS', null), 288.0, 'El gas de la caldera es un medidor independiente');

-- =========================================================
-- 4. Sankey con columna de detalle
-- =========================================================
create function pg_temp.enlace(p_origen text, p_destino text, p_nivel text default 'EDIFICIO') returns numeric language sql as $$
  select (e->>'valor')::numeric
  from jsonb_array_elements(sankey_energia(p_nivel, case p_nivel when 'EDIFICIO' then 'fd200000-0000-0000-0000-000000000001'::uuid
                                                                 else 'fd100000-0000-0000-0000-000000000001'::uuid end,
                                           '2026-10-20', '2026-10-20')->'enlaces') e
  where e->>'origen' = p_origen and e->>'destino' = p_destino;
$$;
insert into resultados (t) select is(pg_temp.enlace('ELECTRICIDAD', 'ILUMINACION'), 336.000, 'Electricidad → Alumbrado: 96 + 48 + 192');
insert into resultados (t) select is(pg_temp.enlace('ILUMINACION', 'ILUMINACION:fd500000-0000-0000-0000-000000000001'), 48.000, 'Alumbrado → Alumbrado del local');
insert into resultados (t) select is(pg_temp.enlace('OTROS', 'OTROS_NO_MEDIDO'), 576.000, 'Lo que el general no reparte entre cuadros va a "no medido"');
insert into resultados (t) select is(pg_temp.enlace('GAS', 'HVAC') || ' ' || pg_temp.enlace('HVAC', 'HVAC_CALEFACCION_ACS'), '288.000 288.000',
  'Gas → HVAC → Calefacción y ACS');
insert into resultados (t) select is((select string_agg(n->>'nombre', ' | ' order by ord)
           from jsonb_array_elements(sankey_energia('EDIFICIO', 'fd200000-0000-0000-0000-000000000001', '2026-10-20', '2026-10-20')->'nodos')
                with ordinality x(n, ord) where (n->>'nivel')::int = 3),
  'Calefacción y ACS | Alumbrado · Planta baja | Alumbrado · Local comercial | Alumbrado · Planta 1 | Informática · Planta 1 | Otros usos · Planta baja | Otros usos · Local comercial | Otros usos · Planta 1 | Otros usos · no medido',
  'Detalle ordenado por uso y planta, con el nombre de la ubicación del cuadro');
insert into resultados (t) select is(pg_temp.enlace('OTROS', 'OTROS_SIN_DESGLOSE', 'CLIENTE'), 912.000,
  'En el cliente no se desglosa por cuadro: otros usos medidos de todos los cuadros (288 + 144 + 480)');

delete from motor_pendiente where id_edificio = 'fd200000-0000-0000-0000-000000000001';
update cuadros_electricos set id_cuadro_padre = 'fd500000-0000-0000-0000-000000000000' where id = 'fd500000-0000-0000-0000-000000000003';
insert into resultados (t) select is((select motivo from motor_pendiente where id_edificio = 'fd200000-0000-0000-0000-000000000001'), 'CONFIGURACION',
  'Cambiar de qué cuadro cuelga otro anota el recálculo del edificio');

create temp table sustituto as select sustituir_sensor('fd800000-0000-0000-0000-000000000006') as id;
insert into resultados (t) select is((select s.funcion_medidor || ' ' || s.id_cuadro::text from sensores s join sustituto n on n.id = s.id),
  'CUADRO fd500000-0000-0000-0000-000000000002', 'Al sustituir un medidor se conservan su función y su cuadro');

-- =========================================================
-- 5. Acceso: el Partner del edificio ve y crea cuadros; otro Partner no
-- =========================================================
insert into auth.users (id, email) values
  ('e9500000-0000-0000-0000-000000000001', 'a@cuadros.test'), ('e9500000-0000-0000-0000-000000000002', 'b@cuadros.test');
insert into usuarios (id, auth_user_id, nombre, email, id_rol)
select x.id::uuid, x.auth::uuid, 'U', x.mail, r.id
from (values ('fd900000-0000-0000-0000-000000000001', 'e9500000-0000-0000-0000-000000000001', 'a@cuadros.test'),
             ('fd900000-0000-0000-0000-000000000002', 'e9500000-0000-0000-0000-000000000002', 'b@cuadros.test')) x(id, auth, mail)
join roles r on r.codigo = 'ADMIN_PARTNER';
insert into usuarios_partners (id_usuario, id_proveedor) values
  ('fd900000-0000-0000-0000-000000000001', 'fd000000-0000-0000-0000-00000000000a'),
  ('fd900000-0000-0000-0000-000000000002', 'fd000000-0000-0000-0000-00000000000b');
create function pg_temp.login(p_auth uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_auth, 'role', 'authenticated', 'aal', 'aal2',
                    'session_id', gen_random_uuid())::text, true);
$$;

select pg_temp.login('e9500000-0000-0000-0000-000000000001');
set local role authenticated;
insert into resultados (t) select is((select count(*)::integer from cuadros_electricos), 4, 'El Partner del edificio ve sus cuadros');
insert into resultados (t) select lives_ok($$ insert into cuadros_electricos (id_edificio, id_planta, codigo, nombre)
                   values ('fd200000-0000-0000-0000-000000000001', 'fd300000-0000-0000-0000-000000000001', 'CP1B', 'Cuadro 2 planta 1') $$,
  'El Partner del edificio da de alta un cuadro');
reset role;

select pg_temp.login('e9500000-0000-0000-0000-000000000002');
set local role authenticated;
insert into resultados (t) select is((select count(*)::integer from cuadros_electricos), 0, 'Otro Partner no ve los cuadros');
insert into resultados (t) select throws_ok($$ insert into cuadros_electricos (id_edificio, id_planta, codigo, nombre)
                    values ('fd200000-0000-0000-0000-000000000001', 'fd300000-0000-0000-0000-000000000001', 'INTRUSO', 'Intruso') $$,
  '42501', null, 'Otro Partner no puede crear cuadros en el edificio');
reset role;

do $$
declare v_total int; v_fallos int; v_detalle text;
begin
  select count(*), count(*) filter (where t like 'not ok%'),
         string_agg(split_part(t, E'\n', 1), E'\n' order by n) filter (where t like 'not ok%')
    into v_total, v_fallos, v_detalle from resultados;
  if v_fallos = 0 and v_total = 29 then
    raise exception 'RESULTADO: % de 29 pruebas OK. Todo correcto (los datos de prueba se han deshecho).', v_total;
  else
    raise exception E'RESULTADO: % pruebas ejecutadas, % FALLAN:\n%', v_total, v_fallos, coalesce(v_detalle, '(faltan pruebas)');
  end if;
end;
$$;
