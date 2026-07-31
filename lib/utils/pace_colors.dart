import 'package:flutter/material.dart';

import '../main.dart';
import '../models/campaign.dart';

/// Цвет выполнения плана по одной шкале для всех экранов.
///
/// Шкала намеренно несимметрична: отклонение в пределах 10% — шум, а вот
/// «сильно отстаём» и «перерасход» одинаково требуют вмешательства, поэтому оба
/// красные. Раньше каждый блок красил по-своему: где-то любое превышение
/// считалось ошибкой, где-то 75% плана оставались зелёными — и один и тот же
/// темп выглядел то нормой, то проблемой.
Color paceColor(double? ratio) {
  if (ratio == null) return kAccent;
  if (ratio > 1.1) return Colors.redAccent; // перерасход
  if (ratio >= 0.9) return const Color(0xFF43A047); // по плану
  if (ratio >= 0.7) return const Color(0xFFF9A825); // подотстаём
  return Colors.redAccent; // сильно отстаём
}

/// Цвета плашки статуса кампании: фон и текст.
///
/// Одно место для всех экранов и, главное, по той же категории, что и подпись:
/// иначе активная кампания со статусом вроде STARTED подписывалась «Активна», а
/// красилась серым «неизвестно».
(Color, Color) campaignStatusPalette(CampaignStatusKind kind) {
  return switch (kind) {
    CampaignStatusKind.active => (
      const Color(0xFFE8F5E9),
      const Color(0xFF2E7D32),
    ),
    CampaignStatusKind.paused => (
      const Color(0xFFFFF3E0),
      const Color(0xFFE65100),
    ),
    CampaignStatusKind.fresh => (
      const Color(0xFFE3F2FD),
      const Color(0xFF1565C0),
    ),
    CampaignStatusKind.offSchedule => (
      const Color(0xFFFFFDE7),
      const Color(0xFFF9A825),
    ),
    CampaignStatusKind.exhausted => (
      const Color(0xFFFFEBEE),
      const Color(0xFFC62828),
    ),
    CampaignStatusKind.completed || CampaignStatusKind.unknown => (
      const Color(0xFFF5F5F5),
      const Color(0xFF757575),
    ),
  };
}
