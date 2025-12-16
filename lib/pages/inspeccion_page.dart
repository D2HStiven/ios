import 'package:flutter/material.dart';
import 'package:awesome_dialog/awesome_dialog.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class InspeccionPage extends StatefulWidget {
  final String idViaje;

  const InspeccionPage({super.key, required this.idViaje});

  @override
  State<InspeccionPage> createState() => _InspeccionPageState();
}

class _InspeccionPageState extends State<InspeccionPage> {
  List<Map<String, dynamic>> items = [];
  bool isLoading = true;
  bool isCompleted = false;

  @override
  void initState() {
    super.initState();
    fetchChecklist();
  }

  @override
  void dispose() {
    for (final it in items) {
      final TextEditingController? c = it['controller'];
      c?.dispose();
    }
    super.dispose();
  }

  // ===============================
  // 🔥 ALERTA CENTRAL VISIBLE
  // ===============================
  void showAlert(String title, String message, {bool error = false}) {
    AwesomeDialog(
      context: context,
      dialogType: error ? DialogType.error : DialogType.info,
      animType: AnimType.scale,
      title: title,
      desc: message,
      btnOkOnPress: () {},
      btnOkColor: error ? Colors.red : Colors.blue,
    ).show();
  }

  // ===============================
  // 🔥 Cargar checklist
  // ===============================
  Future<void> fetchChecklist() async {
    setState(() => isLoading = true);

    try {
      final url = Uri.parse(
        'https://serviciosjr.com/controllers/controlador_checklist.php?ope=getByViaje&id_viaje=${widget.idViaje}',
      );
      final response = await http.get(url);

      if (response.statusCode != 200) {
        setState(() => isLoading = false);
        return showAlert(
          "Error",
          "Error HTTP ${response.statusCode}",
          error: true,
        );
      }

      final data = json.decode(response.body);

      if (data["status"] != "ok") {
        setState(() => isLoading = false);
        return showAlert(
          "Error",
          data["mensaje"] ?? "Error al cargar checklist",
          error: true,
        );
      }

      final info = data["data"];
      final rawItems = List.from(info["items"] ?? []);

      items = rawItems.map<Map<String, dynamic>>((raw) {
        final valor =
            raw['valor'] == true ||
            raw['valor'] == 1 ||
            raw['valor'] == '1' ||
            raw['valor'] == 'true';

        final obs = raw['observacion'] ?? '';
        final controller = TextEditingController(text: obs);

        return {
          'id_item': raw['id_item'] ?? raw['id'],
          'nombre': raw['nombre_item'] ?? raw['nombre'] ?? '',
          'valor': valor,
          'observacion': obs,
          'controller': controller,
        };
      }).toList();

      isCompleted = info['completado'] == true || info['completado'] == 1;

      setState(() => isLoading = false);
    } catch (e) {
      setState(() => isLoading = false);
      showAlert("Error", "Ocurrió un error inesperado.\n$e", error: true);
    }
  }

  bool _isChecked(dynamic v) {
    return v == true || v == 1 || v == "1" || v == "true";
  }

  bool validateChecklist() {
    for (final it in items) {
      final valor = _isChecked(it['valor']);
      final obs = (it['controller'].text).trim();

      if (!valor && obs.isEmpty) return false;
    }
    return true;
  }

  // ===============================
  // 🔥 Guardar checklist
  // ===============================
  Future<void> saveChecklist() async {
    if (isCompleted) {
      return showAlert(
        "Inspección bloqueada",
        "Esta inspección ya fue completada y no puede modificarse.",
        error: true,
      );
    }

    if (!validateChecklist()) {
      return showAlert(
        "Faltan datos",
        "Debe llenar las observaciones de los ítems marcados como NO.",
        error: true,
      );
    }

    final respuestas = items.map((it) {
      final valor = _isChecked(it['valor']) ? 1 : 0;
      final obs = it['controller'].text.trim();
      return {'id_item': it['id_item'], 'valor': valor, 'observacion': obs};
    }).toList();

    final url = Uri.parse(
      'https://serviciosjr.com/controllers/controlador_checklist.php?ope=saveResponses&id_viaje=${widget.idViaje}',
    );

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'respuestas': respuestas}),
      );

      final data = json.decode(response.body);

      if (data['status'] != 'ok') {
        return showAlert(
          "Error",
          data['mensaje'] ?? "No se pudo guardar.",
          error: true,
        );
      }

      AwesomeDialog(
        context: context,
        dialogType: DialogType.success,
        animType: AnimType.scale,
        title: "Guardado",
        desc:
            "Inspeccion guardada correctamente.\nEspere confirmación de mantenimiento.",
        btnOkOnPress: () {
          Navigator.pop(context, true);
        },
        btnOkColor: Colors.green,
      ).show();
    } catch (e) {
      showAlert("Error", "No se pudo guardar: $e", error: true);
    }
  }

  // ===============================
  // 🔥 UI PRINCIPAL
  // ===============================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      appBar: AppBar(
        title: const Text("Inspección Pre-operacional"),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
        actions: [
          if (!isCompleted)
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: "Guardar checklist",
              onPressed: saveChecklist,
            ),
        ],
      ),

      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
          ? const Center(child: Text("No hay ítems disponibles"))
          : ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final it = items[index];
                final checked = _isChecked(it['valor']);
                final controller = it['controller'];

                return Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // TÍTULO + SWITCH
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                it['nombre'],
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),

                            // 🔥 SWITCH ESTILIZADO
                            Switch.adaptive(
                              value: checked,
                              activeColor: Colors.red.shade700,
                              onChanged: isCompleted
                                  ? null
                                  : (value) {
                                      setState(() {
                                        it['valor'] = value;
                                        if (value) controller.text = "";
                                      });
                                    },
                            ),
                          ],
                        ),

                        // OBS REQUERIDA
                        if (!checked)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 10),
                              const Text(
                                "Observación requerida:",
                                style: TextStyle(
                                  color: Colors.black87,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: controller,
                                enabled: !isCompleted,
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: Colors.grey.shade100,
                                  labelText: "Explique el motivo",
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                maxLines: null,
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
