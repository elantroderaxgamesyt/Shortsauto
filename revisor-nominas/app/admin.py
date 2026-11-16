"""Herramientas de administración.

  python -m app.admin codigo --creditos 3        # código con 3 revisiones Pro
  python -m app.admin codigo --dias 30 -n 10     # 10 códigos de 30 días de Pro
"""
import argparse

from . import cuentas


def main() -> None:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("codigo", help="crear códigos de canje")
    c.add_argument("--creditos", type=int, default=0)
    c.add_argument("--dias", type=int, default=0)
    c.add_argument("-n", type=int, default=1)
    a = ap.parse_args()
    if a.cmd == "codigo":
        if not a.creditos and not a.dias:
            ap.error("indica --creditos o --dias")
        for _ in range(a.n):
            print(cuentas.crear_codigo(a.creditos, a.dias))


if __name__ == "__main__":
    main()
