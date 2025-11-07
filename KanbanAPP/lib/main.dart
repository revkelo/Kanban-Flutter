import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await KanbanNotifier.init(); // inicializar canal de notificaciones
  runApp(const KanbanApp());
}

/* ============================================================
   CONSTANTES DE IDENTIDAD / CUMPLIMIENTO HUAWEI
   ============================================================ */

const String kAppName = 'KanbanAPP'; // nombre EXACTO en AppGallery
const String kDeveloperName = 'Kevin Gonzalez'; // developer EXACTO en AppGallery
const String kAppVersion = '1.0.0'; // versión que declaras en build
const String kContactEmail = 'kgagudelo@gmail.com';

// URL pública de la política de privacidad
const String kPrivacyUrl = 'https://revkelo.github.io/Kanban-Flutter/';

/* ===================== MODELO ===================== */

enum Estado { backlog, progreso, hecho }

String estadoLabel(Estado e) {
  switch (e) {
    case Estado.backlog:
      return 'Backlog';
    case Estado.progreso:
      return 'En progreso';
    case Estado.hecho:
      return 'Hecho';
  }
}

Estado estadoFromString(String s) {
  switch (s) {
    case 'backlog':
      return Estado.backlog;
    case 'progreso':
      return Estado.progreso;
    case 'hecho':
      return Estado.hecho;
    default:
      return Estado.backlog;
  }
}

String estadoToString(Estado e) {
  switch (e) {
    case Estado.backlog:
      return 'backlog';
    case Estado.progreso:
      return 'progreso';
    case Estado.hecho:
      return 'hecho';
  }
}

class Tarea {
  final String id;
  final String titulo;
  final String? descripcion;
  final DateTime? vence;
  final Estado estado;
  final DateTime creada;

  Tarea({
    required this.id,
    required this.titulo,
    this.descripcion,
    this.vence,
    required this.estado,
    required this.creada,
  });

  Tarea copyWith({
    String? id,
    String? titulo,
    String? descripcion,
    DateTime? vence,
    Estado? estado,
    DateTime? creada,
  }) {
    return Tarea(
      id: id ?? this.id,
      titulo: titulo ?? this.titulo,
      descripcion: descripcion ?? this.descripcion,
      vence: vence ?? this.vence,
      estado: estado ?? this.estado,
      creada: creada ?? this.creada,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'titulo': titulo,
    'descripcion': descripcion,
    'vence': vence?.toIso8601String(),
    'estado': estadoToString(estado),
    'creada': creada.toIso8601String(),
  };

  static Tarea fromJson(Map<String, dynamic> j) => Tarea(
    id: j['id'] as String,
    titulo: j['titulo'] as String,
    descripcion: j['descripcion'] as String?,
    vence: (j['vence'] as String?) != null
        ? DateTime.parse(j['vence'])
        : null,
    estado: estadoFromString(j['estado'] as String),
    creada: DateTime.parse(j['creada'] as String),
  );
}

/* ===================== NOTIFICACIONES LOCALES ===================== */

class KanbanNotifier {
  static final FlutterLocalNotificationsPlugin _plugin =
  FlutterLocalNotificationsPlugin();

  // Canal Android
  static const AndroidNotificationChannel _dueChannel =
  AndroidNotificationChannel(
    'kanban_due', // id interno
    'Tareas por vencer', // nombre visible en ajustes
    description: 'Recordatorios de vencimiento de tareas',
    importance: Importance.high,
    playSound: true,
  );

  static Future<void> init() async {
    // Inicialización por plataforma (solo Android en este caso)
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(initSettings);

    // Crear canal Android
    await _plugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_dueChannel);
  }

  /// Revisa todas las tareas. Si alguna vence pronto / está vencida,
  /// dispara una notificación (una sola vez por cada tarea).
  static Future<void> checkAndNotify(
      Map<Estado, List<Tarea>> tablero) async {
    final now = DateTime.now();
    final cutoffSoon = now.add(const Duration(hours: 24));
    final notifiedIds = await KanbanPrefs.getNotifiedIds();

    // Recorremos todas las tareas excepto las que ya están en "hecho"
    for (final estado in [Estado.backlog, Estado.progreso]) {
      final lista = tablero[estado] ?? [];
      for (final t in lista) {
        if (t.vence == null) continue;

        final due = t.vence!;
        final yaVencio = due.isBefore(now);
        final vencePronto = !yaVencio && due.isBefore(cutoffSoon);

        if (!yaVencio && !vencePronto) continue;

        // ¿Ya notificada antes?
        if (notifiedIds.contains(t.id)) continue;

        // Mensaje
        final String tituloNotif;
        final String cuerpoNotif;
        if (yaVencio) {
          tituloNotif = 'Tarea vencida';
          cuerpoNotif =
          '“${t.titulo}” debía hacerse el ${_fmtFechaCorta(due)}.';
        } else {
          // vence hoy o en <24h
          tituloNotif = 'Tarea por vencer';
          cuerpoNotif =
          '“${t.titulo}” vence el ${_fmtFechaCorta(due)}. No la dejes pasar.';
        }

        // ID numérico estable a partir del hash del string
        final int notifId = t.id.hashCode & 0x7fffffff;

        final androidDetails = AndroidNotificationDetails(
          _dueChannel.id,
          _dueChannel.name,
          channelDescription: _dueChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          icon: '@mipmap/ic_launcher',
        );

        final details = NotificationDetails(android: androidDetails);

        await _plugin.show(
          notifId,
          tituloNotif,
          cuerpoNotif,
          details,
        );

        // Guardar que ya notificamos esta tarea
        await KanbanPrefs.addNotifiedId(t.id);
      }
    }
  }
}

