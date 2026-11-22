import 'package:flutter/material.dart';
import 'account_access_screen.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});
  @override
  Widget build(BuildContext context) => const AccountAccessScreen(signIn: true);
}
