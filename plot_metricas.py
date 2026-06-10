#!/usr/bin/env python3
"""
Plota a melhoria dos casos de tuning a partir de metricas_casos.csv.

Uso:
    pip install matplotlib
    python plot_metricas.py                # salva metricas_casos.png e abre a janela
    python plot_metricas.py --no-show      # só salva o PNG (útil em CI/headless)

Depende apenas de matplotlib (numpy vem junto com ele). O CSV está em
formato largo (1 linha por caso) com colunas:
    caso, titulo, tecnologia,
    linhas_antes, linhas_depois, tempo_antes_ms, tempo_depois_ms, observacao
"""

import argparse
import csv
import math
from pathlib import Path

import matplotlib.pyplot as plt

CSV_PATH = Path(__file__).with_name("metricas_casos.csv")
NAN = float("nan")

ANTES_COR = "#c0504d"   # vermelho — antes
DEPOIS_COR = "#4f81bd"  # azul — depois
GANHO_COR = "#9bbb59"   # verde — fator (linhas)
GANHO_COR2 = "#8064a2"  # roxo — fator (tempo)


def to_float(s):
    s = (s or "").strip()
    if s == "":
        return NAN
    try:
        return float(s)
    except ValueError:
        return NAN


def isnan(v):
    return v is None or (isinstance(v, float) and math.isnan(v))


def fmt_num(v):
    """3.84M, 12.3k, 1591, n/d."""
    if isnan(v):
        return "n/d"
    v = float(v)
    if v >= 1_000_000:
        return f"{v / 1_000_000:.2f}M"
    if v >= 1_000:
        return f"{v / 1_000:.1f}k"
    if v >= 1:
        return f"{v:.0f}"
    return f"{v:g}"


def fmt_ms(v):
    """Humaniza milissegundos com unidade automática:
    1_260_000 -> '21min', 11_607 -> '11.6s', 770 -> '770ms', 0.12 -> '0.12ms'."""
    if isnan(v):
        return "n/d"
    v = float(v)

    def _trim(x):
        # 21.0 -> '21', 1.5 -> '1.5'
        return f"{x:.1f}".rstrip("0").rstrip(".")

    if v >= 3_600_000:          # >= 1 h
        return f"{_trim(v / 3_600_000)}h"
    if v >= 60_000:             # >= 1 min
        return f"{_trim(v / 60_000)}min"
    if v >= 1_000:              # >= 1 s
        return f"{_trim(v / 1_000)}s"
    if v >= 1:
        return f"{v:.0f}ms"
    return f"{v:g}ms"


def _annotate(ax, barras, valores, fmt):
    for rect, val in zip(barras, valores):
        if isnan(val):
            ax.annotate("n/d", (rect.get_x() + rect.get_width() / 2, 1),
                        ha="center", va="bottom", fontsize=8, color="gray")
        else:
            ax.annotate(fmt(val),
                        (rect.get_x() + rect.get_width() / 2, rect.get_height()),
                        ha="center", va="bottom", fontsize=8)


def barras_antes_depois(ax, labels, antes, depois, titulo, ylabel, fmt):
    x = list(range(len(labels)))
    w = 0.38
    # escala log ignora NaN (a barra simplesmente não é desenhada)
    b1 = ax.bar([i - w / 2 for i in x], antes, w, label="Antes", color=ANTES_COR)
    b2 = ax.bar([i + w / 2 for i in x], depois, w, label="Depois", color=DEPOIS_COR)
    ax.set_yscale("log")
    ax.set_title(titulo, fontweight="bold")
    ax.set_ylabel(ylabel)
    ax.set_xticks(x)
    ax.set_xticklabels(labels)
    ax.legend()
    ax.grid(axis="y", which="both", linestyle=":", alpha=0.4)
    _annotate(ax, b1, antes, fmt)
    _annotate(ax, b2, depois, fmt)


def barras_ganho(ax, labels, fator_linhas, fator_tempo):
    x = list(range(len(labels)))
    w = 0.38
    b1 = ax.bar([i - w / 2 for i in x], fator_linhas, w, label="Linhas lidas", color=GANHO_COR)
    b2 = ax.bar([i + w / 2 for i in x], fator_tempo, w, label="Tempo", color=GANHO_COR2)
    ax.set_yscale("log")
    ax.set_title("Fator de melhoria (antes ÷ depois)", fontweight="bold")
    ax.set_ylabel("vezes menor (log)")
    ax.set_xticks(x)
    ax.set_xticklabels(labels)
    ax.legend()
    ax.grid(axis="y", which="both", linestyle=":", alpha=0.4)
    fmt_x = lambda v: ("n/d" if isnan(v) else f"{v:,.0f}×".replace(",", "."))
    _annotate(ax, b1, fator_linhas, fmt_x)
    _annotate(ax, b2, fator_tempo, fmt_x)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--no-show", action="store_true", help="só salva o PNG")
    parser.add_argument("--out", default=str(CSV_PATH.with_suffix(".png")))
    args = parser.parse_args()

    with open(CSV_PATH, encoding="utf-8") as f:
        rows = list(csv.DictReader(f))

    labels = [f"{int(r['caso']):03d}" for r in rows]
    titulos = [r["titulo"] for r in rows]
    linhas_antes = [to_float(r["linhas_antes"]) for r in rows]
    linhas_depois = [to_float(r["linhas_depois"]) for r in rows]
    tempo_antes = [to_float(r["tempo_antes_ms"]) for r in rows]
    tempo_depois = [to_float(r["tempo_depois_ms"]) for r in rows]

    def fator(a, d):
        return (a / d) if (not isnan(a) and not isnan(d) and d) else NAN

    fator_linhas = [fator(a, d) for a, d in zip(linhas_antes, linhas_depois)]
    fator_tempo = [fator(a, d) for a, d in zip(tempo_antes, tempo_depois)]

    fig, axes = plt.subplots(1, 3, figsize=(16, 6))
    fig.suptitle("Tuning — antes × depois por caso", fontsize=15, fontweight="bold")

    barras_antes_depois(axes[0], labels, linhas_antes, linhas_depois,
                        "Linhas lidas no plano", "linhas (log)", fmt_num)
    barras_antes_depois(axes[1], labels, tempo_antes, tempo_depois,
                        "Tempo de execução", "tempo (escala log)", fmt_ms)
    barras_ganho(axes[2], labels, fator_linhas, fator_tempo)

    legenda = "   |   ".join(f"{lbl}: {t}" for lbl, t in zip(labels, titulos))
    fig.text(0.5, 0.01, legenda, ha="center", fontsize=8, color="#444")

    fig.tight_layout(rect=(0, 0.04, 1, 0.95))
    fig.savefig(args.out, dpi=130)
    print(f"Gráfico salvo em: {args.out}")

    if not args.no_show:
        plt.show()


if __name__ == "__main__":
    main()