/* ===================== PREFERENCIAS LOCALES (AJUSTES & STORAGE) ===================== */

class KanbanPrefs {
  // keys
  static const _storeKeyTareas = 'kanban_v1';
  static const _privacyAcceptedKey = 'privacyAccepted_v1';
  static const _confirmDeleteKey = 'confirmDelete_v1';
  static const _accentColorKey = 'accentColor_v1';

  // nuevo: para evitar notificaciones duplicadas
  static const _notifiedIdsKey = 'kanban_notified_v1';

  // ===== tareas =====
  static Future<Map<Estado, List<Tarea>>> loadBoard() async {
    final sp = await SharedPreferences.getInstance();
    final Map<Estado, List<Tarea>> tablero = {
      Estado.backlog: [],
      Estado.progreso: [],
      Estado.hecho: [],
    };

    final raw = sp.getString(_storeKeyTareas);
    if (raw != null) {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      for (final k in decoded.keys) {
        final estado = estadoFromString(k);
        final lista = (decoded[k] as List)
            .cast<Map>()
            .map((e) => Tarea.fromJson(e.cast<String, dynamic>()))
            .toList();
        tablero[estado] = lista;
      }
    }
    return tablero;
  }

  static Future<void> saveBoard(
      Map<Estado, List<Tarea>> tablero,
      ) async {
    final sp = await SharedPreferences.getInstance();
    final data = <String, dynamic>{
      for (final e in Estado.values)
        estadoToString(e): tablero[e]!.map((t) => t.toJson()).toList(),
    };
    await sp.setString(_storeKeyTareas, jsonEncode(data));
  }

  // ===== ids ya notificados =====
  static Future<Set<String>> getNotifiedIds() async {
    final sp = await SharedPreferences.getInstance();
    final list = sp.getStringList(_notifiedIdsKey) ?? <String>[];
    return list.toSet();
  }

  static Future<void> addNotifiedId(String id) async {
    final sp = await SharedPreferences.getInstance();
    final list = sp.getStringList(_notifiedIdsKey) ?? <String>[];
    if (!list.contains(id)) {
      list.add(id);
      await sp.setStringList(_notifiedIdsKey, list);
    }
  }

  // ===== privacidad =====
  static Future<bool> getPrivacyAccepted() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_privacyAcceptedKey) ?? false;
  }

  static Future<void> setPrivacyAccepted() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_privacyAcceptedKey, true);
  }

  // ===== confirmación de borrado =====
  static Future<bool> getConfirmDelete() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_confirmDeleteKey) ?? true; // default: sí confirmar
  }

  static Future<void> setConfirmDelete(bool v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_confirmDeleteKey, v);
  }

  // ===== color de acento =====
  static Future<String> getAccentColorName() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(_accentColorKey) ?? 'teal';
  }

  static Future<void> setAccentColorName(String name) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_accentColorKey, name);
  }

  static Color seedFromName(String name) {
    switch (name) {
      case 'indigo':
        return Colors.indigo;
      case 'green':
        return Colors.green;
      case 'teal':
      default:
        return Colors.teal;
    }
  }
}

/* ===================== APP ROOT ===================== */

class KanbanApp extends StatefulWidget {
  const KanbanApp({super.key});

  @override
  State<KanbanApp> createState() => _KanbanAppState();
}

class _KanbanAppState extends State<KanbanApp> {
  String _accentName = 'teal';

  @override
  void initState() {
    super.initState();
    _loadAccent();
  }

  Future<void> _loadAccent() async {
    final name = await KanbanPrefs.getAccentColorName();
    if (mounted) {
      setState(() {
        _accentName = name;
      });
    }
  }

  void _updateAccent(String newName) {
    setState(() {
      _accentName = newName;
    });
  }

  @override
  Widget build(BuildContext context) {
    final seed = KanbanPrefs.seedFromName(_accentName);

    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: seed),
      home: MainShell(onThemeChanged: _updateAccent),
    );
  }
}

/* ===================== MAIN SHELL con BottomNav ===================== */

class MainShell extends StatefulWidget {
  final void Function(String newAccentName) onThemeChanged;
  const MainShell({super.key, required this.onThemeChanged});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  late final PageController _pageController;
  late final TabController _tabController;

  Map<Estado, List<Tarea>> _tablero = {
    Estado.backlog: [],
    Estado.progreso: [],
    Estado.hecho: [],
  };

  bool _cargando = true;
  bool _privacyAccepted = false;
  bool _confirmDelete = true;

  SortMode _sortMode = SortMode.creacionAsc;
  String _busqueda = '';

