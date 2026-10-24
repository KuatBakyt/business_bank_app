import 'package:flutter/material.dart';
import 'models.dart';

const navy = Color(0xFF102B43);
const ink = Color(0xFF101F3C);
const teal = Color(0xFF008C91);
const muted = Color(0xFF687A92);
const canvas = Color(0xFFF5F8FC);
const line = Color(0xFFE4EBF3);

ThemeData bankTheme() => ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: canvas,
  fontFamily: 'Roboto',
  colorScheme: ColorScheme.fromSeed(seedColor: teal, primary: teal, secondary: navy, surface: Colors.white),
  textTheme: const TextTheme(
    headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: ink, letterSpacing: -.8),
    headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: ink),
    titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: ink),
    bodyMedium: TextStyle(fontSize: 14, color: ink, height: 1.45),
  ),
  inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: line)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: line))),
  filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)))),
  outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
    foregroundColor: ink, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
    side: const BorderSide(color: line), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)))),
  dividerTheme: const DividerThemeData(color: line, thickness: 1),
);

class Surface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const Surface({super.key, required this.child, this.padding = const EdgeInsets.all(24)});
  @override
  Widget build(BuildContext context) => Container(padding: padding,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: line)), child: child);
}

class StatusPill extends StatelessWidget {
  final String status;
  const StatusPill(this.status, {super.key});
  @override
  Widget build(BuildContext context) {
    final positive = ['EXECUTED', 'READY', 'ACTIVE'].contains(status);
    final waiting = ['PENDING_APPROVAL', 'QUEUED', 'PROCESSING'].contains(status);
    final color = positive ? const Color(0xFF087D6A) : waiting ? const Color(0xFFAD6700) : muted;
    return Container(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: .09), borderRadius: BorderRadius.circular(30)),
      child: Text(statuses[status] ?? status, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)));
  }
}

class SectionTitle extends StatelessWidget {
  final String title, subtitle;
  final Widget? action;
  const SectionTitle(this.title, this.subtitle, {super.key, this.action});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 25), child:
    Wrap(alignment: WrapAlignment.spaceBetween, runSpacing: 15, spacing: 24, crossAxisAlignment: WrapCrossAlignment.center,
      children: [Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.headlineLarge), const SizedBox(height: 6),
        Text(subtitle, style: const TextStyle(color: muted, fontSize: 15)),
      ]), if (action != null) action!]));
}

class EmptyState extends StatelessWidget {
  final String title, detail;
  final Widget? action;
  const EmptyState(this.title, this.detail, {super.key, this.action});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 35, horizontal: 12), child:
    Center(child: Column(children: [const Icon(Icons.inbox_outlined, size: 42, color: muted), const SizedBox(height: 15),
      Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center), const SizedBox(height: 8),
      Text(detail, style: const TextStyle(color: muted), textAlign: TextAlign.center),
      if (action != null) Padding(padding: const EdgeInsets.only(top: 20), child: action!)])));
}

void showError(BuildContext context, Object error) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('$error'), backgroundColor: const Color(0xFF913B3B), behavior: SnackBarBehavior.floating));
void showSuccess(BuildContext context, String message) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), backgroundColor: teal, behavior: SnackBarBehavior.floating));

Future<String?> askText(BuildContext context, String title, {String label = 'Название', String? value}) async {
  final controller = TextEditingController(text: value);
  final result = await showDialog<String>(context: context, builder: (context) => AlertDialog(
    title: Text(title), content: SizedBox(width: 380, child: TextField(controller: controller, autofocus: true,
      maxLength: 200, decoration: InputDecoration(labelText: label))),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
      FilledButton(onPressed: () { if (controller.text.trim().isNotEmpty) Navigator.pop(context, controller.text.trim()); }, child: const Text('Продолжить'))]));
  // Wait for the dialog transition before disposing its controller.
  await Future<void>.delayed(const Duration(milliseconds: 250));
  controller.dispose(); return result;
}
