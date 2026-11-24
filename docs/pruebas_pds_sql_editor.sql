-- VERSIÓN PARA EL SQL EDITOR DE SUPABASE: pegar entero y pulsar Run.
-- Al final sale un mensaje en ROJO a propósito con el resumen;
-- al ser un error, deshace todos los datos de prueba.
-- =========================================================
-- PRUEBAS DE LAS PETICIONES DE SERVICIO (migración 060, D63)
-- =========================================================
begin;
set search_path = public, extensions;

create temp table resultados (n serial, t text);
grant all on resultados to public;
grant all on sequence resultados_n_seq to public;
select plan(16);

insert into proveedores (id, codigo, nombre) values
  ('f1000000-0000-0000-0000-00000000000a', 'PDA', 'Partner alarmas A'),
  ('f1000000-0000-0000-0000-00000000000b', 'PDB', 'Partner alarmas B');
insert into clientes (id, codigo, nombre) values ('f1100000-0000-0000-0000-000000000001', 'PDC', 'Cliente alarmas');
insert into proveedores_clientes (id_proveedor, id_cliente) values
  ('f1000000-0000-0000-0000-00000000000a', 'f1100000-0000-0000-0000-000000000001');
insert into edificios (id, id_cliente, codigo, nombre, zona_horaria) values
  ('f1200000-0000-0000-0000-000000000001', 'f1100000-0000-0000-0000-000000000001', 'TORRE', 'Edificio alarmas', 'Europe/Madrid');
insert into proveedores_edificios (id_proveedor, id_edificio) values
  ('f1000000-0000-0000-0000-00000000000a', 'f1200000-0000-0000-0000-000000000001');
insert into plantas (id, id_edificio, codigo, nombre, nivel) values
  ('f1300000-0000-0000-0000-000000000001', 'f1200000-0000-0000-0000-000000000001', 'P0', 'Planta baja', 0);
insert into recintos (id, id_planta, codigo, nombre) values
  ('f1400000-0000-0000-0000-000000000001', 'f1300000-0000-0000-0000-000000000001', 'CC', 'Cuarto de contadores');
insert into conexiones (id, id_edificio, id_tipo_conexion, codigo, nombre)
select 'f1500000-0000-0000-0000-000000000001', 'f1200000-0000-0000-0000-000000000001', id, 'HTTP', 'Pasarela'
from tipos_conexion where codigo = 'ENVIO_HTTP';
insert into dispositivos (id, id_recinto, id_conexion, id_tipo_dispositivo, codigo, nombre)
select 'f1600000-0000-0000-0000-000000000001', 'f1400000-0000-0000-0000-000000000001', 'f1500000-0000-0000-0000-000000000001', t.id, 'CAG', 'Contador de agua'
from tipos_dispositivo t where t.codigo = 'CONTADOR_ENERGIA';
create function pg_temp.sensor(p_id text, p_disp text, p_cod text, p_fam text, p_nat text, p_uni text, p_ene text) returns void language sql as $$
  insert into sensores (id, id_dispositivo, id_conexion, id_recinto, id_familia, id_naturaleza, id_tratamiento, id_tipo_energia, codigo, nombre, unidad)
  select p_id::uuid, p_disp::uuid, case when p_disp is null then 'f1500000-0000-0000-0000-000000000001'::uuid end,
         'f1400000-0000-0000-0000-000000000001', f.id, n.id, t.id, te.id, p_cod, p_cod, p_uni
  from familias_sensor f, naturalezas_sensor n, tratamientos_sensor t, tipos_energia te
  where f.codigo = p_fam and n.codigo = p_nat and t.codigo = case p_nat when 'ACUMULATIVA' then 'DELTA' else 'PROMEDIO' end
    and te.codigo = p_ene;
$$;
select pg_temp.sensor('f1700000-0000-0000-0000-000000000001', 'f1600000-0000-0000-0000-000000000001', 'AGUA', 'OTRA', 'ACUMULATIVA', 'm³', 'AGUA');
select pg_temp.sensor('f1700000-0000-0000-0000-000000000002', 'f1600000-0000-0000-0000-000000000001', 'PRES', 'PRESION', 'INSTANTANEA', 'bar', 'AGUA');
select pg_temp.sensor('f1700000-0000-0000-0000-000000000003', null, 'TEMP', 'TEMPERATURA', 'INSTANTANEA', '°C', 'OTRA');
update sensores set id_parametro_medidor = (select id from parametros_medidor where codigo = 'CONSUMO_AGUA') where id = 'f1700000-0000-0000-0000-000000000001';
insert into suministros (id, id_edificio, codigo, nombre, tipo) values
  ('f1800000-0000-0000-0000-000000000001', 'f1200000-0000-0000-0000-000000000001', 'AGUA', 'Agua', 'AGUA');
