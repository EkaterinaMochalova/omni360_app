// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;
import 'dart:typed_data';

import 'file_saver.dart';

class WebFileSaver implements FileSaver {
  @override
  Future<void> saveAndShareFile(List<int> bytes, String filename) async {
    final blob = html.Blob([Uint8List.fromList(bytes)]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..click();
    html.Url.revokeObjectUrl(url);
  }
}

FileSaver createFileSaver() => WebFileSaver();
