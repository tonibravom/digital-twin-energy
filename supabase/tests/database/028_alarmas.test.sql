-- =========================================================
-- PRUEBAS DEL MOTOR DE ALARMAS (migración 053, D59)
-- Reglas de la plataforma, niveles y avisos, ciclo de vida
-- (ACTIVA → RECONOCIDA → RESUELTA → CERRADA), reapertura,
-- escalado, silencio, resumen diario y aislamiento entre Partners.
-- Ejecutar con:  npx supabase test db
-- =========================================================
begin;
set search_path = public, extensions;

select plan(38);

insert into proveedores (id, codigo, nombre) values
  ('fa000000-0000-0000-0000-00000000000a', 'ALA', 'Partner alarmas A'),
  ('fa000000-0000-0000-0000-00000000000b', 'ALB', 'Partner alarmas B');
insert into clientes (id, codigo, nombre) values ('fa100000-0000-0000-0000-000000000001', 'ALC', 'Cliente alarmas');
insert into proveedores_clientes (id_proveedor, id_cliente) values
  ('fa000000-0000-0000-0000-00000000000a', 'fa100000-0000-0000-0000-000000000001');
insert into edificios (id, id_cliente, codigo, nombre, zona_horaria) values
  ('fa200000-0000-0000-0000-000000000001', 'fa100000-0000-0000-0000-000000000001', 'ALE', 'Edificio alarmas', 'Europe/Madrid');
insert into proveedores_edificios (id_proveedor, id_edificio) values
  ('fa000000-0000-0000-0000-00000000000a', 'fa200000-0000-0000-0000-000000000001');
insert into plantas (id, id_edificio, codigo, nombre, nivel) values
  ('fa300000-0000-0000-0000-000000000001', 'fa200000-0000-0000-0000-000000000001', 'P0', 'Planta baja', 0);
insert into recintos (id, id_planta, codigo, nombre) values
  ('fa400000-0000-0000-0000-000000000001', 'fa300000-0000-0000-0000-000000000001', 'CC', 'Cuarto de contadores');
insert into conexiones (id, id_edificio, id_tipo_conexion, codigo, nombre)
select 'fa500000-0000-0000-0000-000000000001', 'fa200000-0000-0000-0000-000000000001', id, 'HTTP', 'Pasarela'
from tipos_conexion where codigo = 'ENVIO_HTTP';
insert into dispositivos (id, id_recinto, id_conexion, id_tipo_dispositivo, codigo, nombre)
select 'fa600000-0000-0000-0000-000000000001', 'fa400000-0000-0000-0000-000000000001', 'fa500000-0000-0000-0000-000000000001', t.id, 'CAG', 'Contador de agua'
from tipos_dispositivo t where t.codigo = 'CONTADOR_ENERGIA';
create function pg_temp.sensor(p_id text, p_disp text, p_cod text, p_fam text, p_nat text, p_uni text, p_ene text) returns void language sql as $$
  insert into sensores (id, id_dispositivo, id_conexion, id_recinto, id_familia, id_naturaleza, id_tratamiento, id_tipo_energia, codigo, nombre, unidad)
  select p_id::uuid, p_disp::uuid, case when p_disp is null then 'fa500000-0000-0000-0000-000000000001'::uuid end,
         'fa400000-0000-0000-0000-000000000001', f.id, n.id, t.id, te.id, p_cod, p_cod, p_uni
  from familias_sensor f, naturalezas_sensor n, tratamientos_sensor t, tipos_energia te
  where f.codigo = p_fam and n.codigo = p_nat and t.codigo = case p_nat when 'ACUMULATIVA' then 'DELTA' else 'PROMEDIO' end
    and te.codigo = p_ene;
$$;
select pg_temp.sensor('fa700000-0000-0000-0000-000000000001', 'fa600000-0000-0000-0000-000000000001', 'AGUA', 'OTRA', 'ACUMULATIVA', 'm³', 'AGUA');
select pg_temp.sensor('fa700000-0000-0000-0000-000000000002', 'fa600000-0000-0000-0000-000000000001', 'PRES', 'PRESION', 'INSTANTANEA', 'bar', 'AGUA');
select pg_temp.sensor('fa700000-0000-0000-0000-000000000003', null, 'TEMP', 'TEMPERATURA', 'INSTANTANEA', '°C', 'OTRA');
update sensores set id_parametro_medidor = (select id from parametros_medidor where codigo = 'CONSUMO_AGUA') where id = 'fa700000-0000-0000-0000-000000000001';
insert into suministros (id, id_edificio, codigo, nombre, tipo) values
  ('fa800000-0000-0000-0000-000000000001', 'fa200000-0000-0000-0000-000000000001', 'AGUA', 'Agua', 'AGUA');
