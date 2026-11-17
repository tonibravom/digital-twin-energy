-- =========================================================
-- PRUEBAS DE SUMINISTROS Y MEDIDOR GENERAL (migración 048, D57)
-- Ejecutar con:  npx supabase test db
-- =========================================================
begin;
set search_path = public, extensions;

select plan(16);

insert into proveedores (id, codigo, nombre) values
  ('fc000000-0000-0000-0000-00000000000a', 'SA', 'Partner suministros A'),
  ('fc000000-0000-0000-0000-00000000000b', 'SB', 'Partner suministros B');
insert into clientes (id, codigo, nombre) values ('fc100000-0000-0000-0000-000000000001', 'SC', 'Cliente suministros');
insert into proveedores_clientes (id_proveedor, id_cliente) values
  ('fc000000-0000-0000-0000-00000000000a', 'fc100000-0000-0000-0000-000000000001');
insert into edificios (id, id_cliente, codigo, nombre, zona_horaria) values
  ('fc200000-0000-0000-0000-000000000001', 'fc100000-0000-0000-0000-000000000001', 'SE', 'Edificio suministros', 'Europe/Madrid');
insert into proveedores_edificios (id_proveedor, id_edificio) values
  ('fc000000-0000-0000-0000-00000000000a', 'fc200000-0000-0000-0000-000000000001');
insert into plantas (id, id_edificio, codigo, nombre, nivel) values
  ('fc300000-0000-0000-0000-000000000001', 'fc200000-0000-0000-0000-000000000001', 'P0', 'Planta baja', 0);
insert into recintos (id, id_planta, codigo, nombre) values
  ('fc400000-0000-0000-0000-000000000001', 'fc300000-0000-0000-0000-000000000001', 'CC', 'Cuarto de contadores');
insert into conexiones (id, id_edificio, id_tipo_conexion, codigo, nombre)
select 'fc500000-0000-0000-0000-000000000001', 'fc200000-0000-0000-0000-000000000001', id, 'HTTP', 'Pasarela'
from tipos_conexion where codigo = 'ENVIO_HTTP';
insert into dispositivos (id, id_recinto, id_conexion, id_tipo_dispositivo, codigo, nombre)
select x.id::uuid, 'fc400000-0000-0000-0000-000000000001', 'fc500000-0000-0000-0000-000000000001', t.id, x.cod, x.nom
from (values ('fc600000-0000-0000-0000-000000000001', 'MED-E', 'Medidor general eléctrico'),
             ('fc600000-0000-0000-0000-000000000002', 'MED-G', 'Contador de gas')) x(id, cod, nom),
     tipos_dispositivo t where t.codigo = 'CONTADOR_ENERGIA';

create function pg_temp.sensor(p_id text, p_disp text, p_cod text, p_fam text, p_nat text, p_uni text, p_ene text) returns void language sql as $$
  insert into sensores (id, id_dispositivo, id_conexion, id_recinto, id_familia, id_naturaleza, id_tratamiento, id_tipo_energia, codigo, nombre, unidad)
  select p_id::uuid, p_disp::uuid, case when p_disp is null then 'fc500000-0000-0000-0000-000000000001'::uuid end,
         'fc400000-0000-0000-0000-000000000001', f.id, n.id, t.id, te.id, p_cod, p_cod, p_uni
  from familias_sensor f, naturalezas_sensor n, tratamientos_sensor t, tipos_energia te
  where f.codigo = p_fam and n.codigo = p_nat and t.codigo = case p_nat when 'ACUMULATIVA' then 'DELTA' else 'PROMEDIO' end
    and te.codigo = p_ene;
$$;
create function pg_temp.parametro(p_sensor text, p_par text) returns void language sql as $$
  update sensores set id_parametro_medidor = (select id from parametros_medidor where codigo = p_par) where id = p_sensor::uuid;
$$;
select pg_temp.sensor('fc700000-0000-0000-0000-000000000001', 'fc600000-0000-0000-0000-000000000001', 'E', 'ENERGIA', 'ACUMULATIVA', 'kWh', 'ELECTRICIDAD');
select pg_temp.sensor('fc700000-0000-0000-0000-000000000002', 'fc600000-0000-0000-0000-000000000001', 'P', 'POTENCIA', 'INSTANTANEA', 'kW', 'ELECTRICIDAD');
select pg_temp.sensor('fc700000-0000-0000-0000-000000000003', 'fc600000-0000-0000-0000-000000000001', 'FP', 'FACTOR_POTENCIA', 'INSTANTANEA', '-', 'ELECTRICIDAD');
select pg_temp.sensor('fc700000-0000-0000-0000-000000000004', 'fc600000-0000-0000-0000-000000000001', 'V1', 'TENSION', 'INSTANTANEA', 'V', 'ELECTRICIDAD');
select pg_temp.sensor('fc700000-0000-0000-0000-000000000005', 'fc600000-0000-0000-0000-000000000002', 'G', 'OTRA', 'ACUMULATIVA', 'm³', 'GAS');
select pg_temp.sensor('fc700000-0000-0000-0000-000000000006', null, 'SUELTO', 'POTENCIA', 'INSTANTANEA', 'kW', 'ELECTRICIDAD');

