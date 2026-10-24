import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// One database write, described as data so it can be stored on this PC and replayed later.
/// [id] makes replays idempotent (the DB records applied ids), so a write that actually
/// reached the share just before the link dropped is never applied twice.
class PendingOp {
  PendingOp({required this.id, required this.type, required this.data, required this.at});

  factory PendingOp.create(String type, Map<String, Object?> data) => PendingOp(
        id: '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 31)}',
        type: type,
        data: data,
        at: DateTime.now().toIso8601String(),
      );

  factory PendingOp.fromJson(Map<String, dynamic> j) => PendingOp(
        id: j['id'] as String,
        type: j['type'] as String,
        data: Map<String, Object?>.from(j['data'] as Map),
        at: j['at'] as String,
      );

  final String id;
  final String type;
  final Map<String, Object?> data;
  final String at;

  Map<String, Object?> toJson() => {'id': id, 'type': type, 'data': data, 'at': at};
}

/// FIFO list of writes not yet applied to the shared DB, persisted to a local JSON file
/// (survives app restarts / crashes). Order is preserved so edits replay after the adds they depend on.
class PendingQueue {
  static String? pathOverride;

  final List<PendingOp> _ops = [];

  List<PendingOp> get ops => List.unmodifiable(_ops);
  int get length => _ops.length;

  File get _file {
    final base = pathOverride ??
        '${Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path}\\budget_management\\pending_ops.json';
    return File(base);
  }

  Future<void> load() async {
    _ops.clear();
    try {
      if (await _file.exists()) {
        final list = jsonDecode(await _file.readAsString()) as List;
        _ops.addAll(list.map((e) => PendingOp.fromJson(Map<String, dynamic>.from(e as Map))));
      }
    } catch (_) {
      // unreadable queue file: keep it for inspection, start empty
    }
  }

  Future<void> add(PendingOp op) async {
    _ops.add(op);
    await _save();
  }

  Future<void> remove(String id) async {
    _ops.removeWhere((o) => o.id == id);
    await _save();
  }

  Future<void> _save() async {
    await _file.parent.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode(_ops.map((o) => o.toJson()).toList()), flush: true);
    await tmp.rename(_file.path); // atomic replace: never leaves a half-written queue
  }
}

/// True when the failure means "can't reach / use the shared DB right now" (worth retrying),
/// as opposed to a real rejection such as a UNIQUE violation (retrying can never succeed).
/// Classified by SQLite's primary result code, not by message text (messages echo user data).
bool isConnectionError(Object e) {
  if (e is FileSystemException) return true;
  final s = e.toString();
  final m = RegExp(r'sqlite_error: (\d+)').firstMatch(s);
  if (m != null) {
    // BUSY, LOCKED, READONLY, IOERR, CORRUPT, FULL, CANTOPEN, NOTADB
    const retryable = {5, 6, 8, 10, 11, 13, 14, 26};
    return retryable.contains(int.parse(m[1]!) & 0xFF);
  }
  final head = s.split('\n').first.toLowerCase();
  return head.contains('database_closed') || head.contains('unable to open') || head.contains('cannot open');
}
