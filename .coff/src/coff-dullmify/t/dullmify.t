use strict;
use warnings;
use 5.030;

use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use IPC::Open3;
use JSON::PP;
use Symbol qw(gensym);
use Test::More;

my $JSON = JSON::PP->new->utf8;
my $tmp = tempdir(CLEANUP => 1);
my $state = File::Spec->catdir($tmp, 'state');
my $run_pl = File::Spec->rel2abs(
    File::Spec->catfile('.coff', 'src', 'coff-dullmify', 'scripts', 'run.pl'),
);
my $source_root = File::Spec->rel2abs(
    File::Spec->catdir('.coff', 'src', 'coff-dullmify'),
);

my $new_out = File::Spec->catdir($tmp, 'invalid-new');
my ($status, $stdout, $stderr) = run_dullmify(
    $new_out,
    "sub workflow {\n",
    "### topic `sample`\n\nReturn text.",
);
isnt($status, 0, 'invalid generated workflow fails');
like($stderr, qr/perl -c failed/, 'invalid workflow reports the syntax gate');
ok(!-e $new_out, 'invalid workflow does not create a new output directory');

my $old_out = File::Spec->catdir($tmp, 'invalid-existing');
my %old = (
    'SKILL.md'                         => "old skill\n",
    'scripts/run.pl'                   => "old driver\n",
    'scripts/workflow.pl'              => "old workflow\n",
    'scripts/lib/Coff/Workflow.pm'     => "old runtime\n",
);
for my $relative (sort keys %old) {
    write_file(File::Spec->catfile($old_out, split m{/}, $relative), $old{$relative});
}
($status, $stdout, $stderr) = run_dullmify(
    $old_out,
    "sub workflow {\n",
    "### topic `sample`\n\nReturn text.",
);
isnt($status, 0, 'invalid workflow fails with existing output');
for my $relative (sort keys %old) {
    is(
        read_file(File::Spec->catfile($old_out, split m{/}, $relative)),
        $old{$relative},
        "$relative stays unchanged",
    );
}

my $valid_out = File::Spec->catdir($tmp, 'valid');
my $topics = "### topic `sample`\n\nReturn a short text answer.";
($status, $stdout, $stderr) = run_dullmify(
    $valid_out,
    "sub workflow {\n    return [];\n}",
    $topics,
);
is($status, 0, 'valid dullmify run succeeds') or diag($stderr);
my $done = $JSON->decode($stdout);
ok($done->{done}, 'valid dullmify run reaches done');

my @expected = (
    'SKILL.md',
    'scripts/run.pl',
    'scripts/workflow.pl',
    'scripts/lib/Coff/Workflow.pm',
);
for my $relative (@expected) {
    ok(-f File::Spec->catfile($valid_out, split m{/}, $relative), "$relative is generated");
}
is(
    read_file(File::Spec->catfile($valid_out, 'scripts', 'run.pl')),
    read_file(File::Spec->catfile($source_root, 'scripts', 'run.pl')),
    'run.pl is copied byte-for-byte',
);
is(
    read_file(File::Spec->catfile($valid_out, 'scripts', 'lib', 'Coff', 'Workflow.pm')),
    read_file(File::Spec->catfile($source_root, 'scripts', 'lib', 'Coff', 'Workflow.pm')),
    'runtime is copied byte-for-byte',
);

my $skill = read_file(File::Spec->catfile($valid_out, 'SKILL.md'));
my $prefix = read_file(File::Spec->catfile($source_root, 'templates', 'skill-prefix.md'));
my $suffix = read_file(File::Spec->catfile($source_root, 'templates', 'skill-suffix.md'));
ok(index($skill, $prefix) >= 0, 'SKILL.md contains the byte-identical prefix template');
ok(index($skill, $suffix) >= 0, 'SKILL.md contains the byte-identical suffix template');
like($skill, qr/allowed-tools: Bash\(perl \$\{CLAUDE_SKILL_DIR\}\/scripts\/run\.pl \*\)/, 'SKILL.md allows only run.pl');
unlike($skill, qr/^coff-/m, 'SKILL.md has no coff build keys');
unlike($skill, qr/<!--\{"src":/, 'raw SKILL.md has no footer');
like(read_file(File::Spec->catfile($valid_out, 'scripts', 'workflow.pl')), qr/\Ause utf8;\n\nsub workflow/, 'workflow.pl declares utf8 and contains only generated functions');

done_testing();

sub run_dullmify {
    my ($out, $workflow_body, $topics) = @_;
    my ($status, $stdout, $stderr) = run_process(
        '', '--workflow', 'dullmify.pl', 'start', '.coff/src/coff-compile.skill.md', '-o', $out,
    );
    return ($status, $stdout, $stderr) if $status;
    my $question = $JSON->decode($stdout);
    is($question->{ask}{topic}, 'workflow', 'first dullmify question is workflow');
    if (-f File::Spec->catfile($out, 'scripts', 'workflow.pl')) {
        unlike($question->{ask}{input}{existing}, qr/\Ause utf8;/, 'existing omits the use utf8 line');
    }
    else {
        is($question->{ask}{input}{existing}, '', 'existing is empty when the output has no workflow');
    }
    my $run = $question->{run};

    ($status, $stdout, $stderr) = run_process(
        $workflow_body,
        '--workflow', 'dullmify.pl', 'resume', $run, $question->{index},
    );
    return ($status, $stdout, $stderr) if $status;
    $question = $JSON->decode($stdout);
    is($question->{ask}{topic}, 'topics', 'second dullmify question is topics');

    return run_process(
        $topics,
        '--workflow', 'dullmify.pl', 'resume', $run, $question->{index},
    );
}

sub run_process {
    my ($input, @args) = @_;
    my $error = gensym;
    local %ENV = (%ENV, XDG_STATE_HOME => $state);
    my $pid = open3(my $in, my $out, $error, $^X, $run_pl, @args);
    print {$in} $input;
    close $in;
    local $/;
    my $stdout = <$out> // '';
    my $stderr = <$error> // '';
    waitpid($pid, 0);
    return ($? >> 8, $stdout, $stderr);
}

sub read_file {
    my ($path) = @_;
    open my $fh, '<:raw', $path or die "cannot read $path: $!";
    local $/;
    my $content = <$fh>;
    close $fh;
    return $content;
}

sub write_file {
    my ($path, $content) = @_;
    make_path(dirname($path));
    open my $fh, '>:raw', $path or die "cannot write $path: $!";
    print {$fh} $content;
    close $fh;
}
