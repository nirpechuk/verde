import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:client/helpers/utils.dart';

@immutable
class ExpandableFab extends StatefulWidget {
  const ExpandableFab({
    super.key,
    this.initialOpen,
    required this.distance,
    required this.children,
    this.backgroundColor,
    this.iconColor,
    this.isDarkMode = false,
  });

  final bool? initialOpen;
  final double distance;
  final List<Widget> children;
  final Color? backgroundColor;
  final Color? iconColor;
  final bool isDarkMode;

  @override
  State<ExpandableFab> createState() => _ExpandableFabState();
}

class _ExpandableFabState extends State<ExpandableFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _expandAnimation;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _open = widget.initialOpen ?? false;
    _controller = AnimationController(
      value: _open ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      curve: Curves.fastOutSlowIn,
      reverseCurve: Curves.easeOutQuad,
      parent: _controller,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _open = !_open;
      if (_open) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Stack(
        alignment: Alignment.bottomRight,
        clipBehavior: Clip.none,
        children: [
          if (_open) _buildTapToCloseFab(),
          ..._buildExpandingActionButtons(),
          if (!_open) _buildTapToOpenFab(),
        ],
      ),
    );
  }

  Widget _buildTapToCloseFab() {
    return Container(
      width: kMainFabSize,
      height: kMainFabSize,
      decoration: BoxDecoration(
        color: widget.isDarkMode 
            ? highlight.withValues(alpha: 0.1)
            : lightModeDark.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(kMainFabBorderRadius),
        border: Border.all(
          color: widget.isDarkMode 
              ? highlight.withValues(alpha: 0.3)
              : lightModeDark.withValues(alpha: 0.9),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: (widget.isDarkMode ? highlight : lightModeDark).withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 0),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(kMainFabBorderRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(kMainFabBorderRadius),
          onTap: _toggle,
          child: Container(
            width: kMainFabSize,
            height: kMainFabSize,
            alignment: Alignment.center,
            child: Icon(
              Icons.close,
              color: widget.backgroundColor,
              size: kFloatingButtonIconSize + 6,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTapToOpenFab() {
    return IgnorePointer(
      ignoring: _open,
      child: AnimatedContainer(
        transformAlignment: Alignment.center,
        transform: Matrix4.diagonal3Values(
          _open ? 0.7 : 1.0,
          _open ? 0.7 : 1.0,
          1.0,
        ),
        duration: const Duration(milliseconds: 250),
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
        child: AnimatedOpacity(
          opacity: _open ? 0.0 : 1.0,
          curve: const Interval(0.25, 1.0, curve: Curves.easeInOut),
          duration: const Duration(milliseconds: 250),
          child: Container(
            width: kMainFabSize,
            height: kMainFabSize,
            decoration: BoxDecoration(
              color: widget.isDarkMode 
                  ? highlight.withValues(alpha: 0.1)
                  : lightModeDark.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(kMainFabBorderRadius),
              border: Border.all(
                color: widget.isDarkMode 
                    ? highlight.withValues(alpha: 0.3)
                    : lightModeDark.withValues(alpha: 0.9),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: (widget.isDarkMode ? highlight : lightModeDark).withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 0),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(kMainFabBorderRadius),
              child: InkWell(
                borderRadius: BorderRadius.circular(kMainFabBorderRadius),
                onTap: _toggle,
                child: Container(
                  width: kMainFabSize,
                  height: kMainFabSize,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.add,
                    color: widget.iconColor,
                    size: kFloatingButtonIconSize + 6,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildExpandingActionButtons() {
    final children = <Widget>[];
    final count = widget.children.length;
    for (var i = 0; i < count; i++) {
      // Calculate distance so buttons are evenly spaced from each other
      // First button: edge of main FAB + padding + half of action button
      // Each subsequent button: previous position + button size + spacing
      final firstButtonDistance =
          (kMainFabSize / 2) +
          24 +
          (kFloatingButtonSize / 2); // 20px padding from main FAB
      final buttonDistance =
          firstButtonDistance + (i * (kFloatingButtonSize + widget.distance));

      children.add(
        _ExpandingActionButton(
          directionInDegrees: 90, // straight up
          maxDistance: buttonDistance,
          progress: _expandAnimation,
          child: widget.children[i],
        ),
      );
    }
    return children;
  }
}

/// Private widget for individual expanding buttons.
@immutable
class _ExpandingActionButton extends StatelessWidget {
  const _ExpandingActionButton({
    required this.directionInDegrees,
    required this.maxDistance,
    required this.progress,
    required this.child,
  });

  final double directionInDegrees;
  final double maxDistance;
  final Animation<double> progress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: progress,
      builder: (context, child) {
        final offset = Offset.fromDirection(
          directionInDegrees * (math.pi / 180.0),
          progress.value * maxDistance,
        );
        return Positioned(
          right: 4.0 + offset.dx,
          bottom: 4.0 + offset.dy,
          child: Transform.rotate(
            angle: (1.0 - progress.value) * math.pi / 2,
            child: child!,
          ),
        );
      },
      child: FadeTransition(opacity: progress, child: child),
    );
  }
}

/// Widget for each individual action button inside the expandable FAB.
@immutable
class ActionButton extends StatelessWidget {
  const ActionButton({
    super.key,
    this.onPressed,
    required this.icon,
    required this.backgroundColor,
    required this.iconColor,
    this.iconSize,
    this.isDarkMode = false,
  });

  final VoidCallback? onPressed;
  final Widget icon;
  final Color? backgroundColor;
  final Color? iconColor;
  final double? iconSize;
  final bool isDarkMode;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kFloatingButtonSize,
      height: kFloatingButtonSize,
      decoration: BoxDecoration(
        color: isDarkMode 
            ? highlight.withValues(alpha: 0.1)
            : lightModeDark.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(kFloatingButtonBorderRadius),
        border: Border.all(
          color: isDarkMode 
              ? highlight.withValues(alpha: 0.3)
              : lightModeDark.withValues(alpha: 0.9),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: (isDarkMode ? highlight : lightModeDark).withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 0),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(kFloatingButtonBorderRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(kFloatingButtonBorderRadius),
          onTap: onPressed,
          child: Container(
            width: kFloatingButtonSize,
            height: kFloatingButtonSize,
            alignment: Alignment.center,
            child: IconTheme(
              data: IconThemeData(
                color: iconColor,
                size: kFloatingButtonIconSize,
              ),
              child: icon,
            ),
          ),
        ),
      ),
    );
  }
}
