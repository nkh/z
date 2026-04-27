package Gtk3::SourceEditor::Macro;

use strict;
use warnings;

our $VERSION = '0.01';

my %REGISTRY;   # { name => { file => path, code => coderef } }

# ==========================================================================
# load( %opts )
#
# Load macro file(s) into the registry.
#
#   load( file => 'macros/hello' )     -- load one file
#   load( file => 'macros/hello',
#         name => 'greet' )            -- load with explicit registry name
#   load( dir  => 'macros/' )          -- scan directory
#   load( dir  => 'macros/',
#         name => 'test' )             -- ignored for dirs (name derived from file)
#
# Returns the registered name (single file) or sorted list of all names (dir).
# ==========================================================================

sub load {
    my ($class, %opts) = @_;

    if ($opts{file}) {
        my $path = $opts{file};
        die "Macro::load: file '$path' not found\n" unless -f $path;
        my $name = $opts{name} // _name_from_file($path);
        my $result = _load_file($path);
        if (ref $result eq 'CODE') {
            $REGISTRY{$name} = { file => $path, code => $result };
        } else {
            # Hashref: merge all fields (desc, run, etc.) into registry entry
            $REGISTRY{$name} = { %$result, file => $path };
        }
        return $name;
    }

    if ($opts{dir} && -d $opts{dir}) {
        # Canonicalize: strip trailing slash to avoid double-slash paths
        my $dir = $opts{dir};
        $dir =~ s{/+$}{};
        my @entries;
        opendir my $dh, $dir or die "Macro::load: cannot open dir '$dir': $!\n";
        while (my $f = readdir $dh) {
            next if $f =~ /^\./;    # skip hidden files
            my $full = "$dir/$f";
            if (-d $full) {
                # Recurse into subdirectories
                push @entries, $full;
            } else {
                push @entries, $full;
            }
        }
        closedir $dh;
        for my $f (sort @entries) {
            if (-d $f) {
                $class->load(dir => $f);
            } else {
                $class->load(file => $f);
            }
        }
    }

    return sort keys %REGISTRY;
}

# ==========================================================================
# run( $name, $ctx, @args )
#
# Execute a loaded macro.
# ==========================================================================

sub run {
    my ($class, $name, $ctx, @args) = @_;
    die "Macro '$name' not loaded\n" unless $REGISTRY{$name};
    my $entry = $REGISTRY{$name};
    my $code = $entry->{run} || $entry->{code};
    die "Macro '$name' has no runnable code\n" unless $code && ref $code eq 'CODE';
    return $code->($ctx, @args);
}

# ==========================================================================
# meta( $name )
#
# Return hashref with macro metadata (all keys except code/run/file).
# Returns undef if the macro is not loaded.
# ==========================================================================

sub meta {
    my ($class, $name) = @_;
    return undef unless $REGISTRY{$name};
    my $entry = $REGISTRY{$name};
    return {
        map { $_ => $entry->{$_} }
        grep { !/^(code|run|file)$/ }
        keys %$entry
    };
}

# ==========================================================================
# list()
#
# Return sorted list of registered macro names.
# ==========================================================================

sub list {
    return sort keys %REGISTRY;
}

# ==========================================================================
# info( $name )
#
# Return hashref with macro metadata: { name, file }
# ==========================================================================

sub info {
    my ($class, $name) = @_;
    return undef unless $REGISTRY{$name};
    return {
        name => $name,
        file => $REGISTRY{$name}{file},
    };
}

# ==========================================================================
# save( $name, $file, $source_code )
#
# Write Perl source to $file and register it as $name.
# $source_code must be valid Perl that returns a coderef when do'd.
# ==========================================================================

sub save {
    my ($class, $name, $file, $source_code) = @_;
    die "Macro::save: name is required\n" unless defined $name && length $name;
    die "Macro::save: file is required\n" unless defined $file && length $file;

    require File::Path;
    my $dir = $file;
    $dir =~ s{/[^/]*$}{};
    File::Path::make_path($dir) if length $dir && $dir ne '.';

    open my $fh, '>', $file or die "Macro::save: cannot write '$file': $!\n";
    print $fh $source_code;
    close $fh;

    return $class->load(file => $file, name => $name);
}

# ==========================================================================
# _load_file( $path )  [private]
#
# do() the file and validate it returns a coderef.
# ==========================================================================

sub _load_file {
    my ($path) = @_;

    # Support __DATA__ section: if present, inject $CODE variable
    # before the Perl code so macros can reference buffer content.
    open my $fh, '<', $path or die "Macro::load: cannot read '$path': $!\n";
    local $/;
    my $content = <$fh>;
    close $fh;

    if ($content =~ /^(.*)__DATA__\n(.*)$/s) {
        my $perl_part = $1;
        my $data_part = $2;
        # Remove trailing newline from data to avoid blank line
        chomp $data_part;
        # Inject $CODE as a heredoc at the top of the Perl part
        $content = "my \$CODE = <<'END_CODE';\n${data_part}\nEND_CODE\n" . $perl_part;
    }

    my $result = eval $content;
    if ($@) {
        die "Macro::load: syntax error in '$path': $@\n";
    }
    if (!defined $result) {
        die "Macro::load: '$path' did not return a value\n";
    }
    if (ref $result eq 'CODE') {
        return { code => $result };
    }
    if (ref $result eq 'HASH') {
        unless ($result->{run} && ref $result->{run} eq 'CODE') {
            die "Macro::load: '$path': hashref must contain a 'run' coderef\n";
        }
        return $result;
    }
    die "Macro::load: '$path' returned a " . ref($result)
      . " (expected CODE or HASH ref)\n";
}

# ==========================================================================
# _name_from_file( $path )  [private]
#
# Derive macro name from file path:
#   macros/search_highlight  -> search_highlight
#   macros/delete_line.pl    -> delete_line
#   macros/demo.macro        -> demo
#   /absolute/path/test      -> test
# ==========================================================================

sub _name_from_file {
    my ($path) = @_;
    my $name = $path;
    $name =~ s{.*/}{};              # basename
    $name =~ s{\.(pl|pm|macro|md)$}{};  # strip known extensions
    return $name;
}

1;

__END__

=head1 NAME

Gtk3::SourceEditor::Macro - Macro loader and registry

=head1 SYNOPSIS

    use Gtk3::SourceEditor::Macro;

    # Load a macro file
    Gtk3::SourceEditor::Macro->load(file => 'macros/search_highlight');

    # Load all macros from a directory
    Gtk3::SourceEditor::Macro->load(dir => 'macros/');

    # Run a loaded macro
    my $ctx = Gtk3::SourceEditor::Macro::Context->new(editor => $editor, ...);
    Gtk3::SourceEditor::Macro->run('search_highlight', $ctx, 'pattern');

    # List registered macros
    my @names = Gtk3::SourceEditor::Macro->list;

=head1 DESCRIPTION

Macro files are Perl scripts that return a coderef.  The coderef receives
a C<$ctx> (L<Gtk3::SourceEditor::Macro::Context>) object and optional
arguments.  Macros are loaded into a registry and executed by name.

=head1 MACRO FILE FORMAT

A macro file is a plain Perl script whose last expression is a coderef:

    # macros/hello
    sub {
        my ($ctx, @args) = @_;
        $ctx->echo("Hello! Args: @args");
    }

File names can be anything, with or without an extension.  The basename
(minus C<.pl>, C<.pm>, or C<.macro>) becomes the registry name.

=head1 METHODS

=head2 load( %opts )

=head2 run( $name, $ctx, @args )

=head2 list()

=head2 info( $name )

=head2 save( $name, $file, $source_code )

=cut
