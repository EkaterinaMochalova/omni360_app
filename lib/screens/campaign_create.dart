import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import 'package:dio/dio.dart';
import '../api/omni360_client.dart';
import '../models/reference.dart';
import '../providers/campaigns_provider.dart';
import '../providers/reference_provider.dart';

class CampaignCreateScreen extends ConsumerStatefulWidget {
  const CampaignCreateScreen({super.key});

  @override
  ConsumerState<CampaignCreateScreen> createState() =>
      _CampaignCreateScreenState();
}

class _CampaignCreateScreenState
    extends ConsumerState<CampaignCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  String? _error;

  // ── Basic ──
  final _nameCtrl = TextEditingController();
  String _type = 'FLEX_GUARANTEED';
  Customer? _customer;
  Brand? _brand;

  // ── Dates ──
  DateTime? _startDate;
  DateTime? _endDate;

  // ── Budget ──
  final _budgetCtrl = TextEditingController();
  final _dailyBudgetCtrl = TextEditingController();

  // ── OTS ──
  final _otsCtrl = TextEditingController();
  final _dailyOtsCtrl = TextEditingController();

  // ── Strategy ──
  String _strategy = 'STANDARD';
  final _bidCtrl = TextEditingController();

  // ── Regions ──
  final List<Region> _regions = [];

  // ── Audience ──
  String _gender = 'ALL';
  RangeValues _ageRange = const RangeValues(18, 65);
  final Set<String> _income = {'A', 'B', 'C'};

  @override
  void dispose() {
    _nameCtrl.dispose();
    _budgetCtrl.dispose();
    _dailyBudgetCtrl.dispose();
    _otsCtrl.dispose();
    _dailyOtsCtrl.dispose();
    _bidCtrl.dispose();
    super.dispose();
  }

  // ── Date picker ──
  Future<void> _pickDate(bool isStart) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart
          ? (_startDate ?? now)
          : (_endDate ?? (_startDate ?? now).add(const Duration(days: 7))),
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) _endDate = null;
      } else {
        _endDate = picked;
      }
    });
  }

  // ── Submit ──
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startDate == null || _endDate == null) {
      setState(() => _error = 'Укажите даты кампании');
      return;
    }
    setState(() { _saving = true; _error = null; });

    final body = <String, dynamic>{
      'name': _nameCtrl.text.trim(),
      'type': _type,
      'startDate': '${_startDate!.toIso8601String().substring(0, 10)}T00:00:00',
      'endDate': '${_endDate!.toIso8601String().substring(0, 10)}T23:59:59',
      if (_customer != null) 'customerId': _customer!.id,
      if (_brand != null) 'brandId': _brand!.id,
      if (_budgetCtrl.text.isNotEmpty)
        'budget': double.tryParse(_budgetCtrl.text.replaceAll(' ', '')),
      if (_dailyBudgetCtrl.text.isNotEmpty)
        'dailyBudget': double.tryParse(_dailyBudgetCtrl.text.replaceAll(' ', '')),
      if (_otsCtrl.text.isNotEmpty)
        'ots': double.tryParse(_otsCtrl.text.replaceAll(' ', '')),
      if (_dailyOtsCtrl.text.isNotEmpty)
        'dailyOts': double.tryParse(_dailyOtsCtrl.text.replaceAll(' ', '')),
      'strategy': _strategy,
      if (_bidCtrl.text.isNotEmpty)
        'commonBid': double.tryParse(_bidCtrl.text.replaceAll(' ', '')),
      'segments': <Map<String, dynamic>>[],
      if (_regions.isNotEmpty) 'cities': _regions.map((r) => r.id).toList(),
      if (_income.isNotEmpty || _gender != 'ALL')
        'targetAudience': {
          'enabled': true,
          'gender': [_gender],
          'ageRange': {'start': _ageRange.start.round(), 'end': _ageRange.end.round()},
          if (_income.isNotEmpty) 'income': _income.toList(),
        },
    };

    try {
      await Omni360Client().dio.post('/api/v1.0/clients/campaigns', data: body);
      ref.invalidate(campaignsProvider);
      if (mounted) Navigator.of(context).pop(true);
    } on DioException catch (e) {
      final body = e.response?.data;
      final msg = body is Map
          ? (body['message'] ?? body['error'] ?? body.toString())
          : body?.toString() ?? e.message ?? e.toString();
      setState(() => _error = 'API: $msg');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Новая кампания',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                onPressed: _submit,
                style: FilledButton.styleFrom(backgroundColor: kAccent),
                child: const Text('Создать'),
              ),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: wide ? 40 : 16,
            vertical: 20,
          ),
          child: wide ? _wideLayout() : _narrowLayout(),
        ),
      ),
    );
  }

  // ── Desktop: 2 columns ──
  Widget _wideLayout() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null) _ErrorBanner(_error!),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left column
              Expanded(
                child: Column(children: [
                  _Section('Основное', [
                    _Field('Название кампании', _nameCtrl, required: true),
                    const SizedBox(height: 12),
                    _TypePicker(value: _type, onChanged: (v) => setState(() => _type = v)),
                    const SizedBox(height: 12),
                    _CustomerPicker(
                        selected: _customer,
                        onChanged: (c) => setState(() => _customer = c)),
                    const SizedBox(height: 12),
                    _BrandPicker(
                        selected: _brand,
                        onChanged: (b) => setState(() => _brand = b)),
                  ]),
                  const SizedBox(height: 16),
                  _Section('Даты', [
                    _DateRow(
                      start: _startDate,
                      end: _endDate,
                      onPickStart: () => _pickDate(true),
                      onPickEnd: () => _pickDate(false),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  _Section('Бюджет', [
                    _MoneyField('Общий бюджет, ₽', _budgetCtrl),
                    const SizedBox(height: 12),
                    _MoneyField('Бюджет в день, ₽', _dailyBudgetCtrl),
                  ]),
                ]),
              ),
              const SizedBox(width: 24),
              // Right column
              Expanded(
                child: Column(children: [
                  _Section('OTS и стратегия', [
                    _MoneyField('Плановые OTS', _otsCtrl, symbol: ''),
                    const SizedBox(height: 12),
                    _MoneyField('OTS в день', _dailyOtsCtrl, symbol: ''),
                    const SizedBox(height: 12),
                    _StrategyPicker(
                        value: _strategy,
                        onChanged: (v) => setState(() => _strategy = v)),
                    const SizedBox(height: 12),
                    _MoneyField('Ставка (commonBid)', _bidCtrl, symbol: ''),
                  ]),
                  const SizedBox(height: 16),
                  _Section('Регионы', [
                    _RegionPicker(
                        selected: _regions,
                        onChanged: (r) => setState(() {
                              if (_regions.contains(r)) {
                                _regions.remove(r);
                              } else {
                                _regions.add(r);
                              }
                            })),
                  ]),
                  const SizedBox(height: 16),
                  _Section('Аудитория', [
                    _GenderPicker(
                        value: _gender,
                        onChanged: (v) => setState(() => _gender = v)),
                    const SizedBox(height: 12),
                    _AgeRangePicker(
                        value: _ageRange,
                        onChanged: (v) => setState(() => _ageRange = v)),
                    const SizedBox(height: 12),
                    _IncomePicker(
                        selected: _income,
                        onToggle: (v) => setState(() {
                              if (_income.contains(v)) {
                                _income.remove(v);
                              } else {
                                _income.add(v);
                              }
                            })),
                  ]),
                ]),
              ),
            ],
          ),
        ],
      );

  // ── Mobile: 1 column ──
  Widget _narrowLayout() => Column(
        children: [
          if (_error != null) _ErrorBanner(_error!),
          _Section('Основное', [
            _Field('Название кампании', _nameCtrl, required: true),
            const SizedBox(height: 12),
            _TypePicker(value: _type, onChanged: (v) => setState(() => _type = v)),
            const SizedBox(height: 12),
            _CustomerPicker(
                selected: _customer,
                onChanged: (c) => setState(() => _customer = c)),
          ]),
          const SizedBox(height: 16),
          _Section('Даты', [
            _DateRow(
              start: _startDate,
              end: _endDate,
              onPickStart: () => _pickDate(true),
              onPickEnd: () => _pickDate(false),
            ),
          ]),
          const SizedBox(height: 16),
          _Section('Бюджет', [
            _MoneyField('Общий бюджет, ₽', _budgetCtrl),
            const SizedBox(height: 12),
            _MoneyField('Бюджет в день, ₽', _dailyBudgetCtrl),
          ]),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Section wrapper
// ─────────────────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section(this.title, this.children);

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: kTextPrimary)),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable field widgets
// ─────────────────────────────────────────────────────────────────────────────

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final bool required;
  const _Field(this.label, this.ctrl, {this.required = false});

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: ctrl,
        decoration: _dec(label),
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? 'Обязательное поле' : null
            : null,
      );
}

