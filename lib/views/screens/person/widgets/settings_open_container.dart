import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 通用的平滑展开动画容器，用于承载各类设置入口。
class SettingsOpenContainer extends StatefulWidget {
  final IconData icon;
  final String title;
  final WidgetBuilder pageBuilder;
  final Color? iconColor;

  /// 控制是否启用容器展开动画，便于在页面切换时直接跳转。
  final bool enableTransition;

  /// 当展开页执行收缩动画时通知外部，便于屏蔽页面切换。
  final ValueChanged<bool>? onInteractionLockChanged;

  const SettingsOpenContainer({
    super.key,
    required this.icon,
    required this.title,
    required this.pageBuilder,
    this.iconColor,
    this.enableTransition = true,
    this.onInteractionLockChanged,
  });

  /// 创建对应的状态对象，负责协调开合逻辑。
  @override
  State<SettingsOpenContainer> createState() => _SettingsOpenContainerState();
}

class _SettingsOpenContainerState extends State<SettingsOpenContainer> {
  static const Duration _openDuration = Duration(milliseconds: 400);
  static const Duration _closeDuration = Duration(milliseconds: 250);

  bool _isClosing = false;
  bool _isDirectRouteActive = false;
  bool _isOpen = false;
  Timer? _lockReleaseTimer;
  final GlobalKey<_HideableState> _hideableKey = GlobalKey<_HideableState>();
  _SettingsOpenContainerRoute<void>? _activeRoute;

  /// 处理卡片点击，根据当前状态决定使用容器动画还是直接跳转。
  void _handleTap(BuildContext context) {
    if (_isDirectRouteActive) {
      return;
    }
    if (_isClosing || !widget.enableTransition) {
      _openPageDirectly(context);
      return;
    }
    unawaited(_openWithAnimation());
  }

  /// 通过容器动画展开页面，并在必要时记录状态以便外部取消。
  Future<void> _openWithAnimation() async {
    if (_isOpen) {
      return;
    }
    setState(() {
      _isOpen = true;
    });
    final colorScheme = Theme.of(context).colorScheme;
    final route = _SettingsOpenContainerRoute<void>(
      closedColor: colorScheme.surfaceContainerHighest,
      openColor: colorScheme.surface,
      middleColor: Theme.of(context).canvasColor,
      closedElevation: 0,
      openElevation: 0,
      closedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      openShape: const RoundedRectangleBorder(),
      openBuilder: widget.pageBuilder,
      closedBuilder: (context) => _buildClosedTile(
        Theme.of(context).colorScheme,
        context,
        interactive: false,
      ),
      hideableKey: _hideableKey,
      openDuration: _openDuration,
      closeDuration: _closeDuration,
      onStartClosing: _markClosing,
    );
    _activeRoute = route;
    await Navigator.of(context).push<void>(route);
    if (!mounted) {
      return;
    }
    setState(() {
      _isOpen = false;
    });
    _activeRoute = null;
    _resetClosing();
  }

  /// 在正在执行收缩动画时直接压栈目标页面，避免动画残影。
  Future<void> _openPageDirectly(BuildContext context) async {
    if (_isDirectRouteActive) {
      return;
    }
    setState(() {
      _isDirectRouteActive = true;
      _isClosing = false;
    });
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute<void>(builder: widget.pageBuilder));
    if (!mounted) {
      return;
    }
    setState(() {
      _isDirectRouteActive = false;
    });
  }

  /// 标记收缩动画开始，便于后续判断是否需要跳过收缩效果。
  void _markClosing() {
    if (_isClosing) {
      return;
    }
    setState(() {
      _isClosing = true;
      _isOpen = false;
    });
    widget.onInteractionLockChanged?.call(true);
    _lockReleaseTimer?.cancel();
    // 动画仍在收缩时，短暂锁定底部导航，超时后自动恢复以提升交互流畅度。
    _lockReleaseTimer = Timer(_closeDuration, () {
      if (!mounted) {
        return;
      }
      if (_isClosing) {
        widget.onInteractionLockChanged?.call(false);
      }
      _lockReleaseTimer = null;
    });
  }

  /// 在容器完全关闭后重置状态，恢复正常的开合逻辑。
  void _resetClosing() {
    if (!_isClosing) {
      return;
    }
    setState(() {
      _isClosing = false;
    });
    _lockReleaseTimer?.cancel();
    _lockReleaseTimer = null;
    widget.onInteractionLockChanged?.call(false);
  }

  /// 构建闭合态的列表单元，统一处理样式与交互。
  Widget _buildClosedTile(
    ColorScheme colorScheme,
    BuildContext context, {
    required bool interactive,
  }) {
    return Material(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Icon(
          widget.icon,
          color: widget.iconColor ?? colorScheme.primary,
        ),
        title: Text(
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: interactive ? () => _handleTap(context) : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        tileColor: Colors.transparent,
      ),
    );
  }

  /// 构建带有 Material motion 动画的设置入口卡片。
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return _Hideable(
      key: _hideableKey,
      child: IgnorePointer(
        ignoring: _isClosing,
        child: _buildClosedTile(colorScheme, context, interactive: true),
      ),
    );
  }

  /// 当父级禁用动效时，若容器仍处于展开态则立即尝试收拢。
  @override
  void didUpdateWidget(covariant SettingsOpenContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enableTransition && !widget.enableTransition) {
      if (_isOpen && !_isClosing) {
        _markClosing();
        _activeRoute?.close();
      }
    }
  }

  @override
  void dispose() {
    _lockReleaseTimer?.cancel();
    super.dispose();
  }
}

