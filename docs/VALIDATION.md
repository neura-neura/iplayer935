# Registro de validación

Registro histórico de desarrollo: las referencias a compilaciones son internas y no corresponden a versiones públicas. Las rutas y nombres del entorno privado se han sustituido por ejemplos. Los reportes originales de dispositivo no se distribuyen.

## Comprobado en esta Mac

- Workspace inicial vacío; se creó la aplicación nativa completa y sus scripts.
- Dispositivo USB consultado con libimobiledevice: `ProductType=iPod5,1`, `ProductVersion=9.3.5`.
- El servidor SMB privado de pruebas aceptó una conexión TCP; esto no prueba autenticación ni acceso al recurso.
- Todos los fuentes Objective-C y libsmb2 C se compilan con destino `armv7-apple-ios9.3.5`, SDK iPhoneOS9.3.
- Ejecutable Mach-O `arm_v7`, `LC_VERSION_MIN_IPHONEOS 9.3.5`; dependencias de frameworks del SDK 9.3. Firma ad-hoc ldid con grupo Keychain estable.
- Pruebas de host `tests/run-http-tests.sh`: HTTP GET/HEAD, rangos normales/finales, rechazo de rangos inválidos. Fuente SMB simulada, sin acceso al servidor.
- Pruebas de host `tests/run-store-tests.sh`: primer inicio, persistencia JSON y recarga, escaneo recursivo simulado, exclusión de imágenes, FLAC marcado incompatible, M3U BOM/Unicode/orden/referencias de canciones incompatibles, identidad al editar perfil, rechazo de origen antiguo. No son pruebas de reproducción ni de SMB real.

## Pruebas físicas confirmadas

- El dispositivo conectado es iPod5,1 con iOS9.3.5. La instalación USB se verificó con ideviceinstaller.
- El usuario confirmó apertura correcta de compilación3; se leyó el diagnóstico generado en el iPod. También se ha leído el diagnóstico de compilación4, lo que confirma su apertura y conservación del perfil tras actualizar.
- El usuario introdujo una credencial SMB en la app, guardó el perfil Example y confirmó «Conexión y lectura correctas». El flujo lee la credencial de Keychain; no se exportó ni registró la contraseña.
- Las compilaciones1/2 se cerraban por incompatibilidad ARM/Thumb de punteros generados por el enlazador. Se obtuvieron registros, se corrigió con -marm en todo Objective-C/C y se verificó la apertura posterior. Los registros originales se conservan solo como evidencia local y no se distribuyen.
- No hay apertura remota ni captura por debugserver sin Developer Disk Image. No se montó esa imagen. House Arrest lee Documents/diagnostics.json de esta app con acceso de solo lectura.

## Pendiente de comprobación funcional con credenciales en el iPod

- Reproducción de todos los códecs presentes; las extensiones y cantidades reales ya se obtuvieron durante el escaneo autenticado.
- Contenido real de `All Tracks.m3u`, resolución de sus referencias y orden.
- Reproducción, búsqueda temporal, cambios de canción/origen, controles remotos, segundo plano, auriculares e interrupciones.
- Portadas/metadatos defectuosos y caída del servidor durante reproducción y descargas. El escaneo grande ya terminó en hardware.
- Descarga individual/múltiple/playlist, reproducción fuera de red, límite de caché, borrado y persistencia tras actualizar.
- Acceso mediante ZeroTier/VPN y perfiles adicionales.

La extensión no certifica el códec. FLAC/Ogg/Opus/WMA se muestran como incompatibles en iOS9 con esta versión. Los errores de metadatos no impiden conservar una entrada basada en el nombre del archivo. Las consultas de metadatos pueden transferir partes del audio por HTTP local; no crean automáticamente una descarga sin conexión.

Las capturas de pantalla y debugserver no están disponibles sin una Developer Disk Image. No se montó ninguna imagen ni se actualizó/restauró el iPod. El diagnóstico opcional `scripts/device-report.sh` lee exclusivamente `diagnostics.json` de Documents de esta app mediante House Arrest; contiene versión, fecha, cantidades y extensiones, nunca credenciales. Desde la compilación6 incluye hasta ocho rutas de ejemplo para depurar la importación M3U.

## Ajuste para colección real grande

El usuario informó más de 20 000 canciones durante el primer escaneo real de compilación3. Se cambia la indexación de compilación4 para publicar rutas y M3U sin esperar etiquetas; la lectura de metadatos pasa a tarea separada por tandas, pausable y con reanudación. La mejora pasó pruebas de host y compilación; la compilación4 está instalada y ya generó diagnóstico de apertura. Está pendiente terminar el primer listado real.

## Primer escaneo real completado (compilación4)

Diagnóstico del iPod: 25 154 archivos de audio: 24 391 MP3, 258 M4A, 237 WAV, 261 FLAC, 5 Ogg y 2 Opus. Los 268 FLAC/Ogg/Opus se marcan incompatibles con el decodificador nativo. Se detectó e importó una M3U con 28 390 referencias no resueltas y cero canciones enlazadas; por lo tanto aún no se considera correcta la importación de All Tracks. Se está investigando su formato real de rutas.

## Reproducción real

El usuario confirmó en compilación4 que se escucha música desde SMB y funcionan pausa y avance. Esto verifica lectura del audio por el puente HTTP local y AVPlayer en el iPod. No confirma todavía segundo plano, seek, descargas ni reproducción sin conexión. La revisión visual posterior se entrega en compilación6; pendiente su valoración física.

## Revisión visual y diagnóstico de compilación6

La compilación6 se abrió en hardware y reimportó M3U. El reporte confirma que las referencias usan `/music/Example/…`, un prefijo diferente del root SMB configurado `media/data/music/Example`. Se prepara la corrección de este alias. Se obtuvo una captura desde la propia vista del reproductor: portada real, título, artista, origen, controles y volumen caben completos. La captura inicial precede a la carga de duración, por lo que no verifica seek. No sustituye las pruebas funcionales.

El diseño usa UIKit, iconos dibujados una vez, portada reducida y actualización del progreso a 1Hz solo mientras la pantalla está visible. Referencia visual: https://www.iclarified.com/48445/this-is-the-new-apple-music-app-in-ios-84-photos (2015).

