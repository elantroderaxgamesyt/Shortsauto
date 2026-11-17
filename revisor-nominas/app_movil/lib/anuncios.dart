import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'compras.dart';
import 'config.dart';

/// Anuncios de Google AdMob. Sólo en Android y sólo para usuarios Free:
/// quien tiene la suscripción o revisiones completas no ve ninguno.
///
/// - Al abrir la app: un anuncio a pantalla completa, como mucho una vez cada
///   [horasEntreAperturas] y nunca la primera vez que se abre la app.
/// - Un banner abajo en Inicio y Mis revisiones (nunca en el informe).
///
/// Antes de cargar nada se pide el consentimiento que exige el RGPD
/// (formulario oficial de Google, configurado en AdMob > Privacidad y mensajes).
class Anuncios extends ChangeNotifier {
  Anuncios._();
  static final yo = Anuncios._();

  static const horasEntreAperturas = 4;

  bool _listo = false;
  bool privacidadRequerida = false;

  bool get disponibles => anunciosActivos;

  /// ¿Hay que enseñar anuncios ahora mismo?
  bool get mostrar => _listo && !(Tienda.yo.cuenta?.puedePro ?? false);

  Future<void> iniciar() async {
    if (!disponibles) return;
    Tienda.yo.addListener(notifyListeners); // si compra Pro, los banners desaparecen al momento

    // 1) Consentimiento (RGPD). Si falla, seguimos con lo que diga canRequestAds.
    final consentimiento = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () => ConsentForm.loadAndShowConsentFormIfRequired((_) => consentimiento.complete()),
      (_) => consentimiento.complete(),
    );
    await consentimiento.future;
    if (!await ConsentInformation.instance.canRequestAds()) return;
    privacidadRequerida = await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
        PrivacyOptionsRequirementStatus.required;

    // 2) SDK de anuncios.
    await MobileAds.instance.initialize();
    _listo = true;
    notifyListeners();

    // 3) Anuncio de apertura.
    await _anuncioApertura();
  }

  Future<void> _anuncioApertura() async {
    final prefs = await SharedPreferences.getInstance();
    final ahora = DateTime.now().millisecondsSinceEpoch;
    if (!(prefs.getBool('ya_abierta') ?? false)) {
      await prefs.setBool('ya_abierta', true); // la primera vez, sin anuncio
      return;
    }
    final ultimo = prefs.getInt('ultimo_anuncio_apertura') ?? 0;
    if (ahora - ultimo < horasEntreAperturas * 3600 * 1000) return;

    await Tienda.yo.refrescarCuenta();
    if (!mostrar) return;

    final cargado = Completer<AppOpenAd?>();
    AppOpenAd.load(
      adUnitId: admobApertura,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) => cargado.isCompleted ? ad.dispose() : cargado.complete(ad),
        onAdFailedToLoad: (_) => cargado.isCompleted ? null : cargado.complete(null),
      ),
    );
    // Si tarda demasiado, no lo enseñamos: el usuario ya estará usando la app.
    final ad = await cargado.future.timeout(const Duration(seconds: 4), onTimeout: () => null);
    if (ad == null) return;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) => a.dispose(),
      onAdFailedToShowFullScreenContent: (a, _) => a.dispose(),
    );
    await prefs.setInt('ultimo_anuncio_apertura', ahora);
    await ad.show();
  }

  /// Para el apartado "Privacidad de los anuncios" de Mi cuenta.
  Future<void> abrirPrivacidad() => ConsentForm.showPrivacyOptionsForm((_) {});
}

/// Banner adaptado al ancho de la pantalla. No ocupa nada si no hay que mostrar anuncios.
class BannerAnuncio extends StatefulWidget {
  const BannerAnuncio({super.key});

  @override
  State<BannerAnuncio> createState() => _BannerAnuncioState();
}

class _BannerAnuncioState extends State<BannerAnuncio> {
  BannerAd? _ad;
  bool _cargado = false;
  int? _ancho;

  @override
  void initState() {
    super.initState();
    Anuncios.yo.addListener(_actualizar);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _actualizar();
  }

  @override
  void dispose() {
    Anuncios.yo.removeListener(_actualizar);
    _ad?.dispose();
    super.dispose();
  }

  Future<void> _actualizar() async {
    if (!mounted) return;
    if (!Anuncios.yo.mostrar) {
      if (_ad != null) {
        _ad!.dispose();
        setState(() {
          _ad = null;
          _cargado = false;
        });
      }
      return;
    }
    final ancho = MediaQuery.sizeOf(context).width.truncate();
    if (_ad != null && ancho == _ancho) return;
    _ancho = ancho;
    final tam = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(ancho);
    if (tam == null || !mounted) return;
    _ad?.dispose();
    _cargado = false;
    _ad = BannerAd(
      adUnitId: admobBanner,
      size: tam,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _cargado = true);
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          if (mounted) setState(() => _ad = null);
        },
      ),
    )..load();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad == null || !_cargado || !Anuncios.yo.mostrar) return const SizedBox.shrink();
    return SafeArea(
      top: false,
      bottom: false,
      child: SizedBox(width: ad.size.width.toDouble(), height: ad.size.height.toDouble(), child: AdWidget(ad: ad)),
    );
  }
}
