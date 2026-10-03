# Kyboardclean

Para pasarle el paño al teclado y al trackpad del Mac sin acabar escribiendo un testamento o haciendo clic donde no toca. Kyboardclean activa un modo limpieza que bloquea los eventos compatibles de teclado y ratón durante un rato.

Tiene temporizador y varias formas de salir. macOS pone sus límites y están explicados más abajo, así que empieza con una sesión corta.

Sí, se llama **Kyboardclean**. El nombre es ese, tal cual.

## Qué trae

- Muestra una ventana de control sencilla en SwiftUI.
- Inicia un overlay de limpieza a pantalla completa en todas las pantallas detectadas por AppKit.
- Usa `CGEventTap` para descartar eventos de teclado y ratón mientras el modo limpieza está activo.
- Bloquea clics, arrastres, movimiento de ratón y scroll por defecto para evitar que atraviesen el overlay.
- Ofrece salidas redundantes propias: temporizador, Control + Option + Command + Escape, Escape 5 veces en 3 segundos y límite duro de seguridad de 30 minutos. Command + Option + Escape se deja pasar para abrir Forzar salida de macOS; no detiene Kyboardclean directamente.
- Reproduce sonidos opcionales al empezar y terminar.
- Incluye Ajustes de sonido, idioma y apariencia, además del estado de Accesibilidad y Secure Event Input.
- Puede permanecer opcionalmente en la barra de menús, con duraciones rápidas y acceso a la ventana y Ajustes.
- Ofrece un atajo global configurable y desactivable, recordatorios locales opcionales y un historial local de sesiones con estadísticas básicas.
- Incluye localización real en español e inglés mediante `es.lproj/Localizable.strings` y `en.lproj/Localizable.strings`.
- Incluye icono de app en `Assets.xcassets/AppIcon.appiconset`, generado desde `Resources/AppIconSource.png`.

## Privacidad y límites del bloqueo

- No se conecta a internet.
- No incluye analytics, tracking, telemetría, crash reporter, login, base de datos ni actualizaciones automáticas.
- No guarda teclas, keycodes, texto ni historial de entrada.
- El historial de limpieza solo guarda fecha, duración y resultado; permanece en `UserDefaults` y se puede borrar desde Ajustes.
- No convierte teclas a texto.
- No llama a `CGEventKeyboardGetUnicodeString`.
- No intenta bloquear controles de seguridad de hardware o del sistema, como Touch ID o el botón físico de encendido.
- No bloquea Command + Option + Escape, el atajo de macOS para Forzar salida.
- No garantiza bloquear todos los gestos multitáctiles que macOS gestione fuera de los eventos normales de aplicación.

## Compatibilidad

Kyboardclean está preparada para macOS 14 Sonoma o superior y se compila con Xcode 16 o superior (Swift 6).

Compatibilidad esperada:

- MacBook Air.
- MacBook Pro.
- MacBook Neo.
- iMac.
- Mac mini con monitor externo.
- Mac Studio con monitor externo.
- Pantallas Retina.
- Pantallas externas.
- Varias pantallas.
- Resoluciones pequeñas y grandes.
- Modo claro y modo oscuro.

La app está pensada principalmente para Apple Silicon. El proyecto no fuerza una arquitectura única y usa la configuración estándar de Xcode para macOS; en Release debería poder compilar como Universal Binary para Apple Silicon e Intel compatibles con macOS 14+, siempre que el entorno de Xcode lo permita.

No hay dependencias externas.

## Idioma y ajustes

Desde la ventana principal, abre **Ajustes** con el botón de engranaje o con el menú **Kyboardclean > Ajustes...**.

Opciones disponibles:

- Efectos de sonido activados/desactivados.
- Idioma: Automático según el sistema, Español o Inglés.
- Apariencia: Sistema, Claro u Oscuro.
- Estado de Accesibilidad y Secure Event Input.
- Icono opcional en la barra de menús.
- Atajo global configurable y desactivable.
- Recordatorios: nunca, semanal, cada dos semanas o cada 30 días.
- Actividad local: número de limpiezas, tiempo total, última limpieza, media e historial borrable.

Las preferencias, el atajo y el historial se guardan localmente en `UserDefaults`. La preferencia de idioma se aplica al instante en la interfaz SwiftUI, el overlay y los comandos de menú propios. Automático usa español o inglés según la localización efectiva de macOS y recurre a inglés ante un idioma no soportado. No se envía ningún dato a ningún sitio. Los recordatorios usan `UserNotifications` y solo solicitan permiso al elegir una frecuencia distinta de Nunca.

El historial conserva las 500 sesiones más recientes y elimina primero las más antiguas. Este límite mantiene acotados el tamaño de `UserDefaults` y el trabajo de arranque; cubre más de un año de uso diario o casi diez años de uso semanal. Una sesión solo se registra después de que overlay y EventTap hayan quedado confirmados como activos.

