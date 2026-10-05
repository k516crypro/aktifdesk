import 'package:flutter/material.dart';

import '../../app/app_settings.dart';

class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key, required this.settings, required this.onDone});
  final AppSettings settings;
  final VoidCallback onDone;

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  final _page = PageController();
  int _i = 0;

  static const _pages = <(IconData, String, String)>[
    (
      Icons.devices_rounded,
      'AktifDesk nedir?',
      'Telefonunu PC uzaktan kumandası yap veya bir telefonu diğerinden yönet. Aynı Wi‑Fi’da hızlı LAN; Uzak bağlantı ile farklı ağlar.',
    ),
    (
      Icons.pin_rounded,
      'Kod ile eşleş',
      'Host telefonda 6 haneli kod görünür. Diğer cihazda kodu gir — IP yok. Kodlar tek kullanımlık; anahtarlar güvenli saklanır.',
    ),
    (
      Icons.accessibility_new_rounded,
      'Tam erişim',
      'Uzaktan dokunma için Erişilebilirlik’i aç. Pil ve bildirim izinleri oturumu canlı tutar. Cihaz yöneticisi / silme yok.',
    ),
  ];

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await widget.settings.setTutorialDone(true);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: _finish, child: const Text('Atla')),
            ),
            Expanded(
              child: PageView.builder(
                controller: _page,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _i = i),
                itemBuilder: (_, i) {
                  final p = _pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      children: [
                        const Spacer(),
                        Icon(p.$1, size: 88, color: t.colorScheme.primary),
                        const SizedBox(height: 28),
                        Text(
                          p.$2,
                          textAlign: TextAlign.center,
                          style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          p.$3,
                          textAlign: TextAlign.center,
                          style: t.textTheme.bodyLarge?.copyWith(
                            color: t.colorScheme.onSurfaceVariant,
                            height: 1.45,
                          ),
                        ),
                        const Spacer(flex: 2),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _i == i ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _i == i ? t.colorScheme.primary : t.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    if (_i < _pages.length - 1) {
                      _page.nextPage(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                      );
                    } else {
                      _finish();
                    }
                  },
                  child: Text(_i < _pages.length - 1 ? 'Devam' : 'Başla'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
