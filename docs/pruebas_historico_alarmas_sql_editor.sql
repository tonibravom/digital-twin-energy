-- VERSIÓN PARA EL SQL EDITOR DE SUPABASE: pegar entero y pulsar Run.
-- Al final sale un mensaje en ROJO a propósito con el resumen;
-- al ser un error, deshace todos los datos de prueba.
-- =========================================================
-- PRUEBAS DEL HISTÓRICO DE ALARMAS Y SU CRONOLOGÍA (migración 055, D59)
-- =========================================================
begin;
set search_path = public, extensions;

create temp table resultados (n serial, t text);
grant all on resultados to public;
grant all on sequence resultados_n_seq to public;
select plan(12);

insert into proveedores (id, codigo, nombre) values
  ('fc000000-0000-0000-0000-00000000000a', 'HIA', 'Partner alarmas A'),
  ('fc000000-0000-0000-0000-00000000000b', 'HIB', 'Partner alarmas B');
insert into clientes (id, codigo, nombre) values ('fc100000-0000-0000-0000-000000000001', 'HIC', 'Cliente alarmas');
insert into proveedores_clientes (id_proveedor, id_cliente) values
  ('fc000000-0000-0000-0000-00000000000a', 'fc100000-0000-0000-0000-000000000001');
insert into edificios (id, id_cliente, codigo, nombre, zona_horaria) values
  ('fc200000-0000-0000-0000-000000000001', 'fc100000-0000-0000-0000-000000000001', 'HIE', 'Edificio alarmas', 'Europe/Madrid');
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
select 'fc600000-0000-0000-0000-000000000001', 'fc400000-0000-0000-0000-000000000001', 'fc500000-0000-0000-0000-000000000001', t.id, 'CAG', 'Contador de agua'
from tipos_dispositivo t where t.codigo = 'CONTADOR_ENERGIA';
create function pg_temp.sensor(p_id text, p_disp text, p_cod text, p_fam text, p_nat text, p_uni text, p_ene text) returns void language sql as $$
  insert into sensores (id, id_dispositivo, id_conexion, id_recinto, id_familia, id_naturaleza, id_tratamiento, id_tipo_energia, codigo, nombre, unidad)
  select p_id::uuid, p_disp::uuid, case when p_disp is null then 'fc500000-0000-0000-0000-000000000001'::uuid end,
         'fc400000-0000-0000-0000-000000000001', f.id, n.id, t.id, te.id, p_cod, p_cod, p_uni
  from familias_sensor f, naturalezas_sensor n, tratamientos_sensor t, tipos_energia te
  where f.codigo = p_fam and n.codigo = p_nat and t.codigo = case p_nat when 'ACUMULATIVA' then 'DELTA' else 'PROMEDIO' end
    and te.codigo = p_ene;
$$;
select pg_temp.sensor('fc700000-0000-0000-0000-000000000001', 'fc600000-0000-0000-0000-000000000001', 'AGUA', 'OTRA', 'ACUMULATIVA', 'm³', 'AGUA');
select pg_temp.sensor('fc700000-0000-0000-0000-000000000002', 'fc600000-0000-0000-0000-000000000001', 'PRES', 'PRESION', 'INSTANTANEA', 'bar', 'AGUA');
select pg_temp.sensor('fc700000-0000-0000-0000-000000000003', null, 'TEMP', 'TEMPERATURA', 'INSTANTANEA', '°C', 'OTRA');
update sensores set id_parametro_medidor = (select id from parametros_medidor where codigo = 'CONSUMO_AGUA') where id = 'fc700000-0000-0000-0000-000000000001';
insert into suministros (id, id_edificio, codigo, nombre, tipo) values
  ('fc800000-0000-0000-0000-000000000001', 'fc200000-0000-0000-0000-000000000001', 'AGUA', 'Agua', 'AGUA');
insert into suministros_dispositivos (id_suministro, id_dispositivo, medidor_general) values
  ('fc800000-0000-0000-0000-000000000001', 'fc600000-0000-0000-0000-000000000001', true);

