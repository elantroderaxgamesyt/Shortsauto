import 'package:material_ui/material_ui.dart';

import '../config.dart';
import '../tema.dart';
import '../widgets.dart';
import 'info.dart';
import 'nueva_revision.dart';

class PantallaInicio extends StatelessWidget {
  const PantallaInicio({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tonos = Tonos.de(context);
    return SafeArea(
      child: Pagina(children: [
        const Hueco(8),
        Row(children: [
          // En pantallas anchas el logo ya está en la barra lateral.
          if (MediaQuery.sizeOf(context).width < 840) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset('assets/icono/icono.png', width: 36, height: 36),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(child: Text('Revisor de nóminas', style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
          IconButton(
            tooltip: 'Información',
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PantallaInfo())),
          ),
        ]),
        const Hueco(20),
        if (modoDemo) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Estilo.de('aviso').fondo(context), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Icon(Icons.science_outlined, color: Estilo.de('aviso').texto(context)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Modo demo: la app funciona sin servidor con un informe de ejemplo y los pagos simulados.',
                  style: TextStyle(color: Estilo.de('aviso').texto(context)),
                ),
              ),
            ]),
          ),
          const Hueco(12),
        ],
        const _Portada(),
        const Hueco(24),
        Text('Cómo funciona', style: t.textTheme.titleMedium),
        const Hueco(12),
        const _Paso(1, Icons.upload_file_rounded, 'Sube tu nómina', 'En PDF o con una foto desde el móvil.'),
        const _Paso(2, Icons.fact_check_outlined, 'La revisamos línea a línea',
            'Nora, nuestra asesora con IA, comprueba cada concepto y rehacemos las cuentas.'),
        const _Paso(3, Icons.task_alt_rounded, 'Recibe tu informe',
            'Lo que está bien, lo que falla y qué hacer. Y si hay dudas, pregúntale a Nora.', ultimo: true),
        const Hueco(24),
        Text('Qué comprobamos', style: t.textTheme.titleMedium),
        const Hueco(12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (ic, txt) in const [
            (Icons.payments_outlined, 'Salario y pluses'),
            (Icons.shield_outlined, 'Seguridad Social'),
            (Icons.account_balance_outlined, 'Retención de IRPF'),
            (Icons.card_giftcard_outlined, 'Pagas extra'),
            (Icons.more_time_rounded, 'Horas extra'),
            (Icons.calculate_outlined, 'Sumas y líquido'),
          ])
            Chip(
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              avatar: Icon(ic, size: 18, color: t.colorScheme.primary),
              label: Text(txt),
            ),
        ]),
        const Hueco(24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.lock_outline_rounded, color: tonos.suave),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Tu nómina se envía cifrada sólo para analizarla y no se guarda. '
                  'El informe es orientativo y no sustituye a un asesor laboral.',
                  style: t.textTheme.bodySmall?.copyWith(color: tonos.suave, height: 1.45),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Portada extends StatelessWidget {
  const _Portada();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(gradient: Marca.degradado, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('¿Tu nómina está bien?',
            style: t.textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
        const Hueco(8),
        Text(
          'Descubre en un minuto si te pagan lo que te corresponde y qué hacer si hay un error.',
          style: t.textTheme.bodyLarge?.copyWith(color: Colors.white.withValues(alpha: .88)),
        ),
        const Hueco(20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Marca.azul),
            onPressed: () => empezarRevision(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Revisar mi nómina'),
          ),
        ),
        const Hueco(12),
        // Wrap: en pantallas estrechas pasa a la línea siguiente en vez de cortarse.
        Center(
          child: Wrap(alignment: WrapAlignment.center, runSpacing: 4, children: [
            for (final (i, txt) in const ['Gratis', 'Sin registro', 'Al momento'].indexed)
              Text('${i > 0 ? '  ·  ' : ''}$txt',
                  style: t.textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: .85))),
          ]),
        ),
      ]),
    );
  }
}

class _Paso extends StatelessWidget {
  const _Paso(this.n, this.icono, this.titulo, this.texto, {this.ultimo = false});
  final int n;
  final IconData icono;
  final String titulo, texto;
  final bool ultimo;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tonos = Tonos.de(context);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Column(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: t.colorScheme.primary.withValues(alpha: .1), shape: BoxShape.circle),
            child: Icon(icono, size: 20, color: t.colorScheme.primary),
          ),
          if (!ultimo) Expanded(child: Container(width: 2, color: tonos.borde)),
        ]),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: 2, bottom: ultimo ? 0 : 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo, style: t.textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(texto, style: t.textTheme.bodyMedium?.copyWith(color: tonos.suave)),
            ]),
          ),
        ),
      ]),
    );
  }
}
