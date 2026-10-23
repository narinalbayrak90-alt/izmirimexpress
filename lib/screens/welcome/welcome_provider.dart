import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import 'welcome_content.dart';

/// Fetches admin-configured welcome screen content from `GET /welcome`.
final welcomeContentProvider = FutureProvider<WelcomeContent>((ref) async {
  final data = await ref.watch(apiClientProvider).get('/welcome');
  return WelcomeContent.fromJson(data as Map<String, dynamic>);
});
