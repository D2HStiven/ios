import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'login_page.dart';
import 'horas_page.dart';
import 'inspeccion_page.dart';

class MenuPage extends StatefulWidget {
  const MenuPage({super.key});

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> {
  String? _nombreUsuario;
  String? _fotoUsuario;
  String? _idUsuario;
  bool _cargandoUsuario = true;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final userData = prefs.getString('userData');

    if (userData != null) {
      final data = json.decode(userData);
      setState(() {
        _nombreUsuario = data['nombre'];
        _idUsuario = data['id'].toString();
        _fotoUsuario = null;
        _cargandoUsuario = false;
      });
    } else {
      setState(() => _cargandoUsuario = false);
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('isLoggedIn');
    await prefs.remove('userData');

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  // ================================
  // 🔥 COPIAR HORAS (NUEVO)
  // ================================
  bool _modoCopiar = false;
  String? _viajeActivoCopiar; // placa-recorrido-fecha
  String? _registroOrigen;
  Map<String, bool> _checksCopiar = {};

  /// ================================
  ///   OBTENER VIAJES AGRUPADOS
  /// ================================
  Future<List<dynamic>> _obtenerViajesAgrupados() async {
    if (_idUsuario == null) return [];

    try {
      final response = await http.post(
        Uri.parse('https://serviciosjr.com/controllers/controlador_horas.php'),
        body: {'ope': 'getByUsuario', 'id_usuario': _idUsuario!},
      );

      if (response.statusCode != 200) return [];

      final jsonRes = json.decode(response.body);

      if (jsonRes is! Map || jsonRes['status'] != 'ok') {
        return [];
      }

      final List registros = List.from(jsonRes['data'] ?? []);

      if (registros.isEmpty) return [];

      Map<String, Map<String, dynamic>> viajesAgrupados = {};

      // Helper: extrae el valor de "cierre" intentando varias claves y búsqueda en estructuras anidadas.
      dynamic _buscarCierreEnRegistro(Map reg) {
        // claves candidate
        final keysToTry = [
          'cierre',
          'Cierre',
          'cerrado',
          'cerrado_flag',
          'close',
          'closed',
          'estado_cierre',
        ];

        for (var k in keysToTry) {
          if (reg.containsKey(k)) return reg[k];
        }

        // si no está en la raíz, buscar en submaps
        for (var v in reg.values) {
          if (v is Map) {
            for (var k in keysToTry) {
              if (v.containsKey(k)) return v[k];
            }
          }
        }

        // busqueda basada en nombre aproximado (contiene 'cier' o 'cerr')
        for (var entry in reg.entries) {
          final k = entry.key.toString().toLowerCase();
          if (k.contains('cier') || k.contains('cerr')) return entry.value;
        }

        return null;
      }

      bool _esCierre(dynamic valor) {
        if (valor == null) return false;

        // si es Map o List, intentar buscar dentro
        if (valor is Map) {
          // buscar claves en el mapa
          for (var candidate in ['cierre', 'cerrado', 'closed']) {
            if (valor.containsKey(candidate)) {
              return _esCierre(valor[candidate]);
            }
          }
          return false;
        }

        if (valor is List) {
          // si es lista, comprobar si alguno de sus elementos indica cierre
          for (var it in valor) {
            if (_esCierre(it)) return true;
          }
          return false;
        }

        // normalizar a string (trim, lowercase)
        final s = valor.toString().trim().toLowerCase();

        if (s.isEmpty) return false;

        // Common true values
        final trueSet = {
          '1',
          '1.0',
          'true',
          't',
          'si',
          'sí',
          's',
          'y',
          'yes',
          'verdadero',
          'v',
        };

        // permitir también "1\r", "1\n", etc. ya cubierto por trim()
        if (trueSet.contains(s)) return true;

        // si es un número parseable
        try {
          final d = double.parse(s);
          if (d == 1.0) return true;
        } catch (_) {}

        return false;
      }

      // debug: imprime los primeros 6 registros (tipo, clave y cierre detectado)
      int sampleToLog = registros.length > 6 ? 6 : registros.length;
      for (int i = 0; i < sampleToLog; i++) {
        final reg = registros[i];
        try {
          final cierreDetectado = _buscarCierreEnRegistro(reg as Map);
          debugPrint(
            '[DEBUG-registro sample #$i] id_registro=${reg['id_registro'] ?? 'N/A'} | cierreRaw=${cierreDetectado} (type=${cierreDetectado?.runtimeType}) | wholeReg=${reg}',
          );
        } catch (e) {
          debugPrint(
            '[DEBUG-registro sample #$i] Error al imprimir registro: $e',
          );
        }
      }

      // Función que obtiene un valor de cierre definitivamente (tratando anidamientos)
      bool _registroTieneCierre(Map reg) {
        final cand = _buscarCierreEnRegistro(reg);
        final res = _esCierre(cand);
        // imprimir por cada registro para depuración (puedes comentar si se llena el log)
        debugPrint(
          '[DEBUG-cierre check] id_registro=${reg['id_registro'] ?? 'N/A'} -> cierreRaw=${cand} (type=${cand?.runtimeType}) -> esCierre=$res',
        );
        return res;
      }

      // helper para parsear id_registro robusto
      int _toIntId(dynamic idReg) {
        try {
          if (idReg is int) return idReg;
          return int.parse(idReg.toString().trim());
        } catch (_) {
          return 1 << 30;
        }
      }

      for (var reg in registros) {
        final mapaReg = reg as Map;
        final placa = mapaReg['placa'] ?? '';
        final recorrido = mapaReg['recorrido'] ?? '';
        final fecha = mapaReg['fecha'] ?? '';
        final key = "$placa-$recorrido-$fecha";

        if (!viajesAgrupados.containsKey(key)) {
          viajesAgrupados[key] = {
            'placa': placa,
            'recorrido': recorrido,
            'fecha': fecha,
            'puntos': <dynamic>[],
            'fbe': 0,
            'tieneCierre': false,
            'nombre_autoriza': mapaReg['nombre_autoriza'] ?? null,
          };
        }

        viajesAgrupados[key]!['puntos'].add(mapaReg);

        // acá usamos la nueva detección robusta:
        if (_registroTieneCierre(mapaReg)) {
          viajesAgrupados[key]!['tieneCierre'] = true;
        }
      }

      List<Map<String, dynamic>> resultado = [];
      int excluidos = 0;

      for (var entry in viajesAgrupados.entries) {
        final key = entry.key;
        final v = entry.value;

        if (v['tieneCierre'] == true) {
          excluidos++;
          debugPrint(
            '[obtenerViajes] Excluyendo grupo por cierre: $key (puntos=${(v['puntos'] as List).length})',
          );
          continue;
        }

        (v['puntos'] as List).sort((a, b) {
          final ai = _toIntId(a['id_registro']);
          final bi = _toIntId(b['id_registro']);
          return ai.compareTo(bi);
        });

        if ((v['puntos'] as List).isNotEmpty) {
          v['fbe'] = v['puntos'][0]['fbe'];
        }

        resultado.add(v);
      }

      debugPrint(
        '[obtenerViajes] total grupos: ${viajesAgrupados.length}, excluidos por cierre: $excluidos, retornando: ${resultado.length}',
      );

      return resultado;
    } catch (e, st) {
      debugPrint('Error en _obtenerViajesAgrupados: $e\n$st');
      return [];
    }
  }

  /// ================================
  ///   VERIFICAR INSPECCIÓN
  /// ================================
  Future<bool> _verificarChecklist(String idViaje) async {
    try {
      final url = Uri.parse(
        'https://serviciosjr.com/controllers/controlador_checklist.php'
        '?ope=isCompleted&id_viaje=$idViaje',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final jsonRes = jsonDecode(response.body);
        if (jsonRes['status'] == 'ok') {
          return jsonRes['completado'] == true;
        }
      }
    } catch (_) {}

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final rojoJR = const Color.fromARGB(255, 255, 34, 34);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Mis Viajes"),
        backgroundColor: rojoJR,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: _cargandoUsuario
          ? const Center(child: CircularProgressIndicator())
          : _idUsuario == null
          ? const Center(child: Text("No se encontró el usuario."))
          : Padding(
              padding: const EdgeInsets.all(16),
              child: FutureBuilder<List<dynamic>>(
                future: _obtenerViajesAgrupados(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final viajes = snapshot.data!;

                  if (viajes.isEmpty) {
                    return const Center(
                      child: Text('No tienes viajes asignados.'),
                    );
                  }

                  return ListView.builder(
                    itemCount: viajes.length,
                    itemBuilder: (context, index) {
                      final viaje = viajes[index];
                      final idViaje = "${viaje['placa']}-${viaje['fecha']}";

                      return FutureBuilder<bool>(
                        future: _verificarChecklist(idViaje),
                        builder: (context, snap) {
                          final inspeccionCompleta = snap.data == true;

                          final puntos = viaje['puntos'] as List;

                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            elevation: 4,
                            shadowColor: Colors.red.withOpacity(0.3),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // HEADER DEL VIAJE
                                Container(
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.red.shade700,
                                        Colors.red.shade400,
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(18),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.local_shipping,
                                        color: Colors.white,
                                        size: 28,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          "Placa ${viaje['placa']} — "
                                          "Recorrido ${viaje['recorrido']} — "
                                          "Fecha ${viaje['fecha']} — "
                                          "Total FBE ${viaje['fbe']}",
                                          style: const TextStyle(
                                            fontSize: 19,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 10),

                                // ESTADO INSPECCIÓN
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                inspeccionCompleta
                                                    ? Icons.check_circle
                                                    : Icons.warning_amber,
                                                color: inspeccionCompleta
                                                    ? Colors.green
                                                    : Colors.orange,
                                                size: 22,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                inspeccionCompleta
                                                    ? "Inspección completada"
                                                    : "Inspección pendiente",
                                                style: TextStyle(
                                                  color: inspeccionCompleta
                                                      ? Colors.green
                                                      : Colors.orange,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          // Aquí mostramos el dato adicional, por ejemplo 'autorizado_por'
                                        ],
                                      ),

                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: inspeccionCompleta
                                              ? Colors.grey
                                              : Colors.red,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 18,
                                            vertical: 10,
                                          ),
                                        ),
                                        onPressed: inspeccionCompleta
                                            ? null
                                            : () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        InspeccionPage(
                                                          idViaje: idViaje,
                                                        ),
                                                  ),
                                                );
                                              },
                                        child: Text(
                                          inspeccionCompleta
                                              ? "Completada"
                                              : "Realizar",
                                          style: const TextStyle(fontSize: 15),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 14),
                                const Divider(indent: 16, endIndent: 16),

                                // LISTA DE PUNTOS
                                const Padding(
                                  padding: EdgeInsets.only(left: 20, bottom: 8),
                                  child: Text(
                                    "Puntos del recorrido",
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),

                                ...List.generate(puntos.length, (i) {
                                  final punto = puntos[i];

                                  final idActual = punto['id_registro']
                                      .toString();
                                  final esOrigen = idActual == _registroOrigen;

                                  final origen = puntos.firstWhere(
                                    (p) =>
                                        p['id_registro'].toString() ==
                                        _registroOrigen,
                                    orElse: () => null,
                                  );

                                  final puntoOrigen = origen != null
                                      ? origen['punto']?.toString().trim()
                                      : null;

                                  final puntoActual = punto['punto']
                                      ?.toString()
                                      .trim();

                                  final esCompatible =
                                      !_modoCopiar ||
                                      puntoOrigen == null ||
                                      puntoOrigen == puntoActual;

                                  // 🔥 Nueva lógica:
                                  // Solo se habilitan si la inspección está completa
                                  final habilitado = inspeccionCompleta == true;

                                  return Container(
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: habilitado
                                          ? Colors.white
                                          : Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: habilitado
                                            ? Colors.red.shade300
                                            : Colors.grey.shade400,
                                      ),
                                    ),
                                    child: ListTile(
                                      leading: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.copy),
                                            tooltip: 'Copiar horas',
                                            onPressed: habilitado
                                                ? () {
                                                    setState(() {
                                                      _modoCopiar = true;
                                                      _registroOrigen =
                                                          punto['id_registro']
                                                              .toString();
                                                      _viajeActivoCopiar =
                                                          "${viaje['placa']}-${viaje['recorrido']}-${viaje['fecha']}";
                                                      _checksCopiar.clear();
                                                    });

                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      const SnackBar(
                                                        content: Text(
                                                          'Selecciona los puntos del mismo viaje',
                                                        ),
                                                      ),
                                                    );
                                                  }
                                                : null,
                                          ),

                                          if (_modoCopiar &&
                                              _viajeActivoCopiar ==
                                                  "${viaje['placa']}-${viaje['recorrido']}-${viaje['fecha']}")
                                            Checkbox(
                                              value:
                                                  _checksCopiar[idActual] ??
                                                  false,
                                              onChanged:
                                                  (!esCompatible || esOrigen)
                                                  ? null
                                                  : (v) {
                                                      setState(() {
                                                        _checksCopiar[idActual] =
                                                            v ?? false;
                                                      });
                                                    },
                                            ),

                                          Icon(
                                            Icons.flag,
                                            color: habilitado
                                                ? Colors.red
                                                : Colors.grey,
                                          ),
                                        ],
                                      ),

                                      title: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            "${punto['punto']}",
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: habilitado
                                                  ? Colors.black
                                                  : Colors.grey.shade600,
                                            ),
                                          ),

                                          // 🔥 Mostrar solo si el tipo = DEVOLUCION
                                          if (punto['tipo'] == "DEVOLUCION")
                                            Text(
                                              "DEVOLUCIÓN",
                                              style: TextStyle(
                                                color: Colors.red,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 18,
                                              ),
                                            ),
                                        ],
                                      ),

                                      subtitle: Text(
                                        habilitado ? "Disponible" : "Bloqueado",
                                        style: TextStyle(
                                          color: habilitado
                                              ? Colors.green
                                              : Colors.red,
                                        ),
                                      ),
                                      trailing: Icon(
                                        Icons.arrow_forward_ios,
                                        color: habilitado
                                            ? Colors.black
                                            : Colors.grey,
                                        size: 18,
                                      ),
                                      onTap: habilitado
                                          ? () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) => HorasPage(
                                                    idRegistro:
                                                        punto['id_registro']
                                                            .toString(),
                                                  ),
                                                ),
                                              );
                                            }
                                          : null,
                                    ),
                                  );
                                }),
                                if (_modoCopiar &&
                                    _viajeActivoCopiar ==
                                        "${viaje['placa']}-${viaje['recorrido']}-${viaje['fecha']}")
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: OutlinedButton.icon(
                                      icon: const Icon(
                                        Icons.cancel,
                                        color: Colors.red,
                                      ),
                                      label: const Text(
                                        "Cancelar copiado",
                                        style: TextStyle(color: Colors.red),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(
                                          color: Colors.red,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _modoCopiar = false;
                                          _registroOrigen = null;
                                          _viajeActivoCopiar = null;
                                          _checksCopiar.clear();
                                        });
                                      },
                                    ),
                                  ),

                                if (_modoCopiar &&
                                    _viajeActivoCopiar ==
                                        "${viaje['placa']}-${viaje['recorrido']}-${viaje['fecha']}")
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    child: ElevatedButton.icon(
                                      icon: const Icon(Icons.content_copy),
                                      label: const Text(
                                        "Copiar horas a seleccionados",
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                      ),
                                      onPressed: () async {
                                        final destinos = _checksCopiar.entries
                                            .where((e) => e.value)
                                            .map((e) => e.key)
                                            .toList();

                                        if (destinos.isEmpty ||
                                            _registroOrigen == null)
                                          return;

                                        final confirmar = await showDialog<bool>(
                                          context: context,
                                          builder: (_) => AlertDialog(
                                            title: const Text(
                                              "Confirmar copiado",
                                            ),
                                            content: Text(
                                              "Se copiarán las horas del punto origen "
                                              "a ${destinos.length} punto(s).\n\n¿Deseas continuar?",
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(
                                                  context,
                                                  false,
                                                ),
                                                child: const Text("Cancelar"),
                                              ),
                                              ElevatedButton(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.red,
                                                ),
                                                onPressed: () => Navigator.pop(
                                                  context,
                                                  true,
                                                ),
                                                child: const Text("Confirmar"),
                                              ),
                                            ],
                                          ),
                                        );

                                        if (confirmar != true) return;

                                        await http.post(
                                          Uri.parse(
                                            'https://serviciosjr.com/controllers/controlador_horas.php',
                                          ),
                                          body: {
                                            'ope': 'copiarHoras',
                                            'origen': _registroOrigen!,
                                            'destinos': jsonEncode(destinos),
                                          },
                                        );

                                        setState(() {
                                          _modoCopiar = false;
                                          _registroOrigen = null;
                                          _viajeActivoCopiar = null;
                                          _checksCopiar.clear();
                                        });

                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Horas copiadas correctamente',
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),

                                const SizedBox(height: 14),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
    );
  }
}
