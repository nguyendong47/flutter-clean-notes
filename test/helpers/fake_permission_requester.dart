import 'package:flutter_clean_notes/features/notes/presentation/services/dictation_service.dart';

class FakePermissionRequester implements PermissionRequester {
  FakePermissionRequester({this.granted = true});

  bool granted;
  int requestCalls = 0;

  @override
  Future<bool> requestMicrophoneAndSpeech() async {
    requestCalls += 1;
    return granted;
  }
}
