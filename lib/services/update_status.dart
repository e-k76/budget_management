import 'package:flutter/foundation.dart';

import 'update_service.dart';

/// What the UI knows about updates (so the menu button can show a "new version" dot).
class UpdateStatus extends ChangeNotifier {
  UpdateStatus(this.service);

  final UpdateService service;

  UpdateInfo? info;
  String? error;
  bool checking = false;

  bool get hasUpdate => info?.hasUpdate ?? false;

  Future<void> check() async {
    if (checking) return;
    checking = true;
    error = null;
    notifyListeners();
    try {
      info = await service.check();
    } on UpdateException catch (e) {
      info = null;
      error = e.message;
    } catch (e) {
      info = null;
      error = '$e';
    }
    checking = false;
    notifyListeners();
  }
}