/// 自定义的开合路由，支持不同的打开与关闭时长。
class _SettingsOpenContainerRoute<T> extends ModalRoute<T> {
  _SettingsOpenContainerRoute({
    required this.closedColor,
    required this.openColor,
    required this.middleColor,
    required double closedElevation,
    required this.openElevation,
    required ShapeBorder closedShape,
    required this.openShape,
    required this.openBuilder,
    required this.closedBuilder,
    required this.hideableKey,
    required this.openDuration,
    required this.closeDuration,
    required this.onStartClosing,
    this.clipBehavior = Clip.antiAlias,
  }) : _elevationTween = Tween<double>(
         begin: closedElevation,
         end: openElevation,
       ),
       _shapeTween = ShapeBorderTween(begin: closedShape, end: openShape),
       _colorTween = _buildColorTween(closedColor, openColor, middleColor),
       _closedOpacityTween = _buildClosedOpacityTween(),
       _openOpacityTween = _buildOpenOpacityTween();

  final Color closedColor;
  final Color openColor;
  final Color middleColor;
  final double openElevation;
  final ShapeBorder openShape;
  final WidgetBuilder openBuilder;
  final WidgetBuilder closedBuilder;
  final GlobalKey<_HideableState> hideableKey;
  final Duration openDuration;
  final Duration closeDuration;
  final VoidCallback onStartClosing;
  final Clip clipBehavior;

  final Tween<double> _elevationTween;
  final ShapeBorderTween _shapeTween;
  final _FlippableTweenSequence<Color?> _colorTween;
  final _FlippableTweenSequence<double> _closedOpacityTween;
  final _FlippableTweenSequence<double> _openOpacityTween;
  final GlobalKey _openBuilderKey = GlobalKey();
  final RectTween _rectTween = RectTween();
  bool _notifiedClosing = false;
  AnimationStatus? _lastAnimationStatus;
  AnimationStatus? _currentAnimationStatus;

  static final TweenSequence<Color?> _scrimFadeInTween =
      TweenSequence<Color?>(<TweenSequenceItem<Color?>>[
        TweenSequenceItem<Color?>(
          tween: ColorTween(begin: Colors.transparent, end: Colors.black54),
          weight: 1 / 5,
        ),
        TweenSequenceItem<Color?>(
          tween: ConstantTween<Color?>(Colors.black54),
          weight: 4 / 5,
        ),
      ]);

  static final Tween<Color?> _scrimFadeOutTween = ColorTween(
    begin: Colors.transparent,
    end: Colors.black54,
  );

  static _FlippableTweenSequence<Color?> _buildColorTween(
    Color closedColor,
    Color openColor,
    Color middleColor,
  ) {
    return _FlippableTweenSequence<Color?>(<TweenSequenceItem<Color?>>[
      TweenSequenceItem<Color?>(
        tween: ColorTween(begin: closedColor, end: middleColor),
        weight: 1 / 5,
      ),
      TweenSequenceItem<Color?>(
        tween: ColorTween(begin: middleColor, end: openColor),
        weight: 4 / 5,
      ),
    ]);
  }