class _MoneyField extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final String symbol;
  const _MoneyField(this.label, this.ctrl, {this.symbol = '₽'});

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: _dec(label, suffix: symbol.isEmpty ? null : symbol),
      );
}

InputDecoration _dec(String label, {String? suffix}) => InputDecoration(
      labelText: label,
      suffixText: suffix,
      filled: true,
      fillColor: kBg,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kBorder)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kBorder)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kAccent, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );

// ── Type picker ──
class _TypePicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _TypePicker({required this.value, required this.onChanged});

  static const _types = [
    ('FLEX_GUARANTEED', 'Flex Guaranteed'),
    ('RTB', 'RTB'),
    ('GUARANTEED', 'Guaranteed'),
  ];

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
        value: value,
        decoration: _dec('Тип кампании'),
        items: _types
            .map((t) => DropdownMenuItem(value: t.$1, child: Text(t.$2)))
            .toList(),
        onChanged: (v) { if (v != null) onChanged(v); },
      );
}

// ── Strategy picker ──
class _StrategyPicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _StrategyPicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
        value: value,
        decoration: _dec('Стратегия'),
        items: const [
          DropdownMenuItem(value: 'STANDARD', child: Text('Standard')),
          DropdownMenuItem(value: 'ASAP', child: Text('ASAP')),
        ],
        onChanged: (v) { if (v != null) onChanged(v); },
      );
}

