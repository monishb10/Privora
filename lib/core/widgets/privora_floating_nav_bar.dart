import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_typography.dart';

class _NavItem {
  final IconData icon;
  final String label;

  const _NavItem({required this.icon, required this.label});
}

/// Polished floating navigation bar for Privora.
/// Features a floating capsule with a nearly opaque white/soft-blue tint,
/// delicate border #DCE5F2, restrained shadow, smooth selected-pill transition
/// over 200 ms, and accessible touch targets.
class PrivoraFloatingNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const PrivoraFloatingNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  static const List<_NavItem> _items = [
    _NavItem(icon: Icons.grid_view_rounded, label: 'Categories'),
    _NavItem(icon: Icons.camera_alt_rounded, label: 'Camera'),
    _NavItem(icon: Icons.delete_outline_rounded, label: 'Trash'),
    _NavItem(icon: Icons.shield_outlined, label: 'Account'),
  ];

  @override
  Widget build(BuildContext context) {
    final isReduced = AppMotion.isReducedMotion(context);

    return SafeArea(
      bottom: true,
      child: Padding(
        padding: const EdgeInsets.only(left: 20, right: 20, bottom: 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: isReduced
              // Solid tinted fallback when blur is disabled/expensive
              ? Container(
                  height: 68,
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: AppColors.borderDivider,
                      width: 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.cardShadow,
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: _buildNavRow(),
                )
              // Clipped backdrop blur on small surface with nearly opaque soft tint
              : BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    height: 68,
                    decoration: BoxDecoration(
                      color: const Color(0xF5FFFFFF),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: AppColors.borderDivider,
                        width: 1.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.cardShadow,
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: _buildNavRow(),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildNavRow() {
    return Row(
      children: List.generate(_items.length, (index) {
        final item = _items[index];
        final isSelected = index == currentIndex;

        return Expanded(
          child: PrivoraPressable(
            behavior: HitTestBehavior.opaque,
            onTap: () => onTap(index),
            child: Semantics(
              button: true,
              selected: isSelected,
              label: '${item.label} tab',
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration: AppMotion.navTransitionDuration,
                    curve: AppMotion.standardCurve,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primaryActionBlue
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      item.icon,
                      size: 20,
                      color: isSelected
                          ? Colors.white
                          : AppColors.secondaryTextColor,
                    ),
                  ),
                  const SizedBox(height: 3),
                  AnimatedDefaultTextStyle(
                    duration: AppMotion.navTransitionDuration,
                    curve: AppMotion.standardCurve,
                    style: AppTypography.navLabel.copyWith(
                      color: isSelected
                          ? AppColors.primaryActionBlue
                          : AppColors.secondaryTextColor,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}
