# Search/TextSearch.pm:  Search indexes with Perl
#
# $Id: TextSearch.pm,v 1.5 1996/04/29 20:13:34 mike Exp mike $

# Copyright 1996 by Michael J. Heins <mikeh@iac.net>
#
# $Log: TextSearch.pm,v $
# Revision 1.5  1996/04/29 20:13:34  mike
# Update to Search vice CGI::Search
#
# Revision 1.4  1996/04/29 19:55:58  mike
# Added head_skip
#
# Revision 1.3  1996/04/26 04:38:25  mike
# Initial Release 0.1
#
# Revision 1.2  1996/04/25 18:19:12  mike
# Added many features including return_file_name, record_delim, etc.
#
# Revision 1.1  1996/04/25 06:41:35  mike
# Initial revision
#
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

package Search::TextSearch;
require Search::Base;
@ISA = qw(Search::Base);

$VERSION = substr(q$Revision: 1.5 $, 10);

use Text::ParseWords;
use strict;

sub new {
    my ($class, %options) = @_;
	my $self = new Search::Base;
	my ($key,$val);
	init($self);
	while ( ($key,$val) = each %options) {
		$self->{global}->{$key} = $val;
	}
	bless $self, $class;
}

sub init {
	my $s = shift;
	my $g = $s->{global};
}

sub version {
	$Search::TextSearch::VERSION;
}

