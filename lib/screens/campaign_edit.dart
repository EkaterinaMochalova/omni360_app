import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/omni360_client.dart';
import '../models/campaign.dart';
import '../providers/campaigns_provider.dart';

class CampaignEditScreen extends ConsumerStatefulWidget {
  final Campaign campaign;

  const CampaignEditScreen({super.key, required this.campaign});

  @override
  ConsumerState<CampaignEditScreen> createState() => _CampaignEditScreenState();
}

class _CampaignEditScreenState extends ConsumerState<CampaignEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _budgetCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.campaign.name);
    _budgetCtrl = TextEditingController(
        text: widget.campaign.budget?.toStringAsFixed(0) ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _budgetCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await Omni360Client().dio.put(
        '/api/v1.0/clients/campaigns/${widget.campaign.id}',
        data: {
          'name': _nameCtrl.text.trim(),
          if (_budgetCtrl.text.isNotEmpty)
            'budget': double.parse(_budgetCtrl.text),
        },
      );
      ref.invalidate(campaignDetailProvider(widget.campaign.id));
      ref.read(campaignsProvider.notifier).fetch();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Кампания обновлена'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16213E),
        elevation: 0,
        title: const Text('Редактировать кампанию',
            style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Сохранить',
                    style: TextStyle(color: Color(0xFF6C63FF))),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('Название кампании'),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Введите название' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _budgetCtrl,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.number,
                decoration: _inputDecoration('Бюджет (₽)'),
                validator: (v) {
                  if (v != null && v.isNotEmpty && double.tryParse(v) == null) {
                    return 'Введите число';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        filled: true,
        fillColor: Colors.white10,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF6C63FF)),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
      );
}
