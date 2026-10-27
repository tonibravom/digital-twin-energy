-- =========================================================
-- PRUEBAS DE POTENCIA Y FACTOR DE POTENCIA (migración 033)
-- Ejecutar con:  npx supabase test db
-- Edificio en Europe/Madrid sin calendario (lunes a viernes laborables).
-- "Ahora" = martes 20/10/2026 10:07 → día comparable lunes 19/10 a las 10:07.
-- =========================================================
begin;
set search_path = public, extensions;

select plan(6);

insert into proveedores (id, codigo, nombre) values ('fb000000-0000-0000-0000-00000000000a', 'PP', 'Partner potencia');
insert into clientes (id, codigo, nombre) values ('fb100000-0000-0000-0000-000000000001', 'PC', 'Cliente potencia');
insert into edificios (id, id_cliente, codigo, nombre, zona_horaria) values
  ('fb200000-0000-0000-0000-000000000001', 'fb100000-0000-0000-0000-000000000001', 'PE', 'Edificio potencia', 'Europe/Madrid');
insert into magnitudes_edificio (id, id_edificio, id_magnitud, ambito)
select x.id::uuid, 'fb200000-0000-0000-0000-000000000001', m.id, 'EDIFICIO'
from (values ('fb600000-0000-0000-0000-000000000001', 'POTENCIA_TOTAL'),
             ('fb600000-0000-0000-0000-000000000002', 'FACTOR_POTENCIA')) x(id, cod)
join magnitudes m on m.codigo = x.cod;

insert into valores_magnitud (id_magnitud_edificio, fecha_hora, valor) values
  ('fb600000-0000-0000-0000-000000000001', timestamptz '2026-10-20 09:45 Europe/Madrid', 50),
  ('fb600000-0000-0000-0000-000000000001', timestamptz '2026-10-20 10:00 Europe/Madrid', 60),
  ('fb600000-0000-0000-0000-000000000001', timestamptz '2026-10-19 10:00 Europe/Madrid', 48),
  ('fb600000-0000-0000-0000-000000000001', timestamptz '2026-10-19 10:15 Europe/Madrid', 99),
  ('fb600000-0000-0000-0000-000000000002', timestamptz '2026-10-20 10:00 Europe/Madrid', 0.9473);

select is((potencia_edificio('fb200000-0000-0000-0000-000000000001', timestamptz '2026-10-20 10:07 Europe/Madrid')->>'potencia_kw')::numeric,
  60::numeric, 'Potencia: el valor más reciente de la última hora');
select is((potencia_edificio('fb200000-0000-0000-0000-000000000001', timestamptz '2026-10-20 10:07 Europe/Madrid')->>'potencia_comparable_kw')::numeric,
  48::numeric, 'Potencia del día comparable a la misma hora (no la posterior)');
select is((potencia_edificio('fb200000-0000-0000-0000-000000000001', timestamptz '2026-10-20 10:07 Europe/Madrid')->>'variacion_potencia_pct')::numeric,
  25.0, 'Variación de la potencia frente al día comparable');
select is((potencia_edificio('fb200000-0000-0000-0000-000000000001', timestamptz '2026-10-20 10:07 Europe/Madrid')->>'factor_potencia')::numeric,
  0.947, 'Factor de potencia con 3 decimales');
select is(potencia_edificio('fb200000-0000-0000-0000-000000000001', timestamptz '2026-10-20 12:30 Europe/Madrid')->'potencia_kw',
  'null'::jsonb, 'Sin medidas en la última hora no se muestra potencia');

-- Un usuario sin acceso al edificio no la ve
insert into auth.users (id, email) values ('e9100000-0000-0000-0000-000000000001', 'otro@pot.test');
insert into usuarios (id, auth_user_id, nombre, email, id_rol)
select 'fb500000-0000-0000-0000-000000000001', 'e9100000-0000-0000-0000-000000000001', 'U', 'otro@pot.test', r.id
from roles r where r.codigo = 'USUARIO_CLIENTE';
select set_config('request.jwt.claims', json_build_object('sub', 'e9100000-0000-0000-0000-000000000001',
  'role', 'authenticated', 'aal', 'aal2', 'session_id', gen_random_uuid())::text, true);
set local role authenticated;
select throws_like($$ select potencia_edificio('fb200000-0000-0000-0000-000000000001') $$,
  '%sin acceso%', 'Un usuario sin acceso al edificio no ve su potencia');
reset role;

select * from finish();
rollback;
