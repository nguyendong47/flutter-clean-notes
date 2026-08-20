import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'search_focus_request.g.dart';

@Riverpod(keepAlive: true)
class SearchFocusRequest extends _$SearchFocusRequest {
  @override
  int build() => 0;

  void requestFocus() => state++;
}
