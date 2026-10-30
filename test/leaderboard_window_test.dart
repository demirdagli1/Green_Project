import 'package:flutter_test/flutter_test.dart';
import 'package:green_project/core/utils/leaderboard_window.dart';

void main() {
  group('LeaderboardWindow Algorithm & 120-Row Fixture Tests', () {
    test('boş liste boş sonuç döner', () {
      final res = LeaderboardWindow.build<String>(items: []);
      expect(res, isEmpty);
    });

    test('tek satırlık liste: ellipsis yok, gerçek rank #1', () {
      final res = LeaderboardWindow.build<String>(
        items: ['User1'],
        isSelf: (u) => u == 'User1',
      );
      expect(res.length, 1);
      expect(res[0], isA<LeaderboardDataRow<String>>());
      final row = res[0] as LeaderboardDataRow<String>;
      expect(row.rank, 1);
      expect(row.data, 'User1');
      expect(row.isSelf, true);
    });

    test('5 satırlık liste: 10\'dan az olduğu için tümü gösterilir, ellipsis yok', () {
      final items = List.generate(5, (i) => 'U${i + 1}');
      final res = LeaderboardWindow.build<String>(
        items: items,
        isSelf: (u) => u == 'U3',
      );
      expect(res.length, 5);
      expect(res.every((r) => r is LeaderboardDataRow<String>), true);
      final ranks = res.map((r) => (r as LeaderboardDataRow<String>).rank).toList();
      expect(ranks, [1, 2, 3, 4, 5]);
    });

    test('10 satırlık liste: tam 10 satır, ellipsis yok', () {
      final items = List.generate(10, (i) => 'U${i + 1}');
      final res = LeaderboardWindow.build<String>(
        items: items,
        isSelf: (u) => u == 'U10',
      );
      expect(res.length, 10);
      expect(res.every((r) => r is LeaderboardDataRow<String>), true);
      expect((res[9] as LeaderboardDataRow<String>).isSelf, true);
    });

    test('11 satırlık liste, kullanıcı #11: ilk 10 + 11 (bitişik, ellipsis yok)', () {
      final items = List.generate(11, (i) => 'U${i + 1}');
      final res = LeaderboardWindow.build<String>(
        items: items,
        isSelf: (u) => u == 'U11',
      );
      expect(res.length, 11);
      expect(res.every((r) => r is LeaderboardDataRow<String>), true);
      final ranks = res.map((r) => (r as LeaderboardDataRow<String>).rank).toList();
      expect(ranks, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
    });

    // 120 Satırlık Test Fixture
    final fixture120 = List.generate(120, (i) => 'User_${i + 1}');

    test('120 satır: kullanıcı ilk 10 içinde (#1) -> 1..10 ardından tek trailing ellipsis', () {
      final res = LeaderboardWindow.build<String>(
        items: fixture120,
        isSelf: (u) => u == 'User_1',
      );
      // 10 data row + 1 ellipsis = 11
      expect(res.length, 11);
      for (var i = 0; i < 10; i++) {
        final row = res[i] as LeaderboardDataRow<String>;
        expect(row.rank, i + 1);
        expect(row.isSelf, i == 0);
      }
      expect(res[10], isA<LeaderboardEllipsisRow<String>>());
    });

    test('120 satır: kullanıcı #10 -> komşuları (9, 10, 11) bitişik, 1..11 ardından tek trailing ellipsis', () {
      final res = LeaderboardWindow.build<String>(
        items: fixture120,
        isSelf: (u) => u == 'User_10',
      );
      // 1..11 (11 rows) + 1 ellipsis = 12
      expect(res.length, 12);
      for (var i = 0; i < 11; i++) {
        final row = res[i] as LeaderboardDataRow<String>;
        expect(row.rank, i + 1);
        expect(row.isSelf, i == 9);
      }
      expect(res[11], isA<LeaderboardEllipsisRow<String>>());
    });

    test('120 satır: kullanıcı #11 -> komşuları (10, 11, 12) bitişik, 1..12 ardından tek trailing ellipsis', () {
      final res = LeaderboardWindow.build<String>(
        items: fixture120,
        isSelf: (u) => u == 'User_11',
      );
      // 1..12 (12 rows) + 1 ellipsis = 13
      expect(res.length, 13);
      for (var i = 0; i < 12; i++) {
        final row = res[i] as LeaderboardDataRow<String>;
        expect(row.rank, i + 1);
        expect(row.isSelf, i == 10);
      }
      expect(res[12], isA<LeaderboardEllipsisRow<String>>());
    });

    test('120 satır: kullanıcı #106 (Şartnamedeki örnek: 1..10 … 105, 106(Sen), 107 …)', () {
      final res = LeaderboardWindow.build<String>(
        items: fixture120,
        isSelf: (u) => u == 'User_106',
      );
      // 1..10 (10) + ellipsis (1) + 105,106,107 (3) + ellipsis (1) = 15
      expect(res.length, 15);

      // İlk 10
      for (var i = 0; i < 10; i++) {
        final row = res[i] as LeaderboardDataRow<String>;
        expect(row.rank, i + 1);
        expect(row.isSelf, false);
      }

      // İlk aralık tek ellipsis
      expect(res[10], isA<LeaderboardEllipsisRow<String>>());

      // 105, 106 (Sen), 107
      final row105 = res[11] as LeaderboardDataRow<String>;
      expect(row105.rank, 105);
      expect(row105.isSelf, false);

      final row106 = res[12] as LeaderboardDataRow<String>;
      expect(row106.rank, 106);
      expect(row106.isSelf, true);
      expect(row106.data, 'User_106');

      final row107 = res[13] as LeaderboardDataRow<String>;
      expect(row107.rank, 107);
      expect(row107.isSelf, false);

      // Son aralık tek ellipsis
      expect(res[14], isA<LeaderboardEllipsisRow<String>>());
    });

    test('120 satır: kullanıcı son sırada (#120) -> 1..10 … 119, 120 (sonrasında ellipsis yok)', () {
      final res = LeaderboardWindow.build<String>(
        items: fixture120,
        isSelf: (u) => u == 'User_120',
      );
      // 1..10 (10) + ellipsis (1) + 119, 120 (2) = 13
      expect(res.length, 13);
      for (var i = 0; i < 10; i++) {
        final row = res[i] as LeaderboardDataRow<String>;
        expect(row.rank, i + 1);
      }
      expect(res[10], isA<LeaderboardEllipsisRow<String>>());
      final row119 = res[11] as LeaderboardDataRow<String>;
      expect(row119.rank, 119);
      final row120 = res[12] as LeaderboardDataRow<String>;
      expect(row120.rank, 120);
      expect(row120.isSelf, true);
      // Bitişte başka eleman olmadığı için trailing ellipsis olmamalıdır
      expect(res.last, isA<LeaderboardDataRow<String>>());
    });

    test('120 satır: kullanıcı kaydı yok / sıralama dışı -> ilk 10 + trailing ellipsis, uydurma veri yok', () {
      final res = LeaderboardWindow.build<String>(
        items: fixture120,
        isSelf: (u) => false,
      );
      expect(res.length, 11);
      for (var i = 0; i < 10; i++) {
        final row = res[i] as LeaderboardDataRow<String>;
        expect(row.rank, i + 1);
        expect(row.isSelf, false);
      }
      expect(res[10], isA<LeaderboardEllipsisRow<String>>());
    });

    test('aynı satır mükerrer oluşmaz, gerçek rank sırası kesinlikle bozulmaz', () {
      final res = LeaderboardWindow.build<String>(
        items: fixture120,
        isSelf: (u) => u == 'User_106',
      );
      final seenRanks = <int>{};
      for (final item in res) {
        if (item is LeaderboardDataRow<String>) {
          expect(seenRanks.contains(item.rank), false, reason: 'Rank #${item.rank} mükerrer olamaz.');
          seenRanks.add(item.rank);
        }
      }
      // Rütbeler sıralı mı?
      final rankList = seenRanks.toList();
      for (var i = 1; i < rankList.length; i++) {
        expect(rankList[i] > rankList[i - 1], true);
      }
    });
  });
}
