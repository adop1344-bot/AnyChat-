import 'package:flutter_riverpod/flutter_riverpod.dart';

class PendingInput extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? value) => state = value;
}

final pendingInputProvider =
    NotifierProvider<PendingInput, String?>(PendingInput.new);
