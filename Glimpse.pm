# Search/Glimpse.pm:  Search indexes with Glimpse
#
# $Id: Glimpse.pm,v 1.3 1996/04/29 20:13:34 mike Exp mike $

# Copyright 1996 by Michael J. Heins <mikeh@iac.net>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# $Log: Glimpse.pm,v $
# Revision 1.3  1996/04/29 20:13:34  mike
# Update to Search vice CGI::Search
#
# Revision 1.2  1996/04/26 04:35:14  mike
# Initial Release
#
# Revision 1.1  1996/04/25 06:41:21  mike
# Initial revision
#
# Revision 1.1  1996/04/25 06:40:15  mike
# Initial revision
#
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

package Search::Glimpse;
require Search::Base;
@ISA = qw(Search::Base);

$VERSION = substr(q$Revision: 1.3 $, 10);
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

	# This line is a DOS/NT/MAC portability problem
	$s->{global}->{base_directory} = $ENV{PWD} || `pwd`;
	$s->{global}->{glimpse_cmd} = 'glimpse';
	$s->{global}->{min_string} = 4;
	$s->{global}->{search_server} = undef;
	$s->{global}->{search_port} = undef;

}

sub version {
	$Search::Glimpse::VERSION;
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
	my($max_matches,$mod,$return_delim);
	my($cmd,$code,$count,$joiner,$matches_to_send,@out);
	my($limit_sub,$return_sub);
	my($f,$key,$spec,$val);
	my($searchfile,@searchfiles);
	my(@pats);
	my(@specs);
	my(@cmd);
	while (($key,$val) = each %options) {
		$g->{$key} = $val;
	}
 	my $index_delim = $g->{index_delim};

	$g->{matches} = 0;
	$max_matches = int($g->{max_matches});

	if(defined $g->{search_spec}) {
	  	@specs = $g->{search_spec};
	}
	else {
		@specs = @{$s->{specs}};
	}

    if (!$g->{glimpse_cmd}) {
        &{$g->{log_routine}}
            ("Attempt to search with glimpse, no glimpse configured.\n");
        &{$g->{error_routine}}($g->{error_page},
            "Attempt to search with glimpse, no glimpse present.\n");
        return undef; # if it makes it to here
    }

    # Build glimpse line
    push @cmd, $g->{glimpse_cmd};
    unless (defined $g->{search_server}) {
    	push @cmd, "-H $g->{base_directory}";
	}
	else {
    	push @cmd, "-C $g->{search_server}";
		push (@cmd, "-K $g->{search_port}")
			if defined $g->{search_port} && $g->{search_port};
	}

    if ($g->{spelling_errors}) {
        $g->{spelling_errors} = int  $g->{spelling_errors};
        push @cmd, '-' . $g->{spelling_errors};
    }

    push @cmd, "-i" unless $g->{case_sensitive};
    push @cmd, "-h" unless $g->{return_file_name};
    push @cmd, "-y -L $max_matches:0:$max_matches";
    push(@cmd, "-F '$g->{index_file}'")
		if defined $g->{index_file} && $g->{index_file};

	push(@cmd, '-w') unless $g->{substring_match};
	push(@cmd, '-l') if $g->{return_file_name};
	
	if(! defined $g->{record_delim}) { 
		push @cmd, "-d 'NeVAiRbE'";
	}
	elsif ($g->{record_delim} eq "\n") { } #intentionally empty 
	elsif ($g->{record_delim} =~ /^\n+(.*)/) {
		#This doesn't handle two newlines, unfortunately
		push @cmd, "-d '^$1'";
	}
	elsif (! $g->{record_delim}) { 
		push @cmd, q|-d '$$'|;
	}
	else {
		# Should we modify it? Yes, to give indication that
		# it was done
		&{$g->{log_routine}}
			("Search::Glimpse: escaped single quote in record_delim, value changed.\n")
			if $g->{record_delim} =~ s/'/\\'/g; 
		push @cmd, "-d '$g->{record_delim}'";
	}

	$spec = join ' ', @specs;

	if ($g->{or_search}) {
		$joiner = ',';
	}
	else  {	
		$joiner = ';';
	}

	$spec =~ s/[^"$\d\w\s*]//g;
	$spec =~ /(.*)/;
	$spec = $1;
	@pats = shellwords($spec);
	$s->debug("pats: '", join("', '", @pats), "'");
	$spec = join $joiner, @pats;
    push @cmd, "'$spec'";
	$s->debug("spec: '", $spec, "'");

	$joiner = $spec;
	$joiner =~ s/['";,]//g;
	$s->debug("joiner: '", $spec, "'");
	if(length($joiner) < $g->{min_string}) {
		my $msg = <<EOF;
Search strings must be at least $g->{min_string} characters.
You had '$joiner' as the operative characters  of your search strings.
EOF
		&{$g->{error_routine}}($g->{error_page}, $msg);
		return undef;
	}

    $cmd = join ' ', @cmd;

    # searches for debug
    $s->debug("Glimpse command line:\n$cmd\n");

    if (!open(Search::Glimpse::SEARCH,qq!$cmd | !)) {
        &{$g->{log_routine}}("Can't fork glimpse: $!\n");
        &{$g->{error_routine}}('badsearch', 'Search command could not be run.');
        close Search::Glimpse::SEARCH;
        return;
    }

	$g->{overflow} = 0;

	if($g->{return_file_name}) {
		$s->debug("Got to return_fields FILENAME");
		$return_sub = sub {@_};
	}
	elsif(!defined $g->{return_fields}) {
		$s->debug("Got to return_fields DEFAULT");
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
		my $return_delim = defined $g->{return_delim}
						   ? $g->{return_delim}
						   : $index_delim;
		$return_sub = sub {
			my $line = join "$return_delim",
						(split /$index_delim/, $_[0])[@fields];
			$line;
		};
	}
	elsif( $return_delim = $g->{return_fields} ) {
		$s->debug("Got to return_fields TRIM");
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
		unless ($g->{or_search}) {
			eval {$f = create_search_and(	$g->{case_sensitive},
											$g->{substring_match},
											@pats);
						};
			&{$g->{error_routine}}($g->{error_page}, $@) if $@;
		}
		else	{
			eval {$f = create_search_or(	$g->{case_sensitive},
											$g->{substring_match},
											@pats);
						};
			&{$g->{error_routine}}($g->{error_page}, $@) if $@;
		}
		$limit_sub = sub {
			my ($line) = @_;
			my @fields = (split /$index_delim/, $line)[@{$s->{fields}}];
			my $field = join $index_delim, @fields;
			$_ = $field;
			return ($_ = $line) if &$f();
			return undef;
		};
	}

	local($/) = $g->{record_delim};

	if(defined $limit_sub and $g->{return_file_name}) {
		&{$g->{log_routine}}
			("Search::Glimpse.pm: non-fatal error\n" .
			"Can't field-limit matches in return_file_name mode. Ignoring.\n");
		undef $limit_sub;
	}

	if(defined $limit_sub) {
		while(<Search::Glimpse::SEARCH>) {
			next unless &$limit_sub($_);
			push @out, &$return_sub($_);
		}
	}
	else {
		while(<Search::Glimpse::SEARCH>) {
			push @out, &$return_sub($_);
		}
	}
	close Search::Glimpse::SEARCH;
	if($?) {
		&{$g->{error_routine}}
			($g->{error_page},"glimpse returned error $?: $!");
		return undef;
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

			open(Search::Glimpse::MATCHES, ">$file") or
				&{$g->{error_routine}}
				    ($g->{error_page},"Couldn't write $file: $!\n");
			print Search::Glimpse::MATCHES join "\n", @out;
			close Search::Glimpse::MATCHES;
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
