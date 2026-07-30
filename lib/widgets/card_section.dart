import 'package:flutter/material.dart';

import '../main.dart';

/// Карточка-секция с заголовком/подзаголовком, используемая на экранах
/// аналитики (аукционная аналитика, отчёты по показам и т.д.).
class CardSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const CardSection({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      // Если высота блока задана вручную и содержимое в неё не влезает,
      // прокручиваем содержимое ВНУТРИ карточки. Прокрутка вокруг карточки
      // срезала ей углы и тень, а без прокрутки блок вообще не сжимался.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final header = <Widget>[
            Text(
              title,
              style: const TextStyle(
                color: kTextPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: const TextStyle(color: kTextSecondary, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
          ];

          if (!constraints.hasBoundedHeight) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [...header, child],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ...header,
              // Заголовок остаётся на месте, прокручивается только содержимое.
              Flexible(
                child: SingleChildScrollView(child: child),
              ),
            ],
          );
        },
      ),
    );
  }
}
