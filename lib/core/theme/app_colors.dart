import 'package:flutter/material.dart';

/// MediSense — single-flow US health companion.
/// One calm clinical-teal identity with a red emergency accent.
abstract class AppColors {
  // Neutral foundation
  static const paper = Color(0xFFF6F9F8);
  static const card = Color(0xFFFFFFFF);
  static const ink = Color(0xFF122430);
  static const inkSoft = Color(0xFF32454E);
  static const muted = Color(0xFF5E7179);
  static const line = Color(0xFFE1E9E7);
  static const success = Color(0xFF1FA05C);
  static const successSoft = Color(0xFFE2F5EA);
  static const warning = Color(0xFFC07A12);
  static const warningSoft = Color(0xFFFAF0DE);
  static const danger = Color(0xFFD03A30);
  static const dangerSoft = Color(0xFFFBE9E7);
  static const dangerDark = Color(0xFF2A0F0D);
  static const dangerGradient = [Color(0xFFD03A30), Color(0xFFE0554B)];

  // Brand — MediSense teal
  static const primary = Color(0xFF0C8577);
  static const primaryDark = Color(0xFF085F55);
  static const soft = Color(0xFFDFF2EF);
  static const onSoft = Color(0xFF085F55);
  static const gradient = [Color(0xFF0C8577), Color(0xFF15A392)];

  // Secondary accent — AI violet, used for MedAI assistant surfaces.
  static const ai = Color(0xFF5B4FC7);
  static const aiSoft = Color(0xFFEAE8FA);
  static const aiGradient = [Color(0xFF5B4FC7), Color(0xFF7A6FE0)];
}