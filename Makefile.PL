# $Id: Makefile.PL,v 1.1 1996/04/29 19:57:57 mike Exp mike $
use ExtUtils::MakeMaker;
WriteMakefile(
        NAME        => 'Search::Text',
        VERSION     => '0.2',
        DISTNAME    => "Search",
        dist        => {COMPRESS => 'gzip', SUFFIX => 'gz'},
        test        => {TEST_TYPE => './test.pl'},
);