// ── Date row ──
class _DateRow extends StatelessWidget {
  final DateTime? start;
  final DateTime? end;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  const _DateRow(
      {required this.start,
      required this.end,
      required this.onPickStart,
      required this.onPickEnd});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd.MM.yyyy');
    return Row(
      children: [
        Expanded(child: _DateButton(
          label: 'Дата старта',
          value: start != null ? fmt.format(start!) : null,
          onTap: onPickStart,
        )),
        const SizedBox(width: 12),
        Expanded(child: _DateButton(
          label: 'Дата конца',
          value: end != null ? fmt.format(end!) : null,
          onTap: onPickEnd,
        )),
      ],
    );
  }
}

class _DateButton extends StatelessWidget {
  final String label;
  final String? value;
  final VoidCallback onTap;
  const _DateButton({required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: kBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kBorder),
          ),
          child: Row(
            children: [
              const Icon(Icons.calendar_today_outlined,
                  size: 16, color: kTextSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  value ?? label,
                  style: TextStyle(
                      color: value != null ? kTextPrimary : kTextSecondary,
                      fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      );
}

// ── Customer picker ──
class _CustomerPicker extends ConsumerWidget {
  final Customer? selected;
  final ValueChanged<Customer?> onChanged;
  const _CustomerPicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(customersProvider);
    return async.when(
      loading: () => const _LoadingField('Рекламодатель'),
      error: (_, __) => const _ErrorField('Рекламодатель'),
      data: (list) => DropdownButtonFormField<Customer>(
        value: list.where((c) => c.id == selected?.id).firstOrNull,
        decoration: _dec('Рекламодатель'),
        items: list
            .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
            .toList(),
        onChanged: onChanged,
        isExpanded: true,
      ),
    );
  }
}

// ── Brand picker ──
class _BrandPicker extends ConsumerWidget {
  final Brand? selected;
  final ValueChanged<Brand?> onChanged;
  const _BrandPicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(brandsProvider);
    return async.when(
      loading: () => const _LoadingField('Бренд'),
      error: (_, __) => const _ErrorField('Бренд'),
      data: (list) => DropdownButtonFormField<Brand>(
        value: list.where((b) => b.id == selected?.id).firstOrNull,
        decoration: _dec('Бренд'),
        items: list
            .map((b) => DropdownMenuItem(value: b, child: Text(b.name)))
            .toList(),
        onChanged: onChanged,
        isExpanded: true,
      ),
    );
  }
}

// ── Region picker ──
class _RegionPicker extends ConsumerStatefulWidget {
  final List<Region> selected;
  final ValueChanged<Region> onChanged;
  const _RegionPicker({required this.selected, required this.onChanged});

