package DORC::Ops::PSGI::ChatBridgeController;

use strict;
use warnings;
use v5.10;

use Dancer2;
use Data::Section -setup;
use Net::DBus;
use Plack::Builder;
use Template;

use constant BRIDGE_NAMES => qw(dorc-xmpp);
use constant UNIT_NAMES => { map { $_ => "matterbridge\@$_.service" } BRIDGE_NAMES };

use constant ROOT_PATH => "/dorc/chatbridgecontroller";
use constant COMMAND_PATH => ROOT_PATH . "/command";
use constant LOG_PATH => ROOT_PATH . "/log";

use constant BUS => Net::DBus->session;
use constant SYSTEMD => BUS->get_service("org.freedesktop.systemd1");
use constant MANAGER => SYSTEMD->get_object("/org/freedesktop/systemd1");

use constant ACCESS_RULES => (
    allow => '127.0.0.1',
    deny => "all",
);

if (ROOT_PATH ne "/") {
    get("/", sub { redirect(ROOT_PATH, 302) });
}

get(ROOT_PATH, sub {
    my $body = render_template("root", { bridge_summary => get_bridge_summary() });
    return render_document({ title => "DORC Chat Bridge Controller", body => $body });
});

post(COMMAND_PATH, sub {
    my $command = lc(body_parameters->{command});
    my $bridge_name = body_parameters->{bridge};
    my $unit_name = UNIT_NAMES->{$bridge_name};
    my $body;

    if (! grep({ $_ eq $bridge_name} BRIDGE_NAMES)) {
        die "invalid unit specified: $unit_name";
    }

    if ($command eq "start") {
        MANAGER->StartUnit($unit_name, "replace");
        redirect(ROOT_PATH, 302);
        return;
    } elsif ($command eq "stop") {
        MANAGER->StopUnit($unit_name, "replace");
        redirect(ROOT_PATH, 302);
        return;
    } elsif ($command eq "view log") {
        return view_log($bridge_name);
    } else {
        die "invalid command specified: $command";
    }
});

sub view_log {
    my ($bridge_name) = @_;
    my $unit_name = UNIT_NAMES->{$bridge_name};
    my @lines = split("\n", `journalctl --user -u "$unit_name" | tail -n 100`);

    my $log = join("\n", reverse(@lines));

    my $body = render_template("log", { content => $log, unit => $unit_name, date_time => scalar(localtime()) });
    return render_document({ title => "Log for $unit_name", body => $body});
}

sub get_default_vars {
    return (
        COMMAND_PATH => COMMAND_PATH,
        LOG_PATH => LOG_PATH,
        ROOT_PATH => ROOT_PATH,
    );
}

sub get_data_section {
    our ($name) = @_;
    my $text = __PACKAGE__->section_data($name);

    die "could not find data section: $name" unless defined $text;
    return $$text;
}

sub render_template {
    my ($name, $vars) = @_;
    my $template_content = get_data_section($name);
    my $template = Template->new(TRIM => 1);
    my $output;

    $template->process(\$template_content, { get_default_vars(), %$vars}, \$output) or die $template->error;

    return $output;
}

sub render_document {
    my ($vars) = @_;

    return render_template("_document", $vars);
}

sub get_unit {
    my ($unit_name) = @_;
    my $path = MANAGER->GetUnit($unit_name);
    return SYSTEMD->get_object($path);
}

sub get_bridge_summary {
    my @ret;

    foreach my $bridge_name (BRIDGE_NAMES) {
        my $unit_name = UNIT_NAMES->{$bridge_name};
        my $result = { name => $bridge_name };

        eval {
            my $unit = get_unit($unit_name);
            my $active_state = $unit->ActiveState();

            if ($active_state eq "active") {
                $result->{state} = $unit->SubState();
            }
        };

        if ($@) {
            $result->{error} = "$@";
        }

        unless (exists $result->{state}) {
            $result->{state} = "not running";
        }

        push(@ret, $result);
    }

    return \@ret;
}

builder(sub {
    enable("Access", rules => [ ACCESS_RULES ]);

    __PACKAGE__->to_app;
});

__DATA__

__[_document]__
<html>
  <head>
    <title>[% title %]</title
  </head>
  <body>
    [% body %]
  </body>
</html>

__[root]__
<p>Chat bridges:</p>
[% FOREACH bridge IN bridge_summary %]
<p>
    <form action="[% COMMAND_PATH %]" method="post">
        [% bridge.name %] [% bridge.state %]
        <input type="hidden" name="bridge" value="[% bridge.name %]">
        <input type="submit" name="command" value="View Log">
        <input type="submit" name="command" value="Stop">
        <input type="submit" name="command" value="Start">
    </form>
</p>
[% END %]

__[log]__
<p><a href="[% ROOT_PATH %]">Back to controller</a></p>

[% IF content == "" %]
<p>No log info for [% unit %] at [% date_time %]</p>
[% ELSE %]
<p>Log for [% unit %] at [% date_time %]
<p><pre>[% content %]</pre></p>
[% END %]

<p><a href="[% ROOT_PATH %]">Back to controller</a></p>

__END__
