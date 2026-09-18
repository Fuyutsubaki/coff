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
my $workflow_pl = File::Spec->rel2abs(
    File::Spec->catfile('.claude', 'skills', 'coff-dullmify', 'scripts', 'workflow.pl'),
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
is($stderr, '', 'workflow failure is returned as JSON');
like(decode_output($stdout)->{failed}, qr/perl -c failed/, 'invalid workflow reports the syntax gate');
ok(!-e $new_out, 'invalid workflow does not create a new output directory');

my $old_out = File::Spec->catdir($tmp, 'invalid-existing');
my %old = (
    'SKILL.md'                     => "old skill\n",
    'scripts/workflow.pl'          => "use utf8;\n\nsub workflow { return ['old']; }\n",
    'scripts/lib/Coff/Workflow.pm' => "old runtime\n",
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
my $done = decode_output($stdout);
ok($done->{done}, 'valid dullmify run reaches done');

my @expected = (
    'SKILL.md',
    'scripts/workflow.pl',
    'scripts/lib/Coff/Workflow.pm',
);
for my $relative (@expected) {
    ok(-f File::Spec->catfile($valid_out, split m{/}, $relative), "$relative is generated");
}
my $head = read_file(File::Spec->catfile($source_root, 'templates', 'workflow-head.pl'));
my $tail = read_file(File::Spec->catfile($source_root, 'templates', 'workflow-tail.pl'));
my $generated_workflow = read_file(File::Spec->catfile($valid_out, 'scripts', 'workflow.pl'));
is(substr($generated_workflow, 0, length $head), $head, 'workflow.pl starts with the byte-identical head template');
is(substr($generated_workflow, -length $tail), $tail, 'workflow.pl ends with the byte-identical tail template');
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
like($skill, qr/allowed-tools: Bash\(perl \$\{CLAUDE_SKILL_DIR\}\/scripts\/workflow\.pl \*\)/, 'SKILL.md allows only workflow.pl');
unlike($skill, qr/^coff-/m, 'SKILL.md has no coff build keys');
unlike($skill, qr/<!--\{"src":/, 'raw SKILL.md has no footer');
like($generated_workflow, qr/\nsub workflow\b/, 'workflow.pl contains the generated workflow');

done_testing();

sub run_dullmify {
    my ($out, $workflow_body, $topics) = @_;
    my ($status, $stdout, $stderr) = run_process(
        '', 'start', '.coff/src/coff-compile.skill.md', '-o', $out,
    );
    return ($status, $stdout, $stderr) if $status;
    my $question = decode_output($stdout);
    is($question->{ask}{topic}, 'workflow', 'first dullmify question is workflow');
    my $existing_path = File::Spec->catfile($out, 'scripts', 'workflow.pl');
    if (-f $existing_path) {
        is(
            $question->{ask}{input}{existing},
            strip_generated(read_file($existing_path)),
            'existing workflow is passed without the templates and the footer',
        );
    }
    else {
        is($question->{ask}{input}{existing}, '', 'existing is empty without an output workflow');
    }
    my $run = $question->{run};

    ($status, $stdout, $stderr) = run_process(
        $workflow_body, 'resume', $run, $question->{index},
    );
    return ($status, $stdout, $stderr) if $status;
    $question = decode_output($stdout);
    is($question->{ask}{topic}, 'topics', 'second dullmify question is topics');

    return run_process($topics, 'resume', $run, $question->{index});
}

sub run_process {
    my ($input, @args) = @_;
    my $error = gensym;
    local %ENV = (%ENV, XDG_STATE_HOME => $state);
    my $pid = open3(my $in, my $out, $error, $^X, $workflow_pl, @args);
    print {$in} $input;
    close $in;
    local $/;
    my $stdout = <$out> // '';
    my $stderr = <$error> // '';
    waitpid($pid, 0);
    return ($? >> 8, $stdout, $stderr);
}

sub decode_output {
    return $JSON->decode($_[0]);
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

# 雛形の頭と尻と coff-compile のフッタを除いた形（dullmify が LLM に渡す形）
sub strip_generated {
    my ($text) = @_;
    my $head = read_file(File::Spec->catfile($source_root, 'templates', 'workflow-head.pl'));
    my $tail = read_file(File::Spec->catfile($source_root, 'templates', 'workflow-tail.pl'));
    $text =~ s/\n?# <!--\{"src":.*?"md5":"[a-f0-9]{32}"\} -->\s*\z//s;
    $text = substr($text, length $head) if index($text, $head) == 0;
    $text =~ s/\s+\z//;
    (my $trimmed_tail = $tail) =~ s/\s+\z//;
    $text = substr($text, 0, length($text) - length($trimmed_tail))
        if length($text) >= length($trimmed_tail) && substr($text, -length($trimmed_tail)) eq $trimmed_tail;
    $text =~ s/\s+\z//;
    return $text;
}
