import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_constants.dart';

Future<void> remoteLog(String event, {String? deviceId, Map<String, dynamic>? meta}) async {
  try {
    await http.post(
      Uri.parse('$backendUrl/api/log'),
      headers: {'Content-Type': 'application/json', 'x-log-secret': logSecret},
      body: jsonEncode({'event': event, 'deviceId': deviceId, 'meta': meta ?? {}}),
    ).timeout(const Duration(seconds: 6));
  } catch (_) {}
}
