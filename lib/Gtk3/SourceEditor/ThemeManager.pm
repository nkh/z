package Gtk3::SourceEditor::ThemeManager;
use strict;
use warnings;
use Gtk3::SourceView;
use File::Slurper 'read_text';
use File::Temp qw(tempfile);
use File::Basename qw(dirname);
use Encode qw(encode);

our $VERSION = '0.04';

sub load {
    my (%opts) = @_;
    my $xml_file = $opts{file} // 'themes/default.xml';
    
    unless (-f $xml_file) {
        die "Error: Theme file '$xml_file' not found!\n";
    }

    my ($scheme_id) = $xml_file =~ /([^\/\\]+)\.xml$/;
    die "Error: Invalid theme filename format.\n" unless $scheme_id;

    my $xml_content = read_text($xml_file);
    my ($fg) = $xml_content =~ /<style name="text" [^>]*foreground="([^"]+)"/;
    my ($bg) = $xml_content =~ /<style name="text" [^>]*background="([^"]+)"/;
    $fg //= "#000000";
    $bg //= "#FFFFFF";

    unless ($xml_content =~ /<style name="cursor"/) {
        $xml_content =~ s{(<style name="text" [^>]*\/>)}{$1\n  <style name="cursor" foreground="$fg"/>};
    }

    my ($xml_fh, $tmp_file) = tempfile(SUFFIX => '.xml', UNLINK => 1);
    print $xml_fh $xml_content;
    close $xml_fh;

    my $theme_dir = dirname($tmp_file);
    my $manager = Gtk3::SourceView::StyleSchemeManager->get_default();
    $manager->prepend_search_path($theme_dir);
    my $scheme = $manager->get_scheme($scheme_id);
    die "Error: Could not load scheme '$scheme_id'\n" unless $scheme;

    my $ui_css = qq{
        GtkLabel#mode_label {
            color: $fg;
            background-color: $bg;
            background-image: none;
            padding: 4px 6px;
        }
        GtkEntry#cmd_entry {
            color: $fg;
            background-color: $bg;
            background-image: none;
            border-image: none;
            box-shadow: none;
            border: 1px solid $fg;
        }
    };

    my $ui_css_bytes = encode('UTF-8', $ui_css);
    my $ui_css_provider = Gtk3::CssProvider->new();
    eval { $ui_css_provider->load_from_data($ui_css_bytes); };
    warn "Failed to parse dynamic UI CSS: $@" if $@;

    return {
        scheme => $scheme,
        css_provider => $ui_css_provider,
        fg => $fg,
        bg => $bg
    };
}

1;

__END__

=head1 NAME

Gtk3::SourceEditor::ThemeManager - GtkSourceView XML theme loader and UI style generator

=head1 LICENSE

Artistic License 2.0.

=cut
