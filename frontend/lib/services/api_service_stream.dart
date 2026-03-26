// frontend/lib/services/api_service_stream.dart
//
// Add this file to your project, then import it in agent_screen.dart.
// It adds a `streamPost()` method to the ApiService that handles
// Server-Sent Events (SSE) from the backend streaming endpoints.
//
// Usage:
//   final stream = api.streamPost('/agent/run-stream', {...});
//   await for (final event in stream) {
//     // event is a StreamEvent — handle it in the screen
//   }

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';          // your existing api_service.dart
import '../config/app_constants.dart';

// We extend the existing ApiService class
extension ApiStreamExtension on ApiService {

  /// Stream a POST request and yield parsed SSE events.
  Stream<StreamEvent> streamPost(String path, Map<String, dynamic> body) async* {
    final token = await getToken();   // your existing getToken() method
    final uri   = Uri.parse('$kApiBaseUrl$path');

    final request = http.Request('POST', uri)
      ..headers.addAll({
        'Content-Type':  'application/json',
        'Accept':        'text/event-stream',
        if (token != null) 'Authorization': 'Bearer $token',
      })
      ..body = jsonEncode(body);

    try {
      final response = await request.send();

      if (response.statusCode != 200) {
        yield StreamEvent('error', {'message': 'HTTP ${response.statusCode}'});
        await response.stream.drain<void>();
        return;
      }

      String buffer = '';

      await for (final chunk in response.stream.transform(utf8.decoder)) {
        buffer += chunk;

        // SSE events are separated by double newlines
        while (buffer.contains('\n\n')) {
          final idx    = buffer.indexOf('\n\n');
          final rawEvt = buffer.substring(0, idx);
          buffer       = buffer.substring(idx + 2);

          String? eventType;
          String? eventData;

          for (final line in rawEvt.split('\n')) {
            if (line.startsWith('event: ')) {
              eventType = line.substring(7).trim();
            } else if (line.startsWith('data: ')) {
              eventData = line.substring(6).trim();
            }
          }

          if (eventType != null && eventData != null) {
            try {
              final parsed = jsonDecode(eventData) as Map<String, dynamic>;
              yield StreamEvent(eventType, parsed);
            } catch (_) {
              yield StreamEvent(eventType, {'raw': eventData});
            }
          }
        }
      }
    } catch (e) {
      yield StreamEvent('error', {'message': e.toString()});
    }
  }
}

/// Parsed SSE event from the APEX streaming endpoint.
class StreamEvent {
  final String type;
  final Map<String, dynamic> data;
  const StreamEvent(this.type, this.data);
}
