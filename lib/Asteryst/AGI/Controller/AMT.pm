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
sub ring_space {
    my ($self, $c) = @_;

    my $cid_num = $c->session->caller_id_num || '';
    my $cid_name = $c->session->caller_id_name || '';
    my $dnid = $c->session->dnid || '<Unknown>';

    # obfuscate cid_num
    $cid_num = substr($cid_num, 1, 3) . '-XXX-XXXX'; # just area code
    my $cid = $cid_num;
    $cid .= " <$cid_name>" if $cid_name;

    $c->log(3, "Someone is calling the space!");
    my $msg = "Incoming call from \033[33m$cid\033[0m to extension \033[1;14m$dnid\033[0m";
    #my $msg = "Incoming call from $cid to extension $dnid";
    $c->forward('/AMT/irc_notify', msg => $msg);
    $c->agi->exec('Dial', 'SIP/wooster&SIP/obitalk');
}

# fork, connect to irc, let people know, exit
sub irc_notify {
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
                warn "sent";
                $con->disconnect('done');
            }
        },
        registered => sub {
            $con->send_msg('NOTICE', $channel, $args{msg});
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
