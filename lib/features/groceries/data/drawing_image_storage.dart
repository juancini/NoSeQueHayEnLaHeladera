import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class DrawingImageStorage {
  DrawingImageStorage({Future<Directory> Function()? documentsDirectory})
      : _documentsDirectory = documentsDirectory;

  final Future<Directory> Function()? _documentsDirectory;

  static final _hashPattern = RegExp(r'^[0-9a-f]{64}$');

  Future<Directory> _directory() async {
    final documents = await (_documentsDirectory?.call() ??
        getApplicationDocumentsDirectory());
    final directory = Directory(path.join(documents.path, 'drawings'));
    await directory.create(recursive: true);
    return directory;
  }

  String? hashFromSource(String? imageSrc) {
    if (imageSrc == null) return null;
    final match =
        RegExp(r'^drawings/([0-9a-f]{64})\.png$').firstMatch(imageSrc);
    return match?.group(1);
  }

  Future<String?> savePng(Uint8List bytes) async {
    final hash = sha256.convert(bytes).toString();
    final directory = await _directory();
    final target = File(path.join(directory.path, '$hash.png'));
    if (await target.exists()) {
      final existing = await target.readAsBytes();
      if (sha256.convert(existing).toString() == hash) {
        return 'drawings/$hash.png';
      }
    }
    await _writeAtomically(target, bytes);
    return 'drawings/$hash.png';
  }

  Future<Set<String>> availableHashes() async {
    final directory = await _directory();
    final hashes = <String>{};
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final name = path.basename(entity.path);
      final hash =
          name.endsWith('.png') ? name.substring(0, name.length - 4) : '';
      if (!_hashPattern.hasMatch(hash)) continue;
      final bytes = await entity.readAsBytes();
      if (sha256.convert(bytes).toString() == hash) hashes.add(hash);
    }
    return hashes;
  }

  Future<Uint8List?> readHash(String hash) async {
    if (!_hashPattern.hasMatch(hash)) {
      throw ArgumentError.value(hash, 'hash', 'Invalid drawing hash');
    }
    final directory = await _directory();
    final file = File(path.join(directory.path, '$hash.png'));
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    if (sha256.convert(bytes).toString() != hash) return null;
    return bytes;
  }

  Future<File?> resolve(String? imageSrc) async {
    final hash = hashFromSource(imageSrc);
    if (hash == null) return null;
    final directory = await _directory();
    final file = File(path.join(directory.path, '$hash.png'));
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString() == hash ? file : null;
  }

  Future<void> storeDownloaded(String hash, Uint8List bytes) async {
    if (!_hashPattern.hasMatch(hash) ||
        sha256.convert(bytes).toString() != hash) {
      throw const FormatException('Drawing hash does not match its contents');
    }
    final directory = await _directory();
    await _writeAtomically(File(path.join(directory.path, '$hash.png')), bytes);
  }

  Future<void> delete(String? imageSrc) async {
    final hash = hashFromSource(imageSrc);
    if (hash == null) return;
    final directory = await _directory();
    final file = File(path.join(directory.path, '$hash.png'));
    if (await file.exists()) await file.delete();
  }

  Future<void> _writeAtomically(File target, Uint8List bytes) async {
    final temporary = File(
      '${target.path}.${DateTime.now().microsecondsSinceEpoch}.part',
    );
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(target.path);
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }
}