## Compilación7: M3U y rendimiento

El usuario confirmó que el nuevo reproductor se ve completo y funciona, pero percibe tirones. Se evita recargar desde disco la portada de pantalla bloqueada cada segundo; se conserva hasta cambiar canción/portada. Las vistas de biblioteca ocultas posponen filtrado/ordenación hasta mostrarse; volver sin cambios reutiliza filas. Las playlists se reconstruyen en orden lineal conservando referencias duplicadas. No se dispone de medición de FPS ni de tiempos en hardware; la mejora percibida queda pendiente.

La resolución M3U admite el alias absoluto observado solo cuando su ruta restante coincide exactamente con el índice del perfil. Pruebas de host verifican alias con Unicode, orden y duplicados, rechazan rutas ajenas y traversal, y reimportan sin volver a escanear. La cantidad final enlazada debe comprobarse en el iPod.

## Resultado físico de compilación7 y cambios de compilación8

El usuario confirmó una mejora grande de fluidez y 27 856 referencias M3U enlazadas, con534 pendientes. El reporte leído por USB confirma estas cantidades. Al marcar favoritos nota un tirón: se reemplaza el guardado completo por un archivo independiente y notificación específica que evita reordenar toda la biblioteca. Las pruebas de host verifican guardar/cambiar rápidamente favoritos y recargar junto con un guardado normal.

Compilación8 añade FFmpeg4.4.4 mínimo LGPL para FLAC, Vorbis y Opus, manteniendo AVPlayer nativo para los demás formatos. La compilación armv7 real está disponible. Las verificaciones silenciosas con muestras sintéticas en hardware se informan en codecChecks; escuchar canciones reales y seek siguen requiriendo comprobación física.

Compilación8 construida e instalada por USB con éxito. Prueba host del puente PCM: salida WAV completa y longitud declarada, HEAD y rango de bytes a los6 segundos coinciden exactamente con el audio completo para FLAC, Vorbis y Opus de muestras sintéticas de7 segundos. La decodificación FFmpeg nativa pasó para los tres códecs. Pendiente abrir la app8 y escuchar archivos SMB reales. Vorbis/Opus reabren y decodifican hasta el punto solicitado; los saltos profundos pueden tardar.

## Compilación9: cambio de pista y diagnóstico de AVPlayer

El usuario notificó fallo al abrir un FLAC en compilación8. El diagnóstico del iPod confirma decodificación PCM correcta para las muestras FLAC/Vorbis/Opus, pero esa prueba no verificaba AVPlayer. Se añadió consulta de AVURLAsset en el iPod y captura de códigos de error de AVPlayer con estado del puente PCM, sin URLs ni credenciales. La prueba AVFoundation de host acepta WAV remoto y local con duración7s y una pista de audio.

Se corrigió el cambio de pista: antes de cerrar el servidor anterior se retira el observador y se elimina el antiguo AVPlayerItem, evitando atribuir errores de esa fuente cerrada a la nueva pista. Compilación9 instalada por USB; pendiente reintento físico del FLAC.

La compilación9 abrió físicamente. El diagnóstico confirma que AVURLAsset en iOS9 declara playable=true para las muestras FLAC, Vorbis y Opus decodificadas y servidas por HTTP local. Esto no confirma aún reproducción del FLAC real que falló.

## FLAC real: tiempo de espera y compilación10

El usuario reportó NSURLErrorDomain -1001. El diagnóstico confirma FLAC estéreo44.1kHz, duración234.55s, apertura/decodificación correcta y fallo EINVAL durante una solicitud de búsqueda posterior. Se reemplaza la entrada de FFmpeg vía HTTP encadenado por callbacks AVIO que leen SMB directamente; la hipótesis es bloqueo entre conexiones del servidor HTTP de entrada durante seeks. La salida PCM hacia AVPlayer mantiene HTTP local. Hasta verificar hardware no se considera resuelto.

Compilación10 supera las pruebas host de AVIO con una fuente SMB simulada, incluidos rangos exactos y lectura cerca del final de FLAC sintético de240 segundos. FFmpeg4.4 fallaba buscando binariamente en FLAC sin índice; se evita esa ruta y se reabre/decodifica hasta el punto solicitado. También se usa esa alternativa si una búsqueda indexada devuelve error. Esto conserva memoria limitada, pero añade latencia para archivos largos sin índice. Se corrige además el doble descuento del pre-skip de Opus (delay e initial_padding eran el mismo dato).


## Compilación11: salida PCM directa

El usuario reportó NSURLErrorDomain -1 (-1005) en compilación10. El diagnóstico físico (registro local excluido de la distribución) muestra audio inicial decodificado, seguido por solicitudes de AVPlayer al final del WAV que reciben solo cabeceras. Se sustituye la salida WAV por HTTP por AudioQueue para FLAC/Vorbis/Opus; se conserva el lector SMB directo y el decodificador acotado. La interfaz y controles remotos consultan ambas rutas mediante propiedades comunes. La comprobación silenciosa de códecs usa la API directa de decodificación. La compilación11 se construyó para ARMv7 y se instaló por USB. Pasan las pruebas de decodificación/rangos, lectura y seek cerca del final de un FLAC de240s con SMB simulado, y simulación silenciosa de AudioQueue para los tres formatos (inicio, callback durante pausa, reanudación, drenado completo y stop). La simulación no valida el dispositivo de audio físico. Pendiente escuchar el FLAC real en el iPod.


## Confirmación física de FLAC y compilación12

El usuario confirmó que el FLAC real se escucha en compilación11. Observó ausencia de metadatos, aunque no sabe si ese archivo contiene etiquetas. La ruta AudioQueue todavía no trasladaba las etiquetas del decodificador a la biblioteca. Compilación12 extrae título, artista, álbum, género, número de pista y portada adjunta desde el formato o stream de FFmpeg al abrirlo. Reutiliza la misma apertura SMB. Reduce portada a320px en segundo plano y persiste un mapa pequeño independiente, sin guardar toda la biblioteca por canción. Las etiquetas ausentes no sustituyen datos existentes.

Pruebas host: FLAC sintético con título/artista/álbum UTF-8, pista3/10 y PNG adjunto; decodificación y AudioQueue simulada de los tres formatos; aplicación y recarga del mapa de metadatos sin perder favoritos. Pendiente valoración física de los metadatos reales.

