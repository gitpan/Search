#!/usr/bin/perl -w

	use Search::TextSearch;
	use Search::Glimpse;
	use strict;

	$| = 1;
	#$\ = "\n";

	my $glimpse = `which glimpse`;
	chop($glimpse);
	unless(-x $glimpse) {
		undef $glimpse;
	}

	if(defined $glimpse) {
		my @indices = `ls .glimpse* 2&>/dev/null`;
		if(@indices) {
			warn "There are glimpse indexes in this directory.\n";
			warn "Skipping glimpse test.\n";
			undef $glimpse;
		}
		else {
			my $glimpseindex = `which glimpseindex`;
			chop($glimpseindex);
			if( -x $glimpseindex ) {
				print "Building test glimpseindex...";
				system 'glimpseindex -H . test*.file > /dev/null';
				print "done.\n";
			}
			else {
				warn "No glimpseindex found, skipping glimpse test.\n";
				undef $glimpse;
			}
		}
	}

	my ($v1,$v2);
	my @failed = qw(START 0 0 0 0 0 0 0 0 0);
	my $testno = 1;

	# Simple search with default options for 'foobar' in the named file
	# check with grep
	print "Check basic TextSearch.......";
	my $s = new Search::TextSearch search_file => 'test1.file';
	my @found = $s->search('foobar');
	my @test = `grep -i foobar test1.file`;
	die "grep didn't work" unless @test;


sub check {
	$failed[$testno] = '';
	$failed[$testno] = '*count*'
		if scalar(@found) != scalar(@test);
	for $v2 (@found) {
		$v1 = shift @test;
		next if $v1 eq $v2;
		$failed[$testno] .= '*equality*';
	}
	print "Test $testno " .
		($failed[$testno] ? "FAILED. $failed[$testno]\n\n" : "passed OK.\n");
}
	check();
	$testno++;

	# Search for 'foobar' in return only fields 0 and 2
	# where fields are separated by spaces or tabs. They will
	# be rejoined with a single space.
	print "Check field returns..........";
	$s = new Search::TextSearch;
	@found = $s->search( search_file   => [qw(test1.file test2.file)],
				         search_spec   => 'foobar',
				         return_fields => [0,2],
				         return_delim  => ' ',
				         index_delim   => '\s+'					);
	@test = ('foo baz','foo baz','Barfoo Bazard','Barfoo Bazard');
	check();
	$testno++;

	print "Check case sensitivity.......";
	$s->global(case_sensitive => 1);
	@found = $s->search('foobar');
	@test = ('foo baz','foo baz');
	check();
	$testno++;

	# Search for 'one' and 'three' in only fields 1 and 3
	# where fields are separated by spaces or tabs.
	print "Check field searches.........";
	$s = new Search::TextSearch;
	$s->fields(1,3);
	$s->specs('one','three');
	@found = $s->search( search_file   => [qw(test1.file test2.file)],
				         index_delim   => '\s+'					);
	@test = (
"zero	one	two	three	four	five	six	seven\n",
"zero one two three four five six seven\n",
	);
	check();
	$testno++;

	# Search for 'one' and 'three' in only fields 1 and 3
	# where fields are separated by spaces or tabs.
	print "Check field delimiters.......";
	$s = new Search::TextSearch;
	$s->fields(3,4);
	$s->specs('three');
	@found = $s->search( search_file   => [qw(test1.file test2.file)],
				         index_delim   => "\t"					);
	@test = (
"zero	one	two	three	four	five	six	seven\n",
"Seven	Six	Five	Four	Three	Two	One	Zero\n"
	);
	check();
	$testno++;

	# Search for 'one' and 'three' in the wrong fields to contrast
	print "Check wrong field search.....";
	$s = new Search::TextSearch;
	$s->specs('one','three');
	$s->fields(0,2);
	@found = $s->search( search_file   => [qw(test1.file test2.file)],
				         index_delim   => '\s+'					);
	@test = ();
	check();
	$testno++;
	(print("Glimpse not defined, no Glimpse testing."), exit)
		unless defined $glimpse;

	print "Check basic Glimpse..........";
	# Search for 'foobar' in any file containing 'messages' in
	# the default glimpse index, return the file names
	$s = new Search::Glimpse;
	@found = $s->search( glimpse_cmd   => $glimpse,
						 search_spec   => 'foobar',
				         search_file   => 'test',
				         return_file_name  => 1,       );
	@found = sort @found;
	@test = ("test1.file\n", "test2.file\n");
	check();
	$testno++;

	print "Check case sensitivity.......";
	# Search for 'foobar' in any file containing 'messages' in
	# the default glimpse index, return the file names
	$s = new Search::Glimpse;
	@found = $s->search( glimpse_cmd   => $glimpse,
						 search_spec   => 'foobar',
						 case_sensitive=> 1,
				         search_file   => 'test',
				         return_file_name  => 1,       );
	@found = sort @found;
	@test = ("test1.file\n");
	check();
	$testno++;

	print "Check field returns..........";
	# Search for 'foobar' in any file containing 'messages' in
	# the default glimpse index, return the file names
	$s = new Search::Glimpse;
	@found = $s->search( glimpse_cmd   => $glimpse,
						 search_spec   => 'foobar',
				         search_file   => 'test',
				         return_fields => [0,2],
				         return_delim  => ' ',
				         index_delim   => '\s+'					);

	@test = ('foo baz','foo baz','Barfoo Bazard','Barfoo Bazard');
	check();
	$testno++;

	unlink <.glimpse*>;
__END__