insert into suministros_dispositivos (id_suministro, id_dispositivo, medidor_general) values
  ('fa800000-0000-0000-0000-000000000001', 'fa600000-0000-0000-0000-000000000001', true);

-- Usuarios: dos técnicos del Partner A (el segundo recibe el escalado) y uno del Partner B
insert into auth.users (id, email) values
  ('e9a00000-0000-0000-0000-000000000001', 'a1@alarmas.test'), ('e9a00000-0000-0000-0000-000000000002', 'a2@alarmas.test'),
  ('e9a00000-0000-0000-0000-000000000003', 'b@alarmas.test');
insert into usuarios (id, auth_user_id, nombre, email, id_rol)
select x.id::uuid, x.auth::uuid, x.nom, x.mail, r.id
from (values ('fa900000-0000-0000-0000-000000000001', 'e9a00000-0000-0000-0000-000000000001', 'Técnica A', 'a1@alarmas.test'),
             ('fa900000-0000-0000-0000-000000000002', 'e9a00000-0000-0000-0000-000000000002', 'Jefe A', 'a2@alarmas.test'),
             ('fa900000-0000-0000-0000-000000000003', 'e9a00000-0000-0000-0000-000000000003', 'Técnico B', 'b@alarmas.test')) x(id, auth, nom, mail)
join roles r on r.codigo = 'TECNICO_PARTNER';
insert into usuarios_partners (id_usuario, id_proveedor) values
  ('fa900000-0000-0000-0000-000000000001', 'fa000000-0000-0000-0000-00000000000a'),
  ('fa900000-0000-0000-0000-000000000002', 'fa000000-0000-0000-0000-00000000000a'),
  ('fa900000-0000-0000-0000-000000000003', 'fa000000-0000-0000-0000-00000000000b');
create function pg_temp.login(p_auth uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_auth, 'role', 'authenticated', 'aal', 'aal2',
                    'session_id', gen_random_uuid())::text, true);
$$;
create function pg_temp.presion(p_valor numeric) returns void language sql as $$
  delete from lecturas where id_sensor = 'fa700000-0000-0000-0000-000000000002';
  insert into lecturas (id_sensor, fecha_hora, valor) values
    ('fa700000-0000-0000-0000-000000000002', now() - interval '4 minutes', p_valor),
    ('fa700000-0000-0000-0000-000000000002', now() - interval '1 minute', p_valor);
$$;
create function pg_temp.evento() returns setof eventos_alarma language sql as $$
  select ea.* from eventos_alarma ea join reglas_alarma ra on ra.id = ea.id_regla_alarma
  where ra.codigo = 'AGUA_PRESION_EXCESIVA-AGUA';
$$;

-- 1. Catálogo y niveles
select is((select count(*)::integer from tipos_regla_alarma where activo), 21, 'El catálogo de la plataforma tiene 21 reglas');
select is((select array_agg(codigo::text order by prioridad desc) from niveles_alarma where activo),
  '{MUY_CRITICA,CRITICA,AVISO}'::text[], 'Tres niveles: muy crítica, crítica y aviso');
select is((select envio::text from niveles_alarma where codigo = 'MUY_CRITICA'), 'INMEDIATO', 'Solo las muy críticas van por email al momento');

-- 2. Requisitos
select is(requisitos_regla_alarma('fa200000-0000-0000-0000-000000000001', 'AGUA_PRESION_EXCESIVA', 'fa800000-0000-0000-0000-000000000001'),
  '{Presión}'::text[], 'Sin sensor de presión en el contador no se puede activar (y dice qué falta)');
update sensores set id_parametro_medidor = (select id from parametros_medidor where codigo = 'PRESION_AGUA') where id = 'fa700000-0000-0000-0000-000000000002';
select is(requisitos_regla_alarma('fa200000-0000-0000-0000-000000000001', 'AGUA_PRESION_EXCESIVA', 'fa800000-0000-0000-0000-000000000001'),
  '{}'::text[], 'Con el sensor de presión ya se puede');

-- 3. El Partner B no puede configurar alarmas en un edificio que no es suyo
select pg_temp.login('e9a00000-0000-0000-0000-000000000003');
set local role authenticated;
select throws_ok($$ select activar_regla_alarma('fa200000-0000-0000-0000-000000000001', 'AGUA_PRESION_EXCESIVA',
                    'fa800000-0000-0000-0000-000000000001', null, '{}', null, '{fa900000-0000-0000-0000-000000000003}') $$,
  '42501', null, 'El Partner B NO puede activar reglas en el edificio del Partner A');
