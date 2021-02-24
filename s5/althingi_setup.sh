#!/bin/bash

# Run from the s5 dir

# ASSET_ROOT is defined in path.sh and path.sh runs
# conf/path.conf where the rest of the path variables are defined
# NOTE! Make sure the paths fit to your system setup!

# Make a temporary file for setting up the required directories, based on the directories in conf/path.conf
echo '#!/bin/bash' > tmp.sh
echo '. path.sh' >> tmp.sh
for v in $(egrep "=" conf/path.conf | egrep -v "^#" | cut -d'=' -f1); do echo "mkdir -p $"$v >>tmp.sh; done
echo 'echo Done' >> tmp.sh
echo 'exit 0;' >> tmp.sh

# Change the permissions for tmp.sh 
chmod +x tmp.sh

echo "Setting up data and model directories"
tmp.sh

# thraxgrammar_lex is a symlink not a directory so
rm -r $root_thraxgrammar_lex
ln -s $ASSET_ROOT/ASR/local/thraxgrammar/lex $root_text_norm_listdir/thraxgrammar_lex

# Remove tmp.sh
rm tmp.sh

exit 0
