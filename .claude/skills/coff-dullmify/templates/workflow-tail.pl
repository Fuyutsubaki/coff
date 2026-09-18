
# ここから下も土台。skill 名は親ディレクトリ名で、runtime に workflow と引数を渡して終了コードを返す。
exit run_workflow(name => basename(dirname($FindBin::Bin)),
    workflow => \&workflow, argv => \@ARGV);
