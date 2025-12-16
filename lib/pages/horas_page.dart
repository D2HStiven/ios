import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_datetime_picker_plus/flutter_datetime_picker_plus.dart'
    as picker;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Registro de Horas',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
        useMaterial3: true,
      ),
      home: const HorasPage(),
    );
  }
}

class HorasPage extends StatefulWidget {
  final String? idRegistro;
  const HorasPage({super.key, this.idRegistro});

  @override
  State<HorasPage> createState() => _HorasPageState();
}

class _HorasPageState extends State<HorasPage> {
  // Controllers
  final TextEditingController arriboCtrl = TextEditingController();
  final TextEditingController ventanillaCtrl = TextEditingController();
  final TextEditingController inicioCtrl = TextEditingController();
  final TextEditingController finCtrl = TextEditingController();
  final TextEditingController salidaCtrl = TextEditingController();

  final TextEditingController tempIniCtrl = TextEditingController();
  final TextEditingController tempFinCtrl = TextEditingController();
  final TextEditingController precintoCtrl = TextEditingController();
  final TextEditingController anotacionesCtrl = TextEditingController();

  // Parsed DateTimes (keep in sync when controllers change)
  DateTime? horaArribo;
  DateTime? horaVentanilla;
  DateTime? horaInicio;
  DateTime? horaFin;
  DateTime? horaSalida;

  // Resumen
  String horaEstimada = '';
  String punto = '';
  String recorrido = '';

  // UI / estado
  bool cargando = false;
  bool enviando = false;
  String mensaje = '';

  // estado icono: "pendiente" / "enviado" / "error"
  String estado = "pendiente";

  // Debounce timer
  Timer? _debounceTimer;

  // SharedPreferences key (per registro or nuevo)
  String get _prefsDraftKey =>
      widget.idRegistro != null ? 'draft_${widget.idRegistro}' : 'draft_nuevo';

  // list of all controllers for easy loop
  late final List<TextEditingController> _allCtrls;

  @override
  void initState() {
    super.initState();

    _allCtrls = [
      arriboCtrl,
      ventanillaCtrl,
      inicioCtrl,
      finCtrl,
      salidaCtrl,
      tempIniCtrl,
      tempFinCtrl,
      precintoCtrl,
      anotacionesCtrl,
    ];

    // If editing, load remote registro first (so we don't overwrite)
    if (widget.idRegistro != null) {
      cargando = true;
      _cargarRegistroExistente(widget.idRegistro!).then((_) {
        setState(() => cargando = false);
        _cargarBorradorLocalThenSetup();
      });
    } else {
      // new registro: load draft and setup listeners
      _cargarBorradorLocalThenSetup();
    }

    // small delay then attempt auto-send if draft exists
    Future.delayed(const Duration(milliseconds: 350), () {
      _attemptAutoSendIfNeeded();
    });
  }

  Future<void> _cargarBorradorLocalThenSetup() async {
    await _cargarBorradorLocal();
    _configurarAutoSave();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();

    // remove listeners and dispose controllers
    for (final c in _allCtrls) {
      try {
        c.removeListener(_onAutoChange);
      } catch (_) {}
      c.dispose();
    }
    super.dispose();
  }

  // ---------- Helpers ----------

  String clean(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    if (s.toLowerCase() == 'null') return '';
    return s;
  }