insert into suministros_dispositivos (id_suministro, id_dispositivo, medidor_general) values
  ('f1800000-0000-0000-0000-000000000001', 'f1600000-0000-0000-0000-000000000001', true);

-- Usuarios: dos técnicos del Partner A (el segundo recibe el escalado) y uno del Partner B
insert into auth.users (id, email) values
  ('e9f10000-0000-0000-0000-000000000001', 'a1@pds.test'), ('e9f10000-0000-0000-0000-000000000002', 'a2@pds.test'),
  ('e9f10000-0000-0000-0000-000000000003', 'b@pds.test');
insert into usuarios (id, auth_user_id, nombre, email, id_rol)
select x.id::uuid, x.auth::uuid, x.nom, x.mail, r.id
from (values ('f1900000-0000-0000-0000-000000000001', 'e9f10000-0000-0000-0000-000000000001', 'Técnica A', 'a1@pds.test'),
             ('f1900000-0000-0000-0000-000000000002', 'e9f10000-0000-0000-0000-000000000002', 'Jefe A', 'a2@pds.test'),
             ('f1900000-0000-0000-0000-000000000003', 'e9f10000-0000-0000-0000-000000000003', 'Técnico B', 'b@pds.test')) x(id, auth, nom, mail)
join roles r on r.codigo = 'TECNICO_PARTNER';
insert into usuarios_partners (id_usuario, id_proveedor) values
  ('f1900000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-00000000000a'),
  ('f1900000-0000-0000-0000-000000000002', 'f1000000-0000-0000-0000-00000000000a'),
  ('f1900000-0000-0000-0000-000000000003', 'f1000000-0000-0000-0000-00000000000b');
create function pg_temp.login(p_auth uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_auth, 'role', 'authenticated', 'aal', 'aal2',
                    'session_id', gen_random_uuid())::text, true);
$$;
create function pg_temp.presion(p_valor numeric) returns void language sql as $$
  delete from lecturas where id_sensor = 'f1700000-0000-0000-0000-000000000002';
  insert into lecturas (id_sensor, fecha_hora, valor) values
    ('f1700000-0000-0000-0000-000000000002', now() - interval '4 minutes', p_valor),
    ('f1700000-0000-0000-0000-000000000002', now() - interval '1 minute', p_valor);
$$;
create function pg_temp.evento() returns setof eventos_alarma language sql as $$
  select ea.* from eventos_alarma ea join reglas_alarma ra on ra.id = ea.id_regla_alarma
  where ra.codigo = 'AGUA_PRESION_EXCESIVA-AGUA';
$$;

update sensores set id_parametro_medidor = (select id from parametros_medidor where codigo = 'PRESION_AGUA') where id = 'f1700000-0000-0000-0000-000000000002';

-- 1. Destinos (Partner A sí, Partner B no)
select pg_temp.login('e9f10000-0000-0000-0000-000000000003');
set local role authenticated;
insert into resultados (t) select throws_ok($$ select guardar_destino_pds('f1200000-0000-0000-0000-000000000001', 'Intruso', 'x@y.es') $$,
  '42501', null, 'El Partner B NO configura destinos en el edificio del Partner A');
insert into resultados (t) select throws_ok($$ select crear_pds('f1200000-0000-0000-0000-000000000001', 'CORRECTIVO', 'NORMAL', 'Fuga') $$,
  '42501', null, 'Ni crea peticiones');
reset role;
select pg_temp.login('e9f10000-0000-0000-0000-000000000001');
set local role authenticated;
insert into resultados (t) select throws_like($$ select guardar_destino_pds('f1200000-0000-0000-0000-000000000001', 'Clima', 'no-es-un-email') $$,
  '%email válido%', 'El destino necesita un email válido');
insert into resultados (t) select lives_ok($$ select guardar_destino_pds('f1200000-0000-0000-0000-000000000001', 'Mantenimiento clima', 'Avisos@Mantenedor.test') $$,
  'El Partner A añade un destino');