  Timer? _dueTimer; // timer periódico para volver a chequear vencimientos

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _tabController = TabController(length: 3, vsync: this);
    _initLoad();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _tabController.dispose();
    _dueTimer?.cancel();
    super.dispose();
  }

  Future<void> _initLoad() async {
    final board = await KanbanPrefs.loadBoard();
    final accepted = await KanbanPrefs.getPrivacyAccepted();
    final confirmDelete = await KanbanPrefs.getConfirmDelete();

    setState(() {
      _tablero = board;
      _privacyAccepted = accepted;
      _confirmDelete = confirmDelete;
      _cargando = false;
    });

    // Mostrar popup de privacidad si hace falta
    if (!accepted && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _maybeShowPrivacyDialog();
      });
    }

    // Chequear vencimientos inmediatamente
    await KanbanNotifier.checkAndNotify(_tablero);

    // Y luego cada hora mientras la app siga viva en foreground
    _dueTimer = Timer.periodic(const Duration(hours: 1), (_) async {
      await KanbanNotifier.checkAndNotify(_tablero);
    });
  }

  // ========== PRIVACIDAD POPUP ==========
  void _maybeShowPrivacyDialog() {
    if (_privacyAccepted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Política de Privacidad'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$kAppName es desarrollada por $kDeveloperName.\n\n'
                    'Esta app guarda tus tareas (título, descripción opcional, estado y fechas) '
                    'localmente en tu dispositivo. No vendemos tus datos personales.\n\n'
                    'Al continuar, confirmas que has leído y aceptas nuestra Política de Privacidad.',
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final uri = Uri.parse(kPrivacyUrl);

                final canExternal = await canLaunchUrl(uri);
                if (canExternal) {
                  final ok = await launchUrl(
                    uri,
                    mode: LaunchMode.externalApplication,
                  );
                  if (ok) return;
                }

                final okInApp = await launchUrl(
                  uri,
                  mode: LaunchMode.inAppBrowserView,
                );
                if (okInApp) return;

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content:
                      Text('No se pudo abrir la Política de Privacidad.'),
                    ),
                  );
                }
              },
              child: const Text('Ver política'),
            ),
            FilledButton(
              onPressed: () async {
                setState(() {
                  _privacyAccepted = true;
                });
                await KanbanPrefs.setPrivacyAccepted();
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: const Text('He leído y acepto'),
            ),
          ],
        );
      },
    );
  }

  // ========== MUTADORES DEL TABLERO ==========
  void _agregar(Tarea t) {
    setState(() {
      _tablero[t.estado]!.add(t);
    });
    KanbanPrefs.saveBoard(_tablero);
    KanbanNotifier.checkAndNotify(_tablero); // revisar vencimientos
  }

  void _actualizar(Tarea t) {
    setState(() {
      for (final e in Estado.values) {
        final i = _tablero[e]!.indexWhere((x) => x.id == t.id);
        if (i != -1) {
          _tablero[e]!.removeAt(i);
          break;
        }
      }
      _tablero[t.estado]!.add(t);
    });
    KanbanPrefs.saveBoard(_tablero);
    KanbanNotifier.checkAndNotify(_tablero);
  }

  Future<void> _eliminar(Tarea t) async {
    if (_confirmDelete) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Eliminar tarea'),
          content: Text('¿Seguro que quieres eliminar "${t.titulo}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() {
      _tablero[t.estado]!.removeWhere((x) => x.id == t.id);
    });
    KanbanPrefs.saveBoard(_tablero);
    KanbanNotifier.checkAndNotify(_tablero);
  }

  void _moverA(Tarea t, Estado nuevo) {
    if (t.estado == nuevo) return;
    _actualizar(t.copyWith(estado: nuevo));
  }

  // ========== STATS PARA RESUMEN ==========
  ResumenStats _buildStats() {
    final total =
    _tablero.values.fold<int>(0, (acc, list) => acc + list.length);
    final ahora = DateTime.now();

    int vencidas = 0;
    int backlog = 0;
    int progreso = 0;
    int hecho = 0;

    int hechasHoy = 0;
    int hechasSemana = 0;

    for (final tlist in _tablero.values) {
      for (final t in tlist) {
        switch (t.estado) {
          case Estado.backlog:
            backlog++;
            break;
          case Estado.progreso:
            progreso++;
            break;
          case Estado.hecho:
            hecho++;

            if (_esMismoDia(t.creada, ahora)) {
              hechasHoy++;
            }
            if (t.creada.isAfter(ahora.subtract(const Duration(days: 7)))) {
              hechasSemana++;
            }
            break;
        }

        if (t.vence != null && t.vence!.isBefore(ahora)) {
          vencidas++;
        }
      }
    }

    final pctCompletado = total == 0 ? 0.0 : (hecho / total) * 100.0;

    return ResumenStats(
      total: total,
      backlog: backlog,
      progreso: progreso,
      hecho: hecho,
      vencidas: vencidas,
      hechasHoy: hechasHoy,
      hechasSemana: hechasSemana,
      pctCompletado: pctCompletado,
    );
  }

  bool _esMismoDia(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  // ========== NAVEGACIÓN ==========
  void _goTab(int i) {
    setState(() {
      _index = i;
    });
    _pageController.jumpToPage(i);
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }

    final stats = _buildStats();

    return Scaffold(
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          // 0. TABLERO
          TableroScreen(
            tablero: _tablero,
            busqueda: _busqueda,
            sortMode: _sortMode,
            tabController: _tabController,
            onBusqueda: (v) => setState(() => _busqueda = v),
            onSortChange: (m) => setState(() => _sortMode = m),
            onAgregar: _agregar,
            onActualizar: _actualizar,
            onEliminar: _eliminar,
            onMover: _moverA,
          ),

          // 1. RESUMEN
          ResumenScreen(stats: stats),

          // 2. AJUSTES
          AjustesScreen(
            confirmDelete: _confirmDelete,
            onToggleConfirmDelete: (v) async {
              await KanbanPrefs.setConfirmDelete(v);
              setState(() {
                _confirmDelete = v;
              });
            },
            currentAccentNameCallback: () async {
              return await KanbanPrefs.getAccentColorName();
            },
            onAccentSelected: (newName) async {
              await KanbanPrefs.setAccentColorName(newName);
              widget.onThemeChanged(newName);
              setState(() {});
            },
            onOpenPrivacy: () {
              _launchPrivacy(context);
            },
            onOpenInfoApp: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const InfoAppScreen()),
              );
            },
          ),
        ],
      ),

      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _goTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.view_kanban_outlined),
            selectedIcon: Icon(Icons.view_kanban),
            label: 'Tablero',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Resumen',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Ajustes',
          ),
        ],
      ),
    );
  }

  Future<void> _launchPrivacy(BuildContext context) async {
    final uri = Uri.parse(kPrivacyUrl);

    final canExternal = await canLaunchUrl(uri);
    if (canExternal) {
      final ok = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (ok) return;
    }

    final okInApp = await launchUrl(
      uri,
      mode: LaunchMode.inAppBrowserView,
    );
    if (okInApp) return;

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir la Política de Privacidad.'),
        ),
      );
    }
  }
}

