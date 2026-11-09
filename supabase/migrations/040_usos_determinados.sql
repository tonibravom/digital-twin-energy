-- =========================================================
-- 040 · Usos determinados y "otros usos"
-- Decisión D48 (09/11/2026).
--
-- Un submedidor con uso asignado mide ese uso: la informática es
-- informática, no "otros usos". "Otros usos" queda solo para lo que no
-- tiene uso determinado: la diferencia de cada cuadro (total − sus
-- submedidores) y lo que el contador general no reparte entre cuadros.
--
-- Usos principales (columna central del Sankey):
--   HVAC (climatización, refrigeración, calefacción, ACS, calefacción y
--   ACS, renovación de aire) · Alumbrado · Informática · Servicios
--   comunes · Otros usos (sin uso determinado)
--
-- Informática y Servicios comunes dejan de colgar de "Otros usos" y pasan a
-- ser usos principales. Solo cambian el código, el grupo y el orden: las
-- asignaciones de los sensores, los repartos y los datos calculados se
-- conservan (van por identificador).
-- =========================================================
begin;

update public.usos_energia set codigo = 'INFORMATICA', id_padre = null, orden = 3
where codigo = 'OTROS_INFORMATICA';
update public.usos_energia set codigo = 'SERVICIOS_COMUNES', id_padre = null, orden = 4
where codigo = 'OTROS_SERVICIOS_COMUNES';

comment on table public.usos_energia is
  'Usos de la energía. Usos principales (sin padre): HVAC (con sus usos finales), Alumbrado, Informática, Servicios comunes y Otros usos (sin uso determinado: diferencias de los cuadros y lo no medido).';

commit;