El usuario confirmó en hardware que los metadatos aparecen con compilación12. Quedan confirmados por el usuario la reproducción de FLAC real y la visualización de etiquetas; no se infiere de ello validación física de Ogg/Opus, seek profundo o reproducción sin conexión.


## Compilación13: navegación y biblioteca automática

Minirreproductor persistente sobre pestañas; abrir canciones no presenta automáticamente el reproductor completo. La barra abre una navegación modal con Atrás. La biblioteca conserva el botón de navegación anterior. Se comparte estado de reproducción entre barra, pantalla completa y controles remotos.

Filtrado/orden se trasladan a `IPLibraryIndex`: copia de documentos por ID, normalización una vez por cambio, cola serial y caché de ocho consultas. La consulta inicial por perfil se prepara al iniciar. Se evitan consultas al sistema de archivos para cada celda. Las actualizaciones de etiquetas se agrupan; las filas visibles se refrescan y la reordenación preserva una canción ancla, posponiéndose al terminar de desplazar. Fechas nuevas se toman de SMB mtime, con fecha de incorporación como alternativa.

La indexación automática prioriza filas visibles y consulta ID3v2.2/2.3/2.4 o ID3v1 para MP3, acotando la lectura a1MiB (128KiB durante reproducción) y reutilizando conexión SMB con timeout5s. Otros formatos se aplazan mientras suena audio. Se reducen portadas en background y se actualiza el mapa persistente cada5s o al pasar a segundo plano. La exploración de cambios remotos es automática con intervalo mínimo15min y no bloquea mostrar la biblioteca guardada. No hay notificaciones SMB push.

Pruebas host:25154 documentos, orden reciente, búsqueda sin acentos, conservación de duplicados y orden M3U, invalidación por actualización de etiquetas, parsing ID3 UTF8/número de pista y entradas truncadas, persistencia de etiquetas/favoritos e indexación MP3 automática. Tiempo de prueba índice/orden en Mac0.101s; este número no representa rendimiento del iPod. Compilación ARMv7/iOS9 pasa; pendiente comprobar distribución y fluidez física.


## Compilación14: ID3, estado persistente y barra de Música

El usuario confirmó físicamente en13 que la apertura de Example mejoró, la selección conserva la lista, la barra abre el reproductor y Atrás funciona. Reportó MP3 sin etiquetas, tirones durante el cacheado y controles poco apropiados.

Se sustituyó la lectura inicial limitada de MP3 por recorrido ID3 por rangos. Las portadas mayores de4MiB se saltan sin impedir leer texto posterior; se leen cabeceras extendidas, textos Latin1/UTF16/UTF16BE/UTF8, agrupación/DLI, compresión zlib, unsynchronisation, ID3v1.1 y etiquetas v2.4 al final. Las lecturas fallidas quedan pendientes con espera, sin marcarse completas. MP3 incompletos de13 se repasan una vez; los terminados14, también sin etiquetas, se conservan tras reiniciar. Se amplió el intervalo de reordenación y redujo el ritmo del lector mientras reproduce.

Opciones → Estado de la caché de etiquetas muestra avance guardado, con/sin etiquetas, pendientes, fallos y archivo activo. Pausa/reanudación se conserva entre aperturas. Los contadores se calculan cada2s solo al consultar esa pantalla. La barra de48px usa iconos vectoriales precalculados y progreso fino, basada en capturas de Música de2015: https://www.imore.com/how-use-mini-player-apples-new-music-app .

Pruebas host aprobadas: matriz ID3 indicada, portada de5MiB seguida de título con menos de64KiB leídos, fallo de lectura y truncamiento, persistencia de MP3 sin etiquetas sin ninguna lectura SMB al reabrir, pausa persistente, biblioteca de25154 documentos y suite Store. Construcción ARMv7/iOS9 e instalación USB de14 completadas. Pendiente valoración física de esta compilación; las pruebas sintéticas no garantizan etiquetas válidas en cada MP3 real.


## Compilación15: portadas antiguas omitidas

El usuario confirmó físicamente que14 terminó el cacheado, pausa/continuar funcionaron y la barra inferior le parece adecuada. Reportó portada ausente en un MP3 con etiquetas aunque el texto sí aparece. Autorizó lectura del servidor para analizarlo.

Se leyó únicamente la cabecera ID3 del MP3 original: v2.3, APIC sin flags, MIME image/jpg, imagen JPEG de804503bytes y1500×1500. El lector actual extrae título, artista e imagen; ImageIO de host acepta la imagen y genera miniatura320px. No se modificó el servidor ni se copió el audio completo. La cabecera real se mantiene en build, excluida del paquete fuente.

Se encontró una exclusión en IPNeedsTags: MP3 con metadataLoaded, artista y álbum de versiones anteriores se consideraban terminados sin comprobar portada. Se añade revisión persistente de portadas pendientes, independiente de las etiquetas. Solo se consultan MP3 sin portada que no se hayan revisado con15; se omiten portadas existentes y archivos que14 registró sin etiquetas. Se limita a4MiB la acumulación de portadas por lote antes de entregarlo al reductor. El diagnóstico incluye presencia de portada guardada y marcadores del tema actual, sin URL ni credenciales.

Pruebas host aprobadas: recuperación de JPEG APIC para modelos con texto cacheado13 y14, conservación de artista/álbum, persistencia de imagen tras reinicio sin lecturas SMB adicionales; caché de archivos vacíos y pausa; matriz ID3 e índice de25154 documentos. Construcción ARMv7/iOS9 e instalación USB15 completadas. Pendiente confirmar la portada en el iPod: la extracción y miniatura de host no prueban la pantalla física.


El usuario confirmó físicamente que la portada del MP3 de prueba aparece en compilación15. Queda validada la recuperación de ese MP3 real en el iPod.


## Compilación16: regreso por gesto, sesión y anticipación de audio

Se añade gesto de borde izquierdo en Reproduciendo, con umbral de distancia/velocidad y la misma salida que Atrás. Canción, orden completo de cola con duplicados y posición persisten en dos JSON atómicos, con respaldo de posición inicial y revisión compartida. Al abrir se restaura en pausa. AVPlayer espera a estar listo para posicionarse; AudioQueue recibe el tiempo inicial antes de producir buffers.

