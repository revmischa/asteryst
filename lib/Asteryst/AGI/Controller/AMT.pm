package Asteryst::AGI::Controller::AMT;

use Moose;
extends 'Asteryst::AGI::Controller';

use AnyEvent;
use AnyEvent::IRC::Client;

use feature 'say';
use Data::Dumper;

sub LOAD_CONTROLLER {
    my ($self, $c, %args) = @_;

    $c->log(4, "Loading AMT controller");
}

# someone is calling the space
sub inbound_entry {
    my ($self, $c) = @_;

    # caller ID
    my $cid_num = $c->session->caller_id_num || '';
    my $cid_name = $c->session->caller_id_name || '';
    
    # dialed number id
    my $dnid = $c->session->dnid || '<Unknown>';

    my @cid_display;
    if ($cid_num) {
        # obfuscate cid_num
        $cid_num = substr($cid_num, 1, 3) . '-XXX-XXXX'; # just area code
        push @cid_display, $cid_num;
    }
    push @cid_display, "<$cid_name>" if $cid_name;
    my $cid = join(' ', @cid_display);
    
    # special-case front door
    my $config = $c->config;
    if ($config{front_door_number}) {
        $cid = "the front door" if $cid_num eq $config{front_door_number};
    }
    
    $cid ||= '<Unknown>';

    $c->log(3, "Someone is calling the space!");
    my $msg = "Incoming call from \033[33m$cid\033[0m to extension \033[1;14m$dnid\033[0m";
    #my $msg = "Incoming call from $cid to extension $dnid";
    #$c->forward('/AMT/irc_notify', msg => $msg);
    $c->agi->exec('Macro', 'ring-space');
}

sub irc_notify {
    my ($self, $c, %args) = @_;

    return unless $args{msg};
    
    my $config = $c->config;
    my $toybot_user = $config->{toybot}{user}
        or die "toybot.user not defined in config";
    my $toybot_pass = $config->{toybot}{password}
        or die "toybot.password not defined in config";
    my $channel = $config->{irc}{channel}
        or die "irc.channel not defined in config";
    
    # speak through toybot
    my $ok = open(
        my $rbot_fh => "|-", # open STDIN
        "/home/toybot/rbot/bin/rbot-remote",
        -u => $toybot_user,
        -p => $toybot_pass,
        -d => $channel,
    );
    unless ($ok) {
        warn "failed to run rbot-remote: $!";
        return;
    }

    print $rbot_fh $args{msg};
    close($rbot_fh);
}

# disabled
# fork, connect to irc, let people know, exit
sub fork_irc_notify {
    my ($self, $c, %args) = @_;
    
    fork and return;

    my $config  = $c->config;
    my $server  = $config->{irc}{server} or die "irc.server not defined in config";
    my $nick    = $config->{irc}{nick} or die "irc.nick not defined in config";
    my $channel = $config->{irc}{channel} or die "irc.channel not defined in config";

    my $cv = AnyEvent->condvar;
    my $con = new AnyEvent::IRC::Client;

    $con->reg_cb(disconnect => sub { $cv->broadcast });
    $con->reg_cb(
        sent => sub {
            if ($_[2] eq 'PRIVMSG') {
                $con->disconnect('done');
            }
        },
        registered => sub {
            # this works on most networks. not so good on freenode.
            $con->send_msg('PRIVMSG', $channel, $args{msg});
        },
        debug_recv => sub {
            my (undef, $ircmsg) = @_;
            #say Dumper($ircmsg);
        },
        debug_send => sub {
            my (undef, $ircmsg) = @_;
            #say Dumper($ircmsg);
        },
    );
    $con->connect($server, 6667, { nick => $nick });
    $cv->wait;
    $con->disconnect;
    exit 0;
}

1;
