import 'package:flutter/material.dart';

/// Accent seeds. Every entry is a single flat colour: the theme derives one
/// accent from it and keeps every surface neutral, so picking a colour never
/// repaints the app.
const Map<String, Color> kAccentColors = <String, Color>{
  'black': Color(0xFF1C1C1E),
  'blue': Color(0xFF2F6BEA),
  'lightBlue': Color(0xFF0E93BE),
  'green': Color(0xFF2E8B57),
  'pink': Color(0xFFC2185B),
  'red': Color(0xFFC2362F),
  'orange': Color(0xFFC2703A),
  'purple': Color(0xFF6C4AB6),
};

/// The default signal: copper. Warm enough to read as an instrument needle,
/// quiet enough to sit in a room full of ink.
const Color kDefaultAccent = Color(0xFFC2703A);
