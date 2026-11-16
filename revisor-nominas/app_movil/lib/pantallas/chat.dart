import 'package:material_ui/material_ui.dart';

import '../api.dart';
import '../tema.dart';
import '../widgets.dart';
import 'nueva_revision.dart';

class PantallaChat extends StatefulWidget {
  const PantallaChat(this.r, {super.key});
  final Revision r;

  @override
  State<PantallaChat> createState() => _PantallaChatState();
}

class _PantallaChatState extends State<PantallaChat> {
  final historial = <Map<String, String>>[];
  final campo = TextEditingController();
  final scroll = ScrollController();
  bool escribiendo = false;

  static const sugerencias = [
    '¿Por qué me quitan tanto de IRPF?',
    '¿Qué es la base de cotización?',
    '¿Están bien mis pagas extra?',
    '¿Qué hago si la empresa no me lo corrige?',
  ];

  int get max => widget.r.preguntasChat;
  int get usadas => widget.r.preguntasUsadas + historial.where((m) => m['role'] == 'user').length;
  bool get agotado => max > 0 && usadas >= max;
  Color get acento => widget.r.pro ? Marca.pro : Marca.azul;

  Future<void> enviar(String q) async {
    q = q.trim();
    if (q.isEmpty || escribiendo || agotado) return;
    campo.clear();
    setState(() {
      historial.add({'role': 'user', 'content': q});
      historial.add({'role': 'assistant', 'content': ''});
      escribiendo = true;
    });
    _bajar();
    final peticion = historial.sublist(0, historial.length - 1);
    try {
      await for (final trozo in Api.yo.chat(widget.r.id, peticion)) {
        setState(() => historial.last['content'] = historial.last['content']! + trozo);
        _bajar();
      }
    } on ErrorApi catch (e) {
      setState(() {
        historial.removeLast();
        historial.removeLast();
      });
      if (mounted) aviso(context, e.mensaje);
    } finally {
      if (mounted) setState(() => escribiendo = false);
    }
  }

  void _bajar() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) {
          scroll.animateTo(scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
        }
      });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tonos = Tonos.de(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          const _Avatar(),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Nora', style: t.textTheme.titleMedium),
            Text(escribiendo ? 'escribiendo…' : 'Asesora laboral con IA',
                style: t.textTheme.bodySmall?.copyWith(color: tonos.suave)),
          ]),
        ]),
      ),
      body: SafeArea(
        child: Centrado(
          child: Column(children: [
            Expanded(
              child: ListView(controller: scroll, padding: const EdgeInsets.all(16), children: [
                _Burbuja(
                  'Hola, soy Nora. Ya he revisado tu nómina${widget.r.datos['periodo'] != null ? ' de ${widget.r.datos['periodo']}' : ''}. '
                  '¿Qué quieres saber?',
                  yo: false,
                  acento: acento,
                ),
                if (historial.isEmpty && !agotado) ...[
                  const Hueco(8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final s in sugerencias)
                      ActionChip(
                        label: Text(s),
                        side: BorderSide(color: tonos.borde),
                        backgroundColor: tonos.tarjeta,
                        onPressed: () => enviar(s),
                      ),
                  ]),
                ],
                for (final m in historial)
                  m['content']!.isEmpty
                      ? const _Escribiendo()
                      : _Burbuja(m['content']!, yo: m['role'] == 'user', acento: acento),
                if (agotado && !escribiendo) ...[const Hueco(12), _Limite(acento)],
              ]),
            ),
            if (max > 0 && !agotado)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('Versión gratuita: ${max - usadas == 1 ? 'te queda 1 pregunta' : 'te quedan ${max - usadas} preguntas'}',
                    style: t.textTheme.bodySmall?.copyWith(color: tonos.suave)),
              ),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: campo,
                    enabled: !agotado,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: enviar,
                    decoration: InputDecoration(
                      hintText: agotado ? 'Has usado tu pregunta gratis' : 'Escribe tu duda…',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: acento, minimumSize: const Size(48, 48)),
                  onPressed: agotado || escribiendo ? null : () => enviar(campo.text),
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({this.tam = 36});
  final double tam;

  @override
  Widget build(BuildContext context) => Container(
        width: tam,
        height: tam,
        decoration: const BoxDecoration(gradient: Marca.degradado, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Text('N', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: tam * .42)),
      );
}

class _Burbuja extends StatelessWidget {
  const _Burbuja(this.texto, {required this.yo, required this.acento});
  final String texto;
  final bool yo;
  final Color acento;

  @override
  Widget build(BuildContext context) {
    final tonos = Tonos.de(context);
    final burbuja = Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
      decoration: BoxDecoration(
        color: yo ? acento : tonos.tarjeta,
        border: yo ? null : Border.all(color: tonos.borde),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(yo ? 18 : 4),
          bottomRight: Radius.circular(yo ? 4 : 18),
        ),
      ),
      child: SelectableText(texto, style: TextStyle(color: yo ? Colors.white : null, height: 1.45)),
    );
    if (yo) return Align(alignment: Alignment.centerRight, child: burbuja);
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      const _Avatar(tam: 28),
      const SizedBox(width: 8),
      Flexible(child: burbuja),
    ]);
  }
}

class _Escribiendo extends StatelessWidget {
  const _Escribiendo();

  @override
  Widget build(BuildContext context) => Row(children: [
        const _Avatar(tam: 28),
        const SizedBox(width: 8),
        Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Tonos.de(context).tarjeta,
            border: Border.all(color: Tonos.de(context).borde),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const SizedBox(width: 28, height: 8, child: LinearProgressIndicator()),
        ),
      ]);
}

class _Limite extends StatelessWidget {
  const _Limite(this.acento);
  final Color acento;

  @override
  Widget build(BuildContext context) => Panel(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const InsigniaPro(),
            const SizedBox(width: 8),
            Text('Sigue preguntando', style: Theme.of(context).textTheme.titleSmall),
          ]),
          const Hueco(8),
          const Text('En la versión gratuita puedes hacer 1 pregunta por nómina. Con la revisión completa '
              'las preguntas son ilimitadas y además tienes el resumen para la reclamación.'),
          const Hueco(12),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Marca.pro),
            onPressed: () => empezarRevision(context),
            child: const Text('Hacer revisión completa'),
          ),
        ]),
      );
}
