/// Something the user has started but not saved (e.g. a bill with items on it).
class PendingWork {
  const PendingWork({required this.where, required this.message, required this.page});
  final String where; // screen name, e.g. "New Bill"
  final String message; // what to finish, e.g. "A bill with 3 medicines is not saved yet."
  final int page; // Nav page index to go to
}

/// Screens with unsaved, half-filled work register a check here, so the app can
/// ask the user to finish it before it restarts (e.g. to install an update).
class UnsavedWork {
  static final _checks = <Object, PendingWork? Function()>{};

  static void register(Object owner, PendingWork? Function() check) => _checks[owner] = check;
  static void unregister(Object owner) => _checks.remove(owner);

  static List<PendingWork> pending() => [for (final c in _checks.values) ?c()];
}
