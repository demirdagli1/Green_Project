import 'package:flutter/material.dart';
import '../models/league_tier.dart';

/// Klan lig logolarını gösteren ortak bileşen.
/// Altı PNG dosyasını (logo-klan-1.png ... 6.png) BoxFit.contain ile oran ve şeffaflığı koruyarak gösterir.
/// Dosya yüklenemezse veya test ortamında mevcut dekoratif sembol/renk fallback'ine döner.
class ClanLeagueBadge extends StatelessWidget {
  final LeagueTier tier;
  final double size;
  final BoxFit fit;

  const ClanLeagueBadge({
    super.key,
    required this.tier,
    this.size = 28,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${tier.clanName} Klan Ligi',
      child: SizedBox(
        width: size,
        height: size,
        child: Image.asset(
          tier.clanAssetPath,
          fit: fit,
          errorBuilder: (context, error, stackTrace) => _fallback(),
        ),
      ),
    );
  }

  Widget _fallback() {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tier.color,
        borderRadius: BorderRadius.circular(size * 0.25),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.all(2.0),
          child: Text(
            tier.symbol,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: size * 0.38,
            ),
          ),
        ),
      ),
    );
  }
}
