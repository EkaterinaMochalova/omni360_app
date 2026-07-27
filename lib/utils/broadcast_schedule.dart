import '../models/campaign.dart';

/// Работа с расписанием вещания (`timeSettings` кампании).
///
/// Единственное место, где считается «сколько часов кампания вещает». Раньше
/// это считалось в трёх местах по-разному: размах «первый старт — последний
/// конец» за сегодня, жёстко зашитые 14 часов в сутках и «расписания нет —
/// значит круглые сутки». Отсюда расходились и лимиты, и уведомления.

const int secondsPerDay = 86400;
const int secondsPerHour = 3600;

/// Защита от бесконечного перебора, если endDate уехал далеко в будущее.
const int _maxDaysScanned = 400;

bool hasSchedule(List<TimeSlot>? slots) => slots != null && slots.isNotEmpty;

/// Интервалы вещания (секунды от полуночи) на день недели [weekday] (1=Пн…7=Вс).
///
/// Пересекающиеся и смежные слоты склеиваются — иначе один и тот же час
/// посчитается дважды. Пустой список означает «в этот день не вещаем»;
/// при отсутствии расписания считаем круглые сутки.
List<(int, int)> broadcastRangesForWeekday(List<TimeSlot>? slots, int weekday) {
  if (!hasSchedule(slots)) {
    return const [(0, secondsPerDay)];
  }

  final day =
      slots!
          .where((s) => s.dayOfWeek == weekday)
          .map(
            (s) => (
              s.relativeStartTime.clamp(0, secondsPerDay),
              s.relativeEndTime.clamp(0, secondsPerDay),
            ),
          )
          .where((r) => r.$2 > r.$1)
          .toList()
        ..sort((a, b) => a.$1.compareTo(b.$1));

  if (day.isEmpty) return const [];

  final merged = <(int, int)>[day.first];
  for (final range in day.skip(1)) {
    final last = merged.last;
    if (range.$1 <= last.$2) {
      merged[merged.length - 1] = (
        last.$1,
        range.$2 > last.$2 ? range.$2 : last.$2,
      );
    } else {
      merged.add(range);
    }
  }
  return merged;
}

/// Секунды вещания на дате [date], начиная с [fromSecond] секунды суток.
int broadcastSecondsOnDate(
  List<TimeSlot>? slots,
  DateTime date, {
  int fromSecond = 0,
}) {
  var total = 0;
  for (final range in broadcastRangesForWeekday(slots, date.weekday)) {
    final start = range.$1 > fromSecond ? range.$1 : fromSecond;
    if (range.$2 > start) total += range.$2 - start;
  }
  return total;
}

/// Попадает ли момент [moment] в окно вещания.
bool isWithinBroadcast(List<TimeSlot>? slots, DateTime moment) {
  final seconds =
      moment.hour * secondsPerHour + moment.minute * 60 + moment.second;
  for (final range in broadcastRangesForWeekday(slots, moment.weekday)) {
    if (seconds >= range.$1 && seconds < range.$2) return true;
  }
  return false;
}

/// Часы вещания и число дней вещания в интервале дат включительно.
///
/// Для первого дня по умолчанию учитывается только время после [from] — это
/// нужно для «остатка» (сколько вещания ещё впереди). Для расчёта планового
/// объёма за весь срок кампании передайте [fromTimeOfDay] = false, тогда
/// первый день берётся целиком.
({double hours, int days}) broadcastHoursAndDays(
  List<TimeSlot>? slots,
  DateTime from,
  DateTime lastDate, {
  bool fromTimeOfDay = true,
}) {
  final firstDate = DateTime(from.year, from.month, from.day);
  final endDate = DateTime(lastDate.year, lastDate.month, lastDate.day);
  final span = endDate.difference(firstDate).inDays + 1;
  if (span <= 0) return (hours: 0.0, days: 0);

  final daysToScan = span > _maxDaysScanned ? _maxDaysScanned : span;
  final fromSecond = fromTimeOfDay
      ? from.hour * secondsPerHour + from.minute * 60 + from.second
      : 0;

  var seconds = 0;
  var days = 0;
  for (var i = 0; i < daysToScan; i++) {
    // Через конструктор: day + i сам нормализует переход через конец месяца.
    final date = DateTime(firstDate.year, firstDate.month, firstDate.day + i);
    final onDate = broadcastSecondsOnDate(
      slots,
      date,
      fromSecond: i == 0 ? fromSecond : 0,
    );
    if (onDate <= 0) continue;
    seconds += onDate;
    days++;
  }

  return (hours: seconds / secondsPerHour, days: days);
}

/// Часы вещания за весь срок кампании — знаменатель для «в час» из общего
/// плана. Раньше вместо этого стояли зашитые 14 часов, из-за чего общий план
/// по выходам делился как суточный: на двухнедельной кампании плановые выходы
/// в час завышались примерно в 14 раз, и алерт «отстаём» горел постоянно.
/// null — если дат нет и делить не на что.
double? totalBroadcastHours(
  Campaign campaign, {
  List<TimeSlot>? scheduleOverride,
}) {
  final start = DateTime.tryParse((campaign.startDate ?? '').trim());
  final end = DateTime.tryParse((campaign.endDate ?? '').trim());
  if (start == null || end == null) return null;

  final result = broadcastHoursAndDays(
    scheduleOverride ?? campaign.timeSettings,
    start,
    end,
    fromTimeOfDay: false,
  );
  return result.hours > 0 ? result.hours : null;
}