  @override
  ConsumerState<_RegionPicker> createState() => _RegionPickerState();
}

class _RegionPickerState extends ConsumerState<_RegionPicker> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(regionsProvider);
    return async.when(
      loading: () => const _LoadingField('Регионы'),
      error: (_, __) => const _ErrorField('Регионы'),
      data: (list) {
        final filtered = _search.isEmpty
            ? list
            : list
                .where((r) =>
                    r.name.toLowerCase().contains(_search.toLowerCase()))
                .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              decoration: _dec('Поиск региона',
                  suffix: null).copyWith(hintText: 'Поиск...'),
              onChanged: (v) => setState(() => _search = v),
            ),
            if (widget.selected.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: widget.selected
                    .map((r) => Chip(
                          label: Text(r.name, style: const TextStyle(fontSize: 12)),
                          deleteIcon: const Icon(Icons.close, size: 14),
                          onDeleted: () => widget.onChanged(r),
                          backgroundColor: kAccentLight,
                          side: BorderSide.none,
                          padding: EdgeInsets.zero,
                        ))
                    .toList(),
              ),
            ],
            const SizedBox(height: 8),
            Container(
              height: 180,
              decoration: BoxDecoration(
                border: Border.all(color: kBorder),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final r = filtered[i];
                  final sel = widget.selected.any((s) => s.id == r.id);
                  return CheckboxListTile(
                    dense: true,
                    title: Text(r.name, style: const TextStyle(fontSize: 13)),
                    value: sel,
                    onChanged: (_) => widget.onChanged(r),
                    activeColor: kAccent,
                    controlAffinity: ListTileControlAffinity.leading,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Gender picker ──
class _GenderPicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _GenderPicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
        value: value,
        decoration: _dec('Пол'),
        items: const [
          DropdownMenuItem(value: 'ALL', child: Text('Все')),
          DropdownMenuItem(value: 'MALE', child: Text('Мужчины')),
          DropdownMenuItem(value: 'FEMALE', child: Text('Женщины')),
        ],
        onChanged: (v) { if (v != null) onChanged(v); },
      );
}

// ── Age range ──
class _AgeRangePicker extends StatelessWidget {
  final RangeValues value;
  final ValueChanged<RangeValues> onChanged;
  const _AgeRangePicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              'Возраст: ${value.start.round()} – ${value.end.round()} лет',
              style: const TextStyle(fontSize: 13, color: kTextSecondary)),
          RangeSlider(
            values: value,
            min: 12,
            max: 80,
            divisions: 68,
            activeColor: kAccent,
            onChanged: onChanged,
          ),
        ],
      );
}

// ── Income picker ──
class _IncomePicker extends StatelessWidget {
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  const _IncomePicker({required this.selected, required this.onToggle});

  static const _levels = [
    ('A', 'A — высокий'),
    ('B', 'B — выше среднего'),
    ('C', 'C — средний'),
    ('D', 'D — ниже среднего'),
  ];

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Уровень дохода',
              style: TextStyle(fontSize: 13, color: kTextSecondary)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: _levels.map((l) {
              final sel = selected.contains(l.$1);
              return FilterChip(
                label: Text(l.$2, style: const TextStyle(fontSize: 12)),
                selected: sel,
                onSelected: (_) => onToggle(l.$1),
                selectedColor: kAccentLight,
                checkmarkColor: kAccent,
                side: BorderSide(color: sel ? kAccent : kBorder),
              );
            }).toList(),
          ),
        ],
      );
}

// ── Error banner ──
class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner(this.message);

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFEBEE),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFC62828).withValues(alpha: 0.3)),
        ),
        child: Text(message,
            style: const TextStyle(color: Color(0xFFC62828), fontSize: 13)),
      );
}

// ── Loading / Error field placeholders ──
class _LoadingField extends StatelessWidget {
  final String label;
  const _LoadingField(this.label);

  @override
  Widget build(BuildContext context) => InputDecorator(
        decoration: _dec(label),
        child: const SizedBox(
            height: 16,
            child: LinearProgressIndicator(color: kAccent)),
      );
}

class _ErrorField extends StatelessWidget {
  final String label;
  const _ErrorField(this.label);

  @override
  Widget build(BuildContext context) => InputDecorator(
        decoration: _dec(label),
        child: const Text('Ошибка загрузки',
            style: TextStyle(color: Colors.red, fontSize: 13)),
      );
}
