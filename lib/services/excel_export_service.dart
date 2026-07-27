import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import '../models/campaign_analytics.dart';
import '../models/loss_report.dart';

final _dateFmt = DateFormat('dd.MM.yyyy');
final _dateTimeFmt = DateFormat('dd.MM.yyyy HH:mm:ss');

final _headerStyle = CellStyle(
  bold: true,
  backgroundColorHex: ExcelColor.fromHexString('#D9E1F2'),
);
final _totalRowStyle = CellStyle(
  bold: true,
  backgroundColorHex: ExcelColor.fromHexString('#F2F2F2'),
);

void _appendRow(
  Sheet sheet,
  List<CellValue?> values,
  int rowIndex, {
  CellStyle? style,
}) {
  sheet.appendRow(values);
  if (style != null) {
    for (var col = 0; col < values.length; col++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: rowIndex))
          .cellStyle = style;
    }
  }
}

/// Собирает .xlsx-отчёт по показам кампании — 4 листа, повторяющие структуру
/// исходного analyze_ad_stats.py: Сводная / Поднять ставки / К оператору /
/// Все показы.
List<int> buildLossReportWorkbook({
  required String campaignName,
  required List<CampaignImpressionRecord> records,
  required LossReport report,
}) {
  final excel = Excel.createExcel();
  final defaultSheetName = excel.getDefaultSheet();

  final summarySheet = excel['Сводная'];
  _writeSummarySheet(summarySheet, report.dailyBreakdown);

  final bidSheet = excel['Поднять ставки'];
  _writeBidSheet(bidSheet, report.bidRaiseRows);

  final operatorSheet = excel['К оператору'];
  _writeOperatorSheet(operatorSheet, report.operatorIssueGroups);

  final rawSheet = excel['Все показы'];
  _writeRawSheet(rawSheet, records);

  if (defaultSheetName != null && defaultSheetName != 'Сводная') {
    excel.delete(defaultSheetName);
  }

  final bytes = excel.encode();
  if (bytes == null) {
    throw StateError('Не удалось сформировать xlsx-файл ($campaignName)');
  }
  return bytes;
}

void _writeSummarySheet(Sheet sheet, List<DailyBreakdownRow> days) {
  var row = 0;
  _appendRow(
    sheet,
    [
      TextCellValue('День'),
      TextCellValue('Оператор'),
      TextCellValue('Город'),
      TextCellValue('Всего показов'),
      TextCellValue('Успешных'),
      TextCellValue('% успешных'),
      TextCellValue('Проигрышей по ставке'),
      TextCellValue('Проблем оператора'),
      TextCellValue('Сумма по успешным показам'),
    ],
    row,
    style: _headerStyle,
  );
  row++;

  for (final day in days) {
    final dayLabel = _dateFmt.format(day.day);
    _appendRow(
      sheet,
      [
        TextCellValue(dayLabel),
        TextCellValue('Все операторы'),
        TextCellValue('Все города'),
        IntCellValue(day.total),
        IntCellValue(day.success),
        DoubleCellValue(day.successRate),
        IntCellValue(day.bidLoss),
        IntCellValue(day.operatorIssue),
        DoubleCellValue(day.successSpend),
      ],
      row,
      style: _totalRowStyle,
    );
    row++;

    for (final b in day.breakdown) {
      _appendRow(
        sheet,
        [
          TextCellValue(dayLabel),
          TextCellValue(b.operatorName),
          TextCellValue(b.city),
          IntCellValue(b.total),
          IntCellValue(b.success),
          DoubleCellValue(b.successRate),
          IntCellValue(b.bidLoss),
          IntCellValue(b.operatorIssue),
          DoubleCellValue(b.successSpend),
        ],
        row,
      );
      row++;
    }
  }
}

void _writeBidSheet(Sheet sheet, List<BidRaiseRow> rows) {
  var row = 0;
  _appendRow(
    sheet,
    [
      TextCellValue('GID'),
      TextCellValue('Адрес'),
      TextCellValue('Сторона'),
      TextCellValue('Оператор'),
      TextCellValue('Город'),
      TextCellValue('Проигрышей'),
      TextCellValue('Текущая ставка'),
      TextCellValue('Мин. требуемая ставка'),
      TextCellValue('Макс. выигравшая ставка'),
      TextCellValue('Рекомендуемая новая ставка'),
    ],
    row,
    style: _headerStyle,
  );
  row++;

  for (final r in rows) {
    _appendRow(
      sheet,
      [
        TextCellValue(r.inventoryGid),
        TextCellValue(r.address),
        TextCellValue(r.side),
        TextCellValue(r.operatorName),
        TextCellValue(r.city),
        IntCellValue(r.lossCount),
        DoubleCellValue(r.lastBid),
        DoubleCellValue(r.bidFloor),
        DoubleCellValue(r.maxWinningBid ?? 0),
        DoubleCellValue(r.recommendedBid),
      ],
      row,
    );
    row++;
  }
}

