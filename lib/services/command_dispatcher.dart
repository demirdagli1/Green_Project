import 'dart:convert';

import 'app_store.dart';
import 'auto_motion_engine.dart';

class CommandResult {
  final bool ok;
  final String message;
  final bool duplicate;
  final Map<String, dynamic> data;

  const CommandResult({
    required this.ok,
    required this.message,
    this.duplicate = false,
    this.data = const {},
  });

  Map<String, dynamic> toJson() => {
        'ok': ok,
        'message': message,
        'duplicate': duplicate,
        'data': data,
      };
}

class _IdempotentEntry {
  final String cmd;
  final String paramsDigest;
  final CommandResult result;
  const _IdempotentEntry(this.cmd, this.paramsDigest, this.result);
}

/// Ortak komut yürütücüsü: Hem mobil Admin panelinden hem PC GM panelinden
/// gelen eylemleri tek noktadan, sayısal sınır kontrolleriyle ve idempotent olarak işler.
class CommandDispatcher {
  final AppStore store;
  final Map<String, _IdempotentEntry> _idempotentCache = {};
  static const int _maxCache = 200;

  CommandDispatcher(this.store);

  CommandResult dispatch(
    String cmd,
    Map<String, dynamic> params, {
    String? idempotencyKey,
  }) {
    final currentDigest = jsonEncode(params);

    if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
      if (_idempotentCache.containsKey(idempotencyKey)) {
        final cached = _idempotentCache[idempotencyKey]!;
        // Aynı key ile farklı payload/komut gelirse çakışma (conflict) reddedilir!
        if (cached.cmd != cmd || cached.paramsDigest != currentDigest) {
          return const CommandResult(
            ok: false,
            message: 'İdempotency çakışması: Aynı anahtar farklı bir komut veya parametrelerle yeniden kullanılamaz.',
          );
        }
        return CommandResult(
          ok: cached.result.ok,
          message: '[YİNELENEN İSTEK / IDEMPOTENT] ${cached.result.message}',
          duplicate: true,
          data: cached.result.data,
        );
      }
    }

