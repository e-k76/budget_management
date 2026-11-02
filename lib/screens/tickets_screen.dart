import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../core/search.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../services/auth_service.dart';
import '../services/db_status.dart';
import '../widgets/sync_badge.dart';
import '../widgets/ui_helpers.dart';

/// Everyone can SEND a ticket; only an admin sees the tickets that were sent.
class TicketsPage extends StatelessWidget {
  const TicketsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AuthService>().currentUser?.isAdmin ?? false;
    return isAdmin ? const _AdminTickets() : const _SendTicketPage();
  }
}

// ----------------------------------------------------------------- sending

/// What a non-admin sees: just the form (their tickets are not listed back).
class _SendTicketPage extends StatelessWidget {
  const _SendTicketPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Align(
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('ثبت تیکت',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(
                    'خطا، مشکل یا پیشنهاد خود را بنویسید. تیکت فقط برای مدیر سیستم ارسال می‌شود و او آن را بررسی می‌کند.',
                    style: TextStyle(color: Theme.of(context).hintColor)),
                const SizedBox(height: 16),
                const Card(
                  child: Padding(padding: EdgeInsets.all(20), child: TicketForm()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TicketForm extends StatefulWidget {
  const TicketForm({super.key, this.onSent});

  /// Called after the ticket was saved (e.g. to close a dialog).
  final VoidCallback? onSent;

  @override
  State<TicketForm> createState() => _TicketFormState();
}

class _TicketFormState extends State<TicketForm> {
  final _key = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _message = TextEditingController();
  String _kind = 'bug';
  bool _busy = false;

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_key.currentState!.validate()) return;
    setState(() => _busy = true);
    final state = context.read<AppState>();
    final online = context.read<DbStatus>().db.online;
    try {
      await state.submitTicket(kind: _kind, subject: _subject.text, message: _message.text);
      if (!mounted) return;
      _subject.clear();
      _message.clear();
      showSnack(
          context,
          online
              ? 'تیکت شما ثبت شد و برای مدیر ارسال شد.'
              : 'تیکت ذخیره شد و پس از اتصال به سرور برای مدیر ارسال می‌شود.');
      widget.onSent?.call();
    } catch (e) {
      if (mounted) showSnack(context, '$e', error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _key,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _kind,
            decoration: const InputDecoration(labelText: 'نوع تیکت'),
            items: [
              for (final e in Ticket.kinds.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => setState(() => _kind = v ?? _kind),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _subject,
            maxLength: Ticket.maxSubject,
            decoration: const InputDecoration(labelText: 'موضوع'),
            validator: (v) => (v ?? '').trim().isEmpty ? 'موضوع را وارد کنید' : null,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _message,
            maxLength: Ticket.maxMessage,
            minLines: 5,
            maxLines: 10,
            decoration: const InputDecoration(
                labelText: 'شرح مشکل یا پیشنهاد', alignLabelWithHint: true),
            validator: (v) => (v ?? '').trim().isEmpty ? 'متن تیکت را وارد کنید' : null,
          ),
          const SizedBox(height: 14),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.icon(
              onPressed: _busy ? null : _send,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded),
              label: const Text('ارسال تیکت'),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- admin's list

Color ticketStatusColor(String status) => switch (status) {
      Ticket.done => AppTheme.income,
      Ticket.inProgress => AppTheme.seed,
      _ => AppTheme.expense,
    };

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status, this.label);
  final String status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = ticketStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(color: c, fontWeight: FontWeight.w700)),
    );
  }
}

class _AdminTickets extends StatefulWidget {
  const _AdminTickets();

  @override
  State<_AdminTickets> createState() => _AdminTicketsState();
}

class _AdminTicketsState extends State<_AdminTickets> {
  List<Ticket> _all = [];
  bool _loading = true;
  final _search = TextEditingController();
  String? _status; // null = all
  int _seenDataVersion = -1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    try {
      final rows = await state.tickets();
      if (mounted) setState(() => _all = rows);
    } catch (e) {
      if (mounted) showSnack(context, 'خطا در بارگذاری: $e', error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, '$e', error: true);
    }
  }

  List<Ticket> get _shown => _all.where((t) {
        if (_status != null && t.status != _status) return false;
        return matchesQuery([
          t.subject,
          t.message,
          t.createdByName ?? '',
          t.createdBy ?? '',
          t.kindLabel,
          formatJalaliDateTime(t.createdAt),
        ], _search.text);
      }).toList();

  Future<void> _open(Ticket t) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _TicketDialog(ticket: t),
    );
    if (changed == true) _load();
  }

  Future<void> _delete(Ticket t) async {
    final ok = await confirmDialog(context,
        title: 'حذف تیکت', message: 'تیکت «${t.subject}» حذف شود؟');
    if (ok) _guard(() => context.read<AppState>().deleteTicket(t));
  }

