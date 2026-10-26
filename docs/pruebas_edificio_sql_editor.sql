-- VERSIÓN PARA EL SQL EDITOR DE SUPABASE: pegar entero y pulsar Run.
-- Al final sale un mensaje en ROJO a propósito con el resumen;
-- al ser un error, deshace todos los datos de prueba.
-- =========================================================
-- PRUEBAS DE LA PÁGINA DE EDIFICIO (migración 023)
-- Ejecutar con:  npx supabase test db
--
-- Edificio en Europe/Madrid. Calendario de junio de 2026:
-- lunes a viernes laborables de 08:00 a 18:00, fines de semana
-- no laborables y el viernes 12/06 festivo (no laborable).
-- Electricidad cada 15 min: martes 09/06 todo el día a 1,0 kWh;
-- miércoles 10/06 de 00:00 a 11:45 a 1,5 kWh. Gas 10 kWh a las
-- 09:00 ambos días. Fotovoltaica autoconsumida 2 kWh el miércoles a las 10:00.
-- "Ahora" = miércoles 10/06 a las 12:00.
-- =========================================================
begin;
set search_path = public, extensions;

create temp table resultados (n serial, t text);
grant all on resultados to public;
grant all on sequence resultados_n_seq to public;
select plan(22);

insert into auth.users (id, email) values
  ('e3000000-0000-0000-0000-000000000001', 'admin@edif.test'),
  ('e3000000-0000-0000-0000-000000000002', 'otro@edif.test');
insert into proveedores (id, codigo, nombre) values
  ('f0000000-0000-0000-0000-00000000000a', 'EP', 'Partner'),
  ('f0000000-0000-0000-0000-00000000000b', 'EQ', 'Otro partner');
insert into clientes (id, codigo, nombre) values ('f1000000-0000-0000-0000-000000000001', 'EC', 'Cliente');
insert into proveedores_clientes (id_proveedor, id_cliente) values
  ('f0000000-0000-0000-0000-00000000000a', 'f1000000-0000-0000-0000-000000000001');
insert into edificios (id, id_cliente, codigo, nombre, zona_horaria) values
  ('f2000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001', 'ED', 'Edificio', 'Europe/Madrid');
insert into proveedores_edificios (id_proveedor, id_edificio) values
  ('f0000000-0000-0000-0000-00000000000a', 'f2000000-0000-0000-0000-000000000001');
insert into plantas (id, id_edificio, codigo, nombre) values
  ('f3000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001', 'P0', 'PB');
insert into recintos (id, id_planta, codigo, nombre) values
  ('f4000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001', 'R1', 'Sala');

insert into usuarios (id, auth_user_id, nombre, email, id_rol)
select x.id::uuid, x.auth::uuid, 'U', x.mail, r.id
from (values
  ('f5000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', 'admin@edif.test'),
  ('f5000000-0000-0000-0000-000000000002', 'e3000000-0000-0000-0000-000000000002', 'otro@edif.test')) x(id, auth, mail)
join roles r on r.codigo = 'ADMIN_PARTNER';
insert into usuarios_partners (id_usuario, id_proveedor) values
  ('f5000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-00000000000a'),
  ('f5000000-0000-0000-0000-000000000002', 'f0000000-0000-0000-0000-00000000000b');

-- Calendario de junio
insert into calendario_edificio (id_edificio, fecha, laborable, hora_inicio, hora_fin)
select 'f2000000-0000-0000-0000-000000000001', d::date,
       extract(isodow from d) < 6 and d::date <> date '2026-06-12',
       case when extract(isodow from d) < 6 and d::date <> date '2026-06-12' then time '08:00' end,
       case when extract(isodow from d) < 6 and d::date <> date '2026-06-12' then time '18:00' end
from generate_series(date '2026-06-01', date '2026-06-30', interval '1 day') d;

-- Magnitudes del edificio y sus valores
insert into magnitudes_edificio (id, id_edificio, id_magnitud, ambito)
select x.id::uuid, 'f2000000-0000-0000-0000-000000000001', m.id, 'EDIFICIO'
from (values ('f6000000-0000-0000-0000-000000000001', 'CONSUMO_ELECTRICIDAD'),
             ('f6000000-0000-0000-0000-000000000002', 'CONSUMO_GAS'),
             ('f6000000-0000-0000-0000-000000000003', 'GENERACION_FOTOVOLTAICA')) x(id, cod)
join magnitudes m on m.codigo = x.cod;

