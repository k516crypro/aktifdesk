import 'package:flutter/material.dart';

import '../../app/remote_host_controller.dart';
import '../../core/control/control_protocol.dart';
import '../../core/control/phone_control_server.dart';
import 'phone_onboarding.dart';

/// Phone-as-host: show pairing code, then connected status + basic info.
class RemoteHostShell extends StatelessWidget {
  const RemoteHostShell({super.key, required this.c, this.onLeave});
  final RemoteHostController c;
  final VoidCallback? onLeave;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          if (c.stage == RemoteHostStage.code && c.connection != ControlConnection.connected) {
            return PairingCodeView(
              code: c.pairingCode,
              serviceRunning: c.connection != ControlConnection.stopped,
              error: c.message,
              onNewCode: c.newCode,
              onBack: onLeave,
              waitingLabel: 'Kumanda bekleniyor…',
              hint: 'Bunu diğer telefon veya PC\'deki AktifDesk\'e gir',
              footer: 'Bu telefon uzaktan yönetilecek. Aynı Wi-Fi ağında olun.',
            );
          }
          return _ConnectedView(c: c, onLeave: onLeave);
        },
      );
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
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ne çalışıyor (MVP)', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('• Kodla eşleşme (IP yok)'),
                  Text('• Bağlı durumu'),
                  Text('• Uyanık tut / ekranı uyandır'),
                  Text('• Güvenli uygulama veya http(s) URL aç'),
                  Text('• Durum ping'),
                  SizedBox(height: 8),
                  Text(
                    'Ekran aynalama (MediaProjection) henüz yok — iskelet hazır. '
                    'Kök (root) olmadan tam dokunma enjeksiyonu ve güvenli kilit açma mümkün değil.',
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