-- 1. Catálogo y validación de los parámetros
select is((select array_agg(codigo::text order by orden) from parametros_medidor where tipo_suministro = 'ELECTRICIDAD' and obligatorio),
  '{ENERGIA_ACTIVA_IMPORTADA,POTENCIA_ACTIVA,FACTOR_POTENCIA}'::text[],
  'Electricidad: consumo, potencia y cos φ son obligatorios');
select throws_like($$ select pg_temp.parametro('fc700000-0000-0000-0000-000000000002', 'FACTOR_POTENCIA') $$,
  '%no corresponde a un sensor de la familia POTENCIA%', 'El parámetro tiene que corresponder a la familia del sensor');
select throws_like($$ select pg_temp.parametro('fc700000-0000-0000-0000-000000000006', 'POTENCIA_ACTIVA') $$,
  '%tiene que pertenecer a un dispositivo%', 'Un parámetro del medidor solo se asigna a sensores de un dispositivo');

select pg_temp.parametro('fc700000-0000-0000-0000-000000000001', 'ENERGIA_ACTIVA_IMPORTADA');
select pg_temp.parametro('fc700000-0000-0000-0000-000000000002', 'POTENCIA_ACTIVA');
select pg_temp.parametro('fc700000-0000-0000-0000-000000000004', 'TENSION_L1');
select pg_temp.parametro('fc700000-0000-0000-0000-000000000005', 'CONSUMO_GAS');
select throws_ok($$ select pg_temp.parametro('fc700000-0000-0000-0000-000000000004', 'POTENCIA_ACTIVA') $$,
  '23514', null, 'Cada sensor mide un parámetro de su familia (tensión no es potencia)');

-- 2. Bloqueo de la parametrización
select ok(exists (select 1 from jsonb_array_elements(estado_parametrizacion_edificio('fc200000-0000-0000-0000-000000000001')->'comprobaciones') c
                  where c->>'codigo' = 'SUMINISTRO_ELECTRICO' and not (c->>'ok')::boolean and (c->>'bloqueante')::boolean),
  'Sin suministro eléctrico no se puede cerrar la parametrización');

insert into suministros (id, id_edificio, codigo, nombre, tipo, comercializadora, numero_contrato) values
  ('fc800000-0000-0000-0000-000000000001', 'fc200000-0000-0000-0000-000000000001', 'RED', 'Electricidad', 'ELECTRICIDAD', 'Comercializadora X', 'C-1'),
  ('fc800000-0000-0000-0000-000000000002', 'fc200000-0000-0000-0000-000000000001', 'GAS', 'Gas', 'GAS', null, null);
insert into suministros_dispositivos (id_suministro, id_dispositivo, medidor_general) values
  ('fc800000-0000-0000-0000-000000000001', 'fc600000-0000-0000-0000-000000000001', true),
  ('fc800000-0000-0000-0000-000000000002', 'fc600000-0000-0000-0000-000000000002', true);

select ok(exists (select 1 from jsonb_array_elements(estado_parametrizacion_edificio('fc200000-0000-0000-0000-000000000001')->'comprobaciones') c
                  where c->>'codigo' = 'MEDIDOR_GENERAL' and not (c->>'ok')::boolean and (c->>'bloqueante')::boolean
                    and c->>'detalle' like '%Electricidad%no mide Factor de potencia%'),
  'Un medidor general eléctrico sin cos φ bloquea, y dice qué falta');
select pg_temp.parametro('fc700000-0000-0000-0000-000000000003', 'FACTOR_POTENCIA');
select ok(not exists (select 1 from jsonb_array_elements(estado_parametrizacion_edificio('fc200000-0000-0000-0000-000000000001')->'comprobaciones') c
                      where c->>'codigo' in ('SUMINISTRO_ELECTRICO', 'MEDIDOR_GENERAL') and not (c->>'ok')::boolean),
  'Con consumo, potencia y cos φ se desbloquea (los opcionales no hacen falta)');