Los recordatorios usan una única solicitud pendiente con identificador estable. Cambiar idioma o frecuencia reemplaza esa solicitud. Elegir Nunca borra la frecuencia; perder autorización o fallar la programación cancela la solicitud efectiva, pero conserva la frecuencia elegida para poder recuperarla. La opción Cada 30 días usa un intervalo repetitivo independiente de la zona horaria.

Los elementos estándar que pertenecen a AppKit o macOS, como Edición, Ventana y el chrome del panel Acerca de, siguen el idioma del sistema. `InfoPlist.strings` localiza el contenido propio del panel en español e inglés. Si se cambia el idioma del sistema mientras Kyboardclean está abierta, macOS puede requerir relanzar la app para actualizar esos elementos estándar; cambiar la preferencia interna Español/Inglés/Automático no reinicia una sesión.

Los dos efectos incluidos proceden de SND01 "sine", diseñado por Yasuhiro Tsuchiya y publicado en [snd.dev](https://snd.dev/). Se usan `button.wav` para confirmar la activación y `notification.wav` para una finalización normal del temporizador. Los términos de SND permiten integrarlos en aplicaciones personales y comerciales, pero no redistribuir los archivos crudos por separado; el origen y los términos se conservan en `Kyboardclean/Resources/Sounds/NOTICE.txt`.

## Abrir el proyecto en Xcode

1. Abre `Kyboardclean.xcodeproj`.
2. Selecciona el esquema compartido `Kyboardclean`.
3. Selecciona el target `Kyboardclean`.
4. Compila con Xcode 16 o superior (Swift 6) en macOS 14 o superior.

El proyecto no necesita XcodeGen, Swift Package Manager ni dependencias descargadas.

## Sonidos opcionales

Los dos efectos de sonido **no se incluyen en el repositorio**: su licencia (SND) permite usarlos dentro de apps, pero no redistribuir los archivos originales por separado. Sin ellos la app funciona igual, solo que en silencio.

Para añadirlos:

1. Descarga el pack SND01 "sine" desde [snd.dev](https://snd.dev/).
2. Copia `button.wav` como `Kyboardclean/Resources/Sounds/activation.wav`.
3. Copia `notification.wav` como `Kyboardclean/Resources/Sounds/success.wav`.
4. Vuelve a compilar. Git los ignora, así que no se subirán por error.

## Compilar desde la terminal

Debug:

```sh
xcodebuild -project Kyboardclean.xcodeproj -scheme Kyboardclean -configuration Debug build
```

Release:

```sh
xcodebuild -project Kyboardclean.xcodeproj -scheme Kyboardclean -configuration Release build
```

Tests (99 pruebas unitarias):

```sh
xcodebuild -project Kyboardclean.xcodeproj -scheme Kyboardclean -destination 'platform=macOS' test
```

El proyecto mantiene `DEVELOPMENT_TEAM` vacío para que un build local pueda usar "Sign to Run Locally" sin requerir una cuenta de Apple Developer.

## Distribución fuera de App Store

Kyboardclean está pensada para distribución personal fuera de App Store. Usa un target normal de macOS con entitlements vacíos y sin App Sandbox, porque el bloqueo de entrada de bajo nivel con `CGEventTap` no encaja con el sandbox típico de App Store.

Para uso personal o para compartir con gente de confianza:

1. Genera la app con `Scripts/build_release.sh`.
2. Distribuye `dist/Kyboardclean.dmg` o `dist/Kyboardclean.app.zip`.
3. En otro Mac, arrastra `Kyboardclean.app` a Aplicaciones.
4. Si Gatekeeper bloquea la apertura, usa clic derecho > Abrir y confirma que quieres abrirla.

Sin notarización, macOS puede mostrar avisos de Gatekeeper. Para una distribución pública real, necesitas una cuenta de Apple Developer, un certificado Developer ID Application, firma con hardened runtime y notarización de Apple. La firma local/ad-hoc queda limitada a uso personal o pruebas privadas.

El artefacto recomendado es el DMG o el ZIP. No compartas directamente `dist/Kyboardclean.app`: Finder puede añadir metadatos al bundle después de firmarlo. Los scripts limpian y verifican la app al generar los paquetes.

`Scripts/build_release.sh` no usa `codesign --deep` para verificar la app final. Si en una versión futura se añaden frameworks o helper tools propios, deben firmarse y verificarse explícitamente en vez de confiar en una verificación profunda que pueda ocultar errores de empaquetado.

## Scripts de distribución

Generar app Release en `dist/`:

```sh
Scripts/build_release.sh
```

Generar DMG:

```sh
Scripts/build_dmg.sh
```

Generar ZIP de la app compilada:

```sh
Scripts/build_zip.sh
```

Generar ZIP limpio del código fuente:

```sh
Scripts/build_source_zip.sh
```

Resultado esperado:

```text
dist/
├── Kyboardclean.app
├── Kyboardclean.dmg
├── Kyboardclean.app.zip
└── Kyboardclean_Source.zip
```

## Permiso de Accesibilidad

Kyboardclean necesita el permiso de Accesibilidad para que macOS permita instalar un `CGEventTap` capaz de descartar eventos de teclado durante el modo limpieza.

Si falta el permiso:

- La app no crashea.
- Empezar limpieza queda desactivado.
- La UI explica que Accesibilidad es necesaria.
- El botón Abrir Ajustes abre Privacidad y seguridad > Accesibilidad.
- Puede ser necesario cerrar y volver a abrir Kyboardclean después de conceder el permiso.

Para revocar el permiso, abre Ajustes del Sistema > Privacidad y seguridad > Accesibilidad, desactiva Kyboardclean o elimínala de la lista con el botón menos. Después cierra y vuelve a abrir la app para confirmar el estado.

## Input Monitoring

Kyboardclean no solicita explícitamente Input Monitoring y no usa APIs para convertir o leer texto escrito. Accesibilidad es el permiso necesario para el comportamiento de `CGEventTap` implementado aquí. Las solicitudes de privacidad de macOS pueden variar según la versión del sistema y la política local; si macOS muestra un aviso adicional de Input Monitoring, concédelo solo si confías en la app compilada localmente.

## Secure Event Input

macOS puede activar Secure Event Input cuando hay campos de contraseña o apps sensibles abiertas. Cuando Secure Event Input está activo, macOS puede dejar de entregar teclas a `CGEventTap`.

Kyboardclean comprueba `IsSecureEventInputEnabled()` antes de empezar y durante el modo limpieza. Si Secure Event Input está activo, el modo limpieza no empieza o se detiene inmediatamente porque no se puede garantizar el bloqueo seguro del teclado.

Durante una sesión, un supervisor independiente del hilo de interfaz comprueba Secure Event Input y Accesibilidad y puede desarmar el event tap directamente. La validación de ventanas y pantallas usa AppKit y debe ejecutarse en el hilo principal; el límite duro monotónico sigue siendo independiente si ese hilo queda bloqueado.

## Qué se bloquea

| Elemento | ¿Bloqueado? | Nota |
|---|---|---|
| Teclas normales | Sí | `keyDown` y `keyUp` se descartan mediante `CGEventTap`. |
| Modificadores | Sí | `flagsChanged` se descarta. |
| Teclas de medios/brillo | Si es viable | La máscara incluye el bit raw de `systemDefined` cuando macOS entrega esas teclas como CGEvents; algunas rutas de hardware o sistema pueden saltarse la entrega normal. |
| Command + Option + Escape | No | Se deja pasar explícitamente para que Forzar salida de macOS siga disponible. |
| Clics | Sí | `leftMouseDown`, `leftMouseUp`, clic derecho y otros clics se descartan mediante `CGEventTap`. No hay ruta de ratón para Detener durante Cleaning Mode. |
| Movimiento del ratón | Sí | `mouseMoved` se descarta mediante `CGEventTap` para evitar interacciones indirectas durante la limpieza. |
| Arrastres | Sí | `leftMouseDragged`, `rightMouseDragged` y `otherMouseDragged` se descartan mediante `CGEventTap`. |
| Scroll | Sí | `scrollWheel` se descarta mediante `CGEventTap`. |
| Gestos de trackpad | Parcial / no garantizado | Algunos gestos son comportamiento de sistema de más alto nivel y pueden no existir como CGEvents bloqueables. |
| Touch ID | No | Ruta de seguridad de hardware/sistema. |
| Botón de encendido | No | Ruta de hardware/sistema. |
| Secure Event Input | No | El modo limpieza no empieza o se detiene porque macOS puede no entregar teclas a `CGEventTap`. |

## Por qué Kyboardclean no es un keylogger

Kyboardclean usa `CGEventTap` para descartar eventos durante el modo limpieza. El callback consulta solo el estado mínimo necesario para salidas de emergencia: Escape, modificadores para Control + Option + Command + Escape y marcas de tiempo breves para la secuencia Escape x5.

Kyboardclean no guarda keycodes, no guarda texto escrito, no llama a `CGEventKeyboardGetUnicodeString`, no escribe logs de teclas y no imprime eventos de teclado en consola. El código fuente tampoco contiene APIs de red como `URLSession`, `Network`, `NWConnection`, `NSURLConnection`, `CFNetwork`, sockets ni llamadas HTTP, así que no hay una ruta de código para enviar entrada a ningún sitio.

`UserDefaults` se usa solo para preferencias inocuas, configuración del atajo y recordatorios, y el historial local de sesiones descrito arriba. Nunca contiene teclas ni eventos de entrada.

## La primera vez, prueba esto

1. Compila y abre Kyboardclean.
2. Concede el permiso de Accesibilidad.
3. Cierra y vuelve a abrir la app si el estado del permiso no se actualiza.
4. Elige 30 segundos.
5. Empieza el modo limpieza.
6. Comprueba que aparece el overlay.
7. Comprueba que escribir no afecta a otras apps.
8. Deja que termine el temporizador antes de probar sesiones más largas.

No empieces la primera prueba con modo infinito ni con una sesión larga.

## Cómo salir si algo falla

- Pulsa Control + Option + Command + Escape.
- Pulsa Escape 5 veces en 3 segundos.
- Pulsa Command + Option + Escape para abrir Forzar salida de macOS.
- Espera al temporizador o al límite duro de 30 minutos.
- Cierra la app desde macOS si es posible; al terminar el proceso, macOS elimina el event tap.
- Usa controles de hardware o sistema, como el botón de encendido o Touch ID, si es necesario. Kyboardclean no los bloquea.

## Plan de prueba manual

1. Abrir la app sin permiso de Accesibilidad. Esperado: no crashea, Empezar queda desactivado y se muestra explicación.
2. Conceder Accesibilidad. Esperado: Actualizar muestra permiso concedido; reiniciar la app también.
3. Iniciar una sesión personalizada de 10 segundos. Esperado: aparece el overlay, el teclado queda bloqueado y el temporizador termina solo.
4. Iniciar una sesión de 60 segundos. Esperado: la cuenta atrás empieza en 60 segundos y termina sola.
5. Probar Control + Option + Command + Escape. Esperado: la sesión termina inmediatamente.
6. Probar Escape x5 en 3 segundos. Esperado: la sesión termina inmediatamente.
7. Probar modo infinito. Esperado: no hay cuenta atrás normal y el límite duro cuenta desde 30 minutos.
8. Pulsar muchas teclas a la vez. Esperado: no llega texto ni acciones a otras apps; el atajo de emergencia sigue disponible cuando macOS lo entrega.
9. Probar teclado externo o Bluetooth si está disponible. Esperado: los eventos de teclado entregados al event tap se descartan.
10. Probar dos monitores si están disponibles. Esperado: el overlay aparece en todas las pantallas conectadas.
11. Cerrar la app durante modo limpieza. Esperado: el modo limpieza se detiene y el event tap se elimina con el proceso.
12. Suspender o bloquear el Mac durante modo limpieza. Esperado: la app intenta parar de forma limpia con las notificaciones del sistema.
13. Confirmar privacidad. Esperado: no hay APIs de red, telemetría, logs de teclado ni historial de teclas.
14. Activar un campo de contraseña o app que active Secure Event Input. Esperado: el modo limpieza no empieza o se detiene si ya estaba activo.

## Los peros de macOS

- La app se distribuye fuera de App Store y no está sandboxed.
- Accesibilidad es el permiso necesario para este comportamiento con `CGEventTap`.
- Los clics se bloquean en modo fail-closed. No hay botón Stop por ratón durante Cleaning Mode porque el `CGEventTap` no calcula un rectángulo SwiftUI seguro para permitir solo esa zona.
- Kyboardclean usa `cgSessionEventTap` en vez de `cghidEventTap` para limitar el alcance al contexto de sesión de usuario. Algunas teclas de sistema, gestos o rutas de hardware pueden no entregarse como CGEvents bloqueables.
- La máscara incluye el bit raw de `systemDefined` porque CoreGraphics no expone un caso Swift estable para ese evento en todos los SDKs. Es una cobertura best effort para teclas de medios/brillo cuando macOS las entrega por esa ruta.
- Conectar, desconectar o reconfigurar pantallas durante Cleaning Mode detiene la sesión por seguridad. Kyboardclean no intenta reconstruir overlays mientras el EventTap está activo.
- Teclas de medios, brillo, Secure Event Input y algunos gestos están documentados como limitados porque macOS o el hardware pueden gestionarlos fuera de la entrega normal de eventos.
- El límite duro de seguridad es exactamente 30 minutos, también en modo infinito.
- Si la app no está notarizada, Gatekeeper puede mostrar avisos al abrirla en otro Mac.

## Documentación técnica

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): diseño interno, modelo de seguridad fail-closed y responsabilidades.
- [docs/LOCALIZATION_AUDIT.md](docs/LOCALIZATION_AUDIT.md): revisión de la localización.
- [CHANGELOG.md](CHANGELOG.md): historial de cambios.

## Licencia

Kyboardclean se publica bajo licencia MIT. Consulta `LICENSE`. Los sonidos opcionales tienen su propia licencia (ver `Kyboardclean/Resources/Sounds/NOTICE.txt`).
