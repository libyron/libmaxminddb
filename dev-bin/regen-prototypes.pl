#!/usr/bin/env perl

use strict;
use warnings;

use C::Scan;
use FindBin qw( $Bin );
use File::Basename qw( basename dirname );

sub main {
    _regen_prototypes(
        "$Bin/../src/maxminddb.c",
        "$Bin/../include/maxminddb.h"
    );

    _regen_prototypes(
        "$Bin/../bin/mmdblookup.c",
    );

    _regen_prototypes(
        "$Bin/../t/maxminddb_test_helper.c",
        "$Bin/../t/maxminddb_test_helper.h",
    );
}

sub _regen_prototypes {
    my $c_file = shift;
    my $h_file = shift;

    my $c_code      = read_file($c_file);
    my $h_code      = $h_file ? read_file($h_file) : q{};
    my $orig_c_code = $c_code;
    my $orig_h_code = $h_code;

    my $script_name = basename($0);
    my $dir         = basename($Bin);

    my $indent_off = '/* *INDENT-OFF* */';
    my $indent_on  = '/* *INDENT-ON* */';
    my $prototypes_start
        = "/* --prototypes automatically generated by $dir/$script_name - don't remove this comment */";
    my $prototypes_end
        = q{/* --prototypes end - don't remove this comment-- */};

    ( my $prototypes_start_re = $prototypes_start ) =~ s/ \n /\n */g;
    ( my $prototypes_end_re   = $prototypes_end ) =~ s/\n/\n */g;

    for my $content ( $c_code, $h_code ) {
        $content =~ s{
                    [ ]*
                    \Q$indent_off\E
                    \n
                    [ ]*
                    \Q$prototypes_start\E
                    .+?
                    [ ]*
                    \Q$prototypes_end\E
                    \n
                    [ ]*
                    \Q$indent_on\E
                    \n
            }{__PROTOTYPES__}sx;
    }

    my @prototypes = parse_prototypes($c_code);

    if ($h_file) {
        my $external_prototypes = join q{}, map {
            my $p = 'extern ' . $_->{prototype};
            $p =~ s/^/    /;                # first line
            $p =~ s/\n/\n           /gm;    # the rest
            $p . ";\n"
            }
            grep { $_->{external} } @prototypes;
        $h_code
            =~ s/__PROTOTYPES__/    $indent_off\n    $prototypes_start\n$external_prototypes    $prototypes_end\n    $indent_on\n/;
        $h_code =~ s{\n *(/\* \*INDENT)}{\n    $1}g;
    }

    my $internal_prototypes = join q{},
        map { $_->{prototype} . ";\n" } grep { !$_->{external} } @prototypes;
    $c_code
        =~ s/__PROTOTYPES__/$indent_off\n$prototypes_start\n$internal_prototypes$prototypes_end\n$indent_on\n/;

    write_file( $c_file, $c_code ) if $c_code ne $orig_c_code;
    write_file( $h_file, $h_code ) if $h_file && $h_code ne $orig_h_code;
}

my $return_type_re = qr/(?:\w+\s+)+?\**?/;
my $signature_re   = qr/\([^\(\)]+?\)/;
my $c_function_re  = qr/($return_type_re(\w+)$signature_re)(?>\n{)/s;

# Shamelessly stolen from Inline::C::ParseRegExp
my $sp = qr{[ \t]|\n(?![ \t]*\n)};

my $re_type = qr {
                     (?: \w+ $sp* )+? # words
                     (?: \*  $sp* )*  # stars
             }x;

my $re_identifier = qr{ \w+ $sp* }x;

my $re_args = qr/\(.+?\)/s;

# and again from Inline::C::ParseRegExp
my $re_signature = qr/^($re_type ($re_identifier) $re_args) (?>[\ \t\n]*?{)/x;

{
    my %skip = map { $_ => 1 } qw( memmem );

    sub parse_prototypes {
        my $c_code = shift;

        my @protos;

        for my $chunk ( $c_code =~ /^(\w+.+?[;{])/gsm ) {
            my ( $prototype, $name ) = $chunk =~ /^$re_signature/ms
                or next;

            push @protos,
                {
                name      => $name,
                prototype => $prototype,
                external  => $prototype =~ /^LOCAL/ ? 0 : 1,
                };
        }

        return grep { !$skip{ $_->{name} } } @protos;
    }
}

sub read_file {
    open my $fh, '<', $_[0] or die "Cannot read $_[0]: $!";

    return do {
        local $/;
        <$fh>;
    };
}

sub write_file {
    open my $fh, '>', $_[0] or die "Cannot write to $_[0]: $!";
    print {$fh} $_[1] or die "Cannot write to $_[0]: $!";
    close $fh or die "Cannot write to $_[0]: $!";
}

main();
