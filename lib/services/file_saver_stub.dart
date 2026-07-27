import 'file_saver.dart';

class StubFileSaver implements FileSaver {
  @override
  Future<void> saveAndShareFile(List<int> bytes, String filename) async {
    throw UnsupportedError('Экспорт файлов не поддерживается на этой платформе');
  }
}

FileSaver createFileSaver() => StubFileSaver();
