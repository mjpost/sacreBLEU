#!/usr/bin/env bash

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

# Confirms that BLEU scores computed by sacreBLEU are the same as Moses' mteval-v13a.pl.
# Note that this doesn't work if you lowercase the data (remove -c to mteval-v13a.pl,
# or add "-lc" to sacreBLEU) because mteval-v13a.pl does not lowercase properly: it uses
# tr/[A-Z]/[a-z], which doesn't cover uppercase letters with diacritics. Also, the
# Chinese preprocessing was applied to all zh sources, references, and system outputs
# (http://statmt.org/wmt17/tokenizeChinese.py), as was done for WMT17.

set -u

if [[ $(echo $BASH_VERSION | cut -d. -f1) -lt 4 ]]; then
  echo "This script requires BASH version 4 or above (since it uses hashes)."
  exit 1
fi

# Switch from JSON output to text
export SACREBLEU_FORMAT="text"

# Cleanup temporary files
trap "rm -f .tmp* data/.tmp*" EXIT INT TERM

# For Travis CI to work on Windows/Mac OS X
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
  PYTHON="python"
  CMD="$PYTHON -m sacrebleu"
elif [[ "$OSTYPE" == "msys" ]]; then
  PYTHON="python"
  CMD="$PYTHON -m sacrebleu"
elif [[ "$OSTYPE" == "darwin"* ]]; then
  # OS X ships python -> python2 by default, be explicit
  PYTHON=python3
  CMD="$PYTHON -m sacrebleu"
fi

export SACREBLEU=$(pwd)/.sacrebleu
export PYTHONPATH="${PWD}"    # assuming PYTHONPATH=. as the default
export NO_COLOR=1

# Only run this test
limit_test=${1:-}

SKIP_INITIAL=${SKIP_INITIAL:-}
SKIP_CHRF=${SKIP_CHRF:-}
SKIP_TER=${SKIP_TER:-}
SKIP_MECAB=${SKIP_MECAB:-}
SKIP_MECAB_KO=${SKIP_MECAB_KO:-}
SKIP_MTEVAL13=${SKIP_MTEVAL13:-}
SKIP_MTEVAL14=${SKIP_MTEVAL14:-}
SKIP_MACROF=${SKIP_MACROF:-}

# test case counter
declare -i i=0

# TEST 1: download and process WMT17 data
[[ -d $SACREBLEU/wmt17 ]] && rm -f $SACREBLEU/wmt17/{en-*,*-en*}
${CMD} --echo src -t wmt17 -l cs-en > /dev/null

# Test concatenation of multiple test sets, --echo, -w, --origlang, --verbose
# and a pipeline with two sacrebleu processes
declare -A EXPECTED
EXPECTED["${CMD} -t wmt16,wmt17 -l en-fi --echo ref | ${CMD} -b -w 4 -t wmt16/B,wmt17/B -l en-fi"]=53.7432
EXPECTED["${CMD} -t wmt16,wmt17 -l en-fi --echo ref | ${CMD} -b -w 4 -t wmt16/B,wmt17/B -l en-fi --origlang=en"]=18.9054
EXPECTED["${CMD} -t wmt17 -l en-fi --echo ref | ${CMD} -b -t wmt17/B -l en-fi --detail"]="55.6
origlang=en : sentences=1502   BLEU = 21.4
origlang=fi : sentences=1500   BLEU = 100.0"
EXPECTED["${CMD} -t wmt18,wmt19 -l en-de --echo=src | ${CMD} -t wmt18,wmt19 -l en-de -b --detail"]="3.6
origlang=de                      : sentences=1498   BLEU = 3.6
origlang=en                      : sentences=3497   BLEU = 3.5
origlang=en country=EU           : sentences=265    BLEU = 2.5
origlang=en country=GB           : sentences=913    BLEU = 3.1
origlang=en country=OTHER        : sentences=801    BLEU = 2.5
origlang=en country=US           : sentences=1518   BLEU = 4.2
origlang=en domain=business      : sentences=241    BLEU = 3.4
origlang=en domain=crime         : sentences=570    BLEU = 3.6
origlang=en domain=entertainment : sentences=322    BLEU = 5.1
origlang=en domain=politics      : sentences=959    BLEU = 3.0
origlang=en domain=scitech       : sentences=211    BLEU = 3.1
origlang=en domain=sport         : sentences=534    BLEU = 3.6
origlang=en domain=world         : sentences=660    BLEU = 3.1"

[[ ! -d data ]] && mkdir data
cd data

if [[ ! -d wmt17-submitted-data ]]; then
   echo "Downloading and unpacking WMT'17 system submissions (46 MB)..."
   wget -q http://data.statmt.org/wmt17/translation-task/wmt17-submitted-data-v1.0.tgz
   tar xzf wmt17-submitted-data-v1.0.tgz
fi

if [[ ! -d en-ja-translation-example-master ]]; then
   echo "Downloading and unpacking English-Japanese test data..."
   wget -q https://github.com/MorinoseiMorizo/en-ja-translation-example/archive/master.zip
   unzip master.zip
   rm master.zip
fi

if [[ ! -d en-ko-translation-example-master ]]; then
   echo "Downloading and unpacking English-Korean test data..."
   wget -q https://github.com/NoUnique/en-ko-translation-example/archive/master.zip
   unzip master.zip
   rm master.zip
fi

