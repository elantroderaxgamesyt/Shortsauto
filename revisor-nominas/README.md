# Revisor de nóminas con IA

App web que revisa nóminas españolas. Subes el PDF o una foto y **Nora**, una asesora
laboral con IA (Claude), te dice qué está bien, qué está mal y qué hacer; después puedes
preguntarle dudas en un chat.

Proyecto independiente del resto del repositorio.

## Dos versiones

| | Free | Pro |
|---|---|---|
| Veredicto y resumen | ✅ | ✅ |
| Puntos del informe | 5 más importantes | Revisión concepto a concepto |
| Cálculos que rehace la app | Sumas y líquido | + cada cotización a la SS e IRPF |
| Explicación de cada línea | — | ✅ |
| Preguntas para RRHH y borrador de reclamación | — | ✅ |
| Chat con Nora | 3 preguntas | Ilimitado |
| Informe imprimible / PDF | — | ✅ |
| Esfuerzo de la IA | `low` | `high` |

Los límites están en `app/planes.py`.

## Cómo funciona

1. La IA lee la nómina (PDF o imagen) y devuelve un JSON con estructura fija
   (`app/modelos.py`): datos extraídos + valoración.
2. La app **recalcula los números por su cuenta** (`app/comprobaciones.py`): sumas,
   líquido, y en Pro cada cotización con los tipos de `app/referencia_2026.json`.
   Así el informe no depende sólo de lo que diga la IA.
3. El chat recibe el informe como contexto y responde en streaming.

## Arrancar

```bash
cd revisor-nominas
pip install -r requirements.txt
export ANTHROPIC_API_KEY=...        # sin clave arranca en modo demo con un informe de ejemplo
uvicorn app.main:app --reload
# abre http://localhost:8000
```

Variables opcionales:

- `NOMINAS_CODIGOS_PRO="cod1,cod2"`: exige un código para usar Pro. Vacío = Pro abierto (prototipo).
- `NOMINAS_MODELO`: modelo de Claude (por defecto `claude-opus-5-5`).

## Tests

```bash
python -m pytest -q tests
```

## Antes de publicar

- **Revisa `app/referencia_2026.json`**: base máxima y SMI están marcados `verificado: false`.
- Pagos/cuentas reales para Pro (ahora es un código de acceso).
- Texto legal: privacidad (RGPD, la nómina tiene datos personales) y aviso de que no es asesoramiento profesional.