select is(reglas_alarma_edificio('fa200000-0000-0000-0000-000000000001'), '[]'::jsonb, 'El Partner B NO ve el catálogo del edificio');
select throws_ok($$ select * from usuarios_alarmas_edificio('fa200000-0000-0000-0000-000000000001') $$,
  '42501', null, 'Ni la lista de posibles destinatarios');
reset role;

-- 4. El Partner A activa la regla (de acuerdo con el cliente)
select pg_temp.login('e9a00000-0000-0000-0000-000000000001');
set local role authenticated;
select is((select array_agg(email order by email) from usuarios_alarmas_edificio('fa200000-0000-0000-0000-000000000001')),
  '{a1@alarmas.test,a2@alarmas.test}'::text[], 'Destinatarios posibles: solo quien ve el edificio');
select throws_like($$ select activar_regla_alarma('fa200000-0000-0000-0000-000000000001', 'AGUA_PRESION_EXCESIVA',
                      'fa800000-0000-0000-0000-000000000001') $$,
  '%necesita al menos un destinatario%', 'Una muy crítica necesita destinatario del email');
select throws_like($$ select activar_regla_alarma('fa200000-0000-0000-0000-000000000001', 'AGUA_PRESION_EXCESIVA',
                      'fa800000-0000-0000-0000-000000000001', null, '{}', null, '{fa900000-0000-0000-0000-000000000003}') $$,
  '%no tiene acceso%', 'No se puede poner de destinatario a un usuario de otro Partner');
select throws_like($$ select activar_regla_alarma('fa200000-0000-0000-0000-000000000001', 'ELEC_SIN_SUMINISTRO',
                      'fa800000-0000-0000-0000-000000000001', null, '{}', null, '{fa900000-0000-0000-0000-000000000001}') $$,
  '%no se aplica a este suministro%', 'Una regla eléctrica no se aplica al agua');
select lives_ok($$ select activar_regla_alarma('fa200000-0000-0000-0000-000000000001', 'AGUA_PRESION_EXCESIVA',
                   'fa800000-0000-0000-0000-000000000001', null, '{}', null,
                   '{fa900000-0000-0000-0000-000000000001}', '{fa900000-0000-0000-0000-000000000002}') $$,
  'El Partner A activa «presión excesiva» con destinatario y escalado');
select ok((select (f->'regla'->>'activa')::boolean and f->'regla'->>'nivel' = 'MUY_CRITICA'
           from jsonb_array_elements(reglas_alarma_edificio('fa200000-0000-0000-0000-000000000001')) f
           where f->>'tipo' = 'AGUA_PRESION_EXCESIVA'), 'La pantalla de configuración la muestra activa y muy crítica');
reset role;

-- 5. Se dispara: evento ACTIVA y email inmediato al destinatario (no al de escalado)
select pg_temp.presion(6);
select is((motor_alarmas()->>'abiertas')::integer, 1, 'Con 6 bar sostenidos se abre la alarma');
select is((select array_agg(destinatario::text) from notificaciones n join pg_temp.evento() e on e.id = n.id_evento_alarma where n.motivo = 'INMEDIATO'),
  '{a1@alarmas.test}'::text[], 'Email inmediato solo al destinatario');
select is((motor_alarmas()->>'emails')::integer, 0, 'Mientras sigue, no se repite el email');

-- 6. No se puede cerrar mientras la causa sigue
select pg_temp.login('e9a00000-0000-0000-0000-000000000001');
set local role authenticated;
select throws_like($$ select cerrar_alarma((select id from pg_temp.evento())) $$,
  '%sigue presente%', 'No se puede cerrar una alarma cuya causa sigue');
select throws_like($$ select silenciar_alarma((select id from pg_temp.evento()), now() + interval '40 days', 'Obra') $$,
  '%30 días%', 'Silenciar como máximo 30 días');
select throws_like($$ select silenciar_alarma((select id from pg_temp.evento()), now() + interval '1 day', '') $$,
  '%motivo%', 'Silenciar pide el motivo');
reset role;

-- 7. Escalado: muy crítica sin reconocer pasados los minutos de escalado
update eventos_alarma set fecha_inicio = now() - interval '20 minutes' where id = (select id from pg_temp.evento());
select motor_alarmas();
select is((select array_agg(destinatario::text) from notificaciones n join pg_temp.evento() e on e.id = n.id_evento_alarma where n.motivo = 'ESCALADO'),
  '{a2@alarmas.test}'::text[], 'Sin reconocer a los 15 min se avisa a los de escalado');
select motor_alarmas();
select is((select count(*)::integer from notificaciones where motivo = 'ESCALADO'), 1, 'El escalado se envía una sola vez');

