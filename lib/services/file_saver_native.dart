import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

import 'file_saver.dart';

class NativeFileSaver implements FileSaver {
  @override
  Future<void> saveAndShareFile(List<int> bytes, String filename) async {
    final file = XFile.fromData(
      Uint8List.fromList(bytes),
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    await SharePlus.instance.share(
      ShareParams(files: [file], fileNameOverrides: [filename]),
    );
  }
}

FileSaver createFileSaver() => NativeFileSaver();
