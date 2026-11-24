-- =========================================================
-- PRUEBAS DE LOS INFORMES SEMANAL Y MENSUAL (migración 056, D61)
-- =========================================================
begin;
set search_path = public, extensions;

select plan(16);

insert into proveedores (id, codigo, nombre) values
  ('fd000000-0000-0000-0000-00000000000a', 'INA', 'Partner alarmas A'),
  ('fd000000-0000-0000-0000-00000000000b', 'INB', 'Partner alarmas B');
insert into clientes (id, codigo, nombre) values ('fd100000-0000-0000-0000-000000000001', 'INC', 'Cliente alarmas');
insert into proveedores_clientes (id_proveedor, id_cliente) values
  ('fd000000-0000-0000-0000-00000000000a', 'fd100000-0000-0000-0000-000000000001');
insert into edificios (id, id_cliente, codigo, nombre, zona_horaria) values
  ('fd200000-0000-0000-0000-000000000001', 'fd100000-0000-0000-0000-000000000001', 'INE', 'Edificio alarmas', 'Europe/Madrid');
insert into proveedores_edificios (id_proveedor, id_edificio) values
  ('fd000000-0000-0000-0000-00000000000a', 'fd200000-0000-0000-0000-000000000001');
insert into plantas (id, id_edificio, codigo, nombre, nivel) values
  ('fd300000-0000-0000-0000-000000000001', 'fd200000-0000-0000-0000-000000000001', 'P0', 'Planta baja', 0);
insert into recintos (id, id_planta, codigo, nombre) values
  ('fd400000-0000-0000-0000-000000000001', 'fd300000-0000-0000-0000-000000000001', 'CC', 'Cuarto de contadores');
insert into conexiones (id, id_edificio, id_tipo_conexion, codigo, nombre)
select 'fd500000-0000-0000-0000-000000000001', 'fd200000-0000-0000-0000-000000000001', id, 'HTTP', 'Pasarela'
from tipos_conexion where codigo = 'ENVIO_HTTP';
insert into dispositivos (id, id_recinto, id_conexion, id_tipo_dispositivo, codigo, nombre)
select 'fd600000-0000-0000-0000-000000000001', 'fd400000-0000-0000-0000-000000000001', 'fd500000-0000-0000-0000-000000000001', t.id, 'CAG', 'Contador de agua'
from tipos_dispositivo t where t.codigo = 'CONTADOR_ENERGIA';
create function pg_temp.sensor(p_id text, p_disp text, p_cod text, p_fam text, p_nat text, p_uni text, p_ene text) returns void language sql as $$
  insert into sensores (id, id_dispositivo, id_conexion, id_recinto, id_familia, id_naturaleza, id_tratamiento, id_tipo_energia, codigo, nombre, unidad)
  select p_id::uuid, p_disp::uuid, case when p_disp is null then 'fd500000-0000-0000-0000-000000000001'::uuid end,
         'fd400000-0000-0000-0000-000000000001', f.id, n.id, t.id, te.id, p_cod, p_cod, p_uni
  from familias_sensor f, naturalezas_sensor n, tratamientos_sensor t, tipos_energia te
  where f.codigo = p_fam and n.codigo = p_nat and t.codigo = case p_nat when 'ACUMULATIVA' then 'DELTA' else 'PROMEDIO' end
    and te.codigo = p_ene;
$$;
select pg_temp.sensor('fd700000-0000-0000-0000-000000000001', 'fd600000-0000-0000-0000-000000000001', 'AGUA', 'OTRA', 'ACUMULATIVA', 'm³', 'AGUA');
select pg_temp.sensor('fd700000-0000-0000-0000-000000000002', 'fd600000-0000-0000-0000-000000000001', 'PRES', 'PRESION', 'INSTANTANEA', 'bar', 'AGUA');
select pg_temp.sensor('fd700000-0000-0000-0000-000000000003', null, 'TEMP', 'TEMPERATURA', 'INSTANTANEA', '°C', 'OTRA');
update sensores set id_parametro_medidor = (select id from parametros_medidor where codigo = 'CONSUMO_AGUA') where id = 'fd700000-0000-0000-0000-000000000001';
insert into suministros (id, id_edificio, codigo, nombre, tipo) values
  ('fd800000-0000-0000-0000-000000000001', 'fd200000-0000-0000-0000-000000000001', 'AGUA', 'Agua', 'AGUA');
