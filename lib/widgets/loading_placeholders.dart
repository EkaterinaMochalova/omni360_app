import 'package:flutter/material.dart';

import '../main.dart';

/// Переливающийся прямоугольник на месте ещё не загруженного значения.
///
/// Статичный прочерк неотличим от «данных нет»: пользователь видит пустоту и
/// считает, что так и будет. Движение сразу говорит, что загрузка идёт.
class ShimmerBox extends StatefulWidget {
  final double width;
  final double height;

  const ShimmerBox({super.key, this.width = 64, this.height = 14});

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          // Блик пробегает слева направо: -1 → 2, чтобы он успевал уйти за
          // правый край до начала следующего прохода.
          final shift = -1 + _controller.value * 3;
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: LinearGradient(
                begin: Alignment(shift - 1, 0),
                end: Alignment(shift, 0),
                colors: const [
                  Color(0xFFEDEFF3),
                  Color(0xFFF7F8FA),
                  Color(0xFFEDEFF3),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Многоточие, которое действительно «идёт»: точки появляются по одной.
class LoadingDots extends StatefulWidget {
  final TextStyle? style;

  const LoadingDots({super.key, this.style});

  @override
  State<LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<LoadingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final dots = 1 + (_controller.value * 3).floor().clamp(0, 2);
        // Ширину держим постоянной, иначе соседний текст дёргается.
        return SizedBox(
          width: 14,
          child: Text(
            '.' * dots,
            style: widget.style ??
                const TextStyle(color: kTextSecondary, fontSize: 13),
          ),
        );
      },
    );
  }
}

/// Значение, которое ещё грузится: вместо прочерка — переливающийся блок.
class ValueOrShimmer extends StatelessWidget {
  final bool loading;
  final String? value;
  final TextStyle? style;
  final double shimmerWidth;

  const ValueOrShimmer({
    super.key,
    required this.loading,
    required this.value,
    this.style,
    this.shimmerWidth = 64,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return ShimmerBox(width: shimmerWidth);
    return Text(value ?? '—', style: style);
  }
}
