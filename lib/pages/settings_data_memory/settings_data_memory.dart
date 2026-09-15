import 'package:galmax/pages/settings_data_memory/settings_data_memory_view.dart';
import 'package:flutter/material.dart';

class SettingsDataMemory extends StatefulWidget {
  const SettingsDataMemory({super.key});

  @override
  State<SettingsDataMemory> createState() => SettingsDataMemoryState();
}

class SettingsDataMemoryState extends State<SettingsDataMemory> {
  @override
  Widget build(BuildContext context) => SettingsDataMemoryView(this);
}
