import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../features/household/domain/entities/household_invite.dart';
import '../features/household/presentation/pages/household_page.dart';
import '../features/groceries/presentation/pages/grocery_page.dart';

class HeladeraApp extends StatefulWidget {
  const HeladeraApp({super.key});

  @override
  State<HeladeraApp> createState() => _HeladeraAppState();
}

class _HeladeraAppState extends State<HeladeraApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  String? _lastOpenedInvite;
  String? _pendingInvite;

  @override
  void initState() {
    super.initState();
    _appLinks = AppLinks();
    _linkSubscription = _appLinks.uriLinkStream.listen(
      _handleIncomingLink,
      onError: (Object error, StackTrace stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'app links',
          ),
        );
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_openInitialLink());
    });
  }

  Future<void> _openInitialLink() async {
    try {
      final uri = await _appLinks.getInitialLink();
      if (mounted && uri != null) _handleIncomingLink(uri);
      final pendingInvite = _pendingInvite;
      if (mounted && pendingInvite != null) {
        _handleIncomingLink(Uri.parse(pendingInvite));
      }
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'app links',
        ),
      );
    }
  }

  void _handleIncomingLink(Uri uri) {
    if (!HouseholdInvite.supportsUri(uri)) return;
    final payload = uri.toString();
    if (_lastOpenedInvite == payload) return;
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      _pendingInvite = payload;
      return;
    }
    _lastOpenedInvite = payload;
    _pendingInvite = null;
    unawaited(
      navigator.push<void>(
        MaterialPageRoute(
          builder: (_) => HouseholdPage(invitePayload: payload),
        ),
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_linkSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const seedColor = Color(0xFF477A5B);
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'La heladera',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seedColor),
        scaffoldBackgroundColor: const Color(0xFFF7F8F4),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: const GroceryPage(),
    );
  }
}
