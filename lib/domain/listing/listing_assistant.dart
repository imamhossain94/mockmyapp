import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/on_device_ai.dart';
import '../providers/on_device_ai_provider.dart';
import 'listing_analysis.dart';
import 'listing_heuristics.dart';
import 'listing_prompt.dart';

/// Analyses a product description: the device's model where there is one,
/// then the built-in rules — the only analyser the wizard holds.
///
/// Decided per request, like the caption writer: a model can finish
/// downloading, or be switched on in Settings, while the wizard is open. A
/// model that says it is ready and then fails, or answers with nothing
/// usable, hands over to the rules rather than leaving the user with nothing.
class ListingAssistant {
  const ListingAssistant(this.model);

  /// The device's model, or null where there is none.
  final TextCompleter? model;

  /// What [analyze] would use right now.
  Future<AiEngine> engine() async {
    final m = model;
    if (m != null) {
      final status = await m.completerStatus();
      if (status.usable) return status.engine;
    }
    return AiEngine.phrasebook;
  }

  /// Analyses [description] on the device: its model, else the rules.
  Future<ListingAnalysis> analyze(
    String description, {
    String appName = '',
    int planLength = kDefaultPlanLength,
  }) async {
    final rules = heuristicAnalysis(
      description,
      appName: appName,
      planLength: planLength,
    );
    final m = model;
    if (m == null) return rules;
    try {
      final status = await m.completerStatus();
      if (!status.usable) return rules;
      final reply = await m.complete(
        instructions: kListingInstructions,
        prompt: listingPrompt(
          description,
          appName: appName,
          planLength: planLength,
        ),
      );
      return parseListingReply(
            reply,
            fallback: rules,
            description: description,
            engine: status.engine,
            planLength: planLength,
            appName: appName,
          ) ??
          rules;
    } on OnDeviceAiException {
      return rules;
    }
  }
}

final listingAssistantProvider = Provider<ListingAssistant>(
  (ref) => ListingAssistant(ref.watch(textCompleterProvider)),
);
