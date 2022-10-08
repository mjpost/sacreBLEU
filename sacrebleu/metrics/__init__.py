"""The implementation of various metrics."""

from functools import partial
from .bleu import BLEU, BLEUScore   # noqa: F401
from .chrf import CHRF, CHRFScore   # noqa: F401
from .ter import TER, TERScore      # noqa: F401
from .clseval import ClassifierEval, MultiClassMeasure


METRICS = {
    'BLEU': BLEU,
    'CHRF': CHRF,
    'TER': TER,
}

METRICS['MACROF'] = partial(ClassifierEval, average='macro', max_ngram_order=1)
METRICS['MICROF'] = partial(ClassifierEval, average='micro', max_ngram_order=1)
