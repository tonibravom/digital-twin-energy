begin;

-- =========================================================
-- KPIs DE LOS DASHBOARDS (decisiones 21/10/2026)
--
--   Energía consumida (kWh) = electricidad importada de la red + gas
--                             + renovable consumida (FV y eólica
--                             autoconsumidas + solar térmica, geotermia
--                             y biomasa)
--   Emisiones (tCO2e)    = (electricidad × 0,183 + gas × 0,182) / 1000
--   Agua (m³)            = se muestra aparte
--   Generación renovable = fotovoltaica + eólica + solar térmica +
--                          geotermia + biomasa, en kWh
--   Cobertura renovable %  = renovable consumida / energía consumida
--   Variación %          = año en curso hasta la fecha frente al mismo
--                          periodo del año anterior, SOLO con edificios
--                          que tienen datos en ambos periodos.
--
-- Los KPIs se calculan sobre resumenes_diarios (un valor por
-- edificio, día e indicador), que rellena el motor de cálculo.
-- Así un dashboard con cientos de edificios no recorre lecturas.
-- =========================================================

-- ---------------------------------------------------------
-- 1. Factores de emisión
-- Se aplican a todo el histórico (desde 2000-01-01) porque aún no
-- hay cálculos previos. Un cambio futuro debe cerrar el factor
-- vigente (fecha_fin) e insertar uno nuevo, para que los periodos
-- anteriores sigan calculándose con su factor.
-- ---------------------------------------------------------
update public.parametros_saas
   set valor_numerico = 0.183,
       fecha_inicio = date '2000-01-01',
       descripcion = 'Factor de emisiones de la electricidad consumida.'
 where codigo = 'FACTOR_CO2_ELECTRICIDAD' and activo;

insert into public.parametros_saas (codigo, nombre, valor_numerico, unidad, descripcion, fecha_inicio)
select 'FACTOR_CO2_GAS', 'Factor de emisiones del gas natural', 0.182, 'kgCO2e/kWh',
       'Factor de emisiones del gas natural consumido (kWh PCS).', date '2000-01-01'
where not exists (select 1 from public.parametros_saas where codigo = 'FACTOR_CO2_GAS' and activo);

-- Factor aplicable a una fecha concreta.
create or replace function public.factor_co2(p_codigo text, p_fecha date)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select ps.valor_numerico
  from public.parametros_saas ps
  where ps.codigo = p_codigo
    and ps.fecha_inicio <= p_fecha
    and (ps.fecha_fin is null or ps.fecha_fin > p_fecha)
  order by ps.fecha_inicio desc
  limit 1;
$$;

revoke all on function public.factor_co2(text, date) from public, anon;
grant execute on function public.factor_co2(text, date) to authenticated, service_role;

-- ---------------------------------------------------------
-- 2. Tecnologías de generación (añade solar térmica, geotermia, biomasa)
-- ---------------------------------------------------------
alter table public.suministros_generacion
  drop constraint if exists suministro_generacion_tecnologia_ck;
alter table public.suministros_generacion
  add constraint suministro_generacion_tecnologia_ck
  check (tecnologia in (
    'FOTOVOLTAICA', 'SOLAR_TERMICA', 'GEOTERMIA', 'EOLICA', 'BIOMASA',
    'COGENERACION', 'OTRA'));

alter table public.suministros_generacion
  add column if not exists renovable boolean
  generated always as (
    tecnologia in ('FOTOVOLTAICA', 'SOLAR_TERMICA', 'GEOTERMIA', 'EOLICA', 'BIOMASA')
  ) stored;

comment on column public.suministros_generacion.renovable is
  'Calculado: la cogeneración y "otra" no cuentan como renovables.';

-- ---------------------------------------------------------
-- 3. Magnitudes por tipo de suministro (catálogo del motor)
-- ---------------------------------------------------------
insert into public.magnitudes (codigo, nombre, unidad, descripcion) values
  ('CONSUMO_ELECTRICIDAD', 'Consumo de electricidad', 'kWh', 'Electricidad consumida en el periodo.'),
  ('CONSUMO_GAS', 'Consumo de gas', 'kWh', 'Gas consumido en el periodo, en kWh.'),
  ('CONSUMO_AGUA', 'Consumo de agua', 'm3', 'Agua consumida en el periodo.'),
  ('GENERACION_FOTOVOLTAICA', 'Generación solar fotovoltaica', 'kWh', 'Electricidad generada por instalaciones fotovoltaicas.'),
  ('GENERACION_SOLAR_TERMICA', 'Generación solar térmica', 'kWh', 'Energía térmica generada por captadores solares.'),
  ('GENERACION_GEOTERMIA', 'Generación geotérmica', 'kWh', 'Energía térmica aportada por geotermia.'),
  ('GENERACION_EOLICA', 'Generación eólica', 'kWh', 'Electricidad generada por aerogeneradores.'),
  ('GENERACION_BIOMASA', 'Generación con biomasa', 'kWh', 'Energía térmica producida con biomasa.')