    final res = _execute(cmd, params);
    if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
      _idempotentCache[idempotencyKey] = _IdempotentEntry(cmd, currentDigest, res);
      if (_idempotentCache.length > _maxCache) {
        _idempotentCache.remove(_idempotentCache.keys.first);
      }
    }
    return res;
  }

  CommandResult _execute(String cmd, Map<String, dynamic> p) {
    switch (cmd) {
      case 'add_steps':
        final raw = p['count'];
        if (raw is! num) return const CommandResult(ok: false, message: 'Geçersiz adım sayısı.');
        final n = raw.toInt();
        if (n <= 0 || n > 500000) {
          return const CommandResult(ok: false, message: 'Geçersiz veya sınır dışı adım sayısı (1 - 500.000 arası olmalı).');
        }
        final r = store.demoAddSteps(n);
        return CommandResult(ok: r.ok, message: r.message, data: {
          'added': n,
          'todaySteps': store.me?.todaySteps,
        });

      case 'set_steps':
        final raw = p['total'];
        if (raw is! num) return const CommandResult(ok: false, message: 'Geçersiz adım sayısı.');
        final total = raw.toInt();
        if (total < 0 || total > 500000) {
          return const CommandResult(ok: false, message: 'Geçersiz veya sınır dışı adım sayısı (0 - 500.000 arası olmalı).');
        }
        if (store.me == null) return const CommandResult(ok: false, message: 'Profil yok.');
        final cur = store.me!.todaySteps;
        final diff = total - cur;
        if (diff > 0) {
          final r = store.demoAddSteps(diff);
          return CommandResult(ok: r.ok, message: 'Adım $total yapıldı (+${diff} eklendi).', data: {'todaySteps': store.me?.todaySteps});
        } else {
          store.me = store.me!.copyWith(todaySteps: total);
          store.commitDirect();
          return CommandResult(ok: true, message: 'Adım $total olarak ayarlandı.', data: {'todaySteps': total});
        }

      case 'add_streak':
        final raw = p['days'];
        if (raw is! num) return const CommandResult(ok: false, message: 'Geçersiz gün sayısı.');
        final days = raw.toInt();
        if (days <= 0 || days > 365) {
          return const CommandResult(ok: false, message: 'Geçersiz streak artışı (1 - 365 gün arası olmalı).');
        }
        if (store.me == null) return const CommandResult(ok: false, message: 'Profil yok.');
        final next = (store.me!.streakDays + days).clamp(0, 9999);
        store.me = store.me!.copyWith(streakDays: next);
        store.commitDirect();
        return CommandResult(ok: true, message: '+$days gün streak eklendi ($next gün).', data: {'streakDays': next});

      case 'set_streak':
        final raw = p['days'];
        if (raw is! num) return const CommandResult(ok: false, message: 'Geçersiz streak değeri.');
        final days = raw.toInt();
        if (days < 0 || days > 3650) {
          return const CommandResult(ok: false, message: 'Geçersiz streak değeri (0 - 3650 gün arası olmalı).');
        }
        if (store.me == null) return const CommandResult(ok: false, message: 'Profil yok.');
        store.me = store.me!.copyWith(streakDays: days);
        store.commitDirect();
        return CommandResult(ok: true, message: 'Streak $days gün olarak ayarlandı.', data: {'streakDays': days});

      case 'add_gold':
        final raw = p['amount'];
        if (raw is! num) return const CommandResult(ok: false, message: 'Geçersiz altın miktarı.');
        final n = raw.toInt();
        if (n <= 0 || n > 100000) {
          return const CommandResult(ok: false, message: 'Geçersiz altın miktarı (1 - 100.000 arası olmalı).');
        }
        final r = store.demoGrantGold(n);
        return CommandResult(ok: r.ok, message: r.message, data: {'goldCoins': store.me?.goldCoins});

      case 'set_gold':
        final raw = p['total'];
        if (raw is! num) return const CommandResult(ok: false, message: 'Geçersiz altın miktarı.');
        final total = raw.toInt();
        if (total < 0 || total > 1000000) {
          return const CommandResult(ok: false, message: 'Geçersiz altın miktarı (0 - 1.000.000 arası olmalı).');
        }
        if (store.me == null) return const CommandResult(ok: false, message: 'Profil yok.');
        store.me = store.me!.copyWith(goldCoins: total);
        store.commitDirect();
        return CommandResult(ok: true, message: 'Altın $total olarak ayarlandı.', data: {'goldCoins': total});

      case 'scan_transit':
        final payload = p['payload'] as String? ?? 'YESILADIM://TRANSIT/TRB-BLD-101';
        final source = p['source'] as String? ?? 'GM_PANEL';
        final r = store.scanTransit(payload, source: source);
        return CommandResult(ok: r.ok, message: r.message, data: {'points': r.points, 'co2Kg': r.co2Kg});

      case 'evaluate_vehicle':
        final rawSpeed = p['avgSpeedKmh'];
        final rawDist = p['distanceKm'];
        final rawSteps = p['stepDelta'];
        if ((rawSpeed != null && rawSpeed is! num) || (rawDist != null && rawDist is! num) || (rawSteps != null && rawSteps is! num)) {
          return const CommandResult(ok: false, message: 'Geçersiz araç parametreleri.');
        }
        final speed = (rawSpeed as num?)?.toDouble() ?? 68.0;
        final dist = (rawDist as num?)?.toDouble() ?? 8.5;
        final steps = (rawSteps as num?)?.toInt() ?? 0;
        if (speed.isNaN || speed.isInfinite || speed < 0 || speed > 300 ||
            dist.isNaN || dist.isInfinite || dist <= 0 || dist > 2000 ||
            steps < 0 || steps > 100000) {
          return const CommandResult(ok: false, message: 'Sınır dışı araç parametreleri (hız 0-300, mesafe 0.1-2000, adım 0-100k).');
        }
        final ignoreExemption = p['ignoreTransitExemption'] as bool? ?? false;
        final tripId = p['tripId'] as String? ?? 'gm_taxi_${DateTime.now().microsecondsSinceEpoch}';
        final r = store.evaluateVehicle(
          tripId: tripId,
          avgSpeedKmh: speed,
          distanceKm: dist,
          stepDelta: steps,
          demo: true,
          ignoreTransitExemption: ignoreExemption,
        );
        return CommandResult(ok: r.ok, message: r.message, data: {'wastedCo2': r.co2Kg});

      case 'classify_transport':
        final dist = (p['distanceKm'] as num?)?.toDouble() ?? 5.0;
        final avgSpeed = (p['avgSpeedKmh'] as num?)?.toDouble() ?? 28.0;
        final maxSpeed = (p['maxSpeedKmh'] as num?)?.toDouble() ?? 45.0;
        final cadence = (p['stepCadenceSpm'] as num?)?.toInt() ?? 5;
        final accelVar = (p['accelVariance'] as num?)?.toDouble() ?? 0.15;
        final hasQrNfc = p['hasNfcOrQrScan'] as bool? ?? false;
        final isReliable = p['isGpsReliable'] as bool? ?? true;
        final accuracy = (p['gpsAccuracyMeters'] as num?)?.toDouble() ?? 10.0;
        final demo = p['demo'] as bool? ?? true;

        final res = store.evaluateTransportClassification(
          distanceKm: dist,
          avgSpeedKmh: avgSpeed,
          maxSpeedKmh: maxSpeed,
          stepCadenceSpm: cadence,
          accelVariance: accelVar,
          hasNfcOrQrScan: hasQrNfc,
          isGpsReliable: isReliable,
          gpsAccuracyMeters: accuracy,
          demo: demo,
        );
        return CommandResult(
          ok: true,
          message: res.explanation,
          data: res.toJson(),
        );

      case 'evaluate_bike':
        final rawDist = p['distanceKm'];
        final rawMax = p['maxSpeedKmh'];
        final rawAvg = p['avgSpeedKmh'];
        if ((rawDist != null && rawDist is! num) || (rawMax != null && rawMax is! num) || (rawAvg != null && rawAvg is! num)) {
          return const CommandResult(ok: false, message: 'Geçersiz bisiklet parametreleri.');
        }
        final dist = (rawDist as num?)?.toDouble() ?? 5.0;
        final maxSpeed = (rawMax as num?)?.toDouble() ?? 72.0;
        final avgSpeed = (rawAvg as num?)?.toDouble() ?? 40.0;
        final fastVar = (p['fastAccelVariance'] as num?)?.toDouble();
        if (dist.isNaN || dist.isInfinite || dist <= 0 || dist > 1000 ||
            maxSpeed.isNaN || maxSpeed.isInfinite || maxSpeed < 0 || maxSpeed > 200 ||
            avgSpeed.isNaN || avgSpeed.isInfinite || avgSpeed < 0 || avgSpeed > 150) {
          return const CommandResult(ok: false, message: 'Sınır dışı bisiklet parametreleri.');
        }
        final tripId = p['tripId'] as String? ?? 'gm_bike_${DateTime.now().microsecondsSinceEpoch}';
        final r = store.evaluateBike(
          tripId: tripId,
          distanceKm: dist,
          maxSpeedKmh: maxSpeed,
          avgSpeedKmh: avgSpeed,
          fastAccelVariance: fastVar,
          demo: true,
        );
        return CommandResult(ok: r.ok, message: r.message, data: {'points': r.points, 'co2Kg': r.co2Kg});

      case 'settle_week':
        final week = p['weekId'] as String? ?? store.weekId;
        final ok = store.settleWeek(week);
        return CommandResult(
          ok: ok,
          message: ok ? 'Hafta kapandı; puanlar altına dönüştürüldü.' : 'Bu hafta zaten kapatıldı veya geçersiz hafta ID.',
          data: {'currentWeek': store.weekId},
        );

      case 'notify':
        final title = (p['title'] as String?)?.trim() ?? 'Yeşil Adım';
        final body = (p['body'] as String?)?.trim() ?? 'Test bildirimi';
        if (body.isEmpty) return const CommandResult(ok: false, message: 'Bildirim metni boş olamaz.');
        store.demoNotify(title, body);
        return CommandResult(ok: true, message: 'Bildirim gönderildi.', data: {'title': title, 'body': body});

      case 'flush_pending_steps':
        final r = store.flushPendingStepsWindow();
        return CommandResult(ok: r.ok, message: r.message);

      case 'reset_shame_quota':
        store.resetShameQuota();
        return const CommandResult(ok: true, message: 'Utanç tablosu günlük mesaj kotası sıfırlandı.');

      case 'set_bio':
        final bio = (p['bio'] as String?) ?? '';
        if (bio.runes.length > 160) {
          return const CommandResult(ok: false, message: 'Biyografi en fazla 160 karakter olabilir.');
        }
        if (store.me == null) return const CommandResult(ok: false, message: 'Profil yok.');
        final r = store.updateBio(bio);
        return CommandResult(ok: r.ok, message: r.message, data: {'bio': store.me?.bio});

      case 'auto_motion_simulate':
        final rawSpeed = p['speedKmh'];
        final rawDur = p['durationSeconds'];
        final rawSteps = p['stepDelta'];
        final rawVar = p['variance'];
        final rawAcc = p['accuracy'];

        final speed = (rawSpeed as num?)?.toDouble() ?? 18.0;
        final dur = (rawDur as num?)?.toInt() ?? 30;
        final steps = (rawSteps as num?)?.toInt() ?? 0;
        final variance = (rawVar as num?)?.toDouble() ?? 0.18;
        final accuracy = (rawAcc as num?)?.toDouble() ?? 10.0;

        store.autoMotion.simulateMotionFlow(
          targetMode: AutoMotionMode.cycling,
          speedKmh: speed,
          durationSeconds: dur,
          stepDelta: steps,
          variance: variance,
          accuracy: accuracy,
        );
        return CommandResult(
          ok: true,
          message: 'Otomatik hareket simülasyonu çalıştırıldı ($dur sn, $speed km/sa).',
          data: store.autoMotion.toJson(),
        );

      case 'auto_motion_finish':
        final r = store.autoMotion.finishAutoTrip();
        return CommandResult(ok: r.ok, message: r.message, data: store.autoMotion.toJson());

      case 'auto_motion_cancel':
        final r = store.autoMotion.cancelAutoTrip();
        return CommandResult(ok: r.ok, message: r.message, data: store.autoMotion.toJson());

      default:
        return CommandResult(ok: false, message: 'Bilinmeyen komut: $cmd');
    }
  }
}
