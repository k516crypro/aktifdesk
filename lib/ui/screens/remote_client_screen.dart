import 'package:flutter/material.dart';

import '../../app/remote_client_controller.dart';
import '../widgets/pair_code_form.dart';

/// Enter a pairing code to remote-control another phone.
class RemoteClientShell extends StatelessWidget {
  const RemoteClientShell({super.key, required this.c, this.onLeave});
  final RemoteClientController c;
  final VoidCallback? onLeave;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          if (!c.connected) {
            return _PairPage(c: c, onLeave: onLeave);
          }
          return _ControlPage(c: c, onLeave: onLeave);
        },
      );
}

class _PairPage extends StatelessWidget {
  const _PairPage({required this.c, this.onLeave});
  final RemoteClientController c;
  final VoidCallback? onLeave;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Uzaktan bağlan'),
          leading: onLeave == null
              ? null
              : IconButton(icon: const Icon(Icons.arrow_back), onPressed: onLeave),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.link, size: 64, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 12),
                  Text(
                    'Uzaktan yönetilecek telefondaki kodu gir',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 24),
                  PairCodeForm(
                    onPair: c.pairWithCode,
                    stage: c.pairStage,
                    message: c.pairMessage,
                  ),
                  if (c.pairedHosts.isNotEmpty) ...[
                    const Divider(height: 32),
                    const Text('Kayıtlı telefonlar'),
                    for (final h in c.pairedHosts)
                      ListTile(
                        leading: const Icon(Icons.phone_android),
                        title: Text(h.name),
                        trailing: IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: () => c.reconnect(h),
                        ),
                        onTap: () => c.reconnect(h),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
}

class _ControlPage extends StatefulWidget {
  const _ControlPage({required this.c, this.onLeave});
  final RemoteClientController c;
  final VoidCallback? onLeave;
  @override
  State<_ControlPage> createState() => _ControlPageState();
}

class _ControlPageState extends State<_ControlPage> {
  final _url = TextEditingController(text: 'https://');
  final _pkg = TextEditingController();

  @override
  void dispose() {
    _url.dispose();
    _pkg.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final st = c.hostStatus;
    return Scaffold(
      appBar: AppBar(
        title: Text(c.activeHost?.name ?? 'Uzaktan'),
        leading: widget.onLeave == null
            ? null
            : IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onLeave),
        actions: [
          const Chip(
            avatar: CircleAvatar(backgroundColor: Colors.green, radius: 6),
            label: Text('Bağlı'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (c.message != null)
            Card(
              child: ListTile(
                title: Text(c.message!),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => c.message = null),
                ),
              ),
            ),
          Card(
            child: ListTile(
              title: Text(st?.deviceName ?? c.activeHost?.name ?? 'Telefon'),
              subtitle: Text(
                'Uyanık tut: ${st?.keepAwake == true ? "açık" : "kapalı"} • '
                'Ekran paylaşımı: ${st?.screenShare ?? "?"} '
                '${st?.message != null ? "• ${st!.message}" : ""}',
              ),
              trailing: c.busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(icon: const Icon(Icons.refresh), onPressed: c.ping),
            ),
          ),
          SwitchListTile(
            title: const Text('Telefonda ekranı açık tut'),
            value: st?.keepAwake ?? false,
            onChanged: c.busy ? null : c.setKeepAwake,
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: c.busy ? null : c.unlock,
                icon: const Icon(Icons.lock_open),
                label: const Text('Uyandır / kilit dene'),
              ),
              OutlinedButton.icon(
                onPressed: c.busy ? null : c.requestScreenShare,
                icon: const Icon(Icons.screen_share_outlined),
                label: const Text('Ekran paylaş (yakında)'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Uygulama / URL aç', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _url,
            decoration: const InputDecoration(
              labelText: 'http(s) URL',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: c.busy ? null : () => c.launchUrl(_url.text.trim()),
            child: const Text('URL aç'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pkg,
            decoration: const InputDecoration(
              labelText: 'Paket adı (örn. com.android.chrome)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: c.busy ? null : () => c.launchPackage(_pkg.text.trim()),
            child: const Text('Paketi aç'),
          ),
          const SizedBox(height: 24),
          const Text(
            'Not: Tam ekran aynalama ve dokunma enjeksiyonu root / MediaProjection '
            'olmadan sınırlı. Güvenli kilit (PIN) uzaktan açılamaz.',
            style: TextStyle(fontSize: 12),
          ),
          TextButton(
            onPressed: () async {
              final id = c.activeHost?.id;
              if (id != null) await c.forget(id);
            },
            child: const Text('Eşleştirmeyi kaldır'),
          ),
        ],
      ),
    );
  }
}
