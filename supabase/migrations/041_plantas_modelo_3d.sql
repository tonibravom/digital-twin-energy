-- =========================================================
-- 041 · Plantas del modelo 3D y elemento de cada etiqueta
-- Decisión D51 (11/11/2026).
--
--   · plantas.niveles_modelo: nombres de los niveles del modelo 3D (los de
--     Revit, p. ej. "L1 - Block 35") que forman cada planta de la
--     plataforma. El visor los usa para mostrar el edificio planta a planta.
--     Un nivel del modelo pertenece como mucho a una planta del edificio.
--     Los niveles que no se asignan van a la planta más cercana por cota.
--   · ubicaciones_3d.id_elemento_modelo: elemento del modelo sobre el que se
--     colocó la etiqueta (identificador de Revit), cuando se coloca pulsando
--     en el visor. Sirve para comprobar que la planta coincide con la del
--     recinto del sensor.
-- =========================================================
begin;

alter table public.plantas
  add column if not exists niveles_modelo text[] not null default '{}';
comment on column public.plantas.niveles_modelo is
  'Niveles del modelo 3D (nombres de Revit o Blender) que forman esta planta. Un nivel solo puede estar en una planta del edificio.';

create or replace function public.validar_niveles_modelo_planta()
returns trigger
language plpgsql
security definer   -- comprueba con todas las plantas del edificio; el permiso lo decide RLS
set search_path = ''
as $$
declare
  v_repetido text;
begin
  new.niveles_modelo := coalesce(new.niveles_modelo, '{}');
  select n into v_repetido
  from pg_catalog.unnest(new.niveles_modelo) n
  group by n having count(*) > 1 limit 1;
  if v_repetido is not null then
    raise exception 'El nivel del modelo "%" está repetido en la planta', v_repetido;
  end if;
  select n into v_repetido
  from public.plantas p, pg_catalog.unnest(p.niveles_modelo) n
  where p.id_edificio = new.id_edificio and p.id <> new.id and p.activo
    and n = any (new.niveles_modelo)
  limit 1;
  if v_repetido is not null then
    raise exception 'El nivel del modelo "%" ya está asignado a otra planta del edificio', v_repetido;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_plantas_niveles_modelo on public.plantas;
create trigger trg_plantas_niveles_modelo
before insert or update of niveles_modelo on public.plantas
for each row execute function public.validar_niveles_modelo_planta();

alter table public.ubicaciones_3d
  add column if not exists id_elemento_modelo text;
comment on column public.ubicaciones_3d.id_elemento_modelo is
  'Elemento del modelo 3D (identificador de Revit) sobre el que se colocó la etiqueta pulsando en el visor. Vacío si las coordenadas se escribieron a mano.';

revoke all on function public.validar_niveles_modelo_planta() from public, anon;

commit;
