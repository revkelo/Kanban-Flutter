import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const KanbanApp());
}

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
    vence: (j['vence'] as String?) != null ? DateTime.parse(j['vence']) : null,
    estado: estadoFromString(j['estado'] as String),
    creada: DateTime.parse(j['creada'] as String),
  );
}

/* ===================== APP ===================== */

class KanbanApp extends StatelessWidget {
  const KanbanApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kanban',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: const KanbanHome(),
    );
  }
}

class KanbanHome extends StatefulWidget {
  const KanbanHome({super.key});
  @override
  State<KanbanHome> createState() => _KanbanHomeState();
}

class _KanbanHomeState extends State<KanbanHome>
    with SingleTickerProviderStateMixin {
  static const _storeKey = 'kanban_v1';
  final Map<Estado, List<Tarea>> _tablero = {
    Estado.backlog: [],
    Estado.progreso: [],
    Estado.hecho: [],
  };

  late final TabController _tabController;
  bool _cargando = true;
  String _busqueda = '';
  SortMode _sortMode = SortMode.creacionAsc;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _cargar();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_storeKey);
    if (raw != null) {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      for (final k in decoded.keys) {
        final estado = estadoFromString(k);
        final lista = (decoded[k] as List)
            .cast<Map>()
            .map((e) => Tarea.fromJson(e.cast<String, dynamic>()))
            .toList();
        _tablero[estado] = lista;
      }
    }
    setState(() => _cargando = false);
  }

  Future<void> _guardar() async {
    final sp = await SharedPreferences.getInstance();
    final data = <String, dynamic>{
      for (final e in Estado.values)
        estadoToString(e): _tablero[e]!.map((t) => t.toJson()).toList(),
    };
    await sp.setString(_storeKey, jsonEncode(data));
  }

  void _agregar(Tarea t) {
    setState(() => _tablero[t.estado]!.add(t));
    _guardar();
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
    _guardar();
  }

  void _eliminar(Tarea t) {
    setState(() => _tablero[t.estado]!.removeWhere((x) => x.id == t.id));
    _guardar();
  }

  List<Tarea> _filtrarYOrdenar(List<Tarea> src) {
    var out = src.where((t) {
      if (_busqueda.isEmpty) return true;
      final q = _busqueda.toLowerCase();
      return t.titulo.toLowerCase().contains(q) ||
          (t.descripcion ?? '').toLowerCase().contains(q);
    }).toList();

    int cmp(DateTime a, DateTime b) => a.compareTo(b);

    out.sort((a, b) {
      switch (_sortMode) {
        case SortMode.creacionAsc:
          return cmp(a.creada, b.creada);
        case SortMode.creacionDesc:
          return cmp(b.creada, a.creada);
        case SortMode.venceAsc:
          return (a.vence ?? DateTime(2100)).compareTo(b.vence ?? DateTime(2100));
        case SortMode.venceDesc:
          return (b.vence ?? DateTime(1900)).compareTo(a.vence ?? DateTime(1900));
        case SortMode.titulo:
          return a.titulo.toLowerCase().compareTo(b.titulo.toLowerCase());
      }
    });

    return out;
  }

  Future<void> _dialogoNuevaTarea([Estado estadoInicial = Estado.backlog]) async {
    final t = await showDialog<Tarea>(
      context: context,
      builder: (_) => TareaDialog(estadoInicial: estadoInicial),
    );
    if (t != null) _agregar(t);
  }

  Future<void> _dialogoEditar(Tarea t) async {
    final edit = await showDialog<Tarea>(
      context: context,
      builder: (_) => TareaDialog(tarea: t),
    );
    if (edit != null) _actualizar(edit);
  }

  void _moverA(Tarea t, Estado nuevo) {
    if (t.estado == nuevo) return;
    _actualizar(t.copyWith(estado: nuevo));
  }

  Estado _estadoDeIndex(int i) =>
      [Estado.backlog, Estado.progreso, Estado.hecho][i];

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final esMovil = constraints.maxWidth < 700;

        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 0, // sin título/acciones arriba
            bottom: PreferredSize(
              // Altura suficiente para buscador + espacio + TabBar (en móvil)
              preferredSize: Size.fromHeight(esMovil ? 124 : 64),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            onChanged: (v) => setState(() => _busqueda = v),
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
                          onSelected: (m) => setState(() => _sortMode = m),
                          itemBuilder: (ctx) => [
                            _itemSort(ctx, SortMode.creacionAsc, 'Creación ↑'),
                            _itemSort(ctx, SortMode.creacionDesc, 'Creación ↓'),
                            _itemSort(ctx, SortMode.venceAsc, 'Vencimiento ↑'),
                            _itemSort(ctx, SortMode.venceDesc, 'Vencimiento ↓'),
                            _itemSort(ctx, SortMode.titulo, 'Título A→Z'),
                          ],
                          child: Row(
                            children: [
                              const Icon(Icons.sort),
                              const SizedBox(width: 6),
                              Text(_sortMode.label),
                              const SizedBox(width: 6),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (esMovil)
                    SizedBox(
                      height: kTextTabBarHeight, // 48
                      child: TabBar(
                        controller: _tabController, // <- IMPORTANTE
                        tabs: const [
                          Tab(text: 'Backlog', icon: Icon(Icons.inbox_outlined)),
                          Tab(text: 'En progreso', icon: Icon(Icons.timelapse)),
                          Tab(text: 'Hecho', icon: Icon(Icons.check_circle_outlined)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),


          // ====== CUERPO RESPONSIVE ======
          body: esMovil ? _bodyTabsMovil() : _bodyColumnasDesktop(),

          floatingActionButton: esMovil
              ? FloatingActionButton.extended(
            onPressed: () =>
                _dialogoNuevaTarea(_estadoDeIndex(_tabController.index)),
            icon: const Icon(Icons.add),
            label: const Text('Nueva'),
          )
              : null,
        );
      },
    );
  }

  // ====== MÓVIL: PESTAÑAS ======
  Widget _bodyTabsMovil() {
    return TabBarView(
      controller: _tabController,
      children: Estado.values.map((e) {
        final color = _colorColumna(e);
        final items = _filtrarYOrdenar(_tablero[e]!);
        return _ListaTareas(
          estado: e,
          color: color,
          items: items,
          onEdit: _dialogoEditar,
          onDelete: _eliminar,
          onAdvance: (t) {
            final next = _siguiente(e);
            if (next != null) _moverA(t, next);
          },
          onAddHere: () => _dialogoNuevaTarea(e),
        );
      }).toList(),
    );
  }

  // ====== ESCRITORIO / TABLET ANCHO: COLUMNAS ======
  Widget _bodyColumnasDesktop() {
    return Row(
      children: Estado.values.map((e) {
        final color = _colorColumna(e);
        final items = _filtrarYOrdenar(_tablero[e]!);
        return Expanded(
          child: DragTarget<Tarea>(
            onWillAccept: (t) => true,
            onAccept: (t) => _moverA(t, e),
            builder: (context, candidates, rejects) {
              final hovered = candidates.isNotEmpty;
              return Container(
                decoration: BoxDecoration(
                  border: Border(
                    right: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                  color: hovered ? color.withOpacity(0.08) : null,
                ),
                child: Column(
                  children: [
                    _HeaderColumna(
                      titulo: estadoLabel(e),
                      color: color,
                      count: items.length,
                      onAdd: () => _dialogoNuevaTarea(e),
                    ),
                    Expanded(
                      child: items.isEmpty
                          ? _VacioHint(estado: e)
                          : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final t = items[i];
                          return LongPressDraggable<Tarea>(
                            data: t,
                            feedback: _CardTarea(
                                t: t, color: color, dragging: true),
                            childWhenDragging: Opacity(
                              opacity: 0.3,
                              child: _CardTarea(t: t, color: color),
                            ),
                            child: _CardTarea(
                              t: t,
                              color: color,
                              onTap: () => _dialogoEditar(t),
                              onDelete: () => _eliminar(t),
                              onAdvance: () {
                                final next = _siguiente(e);
                                if (next != null) _moverA(t, next);
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
  }

  PopupMenuItem<SortMode> _itemSort(BuildContext ctx, SortMode m, String label) {
    return PopupMenuItem(
      value: m,
      child: Row(
        children: [
          if (_sortMode == m) const Icon(Icons.check, size: 18),
          if (_sortMode == m) const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
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
}

/* ===================== LISTA EN PESTAÑAS (MÓVIL) ===================== */

class _ListaTareas extends StatelessWidget {
  final Estado estado;
  final Color color;
  final List<Tarea> items;
  final void Function(Tarea) onEdit;
  final void Function(Tarea) onDelete;
  final void Function(Tarea) onAdvance;
  final VoidCallback onAddHere;

  const _ListaTareas({
    required this.estado,
    required this.color,
    required this.items,
    required this.onEdit,
    required this.onDelete,
    required this.onAdvance,
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
              onAdd: onAddHere),
          const SizedBox(height: 8),
          Expanded(child: _VacioHint(estado: estado)),
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
                onAdvance: () => onAdvance(t),
              );
            },
          ),
        ),
      ],
    );
  }
}

/* ===================== UI WIDGETS ===================== */

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
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
            icon: const Icon(Icons.add_circle_outline),
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
  final VoidCallback? onDelete;
  final VoidCallback? onAdvance;

  const _CardTarea({
    required this.t,
    required this.color,
    this.dragging = false,
    this.onTap,
    this.onDelete,
    this.onAdvance,
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
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
              )
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
  const _ChipInfo({required this.icon, required this.label, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final fg =
    danger ? Colors.red : Theme.of(context).colorScheme.onSurfaceVariant;
    final bg = danger
        ? Colors.red.withOpacity(0.10)
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: fg)),
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
            const Icon(Icons.inbox_outlined, size: 36),
            const SizedBox(height: 8),
            Text('No hay tarjetas en ${estadoLabel(estado)}',
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            Text('Pulsa + para añadir o usa “Avanzar”.',
                style: Theme.of(context).textTheme.bodySmall),
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

enum SortMode { creacionAsc, creacionDesc, venceAsc, venceDesc, titulo }

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

/* ===================== DIÁLOGO CREAR / EDITAR ===================== */

class TareaDialog extends StatefulWidget {
  final Tarea? tarea;
  final Estado? estadoInicial;
  const TareaDialog({super.key, this.tarea, Estado? estadoInicial})
      : estadoInicial = estadoInicial;

  @override
  State<TareaDialog> createState() => _TareaDialogState();
}

class _TareaDialogState extends State<TareaDialog> {
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
    _estado = t?.estado ?? widget.estadoInicial ?? Estado.backlog;
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
    if (d != null) setState(() => _vence = d);
  }

  @override
  Widget build(BuildContext context) {
    final editando = widget.tarea != null;

    final w = MediaQuery.of(context).size.width;
    final esEstrecho = w < 380;

    return AlertDialog(
      title: Text(editando ? 'Editar tarjeta' : 'Nueva tarjeta'),
      content: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                const SizedBox(height: 10),
                TextFormField(
                  controller: _descripcion,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Descripción',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),

                if (esEstrecho) ...[
                  DropdownButtonFormField<Estado>(
                    value: _estado,
                    decoration: const InputDecoration(
                      labelText: 'Columna',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: Estado.values
                        .map((e) => DropdownMenuItem(
                      value: e,
                      child: Text(estadoLabel(e)),
                    ))
                        .toList(),
                    onChanged: (v) => setState(() => _estado = v ?? _estado),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickDate,
                          icon: const Icon(Icons.event),
                          label: Text(_vence == null
                              ? 'Sin vencimiento'
                              : _fmtFechaCorta(_vence!)),
                        ),
                      ),
                      if (_vence != null) ...[
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 40, height: 40, // compacto
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            iconSize: 20,
                            onPressed: () => setState(() => _vence = null),
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      ]

                    ],
                  ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickDate,
                          icon: const Icon(Icons.event, size: 20),
                          label: Text(_vence == null ? 'Sin vencimiento' : _fmtFechaCorta(_vence!)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            visualDensity: VisualDensity.compact,
                            minimumSize: const Size(0, 40),
                          ),
                        ),
                      ),
                      if (_vence != null) ...[
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 36,
                          height: 40,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            iconSize: 20,
                            onPressed: () => setState(() => _vence = null),
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      ],
                    ],
                  )


                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop<Tarea?>(context, null),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
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
          },
          child: Text(widget.tarea == null ? 'Crear' : 'Guardar'),
        ),
      ],
    );
  }
}
