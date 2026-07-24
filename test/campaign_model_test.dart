import 'package:flutter_test/flutter_test.dart';
import 'package:omni360_app/models/campaign.dart';

void main() {
  test('parses city objects and string IDs returned by the API', () {
    final campaign = Campaign.fromJson({
      'id': 42,
      'name': 'Кампания',
      'state': 'RUNNING',
      'customer': {'id': '7', 'name': 'Рекламодатель'},
      'cities': [
        {'id': 390, 'name': 'городской округ Люберцы'},
        {'id': '419', 'name': 'городской округ Дзержинский'},
      ],
      'targetCity': {'id': '437', 'name': 'городской округ Котельники'},
    });

    expect(campaign.id, '42');
    expect(campaign.customerId, 7);
    expect(campaign.cityIds, [390, 419, 437]);
  });
}
