import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/settings_controller.dart';
import '../core/constants.dart';
import '../core/ui.dart';
import '../widgets/home_empty_state.dart' show providerLabel;
import '../services/inference_service.dart';
import '../services/hive_service.dart';
import '../services/local_image_service.dart';
import '../services/device_info_service.dart';
import '../services/device_info_native.dart' as platform_info;
import '../ffi/sd_ffi_bindings.dart';
import 'log_view.dart';
import '../core/haptics.dart';

const _tabular = [FontFeature.tabularFigures()];

class SettingsView extends GetView<SettingsController> {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Scaffold(
      backgroundColor: t.bg,
      appBar: appScreenBar(context, title: 'Settings'),
      body: Obx(() => ListView(
            padding: kPagePadding,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              CollapsibleCard(
                icon: Icons.palette_outlined,
                title: 'Appearance',
                summary: _appearanceSummary(),
                child: AppGroup(flat: true, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Theme', style: t.body),
                          const SizedBox(height: 10),
                          AppSegmented<ThemeMode>(
                            items: const [
                              (ThemeMode.light, 'Light'),
                              (ThemeMode.dark, 'Dark'),
                              (ThemeMode.system, 'System'),
                            ],
                            selected: controller.themeMode.value,
                            onChanged: (mode) {
                              if (mode != controller.themeMode.value) {
                                controller.setThemeMode(mode);
                              }
                            },
                          ),
                        ]),
                  ),
                  Obx(() => _buildFontSizeRow(context)),
                  AppRow(
                    icon: Icons.vibration_rounded,
                    title: 'Haptic feedback',
                    subtitle: 'Light vibration on taps and selections',
                    trailing: Switch(
                      value: controller.hapticsEnabled.value,
                      onChanged: controller.setHapticsEnabled,
                    ),
                    onTap: () => controller
                        .setHapticsEnabled(!controller.hapticsEnabled.value),
                  ),
                ]),
              ),
              _gap,
              CollapsibleCard(
                icon: Icons.memory_rounded,
                title: 'Inference mode',
                summary: controller.inferenceMode.value == 'local'
                    ? 'Local · ${_localSubtitle()}'
                    : 'Cloud · ${providerLabel(controller)}',
                child: AppGroup(flat: true, dividerIndent: 60, children: [
                  AppRow(
                    icon: Icons.phone_iphone_rounded,
                    title: 'Local (on-device)',
                    subtitle: _localSubtitle(),
                    selected: controller.inferenceMode.value == 'local',
                    onTap: () => controller.setInferenceMode('local'),
                  ),
                  AppRow(
                    icon: Icons.cloud_outlined,
                    title: 'Cloud API',
                    subtitle: providerLabel(controller),
                    selected: controller.inferenceMode.value == 'cloud',
                    onTap: () => controller.setInferenceMode('cloud'),
                  ),
                ]),
              ),
              _gap,
              CollapsibleCard(
                icon: Icons.chat_bubble_outline_rounded,
                title: 'System prompt',
                summary: _firstLine(controller.globalSystemPrompt.value,
                    fallback: 'Default'),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(children: [
                    TextField(
                      controller: controller.globalSystemPromptController,
                      minLines: 3,
                      maxLines: 6,
                      style: t.body,
                      decoration: appInputDecoration(context,
                          hint: AppConstants.systemPrompt),
                      onSubmitted: (v) => controller.setGlobalSystemPrompt(v),
                    ),
                    _fieldFooter(
                      context,
                      note: 'Applies to local and cloud models.',
                      onSave: () async {
                        await controller.setGlobalSystemPrompt(
                            controller.globalSystemPromptController.text);
                        if (context.mounted) {
                          _confirmSaved(context, 'System prompt saved');
                        }
                      },
                    ),
                  ]),
                ),
              ),
              _gap,
              CollapsibleCard(
                icon: Icons.block_rounded,
                title: 'Stop sequences',
                summary: controller.stopSequences.isEmpty
                    ? 'None'
                    : '${controller.stopSequences.length} '
                        '${controller.stopSequences.length == 1 ? 'sequence' : 'sequences'}',
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(children: [
                    TextField(
                      controller: controller.stopSequencesController,
                      minLines: 2,
                      maxLines: 5,
                      style: t.mono.copyWith(fontSize: 13.5),
                      decoration:
                          appInputDecoration(context, hint: '###\n\\nUser:'),
                    ),
                    _fieldFooter(
                      context,
                      note: 'Local models stop when they write one of these. '
                          'One per line; use \\n for a newline.',
                      onSave: () async {
                        await controller.setStopSequences(
                            controller.stopSequencesController.text);
                        if (context.mounted) {
                          _confirmSaved(context, 'Stop sequences saved');
                        }
                      },
                    ),
                  ]),
                ),
              ),
              _gap,
              CollapsibleCard(
                icon: Icons.tune_rounded,
                title: 'Model parameters',
                summary:
                    'Temperature ${controller.temperature.value.toStringAsFixed(2)}'
                    ' · ${controller.maxTokens.value} tokens'
                    ' · ${controller.contextSize.value} context',
                child: _flatten(_buildModelParametersGroup(context)),
              ),
              _gap,
              CollapsibleCard(
                icon: Icons.speed_rounded,
                title: 'Performance',
                summary: switch (controller.liteRtPerformanceMode.value) {
                  'gpu_fast' => 'GPU fast · GGUF & LiteRT',
                  'cpu_safe' => 'CPU safe · GGUF & LiteRT',
                  _ => 'Auto fast · GGUF & LiteRT',
                },
                child: _flatten(_buildLiteRtGroup(context)),
              ),
              _gap,
              CollapsibleCard(
                icon: Icons.image_outlined,
                title: 'Image generation',
                summary: '${controller.imageSteps.value} steps'
                    ' · ${controller.imageGenSize.value == 0 ? 'Auto size' : '${controller.imageGenSize.value}px'}'
                    ' · ${controller.imageGenBackend.value == Backend.cpu ? 'CPU' : 'GPU'}',
                child: _flatten(_buildImageGenerationGroup(context)),
              ),
              _gap,
              Obx(() {
                final device = Get.find<DeviceInfoService>();
                return CollapsibleCard(
                  icon: Icons.smartphone_rounded,
                  title: 'Device',
                  summary:
                      '${device.totalRamGB.value.toStringAsFixed(1)} GB RAM'
                      ' · ${device.availableRamGB.value.toStringAsFixed(1)} GB free',
                  child: _buildDeviceCard(context),
                );
              }),
              const SizedBox(height: 24),
              AppGroup(dividerIndent: 60, children: [
                AppRow(
                  icon: Icons.article_outlined,
                  title: 'Logs',
                  subtitle: 'Errors, warnings and debug details',
                  chevron: true,
                  onTap: () => Get.to(() => const LogView()),
                ),
                AppRow(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset('assets/icons/appicon.png',
                        width: 32, height: 32),
                  ),
                  title: 'PrivateLM',
                  subtitle: controller.appVersion.value.isEmpty
                      ? 'Version unavailable · by orailnoor & techjarves'
                      : 'Version ${controller.appVersion.value} · by orailnoor & techjarves',
                ),
              ]),
              const SizedBox(height: 16),
            ],
          )),
    );
  }

  static const _gap = SizedBox(height: 10);

  /// Section bodies are built as standalone groups; inside a collapsible
  /// card they drop their own surface so there's no double border.
  Widget _flatten(Widget w) => w is AppGroup
      ? AppGroup(
          flat: true, dividerIndent: w.dividerIndent, children: w.children)
      : w;

  String _appearanceSummary() {
    final theme = switch (controller.themeMode.value) {
      ThemeMode.light => 'Light',
      ThemeMode.dark => 'Dark',
      ThemeMode.system => 'System',
    };
    return '$theme theme · ${(controller.fontScale.value * 100).round()}% text'
        '${controller.hapticsEnabled.value ? '' : ' · Haptics off'}';
  }

  String _firstLine(String s, {required String fallback}) {
    final line = s.trim().split('\n').first.trim();
    return line.isEmpty ? fallback : line;
  }

  // ── Building blocks ─────────────────────────────────────────────────────

  /// Note on the left, explicit Save on the right, under a text field.
  Widget _fieldFooter(BuildContext context,
      {required String note, required VoidCallback onSave}) {
    final t = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 0, 0),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(note, style: t.small),
          ),
        ),
        const SizedBox(width: 12),
        PillButton(label: 'Save', primary: true, onPressed: onSave),
      ]),
    );
  }

  void _confirmSaved(BuildContext context, String message) {
    FocusScope.of(context).unfocus();
    showToast('Saved', message, tone: ToastTone.success);
  }

  /// Consistent slider row: label left, value right, slider below, then an
  /// optional caption and trailing widget (e.g. a warning notice).
  Widget _sliderRow(
    BuildContext context, {
    required String label,
    required String valueLabel,
    required double value,
    required double min,
    required double max,
    int? divisions,
    required ValueChanged<double> onChanged,
    Color? color,
    String? caption,
    List<Widget> below = const [],
  }) {
    final t = AppTokens.of(context);
    final c = color ?? t.accent;
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(child: Text(label, style: t.body)),
            const SizedBox(width: 12),
            Text(valueLabel,
                style: t.body.copyWith(
                    color: color ?? t.muted,
                    fontWeight: color != null ? FontWeight.w600 : null,
                    fontFeatures: _tabular)),
          ]),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            activeTrackColor: c,
            inactiveTrackColor: t.fill,
            thumbColor: Colors.white,
            overlayColor: c.withValues(alpha: 0.12),
            trackShape: const RoundedRectSliderTrackShape(),
            thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: 10, elevation: 2),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            tickMarkShape: SliderTickMarkShape.noTickMark,
            showValueIndicator: ShowValueIndicator.never,
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
        if (caption != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(caption, style: t.small),
          ),
        for (final w in below)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: w,
          ),
      ]),
    );
  }

  // ── Sections ────────────────────────────────────────────────────────────

  String _localSubtitle() {
    final inf = Get.find<InferenceService>();
    final localImage = Get.find<LocalImageService>();
    if (inf.isModelLoaded.value) {
      return 'Active: ${inf.loadedModelName.value}';
    } else if (localImage.isModelLoaded.value) {
      return 'Active: ${localImage.loadedModelName.value}';
    }
    return 'No model loaded';
  }

  Widget _buildFontSizeRow(BuildContext context) {
    final t = AppTokens.of(context);
    const min = 0.8;
    const max = 1.4;
    final v = controller.fontScale.value;

    String scaleLabel(double v) {
      if (v <= 0.85) return 'XS';
      if (v <= 0.95) return 'Small';
      if (v <= 1.05) return 'Recommended';
      if (v <= 1.15) return 'Large';
      if (v <= 1.25) return 'XL';
      return 'XXL';
    }

    final isDefault = v >= 0.9 && v <= 0.95;
    Widget marker(String s, {bool on = false}) => Text(s,
        style: t.small.copyWith(
            fontSize: 11,
            color: on ? t.text : t.faint,
            fontWeight: on ? FontWeight.w600 : FontWeight.w400));

    return _sliderRow(
      context,
      label: 'Text size',
      valueLabel: scaleLabel(v),
      value: v,
      min: min,
      max: max,
      divisions: 12,
      onChanged: (v) => controller.setFontScale(v),
      below: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          marker('XS'),
          marker('Small (default)', on: isDefault),
          marker('Large'),
        ]),
      ],
    );
  }

  Widget _buildDeviceCard(BuildContext context) {
    return Obx(() {
      final t = AppTokens.of(context);
      final device = Get.find<DeviceInfoService>();
      final ram = device.totalRamGB.value.toStringAsFixed(1);
      final (String tierName, String tierHint) =
          switch (device.deviceTier.value) {
        'low' => ('Low RAM', 'Use small models only'),
        'mid' => ('Mid-range', 'Good for 1–3B models'),
        'high' => ('High-end', 'Can run 3–7B models'),
        'ultra' => ('Ultra', 'Full performance mode'),
        _ => ('', ''),
      };
      final isLow = device.deviceTier.value == 'low';

      final soc = device.socFamily.value;
      final quantWarning = soc.quantWarning;

      Widget kv(String k, String v, {Color? color}) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              Text(k, style: t.caption.copyWith(fontSize: 14)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(v,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: t.body.copyWith(
                        fontSize: 14,
                        color: color ?? t.text,
                        fontFeatures: _tabular)),
              ),
            ]),
          );

      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const IconBadge(Icons.smartphone_rounded),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$ram GB RAM',
                        style: t.bodyStrong.copyWith(fontFeatures: _tabular)),
                    if (tierHint.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(tierHint, style: t.caption),
                    ],
                  ]),
            ),
            if (tierName.isNotEmpty) ...[
              const SizedBox(width: 10),
              AppTag(tierName, color: isLow ? t.orange : null),
            ],
          ]),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(height: 0.5, color: t.hairline),
          ),
          kv('Available memory',
              '${device.availableRamGB.value.toStringAsFixed(1)} GB'),
          kv('Recommended context', '${device.recommendedContextSize}'),
          kv('Recommended max tokens', '${device.recommendedMaxTokens}'),
          if (soc != platform_info.SocFamily.unknown) ...[
            kv('Chipset', soc.displayName),
            kv('Recommended quant', soc.recommendedQuant,
                color: quantWarning != null ? t.orange : null),
          ],
          if (quantWarning != null) ...[
            const SizedBox(height: 10),
            AppNotice(quantWarning,
                icon: Icons.warning_amber_rounded, color: t.orange),
          ],
        ]),
      );
    });
  }

  Widget _buildLiteRtGroup(BuildContext context) {
    final modes = [
      (
        value: 'auto_fast',
        title: 'Auto fast',
        subtitle:
            "Uses the GPU when supported, CPU if the GPU can't load the model",
        icon: Icons.auto_awesome_outlined
      ),
      (
        value: 'gpu_fast',
        title: 'GPU fast',
        subtitle: 'Always tries the GPU. Fastest, may crash on some devices',
        icon: Icons.bolt_rounded
      ),
      (
        value: 'cpu_safe',
        title: 'CPU safe',
        subtitle: 'CPU only. Most stable, slower',
        icon: Icons.shield_outlined
      ),
    ];
    final t = AppTokens.of(context);
    return AppGroup(dividerIndent: 60, children: [
      for (final m in modes)
        AppRow(
          icon: m.icon,
          title: m.title,
          subtitle: m.subtitle,
          selected: controller.liteRtPerformanceMode.value == m.value,
          onTap: () => controller.setLiteRtPerformanceMode(m.value),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Text(
            'Applies to both GGUF and LiteRT models. Takes effect the next '
            'time a model is loaded.',
            style: t.small),
      ),
    ]);
  }

  Widget _buildModelParametersGroup(BuildContext context) {
    return AppGroup(children: [
      _modelParameterSlider(
        context,
        label: 'Temperature',
        value: controller.temperature.value,
        min: 0.0,
        max: 2.0,
        divisions: 20,
        safeMax: 1.0,
        onChanged: (v) => controller.setTemperature(v),
        warning: 'High temperature = unpredictable output!',
      ),
      _modelParameterSlider(
        context,
        label: 'Max tokens',
        value: controller.maxTokens.value.toDouble(),
        min: 64,
        max: 4096,
        divisions: 63,
        safeMax: Get.find<DeviceInfoService>().maxSafeTokens.toDouble(),
        onChanged: (v) => controller.setMaxTokens(v.toInt()),
        displayValue: controller.maxTokens.value.toString(),
        warning: 'Your phone may crash with this value!',
      ),
      (() {
        final inference = Get.find<InferenceService>();
        final savedRuntime = Get.find<HiveService>()
                .getSetting<String>(AppConstants.keyLocalModelRuntime) ??
            '';
        final isLiteRtActive = (inference.isModelLoaded.value &&
                inference.loadedModelRuntime.value == 'litert') ||
            (!inference.isModelLoaded.value &&
                savedRuntime.toLowerCase() == 'litert');
        final maxContext = isLiteRtActive ? 4096.0 : 8192.0;
        final divisions = isLiteRtActive ? 7 : 15;
        final currentValue =
            controller.contextSize.value.toDouble().clamp(512.0, maxContext);

        if (currentValue != controller.contextSize.value.toDouble()) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            controller.setContextSize(currentValue.toInt());
          });
        }

        return _modelParameterSlider(
          context,
          label: 'Context size',
          value: currentValue,
          min: 512,
          max: maxContext,
          divisions: divisions,
          safeMax: Get.find<DeviceInfoService>().maxSafeContextSize.toDouble(),
          onChanged: (v) => controller.setContextSize(v.toInt()),
          displayValue: currentValue.toInt().toString(),
          warning: isLiteRtActive
              ? 'Context capped at 4096 to prevent driver memory crash for LiteRT models.'
              : 'Context this large will eat all your RAM!',
        );
      })(),
    ]);
  }

  Widget _modelParameterSlider(
    BuildContext context, {
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required double safeMax,
    required ValueChanged<double> onChanged,
    required String warning,
    String? displayValue,
  }) {
    final t = AppTokens.of(context);
    final isOver = value > safeMax;
    final danger = safeMax < max
        ? ((value - safeMax) / (max - safeMax)).clamp(0.0, 1.0)
        : 0.0;
    final warnColor = isOver ? Color.lerp(t.orange, t.red, danger)! : null;

    return _sliderRow(
      context,
      label: label,
      valueLabel: displayValue ?? value.toStringAsFixed(2),
      value: value,
      min: min,
      max: max,
      divisions: divisions,
      color: warnColor,
      caption: safeMax < max
          ? 'Recommended max: ${safeMax.toInt() > 0 ? safeMax.toInt().toString() : safeMax.toStringAsFixed(1)}'
          : null,
      onChanged: (v) {
        if (v > safeMax && value <= safeMax) {
          Haptics.heavyImpact();
          showToast('Above recommended', warning, tone: ToastTone.warning);
        } else if (v > safeMax) {
          Haptics.mediumImpact();
        }
        onChanged(v);
      },
      below: [
        if (isOver)
          AppNotice(warning,
              icon: Icons.warning_amber_rounded, color: warnColor),
      ],
    );
  }

  Widget _buildImageGenerationGroup(BuildContext context) {
    final t = AppTokens.of(context);
    final stepsValue = controller.imageSteps.value.toDouble();
    const safeMax = 8.0;
    final isOver = stepsValue > safeMax;
    final selectedBackend = controller.imageGenBackend.value;
    final gpuBackend = controller.recommendedImageGpuBackend();
    final gpuAvailable = gpuBackend != Backend.cpu;
    final size = controller.imageGenSize.value;
    final guard = controller.imageGenGpuGuardMb.value;

    return AppGroup(children: [
      // Steps
      _sliderRow(
        context,
        label: 'Steps',
        valueLabel: controller.imageSteps.value.toString(),
        value: stepsValue.clamp(1, 50),
        min: 1,
        max: 50,
        divisions: 49,
        color: isOver ? t.orange : null,
        caption: 'Recommended: 15-20 steps',
        onChanged: (v) => controller.setImageSteps(v.toInt()),
        below: [
          if (isOver)
            AppNotice('More steps = better quality but MUCH slower!',
                icon: Icons.warning_amber_rounded, color: t.orange),
        ],
      ),

      // Size
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Image size', style: t.body)),
            Text(size == 0 ? 'Auto' : '${size}px',
                style: t.body.copyWith(color: t.muted, fontFeatures: _tabular)),
          ]),
          const SizedBox(height: 12),
          AppChips<int>(
            items: const [
              (0, 'Auto'),
              (256, '256'),
              (320, '320'),
              (384, '384'),
              (512, '512'),
            ],
            selected: size,
            onSelected: (v) => controller.setImageGenSize(v),
          ),
          const SizedBox(height: 10),
          Text(
              'Auto recommended. Bigger size = better detail, but much slower and more memory use.',
              style: t.small),
          if (size >= 512) ...[
            const SizedBox(height: 10),
            AppNotice(
                '512 gives more detail but can be MUCH slower, heat the phone, and may fail on some devices.',
                icon: Icons.warning_amber_rounded,
                color: t.orange),
          ],
        ]),
      ),

      // GPU safety
      _sliderRow(
        context,
        label: 'GPU safety',
        valueLabel: guard <= 0 ? 'Off' : '$guard MB',
        value: guard.toDouble().clamp(0, 4096),
        min: 0,
        max: 4096,
        divisions: 16,
        caption:
            'Models at or above this size use CPU. Smaller models can use GPU Experimental.',
        onChanged: (v) => controller.setImageGenGpuGuardMb(v.toInt()),
        below: [
          if (guard <= 0 || guard >= 2048)
            AppNotice(
                guard <= 0
                    ? 'GPU Safety is off. Large models may crash or freeze on GPU.'
                    : 'High GPU Safety allows larger models on GPU and may crash, freeze, or overheat some phones.',
                icon: Icons.warning_amber_rounded,
                color: t.orange),
        ],
      ),

      // Backend
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Backend', style: t.body),
          const SizedBox(height: 2),
          Text(controller.imageGpuLabel(), style: t.caption),
          const SizedBox(height: 12),
          AppSegmented<bool>(
            items: const [(false, 'CPU'), (true, 'GPU')],
            selected: selectedBackend != Backend.cpu,
            onChanged: (useGpu) {
              if (useGpu == (selectedBackend != Backend.cpu)) return;
              if (useGpu && !gpuAvailable) return;
              controller.setImageBackendMode(useGpu);
            },
          ),
          if (selectedBackend != Backend.cpu) ...[
            const SizedBox(height: 10),
            Text('GPU is experimental and only used below GPU Safety size.',
                style: t.small.copyWith(color: t.orange)),
          ],
        ]),
      ),
    ]);
  }
}
