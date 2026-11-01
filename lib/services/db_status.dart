import 'package:flutter/foundation.dart';

import 'database_service.dart';

/// ChangeNotifier view of [DatabaseService] for widgets (connection state,
/// pending changes, data-source version).
class DbStatus extends ChangeNotifier {
  DbStatus(this.db) {
    db.addListener(notifyListeners);
  }

  final DatabaseService db;

  @override
  void dispose() {
    db.removeListener(notifyListeners);
    super.dispose();
  }
}
