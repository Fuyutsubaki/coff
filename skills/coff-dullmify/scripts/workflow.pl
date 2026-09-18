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

# dullmify の二つの問いと書き出しを順番に進める。
sub workflow {
    my @args = @_;
    my $plan = step { _plan(\@args) };
    my $workflow_body = llm('workflow', {
        source   => $plan->{source_content},
        existing => $plan->{existing_workflow},
    });
    my $topics = llm('topics', {
        source => $plan->{source_content},
    });
    step { _publish($plan, $workflow_body, $topics) };
    return ["dullmified: $plan->{source} -> $plan->{out}"];
}

# CLI を検査し、ソースと既存 workflow を UTF-8 で読む。
sub _plan {
    my ($args) = @_;
    my @args = @$args;
    my ($source, $out);
    while (@args) {
        my $arg = shift @args;
        if ($arg eq '-o') {
            die "-o requires a directory\n" unless @args && !defined $out;
            $out = shift @args;
        }
        elsif ($arg =~ /\A-/) {
            die "unknown option: $arg\n";
        }
        elsif (defined $source) {
            die "only one source is accepted\n";
        }
        else {
            $source = $arg;
        }
    }
    die "usage: <source>.skill.md -o <dir>\n"
        unless defined $source && defined $out;
    my ($name) = basename($source) =~ /\A([A-Za-z0-9][A-Za-z0-9._-]*)\.skill\.md\z/
        or die "source must be named <name>.skill.md: $source\n";
    die "source not found: $source\n" unless -f $source;
    my $source_content = _read_text($source);
    die "empty source: $source\n" unless length $source_content;

    my $existing_path = File::Spec->catfile($out, 'scripts', 'workflow.pl');
    my $existing = -f $existing_path ? _read_text($existing_path) : '';
    # coff-compile のフッタと雛形の頭と尻は、答えに含めてはいけないので渡す前に落とす。
    $existing =~ s/\n?# <!--\{"src":[^\n]*"md5":"[a-f0-9]{32}"\} -->[ \t]*\n?\z//;
    $existing = _strip_templates($existing);
    return {
        name              => $name,
        source            => $source,
        source_content    => $source_content,
        existing_workflow => $existing,
        out               => $out,
    };
}

# LLM の答えと雛形を組み立て、構文検査後に3ファイルを書く。
sub _publish {
    my ($plan, $workflow_body, $topics) = @_;
    $workflow_body = _workflow_body($workflow_body);
    $topics = _topics($topics);
    my $scripts = dirname(__FILE__);
    my $skill_root = dirname($scripts);
    my ($head, $tail) = _templates();
    my $workflow_content = "$head$workflow_body\n$tail";
    _check_perl($workflow_content);

    my $frontmatter = _frontmatter($plan->{source_content}, $plan->{name});
    my $prefix = _read_text(File::Spec->catfile($skill_root, 'templates', 'skill-prefix.md'));
    my $suffix = _read_text(File::Spec->catfile($skill_root, 'templates', 'skill-suffix.md'));
    my $skill = "$frontmatter\n\n$prefix$topics\n$suffix";

    my @files = (
        [File::Spec->catfile($plan->{out}, 'SKILL.md'), $skill],
        [File::Spec->catfile($plan->{out}, 'scripts', 'workflow.pl'), $workflow_content],
        [File::Spec->catfile($plan->{out}, 'scripts', 'lib', 'Coff', 'Workflow.pm'),
            _read_text(File::Spec->catfile($scripts, 'lib', 'Coff', 'Workflow.pm'))],
    );
    _write_file($_->[0], $_->[1]) for @files;
    return 1;
}

# workflow の答えに土台や Markdown が混ざっていないことを確かめる。
sub _workflow_body {
    my ($body) = @_;
    $body =~ s/\A\s+|\s+\z//g;
    die "workflow answer is empty\n" unless length $body;
    die "workflow answer must contain sub workflow\n"
        unless $body =~ /^sub workflow\b/m;
    die "workflow answer contains a Markdown fence\n"
        if $body =~ /^\s*(?:```|~~~)/m;
    die "workflow answer contains a shebang\n" if $body =~ /\A#!/;
    die "workflow answer contains use declarations\n" if $body =~ /^\s*use\s+/m;
    my $runner = 'run_' . 'workflow';
    die "workflow answer contains $runner\n" if $body =~ /\b\Q$runner\E\b/;
    die "workflow answer contains a generated footer\n"
        if $body =~ /# <!--\{"src":.*"md5":"[a-f0-9]{32}"\} -->/;
    return $body;
}

# topic 節が薄い SKILL.md の本文として使えることを確かめる。
sub _topics {
    my ($topics) = @_;
    $topics =~ s/\A\s+|\s+\z//g;
    die "topics answer is empty\n" unless length $topics;
    die "topics answer contains frontmatter\n" if $topics =~ /\A---\r?\n/;
    die "topics answer contains a fenced code block\n"
        if $topics =~ /^\s*(?:```|~~~)/m;
    return $topics;
}

