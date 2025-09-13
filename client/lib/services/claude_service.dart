import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/issue.dart';

class ClaudeService {
  static final String? _apiKey = dotenv.env['CLAUDE_API_KEY'];

  static Future<Map<String, dynamic>> analyzeIssue(File image) async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      throw Exception('Claude API key not configured');
    }

    final bytes = await image.readAsBytes();
    final base64Image = base64Encode(bytes);

    final response = await http.post(
      Uri.parse('https://api.anthropic.com/v1/messages'),
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': _apiKey!,
        'anthropic-version': '2023-06-01',
      },
      body: jsonEncode({
        'model': 'claude-3-haiku-20240307',
        'max_tokens': 300,
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'input_text',
                'text':
                    'Identify the issue in this photo and return JSON with title, category, and description. Category must be one of: litter, graffiti, pothole, broken_streetlight, other.'
              },
              {
                'type': 'input_image',
                'source': {
                  'type': 'base64',
                  'media_type': 'image/jpeg',
                  'data': base64Image,
                }
              }
            ]
          }
        ],
        'response_format': {
          'type': 'json_schema',
          'json_schema': {
            'name': 'issue',
            'schema': {
              'type': 'object',
              'properties': {
                'title': {'type': 'string'},
                'category': {
                  'type': 'string',
                  'enum': [
                    'litter',
                    'graffiti',
                    'pothole',
                    'broken_streetlight',
                    'other'
                  ]
                },
                'description': {'type': 'string'}
              },
              'required': ['title', 'category', 'description']
            }
          }
        }
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Claude API error: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    final content = data['content'];
    if (content is List && content.isNotEmpty) {
      final first = content[0];
      if (first is Map && first.containsKey('json')) {
        return Map<String, dynamic>.from(first['json']);
      } else if (first is Map && first.containsKey('text')) {
        return Map<String, dynamic>.from(jsonDecode(first['text']));
      }
    }
    throw Exception('Invalid response from Claude');
  }

  static IssueCategory categoryFromString(String category) {
    return Issue.categoryFromString(category);
  }
}