on conflict (codigo) do nothing;

update public.magnitudes
   set descripcion = 'Emisiones = consumo de electricidad × factor de electricidad + consumo de gas × factor de gas (parametros_saas, vigentes en cada fecha).',
       formula = 'CONSUMO_ELECTRICIDAD * FACTOR_CO2_ELECTRICIDAD + CONSUMO_GAS * FACTOR_CO2_GAS'
 where codigo = 'CO2';

-- ---------------------------------------------------------
-- 4. Resúmenes diarios por edificio
-- fecha = día LOCAL del edificio (edificios.zona_horaria).
-- Los escribe el motor (service_role); los usuarios solo leen.
-- Tamaño: 2.000 edificios × 7 indicadores × 365 días ≈ 5 M filas/año.
-- ---------------------------------------------------------
create table if not exists public.resumenes_diarios (
  id_edificio uuid not null references public.edificios(id) on delete restrict,
  fecha date not null,
  indicador varchar(40) not null,
  valor double precision not null,
  completo boolean not null default true,
  actualizado timestamptz not null default now(),
  constraint resumenes_diarios_pk primary key (id_edificio, fecha, indicador),
  constraint resumenes_diarios_indicador_ck check (indicador in (
    'CONSUMO_ELECTRICIDAD', 'CONSUMO_GAS', 'CONSUMO_AGUA', 'ELECTRICIDAD_EXPORTADA',
    'GENERACION_FOTOVOLTAICA', 'GENERACION_EOLICA',
    'GENERACION_SOLAR_TERMICA', 'GENERACION_GEOTERMIA', 'GENERACION_BIOMASA'))
);

create index if not exists ix_resumenes_diarios_fecha
  on public.resumenes_diarios(fecha, indicador);

alter table public.resumenes_diarios enable row level security;

comment on table public.resumenes_diarios is
  'Totales diarios por edificio para los KPIs de los dashboards. completo = false si faltaron datos ese día.';

drop policy if exists resumenes_diarios_select on public.resumenes_diarios;
create policy resumenes_diarios_select on public.resumenes_diarios
for select to authenticated
using (id_edificio in (select private.edificios_accesibles()));

-- ---------------------------------------------------------
-- 5. Edificios de un ámbito (con los permisos del usuario)
--   PLATAFORMA: todos los accesibles
--   PARTNER:    edificios asignados al partner
--   CLIENTE:    edificios del cliente
--   EDIFICIO:   ese edificio
-- ---------------------------------------------------------
create or replace function public.edificios_de_ambito(p_nivel text, p_id uuid default null)
returns setof uuid
language sql
stable
set search_path = ''
as $$
  select e.id
  from public.edificios e
  where e.activo
    -- Sin sesión de usuario (API con service_role): todos los edificios.
    and (auth.uid() is null or e.id in (select private.edificios_accesibles()))
    and case pg_catalog.upper(p_nivel)
          when 'PLATAFORMA' then true
          when 'PARTNER' then exists (
            select 1 from public.proveedores_edificios pe
            where pe.id_edificio = e.id and pe.id_proveedor = p_id and pe.activo)
          when 'CLIENTE' then e.id_cliente = p_id
          when 'EDIFICIO' then e.id = p_id
          else false
        end;
$$;

