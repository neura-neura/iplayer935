# Biblioteca SQLite

## Migración y persistencia

`IPLibraryDB` usa la SQLite del sistema, WAL y transacciones. Emplea SQL compatible con iOS9: no depende de JSON1, UPSERT moderno o FTS reciente. El esquema contiene un registro JSON por canción y columnas de consulta normalizadas, con índices por perfil/endpoint y por órdenes globales. Los valores de búsqueda se pliegan una vez al cambiar el registro; los índices usan comparación natural para números y texto.

Si falta una base confirmada, el cargador lee library.json, aplica decoded-metadata.json y favorites.json como18 y entrega inmediatamente ese modelo a la interfaz. No espera la conversión SQLite. La biblioteca conserva búsqueda, orden y reproducción con el índice anterior, que ahora se reutiliza entre consultas. Esto mantiene el tiempo de lectura JSON inicial de18; no elimina todo coste de primer arranque.

Después se prepara SQLite en una cola de baja prioridad: tandas de256 registros copiadas brevemente desde main, transacciones pequeñas e índices creados al finalizar la inserción. Un marcador persistente impide abrir una conversión parcial como si estuviera lista. La comparación Unicode libera objetos temporales por comparación y la normalización reutiliza valores frecuentes con caché limitada. La instantánea inicial conserva IDs y ajustes pequeños, evitando duplicar todos los diccionarios de etiquetas.

Opciones → Preparación de la biblioteca muestra etapa, canciones preparadas, errores y Pausar/Continuar. Cambiar a segundo plano solicita pausa y volver permite continuar. Tras cerrar o interrumpir la conversión puede repetirse el trabajo local; no se vuelven a descargar etiquetas ni audio. El presupuesto se comprueba entre tandas e índices (180 segundos); una operación SQL individual puede tardar más antes de comprobarlo. Si falla, la biblioteca anterior sigue disponible y permite reintentar. Durante la preparación los cambios siguen guardándose en los JSON; un registro de cambios se reconcilia antes de activar SQLite, esperando también escrituras JSON pendientes. Solo al terminar se quita el marcador y se activa la colección bajo demanda. Las credenciales siguen en Keychain.

Después de la migración no se vuelven a combinar los JSON al iniciar. Se cargan perfiles, playlists, cuota y el catálogo de IDs, sin leer todos los metadatos. `IPTrackCollection` materializa diccionarios al consultarlos y conserva su identidad para los controladores existentes. Los guardados comparan los modelos consultados contra su última versión persistida y escriben únicamente los modificados. Los cambios estructurales también actualizan el orden y eliminaciones en una transacción.

Las actualizaciones de favoritos y etiquetas llegan a SQLite por la cola de persistencia. Las consultas de pantalla se encolan después de las escrituras precedentes, para que una notificación no consulte un índice anterior. Una vez activada SQLite, los JSON dejan de actualizarse y permanecen como respaldo del estado anterior a esa activación. startup-profiles.json continúa actualizándose como copia pequeña para presentar Servidores antes de abrir la base.

## Listas, metadatos y cola

Las pantallas piden200 filas, sus metadatos y el total en una cola serial de fondo. Al acercarse al final cargado se solicita el siguiente bloque. Cambiar filtros/orden invalida solicitudes anteriores mediante generación. Los totales se cachean por filtro y se invalidan al persistir cambios. Ordenar no reconstruye todos los documentos; usa índices ya guardados. La búsqueda de subcadenas examina la columna normalizada en segundo plano; no usa un índice de texto completo.

Reproducir una fila consulta el orden completo de IDs y crea `IPTrackList`, sin materializar todas sus etiquetas. El guardado/restauración de sesión reconoce ese formato y conserva orden, duplicados y posición. La actualización de la canción actual la busca por clave primaria. La anticipación automática consulta únicamente las próximas canciones. El diagnóstico usa agregados SQL y algunas muestras, evitando un recorrido completo de los metadatos.

El cacheado automático consulta pendientes por índice en tandas de256 y conserva la pausa/reintentos. Las revisiones remotas periódicas mantienen su recorrido SMB para detectar archivos agregados, cambiados o retirados; los registros previos se deserializan fuera de main, y una revisión sin cambios no materializa ni reescribe todas las canciones. Las operaciones masivas explícitas aún pueden requerir recorrer la biblioteca. Los modelos ya consultados permanecen en memoria durante el proceso; no hay un límite estricto de objetos para una sesión que recorra toda la colección.

## Verificación

`Tests/run-database-tests.sh` comprueba25154 canciones, persistencia de ajustes y playlists, primera página y segunda sin solapamientos, órdenes por metadatos, búsqueda con acentos, aislamiento de endpoint, favoritos/descargas, duplicados de playlist, cola completa y restauración con materialización parcial, cambios incrementales, revisión sin cambios, eliminación estructural, rollback de transacción fallida y EXPLAIN QUERY PLAN con índice persistente sin orden temporal para título.

`Tests/run-store-tests.sh` comprueba migración desde JSON con overlays, carga diferida, guardado prematuro protegido, identidad de perfiles, etiquetas, portadas, pausa y caché de audio. `Tests/run-session-cache-tests.sh` mantiene las comprobaciones de sesión y audio automático fuera de red. Los tiempos de host no estiman el tiempo físico del iPod.

En20 se verifican además cancelación/reintento y marcador de disponibilidad, IDs desordenados y títulos multilingües, paridad de comparación natural, acceso a páginas antes de finalizar la preparación, pausa/continuación y reconciliación de favoritos modificados durante la conversión. La prueba de25154 registros tarda aproximadamente0.4s en Mac para importación directa; no predice el tiempo del iPod.
