import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class forgotPassword extends StatefulWidget {
  @override
  _ForgotPasswordState createState() => _ForgotPasswordState();
}

class _ForgotPasswordState extends State<forgotPassword> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(
          Uri.parse("https://twitter-6b2d1.firebaseapp.com/__/auth/action"));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Reset Password")),
      body: WebViewWidget(controller: _controller),
    );
  }
}
