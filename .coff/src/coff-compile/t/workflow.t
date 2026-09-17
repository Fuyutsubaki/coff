use strict;
use warnings;
use 5.030;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use IPC::Open3;
use JSON::PP;
use Symbol qw(gensym);
use Test::More;

use Coff::Workflow qw(publish_files);

my $JSON = JSON::PP->new->utf8;
my $tmp = tempdir(CLEANUP => 1);
my $state = File::Spec->catdir($tmp, 'state');
my $counter = File::Spec->catfile($tmp, 'counter');
my $lib = File::Spec->rel2abs(
    File::Spec->catdir(File::Spec->curdir(), '.coff', 'src', 'coff-compile', 'scripts', 'lib'),
);
my $script = File::Spec->catfile($tmp, 'sample.pl');

write_script($script, 'a' x 32);

my ($status, $stdout, $stderr) = run_script('start', 'stable');
is($status, 0, 'start succeeds');
is($stderr, '', 'start has no stderr');
my $first = decode_line($stdout);
is($first->{ask}{kind}, 'llm', 'start returns the first llm question');
is($first->{ask}{topic}, 'draft', 'question has a topic');
is($first->{index}, 0, 'first effect has index zero');
my $run = $first->{run};

($status, $stdout, $stderr) = run_script('status', $run);
is($status, 0, 'status succeeds');
is_deeply(decode_line($stdout), $first, 'status repeats the pending question');

($status, $stdout, $stderr) = run_script_with_input("draft answer", 'resume', $run, 0);
is($status, 0, 'first resume succeeds');
my $second = decode_line($stdout);
is($second->{ask}{kind}, 'user', 'resume advances to the user question');
is($second->{index}, 1, 'second effect has the next index');

($status, $stdout, $stderr) = run_script_with_input("draft answer", 'resume', $run, 0);
is($status, 0, 'resending the same answer succeeds');
is_deeply(decode_line($stdout), $second, 'resending does not advance the workflow');
ok(!-e $counter, 'resending does not execute a later step');

($status, $stdout, $stderr) = run_script_with_input("different answer", 'resume', $run, 0);
isnt($status, 0, 'resending a different answer is rejected');
like($stderr, qr/already answered differently/, 'different resend reports the conflict');

($status, $stdout, $stderr) = run_script_with_input("yes", 'resume', $run, 1);
is($status, 0, 'second resume succeeds');
my $done = decode_line($stdout);
ok($done->{done}, 'workflow reaches done');
is($done->{report}{value}, 'draft answer:yes', 'answers reach the workflow');
is(read_file($counter), "1\n", 'step runs once');

($status, $stdout, $stderr) = run_script_with_input("yes", 'resume', $run, 1);
is($status, 0, 'resume of a completed run succeeds');
is_deeply(decode_line($stdout), $done, 'completed resume repeats the terminal result');
is(read_file($counter), "1\n", 'completed resume does not repeat the step');
ok(!-e File::Spec->catfile($state, 'coff', 'sample', $run, 'journal.json'), 'done removes the journal');
ok(-e File::Spec->catfile($state, 'coff', 'sample', $run, 'terminal.json'), 'done leaves a terminal marker');

my $version_script = File::Spec->catfile($tmp, 'version.pl');
$script = $version_script;
write_script($script, 'b' x 32);
($status, $stdout, $stderr) = run_script('start', 'stable');
my $version_run = decode_line($stdout)->{run};
write_script($script, 'c' x 32);
($status, $stdout, $stderr) = run_script_with_input('answer', 'resume', $version_run, 0);
isnt($status, 0, 'resume rejects a changed workflow');
like($stderr, qr/workflow changed/, 'version error names the workflow');

my $runtime_script = File::Spec->catfile($tmp, 'runtime-version.pl');
$script = $runtime_script;
write_script($script, 'f' x 32);
($status, $stdout, $stderr) = run_script('start', 'stable');
my $runtime_run = decode_line($stdout)->{run};
my $runtime_journal_path = File::Spec->catfile(
    $state, 'coff', 'sample', $runtime_run, 'journal.json',
);
my $runtime_journal = $JSON->decode(read_file($runtime_journal_path));
$runtime_journal->{runtime_md5} = '0' x 32;
write_file($runtime_journal_path, $JSON->canonical->encode($runtime_journal) . "\n");
($status, $stdout, $stderr) = run_script_with_input('answer', 'resume', $runtime_run, 0);
isnt($status, 0, 'resume rejects a changed runtime');
like($stderr, qr/Coff::Workflow changed/, 'version error names the runtime');

my $nondeterministic_script = File::Spec->catfile($tmp, 'nondeterministic.pl');
$script = $nondeterministic_script;
write_script($script, 'd' x 32);
($status, $stdout, $stderr) = run_script('start', 'stable');
my $nondeterministic_run = decode_line($stdout)->{run};
my $journal_path = File::Spec->catfile(
    $state, 'coff', 'sample', $nondeterministic_run, 'journal.json',
);
my $journal = $JSON->decode(read_file($journal_path));
$journal->{effects}[0]{input_hash} = '0' x 32;
write_file($journal_path, $JSON->canonical->encode($journal) . "\n");
($status, $stdout, $stderr) = run_script_with_input('answer', 'resume', $nondeterministic_run, 0);
isnt($status, 0, 'resume stops on non-determinism');
like($stderr, qr/non-deterministic workflow/, 'non-determinism is reported');
ok(-e $journal_path, 'non-determinism keeps the journal for inspection');

