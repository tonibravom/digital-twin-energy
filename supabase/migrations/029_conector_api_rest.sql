-- =========================================================
-- 029 · Conector API REST genérico (consulta GET/POST de JSON)
-- Decisión D34 (26/10/2026): un único conector configurable sirve para
-- cualquier plataforma que entregue medidas en JSON (incluidas Sentilo y
-- las nubes de fabricantes), sin programar nada por cada origen.
--
-- Configuración de la conexión:
--   url                 dirección del endpoint
--   metodo              GET (por defecto) o POST
--   autenticacion       NINGUNA | BEARER | API_KEY (cabecera) | BASIC (usuario:contraseña)
--   cabecera_clave      nombre de la cabecera con API_KEY (p. ej. X-API-Key)
--   ruta_lista          ruta JSON a la lista de medidas ($.datos, $.data.items, $ si la respuesta es la lista)
--   campo_fecha         campo de la fecha en cada medida
--   formato_fecha       ISO8601 | EPOCH_S | EPOCH_MS
--   parametro_desde / parametro_hasta   nombres de los parámetros de periodo (si la API los admite)
--   formato_parametros  formato de esas fechas: ISO8601 | EPOCH_S | EPOCH_MS
--   ventana_horas       horas por petición (por defecto 24)
-- El secreto (token, clave o usuario:contraseña) se guarda en Vault.
-- Dirección de cada punto: ruta_valor (campo con el valor) y filtro
-- (campos que identifican la medida de ese punto, p. ej. {"punto": "CONT-01"}).
-- =========================================================
begin;

update public.tipos_conexion set modo = 'CONSULTA', admite_recuperacion = true,
  nombre = 'API REST (JSON)',
  descripcion = 'Cualquier API que entregue medidas en JSON: plataformas IoT, nubes de fabricantes, Sentilo, sistemas de gestión con API… Se configura sin programar.',
  esquema_configuracion = '{
    "type": "object",
    "required": ["url", "autenticacion", "ruta_lista", "campo_fecha"],
    "properties": {
      "url":                {"type": "string", "title": "URL del endpoint", "examples": ["https://api.ejemplo.com/v1/medidas"]},
      "metodo":             {"type": "string", "enum": ["GET", "POST"], "default": "GET"},
      "autenticacion":      {"type": "string", "enum": ["NINGUNA", "BEARER", "API_KEY", "BASIC"]},
      "cabecera_clave":     {"type": "string", "title": "Cabecera de la clave (si autenticación = API_KEY)", "examples": ["X-API-Key"]},
      "ruta_lista":         {"type": "string", "title": "Ruta JSON a la lista de medidas", "examples": ["$.datos", "$.data.items", "$"]},
      "campo_fecha":        {"type": "string", "title": "Campo con la fecha de cada medida", "examples": ["fecha", "timestamp"]},
      "formato_fecha":      {"type": "string", "enum": ["ISO8601", "EPOCH_S", "EPOCH_MS"], "default": "ISO8601"},
      "parametro_desde":    {"type": "string", "title": "Parámetro de inicio del periodo", "examples": ["desde", "from"]},
      "parametro_hasta":    {"type": "string", "title": "Parámetro de fin del periodo", "examples": ["hasta", "to"]},
      "formato_parametros": {"type": "string", "enum": ["ISO8601", "EPOCH_S", "EPOCH_MS"], "default": "ISO8601"},
      "ventana_horas":      {"type": "integer", "minimum": 1, "maximum": 744, "default": 24}
    }
  }'::jsonb,
  esquema_punto = '{
    "type": "object",
    "required": ["ruta_valor"],
    "properties": {
      "ruta_valor": {"type": "string", "title": "Campo con el valor", "examples": ["valor", "energy_kwh", "data.value"]},
      "filtro":     {"type": "object", "title": "Campos que identifican la medida de este punto", "examples": [{"punto": "CONT-01"}]}
    }
  }'::jsonb
where codigo = 'API_REST';

-- Coherencia mínima de la configuración API REST (el resto lo valida la API)
create or replace function public.validar_conexion_api_rest()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (select codigo from public.tipos_conexion where id = new.id_tipo_conexion) = 'API_REST' then
    if new.configuracion->>'url' !~* '^https?://' then
      raise exception 'La URL de la API debe empezar por http:// o https://';
    end if;
    if new.configuracion->>'autenticacion' = 'API_KEY' and coalesce(new.configuracion->>'cabecera_clave', '') = '' then
      raise exception 'Con autenticación API_KEY indique la cabecera de la clave (cabecera_clave)';
    end if;
    if (new.configuracion ? 'parametro_desde') <> (new.configuracion ? 'parametro_hasta') then
      raise exception 'Indique los dos parámetros de periodo (desde y hasta) o ninguno';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_conexiones_validar_api_rest on public.conexiones;
create trigger trg_conexiones_validar_api_rest
before insert or update of id_tipo_conexion, configuracion
on public.conexiones
for each row execute function public.validar_conexion_api_rest();

revoke all on function public.validar_conexion_api_rest() from public, anon, authenticated;

commit;
