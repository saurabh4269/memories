import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/memories/join/join_event_page.dart';
import 'package:immich_mobile/memories/join/join_link.dart';
import 'package:immich_mobile/routing/router.dart';

/// Handles `memories://join?code=..&server=..` links at app start and resume.
///
/// Hook (first lines inside `_deepLinkBuilder` in `lib/main.dart`, after
/// `isColdStart` is computed):
/// ```dart
/// if (JoinDeepLinkHandler.canHandle(deepLink.uri)) {
///   return JoinDeepLinkHandler.handle(deepLink, ref, isColdStart: isColdStart);
/// }
/// ```
/// Works without a registered route: the join page is pushed as a native
/// route on the root navigator. On a cold start we let the splash screen
/// finish (auth/bootstrap) and open the page as soon as it navigates away.
class JoinDeepLinkHandler {
  const JoinDeepLinkHandler._();

  static const _splashRouteName = 'SplashScreenRoute';

  static bool canHandle(Uri uri) => JoinLink.isJoinUri(uri);

  static DeepLink handle(PlatformDeepLink deepLink, WidgetRef ref, {required bool isColdStart}) {
    final link = JoinLink.tryParseUri(deepLink.uri);
    if (link == null) {
      return isColdStart ? DeepLink.defaultPath : DeepLink.none;
    }
    final router = ref.read(appRouterProvider);
    if (isColdStart) {
      openWhenReady(router, link);
      return DeepLink.defaultPath;
    }
    _push(router, link);
    return DeepLink.none;
  }

  /// Opens the join page once [router] has left the splash screen.
  static void openWhenReady(StackRouter router, JoinLink link) {
    var done = false;
    late final VoidCallback listener;
    Timer? timeout;

    void finish() {
      if (done) {
        return;
      }
      done = true;
      timeout?.cancel();
      router.removeListener(listener);
      WidgetsBinding.instance.addPostFrameCallback((_) => _push(router, link));
    }

    listener = () {
      final name = router.current.name;
      if (name != _splashRouteName && router.stack.isNotEmpty) {
        finish();
      }
    };
    router.addListener(listener);
    // Safety net in case the router never notifies (e.g. already settled).
    timeout = Timer(const Duration(seconds: 8), finish);
  }

  static void _push(StackRouter router, JoinLink link) {
    unawaited(router.pushNativeRoute<void>(MaterialPageRoute<void>(builder: (_) => JoinEventPage(initialLink: link))));
  }
}