/* ===================== TABLERO SCREEN ===================== */

class TableroScreen extends StatelessWidget {
  final Map<Estado, List<Tarea>> tablero;
  final String busqueda;
  final SortMode sortMode;
  final TabController tabController;

  final ValueChanged<String> onBusqueda;
  final ValueChanged<SortMode> onSortChange;

  final void Function(Tarea) onAgregar;
  final void Function(Tarea) onActualizar;
  final Future<void> Function(Tarea) onEliminar;
  final void Function(Tarea, Estado) onMover;

  const TableroScreen({
    super.key,
    required this.tablero,
    required this.busqueda,
    required this.sortMode,
    required this.tabController,
    required this.onBusqueda,
    required this.onSortChange,
    required this.onAgregar,
    required this.onActualizar,
    required this.onEliminar,
    required this.onMover,
  });

  Estado _estadoDeIndex(int i) =>
      [Estado.backlog, Estado.progreso, Estado.hecho][i];

  List<Tarea> _filtrarYOrdenar(
      List<Tarea> src,
      String q,
      SortMode mode,
      ) {
    var out = src.where((t) {
      if (q.isEmpty) return true;
      final lower = q.toLowerCase();
      return t.titulo.toLowerCase().contains(lower) ||
          (t.descripcion ?? '').toLowerCase().contains(lower);
    }).toList();

    int cmp(DateTime a, DateTime b) => a.compareTo(b);

    out.sort((a, b) {
      switch (mode) {
        case SortMode.creacionAsc:
          return cmp(a.creada, b.creada);
        case SortMode.creacionDesc:
          return cmp(b.creada, a.creada);
        case SortMode.venceAsc:
          return (a.vence ?? DateTime(2100))
              .compareTo(b.vence ?? DateTime(2100));
        case SortMode.venceDesc:
          return (b.vence ?? DateTime(1900))
              .compareTo(a.vence ?? DateTime(1900));
        case SortMode.titulo:
          return a.titulo.toLowerCase().compareTo(b.titulo.toLowerCase());
      }
    });

    return out;
  }

  Estado? _siguiente(Estado e) {
    switch (e) {
      case Estado.backlog:
        return Estado.progreso;
      case Estado.progreso:
        return Estado.hecho;
      case Estado.hecho:
        return null;
    }
  }

  Estado? _anterior(Estado e) {
    switch (e) {
      case Estado.backlog:
        return null;
      case Estado.progreso:
        return Estado.backlog;
      case Estado.hecho:
        return Estado.progreso;
    }
  }

  Color _colorColumna(Estado e) {
    switch (e) {
      case Estado.backlog:
        return Colors.teal;
      case Estado.progreso:
        return Colors.indigo;
      case Estado.hecho:
        return Colors.green;
    }
  }

  Future<void> _dialogoNuevaTarea(
      BuildContext context, {
        required Estado estadoInicial,
      }) async {
    final t = await abrirEditorTarea(
      context,
      estadoInicial: estadoInicial,
    );
    if (t != null) onAgregar(t);
  }

  Future<void> _dialogoEditar(
      BuildContext context,
      Tarea t,
      ) async {
    final edit = await abrirEditorTarea(
      context,
      tarea: t,
      estadoInicial: t.estado,
    );
    if (edit != null) onActualizar(edit);
  }

