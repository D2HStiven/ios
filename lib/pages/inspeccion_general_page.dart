import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:awesome_dialog/awesome_dialog.dart';

class InspeccionGeneralPage extends StatefulWidget {
  final String idViaje;
  final String idUsuario; // 👈 NUEVO

  const InspeccionGeneralPage({
    super.key,
    required this.idViaje,
    required this.idUsuario,
  });

  @override
  State<InspeccionGeneralPage> createState() => _InspeccionGeneralPageState();
}

class _InspeccionGeneralPageState extends State<InspeccionGeneralPage> {
  List<dynamic> items = [];
  bool isLoading = true;

  bool completado = false;
  TextEditingController obsFinalController = TextEditingController();

  @override
  void initState() {
    super.initState();
    fetchChecklistCompleto();
  }

  Future<void> fetchChecklistCompleto() async {
    final url = Uri.parse(
      "https://serviciosjr.com/controllers/controlador_checklist.php?ope=getChecklistFull&id_viaje=${widget.idViaje}",
    );

    try {
      final r = await http.get(url);

      print('Respuesta del servidor fetchChecklistCompleto: ${r.body}');

      final data = jsonDecode(r.body);

      if (data["status"] == "ok") {
        setState(() {
          items = data["data"]["items"] ?? [];
          obsFinalController.text =
              data["data"]["observacion_final"]?.toString() ?? "";
          completado = data["data"]["completado"].toString() == "1";
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
        mostrarMensaje("Error al cargar el checklist");
      }
    } catch (e) {
      setState(() => isLoading = false);
      mostrarMensaje("Error: $e");
    }
  }

  Future<void> saveInspeccionGeneral() async {
    final urlRespuestas = Uri.parse(
      "https://serviciosjr.com/controllers/controlador_checklist.php?ope=saveResponses&id_viaje=${widget.idViaje}",
    );

    final respuestas = items.map((item) {
      return {
        "id_item": item["id_item"].toString(),
        "valor": item["valor"].toString(),
        "observacion": item["observacion"] ?? "",
      };
    }).toList();

    try {
      final r1 = await http.post(
        urlRespuestas,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"respuestas": respuestas}),
      );

      print('Respuesta saveResponses: ${r1.body}');
      final d1 = jsonDecode(r1.body);

      if (d1["status"] != "ok") {
        mostrarMensaje("Error guardando checks");
        return;
      }
    } catch (e) {
      mostrarMensaje("Error guardando checks: $e");
      return;
    }

    final urlFinal = Uri.parse(
      "https://serviciosjr.com/controllers/controlador_checklist.php?ope=saveInspeccionGeneral&id_viaje=${widget.idViaje}",
    );

    try {
      final r2 = await http.post(
        urlFinal,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "observacion_final": obsFinalController.text,
          "completado": completado ? "1" : "0",
          "idusu_autoriza": widget.idUsuario,
        }),
      );

      print('Respuesta saveInspeccionGeneral: ${r2.body}');
      final d2 = jsonDecode(r2.body);
      mostrarMensaje(d2["mensaje"] ?? "Guardado correctamente");
    } catch (e) {
      mostrarMensaje("Error guardando inspección general: $e");
    }
  }

  void mostrarMensaje(String mensaje, {bool success = false}) {
    AwesomeDialog(
      context: context,
      dialogType: success ? DialogType.success : DialogType.error,
      animType: AnimType.scale,
      title: success ? "Éxito" : "Aviso",
      desc: mensaje,
      btnOkOnPress: () {},
      btnOkColor: success ? Colors.green : Colors.red,
    ).show();
  }

  @override
  Widget build(BuildContext context) {
    final rojo = Colors.red.shade700;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: rojo,
        foregroundColor: Colors.white,
        title: const Text("Inspección Viaje"),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: saveInspeccionGeneral,
          ),
        ],
      ),

      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                ...items.map((item) {
                  return Card(
                    elevation: 3,
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item["nombre"] ?? "Item",
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),

                              // ✔ Switch editable por mantenimiento
                              Switch(
                                value: item["valor"].toString() == "1",
                                activeThumbColor: rojo,
                                onChanged: (v) {
                                  setState(() {
                                    item["valor"] = v ? "1" : "0";
                                  });
                                },
                              ),
                            ],
                          ),
                          if (item["observacion"] != null &&
                              item["observacion"].toString().trim().isNotEmpty)
                            Container(
                              padding: const EdgeInsets.all(10),
                              margin: const EdgeInsets.only(top: 6),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                "Obs. Conductor: ${item["observacion"]}",
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }),

                const SizedBox(height: 20),
                TextField(
                  controller: obsFinalController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: "Observación final de Mantenimiento",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),

                const SizedBox(height: 25),
                Row(
                  children: [
                    Transform.scale(
                      scale: 1.6,
                      child: Checkbox(
                        value: completado,
                        onChanged: (v) =>
                            setState(() => completado = v ?? false),
                        activeColor: rojo,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        "Inspección general aprobada",
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
