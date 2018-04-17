#!/usr/bin/env perl

my $software_name = $ARGV[0];
my $software_version = $ARGV[1];

my $base_directory = '/nbi/software/testing/';
my $software_base_directory = $base_directory.'/'.$software_name.'/'.$software_version;
my $src_directory = $software_base_directory."/src";
my $arch_directory = $software_base_directory.'/x86_64';
my $arch_bin_directory = $arch_directory.'/bin';
my $img_filename_nopath = $software_name."-".$software_version.".img";
my $overall_bin = $base_directory."/bin";

`mkdir -p $src_directory`;
`mkdir -p $arch_directory`;
`mkdir -p $arch_bin_directory`;
`mkdir -p $overall_bin`;

# Create the base container
chdir $arch_directory;
my $create_cmd = "sudo singularity create -s 8192 $img_filename_nopath";
`$create_cmd`;

# create the definition
chdir $src_directory;

my $def_file_content = <<'DEF_FILE_CONTENT';
BootStrap: yum
OSVersion: 7
MirrorURL: http://mirror.centos.org/centos-%{OSVERSION}/%{OSVERSION}/os/\$basearch/
Include: yum
UpdateURL: http://yum-repos.hpccluster/centos/7/updates/$basearch/

%runscript
    echo "Please consult provided help for instructions on how to use this container"

%post
	export INST_DIR=/opt/software
	mkdir -p $INST_DIR

	#Pre-requirements
	yum -y install wget bzip2 tar

	# singularity 2.3 allows for biocontainer docker images to be imported, but we are currently on version 2.2, so cant.
	wget https://repo.continuum.io/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda.sh
	bash ~/miniconda.sh -b -p $INST_DIR/miniconda
	export PATH="$INST_DIR/miniconda/bin:$PATH"

	conda config --add channels defaults
	conda config --add channels conda-forge
	conda config --add channels bioconda
	conda install -y zlib
DEF_FILE_CONTENT

$def_file_content .= "\n\tconda install -y --only-deps ".$software_name."=".$software_version."\n";
$def_file_content .= "\n\tconda install -y zlib\n";
$def_file_content .= "\n\t".'ls $INST_DIR/miniconda/bin > $INST_DIR/binbefore'."\n";
$def_file_content .= "\n\tconda install -y ".$software_name."=".$software_version."\n";
$def_file_content .= "\n\t".'ls $INST_DIR/miniconda/bin > $INST_DIR/binafter'."\n";

$def_file_content .= <<'DEF_FILE_CONTENT';
	for i in `ls $INST_DIR/miniconda/bin`; do
		ln -s $INST_DIR/miniconda/bin/${i} /usr/local/bin/${i};
	done
	awk 'FNR==NR {a[$0]++; next} !a[$0]' $INST_DIR/binbefore $INST_DIR/binafter > $INST_DIR/unique_to_package

DEF_FILE_CONTENT

my $def_filename = $src_directory.'/'.$software_name."-".$software_version.'.def';
open(my $fhdef, '>', $def_filename);
print {$fhdef} $def_file_content;
close($fhdef);



# apply the definition file to the container
chdir $arch_directory;
my $bootstrap_cmd  = "sudo singularity bootstrap $img_filename_nopath $def_filename";
`$bootstrap_cmd`;

# prepare the overall wrapper script
chdir $arch_bin_directory;

my $wrapper_file_content = '#!/bin/bash'."\n";
$wrapper_file_content   .= 'DIR=`dirname $(readlink -f $0)`'."\n";
$wrapper_file_content   .= 'singularity exec $DIR/../'.$img_filename_nopath.' $(basename "$0") $@'."\n";

open(my $fhwrapper, '>', 'singularity.exec');
print {$fhwrapper} $wrapper_file_content;
close($fhwrapper);
`chmod +x singularity.exec`;

# Symlink the binaries created by just installing the software (and not dependancies)

my $linking_cmd  = "singularity exec $arch_directory/$img_filename_nopath cat /opt/software/unique_to_package | xargs -L 1 ln -s singularity.exec ";
`$linking_cmd`;

# Add wrapper to overall bin
chdir $overall_bin;

my $top_wrapper_filename = $software_name."-".$software_version;
my $top_wrapper_file_content = '#!/bin/bash'."\n";
$top_wrapper_file_content   .= 'export PATH="$PATH:'.$arch_bin_directory.'"'."\n";
open(my $fhtopwrapper, '>', $top_wrapper_filename);
print {$fhtopwrapper} $top_wrapper_file_content;
close($fhtopwrapper);
`chmod +x $top_wrapper_filename`;




BootStrap: yum
OSVersion: 7
MirrorURL: http://mirror.centos.org/centos-%{OSVERSION}/%{OSVERSION}/os/\$basearch/
Include: yum
UpdateURL: http://yum-repos.hpccluster/centos/7/updates/$basearch/

%runscript
    echo "Please consult provided help for instructions on how to use this container"

%post
	export INST_DIR=/opt/software
	mkdir -p $INST_DIR

	yum -y install wget bzip2 tar gzip
	
	wget https://repo.continuum.io/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda.sh
	bash ~/miniconda.sh -b -p $INST_DIR/miniconda
	export PATH="$INST_DIR/miniconda/bin:$PATH"

	conda config --add channels defaults
	conda config --add channels conda-forge
	conda config --add channels bioconda
	conda install -y zlib

	conda install samtools smalt bwa bowtie2 dos2unix git cpanminus 
	pip3 install pyfastaq biopython

	git clone https://github.com/andrewjpage/Bio-ReferenceManager.git
	cpanm Module::Metadata
	cd Bio-ReferenceManager && dzil authordeps | cpanm
	cd Bio-ReferenceManager && dzil listdeps | cpanm 
	cd Bio-ReferenceManager && dzil install
	