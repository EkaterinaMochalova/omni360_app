import '../models/campaign.dart';
import 'broadcast_schedule.dart';

enum CampaignNoticeType { completed, noImpressionsLastHour }

class CampaignNotice {
  final String key;
  final String campaignId;
  final String campaignName;
  final CampaignNoticeType type;
  final String title;
  final String message;
  final DateTime createdAt;

  const CampaignNotice({
    required this.key,
    required this.campaignId,
    required this.campaignName,
    required this.type,
    required this.title,
    required this.message,
    required this.createdAt,
  });
}

bool isCampaignCompletedStatus(String status) {
  final normalized = status.trim().toUpperCase();
  return normalized == 'COMPLETED' || normalized == 'FINISHED';
}

bool isCampaignCompleted(Campaign campaign) =>
    isCampaignCompletedStatus(campaign.status) ||
    campaign.displayStatus == 'Завершена';

/// Вещала ли кампания непрерывно весь последний час.
///
/// [schedule] — расписание из детального ответа: в списочном `timeSettings`
/// нет, а без него кампания считалась активной круглосуточно, и «Нет показов
/// последний час» приходило ночью, когда она законно молчит.
///
/// null (загрузить не удалось) — возвращаем false: пропущенное уведомление
/// лучше ложной тревоги в три часа ночи. А вот пустое расписание — это
/// «ограничений по времени нет», кампания вещает круглые сутки, и уведомление
/// работать должно.
bool wasCampaignActiveForLastHour(
  Campaign campaign, [
  DateTime? now,
  BroadcastSchedule? schedule,
]) {
  final end = now ?? DateTime.now();
  if (!campaign.isActive || campaign.isNotOnSchedule) return false;
  if (schedule == null) return false;

  for (var minute = 1; minute <= 60; minute++) {
    final probe = end.subtract(Duration(minutes: minute));
    if (!_isCampaignActiveAt(campaign, probe, schedule.slots)) {
      return false;
    }
  }

  return true;
}

bool _isCampaignActiveAt(
  Campaign campaign,
  DateTime moment,
  List<TimeSlot>? slots,
) {
  if (!_isWithinCampaignDates(campaign, moment)) return false;
  return isWithinBroadcast(slots, moment);
}

bool _isWithinCampaignDates(Campaign campaign, DateTime moment) {
  final day = DateTime(moment.year, moment.month, moment.day);
  final start = _parseDate(campaign.startDate);
  final end = _parseDate(campaign.endDate);

  if (start != null && day.isBefore(start)) return false;
  if (end != null && day.isAfter(end)) return false;
  return true;
}

DateTime? _parseDate(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}
