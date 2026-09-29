# Changelog

## 1.1 - 2026-09-29

### Cambiado

- Proyecto en modo de lenguaje **Swift 6** (concurrencia comprobada por el compilador); compila con Xcode 16 o superior sin errores ni avisos.
- `EventTapManager` más pequeño: los tipos auxiliares pasan a `EventTapSupport.swift` y la detección de los atajos de salida (Control + Option + Command + Escape, Forzar salida y la secuencia de 5 Escape) a `EmergencyExit.swift` como lógica pura. Los cinco avisos al MainActor comparten una sola función. Sin cambios de comportamiento.
- Tests divididos: de un único archivo de 1.783 líneas a 10 archivos por área, más una utilidad compartida (`TestSupport.swift`).
- 7 tests nuevos para los atajos de emergencia (99 en total).
- Los sonidos son opcionales: se cargan desde la carpeta `Sounds` del bundle y no se incluyen en el repositorio, porque su licencia no permite redistribuir los archivos originales. El README explica cómo añadirlos.
- Documentación técnica movida a `docs/`, README con instrucciones de tests y sonidos, y CI en GitHub Actions (build y tests en macOS).

## 1.0

Versión original.