select throws_ok($$ insert into suministros_dispositivos (id_suministro, id_dispositivo, medidor_general)
                    values ('fc800000-0000-0000-0000-000000000001', 'fc600000-0000-0000-0000-000000000002', true) $$,
  '23505', null, 'Un solo medidor general por suministro');

-- 3. Etiqueta del medidor: los opcionales no ocupan fila
select is(filas_etiqueta_dispositivo('fc600000-0000-0000-0000-000000000001'), 3,
  'La etiqueta del medidor general muestra solo los 3 obligatorios (la tensión, al desplegarla)');

-- 4. Fichas de los suministros
select is((select array_agg(f->>'tipo') from jsonb_array_elements(suministros_edificio('fc200000-0000-0000-0000-000000000001')) f),
  '{ELECTRICIDAD,GAS}'::text[], 'Las fichas salen ordenadas: electricidad, gas, agua');
select is((select jsonb_array_length(f->'parametros') from jsonb_array_elements(suministros_edificio('fc200000-0000-0000-0000-000000000001')) f
           where f->>'tipo' = 'ELECTRICIDAD'), 4,
  'La ficha eléctrica lleva los obligatorios y los opcionales que tiene el medidor');

-- 5. Consumo mensual: diferencia del contador en los cambios de mes (hora del edificio)
create temp table meses as
select (date_trunc('month', now() at time zone 'Europe/Madrid') - interval '1 month')::timestamp as ini,
       date_trunc('month', now() at time zone 'Europe/Madrid')::timestamp as fin;
insert into lecturas (id_sensor, fecha_hora, valor)
select x.s::uuid, (x.t at time zone 'Europe/Madrid'), x.v
from meses, lateral (values
  ('fc700000-0000-0000-0000-000000000001', meses.ini - interval '1 hour', 1000.0),
  ('fc700000-0000-0000-0000-000000000001', meses.fin - interval '1 hour', 1500.0),
  ('fc700000-0000-0000-0000-000000000005', meses.ini - interval '1 hour', 10.0),
  ('fc700000-0000-0000-0000-000000000005', meses.fin - interval '1 hour', 110.0)) x(s, t, v);
select is((select consumo from consumo_mensual_suministro('fc800000-0000-0000-0000-000000000001') c, meses
           where c.anio = extract(year from meses.ini) and c.mes = extract(month from meses.ini)), 500::float8,
  'Consumo eléctrico del mes pasado = lectura final − lectura inicial');
select is((select round(consumo_kwh)::integer from consumo_mensual_suministro('fc800000-0000-0000-0000-000000000002') c, meses
           where c.anio = extract(year from meses.ini) and c.mes = extract(month from meses.ini)),
  round(100 * private.factor_kwh_sensor('m³', 'GAS', current_date))::integer,
  'El gas del mes se da también en kWh con la conversión del motor');
select is((select count(*)::integer from consumo_mensual_suministro('fc800000-0000-0000-0000-000000000001')),
  12 + extract(month from now() at time zone 'Europe/Madrid')::integer, 'Meses del año pasado y de este hasta el actual');

-- 6. Al sustituir el sensor, el nuevo mide lo mismo
create temp table sustituto as select sustituir_sensor('fc700000-0000-0000-0000-000000000003') as id;
select is((select pm.codigo::text from sensores s join parametros_medidor pm on pm.id = s.id_parametro_medidor
           where s.id = (select id from sustituto)), 'FACTOR_POTENCIA',
  'El sensor sustituto conserva el parámetro del medidor');

-- 7. Acceso: otro Partner no ve los suministros
insert into auth.users (id, email) values ('e9900000-0000-0000-0000-000000000002', 'b@suministros.test');
insert into usuarios (id, auth_user_id, nombre, email, id_rol)
select 'fc990000-0000-0000-0000-000000000002', 'e9900000-0000-0000-0000-000000000002', 'B', 'b@suministros.test', r.id
from roles r where r.codigo = 'ADMIN_PARTNER';
insert into usuarios_partners (id_usuario, id_proveedor) values ('fc990000-0000-0000-0000-000000000002', 'fc000000-0000-0000-0000-00000000000b');
select set_config('request.jwt.claims', json_build_object('sub', 'e9900000-0000-0000-0000-000000000002', 'role', 'authenticated',
                  'aal', 'aal2', 'session_id', gen_random_uuid())::text, true);
set local role authenticated;
select is(suministros_edificio('fc200000-0000-0000-0000-000000000001'), '[]'::jsonb,
  'Otro Partner no ve las fichas de los suministros del edificio');
reset role;

select * from finish();
rollback;