void _writeOperatorSheet(Sheet sheet, List<OperatorIssueGroupRow> groups) {
  var row = 0;
  _appendRow(
    sheet,
    [TextCellValue('Сводка по причинам')],
    row,
    style: _headerStyle,
  );
  row++;

  _appendRow(
    sheet,
    [
      TextCellValue('Причина отказа'),
      TextCellValue('Оператор'),
      TextCellValue('Город'),
      TextCellValue('Кол-во показов'),
      TextCellValue('Затронуто поверхностей (GID)'),
    ],
    row,
    style: _headerStyle,
  );
  row++;

  for (final g in groups) {
    _appendRow(
      sheet,
      [
        TextCellValue(g.reason),
        TextCellValue(g.operatorName),
        TextCellValue(g.city),
        IntCellValue(g.count),
        IntCellValue(g.distinctSurfaceCount),
      ],
      row,
    );
    row++;
  }

  // Пустая строка-разделитель — appendRow физически добавляет строку в лист,
  // одного увеличения счётчика row недостаточно (appendRow всегда пишет в
  // конец текущего листа, счётчик row должен совпадать с реальным количеством
  // уже записанных строк).
  sheet.appendRow(const []);
  row++;

  _appendRow(
    sheet,
    [
      TextCellValue(
        'Детализация по всем поверхностям (GID) — полный список для передачи оператору',
      ),
    ],
    row,
    style: _headerStyle,
  );
  row++;

  _appendRow(
    sheet,
    [
      TextCellValue('Причина отказа'),
      TextCellValue('Оператор'),
      TextCellValue('Город'),
      TextCellValue('GID'),
      TextCellValue('Адрес'),
      TextCellValue('Сторона'),
      TextCellValue('Кол-во показов'),
    ],
    row,
    style: _headerStyle,
  );
  row++;

  for (final g in groups) {
    for (final d in g.details) {
      _appendRow(
        sheet,
        [
          TextCellValue(g.reason),
          TextCellValue(g.operatorName),
          TextCellValue(g.city),
          TextCellValue(d.inventoryGid),
          TextCellValue(d.address),
          TextCellValue(d.side),
          IntCellValue(d.count),
        ],
        row,
      );
      row++;
    }
  }
}

void _writeRawSheet(Sheet sheet, List<CampaignImpressionRecord> records) {
  var row = 0;
  _appendRow(
    sheet,
    [
      TextCellValue('Дата/время показа'),
      TextCellValue('Результат'),
      TextCellValue('Категория'),
      TextCellValue('Причина отказа'),
      TextCellValue('Оператор'),
      TextCellValue('Город'),
      TextCellValue('GID'),
      TextCellValue('Адрес'),
      TextCellValue('Сторона'),
      TextCellValue('Ставка'),
      TextCellValue('Мин. ставка'),
      TextCellValue('Цена показа'),
    ],
    row,
    style: _headerStyle,
  );
  row++;

  for (final r in records) {
    final category = r.isWin
        ? 'Успешный'
        : classifyLoss(r) == LossCategory.lowBid
        ? 'Проигрыш в аукционе (ставка)'
        : 'Проблема на стороне оператора';

    _appendRow(
      sheet,
      [
        TextCellValue(r.showTime != null ? _dateTimeFmt.format(r.showTime!) : ''),
        TextCellValue(r.state),
        TextCellValue(category),
        TextCellValue(r.failureReasonMessage ?? r.failureReasonType ?? ''),
        TextCellValue(r.displayOwnerName ?? ''),
        TextCellValue(r.city ?? ''),
        TextCellValue(r.inventoryGid ?? ''),
        TextCellValue(r.address ?? ''),
        TextCellValue(r.side ?? ''),
        DoubleCellValue(r.bid ?? 0),
        DoubleCellValue(r.bidFloor ?? 0),
        DoubleCellValue(r.chargedPrice ?? r.price ?? 0),
      ],
      row,
    );
    row++;
  }
}
