import 'package:flutter/material.dart';

import '../../app/app_settings.dart';
import '../../core/relay/relay_config.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.settings, this.onChanged});
  final AppSettings settings;
  final VoidCallback? onChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _name;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.settings.deviceName);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text('Cihaz', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: 'Görünen ad',
                      hintText: 'AktifDesk Telefon',
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (v) async {
                      await s.setDeviceName(v);
                      widget.onChanged?.call();
                    },
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () async {
                      await s.setDeviceName(_name.text);
                      widget.onChanged?.call();
                      if (!mounted) return;
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        const SnackBar(content: Text('Kaydedildi')),
                      );
                    },
                    child: const Text('Kaydet'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Bağlantı', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Uzak bağlantı'),
                  subtitle: Text(
                    RelayConfig.isIntegrityOk
                        ? 'Farklı ağlarda kod ile eşleş. LAN her zaman öncelikli.'
                        : 'Relay bütünlük kontrolü başarısız — uzak mod kapalı.',
                  ),
                  value: s.uzakBaglanti && RelayConfig.isIntegrityOk,
                  onChanged: !RelayConfig.isIntegrityOk
                      ? null
                      : (v) async {
                          await s.setUzakBaglanti(v);
                          widget.onChanged?.call();
                          setState(() {});
                        },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(
                    RelayConfig.isIntegrityOk ? Icons.verified : Icons.gpp_bad,
                    color: RelayConfig.isIntegrityOk ? Colors.green : Colors.red,
                  ),
                  title: const Text('Relay (gömülü)'),
                  subtitle: Text(
                    RelayConfig.isIntegrityOk
                        ? 'Sabit wss uç noktası · bütünlük OK\nAyarlardan değiştirilemez'
                        : (RelayConfig.integrityError() ?? 'Hata'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Güvenlik', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '• Eşleşme anahtarları güvenli depoda.\n'
                '• Relay adresi derleme sabiti + hash; runtime ile değiştirilemez.\n'
                '• R8 obfuscation tersine mühendisliği yavaşlatır, garanti değildir.\n'
                '• Railway jetonları APK’da yoktur.',
                style: TextStyle(height: 1.45, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
