import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'storage.dart';

enum OutboxItemStatus { pending, processing, completed, failed, quarantined }

class OutboxItem {
  final String id;
  final String eventId;
  final String actionType;
  final Map<String, dynamic> payload;
  final int createdAtMs;
  int retryCount;
  String? lastError;
  OutboxItemStatus status;
  int? nextRetryAtMs;

  OutboxItem({
    required this.id,
    required this.eventId,
    required this.actionType,
    required this.payload,
    required this.createdAtMs,
    this.retryCount = 0,
    this.lastError,
    this.status = OutboxItemStatus.pending,
    this.nextRetryAtMs,
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
        'nextRetryAtMs': nextRetryAtMs,
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
        nextRetryAtMs: (json['nextRetryAtMs'] as num?)?.toInt(),
      );
}

/// Çevrimdışı olay kuyruğu (Pending Outbox).
/// Ağ kesintisinde olayları yerel depolamada saklar, üstel geri çekilme (exponential backoff)
/// ve zehirli paket karantinası ile Head-of-Line kilitlenmelerini önler.
class SupabaseOutbox extends ChangeNotifier {
  static const String storageKey = 'supabase_outbox_queue_v1';
  static const int maxRetryLimit = 5;

  final KeyValueStore storage;
  final List<OutboxItem> _items = [];

  SupabaseOutbox({required this.storage});

  List<OutboxItem> get items => List.unmodifiable(_items);

  /// İşlenmeye hazır bekleyen öğeler (Karantinadakiler hariç ve backoff süresi dolmuşlar)
  List<OutboxItem> get pendingItems {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _items.where((i) {
      if (i.status == OutboxItemStatus.pending) return true;
      if (i.status == OutboxItemStatus.failed) {
        if (i.nextRetryAtMs == null || i.nextRetryAtMs! <= now) {
          return true;
        }
      }
      return false;
    }).toList();
  }

  List<OutboxItem> get quarantinedItems =>
      _items.where((i) => i.status == OutboxItemStatus.quarantined).toList();

  int get pendingCount => _items.where((i) => i.status == OutboxItemStatus.pending || i.status == OutboxItemStatus.failed).length;
  int get quarantinedCount => quarantinedItems.length;

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

  /// Kalıcı / şema / parametre hatası olup olmadığını tespit eder.
  static bool isPermanentError(String error) {
    final lower = error.toLowerCase();
    return lower.contains('geçersiz') ||
        lower.contains('bulunamadı') ||
        lower.contains('reddedildi') ||
        lower.contains('violates') ||
        lower.contains('permission denied') ||
        lower.contains('syntax error') ||
        lower.contains('not found');
  }

  Future<void> markFailed(String id, String error, {bool forceQuarantine = false}) async {
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx >= 0) {
      final item = _items[idx];
      item.retryCount++;
      item.lastError = error;

      if (forceQuarantine || item.retryCount >= maxRetryLimit || isPermanentError(error)) {
        // Zehirli paket (Poison Pill): Kuyruğu kilitlememesi için karantinaya al!
        item.status = OutboxItemStatus.quarantined;
        debugPrint('[Outbox] Olay karantinaya alındı ($id - ${item.actionType}): $error');
      } else {
        item.status = OutboxItemStatus.failed;
        // İlk yeniden deneme hemen yapılabilir; tekrarlanan hatalarda üstel geri çekilme (2s, 4s, 8s, max 60s)
        if (item.retryCount <= 1) {
          item.nextRetryAtMs = null;
        } else {
          final backoffSec = (1 << item.retryCount).clamp(2, 60);
          item.nextRetryAtMs = DateTime.now().millisecondsSinceEpoch + (backoffSec * 1000);
        }
      }
      await _persist();
    }
  }

  Future<void> clear() async {
    _items.clear();
    await _persist();
  }
}
