/// Сохранение/шаринг сгенерированного файла (например, xlsx-отчёта) —
/// реализация зависит от платформы (web/native), см. file_saver_web.dart /
/// file_saver_native.dart / file_saver_stub.dart и conditional import в
/// местах использования, по образцу app_notification_delegate.dart.
abstract class FileSaver {
  Future<void> saveAndShareFile(List<int> bytes, String filename);
}
