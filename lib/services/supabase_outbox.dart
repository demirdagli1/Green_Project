import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'storage.dart';

enum OutboxItemStatus { pending, processing, completed, failed }

class OutboxItem {
  final String id;
  final String eventId;
  final String actionType;
  final Map<String, dynamic> payload;
  final int createdAtMs;
  int retryCount;
  String? lastError;
  OutboxItemStatus status;

  OutboxItem({
    required this.id,
    required this.eventId,
    required this.actionType,
    required this.payload,
    required this.createdAtMs,
    this.retryCount = 0,
    this.lastError,
    this.status = OutboxItemStatus.pending,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'eventId': eventId,
        'actionType': actionType,
        'payload': payload,
        'createdAtMs': createdAtMs,
        'retryCount': retryCount,
        'lastError': lastError,
        'status': status.name,
      };

  factory OutboxItem.fromJson(Map<String, dynamic> json) => OutboxItem(
        id: json['id'] as String,
        eventId: json['eventId'] as String? ?? json['id'] as String,
        actionType: json['actionType'] as String,
        payload: Map<String, dynamic>.from(json['payload'] as Map),
        createdAtMs: (json['createdAtMs'] as num).toInt(),
        retryCount: (json['retryCount'] as num?)?.toInt() ?? 0,
        lastError: json['lastError'] as String?,
        status: OutboxItemStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => OutboxItemStatus.pending,
        ),
      );
}

/// Çevrimdışı olay kuyruğu (Pending Outbox).
/// Ağ kesintisinde olayları yerel depolamada saklar ve idempotency garantisiyle yeniden iletir.
class SupabaseOutbox extends ChangeNotifier {
  static const String storageKey = 'supabase_outbox_queue_v1';
  final KeyValueStore storage;
  final List<OutboxItem> _items = [];

  SupabaseOutbox({required this.storage});

  List<OutboxItem> get items => List.unmodifiable(_items);
  List<OutboxItem> get pendingItems => _items
      .where((i) => i.status == OutboxItemStatus.pending || i.status == OutboxItemStatus.failed)
      .toList();
  int get pendingCount => pendingItems.length;

  Future<void> load() async {
    try {
      final raw = await storage.read(storageKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        _items.clear();
        for (final item in list) {
          _items.add(OutboxItem.fromJson(item as Map<String, dynamic>));
        }
      }
    } catch (e) {
      debugPrint('[Outbox] Yükleme hatası: $e');
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final jsonStr = jsonEncode(_items.map((i) => i.toJson()).toList());
      await storage.write(storageKey, jsonStr);
    } catch (e) {
      debugPrint('[Outbox] Kayıt hatası: $e');
    }
    notifyListeners();
  }

  Future<OutboxItem> enqueue({
    required String actionType,
    required Map<String, dynamic> payload,
    String? eventId,
  }) async {
    final eid = eventId ?? const Uuid().v4();
    final item = OutboxItem(
      id: const Uuid().v4(),
      eventId: eid,
      actionType: actionType,
      payload: payload,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    _items.add(item);
    await _persist();
    return item;
  }

  Future<void> markCompleted(String id) async {
    _items.removeWhere((i) => i.id == id);
    await _persist();
  }

  Future<void> markFailed(String id, String error) async {
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx >= 0) {
      _items[idx].retryCount++;
      _items[idx].lastError = error;
      _items[idx].status = OutboxItemStatus.failed;
      await _persist();
    }
  }

  Future<void> clear() async {
    _items.clear();
    await _persist();
  }
}
