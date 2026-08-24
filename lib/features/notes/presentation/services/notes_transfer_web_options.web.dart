import 'package:file_picker_web/file_picker_web.dart';

FilePickerWebOptions notesTransferWebOptions({
  required bool withData,
  required bool withReadStream,
}) {
  return FilePickerWebOptions(
    withData: withData,
    withReadStream: withReadStream,
  );
}