  DateTime? _parseFecha(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  String formatearFechaHora(DateTime fecha) {
    return "${fecha.year.toString().padLeft(4, '0')}-"
        "${fecha.month.toString().padLeft(2, '0')}-"
        "${fecha.day.toString().padLeft(2, '0')} "
        "${fecha.hour.toString().padLeft(2, '0')}:"
        "${fecha.minute.toString().padLeft(2, '0')}:"
        "${fecha.second.toString().padLeft(2, '0')}"; // <--- AHORA TIENE SEGUNDOS
  }

  bool _esMayorOValida(DateTime nueva, DateTime? anterior) {
    if (anterior == null) return true; // si no hay anterior, siempre es válida
    return nueva.isAfter(anterior); // solo permitir MAYOR
  }

  // ---------- Load existing registro from server ----------
  Future<void> _cargarRegistroExistente(String idRegistro) async {
    try {
      final response = await http.post(
        Uri.parse('https://serviciosjr.com/controllers/controlador_horas.php'),
        body: {'ope': 'edi', 'id_registro': idRegistro},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'ok' && data['data'] != null) {
          final registro = data['data'] is List && data['data'].isNotEmpty
              ? data['data'][0]
              : data['data'];

          setState(() {
            horaEstimada = clean(registro['hora_estimada']);
            punto = clean(registro['punto']);
            recorrido = clean(registro['recorrido']);

            arriboCtrl.text = clean(registro['hora_arribo']);
            ventanillaCtrl.text = clean(registro['hora_ventanilla']);
            inicioCtrl.text = clean(registro['hora_inicio']);
            finCtrl.text = clean(registro['hora_fin']);
            salidaCtrl.text = clean(registro['hora_salida']);

            tempIniCtrl.text = clean(registro['temperatura_inicial']);
            tempFinCtrl.text = clean(registro['temperatura_final']);
            precintoCtrl.text = clean(registro['precinto']);
            anotacionesCtrl.text = clean(registro['anotaciones']);

            // parse datetimes to keep "anterior" comparisons correct
            horaArribo = _parseFecha(arriboCtrl.text);
            horaVentanilla = _parseFecha(ventanillaCtrl.text);
            horaInicio = _parseFecha(inicioCtrl.text);
            horaFin = _parseFecha(finCtrl.text);
            horaSalida = _parseFecha(salidaCtrl.text);
          });
        }
      }
    } catch (e) {
      debugPrint('Error al cargar registro: $e');
      // ignore network error here; draft may still be loaded
    }
  }

  bool _validarSecuenciaCompleta(DateTime nueva, List<DateTime?> anteriores) {
    for (final h in anteriores) {
      if (h == null) continue;
      if (!nueva.isAfter(h))
        return false; // debe ser MAYOR estricta a todas las anteriores
    }
    return true;
  }

