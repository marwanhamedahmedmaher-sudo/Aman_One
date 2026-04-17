import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

String formatDate(DateTime? date) {
  if (date == null) return '';
  return '${date.day}/${date.month}/${date.year}';
}

String maskPhone(String phone) {
  if (phone.length <= 4) return phone;
  return '${'*' * (phone.length - 4)}${phone.substring(phone.length - 4)}';
}

(String label, Color color) merchantStatusDisplay(String status) {
  return switch (status) {
    'lead' => ('عميل محتمل', AppColors.buttonOrange),
    'qualified' => ('مؤهل', AppColors.primary),
    'rejected' => ('مرفوض', AppColors.buttonRed),
    'converted' => ('تم التحويل', AppColors.primaryDark),
    _ => (status, AppColors.textMedium),
  };
}
