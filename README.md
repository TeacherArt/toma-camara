# Toma — cámara para iPhone

App de cámara nativa (Swift + SwiftUI + AVFoundation) pensada para iPhone 16.

## Fase 1 (esta versión)

- Foto a 24 MP (o 48 MP con el botón de arriba) con prioridad de calidad.
- Captura doble: con "9:16 × 16:9" activo, cada foto se guarda en vertical y horizontal, y el video graba los dos archivos al mismo tiempo.
- Estilos en vivo: Natural, Film 35, G7X, Suave, Dusk, Harbor, Noche, Relic, B/N.
- Zoom .5 / 1 / 2, flash, temporizador de 3 y 10 s, cámara frontal.
- Revelado: cambias estilo, marco (White, Paper, Specs, Date, Polaroid, Ticket, Sello) y formatos (3:4, 4:5, 9:16, 16:9, 1:1) antes de guardar.

Siguientes fases: guía de encuadre por escena, coach de poses (1 persona, pareja, grupo), plantillas de stories y carruseles.

## Cómo se compila (sin Mac)

Cada vez que se sube código a `main`, GitHub Actions compila la app en una Mac en la nube
(`.github/workflows/build.yml`). El resultado aparece en la pestaña **Actions** → la última
ejecución → **Artifacts** → `Toma-ipa`.

## Cómo se instala en el iPhone (desde Windows)

1. Descarga `Toma-ipa` (es un .zip) y descomprímelo: dentro está `Toma.ipa`.
2. Instala Sideloadly (sideloadly.io). Si te pide iTunes/iCloud, usa los instaladores de la página de Apple, no los de Microsoft Store.
3. Conecta el iPhone por cable, arrastra `Toma.ipa` a Sideloadly, escribe tu Apple ID y presiona Start.
4. En el iPhone: Configuración → General → VPN y administración de dispositivos → confía en tu Apple ID.
5. Si iOS lo pide, activa el Modo de desarrollador: Configuración → Privacidad y seguridad → Modo de desarrollador (el iPhone se reinicia).

Con Apple ID gratuito la app funciona 7 días; para renovarla, repite el paso 3.
