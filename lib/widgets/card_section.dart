import 'package:flutter/material.dart';

import '../main.dart';
import 'loading_placeholders.dart';

/// Блок-секция в одном из трёх состояний.
///
/// Раньше не загрузившиеся блоки просто исчезали из сетки: раскладка прыгала,
/// и было непонятно, блок выключен или данных нет. Теперь блок стоит на месте
/// всегда и показывает, что с ним происходит.
class CardSectionState extends StatelessWidget {
  final String title;
  final String? subtitle;

  /// Готовое содержимое. null — ещё грузится (если [error] пуст).
  final Widget? child;

  /// Текст ошибки. Непустой — вместо содержимого показываем его.
  final String? error;

  /// Сколько строк-заглушек рисовать в состоянии загрузки.
  final int skeletonLines;

  const CardSectionState({
    super.key,
    required this.title,
    this.subtitle,
    this.child,
    this.error,
    this.skeletonLines = 3,
  });

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return CardSection(
        title: title,
        subtitle: subtitle,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            error!,
            style: const TextStyle(color: Color(0xFFC62828), fontSize: 12),
          ),
        ),
      );
    }

    if (child == null) {
      return CardSection(
        title: title,
        subtitle: subtitle,
        // Полоса загрузки с пояснением уже есть в шапке страницы, поэтому
        // здесь достаточно скелета — без второй крутилки и текста.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < skeletonLines; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ShimmerBox(
                  width: i.isEven ? 260 : 200,
                  height: 12,
                ),
              ),
          ],
        ),
      );
    }

    return CardSection(title: title, subtitle: subtitle, child: child!);
  }
}

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
