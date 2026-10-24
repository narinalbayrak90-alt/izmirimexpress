import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../services/support_service.dart';

/// Admin's support contact details — the Help & Support screen's top
/// section, above the contact form.
final supportContactInfoProvider = FutureProvider.autoDispose<SupportContactInfo>((ref) {
  return ref.watch(supportServiceProvider).contactInfo();
});