if [ -z $SKIP_INITIAL ]; then
  for command in "${!EXPECTED[@]}"; do
    echo Testing $command
    # Convert line endings to UNIX for Windows tests
    obtained=`eval $command | tr -d '\015'`
    expected=${EXPECTED[$command]}
    if [[ $obtained != $expected ]]; then
        echo -e "\nFAILED:\n expected = $expected\n obtained = $obtained"
        exit 1
    fi
    echo PASS
  done

  # Test loading via file instead of STDIN
  echo "Testing loading via file instead of STDIN"
  ${CMD} -t wmt17 -l en-de --echo ref > .tmp.wmt17
  score=$(${CMD} -t wmt17 -l en-de -i .tmp.wmt17 -b)
  if [[ $score != '100.0' ]]; then
      echo "File test failed."
      exit 1
  fi
  echo PASS

  # Test echoing of source, reference, and both
  # Replace \r\n with \n for Windows compatibility
  ${CMD} -t wmt17/ms -l zh-en --echo src | tr -d '\015' > .tmp.echo
  diff .tmp.echo $SACREBLEU/wmt17/ms/wmt17_ms.zh-en.src
  if [[ $? -ne 0 ]]; then
      echo "Source echo failed."
      exit 1
  fi
  ${CMD} -t wmt17/ms -l zh-en --echo ref:2 | tr -d '\015' > .tmp.echo
  diff .tmp.echo $SACREBLEU/wmt17/ms/wmt17_ms.zh-en.ref-2 > /dev/null
  if [[ $? -ne 0 ]]; then
      echo "Source echo failed."
      pwd
      exit 1
  fi

  export LC_ALL=C

  echo '-----------------------'
  echo 'Control character tests'
  echo '-----------------------'
  printf "Hello! How are you \r doing today?" > .tmp_ref_buggy
  echo "Hello! How are you doing today?" > .tmp_ref_okay
  score1=$( echo "Hello! How are you doing today?" | ${CMD} -w 2 -b .tmp_ref_buggy )
  score2=$( echo "Hello! How are you doing today?" | ${CMD} -w 2 -b .tmp_ref_okay )
  if [[ $score1 != $score2 ]]; then
    echo "Control character in reference test failed"
    exit 1
  fi
  let i++
  echo "Passed control character in reference test"

  #####################################################################
  # Tests for single-ref BLEU, multi-ref BLEU, signature and tokenizers
  #####################################################################
  path="wmt17-submitted-data/txt/system-outputs/newstest2017/cs-en"
  ref1="${path}/newstest2017.online-A.0.cs-en"
  ref2="${path}/newstest2017.online-B.0.cs-en"
  sys="${path}/newstest2017.PJATK.4760.cs-en"

  echo '--------------------------'
  echo 'BLEU/CHRF regression tests'
  echo '--------------------------'
  unset EXPECTED
  declare -A EXPECTED

  paste $ref1 $ref2 > .tmp_refs

  # Single ref, tokenizer variants, lowercase
  EXPECTED["${CMD} -w 4 -b -l cs-en $ref1 -i $sys"]=36.8799
  EXPECTED["${CMD} -lc -w 4 -b -l cs-en $ref1 -i $sys"]=38.1492
  EXPECTED["${CMD} --tokenize 13a  -w 4 -b -l cs-en $ref1 -i $sys"]=36.8799
  EXPECTED["${CMD} --tokenize none -w 4 -b -l cs-en $ref1 -i $sys"]=34.0638
  # multiple REF files
  EXPECTED["${CMD} -w 4 -b -l cs-en $ref1 $ref2 -i $sys"]=44.6732
  # multiple REF CHRF (epsilon smoothing)
  EXPECTED["${CMD} -m chrf --chrf-eps-smoothing -w 4 -b -l cs-en $ref1 $ref2 -i $sys"]=67.8596
  # multiple REF CHRF (effective order smoothing)
  EXPECTED["${CMD} -m chrf -w 4 -b -l cs-en $ref1 $ref2 -i $sys"]=67.8603
  # multiple REF CHRF++
  EXPECTED["${CMD} -m chrf -cw 2 -w 4 -b -l cs-en $ref1 $ref2 -i $sys"]=66.1016
  # multiple REFs with tab-delimited stream
  EXPECTED["${CMD} -w 4 -b -l cs-en --num-refs 2 .tmp_refs -i $sys"]=44.6732
  # Check signature correctness for multi-reference
  # separate files
  EXPECTED["${CMD} -l cs-en $ref1 $ref2 -i $sys | perl -pe 's/.*nrefs:([0-9]).*/\1/'"]=2
  # tab delimited stream
  EXPECTED["${CMD} -l cs-en --num-refs 2 .tmp_refs -i $sys | perl -pe 's/.*nrefs:([0-9]).*/\1/'"]=2


  # Run the tests
  for command in "${!EXPECTED[@]}"; do
    echo Testing $command
    obtained=`eval $command`
    expected=${EXPECTED[$command]}
    if [[ $obtained != $expected ]]; then
        echo -e "\nFAILED:\n expected = $expected\n obtained = $obtained"
        exit 1
    fi
    echo PASS
    let i++
  done
fi

#######################################################
# Pre-computed chrF scores from official implementation
# Cmd: chrF++.py -H hyp -R ref -nw 0
#######################################################
declare -A CHRF=( ["newstest2017.PJATK.4760.cs-en.sgm"]=52.5947
                  ["newstest2017.online-A.0.cs-en.sgm"]=53.3856
                  ["newstest2017.CU-Chimera.4886.en-cs.sgm"]=48.3370
                  ["newstest2017.LIUM-FNMT.4852.en-cs.sgm"]=48.4708
                  ["newstest2017.C-3MA.4959.en-de.sgm"]=51.9533
                  ["newstest2017.FBK.4870.en-de.sgm"]=54.7152
                  ["newstest2017.AaltoHnmtFlatcat.4798.en-fi.sgm"]=50.5981
                  ["newstest2017.online-A.0.en-fi.sgm"]=49.5458
                  ["newstest2017.limsi-factored-norm.5041.en-lv.sgm"]=49.3634
                  ["newstest2017.online-A.0.en-lv.sgm"]=45.2101
                  ["newstest2017.jhu-pbmt.4986.en-ru.sgm"]=54.9569
                  ["newstest2017.online-B.0.en-ru.sgm"]=60.4059
                  ["newstest2017.LIUM-NMT.4953.en-tr.sgm"]=47.5881
                  ["newstest2017.online-G.0.en-tr.sgm"]=48.7404
                  ["newstest2017.UU-HNMT.5134.en-zh.sgm"]=22.6844
                  ["newstest2017.online-F.0.en-zh.sgm"]=18.7403
                )

#########################################################
# Pre-computed chrF++ scores from official implementation
# Cmd: chrF++.py -H hyp -R ref
#########################################################
declare -A CHRFPP=( ["newstest2017.PJATK.4760.cs-en.sgm"]=50.2947
                    ["newstest2017.online-A.0.cs-en.sgm"]=51.1037
                    ["newstest2017.CU-Chimera.4886.en-cs.sgm"]=45.6732
                    ["newstest2017.LIUM-FNMT.4852.en-cs.sgm"]=45.7210
                    ["newstest2017.C-3MA.4959.en-de.sgm"]=49.1683
                    ["newstest2017.FBK.4870.en-de.sgm"]=52.2330
                    ["newstest2017.AaltoHnmtFlatcat.4798.en-fi.sgm"]=46.6295
                    ["newstest2017.online-A.0.en-fi.sgm"]=44.9147
                    ["newstest2017.limsi-factored-norm.5041.en-lv.sgm"]=45.7117
                    ["newstest2017.online-A.0.en-lv.sgm"]=40.8963
                    ["newstest2017.jhu-pbmt.4986.en-ru.sgm"]=52.0154
                    ["newstest2017.online-B.0.en-ru.sgm"]=57.6404
                    ["newstest2017.LIUM-NMT.4953.en-tr.sgm"]=43.8311
                    ["newstest2017.online-G.0.en-tr.sgm"]=44.6236
                    ["newstest2017.UU-HNMT.5134.en-zh.sgm"]=17.0181
                    ["newstest2017.online-F.0.en-zh.sgm"]=14.1572
                  )

