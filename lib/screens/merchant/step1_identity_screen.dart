import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../providers/merchant_provider.dart';
import '../../theme/app_theme.dart';

class Step1IdentityScreen extends StatelessWidget {
  const Step1IdentityScreen({super.key});

  Future<void> _pickImage(
    BuildContext context,
    void Function(String path) onPicked,
  ) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text('اختر مصدر الصورة', style: AppTheme.heading3),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.camera_alt_outlined,
                      color: AppColors.primary),
                ),
                title: Text('الكاميرا', style: AppTheme.bodyLarge),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.photo_library_outlined,
                      color: AppColors.primary),
                ),
                title: Text('المعرض', style: AppTheme.bodyLarge),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null) return;

    final picker = ImagePicker();
    final image = await picker.pickImage(source: source, imageQuality: 80);
    if (image != null) {
      onPicked(image.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MerchantProvider>();
    final merchant = provider.merchant;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Section title
          Text('التحقق من الهوية', style: AppTheme.heading3),
          const SizedBox(height: 4),
          Text(
            'قم برفع صورتك الشخصية وصور الهوية الوطنية',
            style: AppTheme.bodyMedium,
          ),
          const SizedBox(height: 24),

          // Personal photo
          Center(
            child: Column(
              children: [
                Text('صورة العضوية', style: AppTheme.labelText),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => _pickImage(
                    context,
                    (path) => provider.setPersonalPhoto(path),
                  ),
                  child: _PersonalPhotoWidget(
                    photoPath: merchant.personalPhotoPath,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // National ID section
          Text('صورة البطاقة الشخصية', style: AppTheme.labelText),
          const SizedBox(height: 12),

          Row(
            children: [
              // Back side (right in RTL)
              Expanded(
                child: _IdCardUpload(
                  label: 'الوجه الخلفي',
                  imagePath: merchant.nationalIdBackPath,
                  onTap: () => _pickImage(
                    context,
                    (path) => provider.setNationalIdBack(path),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Front side (left in RTL)
              Expanded(
                child: _IdCardUpload(
                  label: 'الوجه الأمامي',
                  imagePath: merchant.nationalIdFrontPath,
                  onTap: () => _pickImage(
                    context,
                    (path) => provider.setNationalIdFront(path),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Next button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: provider.isStep1Valid
                  ? () => provider.nextStep()
                  : null,
              style: AppTheme.primaryButton(),
              child: Text('التالي', style: AppTheme.buttonText),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonalPhotoWidget extends StatelessWidget {
  final String? photoPath;

  const _PersonalPhotoWidget({this.photoPath});

  @override
  Widget build(BuildContext context) {
    if (photoPath != null) {
      return Stack(
        children: [
          CircleAvatar(
            radius: 50,
            backgroundImage: FileImage(File(photoPath!)),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.white, width: 2),
              ),
              child: const Icon(Icons.edit, size: 14, color: AppColors.white),
            ),
          ),
        ],
      );
    }

    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.inputBg,
        border: Border.all(
          color: AppColors.border,
          width: 1.5,
        ),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.camera_alt_outlined,
              size: 28, color: AppColors.textLight),
          SizedBox(height: 4),
          Text(
            'رفع صورة',
            style: TextStyle(fontSize: 10, color: AppColors.textLight),
          ),
        ],
      ),
    );
  }
}

class _IdCardUpload extends StatelessWidget {
  final String label;
  final String? imagePath;
  final VoidCallback onTap;

  const _IdCardUpload({
    required this.label,
    this.imagePath,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 1.5,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.inputBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: imagePath != null ? AppColors.primary : AppColors.border,
              width: imagePath != null ? 1.5 : 1,
            ),
            image: imagePath != null
                ? DecorationImage(
                    image: FileImage(File(imagePath!)),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: imagePath != null
              ? Stack(
                  children: [
                    // Green checkmark badge
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check,
                            size: 14, color: AppColors.white),
                      ),
                    ),
                    // Label at bottom
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(13),
                          ),
                        ),
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: AppTheme.bodySmall.copyWith(
                            color: AppColors.white,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.cloud_upload_outlined,
                        size: 28, color: AppColors.textLight),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      style: AppTheme.bodySmall.copyWith(fontSize: 11),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
