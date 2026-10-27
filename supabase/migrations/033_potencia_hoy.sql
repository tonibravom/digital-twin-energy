-- =========================================================
-- 033 · Potencia y factor de potencia en la pestaña Hoy
-- Decisión D41 (27/10/2026): la pestaña Hoy muestra la potencia (con su
-- comparación con el día comparable a la misma hora) y el factor de
-- potencia del edificio.
--   · Nueva magnitud FACTOR_POTENCIA (sin unidad). El Partner le asigna
--     el sensor de factor de potencia del contador general.
--   · potencia_edificio(): último valor de la última hora de POTENCIA_TOTAL
--     y FACTOR_POTENCIA, y el de POTENCIA_TOTAL a la misma hora del día
--     comparable (mismo criterio que hoy_edificio).
-- =========================================================
begin;

insert into public.magnitudes (codigo, nombre, unidad, descripcion) values
  ('FACTOR_POTENCIA', 'Factor de potencia', '-', 'Factor de potencia (cos φ) del suministro eléctrico general. Asigne un único sensor.')
on conflict (codigo) do nothing;

create or replace function public.potencia_edificio(p_id_edificio uuid, p_ahora timestamptz default now())
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_zona text;
  v_hoy date;
  v_comp date;
  v_comp_instante timestamptz;
  v_pot uuid;
  v_fp uuid;
  v_actual double precision;
  v_comparable double precision;
  v_factor double precision;
begin
  select e.zona_horaria into v_zona from public.edificios e where e.id = p_id_edificio;
  if v_zona is null then
    raise exception 'Edificio inexistente o sin acceso';
  end if;

  v_hoy := (p_ahora at time zone v_zona)::date;
  v_comp := public.dia_comparable(p_id_edificio, v_hoy);
  v_comp_instante := (v_comp::timestamp + ((p_ahora at time zone v_zona) - v_hoy::timestamp)) at time zone v_zona;

  select me.id into v_pot from public.magnitudes_edificio me join public.magnitudes m on m.id = me.id_magnitud
  where me.id_edificio = p_id_edificio and me.ambito = 'EDIFICIO' and me.activa and m.codigo = 'POTENCIA_TOTAL';
  select me.id into v_fp from public.magnitudes_edificio me join public.magnitudes m on m.id = me.id_magnitud
  where me.id_edificio = p_id_edificio and me.ambito = 'EDIFICIO' and me.activa and m.codigo = 'FACTOR_POTENCIA';

  select v.valor into v_actual from public.valores_magnitud v
  where v.id_magnitud_edificio = v_pot and v.fecha_hora <= p_ahora and v.fecha_hora > p_ahora - interval '1 hour'
  order by v.fecha_hora desc limit 1;
  select v.valor into v_comparable from public.valores_magnitud v
  where v.id_magnitud_edificio = v_pot and v_comp is not null
    and v.fecha_hora <= v_comp_instante and v.fecha_hora > v_comp_instante - interval '1 hour'
  order by v.fecha_hora desc limit 1;
  select v.valor into v_factor from public.valores_magnitud v
  where v.id_magnitud_edificio = v_fp and v.fecha_hora <= p_ahora and v.fecha_hora > p_ahora - interval '1 hour'
  order by v.fecha_hora desc limit 1;

  return pg_catalog.jsonb_build_object(
    'potencia_kw', v_actual,
    'potencia_comparable_kw', v_comparable,
    'dia_comparable', v_comp,
    'variacion_potencia_pct', case when v_comparable > 0 and v_actual is not null
                                then round(((v_actual - v_comparable) / v_comparable * 100)::numeric, 1) end,
    'factor_potencia', case when v_factor is not null then round(v_factor::numeric, 3) end,
    'tiene_potencia', v_pot is not null,
    'tiene_factor_potencia', v_fp is not null);
end;
$$;

revoke all on function public.potencia_edificio(uuid, timestamptz) from public, anon;
grant execute on function public.potencia_edificio(uuid, timestamptz) to authenticated, service_role;

commit;
