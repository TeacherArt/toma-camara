# Toma — cámara de Arthur para iPhone

App de cámara nativa (Swift + SwiftUI + AVFoundation + Vision) pensada para iPhone 16.

## Cámara
- Modos **VIDEO · FOTO · G7X · RAW**: se cambian deslizando el dedo sobre la vista previa o sobre la barra de modos.
- Pellizca la vista previa para hacer zoom; toca .5 / 1 / 2 para cambiar de lente.
- **Captura doble** (9:16 × 16:9): foto en vertical y horizontal; el video graba los dos archivos al mismo tiempo.
- **G7X**: flash activado por defecto y receta de color tipo compacta Canon (cielos profundos, piel cálida, nitidez).
- **RAW**: guarda el DNG del sensor junto con la foto en la fototeca; el editor revela la exposición desde el RAW.
- **Video PLANO**: sombras levantadas, color suave y más calidad para editar después.
- **Guía de escena** (ícono de visor): detecta retrato, persona, pareja, grupo, paisaje, atardecer, noche, comida, cuarto o detalle y guía con flechas, nivel y caja objetivo.
- **Poses** (ícono de figura): ideas según cuántas personas hay y qué quieres mostrar, con disparo automático cuando te quedas quieto.

## Editor (después de tomar o desde la galería)
- Fotos y videos de la galería (botón de la esquina inferior izquierda).
- Estilos, ajustes (exposición, contraste, saturación, calidez, sombras, luces), marcos (White, Paper, Specs, Date, Polaroid, Ticket, Sello con o sin borde) y formatos.
- Textos con 14 fuentes, colores, fondo y borde; textos automáticos (ARTHUR, hora, lugar, feeling, fecha, combinación tipo revista, letras en cuentas).
- Stickers: frases tipo acrílico, stickers a color y siluetas de tu gato; borde blanco, acrílico o sin borde.
- Marca Arthur tipo Garmin: silueta + ARTHUR + lugar, hora, feeling o datos de la cámara.

## Cómo se compila (sin Mac)
Cada vez que se sube código a `main`, GitHub Actions compila la app en una Mac en la nube.
El resultado aparece en **Actions** → última ejecución → **Artifacts** → `Toma-ipa`.

## Cómo se instala (desde Windows)
1. Descarga `Toma-ipa` y descomprímelo: dentro está `Toma.ipa`.
2. Conecta el iPhone, arrastra `Toma.ipa` a Sideloadly, escribe tu Apple ID y presiona Start.
3. Con Apple ID gratuito la app dura 7 días; para renovarla, repite el paso 2.
