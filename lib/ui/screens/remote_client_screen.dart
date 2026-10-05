import 'package:flutter/material.dart';

import '../../app/remote_client_controller.dart';
import '../widgets/pair_code_form.dart';
import 'settings_screen.dart';

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
  Widget build(BuildContext context) {
    final uzak = c.settings?.uzakBaglanti == true;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Uzaktan bağlan'),
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
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.link_rounded, size: 56, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 12),
                Text(
                  'Uzaktan yönetilecek telefondaki kodu gir',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  uzak
                      ? 'Uzak bağlantı açık — LAN yoksa relay kullanılır'
                      : 'Önce aynı Wi‑Fi (LAN); bulunamazsa relay denenebilir',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                PairCodeForm(
                  onPair: c.pairWithCode,
                  stage: c.pairStage,
                  message: c.pairMessage,
                ),
                if (c.pairedHosts.isNotEmpty) ...[
                  const Divider(height: 32),
                  Text('Kayıtlı telefonlar', style: Theme.of(context).textTheme.titleSmall),
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
  final _text = TextEditingController();
  Offset? _panStart;
  Size? _padSize;

  @override
  void dispose() {
    _url.dispose();
    _pkg.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final st = c.hostStatus;
    final inputReady = st?.extras['inputReady'] == true || st?.extras['accessibility'] == true;
    return Scaffold(
      appBar: AppBar(
        title: Text(c.activeHost?.name ?? 'Uzaktan'),
        leading: widget.onLeave == null
            ? null
            : IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onLeave),
        actions: [
          Chip(
            avatar: CircleAvatar(
              backgroundColor: Colors.green,
              radius: 6,
            ),
            label: Text(c.viaRelay ? 'Uzak' : 'LAN'),
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
                'Uyanık: ${st?.keepAwake == true ? "açık" : "kapalı"} · '
                'Giriş: ${inputReady ? "hazır" : "Erişilebilirlik?"} '
                '${st?.message != null ? "· ${st!.message}" : ""}',
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
          const SizedBox(height: 8),
          Text('Dokunmatik pad', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          AspectRatio(
            aspectRatio: 9 / 16,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _padSize = Size(constraints.maxWidth, constraints.maxHeight);
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) {
                      final s = _padSize;
                      if (s == null || s.width == 0) return;
                      c.tapQuick(d.localPosition.dx / s.width, d.localPosition.dy / s.height);
                    },
                    onPanStart: (d) => _panStart = d.localPosition,
                    onPanEnd: (d) {
                      final start = _panStart;
                      final s = _padSize;
                      _panStart = null;
                      if (start == null || s == null || s.width == 0) return;
                      final end = d.localPosition;
                      final dx = (end.dx - start.dx).abs();
                      final dy = (end.dy - start.dy).abs();
                      if (dx < 12 && dy < 12) {
                        c.tapQuick(start.dx / s.width, start.dy / s.height);
                        return;
                      }
                      c.swipeQuick(
                        start.dx / s.width,
                        start.dy / s.height,
                        end.dx.clamp(0, s.width) / s.width,
                        end.dy.clamp(0, s.height) / s.height,
                      );
                    },
                    child: Center(
                      child: Text(
                        inputReady
                            ? 'Dokun / kaydır'
                            : 'Host’ta Erişilebilirlik gerekli',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: c.busy ? null : () => c.sendKey('back'),
                  child: const Text('Geri'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: c.busy ? null : () => c.sendKey('home'),
                  child: const Text('Ana ekran'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: c.busy ? null : () => c.sendKey('recents'),
                  child: const Text('Sonlar'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Ekranı açık tut'),
            value: st?.keepAwake ?? false,
            onChanged: c.busy ? null : c.setKeepAwake,
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: c.busy ? null : c.unlock,
                icon: const Icon(Icons.lock_open, size: 18),
                label: const Text('Uyandır'),
              ),
              OutlinedButton.icon(
                onPressed: c.busy ? null : c.requestScreenShare,
                icon: const Icon(Icons.screen_share_outlined, size: 18),
                label: const Text('Ekran (yakında)'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _text,
            decoration: InputDecoration(
              labelText: 'Metin yaz (odaklı alana)',
              suffixIcon: IconButton(
                icon: const Icon(Icons.send),
                onPressed: c.busy
                    ? null
                    : () {
                        c.sendText(_text.text);
                        _text.clear();
                      },
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Uygulama / URL', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _url,
            decoration: const InputDecoration(labelText: 'http(s) URL'),
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
              labelText: 'Paket adı',
              hintText: 'com.android.chrome',
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: c.busy ? null : () => c.launchPackage(_pkg.text.trim()),
            child: const Text('Paketi aç'),
          ),
          const SizedBox(height: 16),
          Text(
            'Güvenli kilit (PIN) açılamaz. Ekran aynalama henüz yok. '
            'Dokunma için host’ta Erişilebilirlik gerekir.',
            style: Theme.of(context).textTheme.bodySmall,
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