  @override
  Widget build(BuildContext context) {
    final dv = context.watch<DbStatus>().db.dataVersion;
    if (_seenDataVersion == -1) _seenDataVersion = dv;
    if (dv != _seenDataVersion) {
      // Shared DB changed (new ticket from another PC, or reconnect): reload quietly.
      _seenDataVersion = dv;
      WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _load() : null);
    }
    final list = _shown;
    final open = _all.where((t) => !t.isDone).length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('تیکت‌ها',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('ثبت تیکت جدید'),
                      content: SizedBox(
                        width: 520,
                        child: SingleChildScrollView(
                          child: TicketForm(onSent: () {
                            Navigator.pop(ctx);
                            _load();
                          }),
                        ),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.add_comment_outlined),
                  label: const Text('ثبت تیکت جدید'),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  tooltip: 'بروزرسانی',
                  onPressed: () async {
                    await refreshFromServer(context);
                    if (mounted) _load();
                  },
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 320,
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'جستجو (موضوع، متن، ثبت‌کننده)',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () => setState(_search.clear),
                            ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _status,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'وضعیت', isDense: true),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('همه')),
                      for (final e in Ticket.statuses.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) => setState(() => _status = v),
                  ),
                ),
                Text('${list.length} از ${_all.length} تیکت  •  $open مورد باز',
                    style: TextStyle(color: Theme.of(context).hintColor)),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _all.isEmpty
                        ? Center(
                            child: Text('هنوز تیکتی ثبت نشده است.',
                                style: TextStyle(color: Theme.of(context).hintColor)))
                        : list.isEmpty
                            ? const Center(child: Text('موردی یافت نشد.'))
                            : _table(list),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _table(List<Ticket> list) {
    final err = Theme.of(context).colorScheme.error;
    return PinnedTable(
      columns: const [
        PinnedColumn('ردیف', flex: 1, minWidth: 56),
        PinnedColumn('تاریخ ثبت', flex: 2, minWidth: 150),
        PinnedColumn('نوع', flex: 2, minWidth: 130),
        PinnedColumn('موضوع', flex: 5, minWidth: 240),
        PinnedColumn('ثبت‌کننده', flex: 2, minWidth: 140),
        PinnedColumn('وضعیت', flex: 2, minWidth: 130),
        PinnedColumn('عملیات', flex: 2, minWidth: 110),
      ],
      onRowTap: (i) => _open(list[i]),
      rows: [
        for (var i = 0; i < list.length; i++)
          [
            Text('${i + 1}'),
            Text(formatJalaliDateTime(list[i].createdAt)),
            Text(list[i].kindLabel),
            Text(list[i].subject,
                style: TextStyle(
                    fontWeight: list[i].isDone ? FontWeight.w400 : FontWeight.w700)),
            Text(list[i].createdByName ?? list[i].createdBy ?? '-'),
            _StatusChip(list[i].status, list[i].statusLabel),
            Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'مشاهده',
                icon: const Icon(Icons.visibility_outlined, size: 20),
                onPressed: () => _open(list[i]),
              ),
              IconButton(
                tooltip: 'حذف',
                icon: Icon(Icons.delete_outline, size: 20, color: err),
                onPressed: () => _delete(list[i]),
              ),
            ]),
          ],
      ],
    );
  }
}

class _TicketDialog extends StatefulWidget {
  const _TicketDialog({required this.ticket});
  final Ticket ticket;

  @override
  State<_TicketDialog> createState() => _TicketDialogState();
}

class _TicketDialogState extends State<_TicketDialog> {
  bool _busy = false;

  Future<void> _setStatus(String status) async {
    setState(() => _busy = true);
    try {
      await context.read<AppState>().setTicketStatus(widget.ticket, status);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showSnack(context, '$e', error: true);
      }
    }
  }

  Widget _line(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 90,
              child: Text(k, style: TextStyle(color: Theme.of(context).hintColor))),
          Expanded(child: SelectableText(v)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final t = widget.ticket;
    return AlertDialog(
      title: Row(children: [
        Expanded(child: Text(t.subject)),
        _StatusChip(t.status, t.statusLabel),
      ]),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _line('نوع', t.kindLabel),
              _line('ثبت‌کننده', '${t.createdByName ?? '-'} (${t.createdBy ?? '-'})'),
              _line('تاریخ ثبت', formatJalaliDateTime(t.createdAt)),
              if (t.updatedAt != null)
                _line('آخرین تغییر', '${formatJalaliDateTime(t.updatedAt)} — ${t.updatedBy ?? '-'}'),
              const Divider(height: 24),
              SelectableText(t.message),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: const Text('بستن')),
        for (final e in Ticket.statuses.entries)
          if (e.key != t.status)
            FilledButton.tonal(
              onPressed: _busy ? null : () => _setStatus(e.key),
              child: Text('علامت‌گذاری: ${e.value}'),
            ),
      ],
    );
  }
}
