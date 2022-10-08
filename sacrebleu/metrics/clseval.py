# Copyright 2017 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"). You may not
# use this file except in compliance with the License. A copy of the License
# is located at
#
#     http://aws.amazon.com/apache2.0/
#
# or in the "license" file accompanying this file. This file is distributed on
# an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
# express or implied. See the License for the specific language governing
# permissions and limitations under the License.

# -*- coding: utf-8 -*-

"""
This work is based on:
  Macro-average: Rare Types Are Important Too
    Gowda et al (NAACL 2021)
    https://aclanthology.org/2021.naacl-main.90/
"""

from itertools import zip_longest
from pathlib import Path
from collections import Counter
from re import S
from typing import Union, Iterable, List, Dict, Tuple, Sequence, Optional
import json

from .base import Metric, Score, Signature
from .bleu import BLEU, sacrelogger

DEF_F_BETA = 1
DEF_AVERAGE = 'macro'
DEF_SMOOTH_VAL = 1


class ClassMeasure(Score):
    __slots__ = 'preds', 'refs', 'correct', 'measure_name', 'name'

    def __init__(self, name, preds=0, refs=0, correct=0, measure_name='f1'):
        self.preds = preds
        self.refs = refs
        self.correct = correct
        self.measure_name = measure_name
        super().__init__(name=name, score=self.measure(measure_name))
 
    @property
    def precision(self) -> float:
        assert 0 <= self.correct <= self.preds
        # Note: zero correct while zero are predicted is perfect precision
        return (self.correct / self.preds) if self.preds > 0 else 1

    @property
    def recall(self) -> float:
        assert 0 <= self.correct <= self.refs
        # Note: zero correct while zero reference is perfect recall
        return (self.correct / self.refs) if self.refs > 0 else 1

    def f_measure(self, beta: float = 1) -> float:
        denr = beta ** 2 * self.precision + self.recall
        if denr == 0:
            # Note: either zero precision or zero recall leads to zero f1
            return 0
        return (1 + beta ** 2) * self.precision * self.recall / denr

    @property
    def f1(self) -> float:
        return self.f_measure(beta=1)     

    def refresh(self):
        self.score = self.measure(self.measure_name)

    def measure(self, measure_name):
        cache = dict(f1=self.f1, precision=self.precision, recall=self.recall)
        if measure_name in cache:
            return cache[measure_name]
        elif measure_name.startswith('f'):
            beta = float(measure_name[1:])
            return self.f_measure(beta=beta)
        else:
            raise Exception(f'Unknown measure name : {measure_name}')

    def __str__(self):
        return f'ClassMeasure[{self.name}, pred/cor/ref={self.preds}/{self.correct}/{self.refs} ' \
               f'P/R/F1={self.precision:g}/{self.recall:g}/{self.f1:g}]'

    def format(self, width=4, score_only=False, signature='', is_json: bool = False) -> str:
        if score_only:
            return f'{self.score:.{width}f}'
        prefix = self.name
        if signature:
            prefix += f'+{signature}'
        return f'{prefix} {self.score:.{width}f}'


AVG_TYPES = {
    'macro': lambda _: 1,
    'micro': lambda f: f,  # term frequency
    #    'micro_sqrt': lambda f: math.sqrt(f),
    #    'micro_log': lambda f: 1 + math.log(f),
    #    'micro_inv': lambda f: 1 / f,  # inverted frequency
}


class ClassifierEvalSignature(Signature):

    def __init__(self, args):
        super().__init__(args)
        self._abbr.update({
            'case': 'c',
            'tok': 'tok',
            'smooth': 's',
            'average': 'a',
            'ngram': 'ng'
        })

        self.info.update({
            'case': 'lc' if args['lowercase'] else 'mixed',
            'tok': args['tokenizer_signature'],
            'average': args['average'],
            'ngram': args['max_ngram_order'],
            'smooth': f'{args["smooth_value"]}.{args["smooth_method"]}'
        })

        ##=======
        # smoothing does not apply to macro average
        if ["average"] == 'macro':
            del self.info['smooth']
        if args["average"] in ('macro', 'micro'):
            # these are common and hence part of name e.g. MacroF, MicroF
            del self.info['average']