insert into suministros_dispositivos (id_suministro, id_dispositivo, medidor_general) values
  ('fd800000-0000-0000-0000-000000000001', 'fd600000-0000-0000-0000-000000000001', true);

-- Usuarios: dos técnicos del Partner A (el segundo recibe el escalado) y uno del Partner B
insert into auth.users (id, email) values
  ('e9d00000-0000-0000-0000-000000000001', 'a1@informes.test'), ('e9d00000-0000-0000-0000-000000000002', 'a2@informes.test'),
  ('e9d00000-0000-0000-0000-000000000003', 'b@informes.test');
insert into usuarios (id, auth_user_id, nombre, email, id_rol)
select x.id::uuid, x.auth::uuid, x.nom, x.mail, r.id
from (values ('fd900000-0000-0000-0000-000000000001', 'e9d00000-0000-0000-0000-000000000001', 'Técnica A', 'a1@informes.test'),
             ('fd900000-0000-0000-0000-000000000002', 'e9d00000-0000-0000-0000-000000000002', 'Jefe A', 'a2@informes.test'),
             ('fd900000-0000-0000-0000-000000000003', 'e9d00000-0000-0000-0000-000000000003', 'Técnico B', 'b@informes.test')) x(id, auth, nom, mail)
join roles r on r.codigo = 'TECNICO_PARTNER';
insert into usuarios_partners (id_usuario, id_proveedor) values
  ('fd900000-0000-0000-0000-000000000001', 'fd000000-0000-0000-0000-00000000000a'),
  ('fd900000-0000-0000-0000-000000000002', 'fd000000-0000-0000-0000-00000000000a'),
  ('fd900000-0000-0000-0000-000000000003', 'fd000000-0000-0000-0000-00000000000b');
create function pg_temp.login(p_auth uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_auth, 'role', 'authenticated', 'aal', 'aal2',
                    'session_id', gen_random_uuid())::text, true);
$$;
create function pg_temp.presion(p_valor numeric) returns void language sql as $$
  delete from lecturas where id_sensor = 'fd700000-0000-0000-0000-000000000002';
  insert into lecturas (id_sensor, fecha_hora, valor) values
    ('fd700000-0000-0000-0000-000000000002', now() - interval '4 minutes', p_valor),
    ('fd700000-0000-0000-0000-000000000002', now() - interval '1 minute', p_valor);
$$;
create function pg_temp.evento() returns setof eventos_alarma language sql as $$
  select ea.* from eventos_alarma ea join reglas_alarma ra on ra.id = ea.id_regla_alarma
  where ra.codigo = 'AGUA_PRESION_EXCESIVA-AGUA';
$$;

-- Un administrador del Partner A (para el logo)
insert into auth.users (id, email) values ('e9d00000-0000-0000-0000-000000000009', 'admin@informes.test');
insert into usuarios (id, auth_user_id, nombre, email, id_rol)
select 'fd900000-0000-0000-0000-000000000009', 'e9d00000-0000-0000-0000-000000000009', 'Admin A', 'admin@informes.test', r.id
from roles r where r.codigo = 'ADMIN_PARTNER';
insert into usuarios_partners (id_usuario, id_proveedor) values ('fd900000-0000-0000-0000-000000000009', 'fd000000-0000-0000-0000-00000000000a');

-- Consumos diarios de octubre de 2026 (100 kWh de electricidad y 2 m³ de agua al día) y de octubre de 2025 (80 kWh)
insert into resumenes_diarios (id_edificio, fecha, indicador, valor, completo, origen)
select 'fd200000-0000-0000-0000-000000000001', d::date, i.ind, i.v, true, 'MOTOR'
from generate_series('2026-10-01'::date, '2026-10-31'::date, interval '1 day') d,
     (values ('CONSUMO_ELECTRICIDAD', 100.0), ('CONSUMO_AGUA', 2.0)) i(ind, v);
