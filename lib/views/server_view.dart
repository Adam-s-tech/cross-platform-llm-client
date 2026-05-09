import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import '../controllers/server_controller.dart';
import '../core/colors.dart';

class ServerView extends GetView<ServerController> {
  const ServerView({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? const Color(0xFF0A84FF) : AppColors.primary;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : const Color(0xFFF2F2F7),
        title: Text('Server', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
      ),
      body: Obx(() {
        final isRunning = controller.isRunning.value;
        final hasKey = controller.apiKey.value.trim().isNotEmpty;
        final publicWithoutKey = controller.useTunnel.value && !controller.useApiKey.value;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            // Status
            _groupedCard(isDark, children: [
              Padding(padding: const EdgeInsets.all(16), child: Row(children: [
                Container(width: 38, height: 38,
                  decoration: BoxDecoration(color: (isRunning ? AppColors.success : Theme.of(context).hintColor).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                  child: Icon(isRunning ? Icons.dns_rounded : Icons.dns_outlined, size: 20, color: isRunning ? AppColors.success : Theme.of(context).hintColor)),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(isRunning ? 'API Server Running' : 'API Server Stopped', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(isRunning ? controller.serverStatus.value : 'Expose your local model as an OpenAI API.', style: GoogleFonts.inter(fontSize: 13, color: Theme.of(context).hintColor)),
                ])),
                Switch(value: isRunning, onChanged: controller.isStarting.value ? null : (v) => controller.toggleServer(v)),
              ])),
            ]),
            const SizedBox(height: 12),

            // Model
            _groupedCard(isDark, children: [
              Padding(padding: const EdgeInsets.all(16), child: Row(children: [
                Container(width: 30, height: 30,
                  decoration: BoxDecoration(color: (controller.hasLiteRtModel ? AppColors.success : AppColors.warning).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(7)),
                  child: Icon(controller.hasLiteRtModel ? Icons.check_circle_outline : Icons.info_outline, size: 16, color: controller.hasLiteRtModel ? AppColors.success : AppColors.warning)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(controller.modelName, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(controller.hasLiteRtModel ? 'LiteRT-LM ready' : 'Requires a loaded .litertlm model', style: GoogleFonts.inter(fontSize: 13, color: Theme.of(context).hintColor)),
                ])),
              ])),
            ]),
            const SizedBox(height: 12),

            if (publicWithoutKey) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Public tunnel enabled without API key. Anyone with the URL can use your model.', style: GoogleFonts.inter(fontSize: 13, color: AppColors.warning))),
                ]),
              ),
              const SizedBox(height: 12),
            ],

            // Security
            _sectionLabel(context, 'SECURITY'),
            _groupedCard(isDark, children: [
              _switchTile(isDark, title: 'Require API key', subtitle: 'Authorization: Bearer <key>',
                value: controller.useApiKey.value, onChanged: (v) { controller.useApiKey.value = v; controller.saveSettings(); }),
              Divider(height: 0.5, indent: 16, color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06)),
              Padding(padding: const EdgeInsets.all(14), child: Row(children: [
                Expanded(child: TextField(
                  controller: TextEditingController(text: controller.apiKey.value)..selection = TextSelection.collapsed(offset: controller.apiKey.value.length),
                  onChanged: (v) => controller.apiKey.value = v,
                  onSubmitted: (_) => controller.saveSettings(),
                  decoration: const InputDecoration(labelText: 'API key', hintText: 'Optional'),
                )),
                const SizedBox(width: 6),
                IconButton(tooltip: 'Generate', onPressed: controller.generateApiKey, icon: Icon(Icons.auto_awesome_rounded, size: 20, color: accent)),
                IconButton(tooltip: 'Copy', onPressed: hasKey ? () => controller.copyText(controller.apiKey.value, 'API key') : null, icon: Icon(Icons.copy_outlined, size: 18, color: Theme.of(context).hintColor)),
              ])),
            ]),
            const SizedBox(height: 20),

            // Tunnel
            _sectionLabel(context, 'TUNNEL'),
            _groupedCard(isDark, children: [
              _switchTile(isDark, title: 'Public tunnel', subtitle: controller.tunnelStatus.value,
                value: controller.useTunnel.value, onChanged: (v) { controller.useTunnel.value = v; controller.saveSettings(); if (!v) controller.stopTunnel(); }),
              Divider(height: 0.5, indent: 16, color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06)),
              Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'cloudflare', label: Text('Cloudflare'), icon: Icon(Icons.cloud_outlined)),
                    ButtonSegment(value: 'ngrok', label: Text('ngrok'), icon: Icon(Icons.lan_outlined)),
                  ],
                  selected: {controller.tunnelProvider.value},
                  onSelectionChanged: (v) { controller.tunnelProvider.value = v.first; controller.saveSettings(); },
                ),
                const SizedBox(height: 14),
                if (controller.tunnelProvider.value == 'cloudflare') ...[
                  _settingField('Cloudflare tunnel token', controller.cloudflareToken.value, (v) => controller.cloudflareToken.value = v, (_) => controller.saveSettings()),
                  const SizedBox(height: 8),
                  _settingField('Stable public URL', controller.cloudflarePublicUrl.value, (v) => controller.cloudflarePublicUrl.value = v, (_) => controller.saveSettings()),
                ] else ...[
                  _settingField('ngrok auth token', controller.ngrokAuthToken.value, (v) => controller.ngrokAuthToken.value = v, (_) => controller.saveSettings()),
                  const SizedBox(height: 8),
                  _settingField('ngrok reserved domain', controller.ngrokDomain.value, (v) => controller.ngrokDomain.value = v, (_) => controller.saveSettings()),
                ],
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: FilledButton.icon(
                    onPressed: isRunning && controller.useTunnel.value ? controller.startTunnel : null,
                    icon: controller.isTunnelStarting.value
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.play_arrow_rounded),
                    label: const Text('Start tunnel'),
                  )),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: controller.publicUrl.value != null ? controller.stopTunnel : null, child: const Icon(Icons.stop_rounded)),
                ]),
              ])),
            ]),
            const SizedBox(height: 12),

            if (isRunning) ...[
              _sectionLabel(context, 'ENDPOINTS'),
              _groupedCard(isDark, children: [
                Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _urlRow(context, isDark, 'Local', controller.localUrl.value),
                  _urlRow(context, isDark, 'Public', controller.publicUrl.value),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: OutlinedButton.icon(
                      onPressed: controller.localUrl.value == null ? null : () => _testHealth(controller.localUrl.value!),
                      icon: const Icon(Icons.wifi, size: 16), label: const Text('Test local'))),
                    const SizedBox(width: 8),
                    Expanded(child: OutlinedButton.icon(
                      onPressed: controller.publicUrl.value == null ? null : () => _testHealth(controller.publicUrl.value!),
                      icon: const Icon(Icons.public, size: 16), label: const Text('Test public'))),
                  ]),
                ])),
              ]),
              const SizedBox(height: 12),

              _sectionLabel(context, 'USAGE EXAMPLES'),
              _groupedCard(isDark, children: [
                Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _codeBlock(context, isDark, 'List models', 'curl ${controller.baseUrl}/v1/models${_authHeader()}'),
                  _codeBlock(context, isDark, 'Chat completion',
                    'curl ${controller.baseUrl}/v1/chat/completions \\\n  -H "Content-Type: application/json"${_authHeader()} \\\n  -d \'{"model":"${controller.inference.loadedModelName.value}","messages":[{"role":"user","content":"Hello"}]}\''),
                  _codeBlock(context, isDark, 'Python SDK',
                    'from openai import OpenAI\n\nclient = OpenAI(\n    base_url="${controller.baseUrl}/v1",\n    api_key="${controller.useApiKey.value ? controller.apiKey.value : "not-needed"}"\n)\n\nresponse = client.chat.completions.create(\n    model="${controller.inference.loadedModelName.value}",\n    messages=[{"role": "user", "content": "Hello"}],\n)\nprint(response.choices[0].message.content)'),
                ])),
              ]),
            ],

            if (controller.lastError.value != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(controller.lastError.value!, style: GoogleFonts.inter(fontSize: 13, color: AppColors.error))),
                ]),
              ),
            ],
          ],
        );
      }),
    );
  }

  // ── Helpers ──

  Widget _groupedCard(bool isDark, {required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(color: isDark ? const Color(0xFF1C1C1E) : Colors.white, borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _sectionLabel(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 6, top: 8),
      child: Text(title, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w400, color: Theme.of(context).hintColor)),
    );
  }

  Widget _switchTile(bool isDark, {required String title, required String subtitle, required bool value, required ValueChanged<bool> onChanged}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: GoogleFonts.inter(fontSize: 15)),
          const SizedBox(height: 2),
          Text(subtitle, style: GoogleFonts.inter(fontSize: 13, color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF8E8E93)), maxLines: 2, overflow: TextOverflow.ellipsis),
        ])),
        Switch(value: value, onChanged: onChanged),
      ]),
    );
  }

  Widget _settingField(String label, String value, ValueChanged<String> onChanged, ValueChanged<String> onSubmitted) {
    return TextField(
      controller: TextEditingController(text: value)..selection = TextSelection.collapsed(offset: value.length),
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(labelText: label),
    );
  }

  Widget _urlRow(BuildContext context, bool isDark, String label, String? url) {
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
      SizedBox(width: 54, child: Text(label, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600))),
      Expanded(child: SelectableText(url ?? 'Not available', maxLines: 1, style: GoogleFonts.firaCode(fontSize: 12, color: Theme.of(context).hintColor))),
      IconButton(tooltip: 'Copy', onPressed: url == null ? null : () => controller.copyText(url, '$label URL'),
        icon: Icon(Icons.copy_outlined, size: 16, color: Theme.of(context).hintColor)),
    ]));
  }

  Widget _codeBlock(BuildContext context, bool isDark, String title, String code) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(title, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600))),
          IconButton(tooltip: 'Copy', onPressed: () => controller.copyText(code, title), icon: Icon(Icons.copy_outlined, size: 16, color: Theme.of(context).hintColor)),
        ]),
        SingleChildScrollView(scrollDirection: Axis.horizontal,
          child: Text(code, style: GoogleFonts.firaCode(fontSize: 12, color: Theme.of(context).hintColor))),
      ]),
    );
  }

  String _authHeader() {
    if (controller.useApiKey.value && controller.apiKey.value.isNotEmpty) {
      return ' \\\n  -H "Authorization: Bearer ${controller.apiKey.value}"';
    }
    return '';
  }

  Future<void> _testHealth(String baseUrl) async {
    try {
      final r = await http.get(Uri.parse('${baseUrl.replaceAll(RegExp(r'/$'), '')}/health')).timeout(const Duration(seconds: 8));
      Get.snackbar('Health check', 'Status ${r.statusCode}');
    } catch (e) {
      Get.snackbar('Health failed', '$e');
    }
  }
}