IPSmartCache anticipa tres canciones y después la actual, con cuota inicial256MiB separada de descargas manuales, lectura serial y moderada, limpieza de parciales, protección de la actual y reemplazo por uso reciente. La fuente local se selecciona antes del servidor. La promoción a descarga manual usa copia local. El panel de Descargas permite consultar/ajustar la caché. Las descargas completas y el manifiesto persisten; las incompletas no se ofrecen fuera de red. Los diagnósticos añaden cantidad/posición de cola y estado de caché sin credenciales.

Pruebas host aprobadas: sesión de25154IDs, duplicados/posición/referencias desaparecidas, respaldo al faltar el archivo de posición, escrituras pequeñas; cuota/LRU/protección/orden de anticipación/offline/reinicio/fallo parcial/mtime/desactivación con SMB simulado; selección automática y promoción a manual sin nuevas lecturas SMB; inicio PCM en segundo2 para FLAC/Vorbis/Opus y ciclo de AudioQueue. Construcción ARMv7/iOS9 e instalación USB16 completadas. Pendientes confirmación física del gesto, restauración y uso de la siguiente canción sin Wi-Fi.


## Compilación17: extensión de archivos locales para AVFoundation

El usuario confirmó en16 el gesto de regreso y la restauración de canción/tiempo. Reproducir tras restaurar o pasar a una canción cacheada sin Wi-Fi falló con AVFoundationErrorDomain -11828 / NSOSStatusErrorDomain -12847. El reporte físico confirma esos códigos y8copias automáticas completas (81853215bytes), con cola de25154IDs. No se considera todavía validada físicamente la continuación de audio o la cola restaurada.

Las descargas manuales y automáticas se almacenan con sufijo .media. El camino nativo entregaba ese nombre directamente a AVPlayer, perdiendo la indicación de formato que sí tiene el HTTP remoto. Se añade IPLocalAudioFile, que crea un enlace duro dentro del contenedor con la extensión nativa correspondiente antes de abrir AVPlayer. Conserva los bytes/caché existentes y no descarga ni duplica audio. Al cambiar de pista se retira el AVPlayerItem anterior y se borra solo el enlace. Se limpian enlaces de procesos anteriores al iniciar. La ruta FFmpeg permanece directa.

Prueba host aprobada: MP3 sintético guardado como .media, enlace .mp3 con mismo inode/tamaño, AVFoundation lo declara reproducible con una pista de audio, reapertura y limpieza sin borrar el original. La app añade una prueba silenciosa, una vez por compilación, de AVURLAsset sobre el mismo MP3 sintético con sufijos .media y .mp3 y publica ambos resultados en codecChecks.nativeCachedMP3; esto no produce audio ni sustituye la prueba de escucha.

Construcción ARMv7/iOS9 e instalación USB17 completadas. Pendiente reintento físico de restauración y siguiente canción cacheada sin Wi-Fi.


El usuario confirmó físicamente que17 reproduce tanto la canción restaurada desde su punto guardado como las siguientes cacheadas con Wi-Fi apagado. La corrección de extensión local queda validada en ese recorrido.

## Compilación18: carga inicial fuera del hilo de interfaz

El usuario reportó varios segundos de pantalla blanca antes de Servidores. El arranque leía y deserializaba library.json y decoded-metadata.json, combinaba todas las etiquetas/favoritos, recorría descargas, preparaba el índice para todos los perfiles y restauraba la cola antes de devolver control a UIKit.

El singleton inicia con un modelo ligero y startup-profiles.json. Después de presentar la ventana, un cargador serializado por estado inicia la lectura/combinación de toda la biblioteca en una cola de fondo. La entrega del modelo y las notificaciones ocurren en main; conserva los objetos de perfil ya abiertos desde Servidores. Las ediciones y los guardados completos se bloquean hasta completar la entrega, para evitar sobrescribir la biblioteca con los arrays vacíos de arranque. La copia pequeña de perfiles se mantiene en cada guardado y se genera automáticamente durante la primera migración. La primera apertura sin esa copia muestra un mensaje de carga; las siguientes muestran los servidores sin deserializar las canciones.

Se elimina el precalentamiento completo de índices antes de mostrar la ventana. El índice se crea al consultar listas. La restauración de la sesión espera la carga local, sin iniciar audio, y el diagnóstico/prueba silenciosa de códecs se difieren. La caché de etiquetas existente se lee del disco, sin reindexado remoto por esta actualización.

Pruebas host Store aprobadas con25154 canciones: constructor ligero sin canciones, copia de perfiles inmediata (0.053ms en Mac host, no representa tiempo de iPod), llamada de carga no bloqueante y coalescida, entrega en main, conservación de identidad del perfil, combinación de etiquetas y favoritos, caché automática disponible, protección ante guardado previo a carga y migración sin startup-profiles.json. Las pruebas previas de metadatos, portadas y promoción de caché a descarga manual también pasan. Construcción ARMv7/iOS9 e instalación USB18 completadas. Pendiente medir la mejora percibida en apertura física desde proceso cerrado; las pruebas host no miden el arranque de UIKit en el iPod.


El usuario confirmó que18 abre más rápido, pero todavía esperaba a que aparecieran servidores y canciones. Autorizó inicializar Git en ese estado antes de optimizar. Se creó `build18-restorable` (`61fa2b7`) con el IPA y fuentes completas, y la rama `optimize-sqlite-library`.

## Compilación19: SQLite, lectura por bloques y cola bajo demanda

Se migra el estado anterior a SQLite en una transacción, manteniendo los JSON originales. Servidores lee su copia pequeña; la apertura posterior de la biblioteca carga IDs y ajustes, sin combinar todos los metadatos. Las consultas usan índices persistentes y páginas de200 registros, cuyos metadatos se deserializan fuera de main. La cola y restauración mantienen todos los IDs con consulta bajo demanda. Se elimina el recorrido completo del reproductor para localizar la canción actual y el diagnóstico usa agregados SQL.

