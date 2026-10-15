# No Se Que Hay en la heladerApp

App Flutter offline-first para recordar qué productos hacen falta en casa.

## Desarrollo

Necesitás Flutter 3.19 o superior y Dart 3.3 o superior. Desde esta carpeta,
generá los proyectos nativos si todavía no existen y luego ejecutá:

```sh
flutter create --platforms=android,ios .
flutter pub get
flutter run
flutter test
```

### Build
Para generar una build para Android se utiliza:
```sh
flutter build apk --debug
```

La sincronización local usa mDNS/Bonjour para encontrar teléfonos del mismo hogar
sin ingresar IPs. Android requiere `INTERNET`, `CHANGE_WIFI_MULTICAST_STATE` y
tráfico HTTP local sin cifrar (`android:usesCleartextTraffic="true"`). iOS declara
el acceso a red local y el servicio Bonjour `_groceries._tcp`. Antes de enviar
filas, los teléfonos verifican el par con un intercambio HMAC firmado. El
contenido no está cifrado, tal como especifica el diseño.

La app está organizada por funcionalidades en `lib/features/`. Cada módulo separa
entidades e interfaces de repositorio, implementaciones SQLite y presentación.
`lib/core/` contiene infraestructura compartida; la UI accede a la lógica mediante
repositorios Dart locales, nunca mediante HTTP.

## Estado funcional

- Productos persistidos localmente en SQLite, disponibles sin conexión.
- Lista de compras derivada al consultar: nunca comprado, vencido o marcado vacío.
- Acciones rápidas para marcar comprado, vacío o eliminar; productos faltantes aparecen primero.
- Duración sugerida de 3, 5 o 7 días, o un valor personalizado.
- Creación de hogar e invitación/unión mediante QR con secreto aleatorio de 32 bytes.
- Sincronización bidireccional HTTP autenticada con HMAC-SHA256 sobre la red local;
  descubrimiento automático de teléfonos del mismo hogar y sincronización mientras
  ambas apps están activas en la misma red local. El ingreso manual de IP queda
  disponible como alternativa de diagnóstico.

El intercambio de filas agrega un cursor local al protocolo para confirmar el cursor
de cambios enviados. Al volver a primer plano se reanuda la búsqueda de pares; las
escrituras locales disparan una sincronización con los pares descubiertos. La app no
promete sincronización con las apps cerradas o suspendidas.