class MultiClassMeasure(Score):
    """
    Consolidates multiple ClassMeasure s into single measure
    """

    def __init__(self, classes: List[ClassMeasure], average='macro', f_beta=1,
                 smooth_value=0, percent=True, hyp_len=None, ref_len=None, signature=''):
        self.smooth_value = smooth_value
        self.classes = classes
        self.percent = percent
        self.signature = signature

        wt_func = AVG_TYPES[average]
        wt_scores = [(m.f_measure(beta=f_beta), wt_func(m.refs + smooth_value))
                     for m in classes]
        f_score = sum(score * w for score, w in wt_scores) / sum(w for _, w in wt_scores)
        scaler = 100 if percent else 1
        f_score *= scaler
        name = 'F{beta:g}'.format(beta=f_beta)
        if average in ('macro', 'micro'):
            name = average.title() + name  # eg MacroF1 MicroF1 MacroF2 ...
        super().__init__(name=name, score=f_score)

        # extra info
        self.hyp_len = hyp_len
        self.ref_len = ref_len
        self.avgs = {}
        for n in ('precision', 'recall'):
            wt_scores = [(m.measure(measure_name=n.lower()), wt_func(m.refs + smooth_value))
                         for m in classes]
            norm = sum(w for score, w in wt_scores)
            self.avgs[n] = scaler * sum(score * w for score, w in wt_scores) / norm
        

    def __str__(self):
        return self.format()

    def format(self, width=2, score_only=False, signature='', is_json: bool = False) -> str:
        res = super().format(width=width, score_only=score_only, signature=signature, is_json=is_json)
        extra = dict(precision=round(self.avgs['precision'], width),
                     recall=round(self.avgs['recall'], width),
                     len_ratio=round(self.hyp_len / self.ref_len, max(width, 3)) if self.ref_len else -1,
                     hyp_len=self.hyp_len,
                     ref_len=self.ref_len)
        verbose_score = ' '.join(f'{k} = {v}' for k, v in extra.items())
        if score_only:
            pass
        elif is_json:
            res = json.loads(res)
            res.update(extra)
            res['verbose_score'] = verbose_score
            res = json.dumps(res, indent=1, ensure_ascii=False)
        else:
            res += ' ' + verbose_score
        return res

    def write_report(self, path):
        if isinstance(path, str):
            path = Path(path)
        scaler, width = 1, 4
        if self.percent:
            scaler, width = 100, 2

        # sort by ascending of ngram, descending of ref_freq, descending of hyp_freq
        class_stats: List[ClassMeasure] = sorted(self.classes, reverse=True,
                                                 key=lambda s: (s.refs, s.preds))
        delim = '\t'
        ljust = 15

        def format_class_stat(class_: ClassMeasure):
            row = [" ".join(class_.name).ljust(ljust), f"{class_.score * scaler:.{width}f}"]
            row += [str(x) for x in [class_.refs, class_.preds, class_.correct]]
            row += [f'{class_.measure(measure_name=x) * scaler:.{width}f}'
                    for x in 'f1 precision recall'.split()]
            return delim.join(row)

        with path.open('w', encoding='utf-8', errors='ignore') as out:
            header = ['Type'.ljust(ljust), 'Score', 'Refs', 'Preds', 'Match', 'F1', 'Precisn',
                      'Recall']
            out.write(self.format(width=width, signature='') + '\n')
            out.write(str(self.signature) + '\n')
            out.write('\n----\n')
            out.write(delim.join(header) + '\n')
            for cs in class_stats:
                out.write(format_class_stat(cs) + '\n')


