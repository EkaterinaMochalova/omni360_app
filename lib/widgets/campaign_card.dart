import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/campaign.dart';

class CampaignCard extends StatelessWidget {
  final Campaign campaign;
  final VoidCallback onTap;

  const CampaignCard({
    super.key,
    required this.campaign,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(locale: 'ru_RU', symbol: '₽', decimalDigits: 0);
    final statusColor = switch (campaign.status.toLowerCase()) {
      'active' || 'running' => Colors.greenAccent,
      'paused' => Colors.orangeAccent,
      _ => Colors.white38,
    };

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF16213E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    campaign.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.chevron_right,
                    color: Colors.white24, size: 20),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (campaign.type != null) ...[
                  _Tag(campaign.type!),
                  const SizedBox(width: 8),
                ],
                _Tag(campaign.status, color: statusColor.withValues(alpha: 0.15),
                    textColor: statusColor),
                const Spacer(),
                if (campaign.budget != null)
                  Text(
                    fmt.format(campaign.budget),
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w500),
                  ),
              ],
            ),
            if (campaign.budget != null && campaign.spent != null) ...[
              const SizedBox(height: 10),
              _BudgetBar(spent: campaign.spent!, total: campaign.budget!),
            ],
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color? color;
  final Color? textColor;

  const _Tag(this.label, {this.color, this.textColor});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color ?? Colors.white10,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
              color: textColor ?? Colors.white54, fontSize: 11),
        ),
      );
}

class _BudgetBar extends StatelessWidget {
  final double spent;
  final double total;

  const _BudgetBar({required this.spent, required this.total});

  @override
  Widget build(BuildContext context) {
    final ratio = total > 0 ? (spent / total).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            backgroundColor: Colors.white10,
            valueColor: AlwaysStoppedAnimation(
                ratio > 0.8 ? Colors.redAccent : const Color(0xFF6C63FF)),
            minHeight: 4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${(ratio * 100).toStringAsFixed(0)}% потрачено',
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ],
    );
  }
}