  // ---------- Date selection with corrected validation ----------
  Future<void> _seleccionarHora(
    TextEditingController controller,
    void Function(DateTime) setHora,
    DateTime? horaAnterior,
    String nombreCampo,
  ) async {
    // valor original para detectar si no hubo cambio
    final String textoOriginal = controller.text;

    DateTime ahora = DateTime.now();
    DateTime min = ahora.subtract(const Duration(days: 1));
    DateTime max = ahora.add(const Duration(hours: 1));

    picker.DatePicker.showDateTimePicker(
      context,
      showTitleActions: true,
      minTime: min,
      maxTime: max,
      theme: picker.DatePickerTheme(
        headerColor: Colors.red,
        backgroundColor: Colors.white,
        itemStyle: const TextStyle(color: Colors.black, fontSize: 18),
        doneStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
      onConfirm: (DateTime seleccionada) {
        final nuevaFormateada = formatearFechaHora(seleccionada);

        // Si seleccionó el mismo valor → no validamos
        if (nuevaFormateada == textoOriginal) {
          final parsed = _parseFecha(textoOriginal);
          if (controller == arriboCtrl) horaArribo = parsed;
          if (controller == ventanillaCtrl) horaVentanilla = parsed;
          if (controller == inicioCtrl) horaInicio = parsed;
          if (controller == finCtrl) horaFin = parsed;
          if (controller == salidaCtrl) horaSalida = parsed;
          return;
        }

        // ---- VALIDACIÓN COMPLETA ----
        // Crear lista de TODAS las anteriores
        List<DateTime?> anteriores = [
          horaArribo,
          horaVentanilla,
          horaInicio,
          horaFin,
        ];

        // Recortar según campo actual
        if (controller == arriboCtrl) {
          anteriores = [];
        } else if (controller == ventanillaCtrl) {
          anteriores = [horaArribo];
        } else if (controller == inicioCtrl) {
          anteriores = [horaArribo, horaVentanilla];
        } else if (controller == finCtrl) {
          anteriores = [horaArribo, horaVentanilla, horaInicio];
        } else if (controller == salidaCtrl) {
          anteriores = [horaArribo, horaVentanilla, horaInicio, horaFin];
        }

        // Validación estricta
        if (!_validarSecuenciaCompleta(seleccionada, anteriores)) {
          _mostrarError(
            "$nombreCampo debe ser MAYOR que todas las horas anteriores registradas (no puede ser igual).",
          );
          return;
        }

        // ---- SI TODO ESTÁ BIEN ----
        setState(() {
          controller.text = nuevaFormateada;
          setHora(seleccionada);
        });

        _guardarBorradorLocal();
        _scheduleAutoSend();
      },
      currentTime: ahora,
      locale: picker.LocaleType.es,
    );
  }

  void _mostrarError(String texto) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Hora inválida", style: TextStyle(color: Colors.red)),
        content: Text(texto),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text("Entendido"),
          ),
        ],
      ),
    );
  }

  // ---------- Auto-save local ----------
  Future<void> _guardarBorradorLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final Map<String, String> data = {
        'hora_arribo': arriboCtrl.text,
        'hora_ventanilla': ventanillaCtrl.text,
        'hora_inicio': inicioCtrl.text,
        'hora_fin': finCtrl.text,
        'hora_salida': salidaCtrl.text,
        'temperatura_inicial': tempIniCtrl.text,
        'temperatura_final': tempFinCtrl.text,
        'precinto': precintoCtrl.text,
        'anotaciones': anotacionesCtrl.text,
      };
      await prefs.setString(_prefsDraftKey, jsonEncode(data));
      setState(() => estado = "pendiente");
    } catch (e) {
      debugPrint('Error guardando borrador local: $e');
    }
  }

  Future<void> _cargarBorradorLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!prefs.containsKey(_prefsDraftKey)) return;

      final raw = prefs.getString(_prefsDraftKey);
      if (raw == null || raw.isEmpty) return;

      final Map<String, dynamic> data = jsonDecode(raw);

      // Fill controllers only if they are empty (don't overwrite server-loaded values)
      if (arriboCtrl.text.isEmpty) arriboCtrl.text = clean(data['hora_arribo']);
      if (ventanillaCtrl.text.isEmpty)
        ventanillaCtrl.text = clean(data['hora_ventanilla']);
      if (inicioCtrl.text.isEmpty) inicioCtrl.text = clean(data['hora_inicio']);
      if (finCtrl.text.isEmpty) finCtrl.text = clean(data['hora_fin']);
      if (salidaCtrl.text.isEmpty) salidaCtrl.text = clean(data['hora_salida']);

      if (tempIniCtrl.text.isEmpty)
        tempIniCtrl.text = clean(data['temperatura_inicial']);
      if (tempFinCtrl.text.isEmpty)
        tempFinCtrl.text = clean(data['temperatura_final']);
      if (precintoCtrl.text.isEmpty)
        precintoCtrl.text = clean(data['precinto']);
      if (anotacionesCtrl.text.isEmpty)
        anotacionesCtrl.text = clean(data['anotaciones']);

      // also parse date-times into variables so comparisons work if user opens without editing
      horaArribo = _parseFecha(arriboCtrl.text);
      horaVentanilla = _parseFecha(ventanillaCtrl.text);
      horaInicio = _parseFecha(inicioCtrl.text);
      horaFin = _parseFecha(finCtrl.text);
      horaSalida = _parseFecha(salidaCtrl.text);
    } catch (e) {
      debugPrint('Error cargando borrador local: $e');
    }
  }

  Future<void> _borrarBorradorLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsDraftKey);
    } catch (e) {
      debugPrint('Error borrando borrador local: $e');
    }
  }

  // ---------- Auto-save & auto-send listeners ----------
  void _configurarAutoSave() {
    // Ensure listeners are not duplicated
    for (final c in _allCtrls) {
      try {
        c.removeListener(_onAutoChange);
      } catch (_) {}
      c.addListener(_onAutoChange);
    }
  }

  void _onAutoChange() {
    // Keep DateTime parsed values in sync for fields when text changes manually (rare for readOnly ones)
    horaArribo = _parseFecha(arriboCtrl.text);
    horaVentanilla = _parseFecha(ventanillaCtrl.text);
    horaInicio = _parseFecha(inicioCtrl.text);
    horaFin = _parseFecha(finCtrl.text);
    horaSalida = _parseFecha(salidaCtrl.text);

    // Save draft locally immediately
    _guardarBorradorLocal();

    // schedule auto-send
    _scheduleAutoSend();
  }

  void _scheduleAutoSend({int ms = 1500}) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(Duration(milliseconds: ms), () {
      enviarRegistro(auto: true);
    });
  }

  void _attemptAutoSendIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!prefs.containsKey(_prefsDraftKey)) return;

      final raw = prefs.getString(_prefsDraftKey);
      if (raw == null || raw.isEmpty) return;

      final Map<String, dynamic> draft = jsonDecode(raw);
      final allEmpty = draft.values.every(
        (v) => v == null || v.toString().trim().isEmpty,
      );
      if (allEmpty) return;

      // Try to send
      enviarRegistro(auto: true);
    } catch (e) {
      debugPrint('Error intentando auto-send al iniciar: $e');
    }
  }

  // ---------- Send to server ----------
  Future<void> enviarRegistro({bool auto = false}) async {
    if (enviando) return;
    enviando = true;
    setState(
      () => mensaje = auto ? "Guardando automáticamente..." : "Enviando...",
    );

    final url = Uri.parse(
      'https://serviciosjr.com/controllers/controlador_horas.php',
    );

    try {
      final response = await http.post(
        url,
        body: {
          'ope': 'save',
          'id_registro': widget.idRegistro ?? '',
          'hora_arribo': arriboCtrl.text,
          'hora_ventanilla': ventanillaCtrl.text,
          'hora_inicio': inicioCtrl.text,
          'hora_fin': finCtrl.text,
          'hora_salida': salidaCtrl.text,
          'temperatura_inicial': tempIniCtrl.text,
          'temperatura_final': tempFinCtrl.text,
          'precinto': precintoCtrl.text,
          'anotaciones': anotacionesCtrl.text,
        },
      );

      enviando = false;

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body);
          final serverMessage = data['mensaje'] ?? 'Guardado';
          setState(() => mensaje = serverMessage.toString());
        } catch (_) {
          setState(() => mensaje = 'Guardado correctamente');
        }
        // Clear local draft on success
        await _borrarBorradorLocal();
        setState(() => estado = "enviado");
      } else {
        setState(
          () => mensaje =
              'No se pudo guardar en servidor (status ${response.statusCode}). Guardado localmente.',
        );
        setState(() => estado = "error");
      }
    } catch (e) {
      enviando = false;
      setState(
        () => mensaje = 'Sin conexión: los datos están guardados localmente.',
      );
      setState(() => estado = "error");
      debugPrint('Error al enviar registro: $e');
    }
  }

  // ---------- UI ----------

  Icon _iconoEstado() {
    switch (estado) {
      case "enviado":
        return const Icon(Icons.check_circle, color: Colors.green);
      case "error":
        return const Icon(Icons.error, color: Colors.red);
      default:
        return const Icon(Icons.sync, color: Colors.orange);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.idRegistro != null
              ? 'Editar Registro #${widget.idRegistro}'
              : 'Nuevo Registro',
        ),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Tooltip(
              message: estado == "enviado"
                  ? "Enviado"
                  : estado == "error"
                  ? "Error al enviar"
                  : "Pendiente de envío",
              child: _iconoEstado(),
            ),
          ),
        ],
      ),
      body: cargando
          ? const Center(child: CircularProgressIndicator(color: Colors.red))
          : Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // --- RESUMEN DE LA OPERACIÓN ---
                    Card(
                      color: Colors.red.shade50,
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Resumen de la operación',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _buildResumenItem('Hora estimada', horaEstimada),
                            _buildResumenItem('Punto', punto),
                            _buildResumenItem('Recorrido', recorrido),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    _buildCampoHora(
                      'Hora de arribo',
                      arriboCtrl,
                      (v) => horaArribo = v,
                      null, // <--- SIN VALIDACIÓN
                    ),

                    _buildCampoHora(
                      'Hora en ventanilla',
                      ventanillaCtrl,
                      (v) => horaVentanilla = v,
                      horaArribo,
                    ),

                    _buildCampoHora(
                      'Hora de inicio',
                      inicioCtrl,
                      (v) => horaInicio = v,
                      horaVentanilla,
                    ),

                    _buildCampoHora(
                      'Hora de fin',
                      finCtrl,
                      (v) => horaFin = v,
                      horaInicio,
                    ),

                    _buildCampoHora(
                      'Hora de salida',
                      salidaCtrl,
                      (v) => horaSalida = v,
                      horaFin,
                    ),

                    const SizedBox(height: 20),
                    _buildCampoNumero('Temperatura inicial (°C)', tempIniCtrl),
                    _buildCampoNumero('Temperatura final (°C)', tempFinCtrl),
                    _buildCampoNumero('Precinto', precintoCtrl),
                    _buildCampoTexto('Anotaciones', anotacionesCtrl),

                    const SizedBox(height: 20),
                    // Mensaje de estado debajo de los campos
                    if (mensaje.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          mensaje,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildResumenItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            value.isNotEmpty ? value : '--',
            style: const TextStyle(fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildCampoHora(
    String label,
    TextEditingController controller,
    void Function(DateTime) setHora,
    DateTime? horaAnterior,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            readOnly: true,
            onTap: () =>
                _seleccionarHora(controller, setHora, horaAnterior, label),
            decoration: InputDecoration(
              hintText: 'Seleccionar fecha y hora',
              prefixIcon: const Icon(Icons.access_time),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCampoNumero(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: 'Ingrese $label',
              prefixIcon: const Icon(Icons.edit),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCampoTexto(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Escriba aquí...',
              prefixIcon: const Icon(Icons.notes),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
