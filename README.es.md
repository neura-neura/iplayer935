<p align="center">
  <img src="Resources/AppIcon-60@3x.png" alt="iPlayer935" width="180" height="180">
</p>
<h1 align="center">iPlayer935</h1>

[English](README.md) · [Español](README.es.md) · [简体中文](README.zh-CN.md)

Reproductor de música nativo para **iPod touch 5 con iOS 9.3.5**. Reproduce tu música desde un servidor SMB, guarda canciones para escucharlas sin conexión y disfruta una interfaz inspirada en la app Música clásica del iPod.

![Reproduciendo, biblioteca y fundido cruzado](docs/media/iplayer935-playback.png)

![Playlists, reproducción sin conexión y servidores SMB](docs/media/iplayer935-library-offline.png)

*Composiciones promocionales basadas en capturas reales del iPod. Los datos privados del servidor están difuminados.*

## Funciones

- Acceso SMB2/SMB3 a tu servidor de música, con varios perfiles y contraseñas guardadas en Keychain.
- Reproducción de MP3, AAC/M4A, ALAC y WAV/AIFF/CAF mediante iOS; decodificación de FLAC, Ogg Vorbis y Opus mediante FFmpeg.
- Caché persistente de metadatos y portadas, con progreso y controles para pausar y continuar.
- Búsqueda y orden por título, artista, álbum, género, número de pista o fecha de modificación del archivo.
- Minirreproductor permanente, vista completa de Reproduciendo, favoritos y acciones para varias canciones.
- Playlists e importación M3U/M3U8, modo aleatorio y restauración de la última canción, posición y cola.
- Fundido cruzado ajustable con curvas de potencia constante o lineal, transiciones manuales/automáticas independientes y control por sesión.
- Descargas manuales y caché automática con límite de espacio que precarga las siguientes canciones de la cola.
- Inglés, español y chino simplificado, con selector de idioma en la app y opción de usar el idioma del sistema.

## Descargar e instalar

Descarga **iPlayer935.ipa** desde la [última release](https://github.com/neura-neura/iplayer935/releases/latest). Allí están las notas de la versión y los paquetes correspondientes de código fuente y objetos para reenlazado, en inglés.

El dispositivo compatible es un **iPod touch 5 (iPod5,1) con jailbreak, iOS 9.3.5 y ARMv7**, con **AppSync Unified** instalado. No se ha validado en otros dispositivos ni versiones de iOS.

Para instalar desde una Mac por USB, clona este repositorio, coloca el IPA descargado en `deliverables/iPlayer935.ipa`, conecta y desbloquea el iPod y acepta la confianza en la computadora si se solicita:

```sh
brew install libimobiledevice ideviceinstaller
./scripts/install.sh
```

Instalar una actualización con el mismo identificador conserva los datos de la app. No la desinstales primero si quieres conservar tu biblioteca, ajustes y descargas.

## Conectar tu música

1. Abre **Servidores**. En instalaciones nuevas solo aparece **Example Music Server**, un perfil ficticio que no se conecta automáticamente. Tócalo para introducir tus datos o usa **+** para agregar un perfil. Cada campo incluye ayuda.
2. Introduce la IP o el nombre del servidor sin `smb://`, el nombre del recurso compartido SMB, una subcarpeta opcional relativa a ese recurso y tus credenciales SMB. Ejemplo: host `music-server.local`, recurso `Music`, carpeta `Albums/Rock`. Usa una cuenta autorizada para SMB; una cuenta SSH puede tener permisos distintos.
3. Guarda y usa **ⓘ → Probar conexión**. Abre el servidor para explorar su biblioteca. La app lee el recurso de música sin modificar archivos del servidor.
4. Usa **⋯ → Actualizar biblioteca y M3U** para forzar un escaneo. Las revisiones automáticas se ejecutan al entrar al servidor y mientras su biblioteca está visible, con un intervalo de 15 minutos entre revisiones. Son escaneos en segundo plano, no notificaciones instantáneas del servidor.
5. Los metadatos y las portadas se guardan en caché local. Consulta o pausa el progreso en **⋯ → Estado de la caché de etiquetas**. Los archivos ya revisados y sin cambios no se vuelven a procesar cada vez que abres la app.

## Reproducción y escucha sin conexión

Toca una canción para reproducirla sin salir de la lista. Toca el minirreproductor para abrir Reproduciendo; vuelve con **Atrás** o deslizando desde el borde izquierdo. El reproductor incluye controles de aleatorio y fundido cruzado; los ajustes del fundido están en **⋯**. Mantén pulsado aleatorio para suspender o reanudar el fundido si ese control por sesión está habilitado.

Usa el icono de selección en una lista, marca canciones y abre **⋯** para aplicar acciones por lote. Crea listas desde **Playlists → +**. Los menús de información de las canciones permiten gestionar favoritos, playlists y descargas.

Gestiona las descargas manuales en **Descargas**. Abre **Descargas → ⋯ → Caché automática** para ajustar la precarga de canciones y consultar cuáles están disponibles. Solo los archivos descargados por completo funcionan sin conexión; la caché automática puede eliminar entradas para respetar su límite de espacio. Para acceder a una canción remota no guardada, el iPod debe tener una ruta al servidor SMB, por ejemplo mediante la misma red o una VPN ya configurada.

## Rendimiento y compatibilidad

La biblioteca usa índices SQLite, listas paginadas y trabajo en segundo plano para manejar colecciones grandes. El primer escaneo y el cacheado de etiquetas requieren tiempo, especialmente con una conexión lenta al servidor; puedes navegar y reproducir durante la preparación.

La extensión no garantiza la compatibilidad del códec. WMA no es compatible. La reproducción FLAC, los saltos de tiempo y la escucha sin conexión se han comprobado en el iPod físico; Ogg/Opus con archivos reales todavía requieren más pruebas en el dispositivo. Consulta las [notas de validación](docs/VALIDATION.md) para conocer el comportamiento probado y sus límites.

## Compilar y desarrollar

La app está escrita en Objective-C/UIKit para ARMv7. Los scripts usan LLVM, ldid y un SDK antiguo de iOS con versión fija; no es un proyecto de Xcode moderno.

```sh
brew install llvm ldid libimobiledevice ideviceinstaller
./scripts/build.sh
```

El resultado es `deliverables/iPlayer935.ipa`. Consulta las [instrucciones de compilación](docs/BUILD.md), [arquitectura](docs/ARCHITECTURE.md), [integración SMB](docs/SMB.md) y [localización](docs/LOCALIZATION.md). Los ejecutores de pruebas están en `Tests/`; algunos requieren las bibliotecas de códecs generadas por `scripts/codec-build.sh`.

## Créditos y dependencias

Hecho por [neura-neura](https://github.com/neura-neura).

La app incluye [libsmb2](https://github.com/sahlberg/libsmb2) y [FFmpeg](https://ffmpeg.org/), con sus avisos LGPL en `Vendor/libsmb2` y `deliverables/licences`. Las releases incluyen el código fuente correspondiente y objetos para reenlazado; consulta las [instrucciones de compilación](docs/BUILD.md) para reconstruir dependencias. Las portadas y los nombres de canciones de las capturas pertenecen a sus respectivos propietarios. Este es un proyecto independiente, sin afiliación con Apple ni Spotify.
