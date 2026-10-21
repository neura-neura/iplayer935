# Caché de etiquetas

La biblioteca y el mapa `decoded-metadata.json` se conservan en Application Support. Los lotes se escriben atómicamente, con agrupación de5s, y se vacían al entrar en segundo plano. Un cierre forzado durante un lote puede repetir solo el avance aún no guardado. No se reinicia toda la colección al abrir la app.

El resultado distingue etiquetas encontradas, archivo revisado sin etiquetas y fallo de lectura pendiente. Los dos primeros quedan terminados; los fallos esperan10min para volver a intentarse. Tras tres fallos consecutivos se detiene esa pasada. La pausa es persistente por origen. Los cambios de tamaño o mtime invalidan la consulta de ese archivo; nuevos archivos se añaden a la cola tras el escaneo automático, cuyo intervalo mínimo es15min. No hay notificaciones push de SMB.

MP3: ID3v1/1.1, v2.2/2.3/2.4, Latin1/UTF16 con BOM/UTF16BE/UTF8, TPE2 como alternativa al artista, pista, géneros ID3 originales, PIC/APIC, extended headers, agrupación/DLI, zlib y unsynchronisation. Se detecta v2.4 al final con footer, también antes de ID3v1. No se descifra ID3 cifrado; ese caso informa fallo. Un archivo sin etiquetas válidas conserva el nombre del archivo.

La lectura usa una ventana de16KiB, bloques máximos de64KiB, texto por frame de hasta64KiB y portada de hasta4MiB. Se saltan portadas mayores y otros bloques innecesarios sin perder texto posterior. Las etiquetas v2.2/3 con unsynchronisation global se normalizan completas con límite8MiB; las que exceden ese límite quedan como fallo explícito. Se limita el recorrido a4096frames. La portada se reduce a320px en segundo plano. No se descarga el audio completo para leer ID3.

El lector reutiliza una conexión SMB con timeout5s. Durante reproducción reduce el ritmo y aplaza formatos que requieren abrir decodificadores. La primera pasada de25mil archivos seguirá tardando; puede pausarse desde Opciones → Estado de la caché de etiquetas. El avance continúa desde pendientes y los resultados llegan a las filas automáticamente. La corrección14 repasa una vez los MP3 incompletos guardados por13.

Referencias de formato: https://id3.org/id3v2-00 , https://id3.org/id3v2.3.0 , https://id3.org/id3v2.4.0-structure .


Desde15, `artworkAutoVersion` registra la revisión de portada de MP3 por separado. Un MP3 con texto guardado pero sin imagen ni revisión15 se consulta una vez. Se omiten los que ya tienen portada y los que14 registró sin etiquetas. El resultado, exista o no imagen, queda guardado; no se repite al reiniciar. Al cambiar tamaño/mtime se invalida también este marcador. Los lotes se entregan para reducción al acumular4MiB de datos de portada, además de los límites de25archivos/5s.
