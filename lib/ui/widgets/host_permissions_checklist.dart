import 'package:flutter/material.dart';

/// Turkish "Tam erişim" checklist — guides the user through critically needed
/// host permissions (Accessibility, battery, notifications, overlay…).
/// Does **not** request Device Admin / wipe capabilities.
class HostPermissionsChecklist extends StatelessWidget {
  const HostPermissionsChecklist({
    super.key,
    required this.status,
    required this.onOpen,
    this.onRefresh,
    this.compact = false,
  });

  final Map<String, Object?> status;
  final Future<bool> Function(String which) onOpen;
  final VoidCallback? onRefresh;
  final bool compact;

  bool _b(String k) => status[k] == true;

  @override
  Widget build(BuildContext context) {
    final items = <_PermItem>[
      _PermItem(
        id: 'accessibility',
        title: 'Erişilebilirlik (zorunlu)',
        subtitle:
            'Uzaktan dokunma, kaydırma ve Geri/Ana ekran için. Ayarlar → Erişilebilirlik → AktifDesk’i aç.',
        ok: _b('accessibility') || _b('accessibilityRunning'),
        critical: true,
      ),
      _PermItem(
        id: 'battery',
        title: 'Pil optimizasyonunu yoksay',
        subtitle: 'Arka planda host oturumunun öldürülmesini azaltır.',
        ok: _b('batteryOptimizationIgnored'),
        critical: true,
      ),
      _PermItem(
        id: 'notifications',
        title: 'Bildirimler',
        subtitle: 'Kalıcı “uzaktan host” bildirimi (ön plan servisi).',
        ok: _b('notifications'),
        critical: true,
      ),
      _PermItem(
        id: 'overlay',
        title: 'Diğer uygulamaların üzerinde göster',
        subtitle: 'İsteğe bağlı; ileride durum katmanı / yardımcı panel için.',
        ok: _b('overlay'),
        critical: false,
      ),
      _PermItem(
        id: 'notification_listener',
        title: 'Bildirim erişimi (isteğe bağlı)',
        subtitle: 'Uzaktan bildirim okuma sonraki sürümler için; şu an şart değil.',
        ok: _b('notificationListener'),
        critical: false,
      ),
    ];

    final criticalOk = items.where((i) => i.critical).every((i) => i.ok);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  criticalOk ? Icons.verified_user : Icons.security,
                  color: criticalOk ? Colors.green : Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tam erişim kurulumu',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                if (onRefresh != null)
                  IconButton(
                    tooltip: 'Yenile',
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              criticalOk
                  ? 'Kritik izinler tamam. Kumanda dokunma/kaydırma gönderebilir.'
                  : 'Uzaktan kontrol için aşağıdaki kritik izinleri aç. '
                      'Cihaz yöneticisi (silme) istenmez — sadece kendi telefonunuz için yardımcı erişim.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            for (final item in items) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: compact,
                leading: Icon(
                  item.ok ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: item.ok ? Colors.green : (item.critical ? Colors.orange : Colors.grey),
                ),
                title: Text(item.title),
                subtitle: Text(item.subtitle, style: const TextStyle(fontSize: 12)),
                trailing: item.ok
                    ? null
                    : TextButton(
                        onPressed: () => onOpen(item.id),
                        child: const Text('Aç'),
                      ),
              ),
              if (!compact) const Divider(height: 1),
            ],
            const SizedBox(height: 8),
            const Text(
              'Not: Ekran aynalama (MediaProjection) henüz yok. Güvenli kilit (PIN/desen) '
              'uzaktan açılamaz. Kök (root) gerekmez.',
              style: TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermItem {
  const _PermItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.ok,
    required this.critical,
  });
  final String id;
  final String title;
  final String subtitle;
  final bool ok;
  final bool critical;
}
