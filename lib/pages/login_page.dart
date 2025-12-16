import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'menu_intermedio_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _loggingIn = false;
  bool _keepLoggedIn = true;

  Future<void> _login() async {
    setState(() => _loggingIn = true);

    final usuario = _userController.text.trim();
    final password = _passwordController.text.trim();

    if (usuario.isEmpty || password.isEmpty) {
      _showMessage("Por favor, ingresa usuario y contraseña.", isError: true);
      setState(() => _loggingIn = false);
      return;
    }

    try {
      final url = Uri.parse("https://serviciosjr.com/models/control_app.php");

      final response = await http.post(
        url,
        headers: {"Content-Type": "application/x-www-form-urlencoded"},

        body: {'usu': usuario, 'pss': password},
      );

      debugPrint("📡 Código HTTP: ${response.statusCode}");
      debugPrint("📩 Respuesta: ${response.body}");

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true) {
          final prefs = await SharedPreferences.getInstance();
          final userInfo = data['usuario'];

          // Guarda datos de usuario
          await prefs.setString('userData', json.encode(userInfo));
          await prefs.setBool('isLoggedIn', _keepLoggedIn);

          _showMessage("Inicio de sesión exitoso");

          if (!mounted) return;

          await Future.delayed(const Duration(milliseconds: 600));

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const MenuIntermedioPage()),
          );
        } else {
          _showMessage(
            data['message'] ?? "Usuario o contraseña incorrectos.",
            isError: true,
          );
        }
      } else {
        _showMessage(
          "Error de conexión (${response.statusCode}).",
          isError: true,
        );
      }
    } catch (e) {
      debugPrint("❌ Error: $e");
      _showMessage("No se pudo conectar al servidor.", isError: true);
    } finally {
      setState(() => _loggingIn = false);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    final snackBar = SnackBar(
      content: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: Colors.white,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
      backgroundColor: isError ? Colors.red.shade400 : Colors.green.shade400,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 2),
    );

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(snackBar);
  }

  @override
  Widget build(BuildContext context) {
    final rojoSuave = Colors.red.shade50;
    final rojoPrincipal = Colors.red.shade400;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.white, rojoSuave],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset('assets/images/logo.png', width: 130),
                const SizedBox(height: 15),
                Text(
                  'Servicios JR App',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 40),

                TextField(
                  controller: _userController,
                  decoration: InputDecoration(
                    labelText: 'Usuario',
                    prefixIcon: const Icon(Icons.person_outline),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 15),

                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: const Icon(Icons.lock_outline),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 15),

                Row(
                  children: [
                    Checkbox(
                      value: _keepLoggedIn,
                      activeColor: rojoPrincipal,
                      onChanged: (v) =>
                          setState(() => _keepLoggedIn = v ?? false),
                    ),
                    const Text("Mantener sesión iniciada"),
                  ],
                ),

                const SizedBox(height: 20),

                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: rojoPrincipal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 80,
                      vertical: 15,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _loggingIn ? null : _login,
                  child: _loggingIn
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Ingresar',
                          style: TextStyle(fontSize: 18, color: Colors.white),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