insert into resumenes_diarios (id_edificio, fecha, indicador, valor, completo, origen)
select 'fd200000-0000-0000-0000-000000000001', d::date, 'CONSUMO_ELECTRICIDAD', 80.0, true, 'MOTOR'
from generate_series('2025-10-01'::date, '2025-10-31'::date, interval '1 day') d;

-- 1. Generar (Partner A) y aislamiento (Partner B)
select pg_temp.login('e9d00000-0000-0000-0000-000000000003');
set local role authenticated;
select throws_ok($$ select generar_informe('fd200000-0000-0000-0000-000000000001', 'MENSUAL', '2026-11-15') $$,
  '42501', null, 'El Partner B NO puede generar informes del edificio del Partner A');
reset role;
select pg_temp.login('e9d00000-0000-0000-0000-000000000001');
set local role authenticated;
select lives_ok($$ select generar_informe('fd200000-0000-0000-0000-000000000001', 'MENSUAL', '2026-11-15') $$, 'El Partner A genera el mensual');
select is((select desde || '/' || hasta from informes where tipo = 'MENSUAL'), '2026-10-01/2026-10-31', 'Es el mes anterior completo');
select is((select (datos->'energia'->'actual'->>'energia')::numeric from informes where tipo = 'MENSUAL'), 3100.0, 'Energía consumida del mes');
select is((select (datos->'energia'->'actual'->>'agua')::numeric from informes where tipo = 'MENSUAL'), 62.00, 'Agua del mes');
select is((select (datos->'energia'->'anio_anterior'->>'energia')::numeric from informes where tipo = 'MENSUAL'), 2480.0, 'Mismo mes del año anterior');
select is((select jsonb_array_length(datos->'diario') from informes where tipo = 'MENSUAL'), 31, 'Un punto por día');
select is((select datos->'marca'->'partner'->>'nombre' from informes where tipo = 'MENSUAL'), 'Partner alarmas A', 'Lleva la marca del Partner');
select lives_ok($$ select guardar_destinatarios_informes('fd200000-0000-0000-0000-000000000001',
                    '{fd900000-0000-0000-0000-000000000001}', '{fd900000-0000-0000-0000-000000000001,fd900000-0000-0000-0000-000000000002}') $$,
  'El Partner A elige los destinatarios');
select throws_like($$ select guardar_destinatarios_informes('fd200000-0000-0000-0000-000000000001', '{fd900000-0000-0000-0000-000000000003}', '{}') $$,
  '%no tiene acceso%', 'No puede poner a un usuario de otro Partner');
select throws_ok($$ select fijar_logo_partner('fd000000-0000-0000-0000-00000000000a', 'proveedores/fd000000-0000-0000-0000-00000000000a/logo.png') $$,
  '42501', null, 'Un técnico no cambia el logo del Partner');
reset role;
select pg_temp.login('e9d00000-0000-0000-0000-000000000009');
set local role authenticated;
select lives_ok($$ select fijar_logo_partner('fd000000-0000-0000-0000-00000000000a', 'proveedores/fd000000-0000-0000-0000-00000000000a/logo.png') $$,
  'El administrador del Partner sí');
reset role;
select pg_temp.login('e9d00000-0000-0000-0000-000000000003');
set local role authenticated;
select is((select count(*)::integer from informes where id_edificio = 'fd200000-0000-0000-0000-000000000001'), 0, 'El Partner B NO ve los informes del Partner A');
reset role;

-- 2. Cada mañana: el día 1 el mensual (ya existe: no se repite) y los lunes el semanal, con su email
select is((preparar_informes('2026-11-02')->>'informes')::integer, 1, 'El lunes 2/11 se genera el semanal (el mensual ya estaba)');
select is((select array_agg(destinatario::text order by destinatario) from notificaciones where motivo = 'INFORME_SEMANAL'),
  '{a1@informes.test}'::text[], 'Email del semanal solo a quien lo tiene marcado');
select is((preparar_informes('2026-11-02')->>'informes')::integer, 0, 'No se repite');

select * from finish();
rollback;