-- Usuarios: dos técnicos del Partner A (el segundo recibe el escalado) y uno del Partner B
insert into auth.users (id, email) values
  ('e9c00000-0000-0000-0000-000000000001', 'a1@historico.test'), ('e9c00000-0000-0000-0000-000000000002', 'a2@historico.test'),
  ('e9c00000-0000-0000-0000-000000000003', 'b@historico.test');
insert into usuarios (id, auth_user_id, nombre, email, id_rol)
select x.id::uuid, x.auth::uuid, x.nom, x.mail, r.id
from (values ('fc900000-0000-0000-0000-000000000001', 'e9c00000-0000-0000-0000-000000000001', 'Técnica A', 'a1@historico.test'),
             ('fc900000-0000-0000-0000-000000000002', 'e9c00000-0000-0000-0000-000000000002', 'Jefe A', 'a2@historico.test'),
             ('fc900000-0000-0000-0000-000000000003', 'e9c00000-0000-0000-0000-000000000003', 'Técnico B', 'b@historico.test')) x(id, auth, nom, mail)
join roles r on r.codigo = 'TECNICO_PARTNER';
insert into usuarios_partners (id_usuario, id_proveedor) values
  ('fc900000-0000-0000-0000-000000000001', 'fc000000-0000-0000-0000-00000000000a'),
  ('fc900000-0000-0000-0000-000000000002', 'fc000000-0000-0000-0000-00000000000a'),
  ('fc900000-0000-0000-0000-000000000003', 'fc000000-0000-0000-0000-00000000000b');
create function pg_temp.login(p_auth uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_auth, 'role', 'authenticated', 'aal', 'aal2',
                    'session_id', gen_random_uuid())::text, true);
$$;
create function pg_temp.presion(p_valor numeric) returns void language sql as $$
  delete from lecturas where id_sensor = 'fc700000-0000-0000-0000-000000000002';
  insert into lecturas (id_sensor, fecha_hora, valor) values
    ('fc700000-0000-0000-0000-000000000002', now() - interval '4 minutes', p_valor),
    ('fc700000-0000-0000-0000-000000000002', now() - interval '1 minute', p_valor);
$$;
create function pg_temp.evento() returns setof eventos_alarma language sql as $$
  select ea.* from eventos_alarma ea join reglas_alarma ra on ra.id = ea.id_regla_alarma
  where ra.codigo = 'AGUA_PRESION_EXCESIVA-AGUA';
$$;

update sensores set id_parametro_medidor = (select id from parametros_medidor where codigo = 'PRESION_AGUA') where id = 'fc700000-0000-0000-0000-000000000002';

-- Una alarma completa: se abre, email, escalado, reconocida, silenciada, quitado el silencio, resuelta y cerrada
select pg_temp.login('e9c00000-0000-0000-0000-000000000001');
set local role authenticated;
select activar_regla_alarma('fc200000-0000-0000-0000-000000000001', 'AGUA_PRESION_EXCESIVA', 'fc800000-0000-0000-0000-000000000001',
  null, '{}', null, '{fc900000-0000-0000-0000-000000000001}', '{fc900000-0000-0000-0000-000000000002}');
reset role;
select pg_temp.presion(6.4);
select motor_alarmas();
select marcar_aviso(id, true) from notificaciones where motivo = 'INMEDIATO' and destinatario = 'a1@historico.test';
update eventos_alarma set fecha_inicio = now() - interval '20 minutes' where id = (select id from pg_temp.evento());
select motor_alarmas();
select pg_temp.login('e9c00000-0000-0000-0000-000000000001');
set local role authenticated;
select reconocer_alarma((select id from pg_temp.evento()), 'Voy');
select silenciar_alarma((select id from pg_temp.evento()), now() + interval '1 hour', 'Revisión');
select silenciar_alarma((select id from pg_temp.evento()), null, null);
reset role;
select pg_temp.presion(3);
select motor_alarmas();
select pg_temp.login('e9c00000-0000-0000-0000-000000000001');
set local role authenticated;
select cerrar_alarma((select id from pg_temp.evento()), 'Regulador cambiado');