-- ---------------------------------------------------------
-- 6. KPIs de un ámbito: año en curso hasta p_fecha frente al
--    mismo periodo del año anterior.
-- ---------------------------------------------------------
create or replace function public.kpis_ambito(
  p_nivel text,
  p_id uuid default null,
  p_fecha date default current_date
)
returns jsonb
language sql
stable
set search_path = ''
as $$
  with
  periodos as (
    select pg_catalog.date_trunc('year', p_fecha)::date as desde,
           p_fecha as hasta,
           (pg_catalog.date_trunc('year', p_fecha) - interval '1 year')::date as desde_ant,
           (p_fecha - interval '1 year')::date as hasta_ant
  ),
  edificios as (
    select id from public.edificios_de_ambito(p_nivel, p_id) as id
  ),
  datos as (
    select r.id_edificio, r.indicador, r.fecha, r.valor,
           (r.fecha between p.desde and p.hasta) as actual,
           case r.indicador
             when 'CONSUMO_ELECTRICIDAD' then r.valor * coalesce(public.factor_co2('FACTOR_CO2_ELECTRICIDAD', r.fecha), 0)
             when 'CONSUMO_GAS'          then r.valor * coalesce(public.factor_co2('FACTOR_CO2_GAS', r.fecha), 0)
           end as kg_co2
    from public.resumenes_diarios r
    cross join periodos p
    where r.id_edificio in (select id from edificios)
      and (r.fecha between p.desde and p.hasta or r.fecha between p.desde_ant and p.hasta_ant)
  ),
  comparables as (
    select id_edificio from datos group by id_edificio
    having bool_or(actual) and bool_or(not actual)
  ),
  -- Por edificio y periodo. Energía consumida (decisión 21/10/2026) =
  -- electricidad importada + gas + renovable consumida, donde
  -- renovable consumida = (FV + eólica − exportada) + térmicas.
  por_edificio as (
    select x.*,
           greatest(x.ren_electrica - x.exportada, 0) + x.ren_termica as renovable_consumida,
           x.electricidad + x.gas + greatest(x.ren_electrica - x.exportada, 0) + x.ren_termica as energia
    from (
      select d.id_edificio, d.actual,
        coalesce(sum(d.valor) filter (where d.indicador = 'CONSUMO_ELECTRICIDAD'), 0) as electricidad,
        coalesce(sum(d.valor) filter (where d.indicador = 'CONSUMO_GAS'), 0) as gas,
        coalesce(sum(d.valor) filter (where d.indicador = 'CONSUMO_AGUA'), 0) as agua,
        coalesce(sum(d.valor) filter (where d.indicador = 'ELECTRICIDAD_EXPORTADA'), 0) as exportada,
        coalesce(sum(d.valor) filter (where d.indicador in ('GENERACION_FOTOVOLTAICA', 'GENERACION_EOLICA')), 0) as ren_electrica,
        coalesce(sum(d.valor) filter (where d.indicador in ('GENERACION_SOLAR_TERMICA', 'GENERACION_GEOTERMIA', 'GENERACION_BIOMASA')), 0) as ren_termica,
        coalesce(sum(d.valor) filter (where d.indicador = 'GENERACION_FOTOVOLTAICA'), 0) as fotovoltaica,
        coalesce(sum(d.valor) filter (where d.indicador = 'GENERACION_EOLICA'), 0) as eolica,
        coalesce(sum(d.valor) filter (where d.indicador = 'GENERACION_SOLAR_TERMICA'), 0) as solar_termica,
        coalesce(sum(d.valor) filter (where d.indicador = 'GENERACION_GEOTERMIA'), 0) as geotermia,
        coalesce(sum(d.valor) filter (where d.indicador = 'GENERACION_BIOMASA'), 0) as biomasa,
        coalesce(sum(d.kg_co2), 0) / 1000.0 as tco2
      from datos d
      group by d.id_edificio, d.actual
    ) x
  ),
  totales as (
    select pe.actual,
           (pe.id_edificio in (select id_edificio from comparables)) as comparable,
           sum(pe.energia) as energia, sum(pe.electricidad) as electricidad, sum(pe.gas) as gas,
           sum(pe.renovable_consumida) as renovable_consumida, sum(pe.tco2) as tco2, sum(pe.agua) as agua,
           sum(pe.ren_electrica + pe.ren_termica) as renovable, sum(pe.exportada) as exportada,
           sum(pe.fotovoltaica) as fotovoltaica, sum(pe.eolica) as eolica,
           sum(pe.solar_termica) as solar_termica, sum(pe.geotermia) as geotermia, sum(pe.biomasa) as biomasa
    from por_edificio pe
    group by 1, 2
  ),
  indicadores(codigo, nombre, unidad, orden) as (
    values ('energia', 'Consumo de energía (importada + renovable consumida)', 'kWh', 1),
           ('tco2', 'Emisiones', 'tCO2e', 2),
           ('electricidad', 'Electricidad importada de la red', 'kWh', 3),
           ('gas', 'Gas', 'kWh', 4),
           ('renovable_consumida', 'Renovable consumida', 'kWh', 5),
           ('agua', 'Agua', 'm3', 6),
           ('renovable', 'Generación renovable', 'kWh', 7),
           ('exportada', 'Electricidad exportada a la red', 'kWh', 8),
           ('fotovoltaica', 'Solar fotovoltaica', 'kWh', 9),
           ('eolica', 'Eólica', 'kWh', 10),
           ('solar_termica', 'Solar térmica', 'kWh', 11),
           ('geotermia', 'Geotermia', 'kWh', 12),
           ('biomasa', 'Biomasa', 'kWh', 13)
  ),
  valores as (
    select i.codigo, i.nombre, i.unidad, i.orden,
           sum((pg_catalog.to_jsonb(t)->>i.codigo)::double precision) filter (where t.actual) as valor,
           sum((pg_catalog.to_jsonb(t)->>i.codigo)::double precision) filter (where t.actual and t.comparable) as actual_comparable,
           sum((pg_catalog.to_jsonb(t)->>i.codigo)::double precision) filter (where not t.actual and t.comparable) as anterior_comparable
    from indicadores i
    left join totales t on true
    group by i.codigo, i.nombre, i.unidad, i.orden
  )
  select pg_catalog.jsonb_build_object(
    'nivel', pg_catalog.upper(p_nivel),
    'id', p_id,
    'periodo', (select pg_catalog.jsonb_build_object('desde', desde, 'hasta', hasta) from periodos),
    'periodo_anterior', (select pg_catalog.jsonb_build_object('desde', desde_ant, 'hasta', hasta_ant) from periodos),
    'edificios', (select count(*) from edificios),
    'edificios_comparables', (select count(*) from comparables),
    'cobertura_renovable_pct', (select case when sum(energia) > 0
                                  then round((sum(renovable_consumida) / sum(energia) * 100)::numeric, 1) end
                                from totales where actual),
    'factores_co2', pg_catalog.jsonb_build_object(
       'electricidad', public.factor_co2('FACTOR_CO2_ELECTRICIDAD', p_fecha),
       'gas', public.factor_co2('FACTOR_CO2_GAS', p_fecha),
       'unidad', 'kgCO2e/kWh'),
    'indicadores', (
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'codigo', codigo, 'nombre', nombre, 'unidad', unidad,
        'valor', coalesce(valor, 0),
        'variacion_pct', case when coalesce(anterior_comparable, 0) <> 0
          then round(((coalesce(actual_comparable, 0) - anterior_comparable) / anterior_comparable * 100)::numeric, 1)
        end) order by orden)
      from valores)
  );
