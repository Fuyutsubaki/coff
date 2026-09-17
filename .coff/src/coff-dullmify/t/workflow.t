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

use Coff::Workflow qw(publish_files);

my $JSON = JSON::PP->new->utf8;
my $tmp = tempdir(CLEANUP => 1);
my $state = File::Spec->catdir($tmp, 'state');
my $counter = File::Spec->catfile($tmp, 'counter');
my $lib = File::Spec->rel2abs(
    File::Spec->catdir('.coff', 'src', 'coff-dullmify', 'scripts', 'lib'),
);
my $script = File::Spec->catfile($tmp, 'sample.pl');

write_script($script, 'first');

my ($status, $stdout, $stderr) = run_script('start', 'stable');
is($status, 0, 'start succeeds');
is($stderr, '', 'start has no stderr');
my $first = decode_line($stdout);
is($first->{ask}{kind}, 'llm', 'attempt rethrows suspension');
is($first->{ask}{topic}, 'draft', 'start returns the first topic');
is($first->{index}, 0, 'first question has index zero');
my $run = $first->{run};

($status, $stdout, $stderr) = run_script('status', $run);
is_deeply(decode_line($stdout), $first, 'status repeats the pending question');

($status, $stdout, $stderr) = run_script_with_input('draft answer', 'resume', $run, 0);
is($status, 0, 'first resume succeeds');
my $second = decode_line($stdout);
is($second->{ask}{kind}, 'user', 'resume advances to the user question');
is($second->{index}, 2, 'second question follows the recorded step');
my $snapshot_journal = $JSON->decode(read_file(journal_path($run)));
is(
    $snapshot_journal->{effects}[1]{result}{value},
    'journal value',
    'step result in the journal is isolated from workflow mutation',
);
is(
    $second->{ask}{input}{snapshot},
    'workflow value',
    'the workflow can mutate its detached return value',
);

($status, $stdout, $stderr) = run_script_with_input('draft answer', 'resume', $run, 0);
is_deeply(decode_line($stdout), $second, 'same answer resend does not advance');
ok(!-e $counter, 'same answer resend does not execute the step');

($status, $stdout, $stderr) = run_script_with_input('different', 'resume', $run, 0);
isnt($status, 0, 'different answer resend is rejected');
like($stderr, qr/already answered differently/, 'different resend reports the conflict');

($status, $stdout, $stderr) = run_script_with_input('yes', 'resume', $run, 2);
is($status, 0, 'second resume succeeds');
my $done = decode_line($stdout);
ok($done->{done}, 'workflow reaches done');
is($done->{report}{value}, 'draft answer:yes', 'answers reach the workflow');
like($done->{report}{caught}, qr/caught failure/, 'attempt catches ordinary failure');
is(read_file($counter), "1\n", 'block-only step runs once');

($status, $stdout, $stderr) = run_script_with_input('yes', 'resume', $run, 2);
is_deeply(decode_line($stdout), $done, 'completed resume repeats the terminal result');
is(read_file($counter), "1\n", 'completed resume does not repeat the step');
ok(!-e journal_path($run), 'done removes the journal');
ok(-e terminal_path($run), 'done leaves the terminal result');

write_script($script, 'version-one');
($status, $stdout, $stderr) = run_script('start', 'stable');
my $version_run = decode_line($stdout)->{run};
write_script($script, 'version-two');
($status, $stdout, $stderr) = run_script_with_input('answer', 'resume', $version_run, 0);
isnt($status, 0, 'resume rejects changed workflow.pl bytes');
like($stderr, qr/workflow changed/, 'workflow version error is reported');

write_script($script, 'runtime-version');
($status, $stdout, $stderr) = run_script('start', 'stable');
my $runtime_run = decode_line($stdout)->{run};
my $runtime_journal = $JSON->decode(read_file(journal_path($runtime_run)));
$runtime_journal->{runtime_md5} = '0' x 32;
write_file(journal_path($runtime_run), $JSON->canonical->encode($runtime_journal) . "\n");
($status, $stdout, $stderr) = run_script_with_input('answer', 'resume', $runtime_run, 0);
isnt($status, 0, 'resume rejects a changed runtime');
like($stderr, qr/Coff::Workflow changed/, 'runtime version error is reported');

write_script($script, 'non-deterministic');
($status, $stdout, $stderr) = run_script('start', 'stable');
my $nondeterministic_run = decode_line($stdout)->{run};
my $journal = $JSON->decode(read_file(journal_path($nondeterministic_run)));
$journal->{effects}[0]{input_hash} = '0' x 32;
write_file(journal_path($nondeterministic_run), $JSON->canonical->encode($journal) . "\n");
($status, $stdout, $stderr) = run_script_with_input('answer', 'resume', $nondeterministic_run, 0);
isnt($status, 0, 'resume stops on changed llm input hash');
like($stderr, qr/non-deterministic workflow/, 'non-determinism is reported');
ok(-e journal_path($nondeterministic_run), 'non-determinism keeps the journal');

