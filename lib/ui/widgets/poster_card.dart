import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/media_item.dart';
import '../app_theme.dart';

class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.item,
    required this.onTap,
    this.width = 186,
    this.compact = false,
  });

  final MediaItem item;
  final VoidCallback onTap;
  final double width;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final posterHeight = compact ? width * .78 : width * 1.34;
    return SizedBox(
      width: width,
      child: Semantics(
        button: true,
        label: '${item.title}, ${item.year}',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Hero(
                tag: 'poster-${item.id}',
                child: PosterArtwork(item: item, height: posterHeight),
              ),
              const SizedBox(height: 10),
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${item.year} · ${item.kind.label}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Icon(
                    Icons.star_rounded,
                    color: Color(0xFFF0A429),
                    size: 16,
                  ),
                  Text(
                    item.rating.toStringAsFixed(1),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PosterArtwork extends StatelessWidget {
  const PosterArtwork({
    super.key,
    required this.item,
    required this.height,
    this.showTitle = true,
  });

  final MediaItem item;
  final double height;
  final bool showTitle;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: item.colors,
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x180F172A),
          blurRadius: 20,
          offset: Offset(0, 10),
        ),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: _AtmospherePainter(item.id)),
        if (item.posterUrl case final posterUrl?)
          Image.network(
            posterUrl,
            fit: BoxFit.cover,
            cacheWidth: 500,
            filterQuality: FilterQuality.low,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              return AnimatedOpacity(
                opacity: wasSynchronouslyLoaded || frame != null ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: child,
              );
            },
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        if (item.posterUrl != null)
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xB3000000)],
                stops: [.48, 1],
              ),
            ),
          ),
        Positioned(
          left: 14,
          top: 14,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .28),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              child: Text(
                item.kind.label.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          ),
        ),
        if (showTitle)
          Positioned(
            left: 15,
            right: 15,
            bottom: 16,
            child: Text(
              item.title.toUpperCase(),
              maxLines: 3,
              style: TextStyle(
                color: Colors.white,
                fontSize: height > 220 ? 21 : 16,
                height: .98,
                fontWeight: FontWeight.w900,
                letterSpacing: -.5,
                shadows: const [Shadow(blurRadius: 12, color: Colors.black54)],
              ),
            ),
          ),
      ],
    ),
  );
}

class _AtmospherePainter extends CustomPainter {
  _AtmospherePainter(this.seed);
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(seed);
    final haze = Paint()..color = Colors.white.withValues(alpha: .10);
    for (var i = 0; i < 7; i++) {
      final radius = size.shortestSide * (.08 + random.nextDouble() * .24);
      canvas.drawCircle(
        Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
        ),
        radius,
        haze,
      );
    }
    final line = Paint()
      ..color = Colors.white.withValues(alpha: .25)
      ..strokeWidth = 1.2;
    canvas.drawLine(
      Offset(size.width * .1, size.height * .62),
      Offset(size.width * .92, size.height * .45),
      line,
    );
    canvas.drawCircle(
      Offset(size.width * .72, size.height * .30),
      size.width * .13,
      Paint()..color = Colors.white.withValues(alpha: .18),
    );
  }

  @override
  bool shouldRepaint(covariant _AtmospherePainter oldDelegate) =>
      oldDelegate.seed != seed;
}
