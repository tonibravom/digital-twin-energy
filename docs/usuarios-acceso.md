# Usuarios y acceso

Cómo se dan de alta los usuarios y cómo entran en la plataforma. Acordado el 26/10/2026 (decisiones D27–D30).

## 1. Quién da de alta a quién

No hay registro público ni invitaciones por email: los usuarios los crea alguien con permiso, con **email y contraseña inicial**, y se la comunica al usuario.

| Quién da de alta | Puede crear |
|---|---|
| Administrador de la plataforma | Cualquier usuario, incluidos otros administradores de la plataforma |
| Administrador del Partner | Administradores y técnicos de **su** Partner, y usuarios de **sus** clientes |
| Técnico del Partner | Técnicos de su Partner y usuarios de sus clientes. **No** crea administradores del Partner |
| Usuarios de cliente | Nadie |

Cada usuario se asigna:
- **Usuarios de Partner:** a un Partner. Con alcance **MASTER** ven todos los edificios del Partner; con **RESTRINGIDO**, solo los que se indiquen.
- **Usuarios de cliente:** a uno o varios clientes. Con **MASTER** ven todos sus edificios; con **RESTRINGIDO**, solo los indicados.

Las mismas reglas se aplican para restablecer la contraseña de otro usuario, darlo de baja o reactivarlo. Nadie puede darse de baja a sí mismo y un técnico no gestiona a su administrador.

## 2. Contraseñas

- Entre 10 y 72 caracteres, con letras y números.
- La **contraseña inicial** solo sirve para la primera entrada: el usuario debe cambiarla. Lo mismo ocurre cuando un administrador se la restablece.
- Para cambiarla, el usuario indica la actual y la nueva, que debe ser distinta.

## 3. Doble factor por email

- Al entrar con email y contraseña, si el usuario lo requiere, la plataforma le envía un **código de 6 cifras** a su email.
- El código caduca a los **10 minutos**. Admite **5 intentos**, y se pueden pedir como máximo 5 códigos cada 15 minutos.
- El código vale para **esa sesión** (ese navegador). Otra sesión necesita otro código.
- **Obligatorio** para el administrador de la plataforma y los administradores de Partner. **Voluntario** para técnicos y clientes, que lo activan desde su perfil.
- Qué roles lo exigen se cambia en la base de datos: `update roles set requiere_doble_factor = true where codigo = '...'`.

## 4. Orden de la entrada

1. Email y contraseña (Supabase Auth).
2. Código por email, si lo requiere.
3. Cambio de contraseña, si es la primera entrada o se la restablecieron.
4. Acceso a la plataforma.

Mientras falte el paso 2 o el 3, **la base de datos no le muestra ningún dato** aunque intente saltarse la interfaz. La función `mi_cuenta()` indica al frontend qué paso falta.

## 5. Rutas de la API

| Ruta | Para qué |
|---|---|
| `GET /v1/mi-cuenta` | Estado de la entrada y datos del usuario |
| `POST /v1/sesion/codigo` | Envía el código al email |
| `POST /v1/sesion/verificar` | Comprueba el código |
| `POST /v1/mi-cuenta/contrasena` | Cambia la propia contraseña |
| `PUT /v1/mi-cuenta/doble-factor` | Activa o desactiva el doble factor voluntario |
| `POST /v1/usuarios` | Alta con contraseña inicial |
| `POST /v1/usuarios/{id}/contrasena` | Restablece la contraseña de otro usuario |
| `POST /v1/usuarios/{id}/baja` y `/reactivar` | Baja y reactivación, que también bloquean o desbloquean la cuenta en Supabase Auth |

Los listados de usuarios los lee el frontend directamente de la base de datos: RLS solo muestra los que cada uno puede ver.

## 6. Servicio de email

Los códigos los envía la API (`EMAIL_PROVEEDOR`):
- **brevo**: API de Brevo. El plan gratuito permite 300 emails al día y solo exige verificar la dirección remitente. Recomendado.
- **smtp**: el servidor de correo del comprador.

Ver el README de la API para la configuración.
