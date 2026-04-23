#!/usr/bin/perl
# t/util.t - Tests for Gtk3::SourceEditor::Util
use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);

use lib "$RealBin/../lib";
use_ok('Gtk3::SourceEditor::Util', 'safe_call', 'parse_hex_color_rgb');

# ==========================================================================
# safe_call tests
# ==========================================================================

subtest 'safe_call with object that has method' => sub {
    my $obj = bless {}, 'MockWithMethod';
    no strict 'refs';
    *{MockWithMethod::can_method} = sub { 1 };
    *{MockWithMethod::hello} = sub { shift; return "hello: @_"; };
    ok($obj->can('hello'), 'mock object has hello method');

    my $result = Gtk3::SourceEditor::Util::safe_call($obj, 'hello', 'world');
    is($result, 'hello: world', 'safe_call dispatches correctly');
};

subtest 'safe_call with object missing method' => sub {
    my $obj = bless {}, 'MockWithoutMethod';
    no strict 'refs';
    *{MockWithoutMethod::can_method} = sub { 0 };

    my $result = Gtk3::SourceEditor::Util::safe_call($obj, 'nonexistent');
    is($result, undef, 'safe_call returns undef for missing method');
};

subtest 'safe_call with undef object' => sub {
    my $result = Gtk3::SourceEditor::Util::safe_call(undef, 'some_method');
    is($result, undef, 'safe_call returns undef for undef object');
};

subtest 'safe_call with undef method' => sub {
    my $obj = bless {}, 'MockObj';
    my $result = Gtk3::SourceEditor::Util::safe_call($obj, undef);
    is($result, undef, 'safe_call returns undef for undef method');
};

subtest 'safe_call warn-once behavior' => sub {
    # Reset the internal warn state for this test
    # (We can't easily test warn output, but we verify no crash)
    my $obj = bless {}, 'MockWarnOnce';
    no strict 'refs';
    *{MockWarnOnce::can_method} = sub { 0 };

    # First call - should warn
    Gtk3::SourceEditor::Util::safe_call($obj, 'missing1');
    # Second call - should NOT warn (already warned)
    Gtk3::SourceEditor::Util::safe_call($obj, 'missing1');
    # Different method - should warn
    Gtk3::SourceEditor::Util::safe_call($obj, 'missing2');

    ok(1, 'warn-once did not crash');
};

# ==========================================================================
# parse_hex_color_rgb tests
# ==========================================================================

subtest 'parse_hex_color_rgb standard colors' => sub {
    my ($r, $g, $b) = parse_hex_color_rgb('#000000');
    is($r, 0.0, 'black R');
    is($g, 0.0, 'black G');
    is($b, 0.0, 'black B');

    ($r, $g, $b) = parse_hex_color_rgb('#ffffff');
    is($r, 1.0, 'white R');
    is($g, 1.0, 'white G');
    is($b, 1.0, 'white B');
};

subtest 'parse_hex_color_rgb without hash prefix' => sub {
    my ($r, $g, $b) = parse_hex_color_rgb('ff0000');
    is(sprintf("%.4f", $r), '1.0000', 'red R');
    is(sprintf("%.4f", $g), '0.0000', 'red G');
    is(sprintf("%.4f", $b), '0.0000', 'red B');
};

subtest 'parse_hex_color_rgb mixed values' => sub {
    my ($r, $g, $b) = parse_hex_color_rgb('#1a2b3c');
    is(sprintf("%.4f", $r), '0.1020', 'custom R');
    is(sprintf("%.4f", $g), '0.1686', 'custom G');
    is(sprintf("%.4f", $b), '0.2353', 'custom B');
};

subtest 'parse_hex_color_rgb uppercase hex' => sub {
    my ($r, $g, $b) = parse_hex_color_rgb('#AABBCC');
    is(sprintf("%.4f", $r), '0.6667', 'uppercase R');
    is(sprintf("%.4f", $g), '0.7333', 'uppercase G');
    is(sprintf("%.4f", $b), '0.8000', 'uppercase B');
};

subtest 'parse_hex_color_rgb dies on undef' => sub {
    eval { parse_hex_color_rgb(undef) };
    like($@, qr/expected.*undef/i, 'dies on undef input');
};

subtest 'parse_hex_color_rgb dies on invalid' => sub {
    eval { parse_hex_color_rgb('not-a-color') };
    like($@, qr/invalid hex color/i, 'dies on invalid input');

    eval { parse_hex_color_rgb('#1234') };
    like($@, qr/invalid hex color/i, 'dies on short input');

    eval { parse_hex_color_rgb('#GGHHII') };
    like($@, qr/invalid hex color/i, 'dies on non-hex chars');
};

done_testing;
