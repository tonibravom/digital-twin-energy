# Usuarios y acceso

Cómo se dan de alta los usuarios y cómo entran en la plataforma. Acordado el 26/10/2026 (decisiones D27–D30).

## 1. Quién da de alta a quién

No hay registro público: los usuarios los crea alguien con permiso, indicando **email, nombre, rol y ámbito**. No se pone contraseña (D39):

1. La plataforma crea la cuenta con una contraseña aleatoria que nadie conoce.
2. El usuario recibe un **email de bienvenida** con la dirección de la plataforma.
3. Entra, pulsa **«¿Primera vez o ha olvidado la contraseña?»**, recibe un código y elige su contraseña (apartado 3 bis).

Así nadie más conoce su contraseña y no hay que comunicársela. Si el email de bienvenida no llega, quien le dio de alta ve las instrucciones en pantalla para dárselas.

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
- La elige siempre el propio usuario: en la primera entrada y cuando la olvida, con el código por email (apartado 3 bis).
- Desde **Mi cuenta** la puede cambiar indicando la actual y la nueva, que debe ser distinta.
- **Anular contraseña** (administradores y Partners, sobre los usuarios que gestionan): si se sospecha que alguien la conoce. Deja de valer al momento, la base de datos deja de mostrarle datos aunque tenga una sesión abierta, y el usuario elige otra con el código.

## 2 bis. Edición de usuarios (D38)

- Se cambian nombre, apellidos, teléfono, rol y ámbito (clientes, alcance y edificios), con las mismas reglas que el alta.
- El rol solo cambia dentro del mismo tipo: Partner (administrador ↔ técnico) o cliente (usuario ↔ avanzado ↔ solo lectura). Para pasar de un tipo a otro, se da de baja y se crea un usuario nuevo **con otro email** (el email es único aunque el usuario esté de baja).
- El email no se cambia (es la cuenta de acceso), ni el Partner de un usuario de Partner.
- Sobre uno mismo solo se cambian los datos personales. Los usuarios de cliente consultan su perfil en **Mi cuenta** y piden los cambios a su administrador.
- Un usuario dado de baja se reactiva antes de editarlo.

## 3. Doble factor por email

- Al entrar con email y contraseña, si el usuario lo requiere, la plataforma le envía un **código de 6 cifras** a su email.
- El código caduca a los **10 minutos**. Admite **5 intentos**, y se pueden pedir como máximo 5 códigos cada 15 minutos.
- El código vale para **esa sesión** (ese navegador). Otra sesión necesita otro código.
- **Obligatorio** para el administrador de la plataforma y los administradores de Partner. **Voluntario** para técnicos y clientes, que lo activan desde su perfil.
- Qué roles lo exigen se cambia en la base de datos: `update roles set requiere_doble_factor = true where codigo = '...'`.

## 3 bis. Recuperación de contraseña

1. En la pantalla de acceso, **¿Has olvidado la contraseña?** → el usuario escribe su email.
2. Si es de un usuario activo, recibe un **código de 6 cifras**. La pantalla responde siempre lo mismo, exista o no el email, para no revelar quién tiene cuenta.
3. Introduce el código y la contraseña nueva (mismas reglas del apartado 2). Ya no tendrá que cambiarla al entrar.

Límites: el código caduca a los **15 minutos**, admite **5 intentos**, como máximo **3 códigos por hora** por usuario y 10 peticiones cada 15 minutos desde la misma conexión. Pedir un código nuevo anula el anterior. Recuperar la contraseña **no** sustituye al doble factor: al entrar, quien lo tenga recibirá además el código de acceso.

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
| `POST /v1/recuperacion/solicitar` y `/confirmar` | Recuperación de contraseña con código (sin sesión) |
| `POST /v1/usuarios` | Alta sin contraseña; envía el email de bienvenida |
| `PUT /v1/usuarios/{id}` | Edita datos, rol y ámbito |
| `POST /v1/usuarios/{id}/anular-contrasena` | Anula la contraseña de otro usuario |
| `POST /v1/usuarios/{id}/baja` y `/reactivar` | Baja y reactivación, que también bloquean o desbloquean la cuenta en Supabase Auth |

Los listados de usuarios los lee el frontend directamente de la base de datos: RLS solo muestra los que cada uno puede ver.

## 6. Servicio de email

Los códigos los envía la API (`EMAIL_PROVEEDOR`):
- **brevo**: API de Brevo. El plan gratuito permite 300 emails al día y solo exige verificar la dirección remitente. Recomendado.
- **smtp**: el servidor de correo del comprador.

Ver el README de la API para la configuración.