write_script($script, 'cancel');
($status, $stdout, $stderr) = run_script('start', 'stable');
my $cancel_run = decode_line($stdout)->{run};
($status, $stdout, $stderr) = run_script('cancel', $cancel_run);
my $cancelled = decode_line($stdout);
ok($cancelled->{cancelled}, 'cancel records cancellation');
($status, $stdout, $stderr) = run_script_with_input('late', 'resume', $cancel_run, 0);
is_deeply(decode_line($stdout), $cancelled, 'cancelled resume repeats the terminal result');

my $old = File::Spec->catdir($state, 'coff', 'sample', 'old-run');
make_path($old);
utime(time - 8 * 24 * 60 * 60, time - 8 * 24 * 60 * 60, $old);
($status, $stdout, $stderr) = run_script('gc');
cmp_ok(decode_line($stdout)->{gc}, '>=', 1, 'gc removes an old run');
ok(!-e $old, 'gc removes runs older than seven days');

my $publish = File::Spec->catdir($tmp, 'publish');
my $skill_path = File::Spec->catfile($publish, 'SKILL.md');
my $perl_path = File::Spec->catfile($publish, 'scripts', 'workflow.pl');
my $module_path = File::Spec->catfile($publish, 'scripts', 'lib', 'Coff', 'Workflow.pm');
make_path(dirname($module_path));
write_file($skill_path, "old skill\n");
write_file($perl_path, "old perl\n");
write_file($module_path, "old module\n");

my $publish_error = eval {
    publish_files(
        files => [
            { path => $skill_path, content => "new skill\n" },
            { path => $perl_path, content => "my \\x = ;\n", check_perl => 1 },
            { path => $module_path, content => "new module\n" },
        ],
        perl_inc => [$lib],
    );
    '';
};
$publish_error = $@ if $@;
like($publish_error, qr/perl -c failed/, 'invalid Perl dies');
is(read_file($skill_path), "old skill\n", 'invalid Perl leaves SKILL.md unchanged');
is(read_file($perl_path), "old perl\n", 'invalid Perl leaves workflow unchanged');
is(read_file($module_path), "old module\n", 'invalid Perl leaves runtime unchanged');

my $published = publish_files(
    files => [
        { path => $skill_path, content => "new skill\n" },
        { path => $perl_path, content => "use utf8;\nsub workflow { return [] }\n", check_perl => 1 },
        { path => $module_path, content => "new module\n" },
    ],
    perl_inc => [$lib],
);
is($published->{changed}, 3, 'valid publish replaces all files');

done_testing();

sub write_script {
    my ($path, $marker) = @_;
    my $quoted_lib = $lib;
    $quoted_lib =~ s/(['\\])/\\$1/g;
    my $quoted_counter = $counter;
    $quoted_counter =~ s/(['\\])/\\$1/g;
    write_file($path, <<"PERL");
use strict;
use warnings;
use utf8;
use lib '$quoted_lib';
use Coff::Workflow qw(run_workflow llm user step attempt);
exit run_workflow(
    name => 'sample',
    script => \$0,
    workflow => sub {
        my (\$mode) = \@_;
        my (\$draft, \$ask_error) = attempt { llm('draft', { mode => \$mode }) };
        die \$ask_error if \$ask_error;
        my (\$unused, \$caught) = attempt { die "caught failure\\n" };
        my \$snapshot = step { return { value => 'journal value' } };
        \$snapshot->{value} = 'workflow value';
        my \$confirmed = user('confirm', {
            draft    => \$draft,
            snapshot => \$snapshot->{value},
        });
        my \$value = step {
            my \$count = -e '$quoted_counter' ? 0 + do {
                open my \$in, '<', '$quoted_counter' or die \$!;
                my \$current = <\$in> // 0;
                close \$in;
                \$current;
            } : 0;
            open my \$out, '>', '$quoted_counter' or die \$!;
            print {\$out} \$count + 1, "\\n";
            close \$out;
            return "\$draft:\$confirmed";
        };
        return { value => \$value, caught => \$caught };
    },
);
# $marker
PERL
}

sub run_script { return run_script_with_input('', @_) }

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

sub journal_path {
    return File::Spec->catfile($state, 'coff', 'sample', $_[0], 'journal.json');
}

sub terminal_path {
    return File::Spec->catfile($state, 'coff', 'sample', $_[0], 'terminal.json');
}

sub decode_line { return $JSON->decode($_[0]) }

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
