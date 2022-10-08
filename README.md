# sacreBLEU

[![PyPI version](https://img.shields.io/pypi/v/sacrebleu)](https://img.shields.io/pypi/v/sacrebleu)
[![Python version](https://img.shields.io/pypi/pyversions/sacrebleu)](https://img.shields.io/pypi/pyversions/sacrebleu)
[![GitHub issues](https://img.shields.io/github/issues/mjpost/sacreBLEU.svg)](https://github.com/mjpost/sacrebleu/issues)

SacreBLEU ([Post, 2018](http://aclweb.org/anthology/W18-6319)) provides hassle-free computation of shareable, comparable, and reproducible **BLEU** scores.
Inspired by Rico Sennrich's `multi-bleu-detok.perl`, it produces the official WMT scores but works with plain text.
It also knows all the standard test sets and handles downloading, processing, and tokenization for you.

The official version is hosted at <https://github.com/mjpost/sacrebleu>.

# Motivation

Comparing BLEU scores is harder than it should be. Every decoder has its own implementation, often borrowed from Moses, but maybe with subtle changes.
Moses itself has a number of implementations as standalone scripts, with little indication of how they differ (note: they mostly don't, but `multi-bleu.pl` expects tokenized input). Different flags passed to each of these scripts can produce wide swings in the final score. All of these may handle tokenization in different ways. On top of this, downloading and managing test sets is a moderate annoyance.

Sacre bleu! What a mess.

**SacreBLEU** aims to solve these problems by wrapping the original reference implementation ([Papineni et al., 2002](https://www.aclweb.org/anthology/P02-1040.pdf)) together with other useful features.
The defaults are set the way that BLEU should be computed, and furthermore, the script outputs a short version string that allows others to know exactly what you did.
As an added bonus, it automatically downloads and manages test sets for you, so that you can simply tell it to score against `wmt14`, without having to hunt down a path on your local file system.
It is all designed to take BLEU a little more seriously.
After all, even with all its problems, BLEU is the default and---admit it---well-loved metric of our entire research community.
Sacre BLEU.

# Features

- It automatically downloads common WMT test sets and processes them to plain text
- It produces a short version string that facilitates cross-paper comparisons
- It properly computes scores on detokenized outputs, using WMT ([Conference on Machine Translation](http://statmt.org/wmt17)) standard tokenization
- It produces the same values as the official script (`mteval-v13a.pl`) used by WMT
- It outputs the BLEU score without the comma, so you don't have to remove it with `sed` (Looking at you, `multi-bleu.perl`)
- It supports different tokenizers for BLEU including support for Japanese and Chinese
- It supports **chrF, chrF++** and **Translation error rate (TER)** metrics
- It performs paired bootstrap resampling and paired approximate randomization tests for statistical significance reporting

# Breaking Changes

## v2.0.0

As of v2.0.0, the default output format is changed to `json` for less painful parsing experience. This means that software that parse the output of sacreBLEU should be modified to either (i) parse the JSON using for example the `jq` utility or (ii) pass `-f text` to sacreBLEU to preserve the old textual output. The latter change can also be made **persistently** by exporting `SACREBLEU_FORMAT=text` in relevant shell configuration files.

Here's an example of parsing the `score` key of the JSON output using `jq`:

```
$ sacrebleu -i output.detok.txt -t wmt17 -l en-de | jq -r .score
20.8
```

# Installation

Install the official Python module from PyPI (**Python>=3.6 only**):

    pip install sacrebleu

In order to install Japanese tokenizer support through `mecab-python3`, you need to run the
following command instead, to perform a full installation with dependencies:

    pip install "sacrebleu[ja]"

In order to install Korean tokenizer support through `pymecab-ko`, you need to run the
following command instead, to perform a full installation with dependencies:

    pip install "sacrebleu[ko]"

# Command-line Usage

You can get a list of available test sets with `sacrebleu --list`. Please see [DATASETS.md](DATASETS.md)
for an up-to-date list of supported datasets. You can also list available test sets for a given language pair
with `sacrebleu --list -l en-fr`.

## Basics

### Downloading test sets

Downloading is triggered when you request a test set. If the dataset is not available, it is downloaded
and unpacked.

E.g., you can use the following commands to download the source, pass it through your translation system
in `translate.sh`, and then score it:

```
$ sacrebleu -t wmt17 -l en-de --echo src > wmt17.en-de.en
$ cat wmt17.en-de.en | translate.sh | sacrebleu -t wmt17 -l en-de
```

### JSON output

As of version `>=2.0.0`, sacreBLEU prints the computed scores in JSON format to make parsing less painful:

```
$ sacrebleu -i output.detok.txt -t wmt17 -l en-de
```

```json
{
 "name": "BLEU",
 "score": 20.8,
 "signature": "nrefs:1|case:mixed|eff:no|tok:13a|smooth:exp|version:2.0.0",
 "verbose_score": "54.4/26.6/14.9/8.7 (BP = 1.000 ratio = 1.026 hyp_len = 62880 ref_len = 61287)",
 "nrefs": "1",
 "case": "mixed",
 "eff": "no",
 "tok": "13a",
 "smooth": "exp",
 "version": "2.0.0"
}
```

If you want to keep the old behavior, you can pass `-f text` or export `SACREBLEU_FORMAT=text`:

```
$ sacrebleu -i output.detok.txt -t wmt17 -l en-de -f text
BLEU|nrefs:1|case:mixed|eff:no|tok:13a|smooth:exp|version:2.0.0 = 20.8 54.4/26.6/14.9/8.7 (BP = 1.000 ratio = 1.026 hyp_len = 62880 ref_len = 61287)
```

### Scoring

(All examples below assume old-style text output for a compact representation that save space)

Let's say that you just translated the `en-de` test set of WMT17 with your fancy MT system and the **detokenized** translations are in a file called `output.detok.txt`:

```
# Option 1: Redirect system output to STDIN
$ cat output.detok.txt | sacrebleu -t wmt17 -l en-de
BLEU|nrefs:1|case:mixed|eff:no|tok:13a|smooth:exp|version:2.0.0 = 20.8 54.4/26.6/14.9/8.7 (BP = 1.000 ratio = 1.026 hyp_len = 62880 ref_len = 61287)

# Option 2: Use the --input/-i argument
$ sacrebleu -t wmt17 -l en-de -i output.detok.txt
BLEU|nrefs:1|case:mixed|eff:no|tok:13a|smooth:exp|version:2.0.0 = 20.8 54.4/26.6/14.9/8.7 (BP = 1.000 ratio = 1.026 hyp_len = 62880 ref_len = 61287)
```

You can obtain a short version of the signature with `--short/-sh`:

```
$ sacrebleu -t wmt17 -l en-de -i output.detok.txt -sh
BLEU|#:1|c:mixed|e:no|tok:13a|s:exp|v:2.0.0 = 20.8 54.4/26.6/14.9/8.7 (BP = 1.000 ratio = 1.026 hyp_len = 62880 ref_len = 61287)
```

If you only want the score to be printed, you can use the `--score-only/-b` flag:

```
$ sacrebleu -t wmt17 -l en-de -i output.detok.txt -b
20.8
```

The precision of the scores can be configured via the `--width/-w` flag:

```
$ sacrebleu -t wmt17 -l en-de -i output.detok.txt -b -w 4
20.7965
```

### Using your own reference file

SacreBLEU knows about common test sets (as detailed in the `--list` example above), but you can also use it to score system outputs with arbitrary references. In this case, do not forget to provide **detokenized** reference and hypotheses files:

```
# Let's save the reference to a text file
$ sacrebleu -t wmt17 -l en-de --echo ref > ref.detok.txt

# Option 1: Pass the reference file as a positional argument to sacreBLEU
$ sacrebleu ref.detok.txt -i output.detok.txt -m bleu -b -w 4
20.7965

# Option 2: Redirect the system into STDIN (Compatible with multi-bleu.perl way of doing things)
$ cat output.detok.txt | sacrebleu ref.detok.txt -m bleu -b -w 4
20.7965
```

### Using multiple metrics

Let's first compute BLEU, chrF and TER with the default settings:

```
$ sacrebleu -t wmt17 -l en-de -i output.detok.txt -m bleu chrf ter
        BLEU|nrefs:1|case:mixed|eff:no|tok:13a|smooth:exp|version:2.0.0 = 20.8 <stripped>
      chrF2|nrefs:1|case:mixed|eff:yes|nc:6|nw:0|space:no|version:2.0.0 = 52.0
TER|nrefs:1|case:lc|tok:tercom|norm:no|punct:yes|asian:no|version:2.0.0 = 69.0
```

Let's now enable `chrF++` which is a revised version of chrF that takes into account word n-grams.
Observe how the `nw:0` gets changed into `nw:2` in the signature:

```
$ sacrebleu -t wmt17 -l en-de -i output.detok.txt -m bleu chrf ter --chrf-word-order 2
        BLEU|nrefs:1|case:mixed|eff:no|tok:13a|smooth:exp|version:2.0.0 = 20.8 <stripped>
    chrF2++|nrefs:1|case:mixed|eff:yes|nc:6|nw:2|space:no|version:2.0.0 = 49.0
TER|nrefs:1|case:lc|tok:tercom|norm:no|punct:yes|asian:no|version:2.0.0 = 69.0
```

Metric-specific arguments are detailed in the output of `--help`:

```
BLEU related arguments:
  --smooth-method {none,floor,add-k,exp}, -s {none,floor,add-k,exp}
                        Smoothing method: exponential decay, floor (increment zero counts), add-k (increment num/denom by k for n>1), or none. (Default: exp)
  --smooth-value BLEU_SMOOTH_VALUE, -sv BLEU_SMOOTH_VALUE
                        The smoothing value. Only valid for floor and add-k. (Defaults: floor: 0.1, add-k: 1)
  --tokenize {none,zh,13a,char,intl,ja-mecab,ko-mecab}, -tok {none,zh,13a,char,intl,ja-mecab,ko-mecab}
                        Tokenization method to use for BLEU. If not provided, defaults to `zh` for Chinese, `ja-mecab` for Japanese, `ko-mecab` for Korean and `13a` (mteval) otherwise.
  --lowercase, -lc      If True, enables case-insensitivity. (Default: False)
  --force               Insist that your tokenized input is actually detokenized.

chrF related arguments:
  --chrf-char-order CHRF_CHAR_ORDER, -cc CHRF_CHAR_ORDER
                        Character n-gram order. (Default: 6)
  --chrf-word-order CHRF_WORD_ORDER, -cw CHRF_WORD_ORDER
                        Word n-gram order (Default: 0). If equals to 2, the metric is referred to as chrF++.
  --chrf-beta CHRF_BETA
                        Determine the importance of recall w.r.t precision. (Default: 2)
  --chrf-whitespace     Include whitespaces when extracting character n-grams. (Default: False)
  --chrf-lowercase      Enable case-insensitivity. (Default: False)
  --chrf-eps-smoothing  Enables epsilon smoothing similar to chrF++.py, NLTK and Moses; instead of effective order smoothing. (Default: False)

TER related arguments (The defaults replicate TERCOM's behavior):
  --ter-case-sensitive  Enables case sensitivity (Default: False)
  --ter-asian-support   Enables special treatment of Asian characters (Default: False)
  --ter-no-punct        Removes punctuation. (Default: False)
  --ter-normalized      Applies basic normalization and tokenization. (Default: False)

MacroF and MicroF related arguments (the defaults replicate Gowda et al NAACL 2021):
  --f-beta F_BETA       Determine the importance of recall w.r.t precision. (Default: 1)
  --f-lowercase         Enable case-insensitivity. (Default: False)
  --f-tokenize {none,zh,13a,char,intl,ja-mecab}
                        Tokenization method to use for Macro and MicroF, same as BLEU --tokenize. (Default: None)
  --f-smooth-value F_SMOOTH_VALUE
                        The smoothing value. only add-k smoothing method is supported for MacroF and MicroF (Default: 1)
```

### Version Signatures
As you may have noticed, sacreBLEU generates version strings such as `BLEU|nrefs:1|case:mixed|eff:no|tok:13a|smooth:exp|version:2.0.0` for reproducibility reasons. It's strongly recommended to share these signatures in your papers!

### Outputting other metadata

Sacrebleu knows about metadata for some test sets, and you can output it like this:

```
$ sacrebleu -t wmt21 -l en-de --echo src docid ref | head 2
Couple MACED at California dog park for not wearing face masks while having lunch (VIDEO) - RT USA News	rt.com.131279	Paar in Hundepark in Kalifornien mit Pfefferspray besprüht, weil es beim Mittagessen keine Masken trug (VIDEO) - RT USA News
There's mask-shaming and then there's full on assault.	rt.com.131279	Masken-Shaming ist eine Sache, Körperverletzung eine andere.
```

If multiple fields are requested, they are output as tab-separated columns (a TSV).

To see the available fields, add `--echo asdf` (or some other garbage data):

```
$ sacrebleu -t wmt21 -l en-de --echo asdf
sacreBLEU: No such field asdf in test set wmt21 for language pair en-de.
sacreBLEU: available fields for wmt21/en-de: src, ref:A, ref, docid, origlang
```

## Translationese Support

If you are interested in the translationese effect, you can evaluate BLEU on a subset of sentences
with a given original language (identified based on the `origlang` tag in the raw SGM files).
E.g., to evaluate only against originally German sentences translated to English use:

    $ sacrebleu -t wmt13 -l de-en --origlang=de -i my-wmt13-output.txt

and to evaluate against the complement (in this case `origlang` en, fr, cs, ru, de) use:

    $ sacrebleu -t wmt13 -l de-en --origlang=non-de -i my-wmt13-output.txt

**Please note** that the evaluator will return a BLEU score only on the requested subset,
but it expects that you pass through the entire translated test set.

## Languages & Preprocessing

### BLEU

- You can compute case-insensitive BLEU by passing `--lowercase` to sacreBLEU
- The default tokenizer for BLEU is `13a` which mimics the `mteval-v13a` script from Moses.
- Other tokenizers are:
   - `none` which will not apply any kind of tokenization at all
   - `char` for language-agnostic character-level tokenization
   - `intl` applies international tokenization and mimics the `mteval-v14` script from Moses
   - `zh` separates out **Chinese** characters and tokenizes the non-Chinese parts using `13a` tokenizer
   - `ja-mecab` tokenizes **Japanese** inputs using the [MeCab](https://pypi.org/project/mecab-python3) morphological analyzer
   - `ko-mecab` tokenizes **Korean** inputs using the [MeCab-ko](https://pypi.org/project/mecab-ko) morphological analyzer
   - `spm` uses the SentencePiece model built from the Flores-101 dataset (https://github.com/facebookresearch/flores#list-of-languages). Note: the canonical .spm file will be automatically fetched if not found locally.
- You can switch tokenizers using the `--tokenize` flag of sacreBLEU. Alternatively, if you provide language-pair strings
  using `--language-pair/-l`, `zh`, `ja-mecab` and `ko-mecab` tokenizers will be used if the target language is `zh` or `ja` or `ko`, respectively.
- **Note that** there's no automatic language detection from the hypotheses so you need to make sure that you are correctly
  selecting the tokenizer for **Japanese**, **Korean** and **Chinese**.


Default 13a tokenizer will produce poor results for Japanese:

```
$ sacrebleu kyoto-test.ref.ja -i kyoto-test.hyp.ja -b
2.1
```

Let's use the `ja-mecab` tokenizer:
```
$ sacrebleu kyoto-test.ref.ja -i kyoto-test.hyp.ja --tokenize ja-mecab -b
14.5
```

If you provide the language-pair, sacreBLEU will use ja-mecab automatically:

```
$ sacrebleu kyoto-test.ref.ja -i kyoto-test.hyp.ja -l en-ja -b
14.5
```

### chrF / chrF++

chrF applies minimum to none pre-processing as it deals with character n-grams:

- If you pass `--chrf-whitespace`, whitespace characters will be preserved when computing character n-grams.
- If you pass `--chrf-lowercase`, sacreBLEU will compute case-insensitive chrF.
- If you enable non-zero `--chrf-word-order` (pass `2` for `chrF++`), a very simple punctuation tokenization will be internally applied.


### TER

Translation Error Rate (TER) has its own special tokenizer that you can configure through the command line.
The defaults provided are **compatible with the upstream TER implementation (TERCOM)** but you can nevertheless modify the
behavior through the command-line:

- TER is by default case-insensitive. Pass `--ter-case-sensitive` to enable case-sensitivity.
- Pass `--ter-normalize` to apply a general Western tokenization
- Pass `--ter-asian-support` to enable the tokenization of Asian characters. If provided with `--ter-normalize`,
  both will be applied.
- Pass `--ter-no-punct` to strip punctuation.

## Multi-reference Evaluation

All three metrics support the use of multiple references during evaluation. Let's first pass all references as positional arguments:

```
$ sacrebleu ref1 ref2 -i system -m bleu chrf ter
        BLEU|nrefs:2|case:mixed|eff:no|tok:13a|smooth:exp|version:2.0.0 = 61.8 <stripped>
      chrF2|nrefs:2|case:mixed|eff:yes|nc:6|nw:0|space:no|version:2.0.0 = 75.0
TER|nrefs:2|case:lc|tok:tercom|norm:no|punct:yes|asian:no|version:2.0.0 = 31.2
```

Alternatively (less recommended), we can concatenate references using tabs as delimiters as well. Don't forget to pass `--num-refs/-nr` in this case!

```
$ paste ref1 ref2 > refs.tsv

$ sacrebleu refs.tsv --num-refs 2 -i system -m bleu
BLEU|nrefs:2|case:mixed|eff:no|tok:13a|smooth:exp|version:2.0.0 = 61.8 <stripped>
```

## Multi-system Evaluation
As of version `>=2.0.0`, SacreBLEU supports evaluation of an arbitrary number of systems for a particular
test set and language-pair. This has the advantage of seeing all results in a
nicely formatted table.

Let's pass all system output files that match the shell glob `newstest2017.online-*` to sacreBLEU for evaluation:

```
$ sacrebleu -t wmt17 -l en-de -i newstest2017.online-* -m bleu chrf
╒═══════════════════════════════╤════════╤═════════╕
│                        System │  BLEU  │  chrF2  │
╞═══════════════════════════════╪════════╪═════════╡
│ newstest2017.online-A.0.en-de │  20.8  │  52.0   │
├───────────────────────────────┼────────┼─────────┤
│ newstest2017.online-B.0.en-de │  26.7  │  56.3   │
├───────────────────────────────┼────────┼─────────┤
│ newstest2017.online-F.0.en-de │  15.5  │  49.3   │
├───────────────────────────────┼────────┼─────────┤
│ newstest2017.online-G.0.en-de │  18.2  │  51.6   │
╘═══════════════════════════════╧════════╧═════════╛

-----------------
Metric signatures
-----------------
 - BLEU       nrefs:1|case:mixed|eff:no|tok:13a|smooth:exp|version:2.0.0
 - chrF2      nrefs:1|case:mixed|eff:yes|nc:6|nw:0|space:no|version:2.0.0
```

You can also change the output format to `latex`:

```
$ sacrebleu -t wmt17 -l en-de -i newstest2017.online-* -m bleu chrf -f latex
\begin{tabular}{rcc}
\toprule
                        System &  BLEU  &  chrF2  \\
\midrule
 newstest2017.online-A.0.en-de &  20.8  &  52.0   \\
 newstest2017.online-B.0.en-de &  26.7  &  56.3   \\
 newstest2017.online-F.0.en-de &  15.5  &  49.3   \\
 newstest2017.online-G.0.en-de &  18.2  &  51.6   \\
\bottomrule
\end{tabular}

...
```

## Confidence Intervals for Single System Evaluation

When enabled with the `--confidence` flag, SacreBLEU will print
(1) the actual system score, (2) the true mean estimated from bootstrap resampling and (3),
the 95% [confidence interval](https://en.wikipedia.org/wiki/Confidence_interval) around the mean.
By default, the number of bootstrap resamples is 1000 (`bs:1000` in the signature)
and can be changed with `--confidence-n`:

```
$ sacrebleu -t wmt17 -l en-de -i output.detok.txt -m bleu chrf --confidence -f text --short
   BLEU|#:1|bs:1000|rs:12345|c:mixed|e:no|tok:13a|s:exp|v:2.0.0 = 22.675 (μ = 22.669 ± 0.598) ...
chrF2|#:1|bs:1000|rs:12345|c:mixed|e:yes|nc:6|nw:0|s:no|v:2.0.0 = 51.953 (μ = 51.953 ± 0.462)
```

**NOTE:** Although provided as a functionality, having access to confidence intervals for just one system
may not reveal much information about the underlying model. It often makes more sense to perform
**paired statistical tests** across multiple systems.

**NOTE:** When resampling, the seed of the `numpy`'s random number generator (RNG)
is fixed to `12345`. If you want to relax this and set your own seed, you can
export the environment variable `SACREBLEU_SEED` to an integer. Alternatively, you can export
`SACREBLEU_SEED=None` to skip initializing the RNG's seed and allow for non-deterministic
behavior.

## Paired Significance Tests for Multi System Evaluation
Ideally, one would have access to many systems in cases such as (1) investigating
whether a newly added feature yields significantly different scores than the baseline or
(2) evaluating submissions for a particular shared task. SacreBLEU offers two different paired significance tests that are widely used in MT research.

### Paired bootstrap resampling (--paired-bs)

This is an efficient implementation of the paper [Statistical Significance Tests for Machine Translation Evaluation](https://www.aclweb.org/anthology/W04-3250.pdf) and is result-compliant with the [reference Moses implementation](https://github.com/moses-smt/mosesdecoder/blob/master/scripts/analysis/bootstrap-hypothesis-difference-significance.pl). The number of bootstrap resamples can be changed with the `--paired-bs-n` flag and its default is 1000.

When launched, paired bootstrap resampling will perform:
 - Bootstrap resampling to estimate 95% CI for all systems and the baseline
 - A significance test between the **baseline** and each **system** to compute a [p-value](https://en.wikipedia.org/wiki/P-value).

### Paired approximate randomization (--paired-ar)

Paired approximate randomization (AR) is another type of paired significance test that is claimed to be more accurate than paired bootstrap resampling when it comes to Type-I errors ([Riezler and Maxwell III, 2005](https://www.aclweb.org/anthology/W05-0908.pdf)). Type-I errors indicate failures to reject the null hypothesis when it is true. In other words, AR should in theory be more robust to subtle changes across systems.

Our implementation is verified to be result-compliant with the [Multeval toolkit](https://github.com/jhclark/multeval) that also uses paired AR test for pairwise comparison. The number of approximate randomization trials is set to 10,000 by default. This can be changed with the `--paired-ar-n` flag.

### Running the tests

- The **first system** provided to `--input/-i` will be automatically taken as the **baseline system** against which you want to compare **other systems.**
- When `--input/-i` is used, the system output files will be automatically named according to the file paths. For the sake of simplicity, SacreBLEU will automatically discard the **baseline system** if it also appears amongst **other systems**. This is useful if you would like to run the tool by passing `-i systems/baseline.txt systems/*.txt`. Here, the `baseline.txt` file will not be also considered as a candidate system.
- Alternatively, you can also use a tab-separated input file redirected to SacreBLEU. In this case, the first column hypotheses will be taken as the **baseline system**. However, this method is **not recommended** as it won't allow naming your systems in a human-readable way. It will instead enumerate the systems from 1 to N following the column order in the tab-separated input.
- On Linux and Mac OS X, you can launch the tests on multiple CPU's by passing the flag `--paired-jobs N`. If `N == 0`, SacreBLEU will launch one worker for each pairwise comparison. If `N > 0`, `N` worker processes will be spawned. This feature will substantially speed up the runtime especially if you want the **TER** metric to be computed.

#### Example: Paired bootstrap resampling
In the example below, we select `newstest2017.LIUM-NMT.4900.en-de` as the baseline and compare it to 4 other WMT17 submissions using paired bootstrap resampling. According to the results, the null hypothesis (i.e. the two systems being essentially the same) could not be rejected (at the significance level of 0.05) for the following comparisons:

- 0.1 BLEU difference between the baseline and the online-B system (p = 0.3077)

```
$ sacrebleu -t wmt17 -l en-de -i newstest2017.LIUM-NMT.4900.en-de newstest2017.online-* -m bleu chrf --paired-bs
╒════════════════════════════════════════════╤═════════════════════╤══════════════════════╕
│                                     System │  BLEU (μ ± 95% CI)  │  chrF2 (μ ± 95% CI)  │
╞════════════════════════════════════════════╪═════════════════════╪══════════════════════╡
│ Baseline: newstest2017.LIUM-NMT.4900.en-de │  26.6 (26.6 ± 0.6)  │  55.9 (55.9 ± 0.5)   │
├────────────────────────────────────────────┼─────────────────────┼──────────────────────┤
│              newstest2017.online-A.0.en-de │  20.8 (20.8 ± 0.6)  │  52.0 (52.0 ± 0.4)   │
│                                            │    (p = 0.0010)*    │    (p = 0.0010)*     │
├────────────────────────────────────────────┼─────────────────────┼──────────────────────┤
│              newstest2017.online-B.0.en-de │  26.7 (26.6 ± 0.7)  │  56.3 (56.3 ± 0.5)   │
│                                            │    (p = 0.3077)     │    (p = 0.0240)*     │
├────────────────────────────────────────────┼─────────────────────┼──────────────────────┤
│              newstest2017.online-F.0.en-de │  15.5 (15.4 ± 0.5)  │  49.3 (49.3 ± 0.4)   │
│                                            │    (p = 0.0010)*    │    (p = 0.0010)*     │
├────────────────────────────────────────────┼─────────────────────┼──────────────────────┤
│              newstest2017.online-G.0.en-de │  18.2 (18.2 ± 0.5)  │  51.6 (51.6 ± 0.4)   │
│                                            │    (p = 0.0010)*    │    (p = 0.0010)*     │
╘════════════════════════════════════════════╧═════════════════════╧══════════════════════╛

------------------------------------------------------------
Paired bootstrap resampling test with 1000 resampling trials
------------------------------------------------------------
 - Each system is pairwise compared to Baseline: newstest2017.LIUM-NMT.4900.en-de.
   Actual system score / bootstrap estimated true mean / 95% CI are provided for each metric.

 - Null hypothesis: the system and the baseline translations are essentially
   generated by the same underlying process. For a given system and the baseline,
   the p-value is roughly the probability of the absolute score difference (delta)
   or higher occurring due to chance, under the assumption that the null hypothesis is correct.

 - Assuming a significance threshold of 0.05, the null hypothesis can be rejected
   for p-values < 0.05 (marked with "*"). This means that the delta is unlikely to be attributed
   to chance, hence the system is significantly "different" than the baseline.
   Otherwise, the p-values are highlighted in red.

 - NOTE: Significance does not tell whether a system is "better" than the baseline but rather
   emphasizes the "difference" of the systems in terms of the replicability of the delta.

-----------------
Metric signatures
-----------------
 - BLEU       nrefs:1|bs:1000|seed:12345|case:mixed|eff:no|tok:13a|smooth:exp|version:2.0.0
 - chrF2      nrefs:1|bs:1000|seed:12345|case:mixed|eff:yes|nc:6|nw:0|space:no|version:2.0.0
```

#### Example: Paired approximate randomization

Let's now run the paired approximate randomization test for the same comparison. According to the results, the findings are compatible with the paired bootstrap resampling test. However, the p-value for the `baseline vs. online-B` comparison is much higher (`0.8066`) than the paired bootstrap resampling test.

(**Note that** the AR test does not provide confidence intervals around the true mean as it does not perform bootstrap resampling.)

```
$ sacrebleu -t wmt17 -l en-de -i newstest2017.LIUM-NMT.4900.en-de newstest2017.online-* -m bleu chrf --paired-ar
╒════════════════════════════════════════════╤═══════════════╤═══════════════╕
│                                     System │     BLEU      │     chrF2     │
╞════════════════════════════════════════════╪═══════════════╪═══════════════╡
│ Baseline: newstest2017.LIUM-NMT.4900.en-de │     26.6      │     55.9      │
├────────────────────────────────────────────┼───────────────┼───────────────┤
│              newstest2017.online-A.0.en-de │     20.8      │     52.0      │
│                                            │ (p = 0.0001)* │ (p = 0.0001)* │
├────────────────────────────────────────────┼───────────────┼───────────────┤
│              newstest2017.online-B.0.en-de │     26.7      │     56.3      │
│                                            │ (p = 0.8066)  │ (p = 0.0385)* │
├────────────────────────────────────────────┼───────────────┼───────────────┤
│              newstest2017.online-F.0.en-de │     15.5      │     49.3      │
│                                            │ (p = 0.0001)* │ (p = 0.0001)* │
├────────────────────────────────────────────┼───────────────┼───────────────┤
│              newstest2017.online-G.0.en-de │     18.2      │     51.6      │
│                                            │ (p = 0.0001)* │ (p = 0.0001)* │
╘════════════════════════════════════════════╧═══════════════╧═══════════════╛

-------------------------------------------------------
Paired approximate randomization test with 10000 trials
-------------------------------------------------------
 - Each system is pairwise compared to Baseline: newstest2017.LIUM-NMT.4900.en-de.
   Actual system score is provided for each metric.

 - Null hypothesis: the system and the baseline translations are essentially
   generated by the same underlying process. For a given system and the baseline,
   the p-value is roughly the probability of the absolute score difference (delta)
   or higher occurring due to chance, under the assumption that the null hypothesis is correct.

 - Assuming a significance threshold of 0.05, the null hypothesis can be rejected
   for p-values < 0.05 (marked with "*"). This means that the delta is unlikely to be attributed
   to chance, hence the system is significantly "different" than the baseline.
   Otherwise, the p-values are highlighted in red.

 - NOTE: Significance does not tell whether a system is "better" than the baseline but rather
   emphasizes the "difference" of the systems in terms of the replicability of the delta.

-----------------
Metric signatures
-----------------
 - BLEU       nrefs:1|ar:10000|seed:12345|case:mixed|eff:no|tok:13a|smooth:exp|version:2.0.0
 - chrF2      nrefs:1|ar:10000|seed:12345|case:mixed|eff:yes|nc:6|nw:0|space:no|version:2.0.0
```

# Using SacreBLEU from Python

For evaluation, it may be useful to compute BLEU, chrF or TER from a Python script. The recommended
way of doing this is to use the object-oriented API, by creating an instance of the `metrics.BLEU` class
for example:

```python
In [1]: from sacrebleu.metrics import BLEU, CHRF, TER
   ...:
   ...: refs = [ # First set of references
   ...:          ['The dog bit the man.', 'It was not unexpected.', 'The man bit him first.'],
   ...:          # Second set of references
   ...:          ['The dog had bit the man.', 'No one was surprised.', 'The man had bitten the dog.'],
   ...:        ]
   ...: sys = ['The dog bit the man.', "It wasn't surprising.", 'The man had just bitten him.']

In [2]: bleu = BLEU()

In [3]: bleu.corpus_score(sys, refs)
Out[3]: BLEU = 48.53 82.4/50.0/45.5/37.5 (BP = 0.943 ratio = 0.944 hyp_len = 17 ref_len = 18)

In [4]: bleu.get_signature()
Out[4]: nrefs:2|case:mixed|eff:no|tok:13a|smooth:exp|version:2.0.0

In [5]: chrf = CHRF()

In [6]: chrf.corpus_score(sys, refs)
Out[6]: chrF2 = 59.73
```

### Variable Number of References

Let's now remove the first reference sentence for the first system sentence `The dog bit the man.` by replacing it with either `None` or the empty string `''`.
This allows using a variable number of reference segments per hypothesis. Observe how the signature changes from `nrefs:2` to `nrefs:var`:

```python
In [1]: from sacrebleu.metrics import BLEU, CHRF, TER
   ...:
   ...: refs = [ # First set of references
                 # 1st sentence does not have a ref here
   ...:          ['', 'It was not unexpected.', 'The man bit him first.'],
   ...:          # Second set of references
   ...:          ['The dog had bit the man.', 'No one was surprised.', 'The man had bitten the dog.'],
   ...:        ]
   ...: sys = ['The dog bit the man.', "It wasn't surprising.", 'The man had just bitten him.']

In [2]: bleu = BLEU()

In [3]: bleu.corpus_score(sys, refs)
Out[3]: BLEU = 29.44 82.4/42.9/27.3/12.5 (BP = 0.889 ratio = 0.895 hyp_len = 17 ref_len = 19)

In [4]: bleu.get_signature()
Out[4]: nrefs:var|case:mixed|eff:no|tok:13a|smooth:exp|version:2.0.0
```

## Compatibility API

You can also use the compatibility API that provides wrapper functions around the object-oriented API to
compute sentence-level and corpus-level BLEU, chrF and TER: (It should be noted that this API can be
removed in future releases)

```python
In [1]: import sacrebleu
   ...: 
   ...: refs = [ # First set of references
   ...:          ['The dog bit the man.', 'It was not unexpected.', 'The man bit him first.'],
   ...:          # Second set of references
   ...:          ['The dog had bit the man.', 'No one was surprised.', 'The man had bitten the dog.'],
   ...:        ]
   ...: sys = ['The dog bit the man.', "It wasn't surprising.", 'The man had just bitten him.']

In [2]: sacrebleu.corpus_bleu(sys, refs)
Out[2]: BLEU = 48.53 82.4/50.0/45.5/37.5 (BP = 0.943 ratio = 0.944 hyp_len = 17 ref_len = 18)
```

# License

SacreBLEU is licensed under the [Apache 2.0 License](LICENSE.txt).

# Credits

This was all Rico Sennrich's idea.
Originally written by Matt Post.
New features and ongoing support provided by Martin Popel (@martinpopel) and Ozan Caglayan (@ozancaglayan).

If you use SacreBLEU, please cite the following:

```
@inproceedings{post-2018-call,
  title = "A Call for Clarity in Reporting {BLEU} Scores",
  author = "Post, Matt",
  booktitle = "Proceedings of the Third Conference on Machine Translation: Research Papers",
  month = oct,
  year = "2018",
  address = "Belgium, Brussels",
  publisher = "Association for Computational Linguistics",
  url = "https://www.aclweb.org/anthology/W18-6319",
  pages = "186--191",
}
```

# Release Notes

Please see [CHANGELOG.md](CHANGELOG.md) for release notes.
