import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

@immutable
class KitchenPalette extends ThemeExtension<KitchenPalette> {
  const KitchenPalette({
    this.background = const Color(0xFFF5F0DF),
    this.icon = const Color(0xFFEEC364),
  });

  final Color background;
  final Color icon;

  @override
  KitchenPalette copyWith({Color? background, Color? icon}) => KitchenPalette(
        background: background ?? this.background,
        icon: icon ?? this.icon,
      );

  @override
  KitchenPalette lerp(ThemeExtension<KitchenPalette>? other, double t) {
    if (other is! KitchenPalette) return this;
    return KitchenPalette(
      background: Color.lerp(background, other.background, t)!,
      icon: Color.lerp(icon, other.icon, t)!,
    );
  }
}

const double kitchenBackgroundCell = 90;
const double kitchenBackgroundGapFactor = 0.10;
const double kitchenBackgroundBaseSize = 88;
const double kitchenBackgroundCenterOpacity = 0.06;
const double kitchenBackgroundCenterStop = 0.22;
const double kitchenBackgroundEdgeStop = 0.85;
const int kitchenBackgroundSeed = 7;
const int _maxPlacementAttemptsPerIcon = 80;

@immutable
class KitchenIconPlacement {
  const KitchenIconPlacement({
    required this.asset,
    required this.center,
    required this.size,
    required this.radius,
    required this.rotation,
  });

  final String asset;
  final Offset center;
  final double size;
  final double radius;
  final double rotation;
}

@immutable
class _KitchenIconType {
  const _KitchenIconType({
    required this.asset,
    required this.scale,
    required this.maxTiltDegrees,
    required this.weight,
  });

  final String asset;
  final double scale;
  final double maxTiltDegrees;
  final int weight;
}

const List<_KitchenIconType> _iconTypes = [
  _KitchenIconType(
    asset: 'assets/icons/background/spoon.svg',
    scale: 0.75,
    maxTiltDegrees: 180,
    weight: 1,
  ),
  _KitchenIconType(
    asset: 'assets/icons/background/fork.svg',
    scale: 1,
    maxTiltDegrees: 180,
    weight: 1,
  ),
  _KitchenIconType(
    asset: 'assets/icons/background/mug.svg',
    scale: 1.2,
    maxTiltDegrees: 30,
    weight: 2,
  ),
  _KitchenIconType(
    asset: 'assets/icons/background/heart.svg',
    scale: 1,
    maxTiltDegrees: 30,
    weight: 1,
  ),
  _KitchenIconType(
    asset: 'assets/icons/background/star.svg',
    scale: 0.8,
    maxTiltDegrees: 180,
    weight: 1,
  ),
];

List<KitchenIconPlacement> buildKitchenIconLayout(
  Size size, {
  int seed = kitchenBackgroundSeed,
}) {
  if (!size.width.isFinite ||
      !size.height.isFinite ||
      size.width <= 0 ||
      size.height <= 0) {
    return const [];
  }

  final random = Random(seed);
  final target = (size.width *
          size.height /
          (kitchenBackgroundCell * kitchenBackgroundCell))
      .ceil();
  const gap = kitchenBackgroundCell * kitchenBackgroundGapFactor;
  final totalWeight =
      _iconTypes.fold<int>(0, (total, type) => total + type.weight);
  final placed = <KitchenIconPlacement>[];
  var attempts = 0;

  while (placed.length < target &&
      attempts < target * _maxPlacementAttemptsPerIcon) {
    attempts++;
    var weightedPick = random.nextInt(totalWeight);
    var type = _iconTypes.first;
    for (final candidate in _iconTypes) {
      weightedPick -= candidate.weight;
      if (weightedPick < 0) {
        type = candidate;
        break;
      }
    }

    final iconSize = kitchenBackgroundBaseSize *
        type.scale *
        (0.9 + random.nextDouble() * 0.2);
    final radius = iconSize * 0.52;
    final center = Offset(
      -0.4 * radius + random.nextDouble() * (size.width + 0.8 * radius),
      -0.4 * radius + random.nextDouble() * (size.height + 0.8 * radius),
    );
    if (placed.any((placement) =>
        (placement.center - center).distance <
        placement.radius + radius + gap)) {
      continue;
    }

    final tilt = type.maxTiltDegrees * pi / 180;
    placed.add(
      KitchenIconPlacement(
        asset: type.asset,
        center: center,
        size: iconSize,
        radius: radius,
        rotation: (random.nextDouble() * 2 - 1) * tilt,
      ),
    );
  }

  return List.unmodifiable(placed);
}

class KitchenBackground extends StatefulWidget {
  const KitchenBackground({required this.child, super.key});

  final Widget child;

  @override
  State<KitchenBackground> createState() => _KitchenBackgroundState();
}

class _KitchenBackgroundState extends State<KitchenBackground> {
  Size? _cachedSize;
  List<KitchenIconPlacement> _cachedLayout = const [];

  List<KitchenIconPlacement> _layoutFor(Size size) {
    if (_cachedSize != size) {
      _cachedSize = size;
      _cachedLayout = buildKitchenIconLayout(size);
    }
    return _cachedLayout;
  }

  @override
  Widget build(BuildContext context) {
    final palette =
        Theme.of(context).extension<KitchenPalette>() ?? const KitchenPalette();

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final placements = _layoutFor(size);
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(color: palette.background),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (bounds) {
                      final maxSide = max(bounds.width, bounds.height);
                      return RadialGradient(
                        radius: maxSide /
                            (sqrt2 * min(bounds.width, bounds.height)),
                        stops: const [
                          0,
                          kitchenBackgroundCenterStop,
                          kitchenBackgroundEdgeStop,
                        ],
                        colors: [
                          palette.icon.withValues(
                            alpha: kitchenBackgroundCenterOpacity,
                          ),
                          palette.icon.withValues(
                            alpha: kitchenBackgroundCenterOpacity,
                          ),
                          palette.icon,
                        ],
                        transform: const _EllipticalGradientTransform(),
                      ).createShader(bounds);
                    },
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        for (final placement in placements)
                          Positioned(
                            left: placement.center.dx - placement.size / 2,
                            top: placement.center.dy - placement.size / 2,
                            width: placement.size,
                            height: placement.size,
                            child: Transform.rotate(
                              angle: placement.rotation,
                              child: SvgPicture.asset(
                                placement.asset,
                                width: placement.size,
                                height: placement.size,
                                colorFilter: _preservingHighlightColorFilter(
                                    palette.icon),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            widget.child,
          ],
        );
      },
    );
  }
}

class _EllipticalGradientTransform extends GradientTransform {
  const _EllipticalGradientTransform();

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    final maxSide = max(bounds.width, bounds.height);
    final center = bounds.center;
    return Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(bounds.width / maxSide, bounds.height / maxSide, 1, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1);
  }
}

ColorFilter _preservingHighlightColorFilter(Color iconColor) {
  // Re-map baked gold fills while preserving the SVGs' white highlights.
  const originalIconColor = Color(0xFFEEC364);
  final redScale = (1 - iconColor.r) / (1 - originalIconColor.r);
  final greenScale = (1 - iconColor.g) / (1 - originalIconColor.g);
  final blueScale = (1 - iconColor.b) / (1 - originalIconColor.b);

  return ColorFilter.matrix([
    redScale,
    0,
    0,
    0,
    1 - redScale,
    0,
    greenScale,
    0,
    0,
    1 - greenScale,
    0,
    0,
    blueScale,
    0,
    1 - blueScale,
    0,
    0,
    0,
    1,
    0,
  ]);
}