my $cancel_script = File::Spec->catfile($tmp, 'cancel.pl');
$script = $cancel_script;
write_script($script, 'e' x 32);
($status, $stdout, $stderr) = run_script('start', 'stable');
my $cancel_run = decode_line($stdout)->{run};
($status, $stdout, $stderr) = run_script('cancel', $cancel_run);
my $cancelled = decode_line($stdout);
ok($cancelled->{cancelled}, 'cancel records cancellation');
ok($cancelled->{done}, 'cancel is terminal');
($status, $stdout, $stderr) = run_script_with_input('late', 'resume', $cancel_run, 0);
is_deeply(decode_line($stdout), $cancelled, 'cancelled resume repeats the terminal result');

my $old = File::Spec->catdir($state, 'coff', 'sample', 'old-run');
make_path($old);
utime(time - 8 * 24 * 60 * 60, time - 8 * 24 * 60 * 60, $old);
($status, $stdout, $stderr) = run_script('gc');
is($status, 0, 'gc succeeds');
cmp_ok(decode_line($stdout)->{gc}, '>=', 1, 'gc reports removed runs');
ok(!-e $old, 'gc removes runs older than seven days');

my $publish = File::Spec->catdir($tmp, 'publish');
my $skill_path = File::Spec->catfile($publish, 'SKILL.md');
my $perl_path = File::Spec->catfile($publish, 'scripts', 'sample.pl');
my $module_path = File::Spec->catfile($publish, 'scripts', 'lib', 'Coff', 'Workflow.pm');
make_path(File::Spec->catdir($publish, 'scripts', 'lib', 'Coff'));
write_file($skill_path, "old skill\n");
write_file($perl_path, "old perl\n");
write_file($module_path, "old module\n");

my $result = publish_files(
    files => [
        { path => $skill_path, content => "new skill\n" },
        { path => $perl_path, content => "my \\x = ;\n", check_perl => 1 },
        { path => $module_path, content => "new module\n" },
    ],
    perl_inc => [$lib],
);
ok(!$result->{ok}, 'publish rejects invalid Perl');
is(read_file($skill_path), "old skill\n", 'invalid Perl leaves SKILL.md unchanged');
is(read_file($perl_path), "old perl\n", 'invalid Perl leaves the script unchanged');
is(read_file($module_path), "old module\n", 'invalid Perl leaves the bundle unchanged');

$result = publish_files(
    files => [
        { path => $skill_path, content => "new skill\n" },
        { path => $perl_path, content => "use strict;\n1;\n", check_perl => 1 },
        { path => $module_path, content => "new module\n" },
    ],
    perl_inc => [$lib],
);
ok($result->{ok}, 'publish accepts valid Perl');
is(read_file($skill_path), "new skill\n", 'valid publish replaces SKILL.md');
is(read_file($perl_path), "use strict;\n1;\n", 'valid publish replaces the script');
is(read_file($module_path), "new module\n", 'valid publish replaces the bundle');

done_testing();

sub write_script {
    my ($path, $md5) = @_;
    my $quoted_lib = $lib;
    $quoted_lib =~ s/(['\\])/\\$1/g;
    my $quoted_counter = $counter;
    $quoted_counter =~ s/(['\\])/\\$1/g;
    write_file($path, <<"PERL");
use strict;
use warnings;
use lib '$quoted_lib';
use Coff::Workflow qw(run_workflow llm user step);
exit run_workflow(
    name => 'sample',
    script => \$0,
    workflow => sub {
        my (\$mode) = \@_;
        my \$draft = llm('draft', { mode => \$mode });
        my \$confirmed = user('confirm', { draft => \$draft });
        my \$value = step {
            my \$count = 0;
            if (open my \$in, '<', '$quoted_counter') {
                \$count = <\$in> // 0;
                close \$in;
            }
            open my \$out, '>', '$quoted_counter' or die \$!;
            print {\$out} \$count + 1, "\\n";
            close \$out;
            return "\$draft:\$confirmed";
        } 'write', { draft => \$draft, confirmed => \$confirmed };
        return { value => \$value };
    },
);
# <!--{"src":"sample","md5":"$md5"} -->
PERL
}

sub run_script {
    return run_script_with_input('', @_);
}

sub run_script_with_input {
    my ($input, @args) = @_;
    my $error = gensym;
    local %ENV = (%ENV, XDG_STATE_HOME => $state);
    my $pid = open3(my $in, my $out, $error, $^X, $script, @args);
    print {$in} $input;
    close $in;
    local $/;
    my $stdout = <$out> // '';
    my $stderr = <$error> // '';
    waitpid($pid, 0);
    return ($? >> 8, $stdout, $stderr);
}

sub decode_line {
    my ($line) = @_;
    return $JSON->decode($line);
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
    make_path(File::Basename::dirname($path));
    open my $fh, '>:raw', $path or die "cannot write $path: $!";
    print {$fh} $content;
    close $fh;
}