insert into valores_magnitud (id_magnitud_edificio, fecha_hora, valor)
select 'f6000000-0000-0000-0000-000000000001', t, 1.0
from generate_series(timestamptz '2026-06-09 00:00 Europe/Madrid', timestamptz '2026-06-09 23:45 Europe/Madrid', interval '15 minutes') t;
insert into valores_magnitud (id_magnitud_edificio, fecha_hora, valor)
select 'f6000000-0000-0000-0000-000000000001', t, 1.5
from generate_series(timestamptz '2026-06-10 00:00 Europe/Madrid', timestamptz '2026-06-10 11:45 Europe/Madrid', interval '15 minutes') t;
insert into valores_magnitud (id_magnitud_edificio, fecha_hora, valor) values
  ('f6000000-0000-0000-0000-000000000002', timestamptz '2026-06-09 09:00 Europe/Madrid', 10),
  ('f6000000-0000-0000-0000-000000000002', timestamptz '2026-06-10 09:00 Europe/Madrid', 10),
  ('f6000000-0000-0000-0000-000000000003', timestamptz '2026-06-10 10:00 Europe/Madrid', 2);

-- Sensor acumulativo (contador) con lecturas horarias
insert into conexiones (id, id_edificio, id_tipo_conexion, codigo, nombre)
select 'f7000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001', id, 'HTTP', 'Gateway'
from tipos_conexion where codigo = 'ENVIO_HTTP';
insert into sensores (id, id_conexion, id_recinto, id_familia, id_naturaleza, id_tratamiento, codigo, nombre, unidad, direccion)
select 'f8000000-0000-0000-0000-000000000001', 'f7000000-0000-0000-0000-000000000001', 'f4000000-0000-0000-0000-000000000001',
       f.id, n.id, t.id, 'CONT', 'Contador', 'kWh', '{"clave": "CONT"}'
from familias_sensor f, naturalezas_sensor n, tratamientos_sensor t
where f.codigo = 'ENERGIA' and n.codigo = 'ACUMULATIVA' and t.codigo = 'DELTA';
insert into lecturas (id_sensor, fecha_hora, valor) values
  ('f8000000-0000-0000-0000-000000000001', timestamptz '2026-06-09 09:00 Europe/Madrid', 100),
  ('f8000000-0000-0000-0000-000000000001', timestamptz '2026-06-09 10:00 Europe/Madrid', 110),
  ('f8000000-0000-0000-0000-000000000001', timestamptz '2026-06-09 11:00 Europe/Madrid', 125);
insert into estado_comunicacion (id_sensor, ultima_lectura, ultimo_valor) values
  ('f8000000-0000-0000-0000-000000000001', timestamptz '2026-06-09 11:00 Europe/Madrid', 125);

