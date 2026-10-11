import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_ja.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
    Locale('ja')
  ];

  /// No description provided for @appTitle.
  ///
  /// In es, this message translates to:
  /// **'Sonero'**
  String get appTitle;

  /// No description provided for @navHome.
  ///
  /// In es, this message translates to:
  /// **'Inicio'**
  String get navHome;

  /// No description provided for @navLibrary.
  ///
  /// In es, this message translates to:
  /// **'Biblioteca'**
  String get navLibrary;

  /// No description provided for @navAnalytics.
  ///
  /// In es, this message translates to:
  /// **'Estadísticas'**
  String get navAnalytics;

  /// No description provided for @navDownload.
  ///
  /// In es, this message translates to:
  /// **'Descargar de YouTube'**
  String get navDownload;

  /// No description provided for @navSearch.
  ///
  /// In es, this message translates to:
  /// **'Buscador'**
  String get navSearch;

  /// No description provided for @downloadComplete.
  ///
  /// In es, this message translates to:
  /// **'Descarga Completada'**
  String get downloadComplete;

  /// No description provided for @librarySection.
  ///
  /// In es, this message translates to:
  /// **'BIBLIOTECA'**
  String get librarySection;

  /// No description provided for @newPlaylist.
  ///
  /// In es, this message translates to:
  /// **'Nueva Playlist'**
  String get newPlaylist;

  /// No description provided for @newPlaylistHint.
  ///
  /// In es, this message translates to:
  /// **'Nombre de la playlist'**
  String get newPlaylistHint;

  /// No description provided for @create.
  ///
  /// In es, this message translates to:
  /// **'Crear'**
  String get create;

  /// No description provided for @cancel.
  ///
  /// In es, this message translates to:
  /// **'Cancelar'**
  String get cancel;

  /// No description provided for @close.
  ///
  /// In es, this message translates to:
  /// **'Cerrar'**
  String get close;

  /// No description provided for @save.
  ///
  /// In es, this message translates to:
  /// **'Guardar'**
  String get save;

  /// No description provided for @confirm.
  ///
  /// In es, this message translates to:
  /// **'Confirmar'**
  String get confirm;

  /// No description provided for @change.
  ///
  /// In es, this message translates to:
  /// **'Cambiar'**
  String get change;

  /// No description provided for @delete.
  ///
  /// In es, this message translates to:
  /// **'Eliminar'**
  String get delete;

  /// No description provided for @retry.
  ///
  /// In es, this message translates to:
  /// **'Reintentar'**
  String get retry;

  /// No description provided for @clear.
  ///
  /// In es, this message translates to:
  /// **'Limpiar'**
  String get clear;

  /// No description provided for @open.
  ///
  /// In es, this message translates to:
  /// **'Abrir'**
  String get open;

  /// No description provided for @download.
  ///
  /// In es, this message translates to:
  /// **'Descargar'**
  String get download;

  /// No description provided for @refresh.
  ///
  /// In es, this message translates to:
  /// **'Actualizar'**
  String get refresh;

  /// No description provided for @renamePlaylist.
  ///
  /// In es, this message translates to:
  /// **'Renombrar Playlist'**
  String get renamePlaylist;

  /// No description provided for @newPlaylistName.
  ///
  /// In es, this message translates to:
  /// **'Nuevo nombre'**
  String get newPlaylistName;

  /// No description provided for @rename.
  ///
  /// In es, this message translates to:
  /// **'Renombrar'**
  String get rename;

  /// No description provided for @deletePlaylist.
  ///
  /// In es, this message translates to:
  /// **'Eliminar Playlist'**
  String get deletePlaylist;

  /// No description provided for @deletePlaylistConfirm.
  ///
  /// In es, this message translates to:
  /// **'Se eliminará \"{name}\". El contenido se mantendrá en tu Biblioteca.'**
  String deletePlaylistConfirm(String name);

  /// No description provided for @settings.
  ///
  /// In es, this message translates to:
  /// **'Configuración'**
  String get settings;

  /// No description provided for @welcomeHome.
  ///
  /// In es, this message translates to:
  /// **'Bienvenido a Sonero'**
  String get welcomeHome;

  /// No description provided for @play.
  ///
  /// In es, this message translates to:
  /// **'Reproducir'**
  String get play;

  /// No description provided for @moreInfo.
  ///
  /// In es, this message translates to:
  /// **'Más información'**
  String get moreInfo;

  /// No description provided for @continueWatching.
  ///
  /// In es, this message translates to:
  /// **'Seguir Reproduciendo'**
  String get continueWatching;

  /// No description provided for @yourSmartPlaylists.
  ///
  /// In es, this message translates to:
  /// **'Playlists Inteligentes'**
  String get yourSmartPlaylists;

  /// No description provided for @language.
  ///
  /// In es, this message translates to:
  /// **'Idioma'**
  String get language;

  /// No description provided for @languageSpanish.
  ///
  /// In es, this message translates to:
  /// **'Español'**
  String get languageSpanish;

  /// No description provided for @languageEnglish.
  ///
  /// In es, this message translates to:
  /// **'Inglés'**
  String get languageEnglish;

  /// No description provided for @languageJapanese.
  ///
  /// In es, this message translates to:
  /// **'Japonés'**
  String get languageJapanese;

  /// No description provided for @appearance.
  ///
  /// In es, this message translates to:
  /// **'Apariencia'**
  String get appearance;

  /// No description provided for @apiConnection.
  ///
  /// In es, this message translates to:
  /// **'Conexión a la API (Local/Remota)'**
  String get apiConnection;

  /// No description provided for @musicFolder.
  ///
  /// In es, this message translates to:
  /// **'Carpeta de Medios'**
  String get musicFolder;

  /// No description provided for @playerShuffle.
  ///
  /// In es, this message translates to:
  /// **'Aleatorio'**
  String get playerShuffle;

  /// No description provided for @playerPrevious.
  ///
  /// In es, this message translates to:
  /// **'Anterior'**
  String get playerPrevious;

  /// No description provided for @playerNext.
  ///
  /// In es, this message translates to:
  /// **'Siguiente'**
  String get playerNext;

  /// No description provided for @playerRepeat.
  ///
  /// In es, this message translates to:
  /// **'Repetir'**
  String get playerRepeat;

  /// No description provided for @playerShowVideo.
  ///
  /// In es, this message translates to:
  /// **'Mostrar Video'**
  String get playerShowVideo;

  /// No description provided for @playerGridView.
  ///
  /// In es, this message translates to:
  /// **'Vista de Cuadrícula'**
  String get playerGridView;

  /// No description provided for @playerListView.
  ///
  /// In es, this message translates to:
  /// **'Vista de Lista'**
  String get playerListView;

  /// No description provided for @trackCount.
  ///
  /// In es, this message translates to:
  /// **'{count} canción{count, plural, =1{} other{es}}'**
  String trackCount(int count);

  /// No description provided for @autoFillMetadata.
  ///
  /// In es, this message translates to:
  /// **'Autocompletar Metadatos'**
  String get autoFillMetadata;

  /// No description provided for @exportCsv.
  ///
  /// In es, this message translates to:
  /// **'Exportar CSV'**
  String get exportCsv;

  /// No description provided for @csvSaved.
  ///
  /// In es, this message translates to:
  /// **'CSV guardado: {path}'**
  String csvSaved(String path);

  /// No description provided for @editMetadata.
  ///
  /// In es, this message translates to:
  /// **'Editar metadatos'**
  String get editMetadata;

  /// No description provided for @autoFillMetadataApi.
  ///
  /// In es, this message translates to:
  /// **'Autocompletar metadatos (API)'**
  String get autoFillMetadataApi;

  /// No description provided for @deleteFile.
  ///
  /// In es, this message translates to:
  /// **'Eliminar archivo'**
  String get deleteFile;

  /// No description provided for @moveTo.
  ///
  /// In es, this message translates to:
  /// **'Mover a...'**
  String get moveTo;

  /// No description provided for @libraryRoot.
  ///
  /// In es, this message translates to:
  /// **'Biblioteca (raíz)'**
  String get libraryRoot;

  /// No description provided for @deleteSong.
  ///
  /// In es, this message translates to:
  /// **'Eliminar canción'**
  String get deleteSong;

  /// No description provided for @deleteSongConfirm.
  ///
  /// In es, this message translates to:
  /// **'¿Seguro que quieres eliminar \"{name}\" del disco?'**
  String deleteSongConfirm(String name);

  /// No description provided for @fileDeleted.
  ///
  /// In es, this message translates to:
  /// **'Archivo eliminado'**
  String get fileDeleted;

  /// No description provided for @movedTo.
  ///
  /// In es, this message translates to:
  /// **'Movida a {destination}'**
  String movedTo(String destination);

  /// No description provided for @emptyLibrary.
  ///
  /// In es, this message translates to:
  /// **'Tu biblioteca está vacía'**
  String get emptyLibrary;

  /// No description provided for @emptyPlaylist.
  ///
  /// In es, this message translates to:
  /// **'{name} está vacía'**
  String emptyPlaylist(String name);

  /// No description provided for @emptyLibraryHint.
  ///
  /// In es, this message translates to:
  /// **'Presiona el atajo de teclado para reconocer una canción'**
  String get emptyLibraryHint;

  /// No description provided for @scanningMetadata.
  ///
  /// In es, this message translates to:
  /// **'Escaneando Metadatos'**
  String get scanningMetadata;

  /// No description provided for @startingScan.
  ///
  /// In es, this message translates to:
  /// **'Iniciando escaneo...'**
  String get startingScan;

  /// No description provided for @starting.
  ///
  /// In es, this message translates to:
  /// **'Iniciando...'**
  String get starting;

  /// No description provided for @unknownError.
  ///
  /// In es, this message translates to:
  /// **'Error desconocido'**
  String get unknownError;

  /// No description provided for @analyticsTitle.
  ///
  /// In es, this message translates to:
  /// **'Analíticas de Consumo'**
  String get analyticsTitle;

  /// No description provided for @yourHabits.
  ///
  /// In es, this message translates to:
  /// **'Tus Hábitos'**
  String get yourHabits;

  /// No description provided for @playbackHours.
  ///
  /// In es, this message translates to:
  /// **'Horas de reproducción'**
  String get playbackHours;

  /// No description provided for @videosCompleted.
  ///
  /// In es, this message translates to:
  /// **'Videos Completados'**
  String get videosCompleted;

  /// No description provided for @musicListened.
  ///
  /// In es, this message translates to:
  /// **'Música Escuchada'**
  String get musicListened;

  /// No description provided for @recentHistory.
  ///
  /// In es, this message translates to:
  /// **'Historial Reciente (Benrio)'**
  String get recentHistory;

  /// No description provided for @analyticsPlaceholder.
  ///
  /// In es, this message translates to:
  /// **'Aquí se integrarán los datos desde el backend cuando se implemente la conexión con Benrio.'**
  String get analyticsPlaceholder;

  /// No description provided for @searchHint.
  ///
  /// In es, this message translates to:
  /// **'Buscar canciones, artistas, o YouTube...'**
  String get searchHint;

  /// No description provided for @typeToSearch.
  ///
  /// In es, this message translates to:
  /// **'Escribe para buscar...'**
  String get typeToSearch;

  /// No description provided for @noLocalResults.
  ///
  /// In es, this message translates to:
  /// **'No hay resultados locales'**
  String get noLocalResults;

  /// No description provided for @localLibraryCount.
  ///
  /// In es, this message translates to:
  /// **'Biblioteca Local ({count})'**
  String localLibraryCount(int count);

  /// No description provided for @noYouTubeResults.
  ///
  /// In es, this message translates to:
  /// **'No hay resultados en YouTube'**
  String get noYouTubeResults;

  /// No description provided for @downloadMedia.
  ///
  /// In es, this message translates to:
  /// **'Descargar Medio'**
  String get downloadMedia;

  /// No description provided for @format.
  ///
  /// In es, this message translates to:
  /// **'Formato:'**
  String get format;

  /// No description provided for @formatLoadError.
  ///
  /// In es, this message translates to:
  /// **'Error cargando formatos: {error}'**
  String formatLoadError(String error);

  /// No description provided for @destinationPlaylist.
  ///
  /// In es, this message translates to:
  /// **'Destino (Playlist):'**
  String get destinationPlaylist;

  /// No description provided for @downloadYouTubeVideo.
  ///
  /// In es, this message translates to:
  /// **'Descargar Video de YouTube'**
  String get downloadYouTubeVideo;

  /// No description provided for @fetchInfo.
  ///
  /// In es, this message translates to:
  /// **'Obtener Info'**
  String get fetchInfo;

  /// No description provided for @selectFormat.
  ///
  /// In es, this message translates to:
  /// **'Seleccionar Formato:'**
  String get selectFormat;

  /// No description provided for @videoFolder.
  ///
  /// In es, this message translates to:
  /// **'Carpeta de Video'**
  String get videoFolder;

  /// No description provided for @notSelected.
  ///
  /// In es, this message translates to:
  /// **'No seleccionada'**
  String get notSelected;

  /// No description provided for @selectFolder.
  ///
  /// In es, this message translates to:
  /// **'Seleccionar carpeta'**
  String get selectFolder;

  /// No description provided for @selectMusicFolderDialog.
  ///
  /// In es, this message translates to:
  /// **'Selecciona la carpeta donde guardar la música'**
  String get selectMusicFolderDialog;

  /// No description provided for @selectVideoFolderDialog.
  ///
  /// In es, this message translates to:
  /// **'Selecciona la carpeta donde guardar los videos'**
  String get selectVideoFolderDialog;

  /// No description provided for @authentication.
  ///
  /// In es, this message translates to:
  /// **'Autenticación (Anti-Bot)'**
  String get authentication;

  /// No description provided for @authDescription.
  ///
  /// In es, this message translates to:
  /// **'Usa tus cookies de YouTube para evitar bloqueos al descargar.'**
  String get authDescription;

  /// No description provided for @syncBenrio.
  ///
  /// In es, this message translates to:
  /// **'Sincronizar (Benrio)'**
  String get syncBenrio;

  /// No description provided for @cookiesSynced.
  ///
  /// In es, this message translates to:
  /// **'Cookies sincronizadas correctamente.'**
  String get cookiesSynced;

  /// No description provided for @loadCookiesFile.
  ///
  /// In es, this message translates to:
  /// **'Cargar cookies.txt'**
  String get loadCookiesFile;

  /// No description provided for @selectCookiesDialog.
  ///
  /// In es, this message translates to:
  /// **'Selecciona tu archivo cookies.txt'**
  String get selectCookiesDialog;

  /// No description provided for @fileLoaded.
  ///
  /// In es, this message translates to:
  /// **'Archivo cargado correctamente.'**
  String get fileLoaded;

  /// No description provided for @themeMode.
  ///
  /// In es, this message translates to:
  /// **'Modo de tema'**
  String get themeMode;

  /// No description provided for @themeSystem.
  ///
  /// In es, this message translates to:
  /// **'Sistema'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In es, this message translates to:
  /// **'Claro'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In es, this message translates to:
  /// **'Oscuro'**
  String get themeDark;

  /// No description provided for @primaryColor.
  ///
  /// In es, this message translates to:
  /// **'Color principal'**
  String get primaryColor;

  /// No description provided for @sidebarColor.
  ///
  /// In es, this message translates to:
  /// **'Color de barra lateral'**
  String get sidebarColor;

  /// No description provided for @defaultColor.
  ///
  /// In es, this message translates to:
  /// **'Por defecto'**
  String get defaultColor;

  /// No description provided for @selectColor.
  ///
  /// In es, this message translates to:
  /// **'Seleccionar color'**
  String get selectColor;

  /// No description provided for @saveUrl.
  ///
  /// In es, this message translates to:
  /// **'Guardar URL'**
  String get saveUrl;

  /// No description provided for @refetchTest.
  ///
  /// In es, this message translates to:
  /// **'Refetch / Probar'**
  String get refetchTest;

  /// No description provided for @connectionSuccess.
  ///
  /// In es, this message translates to:
  /// **'✅ Conexión exitosa al backend.'**
  String get connectionSuccess;

  /// No description provided for @connectionFailed.
  ///
  /// In es, this message translates to:
  /// **'❌ No se pudo conectar al backend.'**
  String get connectionFailed;

  /// No description provided for @listenDuration.
  ///
  /// In es, this message translates to:
  /// **'Duración de escucha'**
  String get listenDuration;

  /// No description provided for @durationSaved.
  ///
  /// In es, this message translates to:
  /// **'Duración guardada'**
  String get durationSaved;

  /// No description provided for @durationRange.
  ///
  /// In es, this message translates to:
  /// **'Entre 5 y 60 segundos.'**
  String get durationRange;

  /// No description provided for @secondsSuffix.
  ///
  /// In es, this message translates to:
  /// **'seg'**
  String get secondsSuffix;

  /// No description provided for @globalHotkeys.
  ///
  /// In es, this message translates to:
  /// **'Atajos de teclado globales'**
  String get globalHotkeys;

  /// No description provided for @hotkeysDescription.
  ///
  /// In es, this message translates to:
  /// **'Funcionan aunque la ventana esté minimizada.'**
  String get hotkeysDescription;

  /// No description provided for @hotkeyMic.
  ///
  /// In es, this message translates to:
  /// **'🎙️ Escuchar con Micrófono'**
  String get hotkeyMic;

  /// No description provided for @hotkeySystem.
  ///
  /// In es, this message translates to:
  /// **'🖥️ Escuchar Audio del Sistema'**
  String get hotkeySystem;

  /// No description provided for @hotkeyVideo.
  ///
  /// In es, this message translates to:
  /// **'📺 Descargar Video (Portapapeles)'**
  String get hotkeyVideo;

  /// No description provided for @hotkeyShow.
  ///
  /// In es, this message translates to:
  /// **'👀 Mostrar Ventana'**
  String get hotkeyShow;

  /// No description provided for @hotkeyHide.
  ///
  /// In es, this message translates to:
  /// **'👻 Ocultar Ventana'**
  String get hotkeyHide;

  /// No description provided for @hotkeySaved.
  ///
  /// In es, this message translates to:
  /// **'Atajo guardado'**
  String get hotkeySaved;

  /// No description provided for @hotkeyTitleMic.
  ///
  /// In es, this message translates to:
  /// **'🎙️ Atajo — Micrófono'**
  String get hotkeyTitleMic;

  /// No description provided for @hotkeyTitleSystem.
  ///
  /// In es, this message translates to:
  /// **'🖥️ Atajo — Sistema'**
  String get hotkeyTitleSystem;

  /// No description provided for @hotkeyTitleVideo.
  ///
  /// In es, this message translates to:
  /// **'📺 Atajo — Video'**
  String get hotkeyTitleVideo;

  /// No description provided for @hotkeyTitleShow.
  ///
  /// In es, this message translates to:
  /// **'👀 Atajo — Mostrar Ventana'**
  String get hotkeyTitleShow;

  /// No description provided for @hotkeyTitleHide.
  ///
  /// In es, this message translates to:
  /// **'👻 Atajo — Ocultar Ventana'**
  String get hotkeyTitleHide;

  /// No description provided for @hotkeyRecordPrompt.
  ///
  /// In es, this message translates to:
  /// **'Presiona la combinación de teclas que quieres usar.'**
  String get hotkeyRecordPrompt;

  /// No description provided for @micDevice.
  ///
  /// In es, this message translates to:
  /// **'Dispositivo de micrófono'**
  String get micDevice;

  /// No description provided for @deviceNumber.
  ///
  /// In es, this message translates to:
  /// **'Dispositivo #{index}'**
  String deviceNumber(int index);

  /// No description provided for @systemDefault.
  ///
  /// In es, this message translates to:
  /// **'Default del sistema'**
  String get systemDefault;

  /// No description provided for @detectDevices.
  ///
  /// In es, this message translates to:
  /// **'Detectar dispositivos'**
  String get detectDevices;

  /// No description provided for @useDefault.
  ///
  /// In es, this message translates to:
  /// **'Usar default'**
  String get useDefault;

  /// No description provided for @audioDevices.
  ///
  /// In es, this message translates to:
  /// **'Dispositivos de audio'**
  String get audioDevices;

  /// No description provided for @editMetadataTitle.
  ///
  /// In es, this message translates to:
  /// **'Editar Metadatos'**
  String get editMetadataTitle;

  /// No description provided for @fieldTitle.
  ///
  /// In es, this message translates to:
  /// **'Título'**
  String get fieldTitle;

  /// No description provided for @fieldArtist.
  ///
  /// In es, this message translates to:
  /// **'Artista'**
  String get fieldArtist;

  /// No description provided for @fieldAlbum.
  ///
  /// In es, this message translates to:
  /// **'Álbum'**
  String get fieldAlbum;

  /// No description provided for @fieldYear.
  ///
  /// In es, this message translates to:
  /// **'Año'**
  String get fieldYear;

  /// No description provided for @fieldGenre.
  ///
  /// In es, this message translates to:
  /// **'Género'**
  String get fieldGenre;

  /// No description provided for @errorSaving.
  ///
  /// In es, this message translates to:
  /// **'Error guardando: {error}'**
  String errorSaving(String error);

  /// No description provided for @errorPrefix.
  ///
  /// In es, this message translates to:
  /// **'Error: {error}'**
  String errorPrefix(String error);

  /// No description provided for @playlistDetected.
  ///
  /// In es, this message translates to:
  /// **'Playlist de YouTube detectada'**
  String get playlistDetected;

  /// No description provided for @downloadPlaylist.
  ///
  /// In es, this message translates to:
  /// **'Descargar Playlist'**
  String get downloadPlaylist;

  /// No description provided for @playlistDownloadOptions.
  ///
  /// In es, this message translates to:
  /// **'Opciones de descarga de Playlist'**
  String get playlistDownloadOptions;

  /// No description provided for @loadingPlaylistInfo.
  ///
  /// In es, this message translates to:
  /// **'Cargando información de la playlist...'**
  String get loadingPlaylistInfo;

  /// No description provided for @playlistVideosCount.
  ///
  /// In es, this message translates to:
  /// **'{count} videos encontrados'**
  String playlistVideosCount(int count);

  /// No description provided for @enqueuingDownloads.
  ///
  /// In es, this message translates to:
  /// **'Encolando {count} descargas...'**
  String enqueuingDownloads(int count);

  /// No description provided for @playlistEnqueued.
  ///
  /// In es, this message translates to:
  /// **'Se han encolado {count} descargas en el gestor.'**
  String playlistEnqueued(int count);

  /// No description provided for @navShare.
  ///
  /// In es, this message translates to:
  /// **'Compartir'**
  String get navShare;

  /// No description provided for @navActiveDownloads.
  ///
  /// In es, this message translates to:
  /// **'Descargas'**
  String get navActiveDownloads;

  /// No description provided for @wifiTitle.
  ///
  /// In es, this message translates to:
  /// **'Compartir vía WiFi'**
  String get wifiTitle;

  /// No description provided for @wifiTabSend.
  ///
  /// In es, this message translates to:
  /// **'Enviar'**
  String get wifiTabSend;

  /// No description provided for @wifiTabReceive.
  ///
  /// In es, this message translates to:
  /// **'Recibir'**
  String get wifiTabReceive;

  /// No description provided for @wifiNoFilesTitle.
  ///
  /// In es, this message translates to:
  /// **'Sin archivos seleccionados'**
  String get wifiNoFilesTitle;

  /// No description provided for @wifiNoFilesHint.
  ///
  /// In es, this message translates to:
  /// **'Ve a tu Biblioteca, mantén presionada una canción o video para activar la selección, marca lo que quieras enviar y toca el icono de WiFi.'**
  String get wifiNoFilesHint;

  /// No description provided for @wifiSendCount.
  ///
  /// In es, this message translates to:
  /// **'Enviar {count} archivo(s)'**
  String wifiSendCount(int count);

  /// No description provided for @wifiClear.
  ///
  /// In es, this message translates to:
  /// **'Limpiar'**
  String get wifiClear;

  /// No description provided for @wifiReceiverIp.
  ///
  /// In es, this message translates to:
  /// **'IP del receptor'**
  String get wifiReceiverIp;

  /// No description provided for @wifiReceiverIpHint.
  ///
  /// In es, this message translates to:
  /// **'Ej. 192.168.1.50'**
  String get wifiReceiverIpHint;

  /// No description provided for @wifiSend.
  ///
  /// In es, this message translates to:
  /// **'Enviar'**
  String get wifiSend;

  /// No description provided for @wifiSending.
  ///
  /// In es, this message translates to:
  /// **'Enviando'**
  String get wifiSending;

  /// No description provided for @wifiQueue.
  ///
  /// In es, this message translates to:
  /// **'Cola de envío'**
  String get wifiQueue;

  /// No description provided for @wifiCompleted.
  ///
  /// In es, this message translates to:
  /// **'{done} / {total} completados'**
  String wifiCompleted(int done, int total);

  /// No description provided for @wifiEnterIp.
  ///
  /// In es, this message translates to:
  /// **'Ingresa la IP del receptor.'**
  String get wifiEnterIp;

  /// No description provided for @wifiSendFinished.
  ///
  /// In es, this message translates to:
  /// **'Envío finalizado.'**
  String get wifiSendFinished;

  /// No description provided for @wifiSendError.
  ///
  /// In es, this message translates to:
  /// **'Error en el envío: {error}'**
  String wifiSendError(String error);

  /// No description provided for @wifiReady.
  ///
  /// In es, this message translates to:
  /// **'Listo para recibir archivos'**
  String get wifiReady;

  /// No description provided for @wifiEnterIpOnSender.
  ///
  /// In es, this message translates to:
  /// **'Ingresa esta IP en la app Sonero del otro dispositivo.'**
  String get wifiEnterIpOnSender;

  /// No description provided for @wifiOtherIps.
  ///
  /// In es, this message translates to:
  /// **'Otras redes: {ips}'**
  String wifiOtherIps(String ips);

  /// No description provided for @wifiOrOpenInBrowser.
  ///
  /// In es, this message translates to:
  /// **'¿Sin la app? Abre esto en el navegador del celular:'**
  String get wifiOrOpenInBrowser;

  /// No description provided for @wifiCopied.
  ///
  /// In es, this message translates to:
  /// **'Copiado al portapapeles.'**
  String get wifiCopied;

  /// No description provided for @wifiCopy.
  ///
  /// In es, this message translates to:
  /// **'Copiar'**
  String get wifiCopy;

  /// No description provided for @wifiReceiveOff.
  ///
  /// In es, this message translates to:
  /// **'Recepción desactivada'**
  String get wifiReceiveOff;

  /// No description provided for @wifiReceiveOffHint.
  ///
  /// In es, this message translates to:
  /// **'Activa la recepción para recibir música o videos desde otros dispositivos en la misma red WiFi.'**
  String get wifiReceiveOffHint;

  /// No description provided for @wifiStartReceiving.
  ///
  /// In es, this message translates to:
  /// **'Iniciar recepción'**
  String get wifiStartReceiving;

  /// No description provided for @wifiStopReceiving.
  ///
  /// In es, this message translates to:
  /// **'Detener recepción'**
  String get wifiStopReceiving;

  /// No description provided for @wifiStartError.
  ///
  /// In es, this message translates to:
  /// **'No se pudo iniciar la recepción: {error}'**
  String wifiStartError(String error);

  /// No description provided for @wifiReceivedList.
  ///
  /// In es, this message translates to:
  /// **'Recibidos / en progreso'**
  String get wifiReceivedList;

  /// No description provided for @wifiNoNetwork.
  ///
  /// In es, this message translates to:
  /// **'No se encontró una red WiFi o LAN. Conéctate a una red para compartir.'**
  String get wifiNoNetwork;

  /// No description provided for @wifiSameNetworkTip.
  ///
  /// In es, this message translates to:
  /// **'Ambos dispositivos deben estar en la misma red WiFi. Una VPN activa puede bloquear la conexión, y tu computadora puede pedir permiso para aceptar conexiones entrantes.'**
  String get wifiSameNetworkTip;

  /// No description provided for @wifiBackendUnavailable.
  ///
  /// In es, this message translates to:
  /// **'No hay conexión con el servidor de Sonero. Revisa que esté en ejecución.'**
  String get wifiBackendUnavailable;

  /// No description provided for @wifiStatusWaiting.
  ///
  /// In es, this message translates to:
  /// **'Esperando…'**
  String get wifiStatusWaiting;

  /// No description provided for @wifiStatusTransferring.
  ///
  /// In es, this message translates to:
  /// **'Transfiriendo… {pct}%'**
  String wifiStatusTransferring(int pct);

  /// No description provided for @wifiStatusDone.
  ///
  /// In es, this message translates to:
  /// **'Completado'**
  String get wifiStatusDone;

  /// No description provided for @wifiStatusDuplicate.
  ///
  /// In es, this message translates to:
  /// **'Ya existía, omitido'**
  String get wifiStatusDuplicate;

  /// No description provided for @wifiStatusFailed.
  ///
  /// In es, this message translates to:
  /// **'Falló: {error}'**
  String wifiStatusFailed(String error);

  /// No description provided for @wifiUnknownError.
  ///
  /// In es, this message translates to:
  /// **'Error desconocido'**
  String get wifiUnknownError;

  /// No description provided for @tvTab.
  ///
  /// In es, this message translates to:
  /// **'TV'**
  String get tvTab;

  /// No description provided for @tvIntro.
  ///
  /// In es, this message translates to:
  /// **'Escucha tu biblioteca en una Android TV conectada a la misma red WiFi. No necesita internet.'**
  String get tvIntro;

  /// No description provided for @tvEnable.
  ///
  /// In es, this message translates to:
  /// **'Activar Sonero TV'**
  String get tvEnable;

  /// No description provided for @tvActiveOn.
  ///
  /// In es, this message translates to:
  /// **'Activo en {ip}'**
  String tvActiveOn(String ip);

  /// No description provided for @tvOff.
  ///
  /// In es, this message translates to:
  /// **'Desactivado: ninguna TV puede conectarse.'**
  String get tvOff;

  /// No description provided for @tvPairButton.
  ///
  /// In es, this message translates to:
  /// **'Emparejar TV'**
  String get tvPairButton;

  /// No description provided for @tvPinTitle.
  ///
  /// In es, this message translates to:
  /// **'Escribe este PIN en la TV'**
  String get tvPinTitle;

  /// No description provided for @tvPinExpires.
  ///
  /// In es, this message translates to:
  /// **'Caduca en {seconds} s · sirve para una sola TV'**
  String tvPinExpires(int seconds);

  /// No description provided for @tvCancel.
  ///
  /// In es, this message translates to:
  /// **'Cancelar'**
  String get tvCancel;

  /// No description provided for @tvDevices.
  ///
  /// In es, this message translates to:
  /// **'TVs emparejadas'**
  String get tvDevices;

  /// No description provided for @tvNoDevices.
  ///
  /// In es, this message translates to:
  /// **'Todavía no hay TVs emparejadas.'**
  String get tvNoDevices;

  /// No description provided for @tvRevoke.
  ///
  /// In es, this message translates to:
  /// **'Quitar'**
  String get tvRevoke;

  /// No description provided for @tvLastSeen.
  ///
  /// In es, this message translates to:
  /// **'Última conexión: {date}'**
  String tvLastSeen(String date);

  /// No description provided for @tvNeverSeen.
  ///
  /// In es, this message translates to:
  /// **'Aún no se ha conectado'**
  String get tvNeverSeen;

  /// No description provided for @tvGetApp.
  ///
  /// In es, this message translates to:
  /// **'En la TV, instala y abre la app Sonero TV: encontrará esta computadora sola.'**
  String get tvGetApp;

  /// No description provided for @tvError.
  ///
  /// In es, this message translates to:
  /// **'Sonero TV: {error}'**
  String tvError(String error);

  /// No description provided for @tvNeedsServer.
  ///
  /// In es, this message translates to:
  /// **'Sonero TV necesita el servidor de Sonero en una computadora.'**
  String get tvNeedsServer;

  /// No description provided for @tvRemoteTitle.
  ///
  /// In es, this message translates to:
  /// **'Control desde el celular'**
  String get tvRemoteTitle;

  /// No description provided for @tvRemoteHint.
  ///
  /// In es, this message translates to:
  /// **'Abre esta dirección en el navegador del celular (misma red WiFi) y empareja con un PIN.'**
  String get tvRemoteHint;

  /// No description provided for @tvOnline.
  ///
  /// In es, this message translates to:
  /// **'Conectada'**
  String get tvOnline;

  /// No description provided for @tvKindRemote.
  ///
  /// In es, this message translates to:
  /// **'Control remoto'**
  String get tvKindRemote;

  /// No description provided for @tvNothingPlaying.
  ///
  /// In es, this message translates to:
  /// **'Nada en reproducción'**
  String get tvNothingPlaying;

  /// No description provided for @castToTv.
  ///
  /// In es, this message translates to:
  /// **'Reproducir en TV'**
  String get castToTv;

  /// No description provided for @castPickTv.
  ///
  /// In es, this message translates to:
  /// **'Elige una TV'**
  String get castPickTv;

  /// No description provided for @castNoTvs.
  ///
  /// In es, this message translates to:
  /// **'No hay ninguna TV conectada. Abre Sonero TV en el televisor y activa Sonero TV en Compartir → TV.'**
  String get castNoTvs;

  /// No description provided for @castSent.
  ///
  /// In es, this message translates to:
  /// **'Reproduciendo en {name}'**
  String castSent(String name);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es', 'ja'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'ja':
      return AppLocalizationsJa();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
