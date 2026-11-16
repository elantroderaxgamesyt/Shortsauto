"""Esquemas de datos que devuelve la IA (salida estructurada) y la API."""
from __future__ import annotations

from typing import List, Literal, Optional

from pydantic import BaseModel

Estado = Literal["ok", "aviso", "error"]
Veredicto = Literal["correcta", "revisar", "incorrecta", "ilegible"]

TipoDeduccion = Literal[
    "contingencias_comunes",
    "desempleo",
    "formacion_profesional",
    "mei",
    "horas_extra",
    "irpf",
    "anticipo",
    "otra",
]


class Linea(BaseModel):
    concepto: str
    importe: float


class Deduccion(BaseModel):
    concepto: str
    tipo: TipoDeduccion
    porcentaje: Optional[float]
    base: Optional[float]
    importe: float


class DatosNomina(BaseModel):
    """Lo que la IA lee de la nómina. Los datos personales van enmascarados."""

    empresa: Optional[str]
    trabajador: Optional[str]
    categoria: Optional[str]
    convenio: Optional[str]
    periodo: Optional[str]
    tipo_contrato: Literal["indefinido", "temporal", "desconocido"]
    devengos: List[Linea]
    deducciones: List[Deduccion]
    total_devengado: Optional[float]
    total_deducciones: Optional[float]
    liquido: Optional[float]
    base_cc: Optional[float]
    base_cp: Optional[float]
    base_irpf: Optional[float]
    pct_irpf: Optional[float]


class Punto(BaseModel):
    concepto: str
    estado: Estado
    explicacion: str


class InformeFree(BaseModel):
    veredicto: Veredicto
    resumen: str
    puntos: List[Punto]
    datos: DatosNomina


class Comprobacion(BaseModel):
    concepto: str
    estado: Estado
    importe_nomina: Optional[float]
    importe_esperado: Optional[float]
    explicacion: str
    que_hacer: str


class InformePro(BaseModel):
    veredicto: Veredicto
    resumen: str
    comprobaciones: List[Comprobacion]
    explicacion_conceptos: List[Punto]
    recomendaciones: List[str]
    preguntas_para_rrhh: List[str]
    borrador_reclamacion: Optional[str]
    confianza: Literal["alta", "media", "baja"]
    limitaciones: str
    datos: DatosNomina
