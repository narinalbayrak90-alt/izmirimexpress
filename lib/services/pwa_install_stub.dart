// Mobile builds: the app is already installed, so there's nothing to offer.

bool isStandalone() => true;

bool isIos() => false;

bool canPrompt() => false;

Future<bool> prompt() async => false;

Stream<void> changes() => const Stream.empty();
