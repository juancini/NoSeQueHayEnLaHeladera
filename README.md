# La heladera

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

Para probar la sincronización Android, el manifiesto nativo debe incluir el permiso
`android.permission.INTERNET` y habilitar tráfico HTTP local sin cifrar
(`android:usesCleartextTraffic="true"`). La firma HMAC autentica estos intercambios;
el contenido no está cifrado, tal como especifica el diseño.

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
  por ahora se inicia manualmente usando la IP privada del otro teléfono.

El intercambio de filas agrega un cursor local al protocolo para confirmar el cursor
de cambios enviados. El descubrimiento automático mDNS, el inicio de sync al volver
a primer plano y la configuración nativa específica de iOS/Android quedan pendientes.
