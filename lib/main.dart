import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app_settings.dart';
import 'app/client_controller.dart';
import 'app/host_controller.dart';
import 'app/remote_client_controller.dart';
import 'app/remote_host_controller.dart';
import 'ui/screens/host_screen.dart';
import 'ui/screens/phone_onboarding.dart';
import 'ui/screens/remote_client_screen.dart';
import 'ui/screens/remote_host_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/screens/tutorial_screen.dart';
import 'ui/theme/aktif_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final isHost = Platform.isWindows ||
      const bool.fromEnvironment('AKTIFDESK_HOST', defaultValue: false);
  if (isHost) {
    final c = HostController();
    await c.init();
    runApp(AktifDeskApp(home: _HostShell(c: c)));
  } else {
    runApp(const AktifDeskApp(home: _AndroidRoot()));
  }
}

class AktifDeskApp extends StatelessWidget {
  const AktifDeskApp({super.key, required this.home});
  final Widget home;
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'AktifDesk',
        debugShowCheckedModeBanner: false,
        theme: AktifTheme.light(),
        darkTheme: AktifTheme.dark(),
        home: home,
      );
}

class _AndroidRoot extends StatefulWidget {
  const _AndroidRoot();
  @override
  State<_AndroidRoot> createState() => _AndroidRootState();
}

class _AndroidRootState extends State<_AndroidRoot> {
  PhoneLaunchRole? _role;
  bool _loading = true;
  bool _showTutorial = false;
  AppSettings? _settings;
  ClientController? _pcClient;
  RemoteHostController? _remoteHost;
  RemoteClientController? _remoteClient;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final settings = await AppSettings.load();
    _settings = settings;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('phone.role');
    final role = switch (raw) {
      'managePc' => PhoneLaunchRole.managePc,
      'remoteHost' => PhoneLaunchRole.remoteHost,
      'remoteClient' => PhoneLaunchRole.remoteClient,
      _ => null,
    };
    if (role != null) {
      await _enter(role, persist: false);
    }
    if (mounted) {
      setState(() {
        _loading = false;
        _showTutorial = !settings.tutorialDone && role == null;
      });
    }
  }

  Future<void> _enter(PhoneLaunchRole role, {bool persist = true}) async {
    if (persist) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'phone.role',
        switch (role) {
          PhoneLaunchRole.managePc => 'managePc',
          PhoneLaunchRole.remoteHost => 'remoteHost',
          PhoneLaunchRole.remoteClient => 'remoteClient',
        },
      );
    }
    await _disposeControllers();
    final settings = _settings ?? await AppSettings.load();
    _settings = settings;
    switch (role) {
      case PhoneLaunchRole.managePc:
        final c = ClientController(skipWelcome: true);
        await c.init();
        _pcClient = c;
      case PhoneLaunchRole.remoteHost:
        final c = RemoteHostController(settings: settings);
        await c.init();
        _remoteHost = c;
      case PhoneLaunchRole.remoteClient:
        final c = RemoteClientController(settings: settings);
        await c.init();
        _remoteClient = c;
    }
    if (mounted) setState(() => _role = role);
  }

  Future<void> _disposeControllers() async {
    _pcClient?.dispose();
    _remoteHost?.dispose();
    _remoteClient?.dispose();
    _pcClient = null;
    _remoteHost = null;
    _remoteClient = null;
  }

  Future<void> _leaveToWelcome() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('phone.role');
    await _disposeControllers();
    if (mounted) setState(() => _role = null);
  }

  @override
  void dispose() {
    _pcClient?.dispose();
    _remoteHost?.dispose();
    _remoteClient?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_showTutorial && _settings != null) {
      return TutorialScreen(
        settings: _settings!,
        onDone: () => setState(() => _showTutorial = false),
      );
    }
    final role = _role;
    if (role == null) {
      return WelcomeView(
        onContinue: () => _enter(PhoneLaunchRole.managePc),
        onPickRole: _enter,
        onOpenSettings: _settings == null
            ? null
            : () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SettingsScreen(
                      settings: _settings!,
                    ),
                  ),
                );
              },
      );
    }
    return switch (role) {
      PhoneLaunchRole.managePc => PhoneShell(c: _pcClient!, onLeave: _leaveToWelcome),
      PhoneLaunchRole.remoteHost =>
        RemoteHostShell(c: _remoteHost!, onLeave: _leaveToWelcome),
      PhoneLaunchRole.remoteClient =>
        RemoteClientShell(c: _remoteClient!, onLeave: _leaveToWelcome),
    };
  }
}

// Re-export for WelcomeView settings button — import settings in main

class _HostShell extends StatefulWidget {
  const _HostShell({required this.c});
  final HostController c;
  @override
  State<_HostShell> createState() => _HostShellState();
}

class _HostShellState extends State<_HostShell> {
  late final AppLifecycleListener _l = AppLifecycleListener(
    onExitRequested: () async {
      await widget.c.shutdown();
      return AppExitResponse.exit;
    },
    onDetach: () => widget.c.shutdown(),
  );

  @override
  void initState() {
    super.initState();
    _l.hashCode;
  }

  @override
  void dispose() {
    _l.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HostScreen(c: widget.c);
}