insert into resultados (t) select is((select email from pds_destinos), 'avisos@mantenedor.test', 'Email guardado en minúsculas');

-- 2. PDS manual: número propio y documento
insert into resultados (t) select lives_ok($$ select crear_pds('f1200000-0000-0000-0000-000000000001', 'CORRECTIVO', 'NORMAL', 'Grifo que gotea', 'Aseo de planta baja',
                   'f1400000-0000-0000-0000-000000000001') $$, 'Se crea una PDS manual');
insert into resultados (t) select is((select numero from pds order by secuencia limit 1), 'TORRE-' || extract(year from now())::int || '-0001', 'Número <edificio>-<año>-0001');
insert into resultados (t) select is((select contenido->'ubicacion'->>'recinto' from pds order by secuencia limit 1), 'Cuarto de contadores', 'Con su ubicación');
insert into resultados (t) select is((select contenido->>'formato' || '/' || (contenido->>'version') from pds order by secuencia limit 1), 'pds/1.0', 'Formato pds/1.0');

-- 3. PDS desde una alarma
select activar_regla_alarma('f1200000-0000-0000-0000-000000000001', 'AGUA_PRESION_EXCESIVA', 'f1800000-0000-0000-0000-000000000001',
  null, '{}', null, '{f1900000-0000-0000-0000-000000000001}');
reset role;
select pg_temp.presion(6.3);
select motor_alarmas();
select pg_temp.login('e9f10000-0000-0000-0000-000000000001');
set local role authenticated;
select crear_pds('f1200000-0000-0000-0000-000000000001', 'CORRECTIVO', 'EMERGENCIA', 'Presión de agua excesiva',
  null, null, null, (select id from pg_temp.evento()));
insert into resultados (t) select is((select contenido->'origen'->'alarma'->>'nivel' || '·' || (contenido->'equipo'->>'sensor') from pds where secuencia = 2),
  'MUY_CRITICA·PRES', 'Lleva la alarma y el sensor');
insert into resultados (t) select ok((select jsonb_array_length(contenido->'origen'->'alarma'->'cronologia') >= 1 from pds where secuencia = 2), 'Y la cronología de la alarma');

-- 4. Envío por email
insert into resultados (t) select throws_like($$ select enviar_pds((select id from pds where secuencia = 2), (select id from pds_destinos), '{otro/edificio/archivo.pdf}') $$,
  '%Adjunto no válido%', 'Solo adjuntos de la propia PDS');
insert into resultados (t) select lives_ok($$ select enviar_pds((select id from pds where secuencia = 2), (select id from pds_destinos),
  array['edificios/f1200000-0000-0000-0000-000000000001/pds/' || (select id from pds where secuencia = 2) || '/pds.pdf']) $$, 'Se envía');
insert into resultados (t) select is((select jsonb_array_length(f->'envios') from jsonb_array_elements(pds_edificio('f1200000-0000-0000-0000-000000000001')) f
           where f->>'titulo' = 'Presión de agua excesiva'), 1, 'Queda en el registro con su envío');
insert into resultados (t) select ok((select array_agg(x->>'accion') @> '{PDS_CREADA,PDS_ENVIADA}' from jsonb_array_elements(cronologia_alarma((select id from pg_temp.evento()))) x),
  'Y en la cronología de la alarma');
reset role;

select pg_temp.login('e9f10000-0000-0000-0000-000000000003');
set local role authenticated;
insert into resultados (t) select is((select count(*)::integer from pds), 0, 'El Partner B NO ve las PDS del Partner A');
reset role;

do $$
declare v_total int; v_fallos int; v_detalle text;
begin
  select count(*), count(*) filter (where t like 'not ok%'),
         string_agg(split_part(t, E'
', 1), E'
' order by n) filter (where t like 'not ok%')
    into v_total, v_fallos, v_detalle from resultados;
  if v_fallos = 0 and v_total = 16 then
    raise exception 'RESULTADO: % de 16 pruebas OK. Todo correcto (los datos de prueba se han deshecho).', v_total;
  else
    raise exception E'RESULTADO: % pruebas ejecutadas, % FALLAN:
%', v_total, v_fallos, coalesce(v_detalle, '(faltan pruebas)');
  end if;
end;
$$;
