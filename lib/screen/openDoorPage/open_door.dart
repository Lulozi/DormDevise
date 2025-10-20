import 'package:flutter/material.dart';
import 'package:dormdevise/screen/openDoorPage/mqtt_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dormdevise/screen/openDoorPage/config_all.dart';
import 'dart:io';
import 'dart:async';

class OpenDoorPage extends StatefulWidget {
  const OpenDoorPage({super.key});

  @override
  State<OpenDoorPage> createState() => _OpenDoorPageState();
}

class _OpenDoorPageState extends State<OpenDoorPage> {
  Timer? _longPressTimer;
  double _longPressProgress = 0.0;
  bool isOpen = false;
  DateTime? lastTapTime;
  MqttService? _mqttService;

  void _handleLongPressStart(LongPressStartDetails details) {
    _longPressTimer?.cancel();
    _longPressProgress = 0.0;
    final int totalMs = 2000;
    int elapsed = 0;
    const tick = 50;
    _longPressTimer = Timer.periodic(const Duration(milliseconds: tick), (
      timer,
    ) {
      elapsed += tick;
      setState(() {
        _longPressProgress = (elapsed / totalMs).clamp(0.0, 1.0);
      });
      if (elapsed >= totalMs) {
        timer.cancel();
        _longPressProgress = 0.0;
        if (mounted) {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const ConfigPage()));
        }
      }
    });
  }

  void _handleLongPressEnd(LongPressEndDetails details) {
    _longPressTimer?.cancel();
    setState(() {
      _longPressProgress = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Card(
                elevation: 0,
                color: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(32),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 36,
                  ),
                  child: SizedBox(
                    width: 260,
                    height: 320,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _CoolDoorButton(
                              isOpen: isOpen,
                              onTap: () async {
                                final now = DateTime.now();
                                if (lastTapTime != null &&
                                    now.difference(lastTapTime!) <
                                        const Duration(seconds: 4)) {
                                  return;
                                }
                                lastTapTime = now;
                                if (!isOpen) {
                                  final messenger = ScaffoldMessenger.maybeOf(
                                    context,
                                  );
                                  final prefs =
                                      await SharedPreferences.getInstance();
                                  final topic =
                                      prefs.getString('mqtt_topic') ??
                                      'test/topic';
                                  final host =
                                      prefs.getString('mqtt_host') ?? '';
                                  final port =
                                      int.tryParse(
                                        prefs.getString('mqtt_port') ?? '1883',
                                      ) ??
                                      1883;
                                  final clientId =
                                      prefs.getString('mqtt_clientId') ??
                                      'flutter_client';
                                  final username = prefs.getString(
                                    'mqtt_username',
                                  );
                                  final password = prefs.getString(
                                    'mqtt_password',
                                  );
                                  final withTls =
                                      prefs.getBool('mqtt_with_tls') ?? false;
                                  final caPath =
                                      prefs.getString('mqtt_ca') ??
                                      'assets/certs/ca.pem';
                                  final certPath = prefs.getString('mqtt_cert');
                                  final keyPath = prefs.getString('mqtt_key');
                                  final keyPwd = prefs.getString(
                                    'mqtt_key_pwd',
                                  );
                                  final msg =
                                      prefs.getString('custom_open_msg') ??
                                      'OPEN';
                                  SecurityContext? sc;
                                  if (withTls) {
                                    sc = await buildSecurityContext(
                                      caAsset: caPath,
                                      clientCertAsset:
                                          (certPath != null &&
                                              certPath.isNotEmpty)
                                          ? certPath
                                          : null,
                                      clientKeyAsset:
                                          (keyPath != null &&
                                              keyPath.isNotEmpty)
                                          ? keyPath
                                          : null,
                                      clientKeyPassword:
                                          (keyPwd != null && keyPwd.isNotEmpty)
                                          ? keyPwd
                                          : null,
                                    );
                                  }
                                  _mqttService ??= MqttService(
                                    host: host,
                                    port: port,
                                    clientId: clientId,
                                    username:
                                        (username != null &&
                                            username.isNotEmpty)
                                        ? username
                                        : null,
                                    password:
                                        (password != null &&
                                            password.isNotEmpty)
                                        ? password
                                        : null,
                                    securityContext: sc,
                                  );
                                  try {
                                    await _mqttService!.connect();
                                    await _mqttService!.subscribe(topic);
                                    await _mqttService!.publishText(topic, msg);
                                    if (!mounted) return;
                                    setState(() {
                                      isOpen = true;
                                    });
                                    Future.delayed(
                                      const Duration(seconds: 2),
                                      () {
                                        if (mounted) {
                                          setState(() {
                                            isOpen = false;
                                          });
                                        }
                                      },
                                    );
                                  } catch (e) {
                                    if (!mounted) return;
                                    if (messenger != null) {
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '开门失败: $e',
                                            style: TextStyle(
                                              color: colorScheme
                                                  .onSecondaryContainer,
                                            ),
                                          ),
                                          backgroundColor:
                                              colorScheme.secondaryContainer,
                                          behavior: SnackBarBehavior.floating,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                          duration: const Duration(
                                            milliseconds: 1500,
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                }
                              },
                              onLongPressStart: _handleLongPressStart,
                              onLongPressEnd: _handleLongPressEnd,
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                        if (_longPressProgress > 0)
                          Positioned(
                            bottom: 32,
                            left: 0,
                            right: 0,
                            child: Column(
                              children: [
                                LinearProgressIndicator(
                                  value: _longPressProgress,
                                  minHeight: 6,
                                  backgroundColor:
                                      colorScheme.surfaceContainerHighest,
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '长按2秒进入配置设置',
                                  style: TextStyle(
                                    color: colorScheme.outline,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================== 门禁按钮组件 ==================

typedef DoorLongPressCallback = void Function(LongPressStartDetails details);
typedef DoorLongPressEndCallback = void Function(LongPressEndDetails details);

class _CoolDoorButton extends StatefulWidget {
  final bool isOpen;
  final VoidCallback onTap;
  final DoorLongPressCallback? onLongPressStart;
  final DoorLongPressEndCallback? onLongPressEnd;
  const _CoolDoorButton({
    required this.isOpen,
    required this.onTap,
    this.onLongPressStart,
    this.onLongPressEnd,
  });

  @override
  State<_CoolDoorButton> createState() => _CoolDoorButtonState();
}

class _CoolDoorButtonState extends State<_CoolDoorButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  late Animation<double> _glowAnim;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _scaleAnim = Tween<double>(
      begin: 1.0,
      end: 1.15,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _glowAnim = Tween<double>(
      begin: 0.0,
      end: 30.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(covariant _CoolDoorButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOpen && !oldWidget.isOpen) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: _handleTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onLongPressStart: widget.onLongPressStart,
      onLongPressEnd: widget.onLongPressEnd,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final scale = _pressed ? 0.93 : _scaleAnim.value;
          final glow = _glowAnim.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              // 外圈发光
              Container(
                width: widget.isOpen ? 240 : 140,
                height: widget.isOpen ? 240 : 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: widget.isOpen
                          ? colorScheme.primary.withAlpha((0.45 * 255).toInt())
                          : colorScheme.secondary.withAlpha(
                              (0.25 * 255).toInt(),
                            ),
                      blurRadius: glow + 30,
                      spreadRadius: glow / 2,
                    ),
                  ],
                ),
              ),
              // 动态渐变按钮
              Transform.scale(
                scale: scale,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  width: widget.isOpen ? 200 : 120,
                  height: widget.isOpen ? 200 : 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(
                      colors: widget.isOpen
                          ? [
                              colorScheme.primary,
                              colorScheme.primaryContainer,
                              colorScheme.tertiary,
                              colorScheme.primary,
                            ]
                          : [
                              colorScheme.secondary,
                              colorScheme.secondaryContainer,
                              colorScheme.tertiaryContainer,
                              colorScheme.secondary,
                            ],
                      stops: const [0.0, 0.5, 0.8, 1.0],
                      startAngle: 0,
                      endAngle: 6.28,
                      transform: GradientRotation(_controller.value * 6.28),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: widget.isOpen
                            ? colorScheme.primary.withAlpha(
                                (0.25 * 255).toInt(),
                              )
                            : colorScheme.secondary.withAlpha(
                                (0.13 * 255).toInt(),
                              ),
                        blurRadius: 30,
                        spreadRadius: 2,
                      ),
                    ],
                    border: Border.all(
                      color: widget.isOpen
                          ? colorScheme.onPrimary
                          : colorScheme.outlineVariant,
                      width: 4,
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 400),
                          transitionBuilder: (child, animation) =>
                              FadeTransition(opacity: animation, child: child),
                          child: Icon(
                            widget.isOpen
                                ? Icons.lock_open_rounded
                                : Icons.lock_outline_rounded,
                            key: ValueKey<bool>(widget.isOpen),
                            color: colorScheme.onPrimary,
                            size: 60,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
              // 波纹动画
              if (_pressed)
                Container(
                  width: widget.isOpen ? 220 : 120,
                  height: widget.isOpen ? 220 : 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.onPrimary.withAlpha(
                      (0.13 * 255).toInt(),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
