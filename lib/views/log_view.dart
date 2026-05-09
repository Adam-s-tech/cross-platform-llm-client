import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/colors.dart';
import '../services/app_log_service.dart';

class LogView extends StatelessWidget {
  const LogView({super.key});

  @override
  Widget build(BuildContext context) {
    final logs = Get.find<AppLogService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : const Color(0xFFF2F2F7),
        title: Text('Logs', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Share logs',
            icon: Icon(Icons.ios_share_rounded, size: 20, color: isDark ? const Color(0xFF0A84FF) : AppColors.primary),
            onPressed: () async {
              await logs.copyImportantLogs();
              Get.snackbar('Copied', 'Important logs copied to clipboard.', snackPosition: SnackPosition.BOTTOM);
            },
          ),
          IconButton(
            tooltip: 'Clear logs',
            icon: Icon(Icons.delete_outline_rounded, size: 20, color: Theme.of(context).hintColor),
            onPressed: logs.clear,
          ),
        ],
      ),
      body: Obx(() {
        final important = logs.importantEntries;
        if (important.isEmpty) {
          return Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.check_circle_outline_rounded, size: 28, color: AppColors.success),
              ),
              const SizedBox(height: 16),
              Text('All Clear', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black)),
              const SizedBox(height: 6),
              Text('Errors and warnings will appear here.', style: GoogleFonts.inter(fontSize: 15, color: Theme.of(context).hintColor)),
            ]),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: important.length,
          itemBuilder: (context, index) {
            final entry = important[index];
            final isError = entry.level == 'ERROR';
            final color = isError ? AppColors.error : AppColors.warning;

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 24, height: 24,
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                    child: Icon(isError ? Icons.error_outline_rounded : Icons.warning_amber_rounded, color: color, size: 14),
                  ),
                  const SizedBox(width: 8),
                  Text(entry.level, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
                  const Spacer(),
                  Text(_formatTime(entry.timestamp), style: GoogleFonts.inter(fontSize: 12, color: Theme.of(context).hintColor)),
                ]),
                const SizedBox(height: 10),
                SelectableText(entry.message, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: isDark ? Colors.white : Colors.black)),
                if (entry.details != null && entry.details!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(entry.details!, style: GoogleFonts.firaCode(fontSize: 11, color: Theme.of(context).hintColor)),
                  ),
                ],
              ]),
            );
          },
        );
      }),
    );
  }

  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
