"""Comprobaciones aritméticas que hace el programa, sin IA.

La IA lee la nómina y opina; estas funciones recalculan los números para que
el informe no dependa sólo de lo que diga el modelo.
"""
from __future__ import annotations

import json
from pathlib import Path

from .modelos import Comprobacion, DatosNomina

REFERENCIA = json.loads((Path(__file__).parent / "referencia_2026.json").read_text("utf-8"))
TOL = REFERENCIA["tolerancia_euros"]


def _eur(x: float) -> str:
    return f"{x:,.2f}".replace(",", "X").replace(".", ",").replace("X", ".")


def _pct(x: float) -> str:
    return f"{x:g}".replace(".", ",")


def _r(x: float) -> float:
    return round(x + 1e-9, 2)


def _cmp(concepto: str, en_nomina: float | None, esperado: float, explic_ok: str, explic_mal: str,
         que_hacer: str, tol: float = TOL) -> Comprobacion:
    if en_nomina is None:
        return Comprobacion(concepto=concepto, estado="aviso", importe_nomina=None,
                            importe_esperado=_r(esperado),
                            explicacion="No aparece en la nómina o no se ha podido leer.",
                            que_hacer="Comprueba el dato a mano en el documento original.")
    dif = _r(en_nomina - esperado)
    ok = abs(dif) <= tol
    return Comprobacion(
        concepto=concepto,
        estado="ok" if ok else "error",
        importe_nomina=_r(en_nomina),
        importe_esperado=_r(esperado),
        explicacion=explic_ok if ok else f"{explic_mal} Diferencia: {'+' if dif > 0 else ''}{_eur(dif)} €.",
        que_hacer="Nada." if ok else que_hacer,
    )


def basicas(d: DatosNomina) -> list[Comprobacion]:
    """Sumas y líquido: disponibles en Free y Pro."""
    out: list[Comprobacion] = []
    suma_dev = sum(l.importe for l in d.devengos)
    suma_ded = sum(l.importe for l in d.deducciones)
    if d.devengos:
        out.append(_cmp("Suma de devengos", d.total_devengado, suma_dev,
                        "El total devengado coincide con la suma de conceptos.",
                        "El total devengado no cuadra con la suma de los conceptos.",
                        "Pide a la empresa el detalle de cómo se calcula el total devengado."))
    if d.deducciones:
        out.append(_cmp("Suma de deducciones", d.total_deducciones, suma_ded,
                        "El total de deducciones coincide con la suma de conceptos.",
                        "El total de deducciones no cuadra con la suma de los conceptos.",
                        "Pide aclaración sobre las deducciones aplicadas."))
    dev = d.total_devengado if d.total_devengado is not None else suma_dev
    ded = d.total_deducciones if d.total_deducciones is not None else suma_ded
    if d.devengos or d.total_devengado is not None:
        out.append(_cmp("Líquido a percibir", d.liquido, dev - ded,
                        "El líquido es devengado menos deducciones.",
                        "El líquido no es igual a devengado menos deducciones.",
                        "Revisa el ingreso en tu cuenta y reclama la diferencia si cobraste menos."))
    return out


NOMBRES = {
    "contingencias_comunes": "Contingencias comunes",
    "desempleo_indefinido": "Desempleo (indefinido)",
    "desempleo_temporal": "Desempleo (temporal)",
    "formacion_profesional": "Formación profesional",
    "mei": "MEI",
    "horas_extra_fuerza_mayor": "Horas extra (fuerza mayor)",
    "horas_extra_resto": "Horas extra",
}


def _tipo_ref(tipo: str, contrato: str) -> tuple[str, dict] | None:
    c = REFERENCIA["cotizacion_trabajador"]
    if tipo == "desempleo":
        clave = "desempleo_temporal" if contrato == "temporal" else "desempleo_indefinido"
        return clave, c[clave]
    if tipo in c:
        return tipo, c[tipo]
    return None


def completas(d: DatosNomina) -> list[Comprobacion]:
    """Sumas + cotizaciones a la Seguridad Social + IRPF: sólo Pro."""
    out = basicas(d)
    bases = {"base_cc": d.base_cc, "base_cp": d.base_cp}

    for ded in d.deducciones:
        if ded.tipo == "irpf":
            base = ded.base if ded.base is not None else d.base_irpf
            pct = ded.porcentaje if ded.porcentaje is not None else d.pct_irpf
            if base is not None and pct is not None:
                out.append(_cmp(f"IRPF ({_pct(pct)} %)", ded.importe, base * pct / 100,
                                "La retención coincide con base × porcentaje.",
                                "La retención no coincide con base × porcentaje indicado.",
                                "Pide a la empresa el cálculo de la retención (modelo 145 y regularización)."))
            continue
        ref = _tipo_ref(ded.tipo, d.tipo_contrato)
        if not ref:
            continue
        clave, info = ref
        base = ded.base if ded.base is not None else bases.get(info["base"])
        if base is None:
            continue
        nombre = NOMBRES.get(clave, clave)
        out.append(_cmp(f"{nombre} ({_pct(info['pct'])} % sobre {_eur(base)} €)", ded.importe, base * info["pct"] / 100,
                        "El descuento coincide con el tipo legal vigente.",
                        f"El tipo legal del trabajador es {info['pct']} % y el descuento no cuadra.",
                        "Señálalo a RRHH/gestoría: puede ser un error de tipo o de base de cotización."))
        if ded.porcentaje is not None and abs(ded.porcentaje - info["pct"]) > 0.001:
            out.append(Comprobacion(
                concepto=f"Porcentaje aplicado: {nombre}", estado="error",
                importe_nomina=ded.porcentaje, importe_esperado=info["pct"],
                explicacion=f"La nómina aplica {ded.porcentaje} % y el tipo de referencia es {info['pct']} %.",
                que_hacer="Pregunta por qué se aplica un porcentaje distinto."))

    tope = REFERENCIA["base_maxima_mensual"]["importe"]
    if tope and d.base_cc and d.base_cc > tope + TOL:
        out.append(Comprobacion(
            concepto="Base de cotización máxima", estado="aviso", importe_nomina=d.base_cc,
            importe_esperado=tope,
            explicacion="La base de contingencias comunes supera el tope mensual de referencia.",
            que_hacer="Verifica el tope del año en curso; por encima de él no se cotiza (salvo cuota de solidaridad)."))
    return out


def para_plan(nivel: str, d: DatosNomina) -> list[Comprobacion]:
    return completas(d) if nivel == "completas" else basicas(d)
