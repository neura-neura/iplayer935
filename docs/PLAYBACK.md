# Sesión y caché automática (compilación16)

La app restaura la última canción y la cola completa en pausa. Al pulsar reproducir abre la fuente disponible y vuelve al segundo guardado. Conserva duplicados y orden de la cola. Las referencias que desaparezcan de la biblioteca se omiten; si desapareció la canción actual se selecciona la siguiente disponible desde el inicio. El volumen continúa siendo el del sistema.

`playback-queue.json` contiene IDs, revisión y posición inicial; se escribe únicamente al cambiar la cola. `playback-position.json` es un archivo pequeño actualizado cada5s mientras suena audio, al pausar y al pasar a segundo plano. Si el proceso termina abruptamente puede perderse hasta el último intervalo de5s. Ambos se escriben atómicamente; si la revisión de posición no coincide, la cola incluye una posición inicial de respaldo. No contienen contraseñas ni URLs de reproducción.

La restauración no inicia conexiones ni audio por sí sola. MP3/M4A usan seek de AVPlayer cuando la fuente está lista. FLAC/Vorbis/Opus posicionan el decodificador antes de llenar los buffers de AudioQueue. Se conserva la alternativa de reabrir y decodificar hasta el punto solicitado: restaurar un punto profundo en estos formatos puede tardar más. Los errores de apertura mantienen el punto pendiente para permitir reintentar.

## Gesto de regreso

Reproduciendo reconoce `UIScreenEdgePanGestureRecognizer` desde el borde izquierdo. Al terminar con avance superior al22% del ancho (mínimo60px), o avance de20px y velocidad superior a450px/s, ejecuta la misma salida que Atrás. Usa el gesto disponible en iOS9, sin tomar capturas ni animaciones de cada cuadro. Un gesto corto conserva el reproductor abierto. El reproductor modal vuelve a la lista sin detener audio.

## Caché automática

Se habilita inicialmente con256MiB independientes del límite de descargas manuales. Dos segundos después de seleccionar una canción prepara primero las tres siguientes distintas y después la actual, en una cola serial. Los cambios de canción cancelan la solicitud vieja. Lee bloques de128KiB con una pausa de100ms para moderar competencia con el audio. Respeta el mismo origen/identidad y las credenciales de Keychain de la app; SMB sigue siendo solo lectura.

El directorio SmartCache y su manifiesto se conservan al cerrar. El identificador de copia incluye ID, identidad de origen, tamaño y mtime. Solo se ofrece el archivo tras leer todos sus bytes y renombrar atómicamente el parcial. Las descargas interrumpidas se descartan, y los restos de parciales/archivos no registrados se limpian al iniciar. Se exige una reserva de64MiB de espacio libre antes de comenzar cada archivo.

Al llenar el límite se reemplazan copias por uso menos reciente. La canción actual y las próximas seleccionadas se protegen durante esa pasada, por lo que puede no caber toda la anticipación si los archivos son grandes. Bajar el límite conserva la canción en uso hasta cambiarla. Vaciar la caché automática conserva la actual y no afecta descargas manuales. Desactivar detiene nuevas lecturas y conserva copias completas.

`localURL` prefiere descarga manual, luego copia automática y finalmente streaming. Si falla un stream y ya hay una copia completa de la canción, se intenta continuar desde la posición conocida con esa copia. Una canción incompleta no puede reproducirse fuera de red; la caché no garantiza continuidad indefinida. Las copias automáticas pueden reemplazarse: para guardar una canción de forma permanente usa Descargar. Si ya existe completa en caché automática se copia localmente a Descargas, sin volver a consultar SMB.

En Descargas → Opciones → Caché automática se consulta espacio, cantidad de canciones y progreso; también permite activar/desactivar, elegir128/256/512MiB y vaciar. Los contadores se consultan solo mientras esa pantalla está visible. La caché de etiquetas permanece independiente.

## Validación

`tests/run-session-cache-tests.sh`: restauración de25154IDs, duplicados, posición, referencias eliminadas, posición de respaldo y escritura pequeña independiente. Caché con SMB simulado: prioridad a siguientes, cuota, LRU, protección actual, uso fuera de red, reinicio, fallos de lectura, cambio de mtime y desactivación.

`tests/run-pcm-player-tests.sh`: inicio en segundo2 antes de producir audio para FLAC/Vorbis/Opus, además del ciclo existente de pausa, buffers, final y stop. `tests/run-store-tests.sh`: selección de copia automática para audio y conversión sin red a descarga manual que sobrevive al vaciado automático. Estas pruebas no sustituyen la comprobación física de gesto, seek de AVPlayer y pérdida de Wi-Fi en el iPod.


## Compatibilidad de copias locales en17

Los archivos de caché conservan el nombre .media para no invalidar descargas existentes. Antes de entregar una copia local al AVPlayer nativo se crea un enlace duro en PlaybackLinks con sufijo .mp3/.m4a/.aac/.wav/.aif/.aiff/.caf según la pista (ALAC se presenta como .m4a). Así AVFoundation9 recibe la indicación de formato. El enlace no duplica los bytes ni cambia la cuota y solo dura mientras se usa esa fuente. Se borra tras retirar el item anterior y se limpian restos al iniciar. FLAC/Vorbis/Opus siguen usando FFmpeg sobre el archivo original de caché.

`tests/run-local-audio-tests.sh` comprueba identidad de inode/bytes, apertura AVFoundation, reapertura y limpieza. La prueba silenciosa incluida en la app informa aceptación de la muestra MP3 con extensión genérica y extensión de audio; no reproduce sonido.


Desde19, la cola también admite IPTrackList: guarda IDs completos y consulta las etiquetas de la canción actual/próximas bajo demanda. El formato persistido de sesión se conserva, por lo que la cola de18 se restaura tras migrar sin materializar todas las canciones.
