import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/omni360_client.dart';
import '../models/reference.dart';

List<T> _parseList<T>(dynamic data, T Function(Map<String, dynamic>) fromJson) {
  List items;
  if (data is List) {
    items = data;
  } else if (data is Map && data['content'] is List) {
    items = data['content'] as List;
  } else if (data is Map && data['data'] is List) {
    items = data['data'] as List;
  } else {
    return [];
  }
  return items
      .whereType<Map<String, dynamic>>()
      .map(fromJson)
      .toList();
}

final customersProvider = FutureProvider<List<Customer>>((ref) async {
  final r = await Omni360Client().dio.get(
        '/api/v1.0/clients/customers',
        queryParameters: {'page': 0, 'size': 200},
      );
  return _parseList(r.data, Customer.fromJson);
});

final brandsProvider = FutureProvider<List<Brand>>((ref) async {
  final r = await Omni360Client().dio.get(
        '/api/v1.0/clients/brands',
        queryParameters: {'page': 0, 'size': 200},
      );
  return _parseList(r.data, Brand.fromJson);
});

final regionsProvider = FutureProvider<List<Region>>((ref) async {
  final r = await Omni360Client().dio.get('/api/v1.0/clients/regions');
  return _parseList(r.data, Region.fromJson);
});