$$;

-- ---------------------------------------------------------
-- 7. KPIs por elemento de la lista (partners, clientes o edificios)
--    para las columnas de la lista de cada nivel.
-- ---------------------------------------------------------
create or replace function public.kpis_lista(
  p_nivel text,
  p_id uuid default null,
  p_fecha date default current_date
)
returns table (
  id uuid,
  energia_kwh double precision,
  tco2 double precision,
  agua_m3 double precision,
  renovable_kwh double precision,
  variacion_energia_pct numeric
)
language sql
stable
set search_path = ''
as $$
  with
  periodos as (
    select pg_catalog.date_trunc('year', p_fecha)::date as desde, p_fecha as hasta,
           (pg_catalog.date_trunc('year', p_fecha) - interval '1 year')::date as desde_ant,
           (p_fecha - interval '1 year')::date as hasta_ant
  ),
  -- elemento de la lista al que pertenece cada edificio del ámbito
  pertenencia as (
    select e.id as id_edificio,
           case pg_catalog.upper(p_nivel)
             when 'PLATAFORMA' then (select pe.id_proveedor from public.proveedores_edificios pe
                                     where pe.id_edificio = e.id and pe.activo limit 1)
             when 'PARTNER' then e.id_cliente
             else e.id
           end as id_elemento
    from public.edificios e
    where e.id in (select public.edificios_de_ambito(p_nivel, p_id))
  ),
  datos as (
    select pt.id_elemento, r.id_edificio, r.indicador, r.valor, r.fecha,
           (r.fecha between p.desde and p.hasta) as actual,
           case r.indicador
             when 'CONSUMO_ELECTRICIDAD' then r.valor * coalesce(public.factor_co2('FACTOR_CO2_ELECTRICIDAD', r.fecha), 0)
             when 'CONSUMO_GAS'          then r.valor * coalesce(public.factor_co2('FACTOR_CO2_GAS', r.fecha), 0)
           end as kg_co2
    from public.resumenes_diarios r
    join pertenencia pt on pt.id_edificio = r.id_edificio
    cross join periodos p
    where r.fecha between p.desde and p.hasta or r.fecha between p.desde_ant and p.hasta_ant
  ),
  comparables as (
    select id_edificio from datos group by id_edificio
    having bool_or(actual) and bool_or(not actual)
  ),
  -- Por edificio y periodo. Energía consumida (decisión 21/10/2026) =
  -- electricidad importada + gas + renovable consumida, donde
  -- renovable consumida = (FV + eólica − exportada) + térmicas.
  por_edificio as (
    select x.*,
           greatest(x.ren_electrica - x.exportada, 0) + x.ren_termica as renovable_consumida,
           x.electricidad + x.gas + greatest(x.ren_electrica - x.exportada, 0) + x.ren_termica as energia
    from (
      select d.id_edificio, d.actual,
        coalesce(sum(d.valor) filter (where d.indicador = 'CONSUMO_ELECTRICIDAD'), 0) as electricidad,
        coalesce(sum(d.valor) filter (where d.indicador = 'CONSUMO_GAS'), 0) as gas,
        coalesce(sum(d.valor) filter (where d.indicador = 'CONSUMO_AGUA'), 0) as agua,
        coalesce(sum(d.valor) filter (where d.indicador = 'ELECTRICIDAD_EXPORTADA'), 0) as exportada,
        coalesce(sum(d.valor) filter (where d.indicador in ('GENERACION_FOTOVOLTAICA', 'GENERACION_EOLICA')), 0) as ren_electrica,
        coalesce(sum(d.valor) filter (where d.indicador in ('GENERACION_SOLAR_TERMICA', 'GENERACION_GEOTERMIA', 'GENERACION_BIOMASA')), 0) as ren_termica,
        coalesce(sum(d.valor) filter (where d.indicador = 'GENERACION_FOTOVOLTAICA'), 0) as fotovoltaica,
        coalesce(sum(d.valor) filter (where d.indicador = 'GENERACION_EOLICA'), 0) as eolica,
        coalesce(sum(d.valor) filter (where d.indicador = 'GENERACION_SOLAR_TERMICA'), 0) as solar_termica,
        coalesce(sum(d.valor) filter (where d.indicador = 'GENERACION_GEOTERMIA'), 0) as geotermia,
        coalesce(sum(d.valor) filter (where d.indicador = 'GENERACION_BIOMASA'), 0) as biomasa,
        coalesce(sum(d.kg_co2), 0) / 1000.0 as tco2
      from datos d
      group by d.id_edificio, d.actual
    ) x
  ),
  agregado as (
    select pt.id_elemento,
      sum(pe.energia) filter (where pe.actual) as energia,
      sum(pe.tco2) filter (where pe.actual) as tco2,
      sum(pe.agua) filter (where pe.actual) as agua,
      sum(pe.ren_electrica + pe.ren_termica) filter (where pe.actual) as renovable,
      sum(pe.energia) filter (where pe.actual and pe.id_edificio in (select id_edificio from comparables)) as energia_act_comp,
      sum(pe.energia) filter (where not pe.actual and pe.id_edificio in (select id_edificio from comparables)) as energia_ant_comp
    from por_edificio pe
    join pertenencia pt on pt.id_edificio = pe.id_edificio
    group by pt.id_elemento
  )
  select x.id_elemento,
         coalesce(a.energia, 0), coalesce(a.tco2, 0), coalesce(a.agua, 0), coalesce(a.renovable, 0),
         case when coalesce(a.energia_ant_comp, 0) <> 0
           then round(((coalesce(a.energia_act_comp, 0) - a.energia_ant_comp) / a.energia_ant_comp * 100)::numeric, 1)
         end
  from (select distinct id_elemento from pertenencia where id_elemento is not null) x
  left join agregado a on a.id_elemento = x.id_elemento;
$$;

revoke all on function public.edificios_de_ambito(text, uuid) from public, anon;
revoke all on function public.kpis_ambito(text, uuid, date) from public, anon;
revoke all on function public.kpis_lista(text, uuid, date) from public, anon;
grant execute on function public.edificios_de_ambito(text, uuid) to authenticated, service_role;
grant execute on function public.kpis_ambito(text, uuid, date) to authenticated, service_role;
grant execute on function public.kpis_lista(text, uuid, date) to authenticated, service_role;

commit;
