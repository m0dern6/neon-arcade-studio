import 'package:flutter/material.dart';

class GameMetadata {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final Color themeColor;
  final Widget gameWidget;

  GameMetadata({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.themeColor,
    required this.gameWidget,
  });
}