  PopupMenuItem<SortMode> _itemSort(
      BuildContext ctx,
      SortMode mode,
      SortMode current,
      String label,
      ) {
    return PopupMenuItem(
      value: mode,
      child: Row(
        children: [
          if (current == mode) const Icon(Icons.check, size: 18),
          if (current == mode) const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final esMovil = constraints.maxWidth < 700;

        final appBar = AppBar(
          toolbarHeight: 64,
          title: Text(
            kAppName,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          centerTitle: false,
          bottom: PreferredSize(
            preferredSize: Size.fromHeight(esMovil ? 76 : 44),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          onChanged: onBusqueda,
                          decoration: InputDecoration(
                            hintText: 'Buscar…',
                            prefixIcon: const Icon(Icons.search),
                            filled: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      PopupMenuButton<SortMode>(
                        tooltip: 'Ordenar',
                        onSelected: onSortChange,
                        itemBuilder: (ctx) => [
                          _itemSort(
                            ctx,
                            SortMode.creacionAsc,
                            sortMode,
                            'Creación ↑',
                          ),
                          _itemSort(
                            ctx,
                            SortMode.creacionDesc,
                            sortMode,
                            'Creación ↓',
                          ),
                          _itemSort(
                            ctx,
                            SortMode.venceAsc,
                            sortMode,
                            'Vencimiento ↑',
                          ),
                          _itemSort(
                            ctx,
                            SortMode.venceDesc,
                            sortMode,
                            'Vencimiento ↓',
                          ),
                          _itemSort(
                            ctx,
                            SortMode.titulo,
                            sortMode,
                            'Título A→Z',
                          ),
                        ],
                        child: Row(
                          children: [
                            const Icon(Icons.sort),
                            const SizedBox(width: 6),
                            Text(sortMode.label),
                            const SizedBox(width: 6),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (esMovil)
                  SizedBox(
                    height: kTextTabBarHeight,
                    child: TabBar(
                      controller: tabController,
                      tabs: const [
                        Tab(
                          text: 'Backlog',
                          icon: Icon(Icons.inbox_outlined),
                        ),
                        Tab(
                          text: 'En progreso',
                          icon: Icon(Icons.timelapse),
                        ),
                        Tab(
                          text: 'Hecho',
                          icon: Icon(Icons.check_circle_outlined),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );

        final body = esMovil
            ? TabBarView(
          controller: tabController,
          children: Estado.values.map((e) {
            final items = _filtrarYOrdenar(
              tablero[e]!,
              busqueda,
              sortMode,
            );
            final color = _colorColumna(e);
            return _ListaTareas(
              estado: e,
              color: color,
              items: items,
              onEdit: (t) => _dialogoEditar(context, t),
              onDelete: onEliminar,
              onAdvance: (t) {
                final next = _siguiente(e);
                if (next != null) onMover(t, next);
              },
              onBack: (t) {
                final prev = _anterior(e);
                if (prev != null) onMover(t, prev);
              },
              onAddHere: () => _dialogoNuevaTarea(
                context,
                estadoInicial: e,
              ),
            );
          }).toList(),
        )
            : Row(
          children: Estado.values.map((e) {
            final color = _colorColumna(e);
            final items =
            _filtrarYOrdenar(tablero[e]!, busqueda, sortMode);
            return Expanded(
              child: DragTarget<Tarea>(
                onWillAccept: (t) => true,
                onAccept: (t) => onMover(t, e),
                builder: (context, candidates, rejects) {
                  final hovered = candidates.isNotEmpty;
                  return Container(
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                      color: hovered ? color.withOpacity(0.08) : null,
                    ),
                    child: Column(
                      children: [
                        _HeaderColumna(
                          titulo: estadoLabel(e),
                          color: color,
                          count: items.length,
                          onAdd: () => _dialogoNuevaTarea(
                            context,
                            estadoInicial: e,
                          ),
                        ),
                        Expanded(
                          child: items.isEmpty
                              ? _VacioHint(estado: e)
                              : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(
                              12,
                              8,
                              12,
                              100,
                            ),
                            itemCount: items.length,
                            itemBuilder: (context, i) {
                              final t = items[i];
                              return LongPressDraggable<Tarea>(
                                data: t,
                                feedback: _CardTarea(
                                  t: t,
                                  color: color,
                                  dragging: true,
                                ),
                                childWhenDragging: Opacity(
                                  opacity: 0.3,
                                  child: _CardTarea(
                                    t: t,
                                    color: color,
                                  ),
                                ),
                                child: _CardTarea(
                                  t: t,
                                  color: color,
                                  onTap: () =>
                                      _dialogoEditar(context, t),
                                  onDelete: () => onEliminar(t),
                                  onBack: () {
                                    final prev = _anterior(e);
                                    if (prev != null) {
                                      onMover(t, prev);
                                    }
                                  },
                                  onAdvance: () {
                                    final next = _siguiente(e);
                                    if (next != null) {
                                      onMover(t, next);
                                    }
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          }).toList(),
        );

        return Scaffold(
          appBar: appBar,
          body: body,
          floatingActionButton: esMovil
              ? FloatingActionButton.extended(
            onPressed: () => _dialogoNuevaTarea(
              context,
              estadoInicial: _estadoDeIndex(tabController.index),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Nueva'),
          )
              : null,
        );
      },
    );
  }
}

/* ===================== RESUMEN SCREEN ===================== */

class ResumenStats {
  final int total;
  final int backlog;
  final int progreso;
  final int hecho;
  final int vencidas;
  final int hechasHoy;
  final int hechasSemana;
  final double pctCompletado;

  ResumenStats({
    required this.total,
    required this.backlog,
    required this.progreso,
    required this.hecho,
    required this.vencidas,
    required this.hechasHoy,
    required this.hechasSemana,
    required this.pctCompletado,
  });
}

class ResumenScreen extends StatelessWidget {
  final ResumenStats stats;
  const ResumenScreen({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget cardStat({
      required IconData icon,
      required String label,
      required String value,
      Color? color,
    }) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, size: 32, color: color ?? cs.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Resumen de productividad'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Visión general',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Este panel resume tu trabajo reciente en KanbanAPP. '
                  'Te muestra cuántas tareas tienes activas, cuántas terminaste '
                  'y tu nivel de avance.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Wrap(
              runSpacing: 12,
              spacing: 12,
              children: [
                SizedBox(
                  width: 200,
                  child: cardStat(
                    icon: Icons.assessment_outlined,
                    label: 'Total de tareas',
                    value: stats.total.toString(),
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: cardStat(
                    icon: Icons.check_circle_outline,
                    label: 'Completadas',
                    value:
                    '${stats.hecho} (${stats.pctCompletado.toStringAsFixed(0)}%)',
                    color: Colors.green,
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: cardStat(
                    icon: Icons.warning_amber_outlined,
                    label: 'Vencidas',
                    value: stats.vencidas.toString(),
                    color: Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Distribución actual',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    _ChipInfo(
                      icon: Icons.inbox_outlined,
                      label: 'Backlog: ${stats.backlog}',
                    ),
                    _ChipInfo(
                      icon: Icons.timelapse,
                      label: 'En progreso: ${stats.progreso}',
                    ),
                    _ChipInfo(
                      icon: Icons.check_circle_outline,
                      label: 'Hechas: ${stats.hecho}',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Rendimiento reciente',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    _ChipInfo(
                      icon: Icons.today,
                      label: 'Hechas hoy: ${stats.hechasHoy}',
                    ),
                    _ChipInfo(
                      icon: Icons.date_range,
                      label: 'Últimos 7 días: ${stats.hechasSemana}',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Consejo rápido',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              stats.vencidas > 0
                  ? 'Tienes ${stats.vencidas} tarea(s) vencida(s). Te recomendamos priorizar esas primero.'
                  : 'Sin tareas vencidas. Buen ritmo 👍',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/* ===================== AJUSTES SCREEN ===================== */

class AjustesScreen extends StatefulWidget {
  final bool confirmDelete;
  final ValueChanged<bool> onToggleConfirmDelete;

  final Future<String> Function() currentAccentNameCallback;
  final Future<void> Function(String newName) onAccentSelected;

  final VoidCallback onOpenPrivacy;
  final VoidCallback onOpenInfoApp;

  const AjustesScreen({
    super.key,
    required this.confirmDelete,
    required this.onToggleConfirmDelete,
    required this.currentAccentNameCallback,
    required this.onAccentSelected,
    required this.onOpenPrivacy,
    required this.onOpenInfoApp,
  });

  @override
  State<AjustesScreen> createState() => _AjustesScreenState();
}

class _AjustesScreenState extends State<AjustesScreen> {
  String _accentName = 'teal';

  @override
  void initState() {
    super.initState();
    _loadAccentNow();
  }

  Future<void> _loadAccentNow() async {
    final name = await widget.currentAccentNameCallback();
    if (mounted) {
      setState(() {
        _accentName = name;
      });
    }
  }

  Future<void> _changeAccent(String name) async {
    setState(() {
      _accentName = name;
    });
    await widget.onAccentSelected(name);
  }

  @override
  Widget build(BuildContext context) {
    final labelStyle =
    Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustes & Privacidad'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Preferencias de usuario',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Confirmar antes de eliminar tarea'),
              subtitle:
              const Text('Muestra un cuadro de confirmación cuando borras.'),
              value: widget.confirmDelete,
              onChanged: widget.onToggleConfirmDelete,
            ),
            const Divider(),
            ListTile(
              title: Text('Color principal', style: labelStyle),
              subtitle: Text(
                _accentName == 'teal'
                    ? 'Verde azulado'
                    : _accentName == 'indigo'
                    ? 'Índigo'
                    : 'Verde',
              ),
              trailing: DropdownButton<String>(
                value: _accentName,
                items: const [
                  DropdownMenuItem(
                    value: 'teal',
                    child: Text('Teal'),
                  ),
                  DropdownMenuItem(
                    value: 'indigo',
                    child: Text('Indigo'),
                  ),
                  DropdownMenuItem(
                    value: 'green',
                    child: Text('Green'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) _changeAccent(v);
                },
              ),
            ),
            const Divider(),
            const SizedBox(height: 24),
            Text(
              'Información legal y soporte',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Política de Privacidad'),
              subtitle: Text(kPrivacyUrl),
              onTap: widget.onOpenPrivacy,
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Información de la app'),
              subtitle: Text(
                '$kAppName v$kAppVersion\nDesarrollador: $kDeveloperName\nSoporte: $kContactEmail',
              ),
              onTap: widget.onOpenInfoApp,
            ),
          ],
        ),
      ),
    );
  }
}

/* ===================== PANTALLA INFO APP ===================== */

class InfoAppScreen extends StatelessWidget {
  const InfoAppScreen({super.key});

  Future<void> _openPrivacyBestEffort(BuildContext context) async {
    final uri = Uri.parse(kPrivacyUrl);

    final canExternal = await canLaunchUrl(uri);
    if (canExternal) {
      final ok = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (ok) return;
    }

    final okInApp = await launchUrl(
      uri,
      mode: LaunchMode.inAppBrowserView,
    );
    if (okInApp) return;

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir la Política de Privacidad.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final labelStyle =
    Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600);
    final valueStyle = Theme.of(context).textTheme.bodyMedium;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Información de la app'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.apps),
              title: Text(kAppName, style: labelStyle),
              subtitle: Text(
                'Nombre de la aplicación',
                style: valueStyle,
              ),
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.account_tree_outlined),
              title: Text(
                kDeveloperName,
                style: labelStyle,
              ),
              subtitle: Text(
                'Desarrollador',
                style: valueStyle,
              ),
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.info_outline),
              title: Text(
                kAppVersion,
                style: labelStyle,
              ),
              subtitle: Text(
                'Versión',
                style: valueStyle,
              ),
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.email_outlined),
              title: Text(
                kContactEmail,
                style: labelStyle,
              ),
              subtitle: Text(
                'Contacto / Soporte',
                style: valueStyle,
              ),
            ),
            const Divider(),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.open_in_new),
              label: const Text('Política de Privacidad'),
              onPressed: () => _openPrivacyBestEffort(context),
            ),
            const SizedBox(height: 24),
            Text(
              'Esta app almacena localmente en tu dispositivo la información de las tareas '
                  'que registras (título, descripción opcional, estado y fechas). '
                  'No vendemos tus datos personales. '
                  '$kAppName es desarrollada y operada por $kDeveloperName.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/* ===================== LISTA EN PESTAÑAS / COLUMNAS ===================== */

class _ListaTareas extends StatelessWidget {
  final Estado estado;
  final Color color;
  final List<Tarea> items;
  final void Function(Tarea) onEdit;
  final Future<void> Function(Tarea) onDelete;
  final void Function(Tarea) onAdvance;
  final void Function(Tarea) onBack;
  final VoidCallback onAddHere;

  const _ListaTareas({
    required this.estado,
    required this.color,
    required this.items,
    required this.onEdit,
    required this.onDelete,
    required this.onAdvance,
    required this.onBack,
    required this.onAddHere,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Column(
        children: [
          _HeaderColumna(
            titulo: estadoLabel(estado),
            color: color,
            count: 0,
            onAdd: onAddHere,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _VacioHint(
              estado: estado,
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        _HeaderColumna(
          titulo: estadoLabel(estado),
          color: color,
          count: items.length,
          onAdd: onAddHere,
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final t = items[i];
              return _CardTarea(
                t: t,
                color: color,
                onTap: () => onEdit(t),
                onDelete: () => onDelete(t),
                onBack: () => onBack(t),
                onAdvance: () => onAdvance(t),
              );
            },
          ),
        ),
      ],
    );
  }
}

/* ===================== WIDGETS DE UI REUTILIZABLES ===================== */

class _HeaderColumna extends StatelessWidget {
  final String titulo;
  final Color color;
  final int count;
  final VoidCallback onAdd;

  const _HeaderColumna({
    required this.titulo,
    required this.color,
    required this.count,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 24,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            titulo,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text('$count'),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Añadir a $titulo',
            onPressed: onAdd,
            icon: const Icon(
              Icons.add_circle_outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _CardTarea extends StatelessWidget {
  final Tarea t;
  final Color color;
  final bool dragging;
  final VoidCallback? onTap;
  final Future<void> Function()? onDelete;
  final VoidCallback? onAdvance;
  final VoidCallback? onBack;

  const _CardTarea({
    required this.t,
    required this.color,
    this.dragging = false,
    this.onTap,
    this.onDelete,
    this.onAdvance,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final vencida = t.vence != null && t.vence!.isBefore(DateTime.now());
    return Card(
      elevation: dragging ? 10 : 1,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.drag_indicator, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.titulo,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if ((t.descripcion ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        t.descripcion!.trim(),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _ChipInfo(
                          icon: Icons.today,
                          label: 'Creada ${_fmtFechaCorta(t.creada)}',
                        ),
                        _ChipInfo(
                          icon: Icons.event,
                          label: t.vence == null
                              ? 'Sin vencimiento'
                              : (vencida
                              ? 'Vencida ${_fmtFechaCorta(t.vence!)}'
                              : 'Vence ${_fmtFechaCorta(t.vence!)}'),
                          danger: vencida,
                        ),
                        _ChipInfo(
                          icon: Icons.label_important_outline,
                          label: estadoLabel(t.estado),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  IconButton(
                    tooltip: 'Retroceder',
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back),
                  ),
                  IconButton(
                    tooltip: 'Avanzar',
                    onPressed: onAdvance,
                    icon: const Icon(Icons.arrow_forward),
                  ),
                  IconButton(
                    tooltip: 'Eliminar',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChipInfo extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool danger;
  const _ChipInfo({
    required this.icon,
    required this.label,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = danger
        ? Colors.red
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final bg = danger
        ? Colors.red.withOpacity(0.10)
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: fg),
          ),
        ],
      ),
    );
  }
}

class _VacioHint extends StatelessWidget {
  final Estado estado;
  const _VacioHint({required this.estado});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.inbox_outlined,
              size: 36,
            ),
            const SizedBox(height: 8),
            Text(
              'No hay tarjetas en ${estadoLabel(estado)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Pulsa + para añadir o usa “Avanzar”.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/* ===================== UTIL ===================== */

String _fmtFechaCorta(DateTime d) {
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  final yyyy = d.year.toString();
  return '$dd/$mm/$yyyy';
}

enum SortMode {
  creacionAsc,
  creacionDesc,
  venceAsc,
  venceDesc,
  titulo
}

extension on SortMode {
  String get label {
    switch (this) {
      case SortMode.creacionAsc:
        return 'Creación ↑';
      case SortMode.creacionDesc:
        return 'Creación ↓';
      case SortMode.venceAsc:
        return 'Vencimiento ↑';
      case SortMode.venceDesc:
        return 'Vencimiento ↓';
      case SortMode.titulo:
        return 'Título A→Z';
    }
  }
}

/* ===================== EDITOR DE TAREA (BOTTOM SHEET) ===================== */

Future<Tarea?> abrirEditorTarea(
    BuildContext context, {
      Tarea? tarea,
      required Estado estadoInicial,
    }) async {
  return await showModalBottomSheet<Tarea>(
    context: context,
    isScrollControlled: true, // clave para que suba correcto con teclado
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return TareaEditorSheet(
        tarea: tarea,
        estadoInicial: estadoInicial,
      );
    },
  );
}

class TareaEditorSheet extends StatefulWidget {
  final Tarea? tarea;
  final Estado estadoInicial;

  const TareaEditorSheet({
    super.key,
    this.tarea,
    required this.estadoInicial,
  });

  @override
  State<TareaEditorSheet> createState() => _TareaEditorSheetState();
}

class _TareaEditorSheetState extends State<TareaEditorSheet> {
  final _form = GlobalKey<FormState>();
  late TextEditingController _titulo;
  late TextEditingController _descripcion;
  DateTime? _vence;
  late Estado _estado;

  @override
  void initState() {
    super.initState();
    final t = widget.tarea;
    _titulo = TextEditingController(text: t?.titulo ?? '');
    _descripcion = TextEditingController(text: t?.descripcion ?? '');
    _vence = t?.vence;
    _estado = t?.estado ?? widget.estadoInicial;
  }

  @override
  void dispose() {
    _titulo.dispose();
    _descripcion.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final base = _vence ?? now;
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      initialDate: base,
      helpText: 'Selecciona fecha de vencimiento',
    );
    if (d != null) {
      setState(() {
        _vence = d;
      });
    }
  }

  void _onSubmit() {
    if (!_form.currentState!.validate()) return;
    final now = DateTime.now();

    if (widget.tarea == null) {
      final nuevo = Tarea(
        id: 't_${now.microsecondsSinceEpoch}',
        titulo: _titulo.text.trim(),
        descripcion: _descripcion.text.trim().isEmpty
            ? null
            : _descripcion.text.trim(),
        vence: _vence,
        estado: _estado,
        creada: now,
      );
      Navigator.pop<Tarea>(context, nuevo);
    } else {
      Navigator.pop<Tarea>(
        context,
        widget.tarea!.copyWith(
          titulo: _titulo.text.trim(),
          descripcion: _descripcion.text.trim().isEmpty
              ? null
              : _descripcion.text.trim(),
          vence: _vence,
          estado: _estado,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final esEdicion = widget.tarea != null;
    final cs = Theme.of(context).colorScheme;

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: bottomInset + 16,
      ),
      child: SafeArea(
        top: false,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Text(
                esEdicion ? 'Editar tarjeta' : 'Nueva tarjeta',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titulo,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Título *',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Escribe un título' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descripcion,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Descripción',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<Estado>(
                      value: _estado,
                      decoration: const InputDecoration(
                        labelText: 'Columna',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: Estado.values
                          .map(
                            (e) => DropdownMenuItem(
                          value: e,
                          child: Text(estadoLabel(e)),
                        ),
                      )
                          .toList(),
                      onChanged: (v) {
                        setState(() {
                          _estado = v ?? _estado;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: _pickDate,
                      icon: const Icon(Icons.event, size: 20),
                      label: Text(
                        _vence == null
                            ? 'Sin vencimiento'
                            : _fmtFechaCorta(_vence!),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (_vence != null) ...[
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 40,
                      height: 48,
                      child: IconButton(
                        onPressed: () {
                          setState(() {
                            _vence = null;
                          });
                        },
                        icon: const Icon(Icons.close),
                        tooltip: 'Quitar fecha',
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop<Tarea?>(context, null),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _onSubmit,
                    child: Text(esEdicion ? 'Guardar' : 'Crear'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
