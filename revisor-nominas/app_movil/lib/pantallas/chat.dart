import 'package:material_ui/material_ui.dart';

import '../api.dart';
import '../main.dart';
import '../widgets.dart';

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
  ];

  int get usadas => historial.where((m) => m['role'] == 'user').length;
  int get max => widget.r.preguntasChat;
  bool get agotado => max > 0 && usadas >= max;

  Future<void> enviar(String q) async {
    q = q.trim();
    if (q.isEmpty || escribiendo || agotado) return;
    campo.clear();
    setState(() {
      historial.add({'role': 'user', 'content': q});
      historial.add({'role': 'assistant', 'content': ''});
      escribiendo = true;
    });
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.mensaje)));
    } finally {
      if (mounted) setState(() => escribiendo = false);
    }
  }

  void _bajar() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) scroll.jumpTo(scroll.position.maxScrollExtent);
      });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final acento = widget.r.pro ? morado : azul;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pregúntale a Nora'),
        bottom: max > 0
            ? PreferredSize(
                preferredSize: const Size.fromHeight(24),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(max == 1
                      ? 'Versión gratuita: ${usadas == 0 ? 'tienes 1 pregunta' : 'ya has usado tu pregunta'}. En Pro son ilimitadas.'
                      : 'Versión gratuita: te quedan ${max - usadas} de $max preguntas',
                      style: t.textTheme.bodySmall),
                ),
              )
            : null,
      ),
      body: SafeArea(
        child: Centrado(
          child: Column(children: [
            Expanded(
              child: historial.isEmpty
                  ? ListView(padding: const EdgeInsets.all(16), children: [
                      Text('Hola, soy Nora. Ya he revisado tu nómina: pregúntame lo que quieras sobre ella.',
                          style: t.textTheme.bodyLarge),
                      const SizedBox(height: 12),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final s in sugerencias) ActionChip(label: Text(s), onPressed: () => enviar(s)),
                      ]),
                    ])
                  : ListView.builder(
                      controller: scroll,
                      padding: const EdgeInsets.all(12),
                      itemCount: historial.length,
                      itemBuilder: (_, i) {
                        final m = historial[i];
                        final yo = m['role'] == 'user';
                        return Align(
                          alignment: yo ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .8),
                            decoration: BoxDecoration(
                              color: yo ? acento : t.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: m['content']!.isEmpty
                                ? const SizedBox(width: 24, height: 14, child: LinearProgressIndicator())
                                : SelectableText(m['content']!, style: TextStyle(color: yo ? Colors.white : null)),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: campo,
                    enabled: !agotado,
                    textInputAction: TextInputAction.send,
                    onSubmitted: enviar,
                    decoration: InputDecoration(
                      hintText: agotado ? 'Pásate a Pro para seguir preguntando' : 'Escribe tu duda…',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: acento),
                  onPressed: agotado || escribiendo ? null : () => enviar(campo.text),
                  icon: const Icon(Icons.send),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
