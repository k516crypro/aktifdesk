import 'package:flutter/material.dart';

import '../../app/remote_host_controller.dart';
import '../../core/control/control_protocol.dart';
import '../../core/control/phone_control_server.dart';
import '../widgets/host_permissions_checklist.dart';
import 'phone_onboarding.dart';
import 'settings_screen.dart';

/// Phone-as-host: pairing code, permission checklist, connected status.
class RemoteHostShell extends StatelessWidget {
  const RemoteHostShell({super.key, required this.c, this.onLeave});
  final RemoteHostController c;
  final VoidCallback? onLeave;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          if (c.stage == RemoteHostStage.code && c.connection != ControlConnection.connected) {
            return _WaitingView(c: c, onLeave: onLeave);
          }
          return _ConnectedView(c: c, onLeave: onLeave);
        },
      );
}

class _WaitingView extends StatelessWidget {
  const _WaitingView({required this.c, this.onLeave});
  final RemoteHostController c;
  final VoidCallback? onLeave;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Uzaktan host'),
        leading: onLeave == null
            ? null
            : IconButton(icon: const Icon(Icons.arrow_back), onPressed: onLeave),
        actions: [
          if (c.settings != null)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SettingsScreen(
                      settings: c.settings!,
                      onChanged: c.onSettingsChanged,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PairingCodeView(
            code: c.pairingCode,
            serviceRunning: c.connection != ControlConnection.stopped,
            error: c.message,
            onNewCode: c.newCode,
            onBack: null,
            waitingLabel: 'Kumanda bekleniyor…',
            hint: 'Bunu diğer telefon veya PC\'deki AktifDesk\'e gir',
            footer: 'Bu telefon uzaktan yönetilecek. Aynı Wi-Fi ağında olun. '
                'Önce aşağıdaki Tam erişim izinlerini açın.',
            embedded: true,
          ),
          const SizedBox(height: 8),
          HostPermissionsChecklist(
            status: c.permissions,
            onOpen: c.openPermission,
            onRefresh: c.refreshPermissions,
          ),
        ],
      ),
    );
  }
}

class _ConnectedView extends StatelessWidget {
  const _ConnectedView({required this.c, this.onLeave});
  final RemoteHostController c;
  final VoidCallback? onLeave;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final connected = c.connection == ControlConnection.connected;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Uzaktan mod'),
        leading: onLeave == null
            ? null
            : IconButton(icon: const Icon(Icons.arrow_back), onPressed: onLeave),
        actions: [
          Chip(
            avatar: CircleAvatar(
              backgroundColor: connected ? Colors.green : Colors.orange,
              radius: 6,
            ),
            label: Text(connected ? 'Bağlı' : 'Bekleniyor'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Icon(Icons.phone_android, color: t.colorScheme.primary, size: 40),
              title: Text(c.deviceName),
              subtitle: Text(connected
                  ? 'Kumanda: ${c.control.hostName ?? c.lastController?.name ?? "bağlı"}'
                  : 'Bağlantı koptu — kodla yeniden eşleştirilebilir'),
            ),
          ),
          if (c.message != null)
            Card(
              child: ListTile(
                title: Text(c.message!),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => c.message = null,
                ),
              ),
            ),
          HostPermissionsChecklist(
            status: c.permissions,
            onOpen: c.openPermission,
            onRefresh: c.refreshPermissions,
            compact: true,
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Ne çalışıyor', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('• Kodla eşleşme (IP yok)'),
                  const Text('• Ön plan servisi + kalıcı bildirim (kararlı oturum)'),
                  const Text('• Uyanık tut / ekranı uyandır'),
                  Text('• Dokunma / kaydırma / Geri-Ana ekran '
                      '(${c.accessibilityReady ? "Erişilebilirlik açık" : "Erişilebilirlik kapalı"})'),
                  const Text('• Güvenli uygulama veya http(s) URL aç'),
                  const SizedBox(height: 8),
                  const Text(
                    'Ekran aynalama (MediaProjection) henüz yok. '
                    'Güvenli kilit (PIN) uzaktan açılamaz. Cihaz yöneticisi / silme yok.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          if (!connected) ...[
            const SizedBox(height: 8),
            Text('Eşleştirme kodun', style: t.textTheme.titleMedium),
            const SizedBox(height: 8),
            Center(
              child: Text(
                PairingCode.format(c.pairingCode),
                style: t.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 6,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: c.newCode,
              icon: const Icon(Icons.refresh),
              label: const Text('Yeni kod'),
            ),
          ],
        ],
      ),
    );
  }
}
