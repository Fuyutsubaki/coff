#!/usr/bin/env perl
use strict; use warnings; use utf8; use 5.030;

use File::Basename qw(basename dirname);
use FindBin;
use lib "$FindBin::Bin/lib";
use Coff::Workflow qw(run_workflow llm step);

# 同じディレクトリの workflow 本体を読み込む。
my $workflow_path = "$FindBin::Bin/workflow.pl";
local $! = 0;
my $loaded = do $workflow_path;
die $@ if $@;
die "cannot load $workflow_path: $!\n" if !defined($loaded) && $!;
die "$workflow_path does not define workflow\n" unless defined &workflow;

# 親の skill 名で runtime を起動する。
exit run_workflow(name => basename(dirname($FindBin::Bin)),
    workflow => \&workflow, argv => \@ARGV);