Favoritos/etiquetas actualizan registros individuales y los guardados consideran solo modelos cambiados. Las lecturas de pantalla esperan las escrituras anteriores. Los pendientes de etiquetas se consultan por índice en tandas de256. Las revisiones remotas leen registros previos fuera de main, mantienen modelos consultados y no reescriben todas las canciones si no cambiaron. La ruta JSON se conserva como alternativa si SQLite no puede activarse.

Pruebas host aprobadas de base de datos, Store y sesión/caché. Con25154 canciones: migración1.152s y consulta del primer bloque con metadatos0.005s en Mac; estas cifras no representan rendimiento de iPod. Se verificó el plan de título mediante EXPLAIN QUERY PLAN, con índice persistente y sin orden temporal. También se verifican paginación, órdenes, búsqueda, filtros, duplicados, cola/restauración sin materializar todos los modelos, cambios incrementales, revisión sin cambios y rollback. Construcción ARMv7/iOS9 e instalación USB19 completadas. Pendiente valoración física de primera conversión, reapertura, desplazamiento, búsqueda/orden y reproducción con cola completa.

Verificación adicional de19 aprobada: la apertura SQLite no materializa etiquetas antes de consultar canciones; cambiar un favorito y guardar no modifica library.json, decoded-metadata.json ni favorites.json del respaldo; al reabrir prevalece el favorito actualizado de SQLite. Una base deliberadamente inválida en una fixture conserva la biblioteca JSON y permite consultar sus canciones con la ruta alternativa.


## Compilación20: biblioteca disponible durante la preparación

El usuario reportó que19 seguía cargando después de esperar un buen rato. No se considera validada su primera migración física. Las fixtures anteriores no reproducían IDs desordenados y títulos multilingües de una biblioteca real. Se elimina la espera obligatoria de SQLite antes de entregar la biblioteca JSON y se permite buscar/reproducir mientras se convierte; el índice anterior se reutiliza.

La conversión usa tandas de256, prioridad baja, índices al final, caché acotada de normalización y liberación de objetos temporales dentro de cada comparación Unicode. No duplica todos los diccionarios de metadatos para la instantánea inicial. Un marcador persistente oculta bases parciales. El panel Preparación de la biblioteca muestra etapas, contador, errores y pausa/reintento. Los cambios hechos durante la preparación se reconcilian antes de activar SQLite; hasta entonces siguen persistiendo por la ruta JSON. Se solicita pausa al pasar a segundo plano. Reabrir antes de terminar puede repetir la preparación local; no requiere descargar etiquetas o audio de nuevo.

Pruebas host aprobadas: acceso a25154 canciones y primera página antes de activar SQLite, pausa/continuación, favoritos cambiados durante la conversión, activación sin materializar toda la colección; cancelación/reintento de importación, marcador invisible hasta finalizar,8192 IDs desordenados con títulos multilingües y paridad de comparación natural; pruebas previas de persistencia, paginación, sesión y caché de audio. Importación directa25154 registros0.411s en Mac y8192 multilingües0.290s; no son mediciones del iPod. Compilación ARMv7/iOS9 e instalación USB20 completadas. Pendiente confirmar en el dispositivo que Example se puede usar mientras avanza la preparación y que esta llega al final.


El usuario confirmó físicamente que20 permite entrar en Example y usar la biblioteca durante la preparación.

## Compilación21: navegación, selección y reproducción aleatoria

Atrás se define en el elemento de navegación padre y queda solo a la izquierda. Opciones usa un icono vectorial de puntos a la derecha; la selección de canciones usa otro icono con marcas/líneas. El «+» queda en Servidores y Playlists. Selección tiene contador, Hecho y menú contextual para reproducir, descargar, agregar a playlist y marcar/quitar favoritos. Conserva IDs seleccionados al paginar/recargar; seleccionar todas se limita explícitamente a las canciones cargadas. Favoritos por lote actualiza modelos e índice una vez, persiste un lote y emite una notificación.

IPShuffleQueue permuta índices sobre la cola original sin materializar todas las etiquetas. Fisher–Yates con arc4random_uniform mezcla las posiciones restantes y fija al inicio la ocurrencia actual. Activar/desactivar no vuelve a abrir el audio; desactivar mapea la ocurrencia actual al orden original. Anterior/siguiente y precarga automática recorren la cola efectiva. La sesión persiste IDs originales y permutación junto con la cola efectiva, y reconstruye el orden original tras reinicio, incluyendo duplicados y filtrado de canciones eliminadas.

Pruebas host aprobadas de sesión/caché, SQLite y Store: permutaciones completas, canción actual fija, duplicados, colas vacía y de una canción, restauración de orden/posición, canciones desaparecidas, cola SQLite de25154 posiciones sin materializar metadatos durante mezcla/guardado/restauración, favoritos por lote en SQLite y ruta JSON, deduplicación y una notificación. Compilación ARMv7/iOS9 e instalación USB21 completadas. Pendiente validación física de iconos, navegación, acciones múltiples y alternancia aleatoria durante reproducción.


El 21 de octubre de2026, el usuario confirmó físicamente que la compilación21 funciona adecuadamente en el recorrido solicitado: Atrás e iconos, selección múltiple y una acción desde Opciones, activación del modo aleatorio, avance de canciones y desactivación conservando el audio y recuperando el orden original. Esta confirmación no incluye explícitamente restaurar una sesión aleatoria después de cerrar completamente la app; ese caso sigue cubierto por pruebas host.


## Compilación22: fundido cruzado configurable

Se implementa el conjunto de funciones de la captura proporcionada: activación, curva lineal/potencia constante, duración1–10segundos (4por defecto), aplicación independiente al cambio manual y al final natural, y control temporal por pulsación larga en aleatorio. Se ubica en el icono de ajustes de Reproduciendo y conserva el estilo UIKit existente. El efecto arranca desactivado y la suspensión de sesión no persiste entre procesos.

IPPlayer conserva la salida anterior mientras abre la siguiente; después aplica la rampa por volumen nativo a AVPlayer y/o AudioQueue. Dos salidas PCM pueden convivir con buffers acotados. Solo se usa una salida fuera de las transiciones. Los cambios rápidos, pausa, seek y cambios de ajustes/aleatorio descartan la salida anterior. Una entrante fallida o sin progreso durante12segundos restaura la anterior, su cola y su posición efectiva. La duración se ajusta al tiempo disponible y la rampa sigue el tiempo de audio entrante, con recuperación ante atasco. La precarga y el orden aleatorio siguen usando la cola efectiva.

