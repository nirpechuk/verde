// lib/services/claude_service.dart
import 'dart:convert';
import 'dart:io';

import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../models/issue.dart';

class ClaudeService {
  static final String? _apiKey =
      dotenv.env['ANTHROPIC_API_KEY'] ?? dotenv.env['CLAUDE_API_KEY'];

  /// Analyze an image and return a structured Issue map:
  /// { "title": String, "category": "waste|pollution|water|other", "description": String }
  static Future<Map<String, dynamic>> analyzeIssue(File image) async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      throw Exception('Anthropic API key not configured');
    }

    final bytes = await image.readAsBytes();
    final base64Image = base64Encode(bytes);

    final mediaType = _guessMediaType(image.path);

    final client = AnthropicClient(apiKey: _apiKey);

    try {
      final res = await client.createMessage(
        request: CreateMessageRequest(
          model: const Model.modelId("claude-sonnet-4-20250514"),
          maxTokens: 300,
          messages: [
            Message(
              role: MessageRole.user,
              // Use blocks to combine text + image.
              // Image blocks are the documented way to send vision inputs. :contentReference[oaicite:1]{index=1}
              content: MessageContent.blocks([
                Block.text(
                  text: '''
You will be analyzing an image to identify the primary environmental issue shown and output your findings in a specific JSON format.

Your task is to examine this image carefully and identify the main environmental issue depicted. You must output ONLY a valid JSON object that matches the exact schema provided below.

JSON Schema:
{
  "title": "short human-friendly title",
  "category": "one of: waste | pollution | water | other",
  "description": "1-3 sentences describing the issue",
  "credibility_score": "integer 0-10"
}

Category Guidelines:
- "waste": Litter, garbage, plastic debris, landfills, improper disposal of materials
- "pollution": Air pollution, chemical contamination, oil spills, industrial emissions, smog
- "water": Water contamination, flooding, drought, water scarcity, algae blooms, water quality issues
- "other": Deforestation, habitat destruction, erosion, climate change effects, biodiversity loss, or any environmental issue not covered by the above categories

Important Rules:
- Respond with JSON only - no backticks, no explanatory text, no additional formatting
- The "category" field MUST be exactly one of these four words: waste, pollution, water, other
- The "title" should be concise and descriptive (under 10 words)
- The "description" should be 1-2 short sentences explaining what environmental issue you observe; only express facts in the image, no interpretations or analysis
- Focus on the PRIMARY or most prominent environmental issue if multiple issues are present
- The "credibility_score" should reflect how convincing the image evidence is of a real environmental issue: 8-10 for significant pollution with good evidence, 0-2 for no apparent impact, adjust within 0-10 according to the scale and scope of the environmental issue. For example basic trash should be low, a large oil spill should be high, and a damanged nature reserve should be in the middle.

Provide your JSON response:
''',
                ),
                Block.image(
                  source: ImageBlockSource(
                    data: base64Image,
                    mediaType: mediaType,
                    type: ImageBlockSourceType.base64,
                  ),
                ),
              ]),
            ),
          ],
        ),
      );

      // The SDK gives you a unified text view of the assistant reply:
      // `res.content.text` concatenates text blocks from the response. :contentReference[oaicite:2]{index=2}
      final rawText = res.content.text.trim();

      // Try strict JSON decode first, then a fallback extractor.
      Map<String, dynamic> payload;
      try {
        payload = Map<String, dynamic>.from(jsonDecode(rawText));
      } catch (_) {
        payload = _extractFirstJsonObject(rawText);
      }

      // Minimal validation / normalization.
      final category = (payload['category'] as String?)?.toLowerCase().trim();
      const allowed = {'waste', 'pollution', 'water', 'other'};
      if (category == null || !allowed.contains(category)) {
        payload['category'] = 'other';
      }

      for (final key in ['title', 'description']) {
        if (payload[key] == null || (payload[key] as String).trim().isEmpty) {
          throw Exception('Missing required "$key" in model output');
        }
      }

      // Normalize credibility score to 0-10 range
      var credibility = 0;
      if (payload['credibility_score'] is num) {
        credibility = (payload['credibility_score'] as num)
            .clamp(0, 10)
            .toInt();
      }
      payload['credibility_score'] = credibility;

      return payload;
    } finally {
      client.endSession();
    }
  }

  static IssueCategory categoryFromString(String category) {
    return Issue.categoryFromString(category);
  }

  // --- Helpers ---

  static ImageBlockSourceMediaType _guessMediaType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return ImageBlockSourceMediaType.imagePng;
    if (lower.endsWith('.webp')) return ImageBlockSourceMediaType.imageWebp;
    if (lower.endsWith('.gif')) return ImageBlockSourceMediaType.imageGif;
    return ImageBlockSourceMediaType.imageJpeg;
  }

  static Map<String, dynamic> _extractFirstJsonObject(String text) {
    // Fallback: pull the first {...} block and decode.
    final match = RegExp(r'\{[\s\S]*\}').firstMatch(text);
    if (match == null) {
      throw Exception('Model did not return JSON.');
    }
    final jsonStr = match.group(0)!;
    final obj = jsonDecode(jsonStr);
    if (obj is! Map<String, dynamic>) {
      throw Exception('Model returned non-object JSON.');
    }
    return obj;
  }
}
