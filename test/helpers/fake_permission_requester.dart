import 'package:flutter_clean_notes/features/notes/presentation/services/dictation_service.dart';

class FakePermissionRequester implements PermissionRequester {
  FakePermissionRequester({
    bool granted = true,
    DictationPermissionResult? result,
  }) : result =
           result ??
           (granted
               ? DictationPermissionResult.granted
               : DictationPermissionResult.denied);

  DictationPermissionResult result;
  int requestCalls = 0;

  bool get granted => result == DictationPermissionResult.granted;
  set granted(bool value) {
    result = value
        ? DictationPermissionResult.granted
        : DictationPermissionResult.denied;
  }

  @override
  Future<DictationPermissionResult> requestMicrophoneAndSpeech() async {
    requestCalls += 1;
    return result;
  }

  @override
  Future<DictationPermissionResult> requestMicrophone() async {
    requestCalls += 1;
    return result;
  }
}
