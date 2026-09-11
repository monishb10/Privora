import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'privora_logo.dart';
import 'privora_wordmark.dart';

/// Mathematically centred Top App Bar for Privora's main authenticated screens.
/// Features a centred Privora logo and title in Playfair Display Bold,
/// with Search and Lock actions positioned on the right without shifting the title.
class PrivoraBrandAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  final bool isSearching;
  final TextEditingController? searchController;
  final ValueChanged<String>? onSearchChanged;
  final VoidCallback onToggleSearch;
  final VoidCallback onLock;

  const PrivoraBrandAppBar({
    super.key,
    this.isSearching = false,
    this.searchController,
    this.onSearchChanged,
    required this.onToggleSearch,
    required this.onLock,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: AppColors.background,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      // Mathematical centering via Stack inside flexibleSpace:
      // Spans the full screen width, centering the logo and title at screenWidth / 2.
      flexibleSpace: SafeArea(
        child: SizedBox(
          height: kToolbarHeight,
          child: isSearching
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: searchController,
                          autofocus: true,
                          style: AppTypography.bodyLarge,
                          decoration: const InputDecoration(
                            hintText: 'Search categories...',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            fillColor: Colors.transparent,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: onSearchChanged,
                        ),
                      ),
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            color: AppColors.primaryText,
                          ),
                          tooltip: 'Close Search',
                          onPressed: onToggleSearch,
                        ),
                      ),
                    ],
                  ),
                )
              : Stack(
                  alignment: Alignment.center,
                  children: [
                    // Left corner: Privora logo icon only
                    const Positioned(
                      left: 16,
                      child: PrivoraLogo(size: 30, showShadow: false),
                    ),

                    // Mathematically centred brand title wordmark image
                    const Center(
                      child: Padding(
                        // Symmetrical margins preserve perfect center while guarding actions and logo
                        padding: EdgeInsets.symmetric(horizontal: 104),
                        child: PrivoraWordmark(height: 26),
                      ),
                    ),

                    // Right action buttons with 48px touch targets
                    Positioned(
                      right: 8,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 48,
                            height: 48,
                            child: IconButton(
                              icon: const Icon(
                                Icons.search_rounded,
                                color: AppColors.primaryText,
                              ),
                              tooltip: 'Search Categories',
                              onPressed: onToggleSearch,
                            ),
                          ),
                          SizedBox(
                            width: 48,
                            height: 48,
                            child: IconButton(
                              icon: const Icon(
                                Icons.lock_outline_rounded,
                                color: AppColors.primaryText,
                              ),
                              tooltip: 'Lock Privora',
                              onPressed: onLock,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
