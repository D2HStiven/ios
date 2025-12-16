import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:auto_size_text/auto_size_text.dart';
import 'menu_page.dart';
import 'menu2_page.dart';
import 'login_page.dart';

class MenuIntermedioPage extends StatefulWidget {
  const MenuIntermedioPage({super.key});

  @override
  State<MenuIntermedioPage> createState() => _MenuIntermedioPageState();
}

class _MenuIntermedioPageState extends State<MenuIntermedioPage> {
  int? rol;
  bool cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarRol();
  }

  Future<void> _cargarRol() async {
    final prefs = await SharedPreferences.getInstance();
    final userData = prefs.getString('userData');

    if (userData != null) {
      final decoded = json.decode(userData);
      final rawRol = decoded['rol']?.toString().trim() ?? '';
      final parsedRol = int.tryParse(rawRol.replaceAll(RegExp(r'[^0-9]'), ''));

      setState(() {
        rol = parsedRol;
        cargando = false;
      });
    } else {
      setState(() => cargando = false);
    }
  }

  Future<void> _logout() async {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text(
          "Confirmar",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text("¿Estás seguro de que deseas cerrar sesión?"),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.grey.shade700),
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar"),
          ),

          // 🔥 BOTÓN BLANCO — COMO LO QUIERES 🔥
          TextButton(
            style: TextButton.styleFrom(
              backgroundColor: Colors.white, // 🔹 Fondo BLANCO
              foregroundColor: Colors.red, // 🔹 Texto ROJO
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              Navigator.pop(context);

              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();

              if (!mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginPage()),
                (route) => false,
              );
            },
            child: const Text(
              "Cerrar sesión",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (cargando) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Colors.red)),
      );
    }

    // 🔹 Roles definidos
    final rolesBasicos = [1, 2, 358, 359];
    final rolesSoloInspecciones = [334, 342, 341, 7, 8, 6];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Menú Principal',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.red,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(
              Icons.logout,
              color: Colors.white, // ✔️ SOLO EL BOTÓN EN BLANCO
            ),
            tooltip: "Cerrar sesión",
            onPressed: _logout,
          ),
        ],
      ),

      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.dashboard_customize, color: Colors.red, size: 100),
            const SizedBox(height: 40),

            // 🔸 Si el usuario tiene rol básico → ver un solo botón de "Viajes"
            if (rolesBasicos.contains(rol)) ...[
              _buildBotonMenu(
                context,
                icono: Icons.directions_bus,
                texto: 'Viajes e Inspecciones',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MenuPage()),
                  );
                },
              ),
            ]
            // 🔸 Si el usuario tiene rol de solo inspecciones → otro menú
            else if (rolesSoloInspecciones.contains(rol)) ...[
              _buildBotonMenu(
                context,
                icono: Icons.search,
                texto: 'Inspecciones Generales',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const Menu2Page()),
                  );
                },
              ),
            ]
            // 🔸 Si no tiene rol válido
            else ...[
              const Text(
                "No tienes permisos asignados.",
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBotonMenu(
    BuildContext context, {
    required IconData icono,
    required String texto,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.red.shade200.withOpacity(0.4),
              blurRadius: 8,
              offset: const Offset(2, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icono, color: Colors.white, size: 34),
              const SizedBox(width: 16),

              // 🔹 Texto adaptable
              Expanded(
                child: AutoSizeText(
                  texto,
                  maxLines: 1,
                  minFontSize: 14,
                  maxFontSize: 22,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
