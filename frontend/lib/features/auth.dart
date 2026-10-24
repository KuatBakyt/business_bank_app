import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/design.dart';
import '../core/store.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController(),
      password = TextEditingController(),
      name = TextEditingController();
  bool register = false, hidden = true;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    name.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    await context.read<BankStore>().authenticate(email.text, password.text,
        register: register, name: name.text);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<BankStore>();
    return Scaffold(
        body: LayoutBuilder(
            builder: (context, box) => Row(children: [
                  if (box.maxWidth > 900)
                    Expanded(
                        child: Container(
                            color: navy,
                            padding: const EdgeInsets.all(64),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(children: [
                                    Icon(Icons.account_balance_rounded,
                                        color: Color(0xFF5DE0D4), size: 36),
                                    SizedBox(width: 14),
                                    Text('Business Bank',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 25,
                                            fontWeight: FontWeight.w700))
                                  ]),
                                  const Spacer(),
                                  const Text('Ваш бизнес.\nВсё под контролем.',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 46,
                                          fontWeight: FontWeight.w800,
                                          height: 1.15)),
                                  const SizedBox(height: 24),
                                  const Text(
                                      'Счета, платежи и команда\nв одном рабочем пространстве.',
                                      style: TextStyle(
                                          color: Color(0xFFB3C7D8),
                                          fontSize: 19,
                                          height: 1.6)),
                                  const SizedBox(height: 38),
                                  Container(
                                      padding: const EdgeInsets.all(22),
                                      decoration: BoxDecoration(
                                          color: Colors.white
                                              .withValues(alpha: .07),
                                          borderRadius:
                                              BorderRadius.circular(16)),
                                      child: const Row(children: [
                                        Icon(Icons.verified_user_outlined,
                                            color: Color(0xFF5DE0D4)),
                                        SizedBox(width: 14),
                                        Expanded(
                                            child: Text(
                                                'Согласование платежей и прозрачная история операций',
                                                style: TextStyle(
                                                    color: Colors.white,
                                                    height: 1.5)))
                                      ])),
                                  const Spacer(),
                                  const Text(
                                      'Учебный проект · Только тестовые средства',
                                      style:
                                          TextStyle(color: Color(0xFFB3C7D8))),
                                ]))),
                  Expanded(
                      child: Center(
                          child: SingleChildScrollView(
                              padding: const EdgeInsets.all(28),
                              child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 420),
                                  child: Form(
                                      key: form,
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            if (box.maxWidth <= 900)
                                              const Padding(
                                                  padding: EdgeInsets.only(
                                                      bottom: 30),
                                                  child: Text('Business Bank',
                                                      style: TextStyle(
                                                          color: teal,
                                                          fontSize: 24,
                                                          fontWeight: FontWeight
                                                              .w800))),
                                            Text(
                                                register
                                                    ? 'Создать аккаунт'
                                                    : 'С возвращением',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .headlineLarge),
                                            const SizedBox(height: 10),
                                            Text(
                                                register
                                                    ? 'Начните с личного аккаунта, затем создайте компанию.'
                                                    : 'Войдите в кабинет вашей компании.',
                                                style: const TextStyle(
                                                    color: muted)),
                                            const SizedBox(height: 30),
                                            if (register) ...[
                                              TextFormField(
                                                  controller: name,
                                                  decoration:
                                                      const InputDecoration(
                                                          labelText:
                                                              'Ваше имя'),
                                                  maxLength: 150),
                                              const SizedBox(height: 16)
                                            ],
                                            TextFormField(
                                                controller: email,
                                                keyboardType:
                                                    TextInputType.emailAddress,
                                                autofillHints: const [
                                                  AutofillHints.email
                                                ],
                                                decoration:
                                                    const InputDecoration(
                                                        labelText: 'Email',
                                                        prefixIcon: Icon(Icons
                                                            .mail_outline)),
                                                validator: (v) => v != null &&
                                                        RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                                            .hasMatch(v.trim())
                                                    ? null
                                                    : 'Введите email'),
                                            const SizedBox(height: 18),
                                            TextFormField(
                                                controller: password,
                                                obscureText: hidden,
                                                onFieldSubmitted: (_) {
                                                  if (!s.busy) submit();
                                                },
                                                decoration: InputDecoration(
                                                    labelText: 'Пароль',
                                                    prefixIcon: const Icon(
                                                        Icons.lock_outline),
                                                    suffixIcon: IconButton(
                                                        tooltip: hidden
                                                            ? 'Показать пароль'
                                                            : 'Скрыть пароль',
                                                        onPressed: () =>
                                                            setState(() =>
                                                                hidden =
                                                                    !hidden),
                                                        icon: Icon(hidden
                                                            ? Icons
                                                                .visibility_outlined
                                                            : Icons
                                                                .visibility_off_outlined))),
                                                validator: (v) =>
                                                    v == null || v.length < 8
                                                        ? 'Не менее 8 символов'
                                                        : null),
                                            if (s.error != null)
                                              Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 18),
                                                  child: Text(s.error!,
                                                      style: const TextStyle(
                                                          color: Colors.red))),
                                            const SizedBox(height: 24),
                                            SizedBox(
                                                width: double.infinity,
                                                child: FilledButton(
                                                    onPressed:
                                                        s.busy ? null : submit,
                                                    child: s.busy
                                                        ? const SizedBox(
                                                            width: 19,
                                                            height: 19,
                                                            child:
                                                                CircularProgressIndicator(
                                                                    strokeWidth:
                                                                        2))
                                                        : Text(register
                                                            ? 'Зарегистрироваться'
                                                            : 'Войти в кабинет'))),
                                            const SizedBox(height: 15),
                                            Center(
                                                child: TextButton(
                                                    onPressed: s.busy
                                                        ? null
                                                        : () => setState(() =>
                                                            register =
                                                                !register),
                                                    child: Text(register
                                                        ? 'Уже есть аккаунт? Войти'
                                                        : 'Создать аккаунт'))),
                                            const SizedBox(height: 28),
                                            const Text(
                                                'Тестовые средства. Реальные переводы не выполняются. После обновления страницы войдите снова.',
                                                style: TextStyle(
                                                    color: muted,
                                                    fontSize: 12,
                                                    height: 1.5)),
                                          ])))))),
                ])));
  }
}