# ソースの frontmatter から実行時に不要なビルド指示を除く。
sub _frontmatter {
    my ($document, $name) = @_;
    die "frontmatter is missing\n" unless $document =~ /\A---\r?\n/;
    die "frontmatter is not closed\n"
        unless $document =~ /\A---\r?\n(.*?)\r?\n---\r?\n/s;
    my @kept;
    my $skip = 0;
    my $has_name = 0;
    for my $line (split /\r?\n/, $1) {
        if ($line =~ /^([A-Za-z0-9_-]+):/) {
            my $key = $1;
            $skip = $key =~ /^coff-/ || $key eq 'allowed-tools';
            if ($key eq 'name') {
                push @kept, "name: $name";
                $has_name = 1;
                next;
            }
        }
        push @kept, $line unless $skip;
    }
    unshift @kept, "name: $name" unless $has_name;
    push @kept, 'allowed-tools: Bash(perl ${CLAUDE_SKILL_DIR}/scripts/workflow.pl *)';
    return "---\n" . join("\n", @kept) . "\n---";
}

# 雛形の頭と尻を読む。
sub _templates {
    my $templates = File::Spec->catdir(dirname(dirname(__FILE__)), 'templates');
    return (
        _read_text(File::Spec->catfile($templates, 'workflow-head.pl')),
        _read_text(File::Spec->catfile($templates, 'workflow-tail.pl')),
    );
}

# 既存 workflow から雛形の頭と尻を取り除き、LLM が書いた部分だけにする。
sub _strip_templates {
    my ($text) = @_;
    my ($head, $tail) = _templates();
    $text = substr($text, length $head) if index($text, $head) == 0;
    $text =~ s/\s+\z//;
    my $trimmed_tail = $tail =~ s/\s+\z//r;
    $text = substr($text, 0, length($text) - length($trimmed_tail))
        if length($text) >= length($trimmed_tail)
        && substr($text, -length($trimmed_tail)) eq $trimmed_tail;
    $text =~ s/\s+\z//;
    return $text;
}

# UTF-8 のテキストファイルを文字列として読む。
sub _read_text {
    my ($path) = @_;
    open my $fh, '<:raw', $path or die "cannot read $path: $!\n";
    local $/;
    my $raw = <$fh>;
    close $fh or die "cannot close $path: $!\n";
    my $text = eval { Encode::decode('UTF-8', $raw, Encode::FB_CROAK()) };
    die "$path is not UTF-8: $@\n" if $@;
    return $text;
}

# workflow を一時ファイルに置き、実際の Perl で構文検査する。
sub _check_perl {
    my ($content) = @_;
    require File::Temp;
    require IPC::Open3;
    require Symbol;
    my ($fh, $path) = File::Temp::tempfile(
        'coff-workflow-XXXXXX', SUFFIX => '.pl', TMPDIR => 1, UNLINK => 1,
    );
    binmode $fh, ':raw';
    print {$fh} Encode::encode_utf8($content);
    close $fh or die "cannot close $path: $!\n";

    my $error = Symbol::gensym();
    # 一時ファイルの場所では雛形の use lib が runtime を見つけられないので、同梱の lib を -I で渡す。
    my $lib = File::Spec->catdir(dirname(__FILE__), 'lib');
    my $pid = IPC::Open3::open3(my $input, my $output, $error, $^X, '-I', $lib, '-c', $path);
    close $input;
    local $/;
    my $diagnostic = (<$output> // '') . (<$error> // '');
    waitpid($pid, 0);
    return if ($? >> 8) == 0;
    $diagnostic =~ s/\Q$path\E/workflow.pl/g;
    $diagnostic =~ s/\s+\z//;
    die "perl -c failed for workflow.pl: $diagnostic\n";
}

# 1ファイルを同じディレクトリの一時ファイルから置き換える。
sub _write_file {
    my ($path, $content) = @_;
    File::Path::make_path(dirname($path));
    my $tmp = "$path.tmp-$$";
    open my $fh, '>:raw', $tmp or die "cannot write $tmp: $!\n";
    print {$fh} Encode::encode_utf8($content) or die "cannot write $tmp: $!\n";
    close $fh or die "cannot close $tmp: $!\n";
    rename $tmp, $path or die "cannot replace $path: $!\n";
}

# ここから下も土台。skill 名は親ディレクトリ名で、runtime に workflow と引数を渡して終了コードを返す。
exit run_workflow(name => basename(dirname($FindBin::Bin)),
    workflow => \&workflow, argv => \@ARGV);
# <!--{"src":".coff/src/coff-dullmify.skill.md","md5":"1d1171a459de54721268b1611cedce5e"} -->
