import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

class _NavItem {
  final IconData icon;
  final String label;

  const _NavItem({required this.icon, required this.label});
}

/// Premium floating navigation bar for Privora.
/// Features a translucent blue-tinted glass aesthetic with BackdropFilter blur,
/// animated brand-blue pill indicators, and floating geometry.
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
    return SafeArea(
      bottom: true,
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              height: 70,
              decoration: BoxDecoration(
                // 86% opacity light-blue / white translucent glass
                color: const Color(0xDCF7FCFF),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: AppColors.brandSkyBlue.withValues(alpha: 0.35),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryActionBlue.withValues(alpha: 0.12),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: List.generate(_items.length, (index) {
                  final item = _items[index];
                  final isSelected = index == currentIndex;

                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onTap(index),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
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
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            style: AppTypography.navLabel.copyWith(
                              color: isSelected
                                  ? AppColors.primaryActionBlue
                                  : AppColors.secondaryTextColor,
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
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
