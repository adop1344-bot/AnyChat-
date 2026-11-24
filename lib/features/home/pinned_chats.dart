import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Chats the user pinned to the top of the drawer. Kept in preferences so it
/// needs no database migration.
class PinnedChats extends AsyncNotifier<List<int>> {
  static const String _key = 'pinned_chats';

  @override
  Future<List<int>> build() async {
    final prefs = await SharedPreferences.getInstance();
    return <int>[
      for (final String raw in prefs.getStringList(_key) ?? const <String>[])
        if (int.tryParse(raw) != null) int.parse(raw),
    ];
  }

  Future<void> toggle(int chatId) async {
    final List<int> current = state.value ?? const <int>[];
    final List<int> next = current.contains(chatId)
        ? (<int>[...current]..remove(chatId))
        : <int>[chatId, ...current];
    state = AsyncData(next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      <String>[for (final int id in next) '$id'],
    );
  }
}

final AsyncNotifierProvider<PinnedChats, List<int>> pinnedChatsProvider =
    AsyncNotifierProvider<PinnedChats, List<int>>(PinnedChats.new);
