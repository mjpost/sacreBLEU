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
from sacrebleu import corpus_macrof, corpus_microf

EPSILON = 1e-9


def test_clseval():
    refs = ['the cat sat on the mat', 'ಬಾ ಬಾ ಗಿಣಿಯೇ ಬಣ್ಣದ ಗಿಣಿಯೇ ಹಣ್ಣನು ಕೊಡುವೆನು ಬಾ ಬಾ']
    refss = [refs]
    assert abs(corpus_macrof(refs, refss).score - 100.0) < EPSILON
    assert abs(corpus_microf(refs, refss).score - 100.0) < EPSILON

    hyps = ['cat sat on mat it', 'the ಗಿಣಿಯೇ ಬಣ್ಣದ ಹಣ್ಣನು ಕೊಡುವೆನು ಬಾ']
    """ total classes 10 + 1 : 
             the (2), cat (1), sat (1), on (1), mat (1), ಬಾ (4), ಗಿಣಿಯೇ (2), ಬಣ್ಣದ (1), ಹಣ್ಣನು (1),
             ಕೊಡುವೆನು (1), it (0)         
    """
    # ['Type', 'Refs', 'Preds', 'Match', "Precision", 'Recall', "F1"],
    stats = [
        ['the',       2,      1,        0,         0,         0,     0],
        ['cat',       1,      1,        1,         1,         1,     1],
        ['sat',       1,      1,        1,         1,         1,     1],
        ['on',        1,      1,        1,         1,         1,     1],
        ['mat',       1,      1,        1,         1,         1,     1],
        ['it',        0,      1,        0,         0,         1,     0],
        ['ಬಾ',        4,      1,        1,         1,       .25,  2*1*.25/(1+.25)],
        ['ಗಿಣಿಯೇ',    2,      1,        1,         1,       .50,   2*1*.50/(1+.50)],
        ['ಬಣ್ಣದ',     1,      1,        1,          1,         1,     1],
        ['ಹಣ್ಣನು',     1,      1,       1,          1,         1,     1],
        ['ಕೊಡುವೆನು',   1,     1,        1,         1,          1,     1],
    ]

    smooth_value = 1   # small smoothing value
    idx_refs, idx_f1 = 1, -1
    macro_expected = 100 * sum(r[idx_f1] for r in stats) / len(stats)
    # Frequencies for micro avg are always from references; so we can compare different hyps
    norm = sum(smooth_value + r[idx_refs] for r in stats)
    micro_expected = 100 * sum((smooth_value + r[idx_refs]) * r[idx_f1] for r in stats) / norm

    assert abs(micro_expected - macro_expected) > 1000 * EPSILON  # they are different

    macro_score = corpus_macrof(hyps, refss)
    assert abs(macro_score.score - macro_expected) < EPSILON


    micro_score = corpus_microf(hyps, refss, smooth_value=smooth_value)
    assert abs(micro_score.score - micro_expected) < EPSILON

    infinity = 1E12     # using a large smoothing_value => micro approaches macro
    micro_score2 = corpus_microf(hyps, refss, smooth_value=infinity)
    assert abs(micro_score2.score - macro_expected) < EPSILON  # they are same


if __name__ == '__main__':
    test_clseval()
