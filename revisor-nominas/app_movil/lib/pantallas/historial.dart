import 'package:material_ui/material_ui.dart';

import '../api.dart';
import '../estado.dart';
import '../tema.dart';
import '../widgets.dart';
import 'informe.dart';
import 'nueva_revision.dart';

class PantallaHistorial extends StatefulWidget {
  const PantallaHistorial({super.key});

  @override
  State<PantallaHistorial> createState() => _PantallaHistorialState();
}

class _PantallaHistorialState extends State<PantallaHistorial> {
  late Future<List<ResumenRevision>> lista = Api.yo.revisiones();

  @override
  void initState() {
    super.initState();
    historialCambiado.addListener(_recargar);
    pestana.addListener(_alCambiarPestana);
  }

  @override
  void dispose() {
    historialCambiado.removeListener(_recargar);
    pestana.removeListener(_alCambiarPestana);
    super.dispose();
  }

  void _alCambiarPestana() {
    if (pestana.value == 1) _recargar();
  }

  Future<void> _recargar() async {
    final f = Api.yo.revisiones();
    setState(() => lista = f);
    await f.catchError((_) => <ResumenRevision>[]);
  }

  Future<void> abrir(ResumenRevision x) async {
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    try {
      final r = await Api.yo.revision(x.id);
      if (!mounted) return;
      Navigator.pop(context);
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => PantallaInforme(r)));
    } on ErrorApi catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      aviso(context, e.mensaje);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tonos = Tonos.de(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Mis revisiones')),
      body: RefreshIndicator(
        onRefresh: _recargar,
        child: FutureBuilder(
          future: lista,
          builder: (context, s) {
            if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            if (s.hasError) {
              return _Vacio(
                icono: Icons.cloud_off_rounded,
                titulo: 'Sin conexión',
                texto: s.error is ErrorApi ? (s.error as ErrorApi).mensaje : 'No se han podido cargar tus revisiones.',
                boton: 'Reintentar',
                onPressed: _recargar,
              );
            }
            final items = s.data!;
            if (items.isEmpty) {
              return _Vacio(
                icono: Icons.inventory_2_outlined,
                titulo: 'Aún no has revisado ninguna nómina',
                texto: 'Cuando revises una, la tendrás aquí para volver a consultarla o preguntarle a Nora.',
                boton: 'Revisar mi nómina',
                onPressed: () => empezarRevision(context),
              );
            }
            return Pagina(children: [
              for (final x in items) ...[
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => abrir(x),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                              color: Estilo.de(x.veredicto).fondo(context), borderRadius: BorderRadius.circular(12)),
                          child: Icon(Estilo.de(x.veredicto).icono, color: Estilo.de(x.veredicto).texto(context)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Flexible(
                                child: Text(x.periodo ?? 'Nómina', style: t.textTheme.titleSmall, overflow: TextOverflow.ellipsis),
                              ),
                              if (x.pro) ...[const SizedBox(width: 8), const InsigniaPro()],
                            ]),
                            const SizedBox(height: 2),
                            Text([x.empresa, fechaCorta(x.fecha)].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                                style: t.textTheme.bodySmall?.copyWith(color: tonos.suave), overflow: TextOverflow.ellipsis),
                          ]),
                        ),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(eur(x.liquido), style: t.textTheme.titleSmall),
                          const SizedBox(height: 4),
                          Etiqueta(x.veredicto),
                        ]),
                      ]),
                    ),
                  ),
                ),
                const Hueco(10),
              ],
            ]);
          },
        ),
      ),
    );
  }
}

class _Vacio extends StatelessWidget {
  const _Vacio({required this.icono, required this.titulo, required this.texto, required this.boton, required this.onPressed});
  final IconData icono;
  final String titulo, texto, boton;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tonos = Tonos.de(context);
    return ListView(padding: const EdgeInsets.all(32), children: [
      const Hueco(60),
      Centrado(
        ancho: 420,
        child: Column(children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: tonos.tenue, shape: BoxShape.circle),
            child: Icon(icono, size: 34, color: tonos.suave),
          ),
          const Hueco(20),
          Text(titulo, style: t.textTheme.titleMedium, textAlign: TextAlign.center),
          const Hueco(8),
          Text(texto, style: t.textTheme.bodyMedium?.copyWith(color: tonos.suave), textAlign: TextAlign.center),
          const Hueco(24),
          FilledButton(onPressed: onPressed, child: Text(boton)),
        ]),
      ),
    ]);
  }
}