class ClassifierEval(Metric):

    DEF_F_BETA = DEF_F_BETA
    _SIGNATURE_TYPE = ClassifierEvalSignature
    TOKENIZER_DEFAULT = BLEU.TOKENIZER_DEFAULT
    TOKENIZERS = BLEU.TOKENIZERS
    DEF_SMOOTH_VAL = DEF_SMOOTH_VAL

    def __init__(self, average: str, smooth_value: float = DEF_SMOOTH_VAL,
                    max_ngram_order: int = 1, beta: float = DEF_F_BETA,
                    lowercase: bool = False, tokenize: Optional[str] = BLEU.TOKENIZER_DEFAULT,
                    trg_lang: str = '', force: bool = False,
                    references: Optional[Sequence[Sequence[str]]] = None):

        super().__init__()
        assert average in ('macro', 'micro')
        assert average in AVG_TYPES, f'{average} is invalid; use:{list(AVG_TYPES.keys())}'
        assert max_ngram_order == 1  # only unigrams are used for now; n > 1 is for future work
        self.average = average
        self.lowercase = lowercase
        self.smooth_method = 'add-k'
        self.weight_func = AVG_TYPES[self.average]
        self.max_ngram_order = max_ngram_order
        self.smooth_value = smooth_value
        self.f_beta = beta
        self.references = references
        self._force = force
        self.trg_lang = trg_lang
        self.force = force

        # some of functionality is delegated to BLEU TODO: delegate more, avoid repetition
        self._bleu_delegate = BLEU(lowercase=lowercase, force=force, tokenize=tokenize, smooth_method=self.smooth_method,
                                   smooth_value=smooth_value, max_ngram_order=max_ngram_order, trg_lang=trg_lang)
        # Create the tokenizer
        self.tokenizer = self._bleu_delegate.tokenizer
        # Build the signature
        self.tokenizer_signature = self._bleu_delegate.tokenizer_signature

        if references is not None:
            # Pre-compute reference ngrams and lengths
            self._ref_cache = self._cache_references(references)
        else:
            self.num_refs = 1  # default

    def corpus_score(self, sys_stream: Union[str, Iterable[str]],
                     references=None, n_bootstrap=1) -> MultiClassMeasure:
        """Produces Multi-class evaluation score from a source against one or more references.

        :param sys_stream: The system stream (a sequence of segments)
        :param references: A list of one or more reference streams (each a sequence of segments)
        :return: a MultiClassMeasure object containing everything you'd want
        """
        assert n_bootstrap == 1, f'Bootstrap sampling is not supported for this metric yet.'
        references = references or self.references

        lines = self._prepare_lines(sys_stream, references)
        m_name = f'f{self.f_beta}'
        gram_stats, ref_len, hyp_len = self.n_gram_performance(lines, self.max_ngram_order, measure_name=m_name)

        class_measures: List[ClassMeasure] = list(gram_stats.values())
        max_oder = 0
        for class_meas in class_measures:
            assert isinstance(class_meas.name, str)
            class_meas.name = tuple(
                class_meas.name.split())  # convert space separated ngram string to tuple
            max_oder = max(max_oder, len(class_meas.name))
        assert max_oder == 1  # only unigrams for now

        score = MultiClassMeasure(classes=class_measures, f_beta=self.f_beta, percent=True,
                                  average=self.average, smooth_value=self.smooth_value,
                                  hyp_len=hyp_len, ref_len=ref_len, signature=self.get_signature())
        return score

    @classmethod
    def n_gram_performance(cls, lines: Iterable[List[str]], max_ngram_order: int, measure_name='f1') \
            -> Tuple[Dict[str, ClassMeasure], int, int]:
        """
        Gets n-gram performance by comparing system output against 1 or more references
        :param lines:  iterator of [output, ref1 ...] where output and ref1,... are tokenized lines
        :param max_ngram_order: maximum n_grams order
        :return: gram_performance, ref_len, sys_len
        """
        assert max_ngram_order >= 1
        sys_len, ref_len = 0, 0
        gram_stats = {}
        for output, *refs in lines:
            out_toks = output.split()
            ref_ngrams, closest_diff, closest_len = cls.reference_stats(
                refs=refs, output_len=len(out_toks), max_order=max_ngram_order)
            sys_len += len(out_toks)
            ref_len += closest_len

            sys_ngrams = cls.extract_ngrams(output, max_order=max_ngram_order)
            for ngram in sys_ngrams.keys():  # n-grams that are recalled by sys
                if ngram not in gram_stats:
                    gram_stats[ngram] = ClassMeasure(name=ngram, measure_name=measure_name)
                gram_stats[ngram].preds += sys_ngrams[ngram]
                gram_stats[ngram].correct += min(sys_ngrams[ngram], ref_ngrams.get(ngram, 0))
                gram_stats[ngram].refs += ref_ngrams.get(ngram, 0)

            for ngram in ref_ngrams.keys() - sys_ngrams.keys():  # n-grams that are not recalled by sys
                if ngram not in gram_stats:
                    gram_stats[ngram] = ClassMeasure(name=ngram, measure_name=measure_name)
                gram_stats[ngram].refs += ref_ngrams[ngram]
                # .cand and .match are zero by default

        # refresh score in each class
        for cls_meas in gram_stats.values():
            cls_meas.refresh()

        return gram_stats, ref_len, sys_len

    def _prepare_lines(self, hyps, refs):
        # Add some robustness to the input arguments
        if isinstance(hyps, str):
            hyps = [hyps]
        if isinstance(refs, str):
            refs = [[refs]]
        tokenized_count = 0  # look for already-tokenized sentences
        fhs = [hyps] + refs
        for lines in zip_longest(*fhs):
            if None in lines:
                raise EOFError("Source and reference streams have different lengths!")

            if not self.force and lines[0].rstrip().endswith(' .'):
                tokenized_count += 1
                if tokenized_count == 100:
                    msg = """"That's 100 lines that end in a tokenized period (' .')
                    It looks like you forgot to detokenize your test data, which may hurt your score.
                    If you insist your data is detokenized, or don't care, you can suppress this message with '--force'."""
                    sacrelogger.warning(msg)

            lines = [self._preprocess_segment(x) for x in lines]
            yield lines

    @classmethod
    def reference_stats(cls, refs, output_len, max_order=1):
        """Extracts reference statistics for a given segment.

        :param refs: A list of segment tokens.
        :param output_len: Hypothesis length for this segment.
        :return: a tuple of (ngrams, closest_diff, closest_len)
        """

        ngrams = Counter()
        closest_diff = None
        closest_len = None

        for ref in refs:
            tokens = ref.split()
            reflen = len(tokens)
            diff = abs(output_len - reflen)
            if closest_diff is None or diff < closest_diff:
                closest_diff = diff
                closest_len = reflen
            elif diff == closest_diff:
                if reflen < closest_len:
                    closest_len = reflen

            ngrams_ref = cls.extract_ngrams(ref, max_order=max_order)
            for ngram in ngrams_ref.keys():
                ngrams[ngram] = max(ngrams[ngram], ngrams_ref[ngram])

        return ngrams, closest_diff, closest_len

    @classmethod
    def extract_ngrams(cls, line, min_order=1, max_order=4) -> Counter:
        """Extracts all the ngrams (min_order <= n <= max_order) from a sequence of tokens.

        :param line: A segment containing a sequence of words.
        :param min_order: Minimum n-gram length (default: 1).
        :param max_order: Maximum n-gram length (default: NGRAM_ORDER).
        :return: a dictionary containing ngrams and counts
        """

        ngrams = Counter()  # type: Counter
        tokens = line.split()
        for n in range(min_order, max_order + 1):
            for i in range(0, len(tokens) - n + 1):
                ngram = ' '.join(tokens[i: i + n])
                ngrams[ngram] += 1

        return ngrams

    #############
    ## New API
    #############
    def _aggregate_and_compute(self, *args, **kwargs):
        raise NotImplementedError()

    def _compute_score_from_stats(self, *args, **kwargs):
        raise NotImplementedError()

    def _compute_segment_statistics(self, *args, **kwargs):
        raise NotImplementedError()

    def _extract_reference_info(self, *args, **kwargs):
        return self._bleu_delegate._extract_reference_info(*args, **kwargs)

    def _preprocess_segment(self, *args, **kwargs):
        return self._bleu_delegate._preprocess_segment(*args, **kwargs)
