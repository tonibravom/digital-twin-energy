# Guía de instalación

Instalación completa de la plataforma en la infraestructura del comprador. Requiere conocimientos básicos de terminal y de Supabase. Tiempo estimado: 2–3 horas.

## 0. Requisitos

| Elemento | Uso |
|---|---|
| Cuenta de **Supabase** (obligatorio), plan de pago | Base de datos PostgreSQL, autenticación, almacenamiento de modelos 3D |
| Servicio para la **API Python/FastAPI** (Render, Railway, Fly.io, un servidor propio…) | Motor de cálculo, ingesta de datos y operaciones de administración |
| Hosting estático para el **frontend** (Render Static Site, Netlify, Vercel, Nginx…) | Aplicación web |
| **Servidor SMTP** propio (SendGrid, Amazon SES, Mailgun, Office 365…) | Invitaciones de usuarios y emails de alarmas |
| **Node.js LTS** y **Docker Desktop** en el equipo del técnico | Supabase CLI y entorno local de pruebas |
| **Git** | Gestión del código |

Antes de empezar, lea `docs/dimensionamiento.md` para elegir los recursos de Supabase.

## 1. Probar en local (recomendado)

```powershell
git clone <repositorio> plataforma
cd plataforma
npx supabase start          # arranca Supabase local en Docker
npx supabase db reset       # aplica las 26 migraciones
npx supabase test db        # ejecuta las pruebas de seguridad: deben pasar todas
```

Si `supabase/config.toml` no existe, ejecute antes `npx supabase init`; conserva las carpetas `migrations` y `tests`.

## 2. Crear el proyecto Supabase

1. En https://supabase.com/dashboard, cree un proyecto nuevo.
   - **Región:** la más cercana a los edificios. Para clientes de la UE, una región europea (RGPD).
   - **Contraseña de base de datos:** guárdela en un gestor de contraseñas.
2. En *Project Settings > Compute and Disk*, ajuste cómputo y disco según `docs/dimensionamiento.md`.
3. En *Database > Extensions*, active **pg_cron**. Lo necesita la tarea diaria de mantenimiento.

Recomendado: un segundo proyecto de **pruebas (staging)** con la misma configuración, para validar cambios antes de producción.

## 3. Configurar la autenticación

En *Authentication*:

| Ajuste | Valor | Motivo |
|---|---|---|
| *Sign In / Providers > Email* | Activado | Acceso con email y contraseña |
| **Allow new users to sign up** | **Desactivado** | Los usuarios los da de alta el administrador o el Partner desde la plataforma. Es esencial para la seguridad |
| *Sign In / Providers > Email > Minimum password length* | 10 | Igual que la regla de la plataforma |
| *URL Configuration > Site URL* | URL pública del frontend | Redirecciones tras iniciar sesión |

Supabase no envía ningún email: los códigos de doble factor los envía la API con el servicio de email configurado (paso 6).

## 4. Aplicar las migraciones

```powershell
npx supabase login
npx supabase link --project-ref <ref-del-proyecto>   # el ref aparece en la URL del dashboard
npx supabase db push                                  # aplica supabase/migrations en orden
```

Compruebe en el *SQL Editor*:

```sql
select * from public.verificar_rls();          -- debe devolver 0 filas
select public.mantenimiento_datos();           -- crea particiones; devuelve un resumen
select jobname, schedule from cron.job;        -- deben aparecer 'mantenimiento_datos' y 'motor_15min'
```

Si `cron.job` no muestra la tarea, active pg_cron (paso 2.3) y vuelva a ejecutar el bloque final de `018_retencion_mantenimiento.sql` en el SQL Editor.

## 5. Crear el primer administrador

1. *Authentication > Users > Add user > Create new user*: introduzca el email y una contraseña temporal, y copie el **UUID** del usuario creado.
2. En el *SQL Editor*:

```sql
select public.instalar_administrador(
  '<UUID copiado>', 'Nombre', 'email@empresa.com', 'Apellidos');
```

Esta función solo funciona mientras no exista ningún administrador. Los demás usuarios se crean desde la aplicación, que llama a la API.

El administrador **necesita el código por email** en cada sesión: configure el servicio de email de la API (paso 6) antes de entrar por primera vez.

## 6. Desplegar la API

Variables de entorno de la API (nunca en el código ni en el repositorio):

| Variable | Valor | Dónde se obtiene |
|---|---|---|
| `SUPABASE_URL` | `https://<ref>.supabase.co` | *Project Settings > API* |
| `SUPABASE_SERVICE_ROLE_KEY` | clave `service_role` / *secret* | *Project Settings > API Keys*. **Solo en el backend** |
| `SUPABASE_ANON_KEY` | clave `anon` / *publishable* | *Project Settings > API Keys* |
| `ORIGENES_CORS` | URL del frontend | Para CORS |
| `WEB_URL` | URL del frontend | Enlace del email de bienvenida a los usuarios nuevos |
| `EMAIL_PROVEEDOR` | `brevo` o `smtp` | Envío de los códigos de doble factor (ver README de la API) |
| `EMAIL_REMITENTE` | dirección verificada en el proveedor | Proveedor de email |
| `BREVO_API_KEY` o `SMTP_*` | clave del proveedor | Proveedor de email. **Solo en el backend** |

Con Brevo: remitente con **dominio propio** autenticado (DKIM y DMARC), clave *Restricted* con solo *Transactional emails: All* copiada entera (`xkeysib-…`) y el bloqueo de *IP autorizadas* desactivado para claves de API. Detalle en el README de la API.

La clave `service_role` salta todas las protecciones de la base de datos. Solo debe existir en las variables de entorno del servidor de la API.

## 7. Desplegar el frontend

El frontend solo necesita `SUPABASE_URL`, la clave `anon`/*publishable* y la URL de la API. La clave `anon` es pública por diseño: la seguridad la garantizan RLS y la API.

## 8. Verificación final

- [ ] `select * from public.verificar_rls();` devuelve 0 filas.
- [ ] El registro público está desactivado. Prueba: intentar registrarse desde la pantalla de login debe fallar.
- [ ] El primer administrador inicia sesión y crea un Partner de prueba.
- [ ] Un usuario del Partner de prueba solo ve los clientes y edificios de ese Partner.
- [ ] Las tareas `mantenimiento_datos` y `motor_15min` aparecen en `cron.job`, y `motor_15min` termina bien en `cron.job_run_details`.
- [ ] Se sube un GLB de prueba: primero el registro en `modelos_3d` y después el archivo en el bucket `modelos-3d`.
- [ ] Las copias de seguridad están activas (*Database > Backups*).
- [ ] `npx supabase test db` pasa en local o en staging.

## 9. Operación habitual

| Tarea | Cómo |
|---|---|
| Alta de Partners | Administrador de plataforma, desde la aplicación |
| Alta de clientes y edificios | Partner, desde la aplicación (funciones `crear_cliente_partner` y `crear_edificio_partner`) |
| Alta de usuarios | Desde la aplicación; la API los crea en Supabase Auth y asigna rol y alcance |
| Modelos 3D | Uno general por edificio y uno por recinto. Rutas: `edificios/<id>/modelos/<archivo>.glb` y `recintos/<id>/modelos/<archivo>.glb` |
| Mantenimiento de datos | Automático (pg_cron, diario a las 03:15 UTC) |
| Revisión de rendimiento | Mensual: *Reports* y *Query Performance* del dashboard de Supabase |
| Cambios de esquema | Siempre con una migración nueva en `supabase/migrations`, probada en staging. Nunca editar una migración ya aplicada |
