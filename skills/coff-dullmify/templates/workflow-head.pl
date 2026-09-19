#!/usr/bin/env perl
# ここから sub workflow の手前までは coff-dullmify が差し込む土台で、LLM は書かない。
use strict;
use warnings;
use utf8;
use 5.030;

use File::Basename qw(basename dirname);
use File::Spec;
use FindBin;
use lib "$FindBin::Bin/lib";
use Coff::Workflow qw(run_workflow llm step);