Pruebas host aprobadas: Tests/run-crossfade-tests.sh comprueba preferencias independientes, persistencia, suspensión temporal, duración acotada y ganancias monotónicas con endpoints correctos y energía constante; Tests/run-pcm-player-tests.sh verifica FLAC/Vorbis/Opus con AudioToolbox simulado, inicio mudo, cambios de ganancia nativa y dos salidas independientes, además de pausa/reanudación/EOF/limpieza y restauración por tiempo. También pasan sesión/aleatorio/caché automática y enlaces de MP3 local. La compilación ARMv7/iOS9 y la instalación USB22 completaron correctamente.

Pendiente comprobar físicamente audición y fluidez de MP3→MP3, PCM→PCM y cambios de motor, avance natural, manual, cambios rápidos, pausa/seek durante solapamiento, fallo de red y pulsación larga sin alterar aleatorio. Las pruebas host de dos salidas usan una AudioQueue simulada; no miden mezcla acústica, carga de CPU o comportamiento de AVFoundation en el iPod. No se considera validada físicamente la función hasta recibir esa comprobación.


El usuario confirmó que el fundido de22 funciona en las pruebas realizadas, salvo que no pudo comprobar una transición con FLAC porque adelantar dentro de ese formato detenía la canción. Esto no valida todavía transiciones físicas que incluyan FLAC ni todos los casos excepcionales enumerados arriba.

## Compilación23: búsqueda y reanudación FLAC

Se reprodujo en host un fallo de saltos consecutivos: el segundo salto capturaba el estado temporal detenido del primero y perdía la intención de reanudar. Se separa la intención de reproducción del estado real de AudioQueue, se descartan trabajos obsoletos y se respeta pausa/play/stop mientras se busca. La interfaz muestra «Buscando…» y evita iniciar un fundido automático durante esa operación. El diagnóstico físico disponible no identifica la causa exacta del incidente del usuario; la confirmación en su FLAC sigue pendiente.

Se añade búsqueda nativa FLAC por un máximo de12 sondeos de bytes y decodificación hasta la muestra solicitada, sin llamar a la búsqueda binaria por timestamps de FFmpeg que fallaba anteriormente. El posicionamiento usa el offset real del parser. Se conserva la ruta secuencial como respaldo y para el prefijo corto; las lecturas y buffers permanecen acotados.

Pruebas host aprobadas: comparación byte a byte de4096 muestras en múltiples saltos hacia delante/atrás, entrada local y SMB simulada, FLAC de240segundos, FLAC etiquetado y estéreo24-bit de compresión variable. Los saltos profundos del archivo de240segundos leyeron64–96KiB por SMB simulado frente a unos4MiB de archivo. No son mediciones de red ni tiempos del iPod. Pasan también las regresiones PCM, preferencias/ganancias del fundido y AudioQueue simulada para FLAC/Vorbis/Opus, incluyendo dos salidas, saltos consecutivos y pausa/play/stop durante búsqueda.

Compilación ARMv7/iOS9 e instalación USB23 completadas. Pendiente comprobar en el iPod el FLAC que fallaba, saltos al centro/final/atrás, saltos consecutivos y Siguiente con fundido activo.

El usuario aclaró que el fallo de22 ocurría al mover la barra de tiempo dentro del FLAC. En23 confirmó que todo funcionó en el recorrido solicitado en el iPod: saltos al centro, cerca del final y hacia atrás, dos saltos seguidos y Siguiente con el fundido activo. La corrección queda validada físicamente para ese recorrido y archivo; no implica haber probado todos los FLAC ni los escenarios excepcionales de red.


## Compilación24: icono y crédito

Se incorpora la propuesta de icono aprobada, conservando el original en Resources/IconArtwork y empaquetando únicamente PNG pequeños en el bundle para icono y Acerca de. Info.plist declara CFBundleIcons y no aplica brillo adicional. La pantalla Acerca de se crea solo al abrirla desde Servidores → Opciones; muestra versión de bundle y un crédito discreto con enlace solo sobre «neura-neura». El destino previsto es https://github.com/neura-neura/iplayer935, configurable en IPRepositoryURL. No se ha creado ni publicado el repositorio. No se modifica el refresco automático/manual existente.

Compilación ARMv7/iOS9 completada; comprobados versión24, enlace y presencia de PNG de iconos en el IPA, dimensiones120×120 sin transparencia para iPod y git diff --check. Pendiente confirmar visualmente el icono del inicio y Servidores → Opciones → Acerca de en el iPod.


El usuario confirmó físicamente que la compilación24 funciona correctamente en el recorrido solicitado: icono, versión y crédito en Acerca de.

## Compilación25: idiomas automáticos

Se añaden320 entradas por catálogo en inglés, español y chino simplificado, con selección por idioma principal del sistema y alternativa inglesa para los demás. Incluye mensajes propios de las capas SMB/PCM/ID3, preparación y progreso, navegación, opciones, reproductor, caché, descargas y accesibilidad. Conserva datos de canciones, nombres, identificadores, protocolos y la caché existente. Los textos de ayuda largos ajustan su altura; el motivo persistente de formato incompatible se traduce al mostrarlo.

Pruebas aprobadas de catálogos y runtime: argumentos printf compatibles, ausencia de claves faltantes entre idiomas, enlace del autor, selección regional española, ambas variantes chinas con interfaz simplificada, idioma principal no compatible aunque el segundo sea español, alternativa inglesa ante una entrada ausente y consultas concurrentes. También pasan regresiones de Store, SQLite/paginación/orden multilingüe, ID3/índice y reproducción PCM simulada, incluyendo búsquedas y dos salidas.

Compilación ARMv7/iOS9 e instalación USB25 completadas; recursos de los tres catálogos verificados dentro del IPA25. Pendiente revisión física del idioma y ajuste visual en el iPod; las pruebas host no comprueban el dibujo de UIKit en iOS9.


El usuario informó que la compilación25 nunca cambió el idioma siguiendo el recorrido indicado. Sus pruebas host no validaron esa detección en iOS9. No se considera aprobada físicamente.

## Compilación26: selector de idioma

