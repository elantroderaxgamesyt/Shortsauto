import 'package:material_ui/material_ui.dart';

import '../anuncios.dart';
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

  /// Preguntas que quedan ahora (las incluidas en el plan + las ganadas con anuncios).
  late int disponibles = widget.r.preguntasDisponibles;

  /// ¿Se puede ganar otra viendo un anuncio? (máximo por revisión)
  late bool porAnuncio = widget.r.preguntasPorAnuncio;
  bool viendoAnuncio = false;

  bool get agotado => disponibles == 0 && !porAnuncio;
  bool get necesitaAnuncio => disponibles == 0 && porAnuncio;
  Color get acento => widget.r.pro ? Marca.pro : Marca.azul;

  Future<void> enviar(String q) async {
    q = q.trim();
    if (q.isEmpty || escribiendo || viendoAnuncio || agotado) return;
    if (necesitaAnuncio && !await _ganarPregunta()) return;
    campo.clear();
    setState(() {
      historial.add({'role': 'user', 'content': q});
      historial.add({'role': 'assistant', 'content': ''});
      escribiendo = true;
      disponibles--;
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
        disponibles = e.codigo == 402 || e.codigo == 429 ? 0 : disponibles + 1;
        if (e.codigo == 429) porAnuncio = false;
      });
      if (mounted) aviso(context, e.mensaje);
    } finally {
      if (mounted) setState(() => escribiendo = false);
    }
  }

  /// Pide ver un anuncio con recompensa: 1 anuncio = 1 pregunta.
  Future<bool> _ganarPregunta() async {
    if (!Anuncios.yo.recompensaDisponible) {
      aviso(context, 'Ahora mismo no hay anuncios disponibles para desbloquear preguntas. Inténtalo más tarde.');
      return false;
    }
    final ver = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) {
        final t = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Icon(Icons.ondemand_video_rounded, size: 40, color: acento),
              const Hueco(12),
              Text('Mira un anuncio y pregunta', style: t.textTheme.titleLarge, textAlign: TextAlign.center),
              const Hueco(8),
              Text('Cada anuncio que veas entero desbloquea una pregunta a Nora.',
                  style: t.textTheme.bodyMedium?.copyWith(color: Tonos.de(context).suave), textAlign: TextAlign.center),
              const Hueco(20),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: acento),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Ver anuncio'),
                onPressed: () => Navigator.pop(context, true),
              ),
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Ahora no')),
            ]),
          ),
        );
      },
    );
    if (ver != true || !mounted) return false;
    setState(() => viendoAnuncio = true);
    try {
      final visto = await Anuncios.yo.verAnuncioRecompensa(dispositivo: Api.yo.usuario, revision: widget.r.id);
      if (!mounted) return false;
      if (!visto) {
        aviso(context, 'Para desbloquear la pregunta hay que ver el anuncio entero.');
        return false;
      }
      // Con la verificación en el servidor, el aviso de Google puede tardar unos segundos.
      for (var i = 0; i < 6; i++) {
        final n = await Api.yo.recompensa(widget.r.id);
        if (n > 0) {
          if (mounted) setState(() => disponibles = n);
          return true;
        }
        await Future.delayed(const Duration(seconds: 2));
      }
      if (mounted) aviso(context, 'No se ha podido confirmar el anuncio. Inténtalo de nuevo.');
      return false;
    } on ErrorApi catch (e) {
      if (mounted) {
        if (e.codigo == 429) setState(() => porAnuncio = false);
        aviso(context, e.mensaje);
      }
      return false;
    } finally {
      if (mounted) setState(() => viendoAnuncio = false);
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
                if (agotado && !escribiendo) ...[const Hueco(12), _Limite(pro: widget.r.pro)],
              ]),
            ),
            if (!agotado)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(necesitaAnuncio ? Icons.ondemand_video_rounded : Icons.chat_bubble_outline_rounded,
                      size: 14, color: tonos.suave),
                  const SizedBox(width: 6),
                  Text(
                      viendoAnuncio
                          ? 'Cargando anuncio…'
                          : necesitaAnuncio
                              ? 'Siguiente pregunta: mira un anuncio corto'
                              : disponibles == 1
                                  ? 'Te queda 1 pregunta'
                                  : 'Te quedan $disponibles preguntas',
                      style: t.textTheme.bodySmall?.copyWith(color: tonos.suave)),
                ]),
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
                      hintText: agotado ? 'Has llegado al máximo de preguntas' : 'Escribe tu duda…',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: acento, minimumSize: const Size(48, 48)),
                  onPressed: agotado || escribiendo || viendoAnuncio ? null : () => enviar(campo.text),
                  icon: Icon(necesitaAnuncio ? Icons.play_arrow_rounded : Icons.arrow_upward_rounded),
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
  const _Limite({required this.pro});
  final bool pro;

  @override
  Widget build(BuildContext context) => Panel(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Has llegado al máximo de preguntas', style: Theme.of(context).textTheme.titleSmall),
          const Hueco(8),
          Text(pro
              ? 'Para esta revisión ya has usado todas las preguntas. Tienes el resumen para la reclamación '
                  'en el informe.'
              : 'Para esta revisión ya has usado todas las preguntas. La revisión completa incluye 3 preguntas '
                  'sin anuncios y el resumen para la reclamación.'),
          if (!pro) ...[
            const Hueco(12),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Marca.pro),
              onPressed: () => empezarRevision(context),
              child: const Text('Hacer revisión completa'),
            ),
          ],
        ]),
      );
}