-- 8. Reconocer y silenciar; al caducar el silencio con la causa presente, vuelve a avisar
select pg_temp.login('e9a00000-0000-0000-0000-000000000001');
set local role authenticated;
select reconocer_alarma((select id from pg_temp.evento()), 'Voy de camino');
select lives_ok($$ select silenciar_alarma((select id from pg_temp.evento()), now() + interval '2 hours', 'Revisión del regulador') $$,
  'Se puede silenciar con motivo');
select ok((select (a->>'silenciada_hasta') is not null and a->>'estado' = 'RECONOCIDA'
           from jsonb_array_elements(alarmas_edificio('fa200000-0000-0000-0000-000000000001')) a where a->>'tipo' = 'ALARMA'),
  'La pestaña Alarmas la muestra reconocida y silenciada');
reset role;
update eventos_alarma set silenciada_hasta = now() - interval '1 minute' where id = (select id from pg_temp.evento());
select motor_alarmas();
select is((select count(*)::integer from notificaciones where motivo = 'REAVISO'), 1, 'Al acabar el silencio con la causa presente, vuelve a avisar');

-- 9. La causa desaparece: RESUELTA (rearme manual) y entonces sí se cierra
select pg_temp.presion(3);
select motor_alarmas();
select is((select estado::text from pg_temp.evento()), 'RESUELTA', 'Sin causa y con rearme manual queda resuelta');
select pg_temp.login('e9a00000-0000-0000-0000-000000000001');
set local role authenticated;
select ok((select (a->>'se_puede_cerrar')::boolean from jsonb_array_elements(alarmas_edificio('fa200000-0000-0000-0000-000000000001')) a
           where a->>'tipo' = 'ALARMA'), 'Una resuelta se puede cerrar');
select lives_ok($$ select cerrar_alarma((select id from pg_temp.evento()), 'Regulador sustituido') $$, 'Se cierra la resuelta');
reset role;

-- 10. Si vuelve antes de una hora, se reabre el mismo evento (sin nuevo email)
select pg_temp.presion(6);
select is((motor_alarmas()->>'abiertas')::integer, 0, 'No se crea un evento nuevo');
select is((select estado::text || '/' || reaperturas from pg_temp.evento()), 'ACTIVA/1', 'Se reabre el mismo evento');

-- 11. Rearme automático: la alarma se cierra sola cuando desaparece la causa
update reglas_alarma set tipo_rearme = 'AUTOMATICO' where codigo = 'AGUA_PRESION_EXCESIVA-AGUA';
select pg_temp.presion(3);
select motor_alarmas();
select is((select estado::text || '/' || cierre_automatico from pg_temp.evento()), 'CERRADA/true', 'Con rearme automático se cierra sola');

-- 12. Crítica: va al resumen diario, una vez al día
insert into reglas_alarma (id, id_edificio, id_sensor, codigo, nombre, condicion, umbral, id_nivel_alarma)
select 'fab00000-0000-0000-0000-000000000001', 'fa200000-0000-0000-0000-000000000001', 'fa700000-0000-0000-0000-000000000003',
       'T_ALTA', 'Temperatura muy alta', 'MAYOR_QUE', 30, n.id from niveles_alarma n where n.codigo = 'CRITICA';
insert into reglas_alarma_usuarios (id_regla_alarma, id_usuario) values ('fab00000-0000-0000-0000-000000000001', 'fa900000-0000-0000-0000-000000000001');
insert into lecturas (id_sensor, fecha_hora, valor) values ('fa700000-0000-0000-0000-000000000003', now() - interval '2 minutes', 33);
select is((motor_alarmas()->>'emails')::integer, 0, 'Una crítica no manda email inmediato');
select is(preparar_resumen_diario(), 1, 'Entra en el resumen diario del destinatario');
select is(preparar_resumen_diario(), 0, 'Un solo resumen al día por usuario');

-- 13. Aislamiento y permisos del motor
select pg_temp.login('e9a00000-0000-0000-0000-000000000003');
set local role authenticated;
select is(alarmas_edificio('fa200000-0000-0000-0000-000000000001'), '[]'::jsonb, 'El Partner B NO ve las alarmas del Partner A');
select throws_ok($$ select motor_alarmas() $$, '42501', null, 'Un usuario no puede ejecutar el motor');
select throws_ok($$ select * from avisos_pendientes() $$, '42501', null, 'Ni leer los emails pendientes');
reset role;

-- 14. Desactivar una regla cierra sus alarmas abiertas
select pg_temp.login('e9a00000-0000-0000-0000-000000000001');
set local role authenticated;
select desactivar_regla_alarma('fab00000-0000-0000-0000-000000000001');
reset role;
select is((select count(*)::integer from eventos_alarma where id_regla_alarma = 'fab00000-0000-0000-0000-000000000001' and estado <> 'CERRADA'), 0,
  'Al desactivar la regla se cierran sus alarmas');

select * from finish();
rollback;