Se añade Servidores → Opciones → Idioma, con sistema/español/inglés/chino simplificado, marca de selección y preferencia persistente propia. Reemplaza la selección única de NSBundle por carga explícita de catálogos y una instantánea inmutable atómica. Los textos se resuelven en memoria; la repetición de una opción no emite notificación ni reconstruye pantallas. Volver a primer plano comprueba si cambió el modo sistema. El diagnóstico registra preferencia, idioma efectivo e idiomas preferidos para distinguir selección y carga en el dispositivo. La causa exacta del fallo físico de25 sigue sin reproducirse en host.

El cambio efectivo reconstruye las raíces de interfaz y conserva el selector abierto, sin llamar a carga de biblioteca, restauración de sesión ni métodos de control del audio. Conserva los objetos Store/Player y sus colas/cachés. Los recorridos de navegación previos se reinician.

Pruebas aprobadas:323 entradas coherentes por idioma y formatos printf; selección explícita inmediata de los tres idiomas; retorno al sistema; misma opción sin evento; alternativa inglesa; preferencia inválida; consultas concurrentes durante cambios; guardado de chino y restauración en otro proceso con sistema inglés. Compilación ARMv7/iOS9 e instalación USB26 completadas; recursos del IPA verificados. Pendiente comprobar visualmente el selector y continuidad del audio en el iPod.


El usuario confirmó que26 cambia el idioma del resto de la interfaz y funciona en el recorrido solicitado, pero la barra inferior siguió en español y mostró «Marcadores» para playlists. Los elementos UITabBarSystemItem conservaron sus títulos de sistema en iOS9 pese a asignar title después de inicializarlos.

## Compilación27: títulos de pestañas propios

Las cuatro pestañas usan initWithTitle:image:tag: con títulos de los catálogos de la app y etiquetas de accesibilidad explícitas. Se elimina la dependencia de UITabBarSystemItem para sus nombres. Playlists usa un icono de lista musical; servidores, favoritos y descargas usan símbolos propios. Los cuatro iconos de26puntos se rasterizan una sola vez, se conservan en memoria y usan el tinte nativo de la barra. Cambiar idioma reutiliza las mismas imágenes. No se modifican reproducción, biblioteca, colas ni catálogos.

Compilación ARMv7/iOS9 e instalación USB27 completadas. Verificados los catálogos y versión dentro del IPA, coherencia de traducciones y git diff --check. Pendiente comprobación física de los cuatro títulos al alternar español, inglés y chino.


El usuario confirmó físicamente que27 corrige los cuatro títulos de pestañas en el recorrido solicitado y que todo funciona bien.

## Compilación28: ejemplo ficticio y distribución limpia

El perfil inicial es Example Music Server, host music.example.invalid, recurso Music, subcarpeta Sample Library y usuario music-user, sin contraseña. Es un ejemplo inerte: abre el editor y no conecta ni escanea hasta configurarlo. La actualización agrega un ejemplo una sola vez a instalaciones existentes y conserva sus perfiles e identidades; el indicador persistente evita que reaparezca al borrarlo. SQLite actualiza solo el pequeño registro de configuración. Se conserva la copia JSON anterior durante la preparación local.

Pruebas host aprobadas de Store: primera instalación con un único ejemplo, escaneo del ejemplo rechazado sin conexión, conservación exacta del perfil anterior y de registros de etiquetas/favoritos/descarga/playlists, archivos manuales/portadas/etiquetas/sesión intactos, manifiesto y audio de caché automática intactos, ningún metadato materializado al agregar o borrar el ejemplo, reinicio sin duplicados, edición del ejemplo y eliminación persistente incluso dejando la lista vacía. También pasan las regresiones de biblioteca diferida de25154 canciones y preparación SQLite.

Los reportes originales y la captura del reproductor se retiran de la distribución y se conservan fuera del árbol versionado actual. Se sustituyen los nombres y rutas privados en las fixtures y documentación. El ZIP fuente se genera desde cero para impedir entradas obsoletas. Los commits/tags anteriores se conservan solo localmente; la futura publicación partirá de una instantánea limpia, sin enviar ese historial.

Compilación ARMv7/iOS9 e instalación USB28 completadas. Pasan las regresiones de SQLite y selección/persistencia de idioma;324 entradas por catálogo. Se verificó que IPA28 y ZIP fuente no contienen los anteriores host/recurso/ruta privados ni reportes/captura retirados. Pendiente confirmar en el iPod ambos perfiles y reproducción con biblioteca/caché conservadas. No se ha creado ni enviado ningún repositorio remoto.


El usuario confirmó físicamente que28 conserva su servidor, canciones y reproducción y agrega el ejemplo correctamente. Solicitó que los campos expliquen mejor qué introducir.

## Compilación29: ayuda para configurar el ejemplo

El editor del ejemplo conserva etiquetas visibles sobre los valores y añade instrucciones en inglés bajo cada campo. Distingue host, recurso compartido y subcarpeta relativa; explica usuario y contraseña SMB. Son seis textos estáticos con altura ajustada al ancho, sin trabajo de red ni de biblioteca. Se conservan los valores ficticios y la lógica de perfiles de28.

Compilación ARMv7/iOS9 e instalación USB29 completadas; catálogo de324 entradas y git diff --check aprobados. Pendiente revisión visual de las ayudas en el iPod.


## Compilación30: ayuda traducida en todos los perfiles

Las seis ayudas de configuración aparecen al agregar y editar cualquier servidor, incluido el ficticio. Se resuelven desde los catálogos locales en español, inglés y chino simplificado al construir el formulario; ajustan la altura al texto traducido. Los valores personales y los ejemplos de nombres/rutas no se traducen. La ayuda de contraseña ahora explica la conservación del valor guardado al dejar el campo vacío. No cambia la persistencia ni el acceso a biblioteca/red.

Pasan el verificador de330 entradas por catálogo, las pruebas de selección/persistencia/cambio de idioma y consultas concurrentes, la compilación ARMv7/iOS9 y la instalación USB30. Pendiente comprobación visual en el dispositivo de los formularios nuevo/existente en los tres idiomas.


## Preparación de la primera publicación