if [ -z $SKIP_CHRF ]; then
  echo "------------------------------"
  echo "Starting chrF and chrF++ tests"
  echo "------------------------------"
  # Test only for different target languages as there is no tokenization
  # issue involved in chrF
  for pair in cs-en en-cs en-de en-fi en-lv en-ru en-tr en-zh; do
      source=$(echo $pair | cut -d- -f1)
      target=$(echo $pair | cut -d- -f2)
      for sgm in wmt17-submitted-data/sgm/system-outputs/newstest2017/$pair/*.sgm; do
          name=$(basename $sgm)

          if [[ ! -v CHRF[$name] ]]; then continue; fi
          if [[ ! -z $limit_test && $limit_test != $name ]]; then continue; fi

          sys=$(basename $sgm .sgm | perl -pe 's/newstest2017\.//')
          txt=$(dirname $sgm | perl -pe 's/sgm/txt/')/$(basename $sgm .sgm)

          # Test chrF
          score=$(cat $txt | ${CMD} -w 4 -t wmt17 -l $source-$target -b --metrics chrf --chrf-eps-smoothing)
          expected_score=${CHRF[$name]}
          echo "import sys; sys.exit(1 if abs(${score}-${expected_score}) > 1e-6 else 0)" | $PYTHON

          if [[ $? -eq 1 ]]; then
              echo "FAILED chrF test $pair/$sys (wanted $expected_score got $score)"
              exit 1
          fi
          echo "Passed $source-$target $sys chrF++.py: $expected_score sacreCHRF: $score"
          let i++

          # Test chrF++
          score=$(cat $txt | ${CMD} -w 4 -t wmt17 -l $source-$target -b --metrics chrf --chrf-word-order 2 --chrf-eps-smoothing)
          expected_score=${CHRFPP[$name]}

          echo "import sys; sys.exit(1 if abs(${score}-${expected_score}) > 1e-6 else 0)" | $PYTHON

          if [[ $? -eq 1 ]]; then
              echo "FAILED chrF++ test $pair/$sys (wanted $expected_score got $score)"
              exit 1
          fi
          echo "Passed $source-$target $sys chrF++.py: $expected_score sacreCHRF++: $score"

          let i++
      done
  done
fi

################################################################
# Pre-computed results from Moses' mteval-v13a.pl for BLEU tests
################################################################
echo "------------------------------------"
echo "Starting BLEU tests (mteval-v13a.pl)"
echo "------------------------------------"
declare -A MTEVAL=( ["newstest2017.PJATK.4760.cs-en.sgm"]=23.15
                    ["newstest2017.online-A.0.cs-en.sgm"]=25.12
                    ["newstest2017.online-B.0.cs-en.sgm"]=27.45
                    ["newstest2017.uedin-nmt.4955.cs-en.sgm"]=30.95
                    ["newstest2017.C-3MA.4958.de-en.sgm"]=28.98
                    ["newstest2017.KIT.4951.de-en.sgm"]=34.56
                    ["newstest2017.LIUM-NMT.4733.de-en.sgm"]=30.1
                    ["newstest2017.RWTH-nmt-ensemble.4920.de-en.sgm"]=33.12
                    ["newstest2017.SYSTRAN.4846.de-en.sgm"]=33.17
                    ["newstest2017.TALP-UPC.4830.de-en.sgm"]=28.09
                    ["newstest2017.online-A.0.de-en.sgm"]=32.48
                    ["newstest2017.online-B.0.de-en.sgm"]=32.97
                    ["newstest2017.online-F.0.de-en.sgm"]=17.67
                    ["newstest2017.online-G.0.de-en.sgm"]=26.04
                    ["newstest2017.uedin-nmt.4723.de-en.sgm"]=35.12
                    ["newstest2017.CU-Chimera.4886.en-cs.sgm"]=20.51
                    ["newstest2017.LIUM-FNMT.4852.en-cs.sgm"]=19.95
                    ["newstest2017.LIUM-NMT.4947.en-cs.sgm"]=20.2
                    ["newstest2017.PJATK.4761.en-cs.sgm"]=16.18
                    ["newstest2017.limsi-factored-norm.4957.en-cs.sgm"]=20.22
                    ["newstest2017.online-A.0.en-cs.sgm"]=16.55
                    ["newstest2017.online-B.0.en-cs.sgm"]=20.12
                    ["newstest2017.tuning-task-afrl_4gb.sgm.0.en-cs.sgm"]=14.18
                    ["newstest2017.tuning-task-afrl_8gb.sgm.0.en-cs.sgm"]=14.69
                    ["newstest2017.tuning-task-baseline_4gb.sgm.0.en-cs.sgm"]=13.69
                    ["newstest2017.tuning-task-baseline_8gb.sgm.0.en-cs.sgm"]=13.79
                    ["newstest2017.tuning-task-denisov_4gb.sgm.0.en-cs.sgm"]=12.64
                    ["newstest2017.tuning-task-ufal_4gb.sgm.0.en-cs.sgm"]=13.06
                    ["newstest2017.tuning-task-ufal_8gb.sgm.0.en-cs.sgm"]=15.25
                    ["newstest2017.uedin-nmt.4956.en-cs.sgm"]=22.8
                    ["newstest2017.C-3MA.4959.en-de.sgm"]=22.67
                    ["newstest2017.FBK.4870.en-de.sgm"]=26.33
                    ["newstest2017.KIT.4950.en-de.sgm"]=26.08
                    ["newstest2017.LIUM-NMT.4900.en-de.sgm"]=26.6
                    ["newstest2017.LMU-nmt-reranked.4934.en-de.sgm"]=27.11
                    ["newstest2017.LMU-nmt-single.4893.en-de.sgm"]=26.56
                    ["newstest2017.PROMT-Rule-based.4735.en-de.sgm"]=16.61
                    ["newstest2017.RWTH-nmt-ensemble.4921.en-de.sgm"]=26.02
                    ["newstest2017.SYSTRAN.4847.en-de.sgm"]=26.71
                    ["newstest2017.TALP-UPC.4834.en-de.sgm"]=21.24
                    ["newstest2017.online-A.0.en-de.sgm"]=20.8
                    ["newstest2017.online-B.0.en-de.sgm"]=26.65
                    ["newstest2017.online-F.0.en-de.sgm"]=15.45
                    ["newstest2017.online-G.0.en-de.sgm"]=18.16
                    ["newstest2017.uedin-nmt.4722.en-de.sgm"]=28.3
                    ["newstest2017.xmu.4910.en-de.sgm"]=26.69
                    ["newstest2017.AaltoHnmtFlatcat.4798.en-fi.sgm"]=17.15
                    ["newstest2017.AaltoHnmtMultitask.4873.en-fi.sgm"]=20.28
                    ["newstest2017.HY-AH.4797.en-fi.sgm"]=9.33
                    ["newstest2017.HY-HNMT.4961.en-fi.sgm"]=20.72
                    ["newstest2017.HY-SMT.4882.en-fi.sgm"]=15.87
                    ["newstest2017.TALP-UPC.4939.en-fi.sgm"]=11.47
                    ["newstest2017.apertium-unconstrained.4769.en-fi.sgm"]=1.05
                    ["newstest2017.jhu-nmt-lattice-rescore.4903.en-fi.sgm"]=15.96
                    ["newstest2017.jhu-pbmt.4968.en-fi.sgm"]=14.46
                    ["newstest2017.online-A.0.en-fi.sgm"]=13.72
                    ["newstest2017.online-B.0.en-fi.sgm"]=22.04
                    ["newstest2017.online-G.0.en-fi.sgm"]=15.51
                    ["newstest2017.C-3MA.5069.en-lv.sgm"]=13.64
                    ["newstest2017.HY-HNMT.5066.en-lv.sgm"]=16.76
                    ["newstest2017.KIT.5062.en-lv.sgm"]=18.31
                    ["newstest2017.LIUM-FNMT.5043.en-lv.sgm"]=16.19
                    ["newstest2017.LIUM-NMT.5042.en-lv.sgm"]=17.01
                    ["newstest2017.PJATK.4744.en-lv.sgm"]=10.15
                    ["newstest2017.QT21-System-Combination.5063.en-lv.sgm"]=18.63
                    ["newstest2017.jhu-pbmt.4969.en-lv.sgm"]=14.35
                    ["newstest2017.limsi-factored-norm.5041.en-lv.sgm"]=16.63
                    ["newstest2017.online-A.0.en-lv.sgm"]=10.84
                    ["newstest2017.online-B.0.en-lv.sgm"]=17.91
                    ["newstest2017.tilde-c-nmt-smt-hybrid.5049.en-lv.sgm"]=20.14
                    ["newstest2017.tilde-nc-nmt-smt-hybrid.5047.en-lv.sgm"]=20.79
                    ["newstest2017.tilde-nc-smt.5044.en-lv.sgm"]=21.05
                    ["newstest2017.uedin-nmt.5016.en-lv.sgm"]=16.93
                    ["newstest2017.usfd-consensus-kit.5078.en-lv.sgm"]=17.48
                    ["newstest2017.usfd-consensus-qt21.5077.en-lv.sgm"]=17.99
                    ["newstest2017.PROMT-Rule-based.4736.en-ru.sgm"]=22.3
                    ["newstest2017.afrl-mitll-backtrans.4907.en-ru.sgm"]=25.37
                    ["newstest2017.jhu-pbmt.4986.en-ru.sgm"]=25.32
                    ["newstest2017.online-A.0.en-ru.sgm"]=23.83
                    ["newstest2017.online-B.0.en-ru.sgm"]=32.05
                    ["newstest2017.online-F.0.en-ru.sgm"]=10.08
                    ["newstest2017.online-G.0.en-ru.sgm"]=27.11
                    ["newstest2017.online-H.0.en-ru.sgm"]=28.41
                    ["newstest2017.uedin-nmt.4756.en-ru.sgm"]=29.79
                    ["newstest2017.JAIST.4858.en-tr.sgm"]=9.98
                    ["newstest2017.LIUM-NMT.4953.en-tr.sgm"]=16.03
                    ["newstest2017.jhu-nmt-lattice-rescore.4904.en-tr.sgm"]=10.37
                    ["newstest2017.jhu-pbmt.4970.en-tr.sgm"]=9.81
                    ["newstest2017.online-A.0.en-tr.sgm"]=11.62
                    ["newstest2017.online-B.0.en-tr.sgm"]=19.93
                    ["newstest2017.online-G.0.en-tr.sgm"]=13.93
                    ["newstest2017.uedin-nmt.4932.en-tr.sgm"]=16.43
                    ["newstest2017.CASICT-DCU-NMT.5157.en-zh.sgm"]=30.52
                    ["newstest2017.Oregon-State-University-S.5174.en-zh.sgm"]=25.93
                    ["newstest2017.SogouKnowing-nmt.5131.en-zh.sgm"]=34.87
                    ["newstest2017.UU-HNMT.5134.en-zh.sgm"]=23.92
                    ["newstest2017.jhu-nmt.5153.en-zh.sgm"]=31.05
                    ["newstest2017.online-A.0.en-zh.sgm"]=29.02
                    ["newstest2017.online-B.0.en-zh.sgm"]=32.07
                    ["newstest2017.online-F.0.en-zh.sgm"]=18.58
                    ["newstest2017.online-G.0.en-zh.sgm"]=21.31
                    ["newstest2017.uedin-nmt.5111.en-zh.sgm"]=36.28
                    ["newstest2017.xmunmt.5165.en-zh.sgm"]=35.84
                    ["newstest2017.Hunter-MT.4925.fi-en.sgm"]=19.96
                    ["newstest2017.TALP-UPC.4937.fi-en.sgm"]=16.13
                    ["newstest2017.apertium-unconstrained.4793.fi-en.sgm"]=6.13
                    ["newstest2017.online-A.0.fi-en.sgm"]=21.13
                    ["newstest2017.online-B.0.fi-en.sgm"]=27.62
                    ["newstest2017.online-G.0.fi-en.sgm"]=22.48
                    ["newstest2017.C-3MA.5067.lv-en.sgm"]=14.31
                    ["newstest2017.Hunter-MT.5092.lv-en.sgm"]=16.23
                    ["newstest2017.PJATK.4740.lv-en.sgm"]=12.42
                    ["newstest2017.jhu-pbmt.4980.lv-en.sgm"]=16.79
                    ["newstest2017.online-A.0.lv-en.sgm"]=15.72
                    ["newstest2017.online-B.0.lv-en.sgm"]=22.02
                    ["newstest2017.tilde-c-nmt-smt-hybrid.5051.lv-en.sgm"]=20.0
                    ["newstest2017.tilde-nc-nmt-smt-hybrid.5050.lv-en.sgm"]=21.92
                    ["newstest2017.uedin-nmt.5017.lv-en.sgm"]=18.98
                    ["newstest2017.NRC.4855.ru-en.sgm"]=33.88
                    ["newstest2017.afrl-mitll-opennmt.4896.ru-en.sgm"]=33.95
                    ["newstest2017.afrl-mitll-syscomb.4905.ru-en.sgm"]=34.71
                    ["newstest2017.jhu-pbmt.4978.ru-en.sgm"]=31.47
                    ["newstest2017.online-A.0.ru-en.sgm"]=31.18
                    ["newstest2017.online-B.0.ru-en.sgm"]=36.94
                    ["newstest2017.online-F.0.ru-en.sgm"]=15.9
                    ["newstest2017.online-G.0.ru-en.sgm"]=34.51
                    ["newstest2017.uedin-nmt.4890.ru-en.sgm"]=30.77
                    ["newstest2017.JAIST.4859.tr-en.sgm"]=12.42
                    ["newstest2017.LIUM-NMT.4888.tr-en.sgm"]=17.91
                    ["newstest2017.PROMT-SMT.4737.tr-en.sgm"]=13.52
                    ["newstest2017.afrl-mitll-m2w-nr1.4901.tr-en.sgm"]=17.54
                    ["newstest2017.afrl-mitll-syscomb.4902.tr-en.sgm"]=18.05
                    ["newstest2017.jhu-pbmt.4972.tr-en.sgm"]=12.64
                    ["newstest2017.online-A.0.tr-en.sgm"]=22.18
                    ["newstest2017.online-B.0.tr-en.sgm"]=25.62
                    ["newstest2017.online-G.0.tr-en.sgm"]=16.38
                    ["newstest2017.uedin-nmt.4931.tr-en.sgm"]=20.08
                    ["newstest2017.CASICT-DCU-NMT.5144.zh-en.sgm"]=22.32
                    ["newstest2017.NMT-Model-Average-Multi-Cards.5099.zh-en.sgm"]=18.98
                    ["newstest2017.NRC.5172.zh-en.sgm"]=25.78
                    ["newstest2017.Oregon-State-University-S.5173.zh-en.sgm"]=18.51
                    ["newstest2017.PROMT-SMT.5125.zh-en.sgm"]=16.47
                    ["newstest2017.ROCMT.5183.zh-en.sgm"]=20.76
                    ["newstest2017.SogouKnowing-nmt.5171.zh-en.sgm"]=26.38
                    ["newstest2017.UU-HNMT.5162.zh-en.sgm"]=15.94
                    ["newstest2017.afrl-mitll-opennmt.5109.zh-en.sgm"]=21.28
                    ["newstest2017.jhu-nmt.5151.zh-en.sgm"]=20.48
                    ["newstest2017.online-A.0.zh-en.sgm"]=24.51
                    ["newstest2017.online-B.0.zh-en.sgm"]=33.23
                    ["newstest2017.online-F.0.zh-en.sgm"]=11.39
                    ["newstest2017.online-G.0.zh-en.sgm"]=15.5
                    ["newstest2017.uedin-nmt.5112.zh-en.sgm"]=25.7
                    ["newstest2017.xmunmt.5160.zh-en.sgm"]=26.0
                    ["kyoto-test"]=14.48
                    ["flores101.devtest.en-ko"]=33.18
                  )

if [ -z $SKIP_MTEVAL13 ]; then
  for pair in cs-en de-en en-cs en-de en-fi en-lv en-ru en-tr en-zh fi-en lv-en ru-en tr-en zh-en; do
      source=$(echo $pair | cut -d- -f1)
      target=$(echo $pair | cut -d- -f2)
      for sgm in wmt17-submitted-data/sgm/system-outputs/newstest2017/$pair/*.sgm; do
          name=$(basename $sgm)

          if [[ ! -v MTEVAL[$name] ]]; then continue; fi
          if [[ ! -z $limit_test && $limit_test != $name ]]; then continue; fi

          sys=$(basename $sgm .sgm | perl -pe 's/newstest2017\.//')
          txt=$(dirname $sgm | perl -pe 's/sgm/txt/')/$(basename $sgm .sgm)
          src=wmt17-submitted-data/sgm/sources/newstest2017-$source$target-src.$source.sgm
          ref=wmt17-submitted-data/sgm/references/newstest2017-$source$target-ref.$target.sgm

          # mteval=$($MOSES/scripts/generic/mteval-v13a.pl -c -s $src -r $ref -t $sgm 2> /dev/null | grep "BLEU score" | cut -d' ' -f9)
          # mteval=$(echo "print($bleu1 * 100)" | python)
          score=$(cat $txt | ${CMD} -w 2 -t wmt17 -l $source-$target -b)

          echo "import sys; sys.exit(1 if abs($score-${MTEVAL[$name]}) > 0.01 else 0)" | $PYTHON

          if [[ $? -eq 1 ]]; then
              echo "FAILED test $pair/$sys (wanted ${MTEVAL[$name]} got $score)"
              exit 1
          fi
          echo "Passed $source-$target $sys mteval-v13a.pl: ${MTEVAL[$name]} sacreBLEU: $score"

          let i++
      done
  done
fi

############################################################################
# Pre-computed results from Moses' mteval-v14.pl for BLEU tests
# mteval-v14a.pl -c -s $src -r $ref -t $sgm -b --international-tokenization
############################################################################
echo "-----------------------------------------------------------------"
echo "Starting BLEU tests (mteval-v14.pl, --international-tokenization)"
echo "-----------------------------------------------------------------"

declare -A MTEVAL14=( ["newstest2017.online-A.0.en-ru.sgm"]=23.99
                      ["newstest2017.online-A.0.en-cs.sgm"]=16.65
                      ["newstest2017.uedin-nmt.4890.ru-en.sgm"]=30.91
                      ["newstest2017.xmunmt.5160.zh-en.sgm"]=26.8
                      ["newstest2017.LIUM-NMT.4900.en-de.sgm"]=26.89
                      ["newstest2017.tilde-nc-nmt-smt-hybrid.5047.en-lv.sgm"]=20.88
                      ["newstest2017.TALP-UPC.4937.fi-en.sgm"]=16.18
                      ["newstest2017.LIUM-NMT.4888.tr-en.sgm"]=17.94
                      ["newstest2017.SogouKnowing-nmt.5131.en-zh.sgm"]=7.24
                      ["newstest2017.online-B.0.en-tr.sgm"]=22.88
                      ["newstest2017.apertium-unconstrained.4769.en-fi.sgm"]=1.08
                      ["newstest2017.tilde-c-nmt-smt-hybrid.5051.lv-en.sgm"]=20.44
                      ["newstest2017.RWTH-nmt-ensemble.4920.de-en.sgm"]=33.73
                      # Below two not exactly compatible with mteval due to &apos;s (#138)
                      ["newstest2017.PJATK.4760.cs-en.sgm"]=23.47
                      ["newstest2017.PJATK.4761.en-cs.sgm"]=15.91
                    )

if [ -z $SKIP_MTEVAL14 ]; then
  for pair in cs-en de-en en-cs en-de en-fi en-lv en-ru en-tr en-zh fi-en lv-en ru-en tr-en zh-en; do
      source=$(echo $pair | cut -d- -f1)
      target=$(echo $pair | cut -d- -f2)
      for sgm in wmt17-submitted-data/sgm/system-outputs/newstest2017/$pair/*.sgm; do
          name=$(basename $sgm)

          if [[ ! -v MTEVAL14[$name] ]]; then continue; fi
          if [[ ! -z $limit_test && $limit_test != $name ]]; then continue; fi

          sys=$(basename $sgm .sgm | perl -pe 's/newstest2017\.//')
          txt=$(dirname $sgm | perl -pe 's/sgm/txt/')/$(basename $sgm .sgm)
          src=wmt17-submitted-data/sgm/sources/newstest2017-$source$target-src.$source.sgm
          ref=wmt17-submitted-data/sgm/references/newstest2017-$source$target-ref.$target.sgm

          score=$(cat $txt | ${CMD} -w 2 -t wmt17 -l $source-$target -b --tokenize intl)

          echo "import sys; sys.exit(1 if abs($score-${MTEVAL14[$name]}) > 0.01 else 0)" | $PYTHON

          if [[ $? -eq 1 ]]; then
              echo "FAILED test $pair/$sys (wanted ${MTEVAL14[$name]} got $score)"
              exit 1
          fi
          echo "Passed $source-$target $sys mteval-v14.pl: ${MTEVAL14[$name]} sacreBLEU: $score"

          let i++
      done
  done
fi

#######################################################
# Pre-computed TER scores from official implementation
# Cmd: java -jar tercom.7.25.jar -r REF -h HYP | grep '^Total TER' | awk '{ printf "%.3f\n", $3 }'
#######################################################
declare -A TER=( ["newstest2017.online-A.0.cs-en.sgm"]=0.637
                 ["newstest2017.online-B.0.cs-en.sgm"]=0.605
                 ["newstest2017.PJATK.4760.cs-en.sgm"]=0.664
                 ["newstest2017.uedin-nmt.4955.cs-en.sgm"]=0.584
                 ["newstest2017.CU-Chimera.4886.en-cs.sgm"]=0.696
                 ["newstest2017.limsi-factored-norm.4957.en-cs.sgm"]=0.696
                 ["newstest2017.LIUM-FNMT.4852.en-cs.sgm"]=0.699
                 ["newstest2017.LIUM-NMT.4947.en-cs.sgm"]=0.701
                 ["newstest2017.online-A.0.en-cs.sgm"]=0.743
                 ["newstest2017.online-B.0.en-cs.sgm"]=0.703
                 ["newstest2017.PJATK.4761.en-cs.sgm"]=0.757
                 ["newstest2017.uedin-nmt.4956.en-cs.sgm"]=0.667
                 ["newstest2017.C-3MA.4959.en-de.sgm"]=0.669
                 ["newstest2017.FBK.4870.en-de.sgm"]=0.636
                 ["newstest2017.KIT.4950.en-de.sgm"]=0.641
                 ["newstest2017.LIUM-NMT.4900.en-de.sgm"]=0.633
                 ["newstest2017.LMU-nmt-reranked.4934.en-de.sgm"]=0.618
                 ["newstest2017.LMU-nmt-single.4893.en-de.sgm"]=0.626
                 ["newstest2017.online-A.0.en-de.sgm"]=0.690
                 ["newstest2017.online-B.0.en-de.sgm"]=0.632
                 ["newstest2017.online-F.0.en-de.sgm"]=0.756
                 ["newstest2017.online-G.0.en-de.sgm"]=0.733
                 ["newstest2017.PROMT-Rule-based.4735.en-de.sgm"]=0.752
                 ["newstest2017.RWTH-nmt-ensemble.4921.en-de.sgm"]=0.628
                 ["newstest2017.SYSTRAN.4847.en-de.sgm"]=0.611
                 ["newstest2017.TALP-UPC.4834.en-de.sgm"]=0.685
                 ["newstest2017.uedin-nmt.4722.en-de.sgm"]=0.612
                 ["newstest2017.xmu.4910.en-de.sgm"]=0.622
                 ["newstest2017.AaltoHnmtFlatcat.4798.en-fi.sgm"]=0.750
                 ["newstest2017.AaltoHnmtMultitask.4873.en-fi.sgm"]=0.673
                 ["newstest2017.apertium-unconstrained.4769.en-fi.sgm"]=1.246
                 ["newstest2017.HY-AH.4797.en-fi.sgm"]=0.857
                 ["newstest2017.HY-HNMT.4961.en-fi.sgm"]=0.676
                 ["newstest2017.HY-SMT.4882.en-fi.sgm"]=0.754
                 ["newstest2017.jhu-nmt-lattice-rescore.4903.en-fi.sgm"]=0.758
                 ["newstest2017.jhu-pbmt.4968.en-fi.sgm"]=0.778
                 ["newstest2017.online-A.0.en-fi.sgm"]=0.761
                 ["newstest2017.online-B.0.en-fi.sgm"]=0.665
                 ["newstest2017.online-G.0.en-fi.sgm"]=0.767
                 ["newstest2017.TALP-UPC.4939.en-fi.sgm"]=0.806
                 ["newstest2017.C-3MA.5069.en-lv.sgm"]=0.843
                 ["newstest2017.HY-HNMT.5066.en-lv.sgm"]=0.786
                 ["newstest2017.jhu-pbmt.4969.en-lv.sgm"]=0.815
                 ["newstest2017.KIT.5062.en-lv.sgm"]=0.773
                 ["newstest2017.limsi-factored-norm.5041.en-lv.sgm"]=0.780
                 ["newstest2017.LIUM-FNMT.5043.en-lv.sgm"]=0.780
                 ["newstest2017.LIUM-NMT.5042.en-lv.sgm"]=0.769
                 ["newstest2017.online-A.0.en-lv.sgm"]=0.846
                 ["newstest2017.online-B.0.en-lv.sgm"]=0.754
                 ["newstest2017.PJATK.4744.en-lv.sgm"]=0.868
                 ["newstest2017.tilde-c-nmt-smt-hybrid.5049.en-lv.sgm"]=0.731
                 ["newstest2017.tilde-nc-nmt-smt-hybrid.5047.en-lv.sgm"]=0.721
                 ["newstest2017.tilde-nc-smt.5044.en-lv.sgm"]=0.747
                 ["newstest2017.uedin-nmt.5016.en-lv.sgm"]=0.772
                 ["newstest2017.usfd-consensus-kit.5078.en-lv.sgm"]=0.950
                 ["newstest2017.usfd-consensus-qt21.5077.en-lv.sgm"]=0.946
                 ["newstest2017.afrl-mitll-backtrans.4907.en-ru.sgm"]=0.655
                 ["newstest2017.jhu-pbmt.4986.en-ru.sgm"]=0.658
                 ["newstest2017.online-A.0.en-ru.sgm"]=0.661
                 ["newstest2017.online-B.0.en-ru.sgm"]=0.563
                 ["newstest2017.online-F.0.en-ru.sgm"]=0.809
                 ["newstest2017.online-G.0.en-ru.sgm"]=0.618
                 ["newstest2017.PROMT-Rule-based.4736.en-ru.sgm"]=0.667
                 ["newstest2017.uedin-nmt.4756.en-ru.sgm"]=0.614
                 ["newstest2017.JAIST.4858.en-tr.sgm"]=0.875
                 ["newstest2017.jhu-nmt-lattice-rescore.4904.en-tr.sgm"]=0.864
                 ["newstest2017.jhu-pbmt.4970.en-tr.sgm"]=0.874
                 ["newstest2017.LIUM-NMT.4953.en-tr.sgm"]=0.752
                 ["newstest2017.online-A.0.en-tr.sgm"]=0.787
                 ["newstest2017.online-B.0.en-tr.sgm"]=0.677
                 ["newstest2017.uedin-nmt.4932.en-tr.sgm"]=0.747
                 ["newstest2017.CASICT-DCU-NMT.5157.en-zh.sgm"]=0.999
                 ["newstest2017.online-A.0.en-zh.sgm"]=2.936
                 ["newstest2017.online-B.0.en-zh.sgm"]=1.092
                 ["newstest2017.online-F.0.en-zh.sgm"]=1.114
                 ["newstest2017.online-G.0.en-zh.sgm"]=1.158
                 ["newstest2017.Oregon-State-University-S.5174.en-zh.sgm"]=5.622
                 ["newstest2017.SogouKnowing-nmt.5131.en-zh.sgm"]=1.402
                 ["newstest2017.uedin-nmt.5111.en-zh.sgm"]=1.334
                 ["newstest2017.UU-HNMT.5134.en-zh.sgm"]=1.000
                 ["newstest2017.xmunmt.5165.en-zh.sgm"]=1.366
                  )

if [ -z $SKIP_TER ]; then
  echo "-------------------"
  echo "Starting TER tests"
  echo "-------------------"
  for pair in cs-en en-cs en-de en-fi en-lv en-ru en-tr en-zh; do
      source=$(echo $pair | cut -d- -f1)
      target=$(echo $pair | cut -d- -f2)
      for sgm in wmt17-submitted-data/sgm/system-outputs/newstest2017/$pair/*.sgm; do
          name=$(basename $sgm)

          if [[ ! -z $limit_test && $limit_test != $name ]]; then continue; fi

          if [[ ! -v "TER[$name]" ]]; then continue ; fi  # official Tercom fails for some outputs...

          sys=$(basename $sgm .sgm | perl -pe 's/newstest2017\.//')
          txt=$(dirname $sgm | perl -pe 's/sgm/txt/')/$(basename $sgm .sgm)
          src=wmt17-submitted-data/sgm/sources/newstest2017-$source$target-src.$source.sgm
          ref=wmt17-submitted-data/sgm/references/newstest2017-$source$target-ref.$target.sgm

          score=$(cat $txt | ${CMD} -w 3 -t wmt17 -l $source-$target -b --metrics ter)

          expected_score="${TER[$name]}"

          echo "import sys; sys.exit(1 if abs(0.01 * ${score}-${expected_score}) > 0.01 else 0)" | $PYTHON

          if [[ $? -eq 1 ]]; then
              echo "FAILED test $pair/$sys (wanted $expected_score got $score)"
              exit 1
          fi
          echo "Passed $source-$target $sys tercom: $expected_score sacreTER: $score"

          let i++
      done
  done
fi

#############
# Mecab tests
#############
if [[ -z $SKIP_MECAB ]]; then
  echo "-----------------------"
  echo "Testing Mecab tokenizer"
  echo "-----------------------"
    pair="en-ja"
    source=$(echo $pair | cut -d- -f1)
    target=$(echo $pair | cut -d- -f2)
    for txt in en-ja-translation-example-master/*.hyp.$target; do
        name=$(basename $txt .hyp.$target)

        if [[ ! -z $limit_test && $limit_test != $name ]]; then continue; fi

        sys=$(basename $txt .hyp.$target)
        ref=$(dirname $txt)/$(basename $txt .hyp.$target).ref.$target
        score=$(cat $txt | ${CMD} -w 2 -l $source-$target -b $ref)

        echo "import sys; sys.exit(1 if abs($score-${MTEVAL[$name]}) > 0.01 else 0)" | $PYTHON

        if [[ $? -eq 1 ]]; then
            echo "FAILED test $pair/$sys (wanted ${MTEVAL[$name]} got $score)"
            exit 1
        fi
        echo "Passed $source-$target $sys mteval-v13a.pl: ${MTEVAL[$name]} sacreBLEU: $score"

        let i++
    done
fi

#############
# Mecab-ko tests
#############
if [[ -z $SKIP_MECAB_KO ]]; then
  echo "-----------------------"
  echo "Testing Mecab-ko tokenizer"
  echo "-----------------------"
    pair="en-ko"
    source=$(echo $pair | cut -d- -f1)
    target=$(echo $pair | cut -d- -f2)
    for txt in en-ko-translation-example-master/*.hyp.$target; do
        name=$(basename $txt .hyp.$target)

        if [[ ! -z $limit_test && $limit_test != $name ]]; then continue; fi

        sys=$(basename $txt .hyp.$target)
        ref=$(dirname $txt)/$(basename $txt .hyp.$target).ref.$target
        score=$(cat $txt | ${CMD} -w 2 -l $source-$target -b $ref)

        echo "import sys; sys.exit(1 if abs($score-${MTEVAL[$name]}) > 0.01 else 0)" | python

        if [[ $? -eq 1 ]]; then
            echo "FAILED test $pair/$sys (wanted ${MTEVAL[$name]} got $score)"
            exit 1
        fi
        echo "Passed $source-$target $sys mteval-v13a.pl: ${MTEVAL[$name]} sacreBLEU: $score"

        let i++
    done
fi


## From https://raw.githubusercontent.com/thammegowda/007-mt-eval-macro/master/justifs/wmt-metrics/tables/wmt-scores-2017.tsv
#lang,name,MacroF1,MicroF1
MACF1_WMT17="cs-en,PJATK.4760,36.0,53.8
cs-en,online-A.0,33.0,53.7
cs-en,online-B.0,36.5,55.9
cs-en,uedin-nmt.4955,39.4,58.3
de-en,C-3MA.4958,35.8,57.0
de-en,KIT.4951,41.3,61.4
de-en,LIUM-NMT.4733,36.9,57.6
de-en,RWTH-nmt-ensemble.4920,39.9,60.5
de-en,SYSTRAN.4846,40.4,60.7
de-en,TALP-UPC.4830,36.7,57.0
de-en,online-A.0,39.9,60.3
de-en,online-B.0,41.1,60.8
de-en,online-F.0,30.2,49.9
de-en,online-G.0,36.6,56.3
de-en,uedin-nmt.4723,41.7,61.9
en-cs,CU-Chimera.4886,23.9,43.1
en-cs,LIUM-FNMT.4852,23.4,42.8
en-cs,LIUM-NMT.4947,23.5,43.0
en-cs,PJATK.4761,20.2,38.5
en-cs,limsi-factored-norm.4957,23.9,43.3
en-cs,online-A.0,20.8,39.7
en-cs,online-B.0,23.5,42.6
en-cs,tuning-task-afrl_4gb.sgm.0,16.9,35.1
en-cs,tuning-task-afrl_8gb.sgm.0,17.1,35.6
en-cs,tuning-task-baseline_4gb.sgm.0,16.0,34.6
en-cs,tuning-task-baseline_8gb.sgm.0,16.3,35.0
en-cs,tuning-task-denisov_4gb.sgm.0,15.6,33.4
en-cs,tuning-task-ufal_4gb.sgm.0,15.4,34.0
en-cs,tuning-task-ufal_8gb.sgm.0,18.3,37.0
en-cs,uedin-nmt.4956,26.3,45.7
en-de,C-3MA.4959,25.5,48.0
en-de,FBK.4870,30.9,52.1
en-de,KIT.4950,28.6,51.0
en-de,LIUM-NMT.4900,30.2,52.2
en-de,LMU-nmt-reranked.4934,29.5,52.1
en-de,LMU-nmt-single.4893,28.9,51.5
en-de,PROMT-Rule-based.4735,21.9,43.2
en-de,RWTH-nmt-ensemble.4921,29.3,51.8
en-de,SYSTRAN.4847,27.7,51.4
en-de,TALP-UPC.4834,24.8,47.1
en-de,online-A.0,25.2,47.4
en-de,online-B.0,30.0,52.0
en-de,online-F.0,21.6,42.1
en-de,online-G.0,25.1,46.1
en-de,uedin-nmt.4722,31.6,53.6
en-de,xmu.4910,29.4,52.2
en-fi,AaltoHnmtFlatcat.4798,16.8,35.8
en-fi,AaltoHnmtMultitask.4873,20.4,40.0
en-fi,HY-AH.4797,12.2,29.4
en-fi,HY-HNMT.4961,20.4,40.1
en-fi,HY-SMT.4882,16.7,35.4
en-fi,TALP-UPC.4939,11.9,29.6
en-fi,apertium-unconstrained.4769,2.0,10.8
en-fi,jhu-nmt-lattice-rescore.4903,16.4,35.6
en-fi,jhu-pbmt.4968,15.7,34.4
en-fi,online-A.0,15.2,33.5
en-fi,online-B.0,21.4,41.2
en-fi,online-G.0,16.8,35.4
en-lv,C-3MA.5069,14.6,33.7
en-lv,HY-HNMT.5066,17.8,37.2
en-lv,KIT.5062,22.0,41.6
en-lv,LIUM-FNMT.5043,18.2,38.0
en-lv,LIUM-NMT.5042,19.1,38.8
en-lv,PJATK.4744,11.6,28.1
en-lv,QT21-System-Combination.5063,22.5,41.7
en-lv,jhu-pbmt.4969,16.7,36.0
en-lv,limsi-factored-norm.5041,20.5,39.7
en-lv,online-A.0,14.9,33.3
en-lv,online-B.0,20.9,40.4
en-lv,tilde-c-nmt-smt-hybrid.5049,23.0,42.6
en-lv,tilde-nc-nmt-smt-hybrid.5047,24.4,43.7
en-lv,tilde-nc-smt.5044,23.3,42.0
en-lv,uedin-nmt.5016,20.9,40.1
en-lv,usfd-consensus-kit.5078,20.9,40.0
en-lv,usfd-consensus-qt21.5077,21.4,40.5
en-ru,PROMT-Rule-based.4736,23.7,44.0
en-ru,afrl-mitll-backtrans.4907,22.8,45.1
en-ru,jhu-pbmt.4986,25.0,46.4
en-ru,online-A.0,23.5,45.1
en-ru,online-B.0,31.5,52.0
en-ru,online-F.0,14.0,32.4
en-ru,online-G.0,27.0,48.3
en-ru,online-H.0,27.7,49.3
en-ru,uedin-nmt.4756,28.6,49.9
en-tr,JAIST.4858,16.1,32.7
en-tr,LIUM-NMT.4953,19.1,36.3
en-tr,jhu-nmt-lattice-rescore.4904,14.6,31.6
en-tr,jhu-pbmt.4970,14.5,31.5
en-tr,online-A.0,17.4,34.5
en-tr,online-B.0,25.4,43.0
en-tr,online-G.0,20.7,37.7
en-tr,uedin-nmt.4932,19.0,37.2
en-zh,CASICT-DCU-NMT.5157,41.2,60.0
en-zh,Oregon-State-University-S.5174,34.8,56.0
en-zh,SogouKnowing-nmt.5131,47.2,63.7
en-zh,UU-HNMT.5134,32.9,54.0
en-zh,jhu-nmt.5153,39.8,60.0
en-zh,online-A.0,44.8,59.2
en-zh,online-B.0,46.9,62.1
en-zh,online-F.0,36.0,52.5
en-zh,online-G.0,40.7,55.5
en-zh,uedin-nmt.5111,47.6,64.4
en-zh,xmunmt.5165,45.7,64.4
fi-en,Hunter-MT.4925,22.4,47.4
fi-en,TALP-UPC.4937,19.9,43.6
fi-en,apertium-unconstrained.4793,21.2,33.5
fi-en,online-A.0,29.2,51.3
fi-en,online-B.0,34.5,56.7
fi-en,online-G.0,32.0,52.7
lv-en,C-3MA.5067,18.9,41.3
lv-en,Hunter-MT.5092,22.4,44.9
lv-en,PJATK.4740,17.9,38.9
lv-en,jhu-pbmt.4980,23.1,45.3
lv-en,online-A.0,25.1,45.6
lv-en,online-B.0,29.6,50.6
lv-en,tilde-c-nmt-smt-hybrid.5051,24.9,47.8
lv-en,tilde-nc-nmt-smt-hybrid.5050,29.8,50.9
lv-en,uedin-nmt.5017,25.5,47.5
ru-en,NRC.4855,38.0,60.3
ru-en,afrl-mitll-opennmt.4896,35.0,59.8
ru-en,afrl-mitll-syscomb.4905,37.3,60.8
ru-en,jhu-pbmt.4978,36.3,58.6
ru-en,online-A.0,34.5,58.1
ru-en,online-B.0,41.9,63.3
ru-en,online-F.0,24.9,46.7
ru-en,online-G.0,42.2,61.8
ru-en,uedin-nmt.4890,34.6,57.5
tr-en,JAIST.4859,24.8,44.7
tr-en,LIUM-NMT.4888,26.1,47.4
tr-en,PROMT-SMT.4737,28.6,47.7
tr-en,afrl-mitll-m2w-nr1.4901,26.1,47.3
tr-en,afrl-mitll-syscomb.4902,26.8,47.9
tr-en,jhu-pbmt.4972,23.0,44.2
tr-en,online-A.0,33.2,53.4
tr-en,online-B.0,37.0,56.3
tr-en,online-G.0,30.2,50.6
tr-en,uedin-nmt.4931,27.9,50.0
zh-en,CASICT-DCU-NMT.5144,29.7,50.3
zh-en,NMT-Model-Average-Multi-Cards.5099,26.2,46.6
zh-en,NRC.5172,32.4,52.7
zh-en,Oregon-State-University-S.5173,25.0,46.9
zh-en,PROMT-SMT.5125,29.1,47.7
zh-en,ROCMT.5183,27.9,48.9
zh-en,SogouKnowing-nmt.5171,35.1,54.2
zh-en,UU-HNMT.5162,23.9,44.6
zh-en,afrl-mitll-opennmt.5109,28.7,49.7
zh-en,jhu-nmt.5151,27.4,48.6
zh-en,online-A.0,32.9,53.0
zh-en,online-B.0,40.8,57.8
zh-en,online-F.0,23.2,42.6
zh-en,online-G.0,27.0,45.9
zh-en,uedin-nmt.5112,33.8,53.4
zh-en,xmunmt.5160,33.5,53.8"

if [ -z $SKIP_MACROF ]; then
  echo "----------------------------"
  echo "Testing MacroF1 and MicroF1"
  echo "----------------------------"
  wmt17dir=wmt17-submitted-data/txt/system-outputs/newstest2017
  echo "$MACF1_WMT17" |
    # shuf | head -30 |   # uncomment to run random 30 tests only
    tr ',' ' ' |
    while read pair name macf1_tru micf1_tru; do
      hyp=$wmt17dir/$pair/newstest2017.$name.$pair
      
      if [[ ! -z $limit_test && "$limit_test" != "$pair $name" ]]; then continue; fi

      #for chinese, use chinese tokenizer
      [[ "$pair" =~ .*-zh ]] && tokr='--tokenize zh' || tokr=''
      macf1_got=$(${CMD} -m macrof -l $pair -t wmt17 -b $tokr < $hyp)
      python -c "import sys; sys.exit(1 if abs(${macf1_got}-${macf1_tru}) > 0.01 else 0)"
      if [[ $? -eq 1 ]]; then
          echo "FAILED MacroF1 test $hyp (wanted ${macf1_tru} got $macf1_got)"
          exit 1
      fi

      micf1_got=$(${CMD} -m microf -l $pair -t wmt17 -b $tokr < $hyp)
      python -c "import sys; sys.exit(1 if abs(${micf1_got}-${micf1_tru}) > 0.01 else 0)"
      if [[ $? -eq 1 ]]; then
          echo "FAILED MicroF1 test $hyp (wanted ${micf1_tru} got $micf1_got)"
          exit 1
      fi
      echo "Pass: wmt17/$pair/$name MacroF1: $macf1_got == $macf1_tru || MicroF1 $micf1_got == $micf1_tru"
      let i++
    done
fi
####=============
echo "Passed $i tests."
exit 0
