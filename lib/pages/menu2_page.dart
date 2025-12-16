import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import 'inspeccion_general_page.dart';

class Menu2Page extends StatefulWidget {
  const Menu2Page({super.key});

  @override
  State<Menu2Page> createState() => _Menu2PageState();
}

class _Menu2PageState extends State<Menu2Page> {
  List<dynamic> viajesAgrupados = [];
  bool cargando = true;

  String? idUsuarioLogueado; // Aquí guardaremos el id del usuario logueado

  @override
  void initState() {
    super.initState();
    cargarUsuarioLogueado(); // Carga usuario primero
    cargarViajes();
  }

  Future<void> cargarUsuarioLogueado() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('userData');
    if (userDataString != null) {
      final userData = jsonDecode(userDataString);
      setState(() {
        idUsuarioLogueado = userData['id']
            ?.toString(); // Ajusta la clave si es diferente en tu JSON
      });
    }
  }

  Future<void> cargarViajes() async {
    try {
      final url = Uri.parse(
        "https://serviciosjr.com/controllers/controlador_horas.php",
      );

      final response = await http.post(url, body: {"ope": "all"});
      final data = json.decode(response.body);

      if (data["status"] != "ok") {
        setState(() => cargando = false);
        return;
      }

      final registros = data["data"] ?? [];

      // Agrupar viajes por placa + recorrido + fecha
      Map<String, List<dynamic>> grupos = {};

      for (var r in registros) {
        final placa = r["placa"];
        final fecha = r["fecha"];
        final key = "$placa-$fecha";

        if (!grupos.containsKey(key)) {
          grupos[key] = [];
        }
        grupos[key]!.add(r);
      }

      // Convertir cada grupo a un viaje
      List<dynamic> viajes = [];

      grupos.forEach((key, listaPuntos) {
        final primero = listaPuntos.first;

        viajes.add({
          "placa": primero["placa"],
          "recorrido": primero["recorrido"],
          "nomope": primero["nomope"],
          "fecha": primero["fecha"],
          "nombre_conductor": primero["nombre_conductor"],
          "nombre_auxiliar": primero["nombre_auxiliar"],
          "nombre_autoriza":
              primero["nombre_autoriza"], // Nuevo campo autorizado_por
          "id_viaje": "${primero["placa"]}-${primero["fecha"]}",
        });
      });

      setState(() {
        viajesAgrupados = viajes;
        cargando = false;
      });
    } catch (e) {
      print("Error cargando viajes: $e");
      setState(() => cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rojo = Colors.red.shade700;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: rojo,
        centerTitle: true,
        title: const Text(
          "Panel de Mantenimiento",
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: cargando
          ? const Center(child: CircularProgressIndicator())
          : viajesAgrupados.isEmpty
          ? const Center(
              child: Text(
                "No hay viajes registrados",
                style: TextStyle(fontSize: 18, color: Colors.black54),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: viajesAgrupados.length,
              itemBuilder: (context, index) {
                final v = viajesAgrupados[index];

                return Card(
                  elevation: 3,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),

                    // Título: Viaje PLACA — Recorrido X
                    title: Text(
                      "Viaje ${v["placa"]} — Fecha ${v["fecha"]}",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: rojo,
                        fontSize: 18,
                      ),
                    ),

                    subtitle: Text(
                      "Operario: ${v["nomope"]}\n"
                      "Conductor: ${v["nombre_conductor"] ?? "-"}\n"
                      "Auxiliar: ${v["nombre_auxiliar"] ?? "-"}\n"
                      "Autorizó: ${v["nombre_autoriza"] ?? "Pendiente"}",
                      style: const TextStyle(fontSize: 14),
                    ),

                    trailing: const Icon(Icons.arrow_forward_ios),

                    onTap: () {
                      if (idUsuarioLogueado == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Usuario no identificado"),
                          ),
                        );
                        return;
                      }

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => InspeccionGeneralPage(
                            idViaje: v["id_viaje"].toString(),
                            idUsuario:
                                idUsuarioLogueado!, // Aquí pasamos el usuario logueado
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
