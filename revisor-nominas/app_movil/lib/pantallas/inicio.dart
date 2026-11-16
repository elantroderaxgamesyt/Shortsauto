import 'package:material_ui/material_ui.dart';

import '../compras.dart';
import '../estado.dart';
import '../tema.dart';
import '../widgets.dart';
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
          const _ChipSaldo(),
        ]),
        const Hueco(20),
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
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (final (i, txt) in const ['Gratis', 'Sin registro', 'Resultado al momento'].indexed) ...[
            if (i > 0) Text('  ·  ', style: TextStyle(color: Colors.white.withValues(alpha: .6))),
            Text(txt, style: t.textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: .85))),
          ],
        ]),
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

/// Saldo arriba a la derecha: "Pro · 2" o "Free". Lleva a Mi cuenta.
class _ChipSaldo extends StatelessWidget {
  const _ChipSaldo();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Tienda.yo,
        builder: (context, _) {
          final c = Tienda.yo.cuenta;
          if (c == null) return const SizedBox.shrink();
          final pro = c.puedePro;
          final morado = Theme.of(context).brightness == Brightness.dark ? Marca.proClaro : Marca.pro;
          return InkWell(
            borderRadius: BorderRadius.circular(99),
            onTap: () => pestana.value = 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: pro ? Marca.degradadoPro : null,
                color: pro ? null : Tonos.de(context).tenue,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(pro ? Icons.workspace_premium_rounded : Icons.workspace_premium_outlined,
                    size: 16, color: pro ? Colors.white : morado),
                const SizedBox(width: 6),
                Text(
                  pro ? (c.suscripcion ? 'Pro mensual' : 'Pro · ${c.creditos}') : 'Hazte Pro',
                  style: TextStyle(
                      color: pro ? Colors.white : morado, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ]),
            ),
          );
        },
      );
}
