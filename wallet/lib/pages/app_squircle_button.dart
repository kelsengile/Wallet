import 'package:flutter/material.dart';

/// Shared tactile "squircle" button used across the calculator and the
/// converter keypad so both screens feel like one design system.
///
/// Press-down scales the button slightly and darkens its background;
/// release springs it back. Visuals (radius, shadow depth) are derived
/// from [height] so the same widget looks right at any size.
class AppSquircleButton extends StatefulWidget {
  final Widget child;
  final double width;
  final double height;
  final Color bgColor;
  final VoidCallback onTap;
  final AlignmentGeometry alignment;
  final EdgeInsetsGeometry? padding;

  const AppSquircleButton({
    super.key,
    required this.child,
    required this.width,
    required this.height,
    required this.bgColor,
    required this.onTap,
    this.alignment = Alignment.center,
    this.padding,
  });

  @override
  State<AppSquircleButton> createState() => _AppSquircleButtonState();
}

class _AppSquircleButtonState extends State<AppSquircleButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 70),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.93).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeIn),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _down(_) {
    setState(() => _pressed = true);
    _ctrl.forward();
  }

  void _up(_) {
    setState(() => _pressed = false);
    _ctrl.reverse();
    widget.onTap();
  }

  void _cancel() {
    setState(() => _pressed = false);
    _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = widget.height * 0.36;
    final shadowAlpha1 = isDark ? 0.32 : 0.10;
    final shadowAlpha2 = isDark ? 0.16 : 0.04;

    final effectiveBg = _pressed
        ? Color.alphaBlend(Colors.black.withValues(alpha: 0.06), widget.bgColor)
        : widget.bgColor;

    return GestureDetector(
      onTapDown: _down,
      onTapUp: _up,
      onTapCancel: _cancel,
      child: ScaleTransition(
        scale: _scale,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: widget.width,
          height: widget.height,
          decoration: ShapeDecoration(
            color: effectiveBg,
            shape: ContinuousRectangleBorder(
              borderRadius: BorderRadius.circular(radius),
            ),
            shadows: [
              BoxShadow(
                color: Colors.black.withValues(alpha: shadowAlpha1),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: shadowAlpha2),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          alignment: widget.alignment,
          padding: widget.padding ?? EdgeInsets.zero,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Shared page header: leading icon button + bold title, matching across
/// the calculator and converter screens.
class AppPageHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final IconData leadingIcon;
  final VoidCallback onLeadingTap;
  final String leadingTooltip;
  final Widget? trailing;
  final double topPadding;

  const AppPageHeader({
    super.key,
    required this.title,
    required this.onLeadingTap,
    this.leadingIcon = Icons.close_rounded,
    this.leadingTooltip = 'Close',
    this.trailing,
    this.topPadding = 0,
  });

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(4, topPadding + 12, 16, 12),
      color: cs.surfaceContainer,
      child: Row(
        children: [
          IconButton(
            icon: Icon(leadingIcon, color: cs.onSurface),
            onPressed: onLeadingTap,
            tooltip: leadingTooltip,
          ),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
