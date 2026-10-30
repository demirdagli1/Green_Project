import 'package:flutter/foundation.dart';

@immutable
sealed class LeaderboardRowItem<T> {
  const LeaderboardRowItem();
}

@immutable
class LeaderboardDataRow<T> extends LeaderboardRowItem<T> {
  final int rank; // 1-tabanlı sıralama numarası
  final T data;
  final bool isSelf;

  const LeaderboardDataRow({
    required this.rank,
    required this.data,
    this.isSelf = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LeaderboardDataRow<T> &&
          runtimeType == other.runtimeType &&
          rank == other.rank &&
          data == other.data &&
          isSelf == other.isSelf;

  @override
  int get hashCode => Object.hash(rank, data, isSelf);

  @override
  String toString() => 'LeaderboardDataRow(#$rank, $data, isSelf: $isSelf)';
}

@immutable
class LeaderboardEllipsisRow<T> extends LeaderboardRowItem<T> {
  const LeaderboardEllipsisRow();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is LeaderboardEllipsisRow<T>;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'LeaderboardEllipsisRow(…)';
}

/// Sıralama pencereleme algoritması:
/// İlk 10 + kullanıcının/klanının gerçek sırası etrafında bir üst / bir alt komşu.
/// Atlanan her aralık için tek bir '…' satırı.
/// Gerçek sıralama numarası (rank) korunur, satır mükerrerliği olmaz.
class LeaderboardWindow {
  LeaderboardWindow._();

  static List<LeaderboardRowItem<T>> build<T>({
    required List<T> items,
    bool Function(T item)? isSelf,
  }) {
    if (items.isEmpty) return const [];
    final n = items.length;
    final selfIdx = isSelf == null ? -1 : items.indexWhere(isSelf);

    final selected = <int>{};
    final topLimit = n < 10 ? n : 10;
    for (var i = 0; i < topLimit; i++) {
      selected.add(i);
    }

    if (selfIdx >= 0) {
      if (selfIdx - 1 >= 0) selected.add(selfIdx - 1);
      selected.add(selfIdx);
      if (selfIdx + 1 < n) selected.add(selfIdx + 1);
    }

    final sortedIndices = selected.toList()..sort();
    final result = <LeaderboardRowItem<T>>[];

    for (var i = 0; i < sortedIndices.length; i++) {
      final idx = sortedIndices[i];
      if (i > 0 && idx > sortedIndices[i - 1] + 1) {
        result.add(LeaderboardEllipsisRow<T>());
      }
      result.add(LeaderboardDataRow<T>(
        rank: idx + 1,
        data: items[idx],
        isSelf: selfIdx == idx,
      ));
    }

    if (sortedIndices.isNotEmpty && sortedIndices.last < n - 1) {
      result.add(LeaderboardEllipsisRow<T>());
    }

    return result;
  }
}
