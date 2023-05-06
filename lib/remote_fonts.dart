library remote_fonts;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;

import 'io_web_mock.dart' if (dart.library.io) 'io_mobile_desktop.dart';

/// Describes the remote font asset with the given [url] and optional
/// [sha256sum] to verify the cached font file.
/// If [sha256sum] is not provided, the font file will **never** be cached.
class RemoteFontAsset {
  /// The url of the remote font file.
  final String url;

  /// The sha256sum of the remote font file.
  final String? sha256sum;

  /// Creates a new [RemoteFontAsset] with the given [url] and optional
  /// [sha256sum].
  ///
  /// @param url The [url] of the remote font file.
  /// @param sha256sum The [sha256sum] of the remote font file.
  const RemoteFontAsset(this.url, [this.sha256sum]);

  Uri get _uri => Uri.parse(url);

  Future<Uint8List> get _remoteBytes async {
    final httpClient = http.Client();
    final bytes = (await httpClient.get(_uri)).bodyBytes;
    httpClient.close();
    return bytes;
  }

  /// Returns the font data as `Future<ByteData>`.
  /// If [cacheDirPath] is provided, the font file will be cached in the
  /// [cacheDirPath] directory and the [sha256sum] will be used as file name.
  ///
  /// @param cacheDirPath The path to the cache directory.
  /// @returns The font data as `Future<ByteData>`.
  Future<ByteData> getFont([FutureOr<String>? cacheDirPath]) async {
    assert((cacheDirPath == null && sha256sum == null) ||
        (cacheDirPath != null && sha256sum != null));
    FileCompat? localFile;
    if (cacheDirPath != null) {
      final localFilePath =
          path.join(await cacheDirPath, '$sha256sum${path.extension(url)}');
      localFile = FileCompat(localFilePath, sha256sum);
      final localBytes = await localFile.cachedBytes();
      if (localBytes != null) {
        return ByteData.view(localBytes.buffer);
      }
    }
    final remoteBytes = await _remoteBytes;
    if (localFile != null) {
      await localFile.cacheFile(remoteBytes);
    }
    return ByteData.view(remoteBytes.buffer);
  }
}

/// Describes the remote font with the given [family] name and [assets] list.
/// The [assets] list contains the font files for the given [family] name.
/// The [assets] list can contain multiple font files for different font
/// weights and styles.
/// The [cacheDirPath] is optional and will be used to cache the font files.
/// If [cacheDirPath] is not provided, the font files will **never** be cached.
/// The [cacheDirPath] can be provided for example by the
/// [path_provider](https://pub.dev/packages/path_provider) package.
class RemoteFont {
  /// The family name of the remote font.
  final String family;

  /// The list of remote font assets.
  final Iterable<RemoteFontAsset> assets;

  /// The path to the cache directory. Optional.
  /// If [cacheDirPath] is not provided, the font files will **never** be cached.
  final FutureOr<String>? cacheDirPath;
  bool _loaded = false;

  /// Creates a new [RemoteFont] with the given [family] name and [assets] list.
  /// The [assets] list contains the font files for the given [family] name.
  /// The [assets] list can contain multiple font files for different font
  /// weights and styles.
  /// The [cacheDirPath] is optional and will be used to cache the font files.
  /// If [cacheDirPath] is not provided, the font files will **never** be cached.
  /// The [cacheDirPath] can be provided for example by the
  /// [path_provider](https://pub.dev/packages/path_provider) package.
  ///
  /// @param family The family name of the remote font.
  /// @param assets The list of remote font assets.
  /// @param cacheDirPath The path to the cache directory. Optional.
  RemoteFont({required this.family, required this.assets, this.cacheDirPath});

  /// Returns the font data as `Iterable<Future<ByteData>>`.
  Iterable<Future<ByteData>> loadableFonts() {
    return assets.map((asset) => asset.getFont(cacheDirPath));
  }

  /// Loads the font data.
  Future<void> load() async {
    if (_loaded) {
      return;
    }
    _loaded = true;

    final fontLoader = FontLoader(family);
    for (final fontData in loadableFonts()) {
      fontLoader.addFont(fontData);
    }
    await fontLoader.load();
  }
}

/// Describes the remote fonts with the given [fonts] list.
/// The [fonts] list contains the remote fonts.
/// The [cacheDirPath] is optional and will be used to cache the font files.
/// If [cacheDirPath] is not provided, the font files will **never** be cached.
/// The [cacheDirPath] can be provided for example by the
/// [path_provider](https://pub.dev/packages/path_provider) package.
class RemoteFonts {
  /// The list of remote fonts.
  final Iterable<RemoteFont> fonts;

  /// The path to the cache directory. Optional.
  final FutureOr<String>? cacheDirPath;

  /// Creates a new [RemoteFonts] with the given [fonts] list.
  /// The [fonts] list contains the remote fonts.
  /// The [cacheDirPath] is optional and will be used to cache the font files.
  /// If [cacheDirPath] is not provided, the font files will **never** be cached.
  /// The [cacheDirPath] can be provided for example by the
  /// [path_provider](https://pub.dev/packages/path_provider) package.
  ///
  /// @param fonts The list of remote fonts.
  /// @param cacheDirPath The path to the cache directory. Optional.
  const RemoteFonts({required this.fonts, this.cacheDirPath});

  Future<void> _loadParallel() async {
    await Future.wait(fonts.map((font) => font.load()));
  }

  /// Load the fonts. If [parallel] is `true`, the fonts will be loaded
  /// in parallel. Otherwise the fonts will be loaded sequentially.
  Future<void> load([bool? parallel]) async {
    if (parallel == true) {
      return await _loadParallel();
    }
    for (final font in fonts) {
      await font.load();
    }
  }
}
