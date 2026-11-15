import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'firebase_options.dart';
import 'store.dart';
import 'ui.dart';

/// Starts Firebase, which only sync needs. False when it cannot, e.g. a website opened offline: the app
/// works without it, and signing in tries again.
Future<bool> connectFirebase() async {
  if (Firebase.apps.isNotEmpty) return true;
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (_) {
    return false;
  }
  // The device copy is the store's own: no second one in Firestore's cache.
  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: false);
  // Against the local Firebase emulators: flutter run --dart-define=EMULATOR=true
  if (const bool.fromEnvironment('EMULATOR')) {
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
  }
  FirebaseAuth.instance.authStateChanges().listen((user) => user == null ? store.stopSync() : store.startSync(user.uid));
  return true;
}

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
        'popup-closed-by-user' || 'cancelled-popup-request' || 'web-context-canceled' => null, // changed their mind
        'popup-blocked' => 'Your browser blocked the Google window. Allow pop-ups for this site and try again.',
        _ => 'That did not work (${e.code}). Try again.',
      };
    } on GoogleSignInException catch (e) {
      result = e.code == GoogleSignInExceptionCode.canceled ? null : 'Google sign-in did not work (${e.code.name}).';
    }
    if (!mounted) return;
    if (FirebaseAuth.instance.currentUser != null) {
      Navigator.pop(context); // signed in: back to the app, which now syncs
    } else {
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
    } else {
      await auth.signInWithEmailAndPassword(email: email.text.trim(), password: password.text);
    }
  });

  /// Google decides whether this is a new account or an existing one.
  void _google() => _run(() async {
    if (kIsWeb) {
      await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
    } else {
      // The account chooser. The app's Google client id comes from android/app/google-services.json.
      await GoogleSignIn.instance.initialize();
      final account = await GoogleSignIn.instance.authenticate();
      await FirebaseAuth.instance.signInWithCredential(
        GoogleAuthProvider.credential(idToken: account.authentication.idToken),
      );
    }
  });

  @override
  Widget build(BuildContext context) {
    final ok = !busy && email.text.contains('@') && password.text.length >= 6;
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.black),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: AutofillGroup(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
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
                          ? 'Create an account to back up your budget and use it on all your devices.'
                          : 'Sign in to back up your budget and use it on all your devices.',
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
                    OutlinedButton(
                      onPressed: busy ? null : _google,
                      child: Text.rich(
                        TextSpan(
                          text: 'Continue with ',
                          children: [
                            // The letters of Google's logo: blue, red, yellow, blue, green, red.
                            for (final (letter, color) in [
                              ('G', 0xFF4285F4),
                              ('o', 0xFFEA4335),
                              ('o', 0xFFFBBC05),
                              ('g', 0xFF4285F4),
                              ('l', 0xFF34A853),
                              ('e', 0xFFEA4335),
                            ])
                              TextSpan(
                                text: letter,
                                style: TextStyle(color: Color(color), fontWeight: FontWeight.w700),
                              ),
                          ],
                        ),
                      ),
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
      ),
    );
  }
}
