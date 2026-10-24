import 'dart:typed_data';

void savePending(String user, String? value) {}
String? readPending(String user) => null;
void downloadBytes(Uint8List bytes, String filename) =>
    throw UnsupportedError('Скачивание доступно в web-версии');
