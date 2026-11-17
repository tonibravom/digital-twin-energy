-- =========================================================
-- 051 · Medidor general del agua: presión y temperatura
-- Decisión D57 (17/11/2026).
--
--   El medidor general del agua mide 4 parámetros: consumo acumulado (m³,
--   obligatorio: contador, lo de cada día o mes es la diferencia de lecturas),
--   caudal instantáneo, presión (bar) y temperatura del agua (opcionales).
-- =========================================================
begin;

insert into public.parametros_medidor (codigo, nombre, tipo_suministro, familias, unidad, obligatorio, consumo, orden) values
  ('PRESION_AGUA', 'Presión', 'AGUA', '{PRESION}', 'bar', false, false, 3),
  ('TEMPERATURA_AGUA', 'Temperatura del agua', 'AGUA', '{TEMPERATURA}', '°C', false, false, 4)
on conflict (codigo) do nothing;

update public.parametros_medidor set nombre = 'Caudal instantáneo' where codigo = 'CAUDAL_AGUA';

commit;
