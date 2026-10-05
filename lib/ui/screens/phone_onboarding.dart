import 'package:flutter/material.dart';

import '../../app/client_controller.dart';
import '../../core/control/control_protocol.dart';
import '../../core/control/phone_control_server.dart';
import 'client_screen.dart';

/// Phone root: Welcome → pairing code → success → dashboard.
class PhoneShell extends StatelessWidget {
  const PhoneShell({super.key, required this.c, this.onLeave});
  final ClientController c;
  final VoidCallback? onLeave;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final Widget page = switch (c.stage) {
        PhoneStage.welcome => WelcomeView(
          onContinue: c.continueFromWelcome,
          // Role already chosen at root; keep a single continue for this flow.
        ),
        PhoneStage.code => PairingCodeView(
          code: c.pairingCode,
          serviceRunning: c.connection != ControlConnection.stopped,
          error: c.message,
          onNewCode: c.newCode,
          onBack: c.pairedPcs.isEmpty ? onLeave : c.openDashboard,
        ),
        PhoneStage.success => PairedSuccessView(
          pcName: c.lastPairedPc?.name ?? c.control.hostName,
          onContinue: c.openDashboard,
        ),
        PhoneStage.dashboard => ClientScreen(c: c),
      };
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: KeyedSubtree(key: ValueKey(c.stage), child: page),
      );
    },
  );
}

/// What the user picks on first launch.
enum PhoneLaunchRole { managePc, remoteHost, remoteClient }

class WelcomeView extends StatelessWidget {
  const WelcomeView({
    super.key,
    required this.onContinue,
    this.onPickRole,
    this.onOpenSettings,
  });

  /// Legacy single-button path (PC manage). Prefer [onPickRole].
  final VoidCallback onContinue;
  final void Function(PhoneLaunchRole role)? onPickRole;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    void pick(PhoneLaunchRole r) {
      if (onPickRole != null) {
        onPickRole!(r);
      } else if (r == PhoneLaunchRole.managePc) {
        onContinue();
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(''),
        actions: [
          if (onOpenSettings != null)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              onPressed: onOpenSettings,
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            children: [
              const Spacer(flex: 2),
              Image.asset(
                'assets/branding/aktifdesk-icon.jpg',
                height: 96,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
              const SizedBox(height: 16),
              Text(
                'Hoş geldin — ne yapmak istiyorsun?',
                textAlign: TextAlign.center,
                style: t.textTheme.titleMedium?.copyWith(
                  color: t.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              _RoleButton(
                key: const Key('role-manage-pc'),
                icon: Icons.desktop_windows_rounded,
                title: "PC'yi yönet",
                subtitle: 'Bu telefon Windows PC\'ye bağlanır',
                onTap: () => pick(PhoneLaunchRole.managePc),
              ),
              const SizedBox(height: 10),
              _RoleButton(
                key: const Key('role-remote-host'),
                icon: Icons.phonelink_setup,
                title: 'Bu telefonu uzaktan yönet',
                subtitle: 'Kod göster; başka cihaz bu telefonu yönetsin',
                onTap: () => pick(PhoneLaunchRole.remoteHost),
              ),
              const SizedBox(height: 10),
              _RoleButton(
                key: const Key('role-remote-client'),
                icon: Icons.settings_remote,
                title: 'Uzaktan bağlan',
                subtitle: 'Başka telefondaki kodu girip onu yönet',
                onTap: () => pick(PhoneLaunchRole.remoteClient),
              ),
              if (onPickRole == null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const Key('welcome-continue'),
                      onPressed: onContinue,
                      child: const Text('Devam et'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleButton extends StatelessWidget {
  const _RoleButton({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, size: 36, color: t.colorScheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: t.textTheme.bodySmall),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class PairingCodeView extends StatelessWidget {
  const PairingCodeView({
    super.key,
    required this.code,
    this.serviceRunning = true,
    this.error,
    this.onNewCode,
    this.onBack,
    this.waitingLabel = 'PC bekleniyor…',
    this.hint = 'Bunu PC\'deki cihazına gir',
    this.footer = 'Telefon ve PC aynı Wi-Fi ağında olmalı.',
    this.embedded = false,
  });

  final String code;
  final bool serviceRunning;
  final String? error;
  final VoidCallback? onNewCode;
  final VoidCallback? onBack;
  final String waitingLabel;
  final String hint;
  final String footer;

  /// When true, return only the code card (no Scaffold) for nesting in ListViews.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final body = Padding(
      padding: EdgeInsets.all(embedded ? 8 : 32),
      child: Column(
        mainAxisSize: embedded ? MainAxisSize.min : MainAxisSize.max,
        children: [
          if (!embedded) const Spacer(),
          Text('Eşleştirme kodun', style: t.textTheme.titleLarge),
          const SizedBox(height: 16),
          FittedBox(
            child: Text(
              PairingCode.format(code),
              key: const Key('pairing-code'),
              style: t.textTheme.displayLarge?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 6,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: t.textTheme.titleMedium,
          ),
          const SizedBox(height: 24),
          if (serviceRunning)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Flexible(child: Text(waitingLabel, style: t.textTheme.bodyMedium)),
              ],
            )
          else
            Text('Bağlantı servisi çalışmıyor', style: TextStyle(color: t.colorScheme.error)),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: t.colorScheme.error),
              ),
            ),
          if (!embedded) const Spacer(),
          const SizedBox(height: 12),
          Text(
            footer,
            textAlign: TextAlign.center,
            style: t.textTheme.bodySmall,
          ),
          if (onNewCode != null)
            TextButton.icon(
              onPressed: onNewCode,
              icon: const Icon(Icons.refresh),
              label: const Text('Yeni kod'),
            ),
        ],
      ),
    );
    if (embedded) return body;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AktifDesk'),
        leading: onBack == null
            ? null
            : IconButton(icon: const Icon(Icons.arrow_back), onPressed: onBack),
      ),
      body: SafeArea(child: body),
    );
  }
}

class PairedSuccessView extends StatelessWidget {
  const PairedSuccessView({super.key, this.pcName, required this.onContinue});
  final String? pcName;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              const Spacer(),
              const Icon(Icons.check_circle_rounded, size: 96, color: Colors.green),
              const SizedBox(height: 24),
              Text(
                'Şu an izinleri aldık',
                textAlign: TextAlign.center,
                style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Telefondan PC\'yi yönetebilirsin',
                textAlign: TextAlign.center,
                style: t.textTheme.titleMedium,
              ),
              if (pcName != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Chip(avatar: const Icon(Icons.computer, size: 18), label: Text(pcName!)),
                ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('success-continue'),
                  onPressed: onContinue,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: const Text('Devam et', style: TextStyle(fontSize: 18)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