sub search {

    my $s = shift;
	my($g) = $s->{global};
	my %options;
	if(@_ == 1) {
		$g->{search_spec} = shift;
	}
	else	{
		undef $g->{search_spec};
		%options = @_;
	}

	my($delim,$string);
	my($max_matches,$mod,$return_delim,$spec);
	my($code,$count,$matches_to_send,@out);
	my($index_delim,$limit_sub,$return_sub);
	my($f,$key,$val);
	my($searchfile,@searchfiles);
	my(@specs);
	my(@pats);

	while (($key,$val) = each %options) {
		$g->{$key} = $val;
	}

 	$index_delim = $g->{index_delim};

	$g->{matches} = 0;

	if(defined $g->{search_spec}) {
	  	@specs = $g->{search_spec};
	}
	else {
		@specs = @{$s->{specs}};
	}

	foreach $string (@{$s->{specs}}) {
		if(length($string) < $g->{min_string}) {
			my $msg = <<EOF;
Search strings must be at least $g->{min_string} characters.
You had '$string' as one of your search strings.
EOF
			&{$g->{error_routine}}($g->{error_page}, $msg);
			return undef;
		}
	}


	$spec = join ' ', @specs;

	$spec =~ s/[^"$\d\w\s*]//g;
	$spec =~ s'\*'\S+'g;
	$spec =~ /(.*)/;
	$spec = $1;
	@pats = shellwords($spec);
	$s->debug("pats: '", join("', '", @pats), "'");

	if ($g->{or_search}) {
		eval {$f = create_search_or(	$g->{case_sensitive},
										$g->{substring_match},
										@pats					)};
		&{$g->{error_routine}}($g->{error_page}, $@) if $@;
	}
	else  {	
		eval {$f = create_search_and(	$g->{case_sensitive},
										$g->{substring_match},
										@pats					)};
		&{$g->{error_routine}}($g->{error_page}, $@) if $@;
	}

	$max_matches = int($g->{max_matches});


	$g->{overflow} = 0;

	if(!defined $g->{return_fields}) {
		$s->debug("Got to return_fields default");
		$return_sub = sub { substr($_[0], 0, index($_[0], $index_delim)) };
	}
	elsif ( ref($g->{return_fields}) =~ /^HASH/ ) {
		$s->debug("Got to return_fields HASH");
		$return_sub = sub {
			my($line) = @_;
			my(@return);
			my(%strings) = %{$g->{return_fields}};
			while ( ($key,$val) = each %strings) {
				print "key: '$key' val: '$val'";
				$val = '\s' unless $val ||= 0;
				1 while $line =~ s/($key)\s*(\S.*?)($val)/push(@return, $2)/ge;
			}
			return undef unless @return;
			join $index_delim, @return;
		};
	}
	elsif ( ref($g->{return_fields}) =~ /^ARRAY/ ) {
		$s->debug("Got to return_fields ARRAY");
		my @fields = @{$g->{return_fields}};
		$return_delim = defined $g->{return_delim}
						   ? $g->{return_delim}
						   : $index_delim;
		$s->debug("ret: '$return_delim' ind: '$index_delim'");
		$return_sub = sub {
			my $line = join "$return_delim",
						(split /$index_delim/, $_[0])[@fields];
			$line;
		};
	}
	elsif( $return_delim = $g->{return_fields} ) {
		$s->debug("Got to return_fields SCALAR");
		$return_sub = sub { substr($_[0], 0, index($_[0], $return_delim)) };
	}
	else {
		$s->debug("Got to return_fields ALL");
		$return_sub = sub { @_ };
	}

	$s->debug('fields/specs: ', scalar @{$s->{fields}}, " ", scalar @{$s->{specs}});

	if ( scalar @{$s->{fields}} == scalar @{$s->{specs}} and 
		 scalar(@{$s->{fields}}) > 1				)  {
		$limit_sub = sub {
			my ($line) = @_;
			my @fields = (split /$index_delim/, $line)[@{$s->{fields}}];
			my @specs = @{$s->{specs}};
			my $i;
			if($g->{case_sensitive}) {
				for($i = 0; $i < scalar @fields; $i++) {
					return undef unless $fields[$i] =~ /$specs[$i]/;
				}
			}
			else { 
				for($i = 0; $i < scalar @fields; $i++) {
					return undef unless $fields[$i] =~ /$specs[$i]/i;
				}
			}
			1;
		};
	}
	elsif ( scalar(@{$s->{fields}}) > 1	)  {
		$limit_sub = sub {
			my ($line) = @_;
			my @fields = (split /$index_delim/, $line)[@{$s->{fields}}];
			my $field = join $index_delim, @fields;
			$_ = $field;
			return($_ = $line) if &$f();
			return undef;
		};
	}

	if(ref($g->{search_file}) =~ /^ARRAY/) {
		@searchfiles = @{$g->{search_file}};
	}
	elsif (! ref($g->{search_file})) {
		@searchfiles = $g->{search_file};
	}
	else {
		&{$g->{error_routine}}
			("{search_file} must be array reference or scalar.\n");
		return undef; # If it makes it this far
	}

	local($/) = $g->{record_delim};

	foreach $searchfile (@searchfiles) {
		open(Search::TextSearch::SEARCH, $searchfile)
			or &{$g->{error_routine}}("Couldn't open $searchfile: $!\n");
		my $line;
		if(defined $g->{head_skip} and $g->{head_skip} > 0) {
			while(<Search::TextSearch::SEARCH>) {
				last if $. >= $g->{head_skip};
			}
		}
		if(defined $limit_sub) {
			while(<Search::TextSearch::SEARCH>) {
				next unless &$f();
				next unless &$limit_sub($_);
				if($g->{return_file_name}) {
					push @out, $searchfile;
					last;
				}
				push @out, &$return_sub($_);
			}
		}
		else {
			while(<Search::TextSearch::SEARCH>) {
				next unless &$f();
				if($g->{return_file_name}) {
					push @out, $searchfile;
					last;
				}
				push @out, &$return_sub($_);
			}
		}
		close Search::TextSearch::SEARCH;
	}

	$g->{matches} = scalar(@out);
	$g->{first_match} = 0;

	if ($g->{matches} > $g->{match_limit}) {
		$matches_to_send = $g->{match_limit};
		my $file;
		$g->{overflow} = 1;
		$g->{next_pointer} = $g->{match_limit};
		if($file = $g->{save_dir}) {
			$file .= '/' . $g->{session_id} . ':' . $g->{search_mod};

			open(Search::TextSearch::MATCHES, ">$file") or
				&{$g->{error_routine}}
				    ($g->{error_page},"Couldn't write $file: $!\n");
			print Search::TextSearch::MATCHES join "\n", @out;
			close Search::TextSearch::MATCHES;
		}
		elsif(ref $g->{save_hash}) {
			my $id = $g->{session_id} . ':' . $g->{search_mod};
			$g->{save_hash}->{$id} = join "\n", @out;
		}
	}
	else {
		$matches_to_send = $g->{matches};
		$g->{next_pointer} = 0;
	}

	$s->debug($g->{matches}, " matches");
	$s->debug("0 .. ", ($matches_to_send - 1));
	$s->save_history() if $g->{history};

	@out[0..($matches_to_send - 1)];
}


sub create_search_and {

	my ($case) = shift(@_) ? '' : 'i';
	my ($bound) = shift(@_) ? '' : '\b';
	die "create_search_and: create_search_and case_sens sub_match patterns" 
		unless @_;
	my $pat;

    my $code = <<EOCODE;
sub {
EOCODE

    $code .= <<EOCODE if @_ > 5;
    study;
EOCODE

    for $pat (@_) {
	$code .= <<EOCODE;
    return 0 unless /$bound$pat$bound/$case;
EOCODE
    } 

    $code .= "}\n";

    my $func = eval $code;
    die "bad pattern: $@" if $@;

    return $func;
} 

sub create_search_or {

	my ($case) = shift(@_) ? '' : 'i';
	my ($bound) = shift(@_) ? '' : '\b';
	die "create_search_or: create_search_or case_sens sub_match patterns" 
		unless @_;
	my $pat;

    my $code = <<EOCODE;
sub {
EOCODE

    $code .= <<EOCODE if @_ > 5;
    study;
EOCODE

    for $pat (@_) {
	$code .= <<EOCODE;
    return 1 if /$bound$pat$bound/$case;
EOCODE
    } 

    $code .= "}\n";

    my $func = eval $code;
    die "bad pattern: $@" if $@;

    return $func;
} 

1;
__END__