insert into resultados (t) select is((select array_agg(x->>'accion' order by o) from jsonb_array_elements(cronologia_alarma((select id from pg_temp.evento())))
           with ordinality as c(x, o)),
  '{ABIERTA,EMAIL_ENVIADO,ESCALADA,RECONOCIDA,SILENCIADA,SILENCIO_RETIRADO,RESUELTA,CERRADA}'::text[],
  'La cronología guarda cada paso en orden');
insert into resultados (t) select is((select x->>'quien' from jsonb_array_elements(cronologia_alarma((select id from pg_temp.evento()))) x where x->>'accion' = 'CERRADA'),
  'Técnica A', 'Con quién cerró');
insert into resultados (t) select is((select x->>'detalle' from jsonb_array_elements(cronologia_alarma((select id from pg_temp.evento()))) x where x->>'accion' = 'CERRADA'),
  'Regulador cambiado', 'Y su explicación');
insert into resultados (t) select is((select x->>'quien' from jsonb_array_elements(cronologia_alarma((select id from pg_temp.evento()))) x where x->>'accion' = 'ESCALADA'),
  'Plataforma', 'Los pasos automáticos son de la plataforma');

-- Histórico
insert into resultados (t) select is((historico_alarmas('fc200000-0000-0000-0000-000000000001')->>'total')::integer, 1, 'El histórico incluye la alarma cerrada');
insert into resultados (t) select ok((select f->>'cierra' = 'Técnica A' and f->>'reconoce' = 'Técnica A' and (f->>'emails')::integer = 1 and (f->>'silencios')::integer = 1
           from jsonb_array_elements(historico_alarmas('fc200000-0000-0000-0000-000000000001')->'filas') f),
  'Con quién la reconoció y cerró, emails y silencios');
insert into resultados (t) select is((historico_alarmas('fc200000-0000-0000-0000-000000000001', p_nivel => 'CRITICA')->>'total')::integer, 0, 'Filtra por nivel');
insert into resultados (t) select is((historico_alarmas('fc200000-0000-0000-0000-000000000001', p_texto => 'regulador')->>'total')::integer, 1, 'Busca en el comentario');
insert into resultados (t) select is((historico_alarmas('fc200000-0000-0000-0000-000000000001', p_desde => current_date + 1)->>'total')::integer, 0, 'Filtra por fechas');
insert into resultados (t) select throws_ok($$ insert into eventos_alarma_acciones (id_evento_alarma, accion) values ((select id from pg_temp.evento()), 'CERRADA') $$,
  '42501', null, 'Nadie puede escribir la cronología a mano');
reset role;

-- Partner B
select pg_temp.login('e9c00000-0000-0000-0000-000000000003');
set local role authenticated;
insert into resultados (t) select is((historico_alarmas('fc200000-0000-0000-0000-000000000001')->>'total')::integer, 0, 'El Partner B NO ve el histórico del Partner A');
insert into resultados (t) select is((select count(*)::integer from eventos_alarma_acciones), 0, 'Ni su cronología');
reset role;

do $$
declare v_total int; v_fallos int; v_detalle text;
begin
  select count(*), count(*) filter (where t like 'not ok%'),
         string_agg(split_part(t, E'
', 1), E'
' order by n) filter (where t like 'not ok%')
    into v_total, v_fallos, v_detalle from resultados;
  if v_fallos = 0 and v_total = 12 then
    raise exception 'RESULTADO: % de 12 pruebas OK. Todo correcto (los datos de prueba se han deshecho).', v_total;
  else
    raise exception E'RESULTADO: % pruebas ejecutadas, % FALLAN:
%', v_total, v_fallos, coalesce(v_detalle, '(faltan pruebas)');
  end if;
end;
$$;