create function pg_temp.login(p_auth uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', p_auth::text, true),
         set_config('request.jwt.claims', json_build_object('sub', p_auth, 'role', 'authenticated', 'aal', 'aal2')::text, true);
$$;

-- =========================================================
-- 1. Día comparable según calendario
-- =========================================================
insert into resultados (t) select is(dia_comparable('f2000000-0000-0000-0000-000000000001', '2026-06-10'), date '2026-06-09',
  'Miércoles laborable → se compara con el martes');
insert into resultados (t) select is(dia_comparable('f2000000-0000-0000-0000-000000000001', '2026-06-15'), date '2026-06-11',
  'Lunes laborable tras un viernes festivo → se compara con el jueves');
insert into resultados (t) select is(dia_comparable('f2000000-0000-0000-0000-000000000001', '2026-06-14'), date '2026-06-13',
  'Domingo → se compara con el sábado');
insert into resultados (t) select is(dia_comparable('f2000000-0000-0000-0000-000000000001', '2026-06-13'), date '2026-06-12',
  'Sábado → se compara con el viernes festivo (también no laborable)');
insert into resultados (t) select ok((select laborable from dia_calendario('f2000000-0000-0000-0000-000000000001', '2026-07-06')),
  'Sin calendario, un lunes se considera laborable');

-- =========================================================
-- 2. Pestaña HOY (como administrador del Partner)
-- =========================================================
select pg_temp.login('e3000000-0000-0000-0000-000000000001');
set local role authenticated;

create temp table h as
select hoy_edificio('f2000000-0000-0000-0000-000000000001', timestamptz '2026-06-10 12:00 Europe/Madrid') as j;

insert into resultados (t) select is((select j->'dia_comparable'->>'fecha' from h), '2026-06-09', 'HOY indica el día con el que compara');
insert into resultados (t) select is((select (j->'hoy'->>'energia_kwh')::float8 from h), 84::float8,
  'Energía consumida hoy hasta las 12:00 = 72 importada + 10 gas + 2 fotovoltaica = 84 kWh');
insert into resultados (t) select is((select j->'hoy'->>'cobertura_renovable_pct' from h), '2.4', 'Cobertura renovable de hoy = 2 / 84 = 2,4 %');
insert into resultados (t) select is((select (j->'comparable_mismo_tramo'->>'energia_kwh')::float8 from h), 58::float8,
  'Energía del martes en el mismo tramo (00:00–12:00) = 48 + 10 = 58 kWh');
insert into resultados (t) select is((select j->>'variacion_energia_pct' from h), '44.8', 'Variación +44,8 % frente al día comparable (84 frente a 58)');
insert into resultados (t) select is((select (j->'hoy'->>'fuera_horario_kwh')::float8 from h), 48::float8,
  'Consumo fuera de horario hoy (00:00–08:00) = 32 × 1,5 = 48 kWh');
insert into resultados (t) select is((select j->'hoy'->>'fuera_horario_pct' from h), '57.1', 'Fuera de horario = 48 / 84 = 57,1 % de lo consumido');
insert into resultados (t) select is((select round(((j->'hoy'->>'tco2')::numeric), 5) from h), round((72 * 0.183 + 10 * 0.182) / 1000.0, 5),
  'Emisiones de hoy con los factores 0,183 y 0,182');
insert into resultados (t) select is((select jsonb_array_length(j->'curva') from h), 96, 'La curva tiene las 96 franjas de 15 minutos del día');
insert into resultados (t) select is((select (c->>'hoy')::float8 from h, jsonb_array_elements(j->'curva') c where c->>'franja' = '10:00'),
  3.5::float8, 'En la franja 10:00, hoy = 1,5 importados + 2 fotovoltaicos');

-- =========================================================
-- 3. Históricos
-- =========================================================
insert into resultados (t) select is((select valor from serie_magnitud('f6000000-0000-0000-0000-000000000001',
            '2026-06-09 00:00 Europe/Madrid', '2026-06-10 00:00 Europe/Madrid', 'hora')
           where instante = timestamptz '2026-06-09 10:00 Europe/Madrid'),
  4::float8, 'Serie horaria: a las 10:00 del martes, 4 × 1 kWh');
insert into resultados (t) select is((select valor from serie_magnitud('f6000000-0000-0000-0000-000000000001',
            '2026-06-09 00:00 Europe/Madrid', '2026-06-10 00:00 Europe/Madrid', 'dia', 'FUERA_HORARIO')),
  56::float8, 'Filtro fuera de horario: 56 de las 96 franjas del martes');
insert into resultados (t) select is((select valor from serie_magnitud('f6000000-0000-0000-0000-000000000001',
            '2026-06-01 00:00 Europe/Madrid', '2026-07-01 00:00 Europe/Madrid', 'mes')),
  168::float8, 'Serie mensual: 96 + 72 = 168 kWh en junio');
insert into resultados (t) select throws_like($$ select * from serie_magnitud('f6000000-0000-0000-0000-000000000001',
            '2026-01-01', '2026-06-01', '15min') $$,
  '%Periodo demasiado largo%', 'Se impide pedir 5 meses cada 15 minutos');
insert into resultados (t) select results_eq($$ select valor from serie_sensor('f8000000-0000-0000-0000-000000000001',
            '2026-06-09 10:00 Europe/Madrid', '2026-06-09 12:00 Europe/Madrid', 'hora') order by instante $$,
  array[10::float8, 15::float8],
  'Un contador acumulativo devuelve el consumo de cada hora (110−100, 125−110)');
insert into resultados (t) select is((select ultimo_valor from sensores_estado_edificio('f2000000-0000-0000-0000-000000000001')
           where codigo = 'CONT'), 125::float8, 'Los sensores del edificio traen su valor actual');
reset role;

-- =========================================================
-- 4. Aislamiento
-- =========================================================
select pg_temp.login('e3000000-0000-0000-0000-000000000002');
set local role authenticated;
insert into resultados (t) select throws_like($$ select hoy_edificio('f2000000-0000-0000-0000-000000000001') $$,
  '%sin acceso%', 'Otro Partner no puede ver la pestaña HOY de este edificio');
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
