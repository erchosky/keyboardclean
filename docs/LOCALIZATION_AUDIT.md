# Auditoría de localización

Fecha: 12 de julio de 2026

## Resultado

- Español: 145 claves únicas.
- Inglés: 145 claves únicas.
- Paridad completa; no hay claves duplicadas, valores vacíos ni placeholders incompatibles.
- Todos los textos visibles propios están resueltos mediante `AppText` o `LocalizedStringKey`.
- Los nombres propios `Kyboardclean` y `Secure Event Input` se conservan intencionadamente.

## Cobertura

- Ventana principal: estado, permisos, duración, CTA, errores y ayudas.
- Overlay: preparación, activo, finalización, temporizador y salidas seguras.
- Ajustes: General, Automatización y Actividad.
- Barra de menús: inicio, duración rápida, ventana, Ajustes y salida.
- Atajo global: grabación, restricciones y conflicto.
- Recordatorios: frecuencias, permiso denegado y contenido de notificación.
- Estadísticas e historial: estado vacío, métricas, resultados y confirmación de borrado.
- Menús propios, panel Acerca de e `InfoPlist.strings`.

## Decisiones

- El idioma interno cambia en vivo entre Automático, Español e Inglés.
- Automático usa español o inglés según la localización efectiva y cae a inglés para idiomas no soportados.
- Los elementos estándar de AppKit siguen el idioma del sistema y pueden requerir relanzar la app tras cambiarlo en macOS.
- Las fechas y los formatos numéricos de Actividad usan el locale efectivo seleccionado.
- Los recordatorios existentes se vuelven a programar con el idioma elegido.

## Validación automática

```sh
plutil -lint Kyboardclean/Resources/es.lproj/Localizable.strings
plutil -lint Kyboardclean/Resources/en.lproj/Localizable.strings
```

La comparación ordenada de claves ES/EN y la búsqueda de duplicados no producen diferencias. La suite verifica además paridad, resolución de claves, placeholders y porcentajes literales.
