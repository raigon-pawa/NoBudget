import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'store.dart';
import 'ui.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  var register = false;
  var busy = false;
  String? message; // error or confirmation shown under the form

  /// Runs an auth call, showing its error (or [done]) under the form.
  Future<void> _run(Future<void> Function() call, {String? done}) async {
    setState(() {
      busy = true;
      message = null;
    });
    String? result = done;
    try {
      await call();
    } on FirebaseAuthException catch (e) {
      result = switch (e.code) {
        'invalid-credential' || 'wrong-password' || 'user-not-found' => 'Wrong email or password.',
        'email-already-in-use' => 'That email already has an account. Sign in instead.',
        'weak-password' => 'Use a password of at least 6 characters.',
        'invalid-email' => 'That does not look like an email address.',
        'network-request-failed' => 'No internet connection.',
        _ => e.message ?? e.code,
      };
    }
    // After a successful sign-in this page is already gone.
    if (mounted) {
      setState(() {
        busy = false;
        message = result;
      });
    }
  }

  void _submit() => _run(() async {
    final auth = FirebaseAuth.instance;
    if (register) {
      await auth.createUserWithEmailAndPassword(email: email.text.trim(), password: password.text);
      store.seedPresets();
    } else {
      await auth.signInWithEmailAndPassword(email: email.text.trim(), password: password.text);
    }
  });

  @override
  Widget build(BuildContext context) {
    final ok = !busy && email.text.contains('@') && password.text.length >= 6;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 14,
                children: [
                  const Text(
                    'NoBudget',
                    style: TextStyle(fontSize: 40, fontWeight: FontWeight.w700, letterSpacing: -1),
                  ),
                  Text(
                    register
                        ? 'Create an account to keep your budget private and backed up.'
                        : 'Sign in to your budget.',
                    style: const TextStyle(color: dim),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  TextField(
                    controller: password,
                    obscureText: true,
                    autofillHints: [register ? AutofillHints.newPassword : AutofillHints.password],
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => ok ? _submit() : null,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      helperText: register ? 'At least 6 characters' : null,
                    ),
                  ),
                  if (message != null) Text(message!, style: const TextStyle(color: Color(0xFFE0A070))),
                  FilledButton(
                    onPressed: ok ? _submit : null,
                    child: Text(busy ? 'Please wait…' : (register ? 'Create account' : 'Sign in')),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                            register = !register;
                            message = null;
                          }),
                    child: Text(register ? 'I already have an account' : 'Create an account'),
                  ),
                  if (!register)
                    TextButton(
                      onPressed: busy || !email.text.contains('@')
                          ? null
                          : () => _run(
                              () => FirebaseAuth.instance.sendPasswordResetEmail(email: email.text.trim()),
                              done: 'If that email has an account, a reset link is on its way.',
                            ),
                      child: const Text('Forgot password?'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
