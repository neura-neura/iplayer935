# iPlayer935

Aplicación nativa Objective-C/ARC y UIKit para iPod touch 5 (`iPod5,1`), armv7, iOS 9.3.5. No usa Swift ni APIs modernas de Files/SMB.

- `IPSMB`: libsmb2 C, autenticación NTLMSSP, SMB2/3, solo listar/stat/abrir O_RDONLY/leer/cerrar. No existen acciones de escritura remota en la interfaz.
- `IPHTTPServer`: listener exclusivo en 127.0.0.1, puerto efímero, HEAD/GET con rangos. Alimenta AVPlayer con bloques de 64 KiB sin persistir la canción entera.
- `IPStore`: perfiles, Keychain por UUID, biblioteca JSON atómica, identidad de canciones por perfil/endpoint/ruta; escaneo recursivo, importación M3U, descargas explícitas por bloques. Metadatos locales accesibles sin red.
- `IPPlayer`: cola de reproducción, AVPlayer, sesión de audio Playback, controles remotos y Now Playing; pausa ante desconexión de auriculares e interrupciones.
- `IPUI`: UIKit de tablas, búsqueda, orden, perfiles, playlists, favoritos, caché; diseño vertical para 320 × 568 puntos.

No se consulta «internet disponible»: cada operación prueba el servidor correspondiente usando las rutas que iOS tenga disponibles, incluidas VPN. La reproducción siempre prefiere la descarga local. Una playlist puede reunir referencias de distintos perfiles; cada cambio de canción abre explícitamente su origen y la pantalla muestra el nombre.

## Evidencia de compatibilidad

Apple documenta que Xcode 14 quitó armv7 y deployment iOS9/10: https://developer.apple.com/documentation/xcode-release-notes/xcode-14-release-notes

Se utiliza SDK iPhoneOS9.3 (mirror Theos), LLVM con backend ARM y enlazador Apple ld que acepta ARM32, deployment 9.3.5, firma ad-hoc mediante ldid para AppSync. La compilación real y las herramientas empleadas se describen en BUILD.md. AppSync no añade APIs ni códecs.

API de reproducción documentada en la guía histórica de Apple: https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/MultimediaPG/UsingAudio/UsingAudio.html

Background audio y Now Playing: https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/MediaPlaybackGuide/Contents/Resources/en.lproj/RefiningTheUserExperience/RefiningTheUserExperience.html

SMB2/3 upstream y licencia LGPL-2.1: https://github.com/sahlberg/libsmb2

Formatos candidatos con AVFoundation en iOS9: MP3, AAC/M4A (incluido ALAC), WAV, AIFF, CAF. La extensión por sí sola no prueba el códec. FLAC, Ogg/Vorbis y Opus usan el puente IPPCMServer con FFmpeg4.4.4 compilado para armv7/iOS9.3.5. Abre el original local o el puente HTTP/SMB y entrega PCM16 por rangos al AVPlayer, con buffers limitados y decodificación fuera de main. WMA permanece incompatible. No se escribe en el servidor.

## Escalabilidad

Para más de 20 000 pistas, el listado y la importación de M3U constituyen una fase rápida independiente de etiquetas. El usuario inicia/reanuda enriquecimiento por tandas, o la app consulta etiquetas de la canción elegida. La tarea es pausable y se cancela al reproducir/descargar. El modelo se actualiza en main; las lecturas SMB, AVAsset y escrituras JSON ocurren en colas separadas. Los snapshots JSON se congelan profundamente antes de encolarlos; al entrar a segundo plano se vacía la cola de persistencia. Los índices de membresía/orden de playlists usan sets y diccionarios para evitar búsquedas cuadráticas.

El enlazador Apple actual perdió el modo Thumb en entradas y punteros a métodos durante la prueba física inicial. La compilación final utiliza `-marm` en todos los fuentes Objective-C/C para evitar esta incompatibilidad. Se comprobó apertura en el iPod con esta estrategia.

## Reproductor visual

La revisión visual se basa en capturas de Música iOS8.4/9 de 2015 (https://www.iclarified.com/48445/this-is-the-new-apple-music-app-in-ios-84-photos). IPNow usa UIKit, portada estática limitada a320px, iconos vectoriales dibujados una sola vez mediante CoreGraphics, tint rosa, texto de título/artista/álbum separado, seek, tiempos, volumen nativo, favorito y cola. No usa blur, WebView ni animaciones continuas. El temporizador de1Hz se invalida al salir; no vuelve a decodificar la portada si no cambia.


## Fundido cruzado (22)

IPCrossfade mantiene preferencias pequeñas en NSUserDefaults y suspensión temporal en memoria. Sus funciones de ganancia usan cos(t·π/2)/sin(t·π/2) para potencia constante, o1−t/t para lineal. La gráfica usa CoreGraphics estático; solo se redibuja al abrir/cambiar ajustes. IPNow ofrece ajustes y pulsación larga con cancelación del toque normal, independiente del modo aleatorio.

IPPlayer retiene un IPAudioTail con los recursos salientes y abre la nueva canción por las rutas existentes. Retira los observadores del AVPlayer saliente y desconecta callbacks PCM para que un EOF antiguo no avance otra vez la cola. La entrante empieza con volumen cero; cuando está lista, una rampa de20Hz ajusta ganancias por AVPlayer.volume y AudioQueueSetParameter(kAudioQueueParam_Volume), sin bucles de mezcla por muestra en Objective-C. La rampa depende del tiempo reproducido por la entrante: un atasco no consume artificialmente toda la rampa. AudioQueue conserva sus tres buffers de4096frames por salida.

La comprobación automática de final se hace a4Hz mientras reproduce, con el efecto automático activo y sin otro solapamiento. No se materializan más metadatos de la cola ni se crea un temporizador por canción. Los temporizadores se invalidan al desactivarse o terminar; la rampa usa modos comunes para seguir al desplazarse por listas. La comprobación automática se detiene cuando no reproduce o al pausar. Solo se conservan dos fuentes audibles; saltos sucesivos terminan la transición previa. La duración se limita al tiempo restante saliente y a la mitad de la duración entrante, para no encadenar solapamientos de canciones muy cortas.

La fuente saliente conserva su enlace local, servidor HTTP o decodificador hasta el final. La entrante usa un directorio de enlaces distinto bajo PlaybackLinks; cada directorio temporal se retira al descartar su salida y el arranque limpia residuos anteriores. No se duplica audio cacheado. Si la entrante falla o no avanza/abre durante12segundos, se detiene y recupera la salida, cola, índice y canción anteriores; se reinstalan observadores/callbacks con nueva generación y se guarda la sesión restaurada. Si la anterior ya terminó, conservarla no puede prolongar su audio. Pausa, seek, cambios de aleatorio y de ajustes terminan el solapamiento; no se reanudan dos fuentes tras restaurar una sesión.
