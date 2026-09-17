#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use 5.030;

use Digest::MD5 qw(md5_hex);
use Encode qw(decode encode_utf8 FB_CROAK);
use File::Basename qw(basename dirname);
use File::Find qw(find);
use File::Path qw(make_path remove_tree);
use File::Spec;
use File::Temp qw(tempfile);
use FindBin;
use IPC::Open3 qw(open3);
use JSON::PP;
use Symbol qw(gensym);
use lib "$FindBin::Bin/lib";

use Coff::Workflow qw(run_workflow llm user step attempt publish_files);

our $COFF_JSON = JSON::PP->new->canonical->utf8->allow_nonref;

my $workflow_file = 'workflow.pl';
if (@ARGV >= 2 && $ARGV[0] eq '--workflow') {
    shift @ARGV;
    $workflow_file = shift @ARGV;
}
die "invalid workflow filename\n"
    unless $workflow_file =~ /\A[A-Za-z0-9][A-Za-z0-9._-]*\.pl\z/;

my $workflow_path = File::Spec->catfile($FindBin::Bin, $workflow_file);
my $workflow_source = coff_read_text($workflow_path);
my $loaded = eval "use strict; use warnings;\n#line 1 \"$workflow_path\"\n$workflow_source\n1;";
die $@ || "cannot load $workflow_path\n" unless $loaded;
die "$workflow_path does not define workflow\n" unless defined &workflow;

my $name = basename(dirname($FindBin::Bin));
exit run_workflow(
    name     => $name,
    script   => $workflow_path,
    workflow => \&workflow,
    argv     => \@ARGV,
);

sub coff_read_text {
    my ($path) = @_;
    open my $fh, '<:raw', $path or die "cannot read $path: $!\n";
    local $/;
    my $raw = <$fh>;
    close $fh or die "cannot close $path: $!\n";
    my $text = eval { decode('UTF-8', $raw, FB_CROAK) };
    die "$path is not UTF-8: $@\n" if $@;
    return $text;
}

sub coff_file_md5 {
    my ($path) = @_;
    open my $fh, '<:raw', $path or die "cannot read $path: $!\n";
    my $digest = Digest::MD5->new->addfile($fh)->hexdigest;
    close $fh or die "cannot close $path: $!\n";
    return $digest;
}

sub coff_footer_md5 {
    my ($path) = @_;
    return undef unless -f $path;
    open my $fh, '<:raw', $path or die "cannot read $path: $!\n";
    my $last = '';
    $last = $_ while <$fh>;
    close $fh or die "cannot close $path: $!\n";
    return $1 if $last =~ /"md5":"([a-f0-9]{32})"/;
    return undef;
}

sub coff_decode_json {
    my ($raw) = @_;
    my $value = eval { $COFF_JSON->decode(encode_utf8($raw)) };
    die "invalid JSON: $@\n" if $@;
    return $value;
}

sub coff_encode_json {
    return $COFF_JSON->encode($_[0]);
}

sub coff_check_perl {
    my ($content) = @_;
    my ($fh, $path) = tempfile('coff-workflow-XXXXXX', SUFFIX => '.pl', TMPDIR => 1, UNLINK => 1);
    binmode $fh, ':raw';
    print {$fh} utf8::is_utf8($content) ? encode_utf8($content) : $content;
    close $fh or die "cannot close $path: $!\n";

    my $error = gensym;
    my $pid = open3(my $input, my $output, $error, $^X, '-c', $path);
    close $input;
    local $/;
    my $diagnostic = (<$output> // '') . (<$error> // '');
    waitpid($pid, 0);
    return if ($? >> 8) == 0;
    $diagnostic =~ s/\Q$path\E/workflow.pl/g;
    $diagnostic =~ s/\s+\z//;
    die "perl -c failed for workflow.pl: $diagnostic\n";
}
