import 'package:flutter/services.dart' show rootBundle;
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

class LegalPage extends StatefulWidget {
  const LegalPage({
    super.key,
    required this.privacy,
    required this.contact,
    this.webUrl = '',
  });

  final bool privacy;
  final String contact;
  final String webUrl;

  @override
  State<LegalPage> createState() => _LegalPageState();
}

class _LegalPageState extends State<LegalPage> {
  late final copy = rootBundle.loadString(
    widget.privacy
        ? 'assets/legal/privacy-ar.txt'
        : 'assets/legal/terms-ar.txt',
  );

  @override
  Widget build(BuildContext context) {
    final url = Uri.tryParse(widget.webUrl);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.privacy ? 'سياسة الخصوصية' : 'شروط الاستخدام'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            FutureBuilder<String>(
              future: copy,
              builder: (_, snapshot) => SelectableText(
                snapshot.data ?? (snapshot.hasError ? 'تعذر عرض النص.' : ''),
                style: const TextStyle(height: 1.65),
              ),
            ),
            const SizedBox(height: 16),
            SelectableText(widget.contact),
            if (url != null && url.isScheme('https') && url.host.isNotEmpty)
              TextButton.icon(
                icon: const Icon(Icons.open_in_new),
                label: const Text('عرض السياسة على الموقع'),
                onPressed: () async {
                  try {
                    if (await launchUrl(
                      url,
                      mode: LaunchMode.externalApplication,
                    )) {
                      return;
                    }
                  } catch (_) {
                    // The full policy remains available offline.
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تعذر فتح الموقع')),
                    );
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}
