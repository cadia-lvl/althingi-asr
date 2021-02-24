
#!/bin/bash

. ./path.sh
. ./cmd.sh
. ./utils/parse_options.sh || exit 1;

#date
d=$(date +'%Y%m%d')

lmdir=$(ls -td $root_lm_modeldir/20* | head -n1)
decoding_lang=$lmdir/lang_3gsmall

am_model=$(ls -td $root_chain/*/*/* | head -n1)
ampath=$(dirname $am_model)

if [ $am_model = $ampath/$d ]; then
  am_model=$(ls -td $root_chain/*/*/* | head -n2 | tail -n1)
fi

outdir=$ampath/$d
[ -d $outdir ] && echo "$outdir already exists" && exit 1;
mkdir -p $outdir/log

echo "Make a small 3-gram graph"
utils/mkgraph.sh --self-loop-scale 1.0 $decoding_lang $am_model $outdir/graph_3gsmall &>$outdir/log/mkgraph.log

# Create symlinks in the new model dir to the old one
for f in cmvn_opts extractor final.ie.id final.mdl frame_subsampling_factor tree ; do
  #ln -s $am_model/$f $outdir/$f
  cp -r -L $am_model/$f $outdir/$f
done
ln -s $(dirname $decoding_lang) $outdir/lmdir

echo $lmdir > $outdir/lminfo

exit 0;
