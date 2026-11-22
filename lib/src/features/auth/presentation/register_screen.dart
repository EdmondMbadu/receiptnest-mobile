import 'package:flutter/material.dart';
import 'account_access_screen.dart';

class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const AccountAccessScreen(signIn: false);
}