  static _FlippableTweenSequence<double> _buildClosedOpacityTween() {
    return _FlippableTweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1.0, end: 0.0),
        weight: 1 / 5,
      ),
      TweenSequenceItem<double>(
        tween: ConstantTween<double>(0.0),
        weight: 4 / 5,
      ),
    ]);
  }

  static _FlippableTweenSequence<double> _buildOpenOpacityTween() {
    return _FlippableTweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: ConstantTween<double>(0.0),
        weight: 1 / 5,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 0.0, end: 1.0),
        weight: 4 / 5,
      ),
    ]);
  }

  void close() {
    _notifyClosing();
    if (subtreeContext != null) {
      Navigator.of(subtreeContext!).pop();
    }
  }

  void _notifyClosing() {
    if (_notifiedClosing) {
      return;
    }
    _notifiedClosing = true;
    onStartClosing();
  }

  bool get _transitionWasInterrupted {
    bool wasInProgress = false;
    bool isInProgress = false;

    switch (_currentAnimationStatus) {
      case AnimationStatus.completed:
      case AnimationStatus.dismissed:
        isInProgress = false;
        break;
      case AnimationStatus.forward:
      case AnimationStatus.reverse:
        isInProgress = true;
        break;
      case null:
        break;
    }

    switch (_lastAnimationStatus) {
      case AnimationStatus.completed:
      case AnimationStatus.dismissed:
        wasInProgress = false;
        break;
      case AnimationStatus.forward:
      case AnimationStatus.reverse:
        wasInProgress = true;
        break;
      case null:
        break;
    }
    return wasInProgress && isInProgress;
  }

  @override
  Duration get transitionDuration => openDuration;

  @override
  Duration get reverseTransitionDuration => closeDuration;

  @override
  bool get opaque => true;

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  void dispose() {
    if (hideableKey.currentState?.isVisible == false) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        final _HideableState? state = hideableKey.currentState;
        if (state != null) {
          state
            ..placeholderSize = null
            ..isVisible = true;
        }
      });
    }
    super.dispose();
  }

  @override
  TickerFuture didPush() {
    _takeMeasurements(navigatorContext: hideableKey.currentContext!);
    animation!.addStatusListener((AnimationStatus status) {
      _lastAnimationStatus = _currentAnimationStatus;
      _currentAnimationStatus = status;
      switch (status) {
        case AnimationStatus.dismissed:
          _toggleHideable(hide: false);
          break;
        case AnimationStatus.completed:
          _toggleHideable(hide: true);
          break;
        case AnimationStatus.forward:
        case AnimationStatus.reverse:
          break;
      }
    });
    return super.didPush();
  }

  @override
  bool didPop(T? result) {
    _notifyClosing();
    _takeMeasurements(
      navigatorContext: subtreeContext!,
      delayForSourceRoute: true,
    );
    return super.didPop(result);
  }

  void _toggleHideable({required bool hide}) {
    if (hideableKey.currentState != null) {
      hideableKey.currentState!
        ..placeholderSize = null
        ..isVisible = !hide;
    }
  }

  void _takeMeasurements({
    required BuildContext navigatorContext,
    bool delayForSourceRoute = false,
  }) {
    final RenderBox navigator =
        Navigator.of(navigatorContext).context.findRenderObject()! as RenderBox;
    final Size navSize = navigator.size;
    _rectTween.end = Offset.zero & navSize;

    void measureSource([Duration? _]) {
      if (!navigator.attached || hideableKey.currentContext == null) {
        return;
      }
      final RenderBox source =
          hideableKey.currentContext!.findRenderObject()! as RenderBox;
      _rectTween.begin = MatrixUtils.transformRect(
        source.getTransformTo(navigator),
        Offset.zero & source.size,
      );
      hideableKey.currentState!.placeholderSize = _rectTween.begin!.size;
    }

    if (delayForSourceRoute) {
      SchedulerBinding.instance.addPostFrameCallback(measureSource);
    } else {
      measureSource();
    }
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return Align(
      alignment: Alignment.topLeft,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          if (animation.isCompleted) {
            return SizedBox.expand(
              child: Material(
                color: openColor,
                elevation: openElevation,
                shape: openShape,
                clipBehavior: clipBehavior,
                child: Builder(key: _openBuilderKey, builder: openBuilder),
              ),
            );
          }

          final Animation<double> curvedAnimation = CurvedAnimation(
            parent: animation,
            curve: Curves.fastOutSlowIn,
            reverseCurve: _transitionWasInterrupted
                ? null
                : Curves.fastOutSlowIn.flipped,
          );

          Tweens tweens = _resolveTweens(animation.status);

          final Rect rect = _rectTween.evaluate(curvedAnimation)!;
          return SizedBox.expand(
            child: Container(
              color: tweens.scrim.evaluate(curvedAnimation),
              child: Align(
                alignment: Alignment.topLeft,
                child: Transform.translate(
                  offset: Offset(rect.left, rect.top),
                  child: SizedBox(
                    width: rect.width,
                    height: rect.height,
                    child: Material(
                      clipBehavior: clipBehavior,
                      color: tweens.color.evaluate(animation)!,
                      shape: _shapeTween.evaluate(curvedAnimation),
                      elevation: _elevationTween.evaluate(curvedAnimation),
                      child: Stack(
                        fit: StackFit.passthrough,
                        children: <Widget>[
                          FittedBox(
                            fit: BoxFit.fitWidth,
                            alignment: Alignment.topLeft,
                            child: SizedBox(
                              width: _rectTween.begin!.width,
                              height: _rectTween.begin!.height,
                              child:
                                  (hideableKey.currentState?.isInTree ?? false)
                                  ? null
                                  : Opacity(
                                      opacity: tweens.closedOpacity.evaluate(
                                        animation,
                                      ),
                                      child: Builder(builder: closedBuilder),
                                    ),
                            ),
                          ),
                          FittedBox(
                            fit: BoxFit.fitWidth,
                            alignment: Alignment.topLeft,
                            child: SizedBox(
                              width: _rectTween.end!.width,
                              height: _rectTween.end!.height,
                              child: Opacity(
                                opacity: tweens.openOpacity.evaluate(animation),
                                child: Builder(
                                  key: _openBuilderKey,
                                  builder: openBuilder,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Tweens _resolveTweens(AnimationStatus status) {
    switch (status) {
      case AnimationStatus.dismissed:
      case AnimationStatus.forward:
        return Tweens(
          color: _colorTween,
          closedOpacity: _closedOpacityTween,
          openOpacity: _openOpacityTween,
          scrim: _scrimFadeInTween,
        );
      case AnimationStatus.reverse:
        if (_transitionWasInterrupted) {
          return Tweens(
            color: _colorTween,
            closedOpacity: _closedOpacityTween,
            openOpacity: _openOpacityTween,
            scrim: _scrimFadeInTween,
          );
        }
        return Tweens(
          color: _colorTween.flipped!,
          closedOpacity: _closedOpacityTween.flipped!,
          openOpacity: _openOpacityTween.flipped!,
          scrim: _scrimFadeOutTween,
        );
      case AnimationStatus.completed:
        return Tweens(
          color: _colorTween,
          closedOpacity: _closedOpacityTween,
          openOpacity: _openOpacityTween,
          scrim: _scrimFadeInTween,
        );
    }
  }
}

/// 统一处理动画过程中使用的补间集合。
class Tweens {
  Tweens({
    required this.color,
    required this.closedOpacity,
    required this.openOpacity,
    required this.scrim,
  });

  final Animatable<Color?> color;
  final Animatable<double> closedOpacity;
  final Animatable<double> openOpacity;
  final Animatable<Color?> scrim;
}

/// 控制闭合内容在动画过程中的显示与占位状态。
class _Hideable extends StatefulWidget {
  const _Hideable({required this.child, super.key});

  final Widget child;

  @override
  State<_Hideable> createState() => _HideableState();
}

class _HideableState extends State<_Hideable> {
  Size? _placeholderSize;
  bool _visible = true;

  Size? get placeholderSize => _placeholderSize;
  set placeholderSize(Size? value) {
    if (_placeholderSize == value) {
      return;
    }
    setState(() {
      _placeholderSize = value;
    });
  }

  bool get isVisible => _visible;
  set isVisible(bool value) {
    if (_visible == value) {
      return;
    }
    setState(() {
      _visible = value;
    });
  }

  bool get isInTree => _placeholderSize == null;

  @override
  Widget build(BuildContext context) {
    if (_placeholderSize != null) {
      return SizedBox.fromSize(size: _placeholderSize);
    }
    return Opacity(opacity: _visible ? 1.0 : 0.0, child: widget.child);
  }
}

/// 可翻转的补间序列，便于在动画反向时沿用相同步骤。
class _FlippableTweenSequence<T> extends TweenSequence<T> {
  _FlippableTweenSequence(super.items) : _items = items;

  final List<TweenSequenceItem<T>> _items;
  _FlippableTweenSequence<T>? _flipped;

  _FlippableTweenSequence<T>? get flipped {
    if (_flipped == null) {
      final List<TweenSequenceItem<T>> newItems = <TweenSequenceItem<T>>[];
      for (int i = 0; i < _items.length; i++) {
        newItems.add(
          TweenSequenceItem<T>(
            tween: _items[i].tween,
            weight: _items[_items.length - 1 - i].weight,
          ),
        );
      }
      _flipped = _FlippableTweenSequence<T>(newItems);
    }
    return _flipped;
  }
}