El usuario aprobó los cambios de30 y las composiciones promocionales con datos privados difuminados. Se preparan README equivalentes en inglés, español y chino simplificado, sin el historial de compilaciones en la portada. IPA y paquete de fuentes/objetos correspondientes se distribuyen como adjuntos de la release. El historial público parte de una instantánea limpia; los puntos de restauración privados anteriores permanecen solo en la máquina de desarrollo.


## Local library — internal build 31

- ARMv7/ARM build and USB installation completed on the target iPod; version 1.1 remains local and unpublished.
- New scanner host suite: nested and Unicode paths, overlapping roots, stable IDs, file removal, photo/hidden/partial exclusions and symlink avoidance passed.
- Store host suite: immutable synthetic source, no SMB access during scan or metadata extraction, MP3 tags/artwork, unchanged refresh, favorite and URL persistence, deleted-file tombstones passed.
- SQLite suite: local/native + manual + automatic cache union, deduplication, missing-file exclusion, metadata search, paging and cache eviction passed. Existing indexed library tests also passed.
- Session/cache regression suite and localization runtime suite passed. All three catalogs have 341 keys with matching format arguments.
- Physical validation of native iTunes asset playback, filesystem permissions and local automatic refresh is pending user confirmation. Installation does not establish those outcomes.
- No GitHub push or release is part of this change.


## Local source isolation — internal build 32

- Corrected Local to include only native iTunes/filesystem records. Manual downloads and automatic cache tracks remain outside Local. Existing audio, cached metadata and downloaded files are not deleted.
- Removed cache membership table, manifest backfill and cache-change UI refreshes that are no longer needed.
- SQLite and fallback query regression tests explicitly supply remote downloaded/cached tracks and assert that only the native file is returned. Missing local files remain excluded.
- Database, fallback index, Store and session/cache host suites passed; 341-key English/Spanish/Chinese catalog validation passed. ARMv7 build passed.
- README and UI help reflect the narrower source. Saved only in local Git; no push or release.


## iOS 6.1.3 compatibility — internal legacy build 33 (in progress)

- Preserved the previously validated IPA locally; `local-ios9-stable32` marks its source checkpoint. Development branch `codex/ios6-compat`; no push/release.
- Separate iOS 6 app/FFmpeg build passed, Mach-O minimum 6.1.3, ARMv7. USB installation on iPod5,1 / 6.1.3 succeeded. User confirmed Servers opens.
- On-device diagnostics: FLAC/Vorbis/Opus each decoded nonzero PCM without error; the native cached-MP3 extension probe reports playable with one audio track.
- All 13 `Tests/run-*.sh` host suites passed, plus pinned FFmpeg decoder smoke tests. Host tests do not emulate iOS 6 UIKit.
- Default iOS 9 rebuild passed. Every packaged file except the executable was byte-identical to the saved IPA; full disassembly of the executable (excluding output pathname header) was identical. Signature/build metadata can differ. Physical iOS 9 revalidation requires that device.
- The iOS 6 DeveloperDiskImage service rejected the available image with ImageMountFailed. Automated launch/screenshot services are unavailable; device reports are retrieved through Documents after manual launch. This does not affect app installation.
- Still pending: SMB connection and large-library scan, audible playback, seeking/crossfade, downloads/offline restore, local iTunes/file playback, language/menu/search journeys and hardware remote events. Do not claim full compatibility until these checks complete.


### Legacy build 34 — profile list refresh

Device inspection confirmed the user-created SMB profile was present in startup-profiles.json even though the list did not show it. The legacy editor now posts IPStoreChanged after a successful save and before popping, marking the covered list for reload in viewWillAppear. This branch compiles only with IP_IOS6; the default iOS 9 editor is unchanged. Legacy build and USB installation passed, and the persisted profile mirror was byte-identical before and after installation. User confirmation of the list/connection is pending.


### Legacy build 36 — empty list after large scan / watchdog

Two device crash reports show 0x8badf00d (resume watchdog), with the main thread waiting for the database lock while the persistence worker runs SQLite writes. AFC inspection found a 1,074,932,752-byte WAL. Its copied frame headers show a large uncommitted transaction repeatedly writing the same pages; committed state still had zero songs. This explains both the empty list and lost scans after termination.

Legacy-only changes: rollback journal instead of old SQLite WAL amplification; 2048-page cache; rebuild secondary indexes once per bulk atomic commit; defer main-thread tag-status reads, automatic metadata startup and diagnostic reads until the queued bulk save finishes. The new target also registers a literal instr() scalar, unavailable in SQLite 3.7.13. The default iOS 9 path retains WAL, index update policy and metadata scheduling.

`Tests/run-ios6-database-tests.sh` downloads a checksum-pinned public-domain SQLite 3.7.13 amalgamation from sqlite.org, then runs the full database and Store suites linked against that engine with IP_IOS6. Large import, ordering/search/paging, literal percent search, rollback atomicity, journal mode, lazy queues, favorites, local-source isolation and persistence tests passed. Default host database and Store suites also passed. Default iOS 9 rebuilt; disassembly differs from build 32 only in four assertion source-line constants moved by the conditional legacy code. Playback/library logic instructions otherwise remain unchanged.

USB install of build 36 succeeded. On-device container inspection after launch showed no WAL, with the original server profiles preserved. Physical completion of the new scan and audible playback remain pending. No remote music files were modified and no GitHub push was made.


### Legacy build 37 — truthful scan completion and less initial indexing

The user confirmed build 36 eventually populated the list. Its on-device diagnostics report 25,156 total records. The former “indexed” completion was posted before the asynchronous database save; a database copy taken during that live transaction was inconsistent and was not used as evidence of corruption or written back.

The iOS 6 scan now completes only after persistence succeeds, propagates save failures, and displays throttled saving counts and index phases. Initial bulk preparation creates the two title sort indexes rather than all twelve sort indexes. Other sort indexes are created on their first query on the background reader and persist for reuse. Legacy profile record reads explicitly preserve ordinal order, avoiding dependence on SQLite's choice of index. These changes compile out of iOS 9.

SQLite 3.7.13 database/Store suites cover lazy initial indexes, all metadata sort queries, persistent refresh order, atomic rollback and scan completion after disk persistence. Default database/Store and three-language localization tests also pass. Host timing is not a device speed measurement; physical scan timing and playback remain to be confirmed. No GitHub push or release.
